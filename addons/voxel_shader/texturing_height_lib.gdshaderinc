group_uniforms height_texturing;
uniform float grass_height = 2.0;
uniform float highland_height = 20.0;
uniform float highland_band_size = 10.0;
uniform float blend_strength : hint_range(0.0, 2.0, 0.01) = 0.5;


vec3 get_top_index(vec3 _world_pos, out vec3 _weight){
	//Very simple height-based side texture placement
	float grass_weight = smoothstep(grass_height-blend_strength*0.5, grass_height+blend_strength*0.5, _world_pos.y) - smoothstep(highland_height-blend_strength*highland_band_size*0.5, highland_height+blend_strength*highland_band_size*0.5, _world_pos.y);
	float forest_weight =  smoothstep(highland_height-blend_strength*highland_band_size*0.5, highland_height+blend_strength*highland_band_size*0.5, _world_pos.y);
	float sand_weight =  1.0-smoothstep(grass_height, grass_height+blend_strength, _world_pos.y);
	float ice_weight;
	_weight = vec3(grass_weight, forest_weight, sand_weight);

	return vec3(0.01, 1.01, 5.01); //your indices for grass, forest and sand go here. Small margin to avoid errors. TODO An advanced logic.;
}

vec3 get_auto_side_index(vec3 _world_pos, out vec3 _weight){
	float cliff_weight = smoothstep(10.0, 15.0, _world_pos.y);
	float sand_weight = 1.0-smoothstep(2.0, 2.5, _world_pos.y);
	float dirt_weight = 1.0-sand_weight-cliff_weight;
	_weight = vec3(cliff_weight, dirt_weight, sand_weight);

	return vec3(8.01, 3.01, 5.01);
}