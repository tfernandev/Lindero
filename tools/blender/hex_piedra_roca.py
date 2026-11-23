"""Variante de la loseta de piedra con Boulder 01 integrada en un lateral.

Roca: "Boulder 01" de Poly Haven (CC0, Rico Cilliers,
https://polyhaven.com/a/boulder_01), malla y texturas originales.

Cómo se integra (no es una roca apoyada encima):
  - Malla baja (2.6k tris) sacada de la original (66k) y UV nuevas limpias;
    difusa, normal y ARM originales se hornean de la alta a la baja.
  - Eje largo paralelo al lateral trasero-izquierdo (normal a 120°), escalada
    con las medidas reales de la loseta (radio 1 = 82 u en Godot, apotema 0.866).
  - Su cara exterior se comprime suave contra el borde (rodilla tanh): abraza
    el lateral sin salirse del hexágono ni mostrar un corte plano.
  - Enterrada un cuarto de su alto; el terreno sube a su encuentro (faldón),
    así emerge del suelo.
  - Las caras que quedan enteras bajo el terreno se borran.
  - Fragmentos de la misma roca al pie, del lado de adentro (mismo material:
    un solo draw call para toda la roca).

Uso:
  blender -b --factory-startup --python tools/blender/hex_piedra_roca.py -- \
      <salida.glb> <carpeta_capturas> <proyecto.blend>

No pisa hex_piedra_v2.glb: table_board.gd usa esta variante en una sola
casilla (HEX_TILE_AT).
"""
import math
import os
import random
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector, kdtree, noise
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hex_piedra as base  # noqa: E402  (terreno, pintura, zócalo)

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_GLB = ARGS[0] if len(ARGS) > 0 else "hex_piedra_roca.glb"
OUT_DIR = ARGS[1] if len(ARGS) > 1 else ""
OUT_BLEND = ARGS[2] if len(ARGS) > 2 else ""
ORIGINAL_GLB = os.path.join(base.ROOT, "models", "tiles", "hex_piedra_v2.glb")

APOTHEM = math.sqrt(3) / 2
EDGE_DEG = 120.0          # lateral elegido: atrás a la izquierda (lejos de la cámara)
ROCK_LEN = 0.70           # largo sobre el lateral (el lado mide 1.0)
ROCK_DEPTH = 0.46         # cuánto entra hacia el centro
ROCK_H = 0.46             # alto total (≈ 38 u en Godot; la ficha está a 6.8)
TILT_DEG = 14.0           # sube hacia el borde: afloramiento, no roca apoyada
ROCK_N = 0.645            # centro de la roca sobre la normal del lateral
BURY = 0.30               # fracción del alto bajo tierra
CLAMP_KNEE = 0.70         # desde acá (en apotemas) empieza a comprimirse
CLAMP_LIMIT = 0.965       # nunca pasa de acá: queda una franja de terreno al borde
SKIRT_H = 0.045           # cuánto sube el terreno al pie de la roca
SKIRT_R = 0.12
ROCK_TRIS = 2600
CHIP_TRIS = 300
BAKE_SIZE = 1024
ROCK_TINT = (1.0, 0.92, 0.80, 1.0)
DIFF_GAIN = 1.10          # la difusa escaneada es más oscura que la pintura
DIFF_SAT = 0.80           # baja el naranja del liquen
NORMAL_STRENGTH = 0.65    # detalle más suave, cerca del estilo pintado
CHIP_KEEP = 0.46          # los fragmentos no se acercan más que esto al centro
TOKEN_DISC = 0.21         # disco de la ficha: 17 u / 82 u

rng = random.Random(23)


def edge_normal(deg):
    a = math.radians(deg)
    return Vector((math.cos(a), math.sin(a), 0.0))


NORMALS = [edge_normal(60 * i) for i in range(6)]
N_MAIN = edge_normal(EDGE_DEG)
# tangente elegida para que la base (T, N, Z) sea de mano derecha: con
# determinante -1 la roca saldría espejada y con las caras al revés.
T_MAIN = Vector((N_MAIN.y, -N_MAIN.x, 0.0))


def smoothstep(e0, e1, x):
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def select_only(*objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[-1]


# ------------------------------------------------------------ roca original
def import_high():
    """Boulder 01 tal cual viene de Poly Haven (malla y material originales)."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=base.BOULDER)
    new = [o for o in bpy.data.objects if o not in before]
    ob = next(o for o in new if o.type == "MESH")
    for o in new:
        if o is not ob:
            bpy.data.objects.remove(o)
    ob.parent = None
    select_only(ob)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    ob.name = "Boulder01_original"
    return ob


def decimated_copy(src, target_tris, name):
    me = src.data.copy()
    me.name = name
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    # El glTF parte vértices en las costuras de UV: se unen para que el
    # decimate pueda colapsar. Las UV buenas salen del bake.
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(me)
    bm.free()
    select_only(ob)
    if me.has_custom_normals:
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    me.calc_loop_triangles()
    n0 = len(me.loop_triangles)
    mod = ob.modifiers.new("dec", "DECIMATE")
    mod.ratio = min(1.0, target_tris / max(1, n0))
    mod.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=mod.name)
    # El original viene doubleSided y con caras invertidas; con culling de caras
    # traseras (más barato en móvil) se vería hueca. Normales hacia afuera.
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    me.calc_loop_triangles()
    print("[roca] %s: %d -> %d tris" % (name, n0, len(me.loop_triangles)))
    for p in me.polygons:
        p.use_smooth = True
    return ob


def new_image(name, size, non_color):
    img = bpy.data.images.new(name, size, size, alpha=False)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    return img


def bake_rock(high, low, size=BAKE_SIZE):
    """Hornea difusa, normal y ARM originales sobre la malla baja con UV limpias."""
    scn = bpy.context.scene
    scn.render.engine = "CYCLES"
    scn.cycles.device = "CPU"
    scn.cycles.samples = 4
    select_only(low)
    while low.data.uv_layers:
        low.data.uv_layers.remove(low.data.uv_layers[0])
    low.data.uv_layers.new(name="UVMap")
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.006, scale_to_bounds=True)
    bpy.ops.object.mode_set(mode="OBJECT")

    hnt = high.data.materials[0].node_tree
    # El importador llama "boulder_01_rough" a la textura ARM (metallicRoughness).
    arm_src = next(n for n in hnt.nodes if n.type == "TEX_IMAGE"
                   and any(lk.to_node.type == "SEPARATE_COLOR" for lk in n.outputs["Color"].links))

    imgs = {"diff": new_image("boulder_roca_diff", size, False),
            "nor": new_image("boulder_roca_nor", size, True),
            "arm": new_image("boulder_roca_arm", size, True)}
    m = bpy.data.materials.new("Boulder")
    m.use_nodes = True
    nt = m.node_tree
    tex = {}
    for k, img in imgs.items():
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = img
        tex[k] = t
    low.data.materials.clear()
    low.data.materials.append(m)

    def run(kind, key, **kw):
        nt.nodes.active = tex[key]
        select_only(high, low)
        bpy.ops.object.bake(type=kind, use_selected_to_active=True, cage_extrusion=0.03,
                            max_ray_distance=0.12, margin=8, **kw)

    run("DIFFUSE", "diff", pass_filter={"COLOR"})
    run("NORMAL", "nor", normal_space="TANGENT")
    # ARM por emisión: R=AO, G=rugosidad, B=metal, sin que pase por la luz.
    out = next(n for n in hnt.nodes if n.type == "OUTPUT_MATERIAL")
    prev = [lk.from_socket for lk in hnt.links if lk.to_node == out and lk.to_socket.name == "Surface"]
    emit = hnt.nodes.new("ShaderNodeEmission")
    hnt.links.new(arm_src.outputs["Color"], emit.inputs["Color"])
    hnt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    run("EMIT", "arm")
    if prev:
        hnt.links.new(prev[0], out.inputs["Surface"])
    grade_diffuse(imgs["diff"])
    for img in imgs.values():
        img.pack()
    print("[roca] bake %dx%d listo (difusa, normal, ARM)" % (size, size))
    return m, tex


def grade_diffuse(img):
    """Lleva la difusa horneada al valor y saturación de la roca pintada."""
    w, h = img.size
    a = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    rgb = a[..., :3]
    lum = (rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32))[..., None]
    rgb = lum + (rgb - lum) * DIFF_SAT
    a[..., :3] = np.clip(rgb * DIFF_GAIN, 0, 1)
    img.pixels[:] = a.ravel()
    img.update()


def finish_material(m, tex):
    """Material mate de la roca con las texturas horneadas."""
    m.use_backface_culling = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    mix.inputs["B"].default_value = ROCK_TINT      # se exporta como factor de color glTF
    nt.links.new(tex["diff"].outputs["Color"], mix.inputs["A"])
    nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nm.inputs["Strength"].default_value = NORMAL_STRENGTH   # -> normalTexture.scale
    nt.links.new(tex["nor"].outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(tex["arm"].outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    group = bpy.data.node_groups.get("glTF Material Output")
    if group is None:
        group = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
        group.interface.new_socket("Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
        group.interface.new_socket("Thickness", in_out="INPUT", socket_type="NodeSocketFloat")
    gn = nt.nodes.new("ShaderNodeGroup")
    gn.node_tree = group
    nt.links.new(sep.outputs["Red"], gn.inputs["Occlusion"])


def principal_frame(me):
    """Centra en XY, base en z=0 y alinea el eje horizontal más largo con X."""
    co = np.array([v.co[:] for v in me.vertices])
    xy = co[:, :2] - co[:, :2].mean(0)
    w, vecs = np.linalg.eigh(np.cov(xy.T))
    major = vecs[:, np.argmax(w)]
    me.transform(Matrix.Translation((-co[:, 0].mean(), -co[:, 1].mean(), -co[:, 2].min())))
    me.transform(Matrix.Rotation(-math.atan2(major[1], major[0]), 4, "Z"))
    co = np.array([v.co[:] for v in me.vertices])
    me.transform(Matrix.Translation((-(co[:, 0].max() + co[:, 0].min()) / 2,
                                     -(co[:, 1].max() + co[:, 1].min()) / 2, 0)))
    co = np.array([v.co[:] for v in me.vertices])
    return co.max(0) - co.min(0)


# ------------------------------------------------------------ integración
def soft_clamp(p, knee, limit):
    """Comprime suave todo lo que pase de `knee` apotemas, sin superar `limit`."""
    k, lim = knee * APOTHEM, limit * APOTHEM
    for n in NORMALS:
        t = p.x * n.x + p.y * n.y
        if t > k:
            t2 = k + (lim - k) * math.tanh((t - k) / (lim - k))
            p.x += (t2 - t) * n.x
            p.y += (t2 - t) * n.y
    return p


def ground(field, x, y):
    """Altura del terreno tal como la arma base.build_terrain."""
    d = math.hypot(x, y)
    h = base.sample(field, x, y)
    h *= min(1.0, max(0.0, (d - base.CLEAR_R) / 0.10))
    edge = 1.0 - min(1.0, max(0.0, (base.hex_dist(x, y) - 0.93) / 0.07))
    return base.SLAB_H + (base.FLOOR_H - base.SLAB_H) * edge + max(h, -0.02) * edge


def shape_main_rock(ob, field):
    me = ob.data
    size = principal_frame(me)
    me.transform(Matrix.Diagonal((ROCK_LEN / size[0], ROCK_DEPTH / size[1], ROCK_H / size[2], 1.0)))
    # inclinada: el lado de afuera (+Y local) sube, el de adentro se hunde
    me.transform(Matrix.Rotation(math.radians(TILT_DEG), 4, "X"))
    # eje largo (X) -> tangente del lateral; Y -> hacia afuera
    me.transform(Matrix(((T_MAIN.x, N_MAIN.x, 0, 0), (T_MAIN.y, N_MAIN.y, 0, 0),
                         (0, 0, 1, 0), (0, 0, 0, 1))))
    cx, cy = N_MAIN.x * ROCK_N, N_MAIN.y * ROCK_N
    me.transform(Matrix.Translation((cx, cy, ground(field, cx, cy) - BURY * ROCK_H)))
    for v in me.vertices:
        soft_clamp(v.co, CLAMP_KNEE, CLAMP_LIMIT)
        v.co.z = max(v.co.z, 0.012)


def skirt(field, rock):
    """Sube el terreno al pie de la roca para que emerja del suelo."""
    contact = [(v.co.x, v.co.y) for v in rock.data.vertices
               if ground(field, v.co.x, v.co.y) - 0.03 < v.co.z < ground(field, v.co.x, v.co.y) + 0.05]
    tree = kdtree.KDTree(len(contact))
    for i, (x, y) in enumerate(contact):
        tree.insert((x, y, 0.0), i)
    tree.balance()
    n = field.shape[0]
    out = field.copy()
    for iy in range(n):
        y = (iy + 0.5) / n * 2 - 1
        for ix in range(n):
            x = (ix + 0.5) / n * 2 - 1
            if math.hypot(x, y) < base.CLEAR_R + 0.10:
                continue
            _, _, d = tree.find((x, y, 0.0))
            if d < SKIRT_R:
                jitter = 0.65 + 0.35 * noise.noise(Vector((x * 9, y * 9, 0.3)))
                out[iy, ix] += SKIRT_H * jitter * (1.0 - smoothstep(0.0, SKIRT_R, d))
    print("[roca] faldón: %d puntos de contacto" % len(contact))
    return out


def chips(field, src, n=6):
    """Fragmentos de la misma roca (ya horneada) al pie, del lado de adentro."""
    size = principal_frame(src.data)
    spots = []
    tries = 0
    while len(spots) < n and tries < 400:
        tries += 1
        along = rng.uniform(-0.40, 0.40)
        inward = rng.uniform(0.17, 0.30)
        p = N_MAIN * (ROCK_N - inward) + T_MAIN * along * ROCK_LEN
        if p.length < CHIP_KEEP or base.hex_dist(p.x, p.y) > 0.86:
            continue
        if any((p - q).length < 0.07 for q, _ in spots):
            continue
        spots.append((p, rng.uniform(0.035, 0.075)))
    out = []
    span = float(max(size))
    for i, (p, s) in enumerate(spots):
        me = src.data.copy()
        ob = bpy.data.objects.new("Chip_%d" % i, me)
        bpy.context.collection.objects.link(ob)
        # los escaneos no tienen fondo: sin inclinar y bien enterrados, así
        # nunca se ve la base abierta
        me.transform(Matrix.Diagonal((s / span, s / span, 0.85 * s / span, 1.0)))
        me.transform(Matrix.Rotation(rng.random() * math.tau, 4, "Z"))
        me.transform(Matrix.Translation((p.x, p.y, ground(field, p.x, p.y) - s * 0.40)))
        for v in me.vertices:
            v.co.z = max(v.co.z, 0.012)
        out.append(ob)
    bpy.data.objects.remove(src)
    return out


def cull_buried(rock, terrain):
    """Borra las caras que quedan enteras bajo el terreno."""
    bvh = BVHTree.FromObject(terrain, bpy.context.evaluated_depsgraph_get())
    bm = bmesh.new()
    bm.from_mesh(rock.data)
    hidden = {}
    for v in bm.verts:
        hit = bvh.ray_cast(Vector((v.co.x, v.co.y, 2.0)), Vector((0, 0, -1)))
        hidden[v.index] = hit[0] is not None and v.co.z < hit[0].z - 0.006
    dead = [f for f in bm.faces if all(hidden[v.index] for v in f.verts)]
    total = len(bm.faces)
    bmesh.ops.delete(bm, geom=dead, context="FACES")
    bm.to_mesh(rock.data)
    bm.free()
    print("[roca] caras enterradas borradas: %d de %d" % (len(dead), total))


def drop_pebbles_under(pebbles, rock):
    tree = kdtree.KDTree(len(rock.data.vertices))
    for i, v in enumerate(rock.data.vertices):
        tree.insert((v.co.x, v.co.y, 0.0), i)
    tree.balance()
    keep = []
    for p in pebbles:
        c = np.array([v.co[:] for v in p.data.vertices])
        mid = c.mean(0)
        r = float(np.max(np.linalg.norm(c[:, :2] - mid[:2], axis=1)))
        _, _, d = tree.find((mid[0], mid[1], 0.0))
        if d < r + 0.03:
            bpy.data.objects.remove(p)
        else:
            keep.append(p)
    return keep


# ------------------------------------------------------------ validación
def validate(objs):
    ok = True
    for ob in objs:
        co = np.array([v.co[:] for v in ob.data.vertices])
        hd = max(base.hex_dist(x, y) for x, y, _ in co)
        print("[valida] %-8s verts=%d hex_dist_max=%.4f z=[%.4f, %.4f] |x|max=%.4f |y|max=%.4f" % (
            ob.name, len(co), hd, co[:, 2].min(), co[:, 2].max(), np.abs(co[:, 0]).max(), np.abs(co[:, 1]).max()))
        if hd > 1.002 or co[:, 2].min() < -1e-4:
            ok = False
        if ob.name == "Boulder":
            if hd > CLAMP_LIMIT + 0.01:
                ok = False
            near = float(np.min(np.hypot(co[:, 0], co[:, 1])))
            print("[valida] roca: punto más cercano al centro = %.3f (disco de la ficha %.2f)" % (near, TOKEN_DISC))
            if near < TOKEN_DISC + 0.08:
                ok = False
    print("[valida] dentro del hexágono, sin tocar la ficha: %s" % ("OK" if ok else "FALLA"))
    return ok


def tri_report():
    total = 0
    for ob in bpy.context.scene.objects:
        if ob.type == "MESH":
            ob.data.calc_loop_triangles()
            total += len(ob.data.loop_triangles)
            print("[tris] %-8s %d  materiales=%d" % (ob.name, len(ob.data.loop_triangles), len(ob.data.materials)))
    print("[tris] total %d" % total)


# ------------------------------------------------------------ capturas
VIEWS = {
    "frente": (-90, 40, 2.6),
    "tres_cuartos": (-55, 32, 2.5),
    "atras": (100, 28, 2.5),
    "lateral": (25, 20, 2.4),
    "arriba": (-90, 86, 3.4),
    "ras": (-120, 9, 2.3),
}


def setup_stage():
    scn = bpy.context.scene
    for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            scn.render.engine = eng
            break
        except TypeError:
            continue
    scn.render.resolution_x = 960
    scn.render.resolution_y = 720
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.66, 0.74, 0.72, 1)
    bg.inputs[1].default_value = 0.65
    scn.world = world
    sun = bpy.data.objects.new("Sol", bpy.data.lights.new("Sol", "SUN"))
    sun.data.energy = 3.2
    sun.data.color = (1.0, 0.93, 0.82)       # cálida
    sun.data.angle = math.radians(9)         # sombras suaves
    sun.rotation_euler = (math.radians(42), 0, math.radians(-35))
    bpy.context.collection.objects.link(sun)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.lens = 50
    bpy.context.collection.objects.link(cam)
    scn.camera = cam
    return cam


def shoot(cam, prefix):
    if not OUT_DIR:
        return
    target = Vector((0, 0, 0.12))
    for name, (az, el, dist) in VIEWS.items():
        a, e = math.radians(az), math.radians(el)
        cam.location = target + Vector((math.cos(a) * math.cos(e), math.sin(a) * math.cos(e), math.sin(e))) * dist
        cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
        bpy.context.scene.render.filepath = os.path.join(OUT_DIR, "%s_%s.png" % (prefix, name))
        bpy.ops.render.render(write_still=True)
    print("[captura] %s: %d vistas" % (prefix, len(VIEWS)))


def render_glb(path, prefix):
    """Abre el GLB exportado en una escena limpia y lo fotografía (valida el export)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    shoot(setup_stage(), prefix)


# ------------------------------------------------------------ armado
def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    img, px = base.load_paint()
    field = base.height_field(px)
    m_paint = base.paint_material(img)
    base.build_side(base.flat_material("Side", (0.14, 0.07, 0.035)))

    high = import_high()
    rock = decimated_copy(high, ROCK_TRIS, "Boulder")
    mat, tex = bake_rock(high, rock)
    finish_material(mat, tex)
    bpy.data.objects.remove(high)

    chip_src = decimated_copy(rock, CHIP_TRIS, "Chip")   # antes de deformar
    shape_main_rock(rock, field)
    field2 = skirt(field, rock)
    pieces = chips(field2, chip_src)

    terrain = base.build_terrain(field2, m_paint)
    pebbles = drop_pebbles_under(base.scatter_boulders(field2, px, m_paint), rock)
    quarry = base.join([terrain] + pebbles, "Quarry")

    rock = base.join([rock] + pieces, "Boulder")
    rock.data.name = "Boulder"
    cull_buried(rock, quarry)

    good = validate([o for o in bpy.context.scene.objects if o.type == "MESH"])
    tri_report()
    base.export(OUT_GLB)
    cam = setup_stage()
    if OUT_BLEND:
        bpy.ops.file.pack_all()
        bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND, compress=True)
        print("[roca] blend", OUT_BLEND)
    if OUT_DIR:
        # se fotografía el GLB exportado (no la escena), así se valida el export
        render_glb(OUT_GLB, "glb_variante")
        if not os.path.exists(os.path.join(OUT_DIR, "glb_original_ras.png")):
            render_glb(ORIGINAL_GLB, "glb_original")
    if not good:
        sys.exit(2)


main()
