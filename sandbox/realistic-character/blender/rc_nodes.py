"""A small expression builder over Blender's shader nodes, so a painted layer reads as one line of maths."""

import bpy


class G:
    """Builds nodes in one tree. Values passed to an input may be a socket, a float or a colour tuple."""

    def __init__(self, tree):
        self.t = tree
        self.n = tree.nodes
        self._coord = None

    def node(self, kind, **props):
        nd = self.n.new(kind)
        for k, v in props.items():
            setattr(nd, k, v)
        return nd

    def set(self, sock, v):
        if v is None:
            return
        if isinstance(v, bpy.types.NodeSocket):
            self.t.links.new(v, sock)
        elif isinstance(v, (tuple, list)) and len(v) == 3 and sock.type == "RGBA":
            sock.default_value = (*v, 1.0)
        else:
            sock.default_value = v

    def coord(self):
        if self._coord is None:
            self._coord = self.node("ShaderNodeTexCoord").outputs["Object"]
        return self._coord

    def attr(self, name):
        return self.node("ShaderNodeAttribute", attribute_name=name).outputs[2]

    def math(self, op, a, b=None, c=None, clamp=False):
        nd = self.node("ShaderNodeMath", operation=op, use_clamp=clamp)
        self.set(nd.inputs[0], a)
        self.set(nd.inputs[1], b)
        self.set(nd.inputs[2], c)
        return nd.outputs[0]

    def mul(self, a, b):
        return self.math("MULTIPLY", a, b)

    def add(self, a, b):
        return self.math("ADD", a, b)

    def sub(self, a, b):
        return self.math("SUBTRACT", a, b)

    def sat(self, a):
        return self.math("ADD", a, 0.0, clamp=True)

    def ramp(self, x, e0, e1, lo=0.0, hi=1.0):
        """Smoothstep of x from e0..e1, mapped to lo..hi."""
        nd = self.node("ShaderNodeMapRange", interpolation_type="SMOOTHSTEP")
        self.set(nd.inputs[0], x)
        for i, v in zip((1, 2, 3, 4), (e0, e1, lo, hi)):
            nd.inputs[i].default_value = v
        return nd.outputs[0]

    def mixf(self, a, b, f):
        nd = self.node("ShaderNodeMix", data_type="FLOAT")
        self.set(nd.inputs[0], f)
        self.set(nd.inputs[2], a)
        self.set(nd.inputs[3], b)
        return nd.outputs[0]

    def mixc(self, a, b, f, blend="MIX"):
        nd = self.node("ShaderNodeMix", data_type="RGBA", blend_type=blend)
        self.set(nd.inputs[0], f)
        self.set(nd.inputs[6], a)
        self.set(nd.inputs[7], b)
        return nd.outputs[2]

    def mapping(self, scale=(1, 1, 1), vec=None):
        nd = self.node("ShaderNodeMapping")
        self.t.links.new(vec or self.coord(), nd.inputs[0])
        nd.inputs[3].default_value = scale
        return nd.outputs[0]

    def noise(self, scale, detail=3.0, rough=0.5, vec=None, stretch=None, colour=False):
        nd = self.node("ShaderNodeTexNoise")
        v = self.mapping(stretch) if stretch else (vec or self.coord())
        self.t.links.new(v, nd.inputs["Vector"])
        nd.inputs["Scale"].default_value = scale
        nd.inputs["Detail"].default_value = detail
        nd.inputs["Roughness"].default_value = rough
        return nd.outputs[1 if colour else 0]

    def voronoi(self, scale, feature="F1", randomness=1.0, out=0, vec=None):
        nd = self.node("ShaderNodeTexVoronoi", feature=feature)
        self.t.links.new(vec or self.coord(), nd.inputs["Vector"])
        nd.inputs["Scale"].default_value = scale
        nd.inputs["Randomness"].default_value = randomness
        return nd.outputs[out]

    def image(self, img, uv=None, interp="Linear"):
        nd = self.node("ShaderNodeTexImage", image=img, interpolation=interp)
        if uv is not None:
            self.t.links.new(uv, nd.inputs[0])
        return nd

    def sep(self, col):
        nd = self.node("ShaderNodeSeparateColor")
        self.t.links.new(col, nd.inputs[0])
        return nd.outputs

    def link(self, a, b):
        self.t.links.new(a, b)

    def xyz(self):
        nd = self.node("ShaderNodeSeparateXYZ")
        self.t.links.new(self.coord(), nd.inputs[0])
        return nd.outputs

    def dist(self, point):
        nd = self.node("ShaderNodeVectorMath", operation="DISTANCE")
        self.t.links.new(self.coord(), nd.inputs[0])
        nd.inputs[1].default_value = point
        return nd.outputs["Value"]

    def dot(self, axis):
        nd = self.node("ShaderNodeVectorMath", operation="DOT_PRODUCT")
        self.t.links.new(self.coord(), nd.inputs[0])
        nd.inputs[1].default_value = axis
        return nd.outputs["Value"]

    def pointiness(self):
        return self.node("ShaderNodeNewGeometry").outputs["Pointiness"]

    def ridge(self, n):
        """Fold-like ridges from a noise value: 1 - |2n - 1|."""
        return self.sub(1.0, self.math("ABSOLUTE", self.sub(self.mul(n, 2.0), 1.0)))


def new_material(name):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    t = m.node_tree
    if t is None:
        m.use_nodes = True
        t = m.node_tree
    t.nodes.clear()
    return m, G(t)


def principled(g):
    out = g.node("ShaderNodeOutputMaterial")
    p = g.node("ShaderNodeBsdfPrincipled")
    g.link(p.outputs[0], out.inputs[0])
    return p, out
