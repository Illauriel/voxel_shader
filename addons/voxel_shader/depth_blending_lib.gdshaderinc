uniform bool u_depth_blending_atlas = true;
uniform bool u_depth_blending_layer = true;
uniform float u_top_blend_strength : hint_range(0.001, 0.999, 0.01) = 0.5;
uniform float u_side_blend_strength : hint_range(0.001, 0.999, 0.01) = 0.5;
uniform float u_layer_blend_strength : hint_range(0.001, 0.999, 0.01) = 0.5;

// Returns weights modified according to material's bump map. Amount controls strength of this effect.
// This implementation is different than one found in HTerrain shader
// Function comes in 3 versions for diff number of inputs
vec4 get_depth_blended_weights4(vec4 weights, vec4 heights, float amount) {
	vec4 h = weights + heights * weights;
	float max_h = max(max(max(h.r, h.g), h.b), h.a) - amount;
	vec4 d = max(h - max_h, vec4(0.0));

	return d / (d.r + d.g + d.b + d.a) * (weights.r + weights.g + weights.b + weights.a);
}

vec3 get_depth_blended_weights3(vec3 weights, vec3 heights, float amount) {
	vec3 h = weights+heights*weights;
	float max_h = max(max(h.r, h.g), h.b) - amount;
	vec3 d = max(h-max_h, vec3(0.0));

	return d / (d.r + d.g + d.b) * (weights.r + weights.g + weights.b);
}

vec2 get_depth_blended_weights2(vec2 weights, vec2 heights, float amount) {
	vec2 h = weights + heights * weights;
	float max_h = max(h.r, h.g) - amount;
	vec2 d = max(h - max_h, vec2(0.0));

	return d / (d.r + d.g) * (weights.r + weights.g);
}