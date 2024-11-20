vec3 get_top_index(vec3 _world_pos, out vec3 _weight){
	//Very simple height-based side texture placement
	float grass_weight = smoothstep(2.0, 2.5, _world_pos.y) - smoothstep(20.0, 30.0, _world_pos.y);
	float forest_weight =  smoothstep(20.0, 30.0, _world_pos.y);
	float sand_weight =  1.0-smoothstep(2.0, 2.5, _world_pos.y);
	float ice_weight;
	_weight = vec3(grass_weight, forest_weight, sand_weight);

	return vec3(0.01, 1.01, 5.01); //your indices for grass, forest and sand go here. Small margin to avoid errors. TODO An advanced logic.;
}

vec3 get_auto_top_index(vec3 _world_pos, out vec3 _weight){
	float cliff_weight = smoothstep(10.0, 15.0, _world_pos.y);
	float sand_weight = 1.0-smoothstep(2.0, 2.5, _world_pos.y);
	float dirt_weight = 1.0-sand_weight-cliff_weight;
	_weight = vec3(cliff_weight, dirt_weight, sand_weight);

	return vec3(8.01, 3.01, 5.01);
}