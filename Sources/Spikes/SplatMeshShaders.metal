//  SplatMeshShaders.metal
//  Vertex + fragment shaders for the USDZ mesh that is composited INTO the splat
//  world (see SplatMeshRenderer.swift). MetalSplatter's own shaders live inside the
//  package and can't be reused for triangle meshes, so this is a minimal opaque,
//  texture-lit pass. Stereo is handled with vertex amplification: the renderer binds
//  one MVP per eye and the GPU picks the right one via [[amplification_id]].

#include <metal_stdlib>
using namespace metal;

// Must match SplatMeshRenderer.VertexUniforms (Swift). float4x4[2] then float4x4.
struct MeshVertexUniforms {
    float4x4 modelViewProjection[2]; // per amplified view (left/right eye)
    float4x4 model;                  // world transform for normals (same both eyes)
};

struct MeshVertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
    float2 uv       [[attribute(2)]];
};

struct MeshVertexOut {
    float4 position [[position]];
    float3 worldNormal;
    float2 uv;
};

vertex MeshVertexOut splatMeshVertex(MeshVertexIn in [[stage_in]],
                                     constant MeshVertexUniforms& u [[buffer(1)]],
                                     ushort ampID [[amplification_id]])
{
    MeshVertexOut out;
    out.position = u.modelViewProjection[ampID] * float4(in.position, 1.0);
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
