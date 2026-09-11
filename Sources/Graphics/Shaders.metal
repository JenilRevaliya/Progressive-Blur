#include <metal_stdlib>
using namespace metal;

constant float MAX_TILT = 0.84106867; // acos(1.0 / 1.5)
constant float3 PURE_BLACK_VOID = float3(0.0, 0.0, 0.0); // True pitch black OLED void
constant int NUM_BLUR_SAMPLES = 16; // Optimized 16-sample Fermat golden spiral disc for locked 60/120 FPS
constant float GOLDEN_ANGLE = 2.39996323; // pi * (3.0 - sqrt(5.0))

struct Uniforms {
    float2 imageSize;
    float2 cover;
    float aspect;
    float turn;                    // 0.0 = fully open (90°), 1.0 = fully closed (0°)
    float blurStrength;
    float perspectiveStrength;
    float darkVoidIntensity;
    float reflectionIntensity;
    float hasNotch;                // 1.0 = notch visible, 0.0 = disabled
    float padding;
    float2 notchSize;              // (normalized width, normalized height)
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut foldVertex(uint vid [[vertex_id]]) {
    const float2 positions[6] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2(-1.0,  1.0),
        float2( 1.0, -1.0),
        float2( 1.0,  1.0)
    };
    
    VertexOut out;
    float2 pos = positions[vid];
    out.position = float4(pos, 0.0, 1.0);
    // UV origin: (0,0) at top-left, (1,1) at bottom-right
    out.uv = float2(pos.x * 0.5 + 0.5, 0.5 - pos.y * 0.5);
    return out;
}

// Exact Signed Distance Field for Apple MacBook Display:
// Top corners have signature Apple rounded curvature; bottom corners (at hinge) are square.
inline float sdMacBookDisplay(float2 p, float2 halfSize, float topRadius) {
    // p centered at (0,0); top is p.y < 0, bottom (hinge) is p.y > 0
    float r = (p.y < 0.0) ? topRadius : 0.0;
    float2 q = abs(p) - halfSize + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// Exact Signed Distance Field for Apple MacBook Camera Housing Notch:
// Centered at top of display, cuts down with rounded bottom corners and subtle shoulders.
inline float sdMacBookNotch(float2 pNotch, float2 notchHalfSize, float bottomRadius) {
    float2 q = abs(pNotch) - notchHalfSize + bottomRadius;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - bottomRadius;
}

// Grain-free, creamy 16-sample optical defocus blur
// Ultra-fast M1 bandwidth: 16 samples + continuous trilinear mip blend = zero noise, zero grain
inline float3 sampleCreamyBokehBlur(
    texture2d<float> tex,
    sampler s,
    float2 uv,
    float radius,
    float2 cover,
    float2 uiPixel
) {
    float2 tuv = (uv - 0.5) * cover + 0.5;
    
    // Near hinge or small radius: return razor-sharp native Retina sample with zero loop overhead
    if (radius <= 0.6) {
        return tex.sample(s, tuv, level(0.0)).rgb;
    }
    
    // Continuous float mip LOD mapping for silky trilinear mip-blend
    float baseLod = clamp(log2(1.0 + radius * 0.25), 0.0, 2.5);
    
    float3 accum = float3(0.0);
    float totalWeight = 0.0;
    
    // Deterministic area-proportional Fermat golden-spiral disc
    for (int i = 0; i < NUM_BLUR_SAMPLES; i++) {
        float fi = float(i);
        float theta = fi * GOLDEN_ANGLE;
        float r = sqrt((fi + 0.5) / float(NUM_BLUR_SAMPLES));
        
        float2 dir = float2(cos(theta), sin(theta));
        float2 offset = dir * (r * radius * uiPixel);
        float2 sampleUV = clamp(tuv + offset, 0.0, 1.0);
        
        // Optical Gaussian falloff from center of lens aperture
        float weight = exp(-2.0 * r * r);
        
        // Outer samples transition smoothly into the filtered mip level
        float sampleLod = mix(0.0, baseLod, smoothstep(0.2, 0.8, r));
        
        accum += tex.sample(s, sampleUV, level(sampleLod)).rgb * weight;
        totalWeight += weight;
    }
    
    float3 blurred = accum / totalWeight;
    
    // Smooth onset of defocus
    float3 sharp = tex.sample(s, tuv, level(0.0)).rgb;
    return mix(sharp, blurred, smoothstep(0.6, 2.2, radius));
}

fragment float4 foldFragment(
    VertexOut in [[stage_in]],
    texture2d<float> tex [[texture(0)]],
    sampler s [[sampler(0)]],
    constant Uniforms &u [[buffer(0)]]
) {
    float turn = clamp(u.turn, 0.0, 1.0);
    
    // Fully open (turn <= 0.0001): 1-cycle direct Retina pass-through
    if (turn <= 0.0001) {
        float2 tuv = (in.uv - 0.5) * u.cover + 0.5;
        return float4(tex.sample(s, tuv, level(0.0)).rgb, 1.0);
    }
    
    float2 uiPixel = 1.0 / max(float2(1.0), u.imageSize);
    
    // Coordinates on physical display:
    // yScreen: 0.0 at bottom hinge, 1.0 at top notch
    // xScreen: horizontal offset from center (-0.5 to +0.5)
    float yScreen = clamp(1.0 - in.uv.y, 0.0, 1.0);
    float xScreen = in.uv.x - 0.5;
    
    // Proportional Opposite Hinge Perspective Angle:
    // Physically, as the MacBook lid rotates downward from 90° towards 0° (turn 0.0 -> 1.0),
    // the virtual inside screen tilts back by an angle phi strictly proportional to (90° - hingeAngle).
    // Max physical tilt is capped at ~85° (1.4835 rad) to prevent singularity at 90°.
    float maxTilt = 1.4835;
    float pStrength = max(0.2, u.perspectiveStrength);
    float bend = clamp(turn * maxTilt * pStrength, 0.0, 1.52);
    float cosine = cos(bend);
    float sine = sin(bend);
    
    // Camera distance in screen-height units
    float eye = 1.35;
    
    // 3D Inverse Frustum Projection:
    // Maps physical screen pixel (xScreen, yScreen) to virtual screen coordinate (x, v).
    // Where v is distance from hinge along virtual surface (0.0 = hinge, 1.0 = top).
    float denom = eye * cosine - yScreen * sine;
    
    // Pixel is above the vanishing horizon -> pitch black void
    if (denom <= 0.005) {
        return float4(PURE_BLACK_VOID, 1.0);
    }
    
    // Virtual surface coordinate v along tilted panel
    float v = (yScreen * eye) / denom;
    
    // Pixel is above physical top of the MacBook lid -> pitch black void
    if (v > 1.05) {
        return float4(PURE_BLACK_VOID, 1.0);
    }
    
    // Decoupled horizontal trapezoid perspective:
    // Narrower width at the farther (upper) edge, anchored to 100% full width at hinge
    float x = xScreen * (1.0 + (v * sine * (0.85 * pStrength)) / eye);
    
    // Pixel is outside the left/right physical bezel -> pitch black void
    if (abs(x) > 0.54) {
        return float4(PURE_BLACK_VOID, 1.0);
    }
    
    // Normalized virtual plane texture UV coordinates
    float2 plane;
    plane.x = x + 0.5;
    plane.y = 1.0 - v;
    
    // Distance from hinge on virtual display:
    // 0.0 is hinge (sharp, unblurred, full width)
    // 1.0 is top (heavy defocus, narrower width, receding in 3D depth)
    float fromHinge = clamp(v, 0.0, 1.0);
    
    // Spatial Contrast:
    // Nearer edge (fromHinge < 0.15) MUST be razor-sharp and non-blur!
    // Farther edge (fromHinge -> 1.0) ramps up into heavy defocus.
    float hingeGradient = smoothstep(0.08, 0.92, fromHinge);
    float blurSpread = pow(hingeGradient, 2.0); // Steep acceleration towards the top
    float motion = smoothstep(0.0, 1.0, turn) * blurSpread;
    float radius = 68.0 * motion * max(0.05, u.blurStrength);
    
    // Apple-Style Screen Geometry SDF:
    // Centered coordinates with aspect ratio scaling
    float2 p = float2(x * u.aspect, (1.0 - v) - 0.5);
    float2 halfBox = float2(0.5 * u.aspect, 0.5);
    
    // Signature Apple Display Corner Radius for top corners:
    // ~44pt radius on a Retina display (~0.055 of screen height)
    float appleTopCornerRadius = 0.054 * min(1.0, u.aspect);
    
    // Distance to display boundary (negative inside, positive outside)
    float dist = sdMacBookDisplay(p, halfBox, appleTopCornerRadius);
    
    // Exact sub-pixel edge antialiasing across 1 screen pixel
    float edgeWidth = max(0.0008, fwidth(dist));
    float edgeMask = 1.0 - smoothstep(-0.5 * edgeWidth, 0.5 * edgeWidth, dist);
    
    // Early exit outside display boundary -> pure pitch black void
    if (edgeMask <= 0.0001) {
        return float4(PURE_BLACK_VOID, 1.0);
    }
    
    // Camera Housing Notch for newer MacBook models:
    float inNotchMask = 0.0;
    float notchBezelRim = 0.0;
    float cameraLensDot = 0.0;
    
    if (u.hasNotch > 0.5) {
        float notchHalfW = (u.notchSize.x * 0.5) * u.aspect;
        float notchH = u.notchSize.y;
        float notchRadius = 0.012 * min(1.0, u.aspect);
        
        // pNotch: centered horizontally, extends downward from top edge (y = -0.5)
        float2 pNotch = float2(p.x, p.y - (-0.5 + notchH * 0.5));
        float2 notchHalfBox = float2(notchHalfW, notchH * 0.5);
        
        float notchDist = sdMacBookNotch(pNotch, notchHalfBox, notchRadius);
        inNotchMask = 1.0 - smoothstep(-0.5 * edgeWidth, 0.5 * edgeWidth, notchDist);
        
        // Physical rim highlight around notch outline
        notchBezelRim = exp(-abs(notchDist) / (edgeWidth * 2.0)) * 0.22 * (0.5 + 0.5 * sine);
        
        // Camera lens sensor reflection inside the notch
        float2 lensPos = float2(pNotch.x, pNotch.y + notchH * 0.05);
        float lensDist = length(lensPos);
        cameraLensDot = exp(-pow(lensDist / (0.0045 * min(1.0, u.aspect)), 2.0)) * 0.25;
    }
    
    // Active display area (screen minus camera housing notch)
    float activeScreenMask = edgeMask * (1.0 - inNotchMask);
    
    // Sample texture with grain-free, creamy optical defocus blur
    float3 color = sampleCreamyBokehBlur(tex, s, plane, radius, u.cover, uiPixel);
    
    // Subtle physical glass rim highlight along the physical perimeter
    float rimDistance = abs(dist);
    float rimHighlight = exp(-rimDistance / (edgeWidth * 2.5)) * sine * 0.15;
    color += float3(0.75, 0.82, 0.90) * rimHighlight;
    
    // Specular light reflection band near the upper fold horizon
    float foldReflection = exp(-pow((fromHinge - 0.70) / 0.28, 2.0)) * sine;
    color += float3(0.85, 0.88, 0.92) * foldReflection * (0.025 * u.reflectionIntensity);
    
    // Physical glass attenuation as surface tilts away
    color *= (1.0 - 0.18 * sine * pow(fromHinge, 1.4));
    
    // Dark Void Horizon Falloff: receding far top slips smoothly into darkness
    float fadeStart = 0.20;
    float fadeDistance = clamp((fromHinge - fadeStart) / (1.0 - fadeStart), 0.0, 1.0);
    float voidAmount = pow(turn, 1.1) * pow(fadeDistance, 1.3) * max(0.2, u.darkVoidIntensity);
    color *= (1.0 - 0.88 * voidAmount);
    
    // Final closure into deep black as lid shuts completely (turn > 0.92)
    float finalClose = 1.0 - smoothstep(0.92, 1.0, turn);
    color *= finalClose;
    
    // Base display color with notch cutout
    float3 screenColor = mix(PURE_BLACK_VOID, color, activeScreenMask * finalClose);
    
    // Add camera lens and notch bezel rim onto the physical housing
    if (u.hasNotch > 0.5) {
        float3 lensColor = float3(0.12, 0.25, 0.45) * cameraLensDot * (0.3 + 0.7 * cosine);
        float3 notchRimColor = float3(0.70, 0.75, 0.82) * notchBezelRim;
        screenColor += (lensColor + notchRimColor) * edgeMask * finalClose;
    }
    
    return float4(screenColor, 1.0);
}
