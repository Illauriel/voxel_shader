# Voxel World Materials Shader

This shader is designed for use with smooth transvoxel terrains in Zylann's Voxel Module for Godot engine, offering a flexible system for blending side and top textures with various material properties. It is based on smooth_texture_array shader in Zylann's [voxelgame demo](https://github.com/Zylann/voxelgame)

## Installation

While originally stored in the `addons` folder following the convention of Zylann's voxelgame demo, you can place this shader anywhere in your Godot project structure. The shader uses includes from the voxelgame demo, so you also have to clone or download it and copy the necessary includes into your project.

There's an example of setting up the material on VoxelTerrain included in the repository. All textures used in atlases are CC0, taken from <https://ambientcg.com/>.
For the example to work out of the box, copy the *zylann.voxel* folder from [voxelgame demo](https://github.com/Zylann/voxelgame) into *addons* subfolder of your test project 

## Features

- Dual texture atlas system: separate sets for 'side' and 'top' textures
- Utilizes VoxelTerrain's weights and indices (16x4) for side textures
- Customizable logic for top texture selection
- Auto-material functionality for procedural texture application
- Optional depth blending between top and side textures, and within atlases

#### Upcoming
- A minimal PBR shader example (current one is too performance intensive, and will include features unneeded if you don't use dynamic weather or procedural texturing)
- More granular depth blending control
- Dynamic snow coverage (displacement may look weird until we get some kind of tesselation in Godot)
- Depth-blended puddles (droplet animations are a bit of a problem so far)
- Parallax mapping (likely not happening unless I find a good example or paper on its usage with triplanar)

## Architecture

The shader employs a dual-layer texturing system, consisting of 'side' textures and 'top' textures, each serving a distinct purpose in creating realistic terrain.

### Side Textures

Side textures form the core of the terrain's volume, representing materials like rock, dirt, and sand. These textures leverage VoxelTerrain's built-in weight and index system.

The "auto-material" functionality is activated when the texture index is set to 0. This enables procedural texturing, where the shader automatically selects and applies appropriate textures based on factors like terrain height or slope. However, if you prefer more control, you can override this automatic selection by explicitly setting material indices and weights using VoxelTool or generator's OutputWeight node. 

### Top Textures

Top textures act as an overlay, adding surface details such as grass, dust, moss, or forest floor. Unlike side textures, the selection and blending of top textures require custom logic that you'll need to implement within the shader. This offers greater flexibility in defining how your terrain's surface appears and behaves.

### Blending

The shader provides options for depth blending, both between the top and side textures and within each texture atlas. This feature, when enabled, creates sharper, more realistic transitions between different materials and can significantly enhance the visual quality of your terrain.

## Preparing Texture Atlases

Each texture set (side and top) requires two atlas textures:

1. Albedo Atlas:
   - RGB channels: Albedo color
   - Alpha channel: Bump/height map

2. Normal-Roughness Atlas:
   - RGB channels: Normal map
   - Alpha channel: Roughness map

### Recommended Tools
- **Material Maker**: Use for exporting texture maps in Godot-friendly format
- **HTerrain Texture Tools**: Part of Zylann's [HTerrain addon](https://github.com/Zylann/godot_heightmap_plugin), useful for building atlases from individual textures

## Usage Tips

- Experiment with depth blending settings for more realistic texture transitions
- Customize the auto-material logic in the shader to fit your terrain needs
- Adjust UV scales and blending parameters for desired detail levels

## Requirements

- Godot 4.x
- [Zylann's Voxel Module](https://github.com/Zylann/godot_voxel)
