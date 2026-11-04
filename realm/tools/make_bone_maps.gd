extends SceneTree
## Bone maps from each rig to Godot's humanoid profile, for import retargeting.

const SIDES := {"Left": ["l", "Left"], "Right": ["r", "Right"]}

func _init():
	var ue := {"Root": "root", "Hips": "pelvis", "Spine": "spine_01", "Chest": "spine_02", "UpperChest": "spine_03", "Neck": "neck_01", "Head": "Head"}
	var mx := {"Hips": "mixamorig_Hips", "Spine": "mixamorig_Spine", "Chest": "mixamorig_Spine1", "UpperChest": "mixamorig_Spine2", "Neck": "mixamorig_Neck", "Head": "mixamorig_Head", "LeftEye": "LeftEye", "RightEye": "RightEye"}
	for side in SIDES:
		var s: String = SIDES[side][0]
		var M: String = "mixamorig_" + side
		ue[side + "Shoulder"] = "clavicle_" + s
		ue[side + "UpperArm"] = "upperarm_" + s
		ue[side + "LowerArm"] = "lowerarm_" + s
		ue[side + "Hand"] = "hand_" + s
		ue[side + "UpperLeg"] = "thigh_" + s
		ue[side + "LowerLeg"] = "calf_" + s
		ue[side + "Foot"] = "foot_" + s
		ue[side + "Toes"] = "ball_" + s
		mx[side + "Shoulder"] = M + "Shoulder"
		mx[side + "UpperArm"] = M + "Arm"
		mx[side + "LowerArm"] = M + "ForeArm"
		mx[side + "Hand"] = M + "Hand"
		mx[side + "UpperLeg"] = M + "UpLeg"
		mx[side + "LowerLeg"] = M + "Leg"
		mx[side + "Foot"] = M + "Foot"
		mx[side + "Toes"] = M + "ToeBase"
		var parts := {"Thumb": ["Metacarpal", "Proximal", "Distal"], "Index": ["Proximal", "Intermediate", "Distal"], "Middle": ["Proximal", "Intermediate", "Distal"], "Ring": ["Proximal", "Intermediate", "Distal"], "Little": ["Proximal", "Intermediate", "Distal"]}
		for f in parts:
			var uef: String = "pinky" if f == "Little" else f.to_lower()
			var mxf: String = "Pinky" if f == "Little" else f
			for i in 3:
				ue[side + f + parts[f][i]] = "%s_%02d_%s" % [uef, i + 1, s]
				mx[side + f + parts[f][i]] = "%sHand%s%d" % [M, mxf, i + 1]
	var rg := {"Root": "root", "Hips": "DEF-hips", "Spine": "DEF-spine.001", "Chest": "DEF-spine.002", "UpperChest": "DEF-spine.003", "Neck": "DEF-neck", "Head": "DEF-head"}
	for side in SIDES:
		var c: String = side.substr(0, 1)
		rg[side + "Shoulder"] = "DEF-shoulder." + c
		rg[side + "UpperArm"] = "DEF-upper_arm." + c
		rg[side + "LowerArm"] = "DEF-forearm." + c
		rg[side + "Hand"] = "DEF-hand." + c
		rg[side + "UpperLeg"] = "DEF-thigh." + c
		rg[side + "LowerLeg"] = "DEF-shin." + c
		rg[side + "Foot"] = "DEF-foot." + c
		rg[side + "Toes"] = "DEF-toe." + c
		var segs := ["Proximal", "Intermediate", "Distal"]
		for i in 3:
			rg[side + "Thumb" + ["Metacarpal", "Proximal", "Distal"][i]] = "DEF-thumb.%02d.%s" % [i + 1, c]
			for f in [["Index", "index"], ["Middle", "middle"], ["Ring", "ring"], ["Little", "pinky"]]:
				rg[side + f[0] + segs[i]] = "DEF-f_%s.%02d.%s" % [f[1], i + 1, c]
	for pair in [["ue", ue], ["mixamo", mx], ["rigify", rg]]:
		var bm := BoneMap.new()
		bm.profile = SkeletonProfileHumanoid.new()
		for k in pair[1]:
			bm.set_skeleton_bone_name(k, pair[1][k])
		ResourceSaver.save(bm, "res://assets/retarget/%s_map.tres" % pair[0])
		print("saved ", pair[0], " ", pair[1].size())
	quit()
