import bpy
import math
import os

OUTPUT_DIR = os.path.dirname(os.path.abspath(__file__))

def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    for collection in bpy.data.meshes:
        bpy.data.meshes.remove(collection)

def save(name):
    path = os.path.join(OUTPUT_DIR, f"{name}.blend")
    bpy.ops.wm.save_as_mainfile(filepath=path)
    print(f"Saved {path}")

# --- Cone ---
clear_scene()
bpy.ops.mesh.primitive_cone_add(vertices=32, radius1=1.0, radius2=0.0, depth=2.0, location=(0,0,0))
save("cone")

# --- Hexagonal Prism ---
clear_scene()
bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=1.0, depth=2.0, location=(0,0,0))
save("hexagonal_prism")

# --- Triangular Prism ---
clear_scene()
bpy.ops.mesh.primitive_cylinder_add(vertices=3, radius=1.0, depth=2.0, location=(0,0,0))
save("triangular_prism")

# --- Capsule ---
clear_scene()
# Blender 3.x+ has primitive_round_cube, but capsule is most reliably made as
# a UV sphere squashed in the middle — use a cylinder with hemisphere caps via
# meta objects, or just use the built-in capsule if available (4.x).
try:
    bpy.ops.mesh.primitive_round_cube_add(arc_div=16, radius=1.0, size=(0.6, 0.6, 1.6))
except AttributeError:
    pass
# Fallback: use the capsule operator if available (Blender 4.x)
if not bpy.context.selected_objects:
    try:
        bpy.ops.mesh.primitive_capsule_add(radius=0.5, depth=1.0, location=(0,0,0))
    except AttributeError:
        # Final fallback: build capsule from UV sphere + cylinder + sphere manually
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.5, location=(0,0,0.75))
        top = bpy.context.active_object
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.5, location=(0,0,-0.75))
        bot = bpy.context.active_object
        bpy.ops.mesh.primitive_cylinder_add(radius=0.5, depth=1.5, location=(0,0,0))
        cyl = bpy.context.active_object
        bpy.ops.object.select_all(action='SELECT')
        bpy.context.view_layer.objects.active = cyl
        bpy.ops.object.join()
save("capsule")

# --- Cube ---
clear_scene()
bpy.ops.mesh.primitive_cube_add(size=2.0, location=(0,0,0))
save("cube")

print("All meshes generated.")
