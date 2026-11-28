extends SceneTree
## QA viewer (window, not headless): the CC0 tree models close up, by day or night. CB_TREE_OUT=<png>, CB_TREE_NIGHT=1, CB_TREE_DIST=<m> (default 22),
## CB_TREE_LOD=0|1. Three species side by side (fir a, fir b, broadleaf), each 10 m tall, the camera at a low angle.
## Run: godot --path godot --rendering-method forward_plus --script res://tests/tree_view.gd

func _initialize() -> void:
	var night := OS.get_environment("CB_TREE_NIGHT") != ""
	var lod := int(OS.get_environment("CB_TREE_LOD")) if OS.get_environment("CB_TREE_LOD") != "" else 0
	var dist := float(OS.get_environment("CB_TREE_DIST")) if OS.get_environment("CB_TREE_DIST") != "" else 22.0
	var env := Environment.new(); env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.07) if night else Color(0.55, 0.70, 0.88)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.13, 0.19, 0.34) if night else Color(0.55, 0.62, 0.72)
	env.ambient_light_energy = 0.95 if night else 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new(); we.environment = env; root.add_child(we)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-35, 40, 0)
	sun.light_color = Color(0.58, 0.70, 1.0) if night else Color(1.0, 0.95, 0.88); sun.light_energy = 0.7 if night else 1.5; sun.shadow_enabled = true
	root.add_child(sun)
	var ground := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(120, 120); ground.mesh = pm
	var gm := StandardMaterial3D.new(); gm.albedo_color = Color(0.22, 0.34, 0.14); ground.material_override = gm; root.add_child(ground)
	var kinds: Array = (OS.get_environment("CB_TREE_KINDS") if OS.get_environment("CB_TREE_KINDS") != "" else "fir_a,fir_b,broad_a,broad_b,broad_c").split(",")
	for i in kinds.size():
		var at := Vector3((i - (kinds.size() - 1) * 0.5) * 8.5, 0, 0)
		if str(kinds[i]).begins_with("glb:"):   # a model file as it comes (QA of candidate trees): scaled to 10 m
			var inst: Node3D = (load("res://world3d/assets/trees/%s.glb" % str(kinds[i]).substr(4)) as PackedScene).instantiate()
			root.add_child(inst)
			var bb := AABB(); var first := true
			var stack: Array = [inst]
			while not stack.is_empty():
				var nd: Node = stack.pop_back()
				for c in nd.get_children(): stack.append(c)
				if nd is MeshInstance3D:
					var a: AABB = (nd as MeshInstance3D).global_transform * (nd as MeshInstance3D).get_aabb()
					bb = a if first else bb.merge(a); first = false
			var sc := 10.0 / maxf(0.1, bb.size.y)
			inst.scale = Vector3.ONE * sc; inst.position = at - Vector3(bb.get_center().x * sc, bb.position.y * sc, bb.get_center().z * sc)
			continue
		var mi := MeshInstance3D.new(); mi.mesh = Assets3D.tree_mesh(kinds[i], lod)
		var s := 10.0 / Assets3D._trunk_h(kinds[i])
		mi.transform = Transform3D(Basis().scaled(Vector3(s * Assets3D.tree_wide(kinds[i]), s * Assets3D.tree_tall(kinds[i]), s * Assets3D.tree_wide(kinds[i]))), at); root.add_child(mi)
	var cam := Camera3D.new(); cam.fov = 42.0; root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 4.5, dist), Vector3(0, 4.5, 0), Vector3.UP)
	cam.current = true
	var out := OS.get_environment("CB_TREE_OUT")
	await create_timer(1.5).timeout
	await process_frame; await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out if out != "" else "/tmp/tree_view.png")
	quit(0)
