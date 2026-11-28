import bpy, math
def clean_normals(o):
    """Drop imported custom normals (decimation moves them off the faces) and let the exporter write normals from the winding."""
    bpy.context.view_layer.objects.active = o
    for x in bpy.context.scene.objects: x.select_set(x == o)
    try: bpy.ops.mesh.customdata_custom_splitnormals_clear()
    except Exception as e: print("NOCLEAR", e)
    try: bpy.ops.object.shade_auto_smooth(angle=math.radians(40))
    except Exception as e:
        print("NOAUTO", e); bpy.ops.object.shade_smooth()
