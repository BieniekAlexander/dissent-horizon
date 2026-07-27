"""Generate the rough Colonial unit models described in each piece's `## Visuals`
note (gdd/factions/colonial/units/*.md).

Run:
    blender --background --python assets/meshes/generate_colonial_meshes.py

Conventions this file has to honour — see CLAUDE.md and Movement.get_facing:
  * Blender is Z-up; Godot's glTF importer maps (x, y, z) -> (x, z, -y).
  * Models are authored facing -Y in Blender, which lands on +Z in Godot. That is
    the project's visual front (NOT the engine's own -Z forward): the root node's
    rotation.y orients the mesh directly.
  * Ground units sit with their base at z = 0; aircraft straddle z = 0 and are
    lifted by the scene.
  * Every surface is a Principled BSDF so the glTF import yields a
    StandardMaterial3D — MeshVisual only tints BaseMaterial3D surfaces, and
    silently skips anything else.
  * Albedos stay light and desaturated: MeshVisual multiplies the team colour
    over every surface, so a saturated base colour muddies the tint.

Everything here is deliberately blocky placeholder art.
"""

import bpy
import math
import os

OUTPUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "entities", "colonial")

TEAM_COLOR = (0.82, 0.82, 0.85, 1.0)
BASE_COLOR = (0.34, 0.36, 0.40, 1.0)

TEAM = 0
BASE = 1


# --------------------------------------------------------------------------- #
# geometry helpers — each appends to a shared (verts, faces, mat_ids) buffer
# --------------------------------------------------------------------------- #

class Build:
    def __init__(self):
        self.verts = []
        self.faces = []
        self.mats = []

    def _push(self, vs, fs, mat):
        base = len(self.verts)
        self.verts.extend(vs)
        for f in fs:
            self.faces.append(tuple(base + i for i in f))
            self.mats.append(mat)

    def box(self, x0, x1, y0, y1, z0, z1, mat=TEAM):
        """Axis-aligned box, outward-wound."""
        vs = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
              (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
        fs = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
              (2, 3, 7, 6), (1, 2, 6, 5), (3, 0, 4, 7)]
        self._push(vs, fs, mat)

    def extrude_x(self, profile, x0, x1, mat=TEAM):
        """Extrude a (y, z) polygon along X. `profile` is CCW in the YZ plane
        when viewed from +X, which makes the generated side walls face outward.
        Used for sloped vehicle hulls, where a stack of boxes reads wrong."""
        n = len(profile)
        vs = [(x0, y, z) for (y, z) in profile] + [(x1, y, z) for (y, z) in profile]
        fs = [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
        for i in range(n):
            j = (i + 1) % n
            fs.append((i, j, j + n, i + n))
        self._push(vs, fs, mat)

    def prism_z(self, footprint, z0, z1, mat=TEAM):
        """Extrude an (x, y) polygon along Z. `footprint` must be CCW in XY."""
        n = len(footprint)
        vs = [(x, y, z0) for (x, y) in footprint] + [(x, y, z1) for (x, y) in footprint]
        fs = [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
        for i in range(n):
            j = (i + 1) % n
            fs.append((i, j, j + n, i + n))
        self._push(vs, fs, mat)

    def cylinder_z(self, cx, cy, r, z0, z1, seg=16, mat=TEAM):
        ring = [(cx + r * math.cos(2 * math.pi * i / seg),
                 cy + r * math.sin(2 * math.pi * i / seg)) for i in range(seg)]
        self.prism_z(ring, z0, z1, mat)

    def cylinder_x(self, cy, cz, r, x0, x1, seg=10, mat=BASE):
        """Wheel: a cylinder whose axis runs along X."""
        ring = [(cy + r * math.cos(2 * math.pi * i / seg),
                 cz + r * math.sin(2 * math.pi * i / seg)) for i in range(seg)]
        self.extrude_x(ring, x0, x1, mat)

    def wheel_pair(self, y, z, r, x_inner, x_outer, mat=BASE):
        self.cylinder_x(y, z, r, -x_outer, -x_inner, mat=mat)
        self.cylinder_x(y, z, r, x_inner, x_outer, mat=mat)


def emit(name, build):
    """Write one .blend holding a single mesh object with team/base slots."""
    bpy.ops.wm.read_factory_settings(use_empty=True)

    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(build.verts, [], build.faces)
    mesh.validate(verbose=False)

    for mat_name, color in (("team", TEAM_COLOR), ("base", BASE_COLOR)):
        mat = bpy.data.materials.new(mat_name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Roughness"].default_value = 0.75
        bsdf.inputs["Metallic"].default_value = 0.0
        mat.diffuse_color = color
        mesh.materials.append(mat)

    for poly, mat_id in zip(mesh.polygons, build.mats):
        poly.material_index = mat_id

    mesh.shade_flat()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    path = os.path.join(OUTPUT_DIR, f"{name}.blend")
    bpy.ops.wm.save_as_mainfile(filepath=path)
    print(f"WROTE {path}  verts={len(build.verts)} faces={len(build.faces)}")


# --------------------------------------------------------------------------- #
# cl_aircraftLight_antiLight — Clipper: "slender helicopter"
# --------------------------------------------------------------------------- #

def clipper():
    b = Build()
    # cabin + tapered nose (nose toward -Y)
    b.box(-0.18, 0.18, -0.50, 0.22, 0.10, 0.50, TEAM)
    b.box(-0.13, 0.13, -0.80, -0.50, 0.15, 0.42, TEAM)
    # tail boom, fin and horizontal stabiliser
    b.box(-0.055, 0.055, 0.22, 1.00, 0.30, 0.40, TEAM)
    b.box(-0.03, 0.03, 0.86, 1.02, 0.30, 0.66, BASE)
    b.box(-0.24, 0.24, 0.80, 0.92, 0.32, 0.36, BASE)
    # tail rotor plate
    b.box(0.055, 0.085, 0.88, 0.98, 0.40, 0.62, BASE)
    # rotor mast + two crossed blades
    b.box(-0.045, 0.045, -0.20, -0.11, 0.50, 0.60, BASE)
    b.box(-0.85, 0.85, -0.21, -0.10, 0.585, 0.615, BASE)
    b.box(-0.055, 0.055, -1.00, 0.72, 0.585, 0.615, BASE)
    # landing skids
    for sx in (-1.0, 1.0):
        b.box(sx * 0.22, sx * 0.16, -0.45, 0.15, -0.10, -0.06, BASE)
        b.box(sx * 0.20, sx * 0.18, -0.34, -0.28, -0.06, 0.12, BASE)
        b.box(sx * 0.20, sx * 0.18, 0.02, 0.08, -0.06, 0.12, BASE)
    emit("clipper", b)


# --------------------------------------------------------------------------- #
# cl_aircraftMedium_antiMech — Drake: "generic fighter jet"
# --------------------------------------------------------------------------- #

def drake():
    b = Build()
    # Tapered fuselage, drawn as a plan-view outline extruded upward. Listed
    # counter-clockwise in XY: nose, down the +X flank to the tail, back up -X.
    b.prism_z([(0.0, -1.35), (0.13, -0.85), (0.16, 0.30), (0.13, 1.00),
               (0.0, 1.05), (-0.13, 1.00), (-0.16, 0.30), (-0.13, -0.85)],
              0.0, 0.30, TEAM)
    # canopy
    b.box(-0.11, 0.11, -0.62, -0.16, 0.30, 0.44, BASE)
    # swept main wings — thin plates, mirrored (the -X copy is wound in reverse
    # so its faces still point outward)
    b.prism_z([(0.15, -0.30), (0.95, 0.30), (0.95, 0.52), (0.15, 0.62)],
              0.10, 0.16, TEAM)
    b.prism_z([(-0.15, -0.30), (-0.15, 0.62), (-0.95, 0.52), (-0.95, 0.30)],
              0.10, 0.16, TEAM)
    # tailplanes
    b.prism_z([(0.13, 0.72), (0.52, 0.92), (0.52, 1.04), (0.13, 1.02)],
              0.12, 0.17, BASE)
    b.prism_z([(-0.13, 0.72), (-0.13, 1.02), (-0.52, 1.04), (-0.52, 0.92)],
              0.12, 0.17, BASE)
    # swept vertical stabiliser
    b.extrude_x([(0.55, 0.30), (1.02, 0.30), (1.02, 0.80), (0.80, 0.80)],
                -0.03, 0.03, BASE)
    # twin exhausts
    b.box(-0.14, -0.02, 0.98, 1.10, 0.06, 0.22, BASE)
    b.box(0.02, 0.14, 0.98, 1.10, 0.06, 0.22, BASE)
    emit("drake", b)


# --------------------------------------------------------------------------- #
# cl_aircraftStrong_superUnit — Reverence: Science-Vessel-ish "floating cylinder"
# --------------------------------------------------------------------------- #

def reverence():
    b = Build()
    b.cylinder_z(0.0, 0.0, 0.85, 0.10, 0.72, seg=16, mat=TEAM)     # main drum
    b.cylinder_z(0.0, 0.0, 0.45, -0.20, 0.10, seg=16, mat=BASE)    # underslung pod
    b.cylinder_z(0.0, 0.0, 0.34, 0.72, 0.94, seg=16, mat=BASE)     # dorsal cap
    b.cylinder_z(0.0, 0.0, 0.10, 0.94, 1.12, seg=8, mat=BASE)      # mast
    # a small forward blister, so the hull is not perfectly radially symmetric
    # and the player can read which way it is pointing
    b.box(-0.16, 0.16, -1.00, -0.74, 0.26, 0.52, BASE)
    emit("reverence", b)


# --------------------------------------------------------------------------- #
# cl_bioLight_stealth — Sleeper: the irregular, with a triangular torso
# --------------------------------------------------------------------------- #

def sleeper():
    b = Build()
    # Triangular torso, apex forward (-Y) — the one change the note asks for.
    # CCW in XY so prism_z winds the walls outward.
    b.prism_z([(0.0, -0.20), (0.24, 0.14), (-0.24, 0.14)], 0.0, 1.15, TEAM)
    # head + rear nub, carried over from irregular.blend unchanged
    b.box(-0.16, 0.16, -0.16, 0.16, 1.15, 1.50, BASE)
    b.box(-0.05, 0.05, 0.16, 0.28, 1.28, 1.38, BASE)
    emit("sleeper", b)


# --------------------------------------------------------------------------- #
# cl_mechLight_support — Kobold: "a small pick-up truck"
# --------------------------------------------------------------------------- #

def kobold():
    b = Build()
    b.box(-0.38, 0.38, -0.72, 0.78, 0.16, 0.30, TEAM)   # chassis / bed floor
    b.box(-0.36, 0.36, -0.30, 0.28, 0.30, 0.66, TEAM)   # cab
    b.box(-0.36, 0.36, -0.72, -0.30, 0.30, 0.48, TEAM)  # hood
    # open bed walls
    b.box(-0.38, -0.30, 0.28, 0.78, 0.30, 0.46, TEAM)
    b.box(0.30, 0.38, 0.28, 0.78, 0.30, 0.46, TEAM)
    b.box(-0.38, 0.38, 0.70, 0.78, 0.30, 0.46, TEAM)
    b.wheel_pair(-0.45, 0.17, 0.17, 0.36, 0.44)
    b.wheel_pair(0.50, 0.17, 0.17, 0.36, 0.44)
    emit("kobold", b)


# --------------------------------------------------------------------------- #
# cl_mechMedium_antiLight — Sloop: "Model of an APC"
# --------------------------------------------------------------------------- #

def sloop():
    b = Build()
    # sloped-glacis hull, as a YZ profile extruded across the width
    b.extrude_x([(-1.00, 0.20), (0.98, 0.20), (0.98, 0.62), (-0.62, 0.62)],
                -0.52, 0.52, TEAM)
    b.box(-0.42, 0.42, -0.40, 0.72, 0.62, 0.82, TEAM)          # troop compartment
    b.cylinder_z(0.0, 0.10, 0.16, 0.82, 0.96, seg=10, mat=BASE)  # cupola
    for y in (-0.62, 0.05, 0.72):
        b.wheel_pair(y, 0.20, 0.20, 0.52, 0.62)
    emit("sloop", b)


# --------------------------------------------------------------------------- #
# cl_mechStrong_support — Avalanche: generic turreted tank, deliberately NO barrel
# --------------------------------------------------------------------------- #

def avalanche():
    b = Build()
    b.extrude_x([(-1.10, 0.22), (1.05, 0.22), (1.05, 0.60), (-0.72, 0.60)],
                -0.62, 0.62, TEAM)
    for sx in (-1.0, 1.0):
        b.box(sx * 0.74, sx * 0.60, -1.05, 1.05, 0.02, 0.42, BASE)   # tracks
    b.cylinder_z(0.0, 0.02, 0.42, 0.60, 0.66, seg=16, mat=BASE)      # turret ring
    b.box(-0.40, 0.40, -0.42, 0.46, 0.66, 0.96, TEAM)                # turret, no barrel
    b.cylinder_z(0.0, 0.02, 0.12, 0.96, 1.10, seg=10, mat=BASE)      # emitter node
    emit("avalanche", b)


# --------------------------------------------------------------------------- #
# cl_airField — Sky Port: the apron an aircraft actually lands on
#
# THE FOOTPRINT IS THE MESH. Structure.dimensions is 6x4 cells at Map.CELL_SIZE 1.0,
# so this occupies exactly x -3..3 by y -2..2 in Blender, which lands on 6 x 4 in
# Godot's XZ (the importer maps (x, y, z) -> (x, z, -y)). Nothing may stick out past
# that: a building whose art overhangs its grid cells reads as though it should block
# ground the game says is walkable.
#
# The runway is the long axis, down the middle, with two parking pads either side of
# it — the layout the docking sequence taxis through (see DockingBay.runway_path and
# the Pad markers on cl_air_field.tscn, which have to agree with these positions).
# --------------------------------------------------------------------------- #

def sky_port():
    b = Build()
    APRON = 0.10
    MARK = 0.12
    b.box(-3.0, 3.0, -2.0, 2.0, 0.0, APRON, BASE)              # tarmac apron
    b.box(-2.9, 2.9, -0.45, 0.45, APRON, MARK, TEAM)           # runway, along X
    for (px, py) in ((-1.5, -1.25), (0.75, -1.25), (-1.5, 1.25), (0.75, 1.25)):
        b.box(px - 0.7, px + 0.7, py - 0.7, py + 0.7, APRON, MARK, TEAM)   # parking pads
    b.box(2.10, 2.85, 1.25, 1.90, 0.0, 1.20, TEAM)             # control tower
    b.box(1.95, 2.95, 1.05, 1.95, 1.20, 1.50, BASE)            # tower cab
    b.box(2.10, 2.85, -1.90, -1.25, 0.0, 0.55, BASE)           # fuel bunker
    emit("sky_port", b)


if __name__ == "__main__":
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    clipper()
    drake()
    reverence()
    sleeper()
    kobold()
    sloop()
    avalanche()
    sky_port()
    print("ALL DONE")
