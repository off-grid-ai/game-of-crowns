"""A body rigged on Unreal's mannequin skeleton (pelvis, spine_01, thigh_l...),
renamed to Mixamo's bone names so it takes the shared moves through the
standard map (assets/retarget/mixamo_map.tres), stood in its rest pose with
any animation dropped, its maps swapped for smaller copies, and saved as glTF.

  Blender -b -P tools/ue_to_mixamo.py -- <in.fbx> <out.gltf> <tex dir>

<tex dir> holds the maps by material, lower case: <material>_col.png (alpha cuts hair
cards), <material>_nor.png. Meshes whose name says "Hair" get their own
alpha-cut copy of their material; everything else is drawn solid.
"""
import bpy, sys, os

src, out, tex = sys.argv[-3:]

SIDES = {"l": "Left", "r": "Right"}
NAMES = {"pelvis": "Hips", "spine_01": "Spine", "spine_02": "Spine1", "spine_03": "Spine2",
	"neck_01": "Neck", "head": "Head"}
LIMBS = {"clavicle": "Shoulder", "upperarm": "Arm", "lowerarm": "ForeArm", "hand": "Hand",
	"thigh": "UpLeg", "calf": "Leg", "foot": "Foot", "ball": "ToeBase"}
FINGERS = {"thumb": "Thumb", "index": "Index", "middle": "Middle", "ring": "Ring", "pinky": "Pinky"}


def mixamo(name: str) -> str:
	if name in NAMES:
		return "mixamorig:" + NAMES[name]
	parts = name.split("_")
	if len(parts) == 2 and parts[0] in LIMBS and parts[1] in SIDES:
		return "mixamorig:" + SIDES[parts[1]] + LIMBS[parts[0]]
	if len(parts) == 3 and parts[0] in FINGERS and parts[2] in SIDES:
		return "mixamorig:%sHand%s%d" % (SIDES[parts[2]], FINGERS[parts[0]], int(parts[1]))
	return name


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=src)
arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
if arm.animation_data:
	arm.animation_data.action = None
for a in list(bpy.data.actions):
	bpy.data.actions.remove(a)
for pb in arm.pose.bones:
	pb.matrix_basis.identity()
renamed = {}
for b in arm.data.bones:
	new = mixamo(b.name)
	if new != b.name:
		renamed[b.name] = new
for old, new in renamed.items():
	arm.data.bones[old].name = new  # vertex groups follow the rename
print("renamed %d bones" % len(renamed))


def image(path: str):
	return bpy.data.images.load(path) if os.path.exists(path) else None


def dress(mat, key: str, cut: bool):
	mat.use_nodes = True
	nt = mat.node_tree
	nt.nodes.clear()
	bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
	outn = nt.nodes.new("ShaderNodeOutputMaterial")
	nt.links.new(bsdf.outputs[0], outn.inputs[0])
	bsdf.inputs["Roughness"].default_value = 0.85
	col = image(os.path.join(tex, key + "_col.png"))
	if col:
		t = nt.nodes.new("ShaderNodeTexImage")
		t.image = col
		nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
		if cut:
			nt.links.new(t.outputs["Alpha"], bsdf.inputs["Alpha"])
	nor = image(os.path.join(tex, key + "_nor.png"))
	if nor:
		nor.colorspace_settings.name = "Non-Color"
		t = nt.nodes.new("ShaderNodeTexImage")
		t.image = nor
		nm = nt.nodes.new("ShaderNodeNormalMap")
		nt.links.new(t.outputs["Color"], nm.inputs["Color"])
		nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
	if cut:
		mat.surface_render_method = "DITHERED"
		mat.blend_method = "CLIP"


for o in [o for o in bpy.data.objects if o.type == "MESH" and o.parent != arm]:
	bpy.data.objects.remove(o)  # stray helpers (a placeholder sphere)
for m in list(bpy.data.materials):
	dress(m, m.name.lower(), False)
hair_of = {}
for o in [o for o in bpy.data.objects if o.type == "MESH" and "hair" in o.name.lower()]:
	for i, m in enumerate(o.data.materials):
		if m.name not in hair_of:
			hair_of[m.name] = m.copy()
			hair_of[m.name].name = m.name + "Hair"
			dress(hair_of[m.name], m.name.lower(), True)
		o.data.materials[i] = hair_of[m.name]

bpy.ops.export_scene.gltf(filepath=out, export_format="GLTF_SEPARATE", export_animations=False,
	export_skins=True, export_apply=False, export_yup=True, export_image_format="AUTO")
print("wrote", out)
