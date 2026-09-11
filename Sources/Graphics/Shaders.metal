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

// Silky, zero-ghosting 32-sample optical defocus blur
// Uses deterministic Vogel disc with screen-space interleaved gradient micro-jitter
// and continuous trilinear mipmap filtering to completely eliminate duplicate echoes.
inline float3 sampleSilkyDefocusBlur(
    texture2d<float> tex,
    sampler s,
    float2 uv,
    float radius,
    float2 cover,
    float2 uiPixel,
    float2 screenPos
) {
    float2 tuv = (uv - 0.5) * cover + 0.5;
    
    // Near hinge or minimal radius: return razor-sharp native Retina sample with zero overhead
    if (radius <= 0.25) {
        return tex.sample(s, tuv, level(0.0)).rgb;
    }
    
    // Continuous float mip LOD mapping for trilinear mip blend
    // Prevents undersampling when blur radius is large
    float baseLod = clamp(log2(max(1.0, radius * 0.22)), 0.0, 2.2);
    
    // Screen-space interleaved gradient noise rotation:
    // Rotates the sample spiral uniquely at each pixel to destroy discrete duplicate echoes
    float noise = fract(52.9829189 * fract(dot(screenPos, float2(0.06711056, 0.00583715))));
    float rot = noise * 6.28318530718;
    float cosR = cos(rot);
    float sinR = sin(rot);
    
    float3 accum = float3(0.0);
    float totalWeight = 0.0;
    
    constexpr int NUM_SAMPLES = 32;
    constexpr float GOLDEN_ANGLE = 2.39996323; // pi * (3.0 - sqrt(5.0))
    
    for (int i = 0; i < NUM_SAMPLES; i++) {
        float fi = float(i);
        float theta = fi * GOLDEN_ANGLE;
        float r = sqrt((fi + 0.5) / float(NUM_SAMPLES));
        
        // Rotate direction by per-pixel micro-jitter
        float uX = cos(theta);
        float uY = sin(theta);
        float2 dir = float2(uX * cosR - uY * sinR, uX * sinR + uY * cosR);
        
        float2 offset = dir * (r * radius * uiPixel);
        float2 sampleUV = clamp(tuv + offset, 0.001, 0.999);
        
        // Gaussian optical falloff from center of lens aperture
        float weight = exp(-2.4 * r * r);
        
        // Center samples draw fine details; outer samples blend into smooth pre-filtered mip
        float sampleLod = mix(0.0, baseLod, smoothstep(0.15, 0.85, r));
        
        accum += tex.sample(s, sampleUV, level(sampleLod)).rgb * weight;
        totalWeight += weight;
    }
    
    float3 blurred = accum / totalWeight;
    
    // Smooth transition from sharp to blurred as radius increases from zero
    float3 sharp = tex.sample(s, tuv, level(0.0)).rgb;
    return mix(sharp, blurred, smoothstep(0.1, 1.8, radius));
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
    // yScreen: 0.0 at bottom hinge, 1.0 at top of display
    // xScreen: horizontal offset from center (-0.5 to +0.5)
    float yScreen = clamp(1.0 - in.uv.y, 0.0, 1.0);
    float xScreen = in.uv.x - 0.5;
    
    // True 3D Clamshell Hinge Perspective:
    // As the MacBook lid closes (turn 0.0 -> 1.0, 90 deg -> 0 deg):
    // The panel rotates forward/downward toward the keyboard.
    // The perspective projection maps screen coordinates (xScreen, yScreen)
    // to virtual panel coordinates (x, v), where v is distance along panel from hinge (0.0 to 1.0).
    float pStrength = clamp(u.perspectiveStrength, 0.4, 2.0);
    float maxTilt = 1.15; // ~66 degrees maximum apparent tilt
    float theta = turn * maxTilt;
    float cosT = cos(theta);
    float sinT = sin(theta);
    
    // Camera eye distance in display height units
    float eye = 1.85 / pStrength;
    
    // Inverse perspective denominator:
    // D = eye * cosT - yScreen * sinT
    float denom = eye * cosT - yScreen * sinT;
    
    // If denom <= 0.005 or pixel is far above the folded lid: early-out to pure black void
    if (denom <= 0.005) {
        return float4(PURE_BLACK_VOID, 1.0);
    }
    
    // Virtual coordinate along the tilted panel from hinge (0.0 = hinge, 1.0 = top)
    float v = (yScreen * eye) / denom;
    
    // Pixel is above the top physical edge of the MacBook lid
    if (v > 1.06) {
        return float4(PURE_BLACK_VOID, 1.0);
    }
    
    // True horizontal perspective scaling:
    // Content width narrows proportionally with distance v from hinge
    float x = xScreen * (1.0 + (v * sinT) / eye);
    
    // Pixel is outside the left/right physical display boundary
    if (abs(x) > 0.55) {
        return float4(PURE_BLACK_VOID, 1.0);
    }
    
    // Normalized coordinates on the virtual display panel:
    // plane.x in [0, 1] (0 = left edge, 1 = right edge)
    // plane.y in [0, 1] (0 = top notch edge, 1 = bottom hinge)
    float2 plane;
    plane.x = x + 0.5;
    plane.y = 1.0 - v;
    
    // Distance from hinge on virtual display (0.0 = hinge, 1.0 = top)
    float fromHinge = clamp(v, 0.0, 1.0);
    
    // Progressive Defocus Blur Radius:
    // Bottom hinge (fromHinge < 0.05) is razor-sharp native Retina!
    // Progressively ramps up towards the top edge
    float hingeGradient = smoothstep(0.04, 0.90, fromHinge);
    float blurSpread = pow(hingeGradient, 1.6);
    float motion = smoothstep(0.0, 1.0, turn) * blurSpread;
    float radius = 52.0 * motion * max(0.05, u.blurStrength);
    
    // Display Boundary SDF on the virtual panel:
    // Coordinates centered on the virtual panel:
    // Top corners have Apple continuous squircle curvature; bottom corners at hinge are square.
    float2 p = float2(x * u.aspect, (1.0 - v) - 0.5);
    float2 halfBox = float2(0.5 * u.aspect, 0.5);
    float appleTopCornerRadius = 0.048 * min(1.0, u.aspect);
    float dist = sdMacBookDisplay(p, halfBox, appleTopCornerRadius);
    
    // Smooth antialiased display boundary
    float edgeWidth = max(0.001, fwidth(dist));
    float edgeMask = 1.0 - smoothstep(-0.5 * edgeWidth, 0.5 * edgeWidth, dist);
    
    if (edgeMask <= 0.0001) {
        return float4(PURE_BLACK_VOID, 1.0);
    }
    
    // Camera Housing Notch on virtual panel:
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
        
        notchBezelRim = exp(-abs(notchDist) / (edgeWidth * 2.0)) * 0.22 * (0.5 + 0.5 * sinT);
        
        float2 lensPos = float2(pNotch.x, pNotch.y + notchH * 0.05);
        float lensDist = length(lensPos);
        cameraLensDot = exp(-pow(lensDist / (0.0045 * min(1.0, u.aspect)), 2.0)) * 0.25;
    }
    
    float activeScreenMask = edgeMask * (1.0 - inNotchMask);
    
    // Sample texture with silky, zero-duplicate optical defocus blur
    float3 color = sampleSilkyDefocusBlur(tex, s, plane, radius, u.cover, uiPixel, in.position.xy);
    
    // Subtle physical glass rim highlight along the display perimeter
    float rimHighlight = exp(-abs(dist) / (edgeWidth * 2.5)) * sinT * 0.15;
    color += float3(0.75, 0.82, 0.90) * rimHighlight;
    
    // Specular light reflection band near the upper fold horizon
    float foldReflection = exp(-pow((fromHinge - 0.75) / 0.25, 2.0)) * sinT;
    color += float3(0.85, 0.88, 0.92) * foldReflection * (0.025 * u.reflectionIntensity);
    
    // Physical glass attenuation as surface tilts away
    color *= (1.0 - 0.15 * sinT * pow(fromHinge, 1.4));
    
    // Dark Void Horizon Falloff: receding far top slips smoothly into darkness
    float fadeStart = 0.25;
    float fadeDistance = clamp((fromHinge - fadeStart) / (1.0 - fadeStart), 0.0, 1.0);
    float voidAmount = pow(turn, 1.1) * pow(fadeDistance, 1.3) * max(0.2, u.darkVoidIntensity);
    color *= (1.0 - 0.88 * voidAmount);
    
    // Final closure into deep black as lid shuts completely (turn > 0.94)
    float finalClose = 1.0 - smoothstep(0.94, 1.0, turn);
    color *= finalClose;
    
    // Base display color with notch cutout
    float3 screenColor = mix(PURE_BLACK_VOID, color, activeScreenMask * finalClose);
    
    // Add camera lens and notch bezel rim onto the physical housing
    if (u.hasNotch > 0.5) {
        float3 lensColor = float3(0.12, 0.25, 0.45) * cameraLensDot * (0.3 + 0.7 * cosT);
        float3 notchRimColor = float3(0.70, 0.75, 0.82) * notchBezelRim;
        screenColor += (lensColor + notchRimColor) * edgeMask * finalClose;
    }
    
    return float4(screenColor, 1.0);
}
