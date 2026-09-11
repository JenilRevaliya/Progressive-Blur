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
    float showHingeFrame;          // 0.0 = iPhone Duo full-screen mode (default), 1.0 = hardware bezel & notch
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
    
    // =========================================================================
    // MODE A: Authentic iPhone Duo Progressive Blur (Default, showHingeFrame < 0.5)
    // Full-screen seamless progressive blur anchored at the bottom hinge line.
    // As the lid closes, the top side tilts away in perspective, blurs with Vogel disc,
    // and darkens gradually into deep shadow.
    // =========================================================================
    if (u.showHingeFrame < 0.5) {
        // Hinge is anchored at the bottom edge of the display (in.uv.y = 1.0)
        float fromHinge = clamp(1.0 - in.uv.y, 0.0, 1.0);
        
        float bend = turn * MAX_TILT;
        float cosine = cos(bend);
        float sine = sin(bend);
        
        // Stable perspective projection matching iPhone Duo foldable geometry
        float invAspect = 1.0 / max(0.1, u.aspect);
        float eye = (3.2 * max(invAspect, 1.0)) / max(0.2, u.perspectiveStrength);
        float depth = fromHinge * (0.80 * invAspect) * sine;
        float perspective = eye / max(0.01, (eye - depth));
        
        float2 plane;
        plane.y = 1.0 - fromHinge * cosine * perspective;
        plane.x = 0.5 + (in.uv.x - 0.5) * perspective;
        
        // Progressive Defocus Blur:
        // Hinge line (fromHinge = 0.0) stays razor-sharp native Retina.
        // Defocus blur spreads progressively towards the top edge.
        float blurSpread = pow(smoothstep(0.0, 0.85, fromHinge), 1.25);
        float motion = smoothstep(0.0, 1.0, turn) * mix(0.15, 1.0, blurSpread);
        float radius = 56.0 * motion * max(0.05, u.blurStrength);
        
        // Lateral perspective margin softness
        float softness = fwidth(in.uv.x) * 2.0 + radius * 0.0015;
        float sideMask = 1.0 - smoothstep(0.5 - softness, 0.5 + softness, abs(plane.x - 0.5));
        float topMask = (plane.y >= -0.05) ? (1.0 - smoothstep(-0.05, 0.02, -plane.y)) : 0.0;
        float mask = clamp(sideMask * topMask, 0.0, 1.0);
        
        // Sample texture using 32-sample Vogel disc continuous matte blur
        float3 color = sampleSilkyDefocusBlur(tex, s, plane, radius, u.cover, uiPixel, in.position.xy);
        
        // Gradual Top-Edge Depth Darkening:
        // Content darkens progressively alongside blur:
        // Hinge line remains 100% bright and clear Retina,
        // while the receding top edge falls smoothly and progressively into deep shadow.
        float topDarkGradient = pow(fromHinge, 1.25);
        float foldDarkProgress = pow(turn, 0.80);
        float darkFalloff = topDarkGradient * foldDarkProgress * clamp(u.darkVoidIntensity, 0.3, 2.5);
        float brightness = clamp(1.0 - 0.95 * darkFalloff, 0.0, 1.0);
        color *= brightness;
        
        // Subtle optical glass attenuation and specular sheen
        float glass = sine * pow(fromHinge, 1.5);
        color *= (1.0 - 0.18 * glass);
        float reflection = exp(-pow((fromHinge - 0.65) / 0.35, 2.0)) * sine;
        color += float3(0.82, 0.85, 0.88) * reflection * (0.025 * u.reflectionIntensity);
        
        // Final smooth closure into black void as lid completely shuts (turn > 0.92)
        float finalClose = 1.0 - smoothstep(0.92, 1.0, turn);
        color *= finalClose;
        
        return float4(mix(PURE_BLACK_VOID, color, mask * finalClose), 1.0);
    }
    
    // =========================================================================
    // MODE B: Hardware Clamshell Simulation (Optional, showHingeFrame >= 0.5)
    // Simulates MacBook unibody display bezel, squircle top corners,
    // and Liquid Retina camera housing notch cutout.
    // =========================================================================
    float yScreen = clamp(1.0 - in.uv.y, 0.0, 1.0);
    float xScreen = in.uv.x - 0.5;
    
    float pStrength = clamp(u.perspectiveStrength, 0.4, 2.0);
    float maxTilt = 1.15;
    float theta = turn * maxTilt;
    float cosT = cos(theta);
    float sinT = sin(theta);
    
    float eye = 1.85 / pStrength;
    float denom = eye * cosT - yScreen * sinT;
    if (denom <= 0.005) {
        return float4(PURE_BLACK_VOID, 1.0);
    }
    
    float v = (yScreen * eye) / denom;
    if (v > 1.06) {
        return float4(PURE_BLACK_VOID, 1.0);
    }
    
    float x = xScreen * (1.0 + (v * sinT) / eye);
    if (abs(x) > 0.55) {
        return float4(PURE_BLACK_VOID, 1.0);
    }
    
    float2 plane;
    plane.x = x + 0.5;
    plane.y = 1.0 - v;
    float fromHinge = clamp(v, 0.0, 1.0);
    
    float hingeGradient = smoothstep(0.04, 0.90, fromHinge);
    float blurSpread = pow(hingeGradient, 1.6);
    float motion = smoothstep(0.0, 1.0, turn) * blurSpread;
    float radius = 52.0 * motion * max(0.05, u.blurStrength);
    
    float2 p = float2(x * u.aspect, (1.0 - v) - 0.5);
    float2 halfBox = float2(0.5 * u.aspect, 0.5);
    float appleTopCornerRadius = 0.048 * min(1.0, u.aspect);
    float dist = sdMacBookDisplay(p, halfBox, appleTopCornerRadius);
    
    float edgeWidth = max(0.001, fwidth(dist));
    float edgeMask = 1.0 - smoothstep(-0.5 * edgeWidth, 0.5 * edgeWidth, dist);
    if (edgeMask <= 0.0001) {
        return float4(PURE_BLACK_VOID, 1.0);
    }
    
    float inNotchMask = 0.0;
    float notchBezelRim = 0.0;
    float cameraLensDot = 0.0;
    
    if (u.hasNotch > 0.5) {
        float notchHalfW = (u.notchSize.x * 0.5) * u.aspect;
        float notchH = u.notchSize.y;
        float notchRadius = 0.012 * min(1.0, u.aspect);
        
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
    float3 color = sampleSilkyDefocusBlur(tex, s, plane, radius, u.cover, uiPixel, in.position.xy);
    
    // Gradual top-edge depth darkening:
    float topDarkGradient = pow(fromHinge, 1.25);
    float foldDarkProgress = pow(turn, 0.80);
    float darkFalloff = topDarkGradient * foldDarkProgress * clamp(u.darkVoidIntensity, 0.3, 2.5);
    float brightness = clamp(1.0 - 0.95 * darkFalloff, 0.0, 1.0);
    color *= brightness;
    
    float rimHighlight = exp(-abs(dist) / (edgeWidth * 2.5)) * sinT * 0.15;
    color += float3(0.75, 0.82, 0.90) * rimHighlight;
    
    float foldReflection = exp(-pow((fromHinge - 0.75) / 0.25, 2.0)) * sinT;
    color += float3(0.85, 0.88, 0.92) * foldReflection * (0.025 * u.reflectionIntensity);
    color *= (1.0 - 0.15 * sinT * pow(fromHinge, 1.4));
    
    float finalClose = 1.0 - smoothstep(0.94, 1.0, turn);
    color *= finalClose;
    
    float3 screenColor = mix(PURE_BLACK_VOID, color, activeScreenMask * finalClose);
    if (u.hasNotch > 0.5) {
        float3 lensColor = float3(0.12, 0.25, 0.45) * cameraLensDot * (0.3 + 0.7 * cosT);
        float3 notchRimColor = float3(0.70, 0.75, 0.82) * notchBezelRim;
        screenColor += (lensColor + notchRimColor) * edgeMask * finalClose;
    }
    
    return float4(screenColor, 1.0);
}
