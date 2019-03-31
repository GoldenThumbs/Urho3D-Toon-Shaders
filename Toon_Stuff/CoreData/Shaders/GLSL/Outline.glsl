#include "Uniforms.glsl"
#include "Samplers.glsl"
#include "Transform.glsl"
#include "ScreenPos.glsl"
#include "Lighting.glsl"

varying vec4 vScreenPos;
varying float vCamNear;
varying float vCamFar;

#ifdef COMPILEVS

void VS()
{
    mat4 modelMatrix = iModelMatrix;
    vec3 worldPos = GetWorldPos(modelMatrix);
    gl_Position = GetClipPos(worldPos);
    vScreenPos = GetScreenPos(gl_Position);
	vCamNear = cNearClip;
	vCamFar = cFarClip;
}

#endif


#ifdef COMPILEPS
uniform vec2 cScreenSize;

float linearizeDepth(float depth)
    {
        float nearToFarDistance = vCamFar - vCamNear;
        return (2.0 * vCamNear) / (vCamFar + vCamNear - depth * nearToFarDistance);
        //http://www.ozone3d.net/blogs/lab/20090206/how-to-linearize-the-depth-value/ 
        //http://www.geeks3d.com/20091216/geexlab-how-to-visualize-the-depth-buffer-in-glsl/
    } 

vec3 viewSpacePositionFromDepth(in float depth, vec2 ndc) //PositionFromDepth_DarkPhoton(): https://www.opengl.org/discussion_boards/showthread.php/176040-Render-depth-to-texture-issue
{
    vec3 eye;             // Reconstructed EYE-space position
    
    float top = 0.05463024898; //per 1 radianm FoV & distance of 0.1
        
    float right = top * cScreenSize.x / cScreenSize.y;
    
    eye.z = linearizeDepth(depth);
    eye.x = (-ndc.x * eye.z) * right/vCamNear;
    eye.y = (-ndc.y * eye.z) * top/vCamNear;
    
    return eye;
}
	
vec3 getNormal(vec2 uv, vec2 ndc, float baseDepth)
{
	vec2 offset1 = vec2(0, 0.001);
    vec2 offset2 = vec2(0.001, 0);
	
    float depth1 = DecodeDepth(texture2D(sEmissiveMap, uv + offset1).rgb);
    float depth2 = DecodeDepth(texture2D(sEmissiveMap, uv + offset2).rgb);
	
	vec3 p  = viewSpacePositionFromDepth(baseDepth, ndc);
	vec3 p1 = viewSpacePositionFromDepth(depth1, ndc + offset1);
    vec3 p2 = viewSpacePositionFromDepth(depth2, ndc + offset2);
	
	vec3 v1 = (p1-p);
    vec3 v2 = (p2-p);
	
	vec3 normal = cross(v1, v2);
    normal.z = -normal.z;
	return normalize(normal) * 0.5 + 0.5;
}

void compareDepth(inout float depthOutline, inout float normalOutline, float baseDepth, vec3 baseNormal, vec2 uv, vec2 ndc, vec2 offset)
{
	vec2 inParam = vec2(1/cScreenSize.x, 1/cScreenSize.y);
    float neighborDepth = DecodeDepth(texture2D(sEmissiveMap, uv + inParam * offset).rgb);
	vec3 neighborNormal = getNormal(uv, ndc, neighborDepth);
    float depthDifference = baseDepth - neighborDepth;
    depthOutline = depthOutline + depthDifference;
	
	vec3 normalDifference = baseNormal - neighborNormal;
	float fNormalDifference = normalDifference.r + normalDifference.g + normalDifference.b;
	normalOutline = normalOutline + fNormalDifference;
}

void PS()
{
	int lineScale = 2;
	float normalMult = 2;
	float normalBias = 0.3;
	float depthMult = 28;
	float depthBias = 0.25;
	vec3 outlineColor = vec3(0, 0, 0);
	
	vec2 screenuv = vScreenPos.xy / vScreenPos.w;
	
	vec2 ndc;
	ndc.x = dFdx(screenuv.x);
    ndc.y = dFdy(screenuv.y);
	
	vec3 irgb = texture2D(sEnvMap, screenuv).rgb;
    float depth = DecodeDepth(texture2D(sEmissiveMap, screenuv).rgb);
	vec3 baseNorm;
    vec3 normal = getNormal(screenuv, ndc, depth);
	
	float depthDifference = 0;
	float normalDifference = 0;
	
	for (int x = -lineScale; x <= lineScale; ++x)
	{
        for (int y = -lineScale; y <= lineScale; ++y)
		{
			compareDepth(depthDifference, normalDifference, depth, normal, screenuv, ndc, vec2(float(x), float(y)));
	    }
    }

	
	depthDifference = depthDifference * depthMult;
	depthDifference = clamp(depthDifference, 0, 1);
	depthDifference = step(0.2, pow(depthDifference, depthBias));
	
	normalDifference = normalDifference * normalMult;
	normalDifference = clamp(normalDifference, 0, 1);
	normalDifference = step(0.2, pow(normalDifference, normalBias));
	
	float outline = clamp(depthDifference+normalDifference, 0, 1);

	vec3 finalColor = mix(irgb, outlineColor, outline);
	
	gl_FragColor = vec4(finalColor, 1);
	//gl_FragColor = vec4(outline, outline, outline, 1);
	//gl_FragColor = vec4(depthDifference, depthDifference, depthDifference, 1);
	//gl_FragColor = vec4(normalDifference, normalDifference, normalDifference, 1);
}

#endif