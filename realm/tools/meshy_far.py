"""A Meshy building's far mesh: what roof height and the middle zoom see, a few thousand triangles (towns.json hlod).

Blender, headless, CPU only (no GPU, no Godot):

  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup -P realm/tools/meshy_far.py -- [<name> ...]

No names: every imported piece (assets/meshy/<name>/<name>.glb). Each is read as meshy_import.py wrote it, its
vertices welded where they sit together (Meshy pieces come split at every UV seam, so a cut tore the thatch into
shards), cut with Blender's Decimate to meshy.json far_tris (defaults, or the piece's own), its place baked into the
vertices, and written without images to assets/meshy_far/<name>.glb (a .gdignore folder: the game reads it at run time
with GLTFDocument, realistic.gd _far, and gives it the whole model's own materials by name). A piece under twice
far_tris gets none. Glue only: Blender's glTF importer and exporter, bmesh's weld and its Decimate modifier.
"""
import bmesh
import bpy
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REALM = os.path.dirname(HERE)
SRC = os.path.join(REALM, "assets", "meshy")
OUT = os.path.join(REALM, "assets", "meshy_far")
WELD = 0.0005  # how close two vertices sit to be one, as a share of the piece's size


def tris(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def far_tris(name, data):
    return int(data["pieces"].get(name, {}).get("far_tris", data.get("defaults", {}).get("far_tris", 4000)))


def one(name, budget):
    glb = os.path.join(SRC, name, name + ".glb")
    out = os.path.join(OUT, name + ".glb")
    if not os.path.exists(glb):
        return
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    before = tris(obj)
    if before <= budget * 2:  # a far mesh over half the whole is not worth a second batch
        if os.path.exists(out):
            os.remove(out)
        print("FAR %s %d: light enough, none" % (name, before))
        return
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=WELD * max(obj.dimensions))
    bm.to_mesh(obj.data)
    bm.free()
    m = obj.modifiers.new("far", "DECIMATE")
    m.ratio = budget / float(tris(obj))
    m.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=m.name)
    for o in list(bpy.context.scene.objects):
        if o != obj:
            bpy.data.objects.remove(o)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_yup=True, export_apply=True,
                              export_image_format="NONE")
    print("FAR %s %d -> %d" % (name, before, tris(obj)))


def main():
    data = json.load(open(os.path.join(REALM, "data", "meshy.json")))
    names = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if not names:
        names = sorted(n for n in os.listdir(SRC) if os.path.exists(os.path.join(SRC, n, n + ".glb")))
    os.makedirs(OUT, exist_ok=True)
    open(os.path.join(OUT, ".gdignore"), "w").close()
    for n in names:
        one(n, far_tris(n, data))


main()
