"""A rigged model as a plain mesh in its rest pose, for rig_unit.py (which brings its own skeleton and weights):
the model's armature and skin are dropped, its meshes kept with their materials. For downloads that come rigged
(Meshy's community soldiers): fed to rig_unit.py as they are, their own armature and skin went through with them
and the export was a stray 80-triangle piece.

  /Applications/Blender.app/Contents/MacOS/Blender -b --python realm/tools/rig/strip_rig.py -- <rigged.glb> <plain.glb>
"""
import bpy, sys

args = sys.argv[sys.argv.index("--") + 1:]
src, dst = args[0], args[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
for a in [o for o in bpy.data.objects if o.type == "ARMATURE"]:
    a.data.pose_position = "REST"
bpy.context.view_layer.update()
meshes = [o for o in bpy.data.objects if o.type == "MESH" and len(o.data.polygons) > 0]
for o in meshes:
    m = o.matrix_world.copy()
    o.parent = None
    o.matrix_world = m
    for mod in list(o.modifiers):
        o.modifiers.remove(mod)  # the skin goes; the rest pose stays as the mesh's own shape
    o.vertex_groups.clear()
    o.shape_key_clear() if o.data.shape_keys else None
for o in [o for o in bpy.data.objects if o.type != "MESH" or o not in meshes]:
    bpy.data.objects.remove(o, do_unlink=True)
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_animations=False, export_skins=False)
print("STRIP", src, "->", dst, sum(len(o.data.polygons) for o in meshes), "faces in", len(meshes), "meshes")
