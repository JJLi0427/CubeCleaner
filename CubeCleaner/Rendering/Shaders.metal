//
//  Shaders.metal
//  CubeCleaner
//
//  Created by AI Assistant on 2023-10-01.
//

#include <metal_stdlib>
using namespace metal;

// Vertex shader input structure
struct VertexIn {
    float3 position [[attribute(0)]];
    float4 color [[attribute(1)]];
};

// Vertex shader output structure (passed to fragment shader)
struct VertexOut {
    float4 position [[position]];
    float4 color;
    float3 worldPosition;
    float3 normal;
};

// Uniform buffer structure
struct Uniforms {
    float4x4 modelViewProjectionMatrix;
};

// Vertex shader function
vertex VertexOut vertexShader(uint vertexID [[vertex_id]],
                             constant float3 *positions [[buffer(0)]],
                             constant float4 *colors [[buffer(1)]],
                             constant Uniforms &uniforms [[buffer(2)]]) {
    VertexOut out;
    
    // Get the vertex position and transform it
    float3 position = positions[vertexID];
    out.position = uniforms.modelViewProjectionMatrix * float4(position, 1.0);
    
    // Pass color to fragment shader
    out.color = colors[vertexID];
    
    // Calculate normal based on vertex ID (simplified for cubes)
    // In a real implementation, you would pass normals as vertex attributes
    uint faceIndex = vertexID / 6; // 6 vertices per face (2 triangles)
    switch (faceIndex % 6) {
        case 0: out.normal = float3(0, 0, 1); break;  // Front face
        case 1: out.normal = float3(1, 0, 0); break;  // Right face
        case 2: out.normal = float3(0, 0, -1); break; // Back face
        case 3: out.normal = float3(-1, 0, 0); break; // Left face
        case 4: out.normal = float3(0, 1, 0); break;  // Top face
        case 5: out.normal = float3(0, -1, 0); break; // Bottom face
    }
    
    // Pass world position for lighting calculations
    out.worldPosition = position;
    
    return out;
}

// Fragment shader function
fragment float4 fragmentShader(VertexOut in [[stage_in]]) {
    // Simple lighting calculation
    float3 lightDirection = normalize(float3(1, 1, 1));
    float3 normal = normalize(in.normal);
    
    // Calculate diffuse lighting
    float diffuseIntensity = max(0.0, dot(normal, lightDirection));
    
    // Add ambient lighting
    float ambientIntensity = 0.3;
    float lightIntensity = ambientIntensity + diffuseIntensity * (1.0 - ambientIntensity);
    
    // Apply lighting to color
    float4 litColor = float4(in.color.rgb * lightIntensity, in.color.a);
    
    // Add subtle edge highlighting
    float edgeFactor = 1.0 - abs(dot(normal, normalize(float3(0, 0, 1))));
    float edgeIntensity = pow(edgeFactor, 3.0) * 0.5;
    litColor.rgb = mix(litColor.rgb, float3(1, 1, 1), edgeIntensity);
    
    return litColor;
}

// Selection highlight shader
fragment float4 selectionShader(VertexOut in [[stage_in]]) {
    // Get base color from regular fragment shader
    float4 baseColor = fragmentShader(in);
    
    // Add pulsing highlight effect
    float time = fmod(float(uint(current_time() * 1000)) / 1000.0, 2.0);
    float pulse = 0.5 + 0.5 * sin(time * 3.14159);
    
    // Mix with highlight color
    float3 highlightColor = float3(1.0, 0.9, 0.4); // Golden highlight
    float highlightStrength = 0.3 * pulse;
    
    return float4(mix(baseColor.rgb, highlightColor, highlightStrength), baseColor.a);
}

// Outline shader for selected items
vertex VertexOut outlineVertexShader(uint vertexID [[vertex_id]],
                                   constant float3 *positions [[buffer(0)]],
                                   constant float4 *colors [[buffer(1)]],
                                   constant Uniforms &uniforms [[buffer(2)]]) {
    VertexOut out = vertexShader(vertexID, positions, colors, uniforms);
    
    // Scale vertex slightly to create outline
    float3 normal = normalize(out.normal);
    float3 scaledPosition = out.worldPosition + normal * 0.02; // Outline thickness
    out.position = uniforms.modelViewProjectionMatrix * float4(scaledPosition, 1.0);
    
    return out;
}

fragment float4 outlineFragmentShader(VertexOut in [[stage_in]]) {
    // Solid outline color
    return float4(1.0, 0.9, 0.0, 1.0); // Golden outline
}