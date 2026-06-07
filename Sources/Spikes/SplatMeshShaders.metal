//  SplatMeshShaders.metal
//  Vertex + fragment shaders for the USDZ mesh that is composited INTO the splat
//  world (see SplatMeshRenderer.swift). MetalSplatter's own shaders live inside the
//  package and can't be reused for triangle meshes, so this is a minimal opaque,
//  texture-lit pass.
//
//  Stereo is done WITHOUT vertex amplification (the visionOS Simulator does not
//  support it — setting maxVertexAmplificationCount > 1 aborts pipeline creation).
//  Instead the renderer draws once per eye and the vertex shader routes each draw to
//  the right texture-array layer via [[render_target_array_index]].

#include <metal_stdlib>
using namespace metal;

// Must match SplatMeshRenderer.VertexUniforms (Swift). Per-eye (per-draw) data.
struct MeshVertexUniforms {
    float4x4 modelViewProjection; // this eye's MVP
    float4x4 model;               // world transform for normals
    uint     layer;               // render-target array slice for this eye (0 or 1)
};

struct MeshVertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
    float2 uv       [[attribute(2)]];
};

struct MeshVertexOut {
    float4 position [[position]];
    uint   layer [[render_target_array_index]];
    float3 worldNormal;
    float2 uv;
};

vertex MeshVertexOut splatMeshVertex(MeshVertexIn in [[stage_in]],
                                     constant MeshVertexUniforms& u [[buffer(1)]])
{
    MeshVertexOut out;
    out.position = u.modelViewProjection * float4(in.position, 1.0);
    out.layer = u.layer;
    out.worldNormal = (u.model * float4(in.normal, 0.0)).xyz;
    out.uv = in.uv;
    return out;
}

fragment float4 splatMeshFragment(MeshVertexOut in [[stage_in]],
                                  texture2d<float> baseColor [[texture(0)]])
{
    constexpr sampler texSampler(mag_filter::linear,
                                 min_filter::linear,
                                 mip_filter::linear,
                                 address::repeat);

    float4 albedo = baseColor.sample(texSampler, in.uv);

    // Simple fixed directional light + ambient so the model reads as 3D in-world.
    float3 n = normalize(in.worldNormal);
    float3 lightDir = normalize(float3(0.4, 0.85, 0.45));
    float diffuse = max(dot(n, lightDir), 0.0);
    float3 lit = albedo.rgb * (0.4 + 0.75 * diffuse);

    return float4(lit, albedo.a);
}
