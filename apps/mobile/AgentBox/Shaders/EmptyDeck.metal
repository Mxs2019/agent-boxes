#include <metal_stdlib>
using namespace metal;

static float softCircle(float2 point, float2 center, float radius, float softness) {
    return 1.0 - smoothstep(radius - softness, radius + softness, distance(point, center));
}

[[ stitchable ]] float2 emptyDeckRipple(
    float2 position,
    float2 size,
    float time,
    float2 touch,
    float touchIntensity
) {
    float2 safeSize = max(size, float2(1.0));
    float2 uv = position / safeSize;
    float2 delta = uv - touch;
    delta.x *= safeSize.x / safeSize.y;

    float touchDistance = length(delta);
    float2 direction = delta / max(touchDistance, 0.0001);
    float2 tangent = float2(-direction.y, direction.x);
    float intensity = saturate(touchIntensity);
    float envelope = exp(
        -touchDistance * touchDistance * mix(34.0, 16.0, intensity)
    );
    float wave = sin(touchDistance * mix(58.0, 82.0, intensity) - time * 7.0);
    float pulse = sin(touchDistance * 28.0 - time * 3.8);
    float strength = smoothstep(0.02, 0.96, intensity);

    float2 displacement = direction * (
        wave * mix(3.0, 13.0, intensity)
        - envelope * mix(2.0, 9.0, intensity)
    );
    displacement += tangent * pulse * mix(1.0, 5.0, intensity);
    displacement *= envelope * strength;

    return clamp(position + displacement, float2(0.5), safeSize - float2(0.5));
}

[[ stitchable ]] half4 emptyDeckField(
    float2 position,
    half4 source,
    float2 size,
    float time,
    float2 touch,
    half4 accent,
    float darkMode,
    float touchIntensity
) {
    float2 safeSize = max(size, float2(1.0));
    float2 uv = position / safeSize;
    float2 point = uv - 0.5;
    point.x *= safeSize.x / safeSize.y;

    float2 touchPoint = touch - 0.5;
    touchPoint.x *= safeSize.x / safeSize.y;

    float slowTime = time * 0.24;
    float2 drift = float2(sin(slowTime) * 0.16, cos(slowTime * 0.83) * 0.13);
    float glow = softCircle(point, drift, 0.2, 0.3);

    float touchDistance = distance(point, touchPoint);
    float intensity = saturate(touchIntensity);
    float ripple = sin(touchDistance * 58.0 - time * 6.0);
    ripple *= exp(-touchDistance * 4.6);
    ripple *= mix(0.04, 0.9, intensity);
    float touchGlow = softCircle(point, touchPoint, 0.08, 0.2) * intensity;

    half3 accentColor = accent.rgb;
    half luminance = dot(accentColor, half3(0.2126, 0.7152, 0.0722));
    half accentLimit = mix(
        half(1.0),
        half(0.55),
        half(smoothstep(0.86, 1.0, float(luminance)))
    );

    half3 liftedAccent = mix(accentColor, half3(1.0), half(0.26));
    half tintStrength = half(
        glow * 0.045
        + touchGlow * 0.14
        + max(ripple, 0.0) * 0.16
    ) * accentLimit;
    half3 color = mix(source.rgb, liftedAccent, saturate(tintStrength));
    color += half3(max(ripple, 0.0) * mix(0.035, 0.055, darkMode));
    color -= half3(max(-ripple, 0.0) * 0.025);
    color *= half(mix(1.0, 0.94, darkMode));

    return half4(color, source.a);
}

[[ stitchable ]] float2 snoozeCardFold(
    float2 position,
    float2 size,
    float progress
) {
    float2 safeSize = max(size, float2(1.0));
    float amount = smoothstep(0.0, 1.0, progress);
    float2 sourcePosition = position;
    float2 sourceUV = sourcePosition / safeSize;

    float foldEnvelope = sin(amount * M_PI_F);
    float horizontalFold = sin(sourceUV.y * M_PI_F * 8.0);
    float verticalFold = sin(sourceUV.x * M_PI_F * 2.0 + amount * M_PI_F);
    sourcePosition.x += horizontalFold * safeSize.x * 0.07 * foldEnvelope;
    sourcePosition.y += verticalFold * safeSize.y * 0.02 * foldEnvelope;

    return sourcePosition;
}

[[ stitchable ]] half4 snoozeCardFoldLight(
    float2 position,
    half4 source,
    float2 size,
    float progress
) {
    float2 safeSize = max(size, float2(1.0));
    float2 uv = position / safeSize;
    float amount = smoothstep(0.0, 1.0, progress);
    float fold = sin((uv.y * 8.0 + amount * 0.8) * M_PI_F);
    float ridge = pow(abs(fold), 5.0);
    float foldEnvelope = sin(amount * M_PI_F);
    half light = half(1.0 + fold * 0.22 * foldEnvelope - ridge * 0.28 * foldEnvelope);
    half fade = half(1.0 - smoothstep(0.84, 1.0, amount));

    return half4(source.rgb * light, source.a * fade);
}
