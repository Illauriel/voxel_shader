shader_type spatial;


//#define DEBUG_MODE_NORMAL
//#define DEBUG_MODE_VERTEX
//#define DEBUG_MODE_TEXTURE

render_mode blend_mix,depth_draw_opaque,cull_back,diffuse_burley,specular_schlick_ggx;

#include "res://addons/zylann.voxel/shaders/transvoxel.gdshaderinc"
#include "res://addons/zylann.voxel/shaders/virtual_texturing.gdshaderinc"
#include "res://addons/zylann.voxel/shaders/triplanar.gdshaderinc"
#include "res://addons/voxel_shader/triplanar_scaled.gdshaderinc"
#include "res://addons/voxel_shader/texturing_height_lib.gdshaderinc"
#include "res://addons/voxel_shader/depth_blending_lib.gdshaderinc"
#include "res://addons/zylann.voxel/shaders/lod_fade.gdshaderinc"
#include "res://addons/zylann.voxel/shaders/voxel_texturing.gdshaderinc"


group_uniforms side_texture;
uniform float u_side_uv_scales[16];
uniform float u_side_roughness_scale = 1.0;
uniform sampler2DArray u_side_albedo_array : source_color, filter_nearest_mipmap;
uniform sampler2DArray u_side_normal_array : hint_roughness_normal, filter_nearest_mipmap;


group_uniforms top_texture;

uniform float u_top_uv_scales[16];
uniform float u_top_roughness_scale = 1.0;

uniform float top_noise_strength : hint_range(-0.5, 0.5, 0.001) = 0.0;
uniform float top_noise_lacunarity : hint_range(-1.0, 1.0, 0.01) = 0.0;

uniform sampler2DArray u_top_texture_array : source_color, filter_nearest_mipmap;
uniform sampler2DArray u_top_normal_array : hint_roughness_normal, filter_nearest_mipmap;
group_uniforms;

group_uniforms texture_blending;
uniform float layer_normal_strength : hint_range(-0.2, 0.2, 0.01) = 0.0;
uniform float layer_depth_strength : hint_range(0.0, 0.2, 0.01) = 0.0;
uniform float layer_noise_strength : hint_range(-0.2, 0.2, 0.01) = 0.0;
uniform float layer_blend_smoothness : hint_range(0.0, 3.0, 0.01) = 0.4;

uniform sampler2D u_blend_noise2d : source_color; // Used to perturb top-side texture mix
uniform float u_blend_noise_scale_coarse = 0.001;
uniform float u_blend_noise_scale_medium = 0.01;
uniform float u_blend_noise_scale_fine = 0.1;
group_uniforms;

uniform sampler2DArray u_test_uv_texture : source_color, filter_nearest_mipmap; // You can plug in a checkered texture to test UV mapping

uniform float u_specular = 0.5;

uniform float u_normalmap_depth : hint_range(-5.0, 5.0, 0.01) = 1.0;

uniform float u_triplanar_sharpness : hint_range(0.0, 155.0, 0.01) = 8.0;


//group_uniforms voxel;

varying vec3 v_world_pos;
varying vec3 v_vertex_pos_model;

varying vec3 v_triplanar_blend;

varying vec4 v_material_indices;
varying vec4 v_material_weights;

varying vec3 v_auto_side_indices;
varying vec3 v_auto_side_weights;

varying vec3 v_top_indices;
varying vec3 v_top_weights;


void vertex() {
	VERTEX = get_transvoxel_position(VERTEX, CUSTOM0);
	v_vertex_pos_model = VERTEX;

	// The tangent space calculations are lifted directly from Godot Standard Shader code
	// and modified to fit the updated triplanar function
	vec3 normal = MODEL_NORMAL_MATRIX * NORMAL;

	TANGENT = vec3(0.0, 0.0, -1.0) * normal.x; //de-absolutized, fixes x-axis lighting
	TANGENT += vec3(-1.0, 0.0, 0.0) * abs(normal.y); //flipped
	TANGENT += vec3(1.0, 0.0, 0.0) * normal.z; //de-absolutized, fixes z-axis lighting
	TANGENT = inverse(MODEL_NORMAL_MATRIX) * normalize(TANGENT);

	BINORMAL = vec3(0.0, 1.0, 0.0) * abs(normal.x);
	BINORMAL += vec3(0.0, 0.0, 1.0) * abs(normal.y); //flipped to fix y axis lighting
	BINORMAL += vec3(0.0, 1.0, 0.0) * abs(normal.z);
	BINORMAL = inverse(MODEL_NORMAL_MATRIX) * normalize(BINORMAL);

	//We'll need this later in Fragment. It's better to calculate it here
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	//Calculating triplanar blend factor is moved here for optimization
	v_triplanar_blend = get_triplanar_blend(normal, u_triplanar_sharpness);

	// Indices are integer values so we can decode them as-is
    v_material_indices = decode_8bit_vec4(CUSTOM1.x);

	// Weights must be in [0..1] so we divide them
    v_material_weights = decode_8bit_vec4(CUSTOM1.y) / 255.0;


	//This is a crucial step because non-normalized weights cause trouble
	//The smol number is to ensure there's never a divide by zero
	v_material_weights /= v_material_weights.x + v_material_weights.y + v_material_weights.z + v_material_weights.w + 0.000001;

	//Automaterial function for side texture goes here
	vec3 side_weights;
	v_auto_side_indices = get_auto_side_index(v_world_pos, side_weights);
	v_auto_side_weights = side_weights;
	
	//normalize auto-material weights
	v_auto_side_weights /= v_auto_side_weights.x+v_auto_side_weights.y+v_auto_side_weights.z+0.0001;


	//Automaterial logic for top tex choice goes here
	vec3 top_weights;
	v_top_indices = get_top_index(v_world_pos, top_weights);
	v_top_weights = top_weights;
	
	//commented out because not necessary in simple 3 weight example, but might be necessary w advanced func
	//v_top_weights /= max(1.0, v_top_weights.x+v_top_weights.y+v_top_weights.z);
}

void fragment() {

	NORMAL = get_voxel_normal_view(v_vertex_pos_model, NORMAL, VIEW_MATRIX * MODEL_MATRIX);

	vec3 world_normal = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	vec3 world_pos = v_world_pos;

	// can be used for distance fading of larger UVs and the like
	float dist = length(world_pos-CAMERA_POSITION_WORLD);

	//How much of an overlap the three projected textures have
	vec3 blending = v_triplanar_blend;

	//Sample noise at various scales to use for more texture variation.
	float blend_noise_fine = texture(u_blend_noise2d,world_pos.xz*u_blend_noise_scale_fine).r;
	float blend_noise = texture(u_blend_noise2d,world_pos.xz*u_blend_noise_scale_medium).r;
	float blend_noise_coarse = texture(u_blend_noise2d,world_pos.xz*u_blend_noise_scale_coarse).r;

	// Sample the 4 blending textures, all with triplanar mapping.
    // We can re-use the same triplanar blending factors for all of them so separating that part
    // of the function improves performance a little.
	vec4 ab[4];
	vec4 nr[4];
	float auto_top_weight = 0.0; //In this implementation we will remove top texture in non-automaterial fragments and use this var


	//We do some sign flipping to fix textures appearing flipped in negative coordinates
	float x_sign = sign(dot(world_normal, vec3(0.0, 0.0, 1.0)));
	float z_sign = sign(dot(world_normal, vec3(-1.0, 0.0, 0.0)));
	vec3 tr_signs = vec3(x_sign, -1.0, z_sign);

	for (int i=0; i<4; i++){
		//might save a few array reads, idk
		float index = min(v_material_indices[i], 15.0);
		if (v_material_indices[i] != 0.0){
			ab[i] = texture_array_triplanar_scaled(u_side_albedo_array, world_pos, tr_signs, blending, index, u_side_uv_scales[int(index)]);
			nr[i] = texture_array_triplanar_scaled(u_side_normal_array, world_pos, tr_signs, blending, index, u_side_uv_scales[int(index)]);
		}
		else{
			vec4 auto_ab0 = texture_array_triplanar_scaled(u_side_albedo_array, world_pos, tr_signs, blending, v_auto_side_indices[0], u_side_uv_scales[int(v_auto_side_indices[0])]);
			vec4 auto_ab1 = texture_array_triplanar_scaled(u_side_albedo_array, world_pos, tr_signs, blending, v_auto_side_indices[1], u_side_uv_scales[int(v_auto_side_indices[1])]);
			vec4 auto_ab2 = texture_array_triplanar_scaled(u_side_albedo_array, world_pos, tr_signs, blending, v_auto_side_indices[2], u_side_uv_scales[int(v_auto_side_indices[2])]);

			vec4 auto_nr0 = texture_array_triplanar_scaled(u_side_normal_array, world_pos, tr_signs, blending, v_auto_side_indices[0], u_side_uv_scales[int(v_auto_side_indices[0])]);
			vec4 auto_nr1 = texture_array_triplanar_scaled(u_side_normal_array, world_pos, tr_signs, blending, v_auto_side_indices[1], u_side_uv_scales[int(v_auto_side_indices[1])]);
			vec4 auto_nr2 = texture_array_triplanar_scaled(u_side_normal_array, world_pos, tr_signs, blending, v_auto_side_indices[2], u_side_uv_scales[int(v_auto_side_indices[2])]);

			vec3 auto_weights;

			if (u_depth_blending_atlas){
				auto_weights = get_depth_blended_weights3(v_auto_side_weights, vec3(auto_ab0.a, auto_ab1.a, auto_ab2.a), u_side_blend_strength);
			}

			ab[i] = auto_ab0 * auto_weights.x + auto_ab1 * auto_weights.y + auto_ab2 * auto_weights.z;
			nr[i] = auto_nr0 * auto_weights.x + auto_nr1 * auto_weights.y + auto_nr2 * auto_weights.z;
			auto_top_weight = v_material_weights[i];
		}
	}


	vec3 albedo_side0 = ab[0].rgb;
    vec3 albedo_side1 = ab[1].rgb;
    vec3 albedo_side2 = ab[2].rgb;
    vec3 albedo_side3 = ab[3].rgb;

	vec3 normal_side0 = nr[0].rgb;
	vec3 normal_side1 = nr[1].rgb;
	vec3 normal_side2 = nr[2].rgb;
	vec3 normal_side3 = nr[3].rgb;


	//Top texture sampling
	vec4 ab_t0 = texture_array_triplanar_scaled(u_top_texture_array, world_pos, tr_signs, blending, v_top_indices.x, u_top_uv_scales[int(v_top_indices.x)]);
	vec4 ab_t1 = texture_array_triplanar_scaled(u_top_texture_array, world_pos, tr_signs, blending, v_top_indices.y, u_top_uv_scales[int(v_top_indices.y)]);
	vec4 ab_t2 = texture_array_triplanar_scaled(u_top_texture_array, world_pos, tr_signs, blending, v_top_indices.z, u_top_uv_scales[int(v_top_indices.z)]);

	vec3 albedo_top0 = ab_t0.rgb;
	vec3 albedo_top1 = ab_t1.rgb;
	vec3 albedo_top2 = ab_t2.rgb;

	float height_top0 = ab_t0.a;
	float height_top1 = ab_t1.a;
	float height_top2 = ab_t2.a;

	vec4 nr_t0 = texture_array_triplanar_scaled(u_top_normal_array, world_pos, tr_signs, blending, v_top_indices.x, u_top_uv_scales[int(v_top_indices.x)]);
	vec4 nr_t1 = texture_array_triplanar_scaled(u_top_normal_array, world_pos, tr_signs, blending, v_top_indices.y, u_top_uv_scales[int(v_top_indices.y)]);
	vec4 nr_t2 = texture_array_triplanar_scaled(u_top_normal_array, world_pos, tr_signs, blending, v_top_indices.z, u_top_uv_scales[int(v_top_indices.z)]);

	vec3 normal_top0 = nr_t0.rgb;
	vec3 normal_top1 = nr_t1.rgb;
	vec3 normal_top2 = nr_t2.rgb;

	float rough_top0 = nr_t0.a;
	float rough_top1 = nr_t1.a;
	float rough_top2 = nr_t2.a;

    // Get weights and make sure they are normalized.
    // We may add a tiny safety margin so we can afford some degree of error.
    vec4 side_weights = v_material_weights;
	vec3 top_weights = v_top_weights;

	// Add noise to make grass/sand transition less boring
	float perturb = ((blend_noise_fine+blend_noise*top_noise_lacunarity) * 2.0 - 1.0)*top_noise_strength;

	top_weights.x = clamp(top_weights.x+perturb, 0.0, 1.0);
	top_weights.y = clamp(top_weights.y-perturb, 0.0, 1.0);
	top_weights.z = clamp(top_weights.z-perturb, 0.0, 1.0);

	top_weights /= (top_weights.x + top_weights.y + top_weights.z);


	if (u_depth_blending_atlas) {
		side_weights = get_depth_blended_weights4(side_weights, vec4(ab[0].a, ab[1].a, ab[2].a, ab[3].a), u_side_blend_strength);
		top_weights = get_depth_blended_weights3(top_weights, vec3(height_top0, height_top1, height_top2), u_top_blend_strength);
	}


    // Calculate side colors
    vec3 albedo_side =
        albedo_side0 * side_weights.r +
        albedo_side1 * side_weights.g +
        albedo_side2 * side_weights.b +
        albedo_side3 * side_weights.a;

	float height_side =
		ab[0].a * side_weights.r +
		ab[1].a * side_weights.g +
		ab[2].a * side_weights.b +
		ab[3].a * side_weights.a;

	vec3 normal_side =
		normal_side0 * side_weights.r +
        normal_side1 * side_weights.g +
        normal_side2 * side_weights.b +
        normal_side3 * side_weights.a;

	float rough_side =
		nr[0].a * side_weights.r +
		nr[1].a * side_weights.g +
		nr[2].a * side_weights.b +
		nr[3].a * side_weights.a;

	rough_side *= u_side_roughness_scale;

	// Now colors for top texture
	vec3 albedo_top =
		albedo_top0 * top_weights.x +
		albedo_top1 * top_weights.y +
		albedo_top2 * top_weights.z;

	float height_top =
		height_top0*top_weights.x +
		height_top1*top_weights.y +
		height_top2*top_weights.z;

	vec3 normal_top =
		normal_top0 * top_weights.x +
		normal_top1 * top_weights.y +
		normal_top2 * top_weights.z;

	float rough_top =
		rough_top0*top_weights.x +
		rough_top1*top_weights.y +
		rough_top2*top_weights.z;

	rough_top *= u_top_roughness_scale;


	// Now blend between top and side textures

	float topness_midlevel = 0.5+layer_normal_strength+layer_depth_strength*(height_side-height_top)+layer_noise_strength*blend_noise_fine;
	float topness_smoothness = layer_blend_smoothness * 0.1;
	float topness_min = topness_midlevel - topness_smoothness;
	float topness_max = topness_midlevel + topness_smoothness;
	float topness = smoothstep(topness_min, topness_max, world_normal.y);

	// If sum of top weights is < 1.0, it should reveal side texture
	topness *= top_weights.x+top_weights.y+top_weights.z;
	topness *= max(0.0, auto_top_weight);

	
	if (u_depth_blending_layer){
		vec2 top_weight = get_depth_blended_weights2(vec2(topness, 1.0-topness), vec2(height_top, height_side), u_layer_blend_strength);
		ALBEDO = albedo_top * top_weight.x + albedo_side * top_weight.y;
		ROUGHNESS = rough_top * top_weight.x + rough_side * top_weight.y;

		NORMAL = (VIEW_MATRIX*vec4(world_normal, 0.0)).xyz;
		NORMAL_MAP = normal_top * top_weight.x + normal_side * top_weight.y;
		NORMAL_MAP_DEPTH = u_normalmap_depth;
		SPECULAR = u_specular;
	}
	else{
	    ALBEDO = mix(albedo_side, albedo_top, topness);
		ROUGHNESS = mix(rough_side, rough_top, topness);

		//Previous approach to normal mixing, lifted from HTerrain shader
		//world_normal = normalize(vec3(
	        //world_normal.x + normal_side.x,
	        //world_normal.y,
	        //world_normal.z + normal_side.z
	    //));

		NORMAL = (VIEW_MATRIX*vec4(world_normal, 0.0)).xyz;
		NORMAL_MAP = mix(normal_side, normal_top, topness);
		NORMAL_MAP_DEPTH = u_normalmap_depth;
	}



	#ifdef DEBUG_MODE_NORMAL
			ALBEDO = ((mat3(INV_VIEW_MATRIX) * NORMAL * vec3(1.0,1.0,1.0)));
			NORMAL = (VIEW_MATRIX*vec4(world_normal, 0.0)).xyz;
			NORMAL_MAP_DEPTH = 0.0;
			ROUGHNESS = 0.7;
	#endif
	#ifdef DEBUG_MODE_VERTEX

			ALBEDO = COLOR.rgb;
			NORMAL = (VIEW_MATRIX*vec4(world_normal, 0.0)).xyz;
			NORMAL_MAP_DEPTH = 0.0;
			ROUGHNESS = 0.7;
	#endif
	#ifdef DEBUG_MODE_TEXTURE

			ALBEDO = texture_array_triplanar_scaled(u_test_uv_texture, world_pos, tr_signs, blending, 0.0, 1.0).rgb;
			NORMAL = (VIEW_MATRIX*vec4(world_normal, 0.0)).xyz;
			NORMAL_MAP_DEPTH = 0.0;
			ROUGHNESS = 0.7;
	#endif

	// Discard has to be last to workaround https://github.com/godotengine/godot/issues/34966
	if (get_lod_fade_discard(SCREEN_UV)) {
		discard;
	}
}