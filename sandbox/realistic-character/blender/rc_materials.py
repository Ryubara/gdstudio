"""The game materials of the realistic character: Principled BSDFs fed by the baked texture sets, so Cycles, EEVEE
and the glTF export all read the same maps (kit docs: tools/blender/realistic-characters.md#materials)."""

import bpy

from rc_nodes import new_material, principled


def load(path, colour):
    img = bpy.data.images.load(path, check_existing=True)
    img.colorspace_settings.name = "sRGB" if colour else "Non-Color"
    return img


def texset(g, texdir, name, maps=("albedo", "normal", "orm")):
    out = {}
    for m in maps:
        out[m] = g.image(load(f"{texdir}/{name}_{m}.png", m == "albedo"))
    return out


def normal_map(g, colour, strength=1.0):
    n = g.node("ShaderNodeNormalMap")
    n.inputs["Strength"].default_value = strength
    g.link(colour, n.inputs["Color"])
    return n.outputs[0]


def skin(name, texdir, texname):
    m, g = new_material(name)
    p, _ = principled(g)
    t = texset(g, texdir, texname, ("albedo", "normal", "orm", "mask"))
    g.link(t["albedo"].outputs[0], p.inputs["Base Color"])
    orm = g.sep(t["orm"].outputs[0])
    mask = g.sep(t["mask"].outputs[0])
    g.link(orm[1], p.inputs["Roughness"])
    g.link(normal_map(g, t["normal"].outputs[0]), p.inputs["Normal"])
    p.subsurface_method = "RANDOM_WALK_SKIN"
    g.link(g.mul(mask[0], 0.85), p.inputs["Subsurface Weight"])
    p.inputs["Subsurface Radius"].default_value = (1.0, 0.32, 0.16)
    p.inputs["Subsurface Scale"].default_value = 0.0035
    p.inputs["Subsurface IOR"].default_value = 1.4
    p.inputs["Subsurface Anisotropy"].default_value = 0.8
    p.inputs["IOR"].default_value = 1.4
    g.link(g.mul(mask[1], 0.7), p.inputs["Coat Weight"])
    p.inputs["Coat Roughness"].default_value = 0.14
    p.inputs["Coat IOR"].default_value = 1.33
    g.t.nodes.active = t["albedo"]
    return m


def eye(texdir):
    m, g = new_material("eye")
    p, _ = principled(g)
    t = g.image(load(f"{texdir}/eye_albedo.png", True))
    g.link(t.outputs[0], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = 0.38
    p.inputs["Subsurface Weight"].default_value = 0.15
    p.inputs["Subsurface Radius"].default_value = (1.0, 0.4, 0.3)
    p.inputs["Subsurface Scale"].default_value = 0.002
    g.t.nodes.active = t
    return m


def clear_shell(name, ior, roughness=0.0):
    """A wet, clear layer (cornea, tear line): it refracts, and lets light through to what it covers."""
    m, g = new_material(name)
    out = g.node("ShaderNodeOutputMaterial")
    p = g.node("ShaderNodeBsdfPrincipled")
    p.inputs["Base Color"].default_value = (1, 1, 1, 1)
    p.inputs["Transmission Weight"].default_value = 1.0
    p.inputs["Roughness"].default_value = roughness
    p.inputs["IOR"].default_value = ior
    tr = g.node("ShaderNodeBsdfTransparent")
    lp = g.node("ShaderNodeLightPath")
    mix = g.node("ShaderNodeMixShader")
    g.link(lp.outputs["Is Shadow Ray"], mix.inputs[0])
    g.link(p.outputs[0], mix.inputs[1])
    g.link(tr.outputs[0], mix.inputs[2])
    g.link(mix.outputs[0], out.inputs[0])
    m.surface_render_method = "DITHERED"
    m.use_raytrace_refraction = True
    m.use_transparent_shadow = True
    return m


def occlusion():
    """The soft shadow the lids cast on the eye: black, as opaque as the `occ` vertex attribute says."""
    m, g = new_material("eye_occlusion")
    out = g.node("ShaderNodeOutputMaterial")
    d = g.node("ShaderNodeBsdfDiffuse")
    d.inputs[0].default_value = (0.0, 0.0, 0.0, 1)
    tr = g.node("ShaderNodeBsdfTransparent")
    mix = g.node("ShaderNodeMixShader")
    a = g.node("ShaderNodeAttribute", attribute_name="Color")
    g.link(a.outputs["Alpha"], mix.inputs[0])
    g.link(tr.outputs[0], mix.inputs[1])
    g.link(d.outputs[0], mix.inputs[2])
    g.link(mix.outputs[0], out.inputs[0])
    m.surface_render_method = "BLENDED"
    m.use_transparent_shadow = True
    return m


def hair(texdir):
    """Hair cards: the strand atlas with its alpha, a highlight stretched across the strands, both faces drawn."""
    m, g = new_material("hair")
    p, _ = principled(g)
    t = texset(g, texdir, "hair")
    orm = g.sep(t["orm"].outputs[0])
    shaded = g.mixc(t["albedo"].outputs[0], (0, 0, 0), g.ramp(orm[0], 0.4, 1.0, 0.6, 0.0))
    g.link(shaded, p.inputs["Base Color"])
    g.link(t["albedo"].outputs[1], p.inputs["Alpha"])
    g.link(orm[1], p.inputs["Roughness"])
    g.link(normal_map(g, t["normal"].outputs[0], 0.8), p.inputs["Normal"])
    p.inputs["Anisotropic"].default_value = 0.65
    p.inputs["IOR"].default_value = 1.55
    m.surface_render_method = "DITHERED"
    m.use_backface_culling = False
    m.use_transparent_shadow = True
    g.t.nodes.active = t["albedo"]
    return m


def pbr(name, texdir, texname, detail_scale=0.0, two_sided=False):
    """Clothes and gear: albedo, normal, ORM (occlusion, roughness, metallic) and, with `detail_scale`, a tiling
    weave normal laid over the faces the mask's red channel marks as cloth."""
    m, g = new_material(name)
    p, _ = principled(g)
    t = texset(g, texdir, texname, ("albedo", "normal", "orm") + (("mask",) if detail_scale else ()))
    g.link(t["albedo"].outputs[0], p.inputs["Base Color"])
    orm = g.sep(t["orm"].outputs[0])
    g.link(orm[1], p.inputs["Roughness"])
    g.link(orm[2], p.inputs["Metallic"])
    nrm = t["normal"].outputs[0]
    if detail_scale:
        uv = g.node("ShaderNodeUVMap")
        mp = g.node("ShaderNodeMapping")
        mp.inputs[3].default_value = (detail_scale, detail_scale, 1)
        g.link(uv.outputs[0], mp.inputs[0])
        d = g.image(load(f"{texdir}/detail_weave_normal.png", False), mp.outputs[0])
        off = g.node("ShaderNodeVectorMath", operation="SUBTRACT")
        g.link(d.outputs[0], off.inputs[0])
        off.inputs[1].default_value = (0.5, 0.5, 1.0)
        sc = g.node("ShaderNodeVectorMath", operation="SCALE")
        g.link(off.outputs[0], sc.inputs[0])
        g.link(g.mul(g.sep(t["mask"].outputs[0])[0], 0.5), sc.inputs["Scale"])
        add = g.node("ShaderNodeVectorMath", operation="ADD")
        g.link(nrm, add.inputs[0])
        g.link(sc.outputs[0], add.inputs[1])
        nrm = add.outputs[0]
    g.link(normal_map(g, nrm), p.inputs["Normal"])
    m.use_backface_culling = not two_sided
    g.t.nodes.active = t["albedo"]
    return m
