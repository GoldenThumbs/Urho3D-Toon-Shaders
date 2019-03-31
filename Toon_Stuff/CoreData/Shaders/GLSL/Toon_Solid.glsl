#include "Uniforms.glsl"
#include "Samplers.glsl"
#include "Transform.glsl"
#include "ScreenPos.glsl"
#include "Lighting.glsl"
#include "Fog.glsl"

uniform sampler2D sRamp6;
uniform sampler2D sHatches7;

varying vec2 vTexCoord;
varying vec4 vScreenPos;

#ifdef NORMALMAP
	varying vec3 vBitangent;
    varying vec3 vTangent;
#endif
varying vec3 vNormal;
varying vec4 vWorldPos;

#ifdef REFLECTION
    varying vec3 vReflectionVec;
#endif

#ifdef PERPIXEL
    #ifdef SHADOW
        #ifndef GL_ES
            varying vec4 vShadowPos[NUMCASCADES];
        #else
            varying highp vec4 vShadowPos[NUMCASCADES];
        #endif
    #endif
    #ifdef SPOTLIGHT
        varying vec4 vSpotPos;
    #endif
    #ifdef POINTLIGHT
        varying vec3 vCubeMaskVec;
    #endif
#else
    varying vec3 vVertexLight;
    #if defined(LIGHTMAP) || defined(AO)
        varying vec2 vTexCoord2;
    #endif
#endif

#ifdef COMPILEPS
	uniform float cScreenScale;
#endif

void VS()
{
	mat4 modelMatrix = iModelMatrix;
    vec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
	vNormal = GetWorldNormal(modelMatrix);
	vWorldPos = vec4(worldPos, GetDepth(gl_Position));
    vScreenPos = GetScreenPos(gl_Position);
	vTexCoord = GetTexCoord(iTexCoord);
	
	#ifdef NORMALMAP
        vec4 tangent = GetWorldTangent(modelMatrix);
        vec3 bitangent = cross(tangent.xyz, vNormal) * tangent.w;
        vBitangent = bitangent.xyz;
        vTangent = tangent.xyz;
    #endif
	
	#ifdef REFLECTION
		vReflectionVec = worldPos - cCameraPos;
	#endif
	
    #ifdef PERPIXEL
        // Per-pixel forward lighting
        vec4 projWorldPos = vec4(worldPos, 1.0);

        #ifdef SHADOW
            // Shadow projection: transform from world space to shadow space
            for (int i = 0; i < NUMCASCADES; i++)
                vShadowPos[i] = GetShadowPos(i, vNormal, projWorldPos);
        #endif

        #ifdef SPOTLIGHT
            // Spotlight projection: transform from world space to projector texture coordinates
            vSpotPos = projWorldPos * cLightMatrices[0];
        #endif
    
        #ifdef POINTLIGHT
            vCubeMaskVec = (worldPos - cLightPos.xyz) * mat3(cLightMatrices[0][0].xyz, cLightMatrices[0][1].xyz, cLightMatrices[0][2].xyz);
        #endif
    #else
        // Ambient & per-vertex lighting
        #if defined(LIGHTMAP) || defined(AO)
            // If using lightmap, disregard zone ambient light
            // If using AO, calculate ambient in the PS
            vVertexLight = vec3(0.0, 0.0, 0.0);
            vTexCoord2 = iTexCoord1;
        #else
            vVertexLight = GetAmbient(GetZonePos(worldPos));
        #endif
        
        #ifdef NUMVERTEXLIGHTS
            for (int i = 0; i < NUMVERTEXLIGHTS; ++i)
                vVertexLight += GetVertexLight(i, worldPos, vNormal) * cVertexLights[i * 3].rgb;
        #endif
    #endif
}

void PS()
{
	vec2 coord = vTexCoord.xy;
	vec2 screenUV = vScreenPos.xy / vScreenPos.w;
	
	#ifdef DIFFMAP
        vec4 diffInput = texture2D(sDiffMap, coord.xy);
        #ifdef ALPHAMASK
            if (diffInput.a < 0.5)
                discard;
        #endif
        vec4 diffColor = cMatDiffColor * diffInput;
    #else
        vec4 diffColor = cMatDiffColor;
    #endif

    #ifdef VERTEXCOLOR
        diffColor *= vColor;
    #endif
    
    // Get material specular albedo
    #ifdef SPECMAP
        vec3 specColor = cMatSpecColor.rgb * texture2D(sSpecMap, coord.xy).rgb;
    #else
        vec3 specColor = cMatSpecColor.rgb;
    #endif
	
	#ifdef NORMALMAP
        mat3 tbn = mat3(vTangent.xyz, vBitangent.xyz, vNormal.xyz);
        vec3 normal = normalize(tbn * DecodeNormal(texture2D(sNormalMap, coord)));
    #else
        vec3 normal = normalize(vNormal);
    #endif
	
	#ifdef REFRACTION
		vec3 refractColor;
		#ifdef NORM_REFR
			refractColor = texture2D(sEnvMap, screenUV).rgb;
		#elif defined(GEO_NORM_REFR)
			refractColor = texture2D(sEnvMap, screenUV).rgb;
		#else
			refractColor = texture2D(sEnvMap, screenUV).rgb;
		#endif
		
	#else
	
	#endif
	
	#ifdef REFLECTION
		vec3 worldRefl = reflect(vReflectionVec, normal);
		#ifdef NORM_REFL
			
		#elif defined(GEO_NORM_REFL)
			
		#else
			
		#endif
		
	#endif
	
	// Get fog factor
    #ifdef HEIGHTFOG
        float fogFactor = GetHeightFogFactor(vWorldPos.w, vWorldPos.y);
    #else
        float fogFactor = GetFogFactor(vWorldPos.w);
    #endif

    #if defined(PERPIXEL)
		float shadeLevels = 5;
        // Per-pixel forward lighting
        vec3 lightColor;
        vec3 lightDir;
		float lightDist;
        vec3 finalColor;
		vec3 ambCol;
		
		vec3 shadingTex = texture2D(sHatches7, screenUV.xy * cScreenScale).rgb;
		
		float internalDiff = GetDiffuse(normal, vWorldPos.xyz, lightDir);
		
		#ifdef SHADOW
            internalDiff *= GetShadow(vShadowPos, vWorldPos.w);
        #endif
		
		vec4 ramp = texture2D(sRamp6, vec2(internalDiff, 0)).rgba; // Get value from color ramp
		float dA = shadingTex.b * ramp.r;
		float dB = shadingTex.g * ramp.b;
		float dC = shadingTex.r * ramp.g;
		float diff = clamp(dA+dB+dC+(1-ramp.a), 0, 1);
    
        #if defined(SPOTLIGHT)
            lightColor = vSpotPos.w > 0.0 ? texture2DProj(sLightSpotMap, vSpotPos).rgb * cLightColor.rgb : vec3(0.0, 0.0, 0.0);
        #elif defined(CUBEMASK)
            lightColor = textureCube(sLightCubeMap, vCubeMaskVec).rgb * cLightColor.rgb;
        #else
            lightColor = cLightColor.rgb;
        #endif
		
        #ifdef SPECULAR
            float internalSpec = GetSpecular(normal, cCameraPosPS - vWorldPos.xyz, lightDir, cMatSpecColor.a);
			vec4 sRamp = texture2D(sRamp6, vec2(internalSpec, 0)).rgba; // Get value from color ramp
			float sA = (1-shadingTex.r) * sRamp.r;
			float sB = (1-shadingTex.g) * sRamp.b;
			float sC = (1-shadingTex.b) * sRamp.g;
			float spec = clamp(sA+sB+sC+(1-sRamp.a), 0, 1);
			//float spec = GetSpecular(normal, cCameraPosPS - vWorldPos.xyz, lightDir, cMatSpecColor.a);
            finalColor = lightColor * diff * (diffColor.rgb + spec * specColor * cLightColor.a);
        #else
            finalColor = diff * lightColor * diffColor.rgb;
        #endif
		
		#ifdef AMBIENT
            finalColor += cAmbientColor.rgb * diffColor.rgb;
            finalColor += cMatEmissiveColor;
            gl_FragColor = vec4(GetFog(finalColor, fogFactor), diffColor.a);
        #else
			gl_FragColor = vec4(GetLitFog(finalColor, fogFactor), diffColor.a);
        #endif
		
		//gl_FragColor = vec4(GetFog(finalColor, fogFactor), diffColor.a);
		//gl_FragColor = vec4(ramp.rgb, 1);
    #elif defined(PREPASS)
        // Fill light pre-pass G-Buffer
        float specPower = cMatSpecColor.a / 255.0;

        gl_FragData[0] = vec4(normal * 0.5 + 0.5, specPower);
        gl_FragData[1] = vec4(EncodeDepth(vWorldPos.w), 0.0);
    #elif defined(DEFERRED)
        // Fill deferred G-buffer
        float specIntensity = specColor.g;
        float specPower = cMatSpecColor.a / 255.0;

        vec3 finalColor = vVertexLight * diffColor.rgb;
        #ifdef AO
            // If using AO, the vertex light ambient is black, calculate occluded ambient here
            finalColor += texture2D(sEmissiveMap, vTexCoord2).rgb * cAmbientColor.rgb * diffColor.rgb;
        #endif
		
        #ifdef LIGHTMAP
            finalColor += texture2D(sEmissiveMap, vTexCoord2).rgb * diffColor.rgb;
        #endif
        #ifdef EMISSIVEMAP
            finalColor += cMatEmissiveColor * texture2D(sEmissiveMap, coord.xy).rgb;
        #else
            finalColor += cMatEmissiveColor;
        #endif

        gl_FragData[0] = vec4(GetFog(finalColor, fogFactor), 1.0);
        gl_FragData[1] = fogFactor * vec4(diffColor.rgb, specIntensity);
        gl_FragData[2] = vec4(normal * 0.5 + 0.5, specPower);
        gl_FragData[3] = vec4(EncodeDepth(vWorldPos.w), 0.0);
    #else
        // Ambient & per-vertex lighting
		vec3 shadingTex = texture2D(sHatches7, screenUV.xy * cScreenScale).rgb;
		vec4 ramp = texture2D(sRamp6, vec2(length(vVertexLight), 0)).rgba; // Get value from color ramp
		float dA = shadingTex.b * ramp.r;
		float dB = shadingTex.g * ramp.b;
		float dC = shadingTex.r * ramp.g;
        vec3 finalColor = (vec3(1, 1, 1) * clamp(dA+dB+dC+(1-ramp.a), 0, 1)) * (diffColor.rgb + vVertexLight);
        #ifdef AO
            // If using AO, the vertex light ambient is black, calculate occluded ambient here
            finalColor += texture2D(sEmissiveMap, vTexCoord2).rgb * cAmbientColor.rgb * diffColor.rgb;
        #endif
        
        #ifdef MATERIAL
            // Add light pre-pass accumulation result
            // Lights are accumulated at half intensity. Bring back to full intensity now
            vec4 lightInput = 2.0 * texture2DProj(sLightBuffer, vScreenPos);
            vec3 lightSpecColor = lightInput.a * lightInput.rgb / max(GetIntensity(lightInput.rgb), 0.001);

            finalColor += lightInput.rgb * diffColor.rgb + lightSpecColor * specColor;
        #endif
		
        #ifdef LIGHTMAP
            finalColor += texture2D(sEmissiveMap, vTexCoord2).rgb * diffColor.rgb;
        #endif
        #ifdef EMISSIVEMAP
            finalColor += cMatEmissiveColor * texture2D(sEmissiveMap, coord.xy).rgb;
        #else
            finalColor += cMatEmissiveColor;
        #endif

        gl_FragColor = vec4(GetFog(finalColor, fogFactor), diffColor.a);
    #endif
}
