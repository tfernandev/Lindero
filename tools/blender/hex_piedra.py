"""Loseta de piedra de Lindero: relieve 3D sacado de la pintura del juego.

La lámina pintada art/terreno_piedra.jpg (cantera vista desde arriba) se
proyecta desde arriba sobre una malla cuyo relieve se calcula a partir de la
misma pintura: paredes de roca altas, piso de la cantera hundido, arbustos
abultados. Encima van rocas 3D sueltas con la misma pintura proyectada, así
todo comparte paleta y luz con el resto de las losetas.

Uso (sin abrir Blender):
  blender -b --factory-startup --python tools/blender/hex_piedra.py -- \
      models/tiles/hex_piedra_v2.glb debug_captures/hex_piedra_preview.png

Convenciones que espera table_board.gd:
  - Hexágono "pointy-top" de radio 1 (puntas sobre +-Y de Blender = Z Godot).
  - Objeto de bordes "Side" (recibe la madera del tablero).
  - Centro (radio ~0.24) parejo: ahí se apoya la ficha de número.
  - HEX_OWN_MATS: el terreno usa el material del tablero; los objetos
    "Boulder_*" (roca de Poly Haven, CC0) conservan su propio material.
"""
import math
import os
import random
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Euler, Vector, noise

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_GLB = ARGS[0] if len(ARGS) > 0 else "hex_piedra.glb"
OUT_PNG = ARGS[1] if len(ARGS) > 1 else ""
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
PAINT = os.path.join(ROOT, "art", "terreno_piedra.jpg")
# Poly Haven "Boulder 01" (CC0, Rico Cilliers): https://polyhaven.com/a/boulder_01
BOULDER = os.path.join(ROOT, "art_src", "polyhaven", "boulder_01", "boulder_01_1k.gltf")
BOULDER_TRIS = 1800   # la original tiene 124k
# (ángulo°, radio, largo en unidades de loseta, giro°): la principal y dos chicas
BOULDER_SPOTS = [(118, 0.55, 0.50, 15), (152, 0.72, 0.18, 80), (88, 0.76, 0.14, 200)]

SEED = 11
R = 1.0
SLAB_H = 0.083        # zócalo (≈ 6.8 u en Godot, como las otras losetas)
FLOOR_H = 0.090       # nivel base del terreno
WALL_H = 0.240        # alto extra de las paredes de roca
BUSH_H = 0.050        # bulto de los arbustos
RIM_H = 0.030         # meseta de pasto alrededor
CLEAR_R = 0.24
GRID = 150            # resolución de la malla antes de decimar
DECIMATE = 0.32

rng = random.Random(SEED)


# ---------------------------------------------------------------- pintura
def load_paint():
    img = bpy.data.images.load(PAINT)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)[:, :, :3]
    return img, px  # fila 0 = abajo de la imagen (convención de Blender)


def box_blur(a, r):
    if r <= 0:
        return a
    k = 2 * r + 1
    pad = np.pad(a, r, mode="edge")
    c = pad.cumsum(0).cumsum(1)
    c = np.pad(c, ((1, 0), (1, 0)))
    return (c[k:, k:] - c[:-k, k:] - c[k:, :-k] + c[:-k, :-k]) / (k * k)


def height_field(px):
    """Mapa de alturas por capas, a partir del color de la pintura."""
    small = px[::4, ::4]
    r, g, b = small[..., 0], small[..., 1], small[..., 2]
    mx = small.max(-1)
    mn = small.min(-1)
    sat = (mx - mn) / np.maximum(mx, 1e-4)
    val = mx
    n = small.shape[0]
    yy, xx = np.mgrid[0:n, 0:n]
    u = (xx + 0.5) / n * 2 - 1
    v = (yy + 0.5) / n * 2 - 1
    rad = np.sqrt(u * u + v * v)

    green = np.clip((g - np.maximum(r, b)) * 6.0, 0, 1) * np.clip((sat - 0.25) * 4, 0, 1)
    rocky = np.clip((0.42 - sat) * 5.0, 0, 1) * np.clip((val - 0.18) * 4, 0, 1)
    ring = np.clip(1.0 - np.abs(rad - 0.52) / 0.30, 0, 1)
    floor = np.clip(1.0 - rad / 0.42, 0, 1)

    wall = box_blur(rocky * ring, 3)
    wall = np.clip(wall * 1.8, 0, 1) ** 0.8
    bush = np.clip(box_blur(green, 2) * 1.6, 0, 1)
    plateau = np.clip((rad - 0.55) / 0.25, 0, 1)
    detail = box_blur(val, 1) - box_blur(val, 4)

    return (WALL_H * wall + BUSH_H * bush * (1 - wall) + RIM_H * plateau * (1 - wall)
            - 0.02 * floor + 0.012 * np.clip(detail * 4, -1, 1))


def sample(field, x, y):
    n = field.shape[0]
    fx = float(np.clip((x * 0.5 + 0.5) * n - 0.5, 0, n - 1.001))
    fy = float(np.clip((y * 0.5 + 0.5) * n - 0.5, 0, n - 1.001))
    x0, y0 = int(fx), int(fy)
    tx, ty = fx - x0, fy - y0
    a = field[y0, x0] * (1 - tx) + field[y0, x0 + 1] * tx
    b = field[y0 + 1, x0] * (1 - tx) + field[y0 + 1, x0 + 1] * tx
    return float(a * (1 - ty) + b * ty)


def color_at(px, x, y):
    h, w = px.shape[:2]
    i = int(np.clip((y * 0.5 + 0.5) * h, 0, h - 1))
    j = int(np.clip((x * 0.5 + 0.5) * w, 0, w - 1))
    return px[max(0, i - 6):i + 7, max(0, j - 6):j + 7].reshape(-1, 3).mean(0)


# ---------------------------------------------------------------- geometría
def hex_corners(radius):
    return [Vector((radius * math.cos(math.radians(60 * i + 90)),
                    radius * math.sin(math.radians(60 * i + 90)), 0.0)) for i in range(6)]


def hex_dist(x, y):
    ax, ay = abs(x), abs(y)
    return max(ax / (math.sqrt(3) / 2), ax / math.sqrt(3) + ay)


def top_uv(bm):
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        for lp in f.loops:
            co = lp.vert.co
            lp[uv].uv = (co.x * 0.5 + 0.5, co.y * 0.5 + 0.5)


def link(name, bm, mats, smooth=True):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    for p in me.polygons:
        p.use_smooth = smooth
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    return ob


def paint_material(img):
    m = bpy.data.materials.new("Terrain")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.extension = "EXTEND"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.92
    return m


def flat_material(name, color, rough=0.86):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    return m


def build_terrain(field, mat):
    bm = bmesh.new()
    c = bm.verts.new((0, 0, 0))
    ring = [bm.verts.new(v) for v in hex_corners(R)]
    for i in range(6):
        bm.faces.new((c, ring[i], ring[(i + 1) % 6]))
    bmesh.ops.subdivide_edges(bm, edges=list(bm.edges), cuts=GRID // 6, use_grid_fill=True)
    for v in bm.verts:
        x, y = v.co.x, v.co.y
        d = math.hypot(x, y)
        h = sample(field, x, y)
        h *= min(1.0, max(0.0, (d - CLEAR_R) / 0.10))          # claro para la ficha
        edge = 1.0 - min(1.0, max(0.0, (hex_dist(x, y) - 0.93) / 0.07))
        v.co.z = SLAB_H + (FLOOR_H - SLAB_H) * edge + max(h, -0.02) * edge
    top_uv(bm)
    ob = link("Terrain", bm, [mat])
    mod = ob.modifiers.new("dec", "DECIMATE")
    mod.ratio = DECIMATE
    mod.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    top_uv(bm)
    bm.to_mesh(ob.data)
    bm.free()
    return ob


def build_side(mat):
    bm = bmesh.new()
    top = [bm.verts.new((c.x, c.y, SLAB_H)) for c in hex_corners(R)]
    bot = [bm.verts.new((c.x, c.y, 0.0)) for c in hex_corners(R)]
    for i in range(6):
        j = (i + 1) % 6
        bm.faces.new((bot[i], bot[j], top[j], top[i]))
    bm.faces.new(list(reversed(bot)))
    return link("Side", bm, [mat], smooth=False)


def boulder(name, field, x, y, size, mat):
    """Roca: icoesfera con ruido en capas y lascas, apoyada en el relieve."""
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=3, radius=1.0)
    off = Vector((rng.random() * 90, rng.random() * 90, rng.random() * 90))
    squash = rng.uniform(0.55, 0.85)
    stretch = rng.uniform(0.75, 1.0)
    for v in bm.verts:
        p = v.co.copy()
        n1 = noise.noise(p * 1.3 + off)
        n2 = noise.noise(p * 3.2 + off * 1.7) * 0.35
        ridge = -abs(noise.noise(p * 2.1 - off)) * 0.10
        v.co = p * (1.0 + 0.32 * n1 + 0.12 * n2 + ridge)
        v.co.z = max(v.co.z * squash, -0.1)
    rot = Euler((0, 0, rng.random() * math.tau))
    base_z = SLAB_H + (FLOOR_H - SLAB_H) + sample(field, x, y)
    for v in bm.verts:
        q = Vector((v.co.x * size, v.co.y * size * stretch, (v.co.z + 0.1) * size))
        q.rotate(rot)
        v.co = q + Vector((x, y, base_z - 0.004))
    top_uv(bm)
    return link(name, bm, [mat])


def scatter_boulders(field, px, mat):
    obs = []
    tries = 0
    while len(obs) < 26 and tries < 4000:
        tries += 1
        a = rng.random() * math.tau
        rr = rng.uniform(0.32, 0.86)
        x, y = math.cos(a) * rr, math.sin(a) * rr
        if hex_dist(x, y) > 0.88:
            continue
        col = color_at(px, x, y)
        sat = (col.max() - col.min()) / max(col.max(), 1e-4)
        if col[1] > max(col[0], col[2]) and sat > 0.3:
            continue  # no sobre arbustos
        on_floor = rr < 0.45
        size = rng.uniform(0.028, 0.055) if on_floor else rng.uniform(0.045, 0.11)
        obs.append(boulder("Rock_%02d" % len(obs), field, x, y, size, mat))
    return obs


def rock_palette(px):
    """Color medio y desvío de la roca pintada (poca saturación, ni sombra ni luz)."""
    small = px[::4, ::4].reshape(-1, 3)
    mx, mn = small.max(1), small.min(1)
    sat = (mx - mn) / np.maximum(mx, 1e-4)
    sel = small[(sat < 0.32) & (mx > 0.48) & (mx < 0.93)]
    if len(sel) < 50:
        sel = small
    return sel.mean(0), sel.std(0)


def tint_boulder_texture(img, px, ao_img):
    """Lleva el albedo escaneado a la paleta de la pintura y le suma su AO.

    Conserva el detalle (vetas, grietas) pero con el tono y el contraste de la
    roca pintada, para que no se vea fotográfica al lado del resto.
    """
    w, h = img.size
    a = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    rgb = a[..., :3]
    lum = rgb @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    mean, std = rock_palette(px)
    z = (lum - lum.mean()) / max(float(lum.std()), 1e-4)
    warm = np.array([1.06, 0.95, 0.80], dtype=np.float32)  # luz cálida de la pintura
    painted = (mean * warm * 0.90)[None, None, :] + z[..., None] * (std.mean() * 1.20)
    gain = float(mean.mean()) / max(float(rgb.mean()), 1e-4)
    out = painted * 0.78 + rgb * gain * 0.22
    if ao_img is not None:
        ao = np.array(ao_img.pixels[:], dtype=np.float32).reshape(h, w, 4)[..., 0]
        out *= (0.72 + 0.28 * ao)[..., None]
    a[..., :3] = np.clip(out, 0, 1)
    img.pixels[:] = a.ravel()
    img.update()
    img.pack()


def import_boulder(px):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=BOULDER)
    meshes = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    ob = meshes[0]
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    ob.parent = None
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in bpy.data.objects:
        if o not in before and o is not ob:
            bpy.data.objects.remove(o)
    me = ob.data
    # El glTF parte los vértices en cada costura de UV; sin unirlos el
    # decimate no puede colapsar a través de ellas. Las UV viven en los loops,
    # así que sobreviven a la unión.
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(me)
    bm.free()
    if me.has_custom_normals:
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    me.calc_loop_triangles()
    print("[hex_piedra] boulder original tris=%d" % len(me.loop_triangles))
    mod = ob.modifiers.new("dec", "DECIMATE")
    mod.ratio = min(1.0, BOULDER_TRIS / max(1, len(me.loop_triangles)))
    bpy.ops.object.modifier_apply(modifier=mod.name)
    me.calc_loop_triangles()
    print("[hex_piedra] boulder decimada tris=%d" % len(me.loop_triangles))
    # centrar en XY, base en z=0, largo mayor = 1
    vs = np.array([v.co[:] for v in me.vertices])
    lo, hi = vs.min(0), vs.max(0)
    span = max(hi[0] - lo[0], hi[1] - lo[1])
    shift = Vector(((lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, lo[2]))
    for v in me.vertices:
        v.co = (v.co - shift) / span
    mat = me.materials[0]
    mat.name = "Boulder"
    diff = ao = None
    for n in mat.node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.image is not None:
            nm = n.image.name.lower()
            if "diff" in nm:
                diff = n.image
    ao_path = BOULDER.replace("boulder_01_1k.gltf", "textures/boulder_01_arm_1k.jpg")
    if os.path.exists(ao_path):
        ao = bpy.data.images.load(ao_path)
    if diff is not None:
        tint_boulder_texture(diff, px, ao)
    for p in me.polygons:
        p.use_smooth = True
    ob.name = "Boulder_00"
    me.name = "Boulder"
    return ob


def place_boulders(src, field):
    obs = []
    for i, (ang, rr, size, spin) in enumerate(BOULDER_SPOTS):
        ob = src if i == 0 else src.copy()
        if i:
            ob.name = "Boulder_%02d" % i
            bpy.context.collection.objects.link(ob)
        x = math.cos(math.radians(ang)) * rr
        y = math.sin(math.radians(ang)) * rr
        ground = SLAB_H + (FLOOR_H - SLAB_H) + sample(field, x, y)
        ob.scale = (size, size, size * 0.85)
        ob.rotation_euler = (0, 0, math.radians(spin))
        ob.location = (x, y, ground - size * 0.12)   # algo enterrada, no apoyada
        obs.append(ob)
    return obs


def clear_near(rocks, spots):
    keep = []
    for r in rocks:
        c = Vector(np.array([v.co[:] for v in r.data.vertices]).mean(0))
        near = False
        for ang, rr, size, _ in spots:
            bx = math.cos(math.radians(ang)) * rr
            by = math.sin(math.radians(ang)) * rr
            if math.hypot(c.x - bx, c.y - by) < size * 0.75 + 0.05:
                near = True
        if near:
            bpy.data.objects.remove(r)
        else:
            keep.append(r)
    return keep


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    return ob


def stats():
    tris = 0
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            o.data.calc_loop_triangles()
            tris += len(o.data.loop_triangles)
    print("[hex_piedra] tris=%d" % tris)


def export(path):
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True,
                              export_yup=True, export_image_format="JPEG",
                              export_jpeg_quality=90)
    print("[hex_piedra] exportado", path)


def preview(path):
    scn = bpy.context.scene
    for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            scn.render.engine = eng
            break
        except TypeError:
            continue
    scn.render.resolution_x = 1000
    scn.render.resolution_y = 760
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.62, 0.78, 0.76, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.55
    scn.world = world
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(48), 0, math.radians(-32))
    bpy.context.collection.objects.link(sun)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.location = (0.0, -2.1, 1.75)
    cam.rotation_euler = (math.radians(52), 0, 0)
    bpy.context.collection.objects.link(cam)
    scn.camera = cam
    scn.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("[hex_piedra] preview", path)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    img, px = load_paint()
    field = height_field(px)
    m_paint = paint_material(img)
    m_side = flat_material("Side", (0.14, 0.07, 0.035))
    build_side(m_side)
    terrain = build_terrain(field, m_paint)
    rocks = scatter_boulders(field, px, m_paint)
    rocks = clear_near(rocks, BOULDER_SPOTS)
    join([terrain] + rocks, "Quarry")
    place_boulders(import_boulder(px), field)
    stats()
    export(OUT_GLB)
    if OUT_PNG:
        preview(OUT_PNG)


# hex_piedra_roca.py importa este archivo como módulo para reusar el terreno.
if __name__ == "__main__":
    main()
