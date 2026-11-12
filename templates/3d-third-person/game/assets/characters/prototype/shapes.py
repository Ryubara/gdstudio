"""The skin of a prototype mannequin (kit #1149), made from a body's numbers. Pure numpy, no Blender.

Every part is a tube: rings of points round an axis, joined by quads and closed by a dome at each end. A ring is a
superellipse (its two half sizes and how boxy it is), so the same code draws a round limb, a flat palm and a faceted
low-poly thigh. Because the rings follow the bones, the weights are a function of where a ring is along its bone:
nothing is painted, and a body of other proportions skins the same way. Colours are palette cells per face.

Axes are Godot's: +Y up, +Z front, +X the character's left. Parts are built for the left side and mirrored.
"""

import math

import numpy as np

## Palette cells (`styles.py` gives each look its colours).
MAIN, PANEL, JOINT, LEFT, RIGHT, VISOR, PALM, SOLE, MARK = range(9)

X = np.array([1.0, 0.0, 0.0])
Y = np.array([0.0, 1.0, 0.0])
Z = np.array([0.0, 0.0, 1.0])

## The reference hand's finger radii (m), thumb to pinky.
FINGER_RADIUS = {"thumb": 0.0115, "index": 0.0098, "middle": 0.0102, "ring": 0.0096, "pinky": 0.0086}


def smooth(lo, hi, x):
    if hi == lo:
        return 1.0 if x >= hi else 0.0
    t = min(1.0, max(0.0, (x - lo) / (hi - lo)))
    return t * t * (3 - 2 * t)


class Soup:
    """Vertices, faces, a palette cell per face and bone weights per vertex."""

    def __init__(self):
        self.verts, self.weights, self.faces, self.cells = [], [], [], []

    def vertex(self, place, weights):
        total = sum(weights.values())
        self.verts.append(np.array(place, float))
        self.weights.append({b: w / total for b, w in weights.items() if w / total > 0.004})
        return len(self.verts) - 1

    def face(self, corners, cell):
        self.faces.append(tuple(corners))
        self.cells.append(cell)

    def mirror(self, first_vertex, first_face):
        """Copy everything from the two marks on across the body's middle, for the right side."""
        swap = {LEFT: RIGHT, RIGHT: LEFT}
        offset = len(self.verts) - first_vertex
        for i in range(first_vertex, first_vertex + offset):
            place = self.verts[i] * np.array([-1.0, 1.0, 1.0])
            self.vertex(place, {(b[:-2] + "_r" if b.endswith("_l") else b): w for b, w in self.weights[i].items()})
        for i in range(first_face, len(self.faces)):
            self.faces.append(tuple(c + offset for c in reversed(self.faces[i])))
            self.cells.append(swap.get(self.cells[i], self.cells[i]))


class Ring:
    """One ring of a tube: its middle, half sizes along the tube's two cross axes, boxiness, weights and the cell
    of the strip that starts at it. `back` is the half size on the far side of the second axis when it differs;
    `stripe` lets the tube's stripes paint that strip; a `minor` ring is left out of the lighter levels of detail."""

    def __init__(self, middle, a, b, weights, cell=MAIN, back=None, power=2.0, minor=False, stripe=False):
        self.middle, self.a, self.b, self.back = np.array(middle, float), a, b, back if back is not None else b
        self.weights, self.cell, self.power, self.minor, self.stripe = weights, cell, power, minor, stripe


def _phase(segments):
    """A four-sided tube is turned an eighth, so it is a box with a flat top and not a diamond."""
    return 0.5 if segments == 4 else 0.0


def _ring_points(ring, u, v, segments, shrink=1.0):
    points = []
    for k in range(segments):
        angle = 2 * math.pi * (k + _phase(segments)) / segments
        c, s = math.cos(angle), math.sin(angle)
        e = 2.0 / ring.power
        x = math.copysign(abs(c) ** e, c) * ring.a * shrink
        y = math.copysign(abs(s) ** e, s) * (ring.b if s >= 0 else ring.back) * shrink
        points.append(ring.middle + x * u + y * v)
    return points


def tube(soup, rings, axis, up, segments, domes=(0.0, 0.0), dome_rings=2, stripes=(), lod=0, fix=None, dome_cells=(None, None)):
    """Loft `rings` along `axis` (a unit vector); a ring's `b` lies along `up`, its `a` along up x axis.

    `domes` is how far the round end caps reach before the first ring and past the last. `stripes` paints the
    quads that face a direction, on every strip whose ring has `stripe`: (direction, cell, width in quads). `fix(place, weights)` may change a vertex's weights.
    Returns the index of the first vertex.
    """
    axis = np.array(axis, float) / np.linalg.norm(axis)
    v = np.array(up, float) - np.dot(up, axis) * axis
    v /= np.linalg.norm(v)
    u = np.cross(v, axis)
    rings = [r for r in rings if lod == 0 or not r.minor]
    rows = []  # (points, weights, cell of the strip that starts here)
    count = dome_rings
    for i in range(count, 0, -1):
        if domes[0] > 0:
            phi = math.pi / 2 * i / (count + 1)
            moved = Ring(rings[0].middle - axis * domes[0] * math.sin(phi), rings[0].a, rings[0].b, rings[0].weights, back=rings[0].back, power=rings[0].power)
            rows.append((_ring_points(moved, u, v, segments, math.cos(phi)), rings[0].weights, dome_cells[0] if dome_cells[0] is not None else rings[0].cell))
    first_strip = len(rows)
    for ring in rings:
        rows.append((_ring_points(ring, u, v, segments), ring.weights, ring.cell))
    last = rings[-1]
    end_cell = dome_cells[1] if dome_cells[1] is not None else last.cell
    for i in range(1, count + 1):
        if domes[1] > 0:
            phi = math.pi / 2 * i / (count + 1)
            moved = Ring(last.middle + axis * domes[1] * math.sin(phi), last.a, last.b, last.weights, back=last.back, power=last.power)
            rows.append((_ring_points(moved, u, v, segments, math.cos(phi)), last.weights, end_cell))
    start = len(soup.verts)
    index = []
    for points, weights, _cell in rows:
        ring_index = []
        for place in points:
            w = dict(weights)
            if fix is not None:
                w = fix(place, w)
            ring_index.append(soup.vertex(place, w))
        index.append(ring_index)
    painted = {}
    for direction, cell, width in stripes:
        d = np.array(direction, float)

        def facing(k, d=d, width=width):
            angle = 2 * math.pi * (k + _phase(segments) + 0.5 * width) / segments
            return np.dot(d, math.cos(angle) * u + math.sin(angle) * v)

        best = max(range(segments), key=facing)
        for strip, ring in enumerate(rings[:-1]):
            if ring.stripe:
                for k in range(width):
                    painted[(first_strip + strip, (best + k) % segments)] = cell
    for i in range(len(rows) - 1):
        for k in range(segments):
            n = (k + 1) % segments
            soup.face((index[i][k], index[i][n], index[i + 1][n], index[i + 1][k]), painted.get((i, k), rows[i][2]))
    # Close the ends on a pole (a fan), on the dome's tip or flat on the ring.
    low = soup.vertex(rings[0].middle - axis * domes[0], rings[0].weights if fix is None else fix(rings[0].middle, dict(rings[0].weights)))
    high = soup.vertex(last.middle + axis * domes[1], last.weights if fix is None else fix(last.middle, dict(last.weights)))
    for k in range(segments):
        n = (k + 1) % segments
        soup.face((low, index[0][n], index[0][k]), rows[0][2])
        soup.face((high, index[-1][k], index[-1][n]), end_cell)
    return start


def ball(soup, middle, radius, bone, cell, segments, rings=3):
    """A sphere on a joint, for the looks that show their joints."""
    ring = Ring(middle, radius, radius, {bone: 1.0}, cell)
    tube(soup, [ring, Ring(np.array(middle) + Y * 1e-4, radius, radius, {bone: 1.0}, cell)], Y, Z, segments, domes=(radius, radius), dome_rings=rings)


def _levels(style, lod):
    return {key: value[lod] for key, value in style["detail"].items()}


def build(body, rest, style, lod):
    """The whole skin of `body` in the look `style` at level of detail `lod`: a `Soup`."""
    soup = Soup()
    shape, girth = body["shape"], style["girth"]
    detail = _levels(style, lod)
    place = {name: value[0] for name, value in rest.items()}
    leg, hand = body["leg"], body["hand_scale"]
    twist, rigid = style["twist"], style["rigid"]
    power = style["power"]

    def twisted(weights):
        """Fold the twist bones' weights into their limbs for a look that does not use them."""
        if twist:
            return weights
        out = {}
        for bone, w in weights.items():
            bone = bone.replace("_twist_01", "")
            out[bone] = out.get(bone, 0.0) + w
        return out

    # --- Trunk and neck: one tube from the crotch to under the head.
    rows = shape["trunk"]
    anchors = [
        (place["thigh_l"][1], "pelvis"),
        ((place["spine_01"][1] + place["spine_02"][1]) / 2, "spine_01"),
        ((place["spine_02"][1] + place["spine_03"][1]) / 2, "spine_02"),
        (place["spine_03"][1] + 0.55 * (place["neck_01"][1] - place["spine_03"][1]), "spine_03"),
        ((place["neck_01"][1] + place["Head"][1]) / 2, "neck_01"),
        (place["Head"][1] + 0.02 * leg, "Head"),
    ]

    def trunk_weights(y):
        if y <= anchors[0][0]:
            return {anchors[0][1]: 1.0}
        for (y0, b0), (y1, b1) in zip(anchors, anchors[1:]):
            if y <= y1:
                t = smooth(y0, y1, y)
                return {b0: 1 - t, b1: t}
        return {anchors[-1][1]: 1.0}

    shoulder_y, shoulder_x = place["upperarm_l"][1], place["upperarm_l"][0]

    def yoke(p, w):
        # The top corners of the chest follow the collarbones, so a shrug lifts the shoulders.
        share = 0.7 * smooth(0.3 * shoulder_x, 0.85 * shoulder_x, abs(p[0])) * smooth(shoulder_y - 0.11 * (shoulder_y - place["spine_03"][1] + 0.1), shoulder_y - 0.02, p[1])
        if share <= 0 or rigid:
            return w
        side = "clavicle_l" if p[0] > 0 else "clavicle_r"
        w = {b: x * (1 - share) for b, x in w.items()}
        w[side] = share
        return w

    limb_cell = style["limb_cell"]

    def trunk_cell(i):
        return (limb_cell, limb_cell, JOINT, MAIN, MAIN, MAIN, MAIN, JOINT)[i]

    wide, deep = girth["trunk_wide"], girth["trunk_deep"]
    waist = girth["waist"]
    trunk = []
    for i, (y, half, front, back, z) in enumerate(rows):
        pinch = waist if i == 3 else (1 + waist) / 2 if i in (2, 4) else 1.0
        chest = girth["chest"] if i in (5, 6) else 1.0
        trunk.append(Ring((0, y, z), half * wide * pinch * chest, front * deep, trunk_weights(y), trunk_cell(i), back=back * deep, power=power["trunk"], minor=i in (2, 4), stripe=i == 5))
    neck_r, neck_d = shape["neck"]
    neck_y, head_y = place["neck_01"][1], place["Head"][1]
    trunk.append(Ring((0, neck_y + 0.012 * leg, place["neck_01"][2] + 0.004), neck_r * 1.12 * girth["neck"], neck_d * 1.1 * girth["neck"], trunk_weights(neck_y), JOINT, power=2.0))
    trunk.append(Ring((0, head_y + 0.03 * leg, place["Head"][2]), neck_r * girth["neck"], neck_d * girth["neck"], trunk_weights(head_y + 0.03), JOINT, power=2.0))
    if not rigid:
        segments = detail["trunk"]
        tube(soup, trunk, Y, Z, segments, domes=(0.035 * leg, 0.0), dome_rings=detail["dome"], lod=lod, fix=yoke, stripes=[(Z, MARK, 2)] if style["chest_mark"] else ())
    else:
        _rigid_trunk(soup, trunk, rows, place, detail, lod, style, leg)

    # --- Head: a tube from the chin up, closed by a dome; the visor is a patch of its faces.
    head = shape["head"]
    chin, top, half = head["chin"], head["top"], head["half_width"] * girth["head"]
    front, back, hz = head["front"] * girth["head"], head["back"] * girth["head"], head["z"]
    tall = top - chin
    profile = [(0.0, 0.50, 0.66, 0.36, False), (0.13, 0.76, 0.88, 0.64, True), (0.34, 0.95, 0.98, 0.88, False), (0.50, 1.0, 1.0, 0.97, True), (0.63, 1.0, 0.99, 1.0, False), (0.74, 0.95, 0.94, 0.97, False)]
    rings = [Ring((0, chin + f * tall, hz), half * a, front * b, {"Head": 1.0}, MAIN, back=back * c, power=power["head"], minor=minor, stripe=f in (0.34, 0.50)) for f, a, b, c, minor in profile]
    visor = [(Z, VISOR, max(2, 2 * round(detail["head"] * 0.17)))]
    tube(soup, rings, Y, Z, detail["head"], domes=(0.014 * tall, 0.26 * tall), dome_rings=max(1, detail["dome"]), stripes=visor if style["visor"] else (), lod=lod)

    left_vertex, left_face = len(soup.verts), len(soup.faces)

    # --- Arm and palm: one tube from the shoulder to the knuckles.
    s, e, w = place["upperarm_l"], place["lowerarm_l"], place["hand_l"]
    upper, fore = e[0] - s[0], w[0] - e[0]
    u0, u1, u2 = (r * g for r, g in zip(shape["upper_arm"], girth["upper_arm"]))
    f0, f1, f2 = (r * g for r, g in zip(shape["forearm"], girth["forearm"]))
    palm_w, palm_t = shape["palm"][0] * girth["hand"], shape["palm"][1] * girth["hand"]
    knuckle = place["middle_01_l"][0]
    palm_z = (place["index_01_l"][2] + place["pinky_01_l"][2]) / 2
    elbow_blend, wrist_blend = 0.9 * u2, 0.022 * hand

    def arm_weights(x):
        bend = smooth(e[0] - elbow_blend, e[0] + elbow_blend, x)
        wrist = smooth(w[0] - wrist_blend, w[0] + wrist_blend, x)
        shoulder_twist = min(1.0, max(0.0, 1 - (x - s[0]) / (0.85 * upper)))
        wrist_twist = min(1.0, max(0.0, (x - e[0]) / fore))
        return twisted(
            {
                "upperarm_twist_01_l": (1 - bend) * shoulder_twist,
                "upperarm_l": (1 - bend) * (1 - shoulder_twist),
                "lowerarm_l": bend * (1 - wrist) * (1 - wrist_twist),
                "lowerarm_twist_01_l": bend * (1 - wrist) * wrist_twist,
                "hand_l": bend * wrist,
            }
        )

    def arm_ring(x, a, b, cell, z=None, y=None, minor=False, p=None):
        return Ring((x, s[1] if y is None else y, s[2] if z is None else z), a, b, arm_weights(x), cell, power=p or power["limb"], minor=minor, stripe=cell == limb_cell and p is None)

    limb_cell = style["limb_cell"]
    arm = [
        arm_ring(s[0], u0, u0, JOINT),
        arm_ring(s[0] + 0.16 * upper, u0 * 0.97, u0 * 0.97, limb_cell, minor=True),
        arm_ring(s[0] + 0.42 * upper, u1 * 1.04, u1 * 1.06, limb_cell),
        arm_ring(e[0] - 0.8 * u2, 0.35 * u1 + 0.65 * u2, 0.35 * u1 + 0.65 * u2, JOINT),
        arm_ring(e[0], u2, u2, JOINT, z=e[2]),
        arm_ring(e[0] + 0.8 * u2, 0.4 * u2 + 0.6 * f0, 0.4 * u2 + 0.6 * f0, limb_cell, z=e[2]),
        arm_ring(e[0] + 0.30 * fore, f0, f0 * 1.04, limb_cell, minor=True),
        arm_ring(e[0] + 0.66 * fore, 0.5 * (f0 + f1), 0.48 * (f0 + f1), limb_cell),
        arm_ring(w[0] - 0.03 * hand, f1, f2 * 1.08, JOINT, z=w[2]),
        arm_ring(w[0] + 0.012 * hand, f1 * 0.98, f2, PANEL, z=w[2], p=power["palm"]),
        arm_ring(w[0] + 0.05 * hand, palm_w * 0.93, palm_t, PANEL, z=palm_z, p=power["palm"], minor=True),
        arm_ring(knuckle - 0.012 * hand, palm_w, palm_t * 0.95, PANEL, z=palm_z, p=power["palm"]),
    ]
    mitten = detail["finger"] == 0
    if mitten:
        # The far level's hand: the four fingers are one block on the hand bone.
        tip = place["middle_04_leaf_l"][0]
        arm.append(arm_ring(tip - 0.02 * hand, palm_w * 0.9, palm_t * 0.75, PANEL, z=palm_z, p=power["palm"]))
    if not rigid:
        tube(soup, arm, X, Y, detail["limb"], domes=(u0 * 0.95, 0.012 * hand), dome_rings=detail["dome"], lod=lod, stripes=[(Y, LEFT, 1)] if style["stripes"] else ())
    else:
        _rigid_arm(soup, place, shape, girth, detail, lod, style, hand, mitten)

    # --- Fingers: a tube a finger, bending at its two knuckles.
    for finger, radius in FINGER_RADIUS.items():
        if mitten and finger != "thumb":
            continue
        joints = [place[f"{finger}_0{i}_l"] for i in (1, 2, 3)] + [place[f"{finger}_04_leaf_l"]]
        axis = joints[3] - joints[0]
        axis /= np.linalg.norm(axis)
        r = radius * hand * shape["finger"] * girth["finger"]
        names = [f"{finger}_0{i}_l" for i in (1, 2, 3)]
        if mitten:
            names = ["hand_l"] * 3
        reach = [float(np.dot(j - joints[0], axis)) for j in joints]

        def finger_weights(d, names=names, reach=reach, r=r):
            if rigid:
                return {names[0] if d < reach[1] else names[1] if d < reach[2] else names[2]: 1.0}
            a = smooth(reach[1] - 0.7 * r, reach[1] + 0.7 * r, d)
            b = smooth(reach[2] - 0.7 * r, reach[2] + 0.7 * r, d)
            out = {}
            for name, share in zip(names, (1 - a, a * (1 - b), a * b)):
                out[name] = out.get(name, 0.0) + share
            return out

        def finger_ring(d, scale, minor=False, joints=joints, axis=axis, reach=reach, r=r):
            # Follow the bones: a point at reach `d` lies on the line between the two joints round it.
            for (d0, j0), (d1, j1) in zip(zip(reach, joints), zip(reach[1:], joints[1:])):
                if d <= d1 or d1 == reach[-1]:
                    middle = j0 + (j1 - j0) * ((d - d0) / (d1 - d0))
                    break
            return Ring(middle, r * scale, r * scale * 0.92, finger_weights(d), PANEL, power=power["finger"], minor=minor)

        rings = [
            finger_ring(reach[0], 1.08),
            finger_ring(reach[1] - 0.75 * r, 1.04, minor=True),
            finger_ring(reach[1] + 0.75 * r, 1.0),
            finger_ring(reach[2] - 0.75 * r, 0.98, minor=True),
            finger_ring(reach[2] + 0.75 * r, 0.95),
            finger_ring(reach[3] - 0.7 * r, 0.88),
        ]
        hint = Y if finger != "thumb" else np.cross(axis, np.cross(Y, axis))
        tube(soup, rings, axis, hint, max(3, detail["finger"]), domes=(r * 0.8, r * 0.75), dome_rings=min(1, detail["dome"]) if lod else 2, lod=lod)

    # --- Leg: one tube from the hip to the ankle.
    h, k, a = place["thigh_l"], place["calf_l"], place["foot_l"]
    thigh, calf = h[1] - k[1], k[1] - a[1]
    t0, t1, t2 = (r * g for r, g in zip(shape["thigh"], girth["thigh"]))
    c0, c1 = (r * g for r, g in zip(shape["calf"], girth["calf"]))
    knee_blend = 0.9 * t2

    def leg_weights(y):
        bend = smooth(k[1] + knee_blend, k[1] - knee_blend, y)
        hip_twist = min(1.0, max(0.0, 1 - (h[1] - y) / (0.8 * thigh)))
        return twisted({"thigh_twist_01_l": (1 - bend) * hip_twist, "thigh_l": (1 - bend) * (1 - hip_twist), "calf_l": bend})

    def leg_ring(y, r, cell, back=1.0, front=1.0, minor=False):
        t = (h[1] - y) / (h[1] - a[1])
        x = h[0] + (a[0] - h[0]) * t
        z = h[2] + (k[2] - h[2]) * min(1.0, (h[1] - y) / thigh) if y >= k[1] else k[2] + (a[2] - k[2]) * (k[1] - y) / calf
        return Ring((x, y, z), r, r * front, leg_weights(y), cell, back=r * back, power=power["limb"], minor=minor, stripe=cell == limb_cell)

    legs = [
        leg_ring(h[1], t0, limb_cell),
        leg_ring(h[1] - 0.14 * thigh, t0 * 0.99, limb_cell, minor=True),
        leg_ring(h[1] - 0.45 * thigh, t1, limb_cell, front=1.05),
        leg_ring(k[1] + 0.8 * t2, 0.3 * t1 + 0.7 * t2, JOINT),
        leg_ring(k[1], t2, JOINT, front=1.04),
        leg_ring(k[1] - 0.8 * t2, 0.45 * t2 + 0.55 * c0, limb_cell, back=1.04),
        leg_ring(k[1] - 0.30 * calf, c0, limb_cell, back=1.14, front=0.92, minor=True),
        leg_ring(k[1] - 0.66 * calf, 0.5 * (c0 + c1) * 0.96, limb_cell, back=1.05),
        leg_ring(a[1] + 0.25 * c1, c1, JOINT),
    ]
    if not rigid:
        tube(soup, legs, -Y, Z, detail["limb"], domes=(t0 * 0.9, c1 * 0.9), dome_rings=detail["dome"], lod=lod, stripes=[(X, LEFT, 1)] if style["stripes"] else (), dome_cells=(limb_cell, None))
    else:
        _rigid_leg(soup, place, shape, girth, detail, lod, style)

    # --- Foot: a tube from the heel to the toes with a flat sole.
    foot = shape["foot"]
    half = foot["half_width"] * girth["foot"]
    ball_z, tip_z = place["ball_l"][2], place["ball_leaf_l"][2]
    ankle_y = a[1] * foot.get("height", 1.0)
    span = ball_z - a[2]

    def foot_ring(z, wide, tall, minor=False, lift=0.0):
        bend = 0.0 if rigid and z < ball_z else 1.0 if rigid else smooth(ball_z - 0.16 * span, ball_z + 0.12 * span, z)
        height = tall * ankle_y
        # `lift` raises a ring off the floor: the heel's round back and the toes' spring, which keep a
        # pitched foot from digging in.
        return Ring((a[0], height / 2 + lift * ankle_y, z), half * wide, height / 2, {"foot_l": 1 - bend, "ball_l": bend}, PANEL, power=power["foot"], minor=minor)

    rings = [
        foot_ring(a[2] + foot["heel"] * leg, 0.70, 0.66, lift=0.06),
        foot_ring(a[2], 0.90, 1.12),
        foot_ring(a[2] + 0.5 * span, 1.0, 0.84, minor=True),
        foot_ring(ball_z - 0.02 * span, 1.06, 0.56),
        foot_ring(tip_z - 0.1 * span, 0.92, 0.38, lift=0.07),
    ]
    tube(soup, rings, Z, Y, detail["foot"], domes=(0.12 * span, 0.14 * span), dome_rings=min(detail["dome"], 2), lod=lod)

    soup.mirror(left_vertex, left_face)
    _paint_undersides(soup, left_face, place)
    return soup


def _paint_undersides(soup, first_face, place):
    """Palms and soles: the hand's and the foot's faces that look down get their own cell."""
    ankle = max(place["foot_l"][1] * 1.3, 0.03)
    wrist = place["hand_l"][0]
    for i in range(first_face, len(soup.faces)):
        if soup.cells[i] != PANEL:
            continue
        corners = [soup.verts[c] for c in soup.faces[i]]
        normal = np.cross(corners[1] - corners[0], corners[2] - corners[0])
        length = np.linalg.norm(normal)
        if length == 0 or normal[1] / length > -0.6:
            continue
        middle = sum(corners) / len(corners)
        if middle[1] < ankle:
            soup.cells[i] = SOLE
        elif abs(middle[0]) > wrist:
            soup.cells[i] = PALM


# --- The look with rigid shells and ball joints: every vertex follows one bone.


def _shell(soup, rings, axis, up, segments, detail, lod, domes, stripes=()):
    tube(soup, rings, axis, up, segments, domes=domes, dome_rings=detail["dome"], lod=lod, stripes=stripes)


def _rigid_trunk(soup, trunk, rows, place, detail, lod, style, leg):
    segments = detail["trunk"]

    def part(rings, bone, cell, domes):
        copies = [Ring(r.middle, r.a, r.b, {bone: 1.0}, cell, back=r.back, power=r.power, minor=False) for r in rings]
        _shell(soup, copies, Y, Z, segments, detail, lod, domes)

    gap = 0.012 * leg
    hips = [trunk[0], trunk[1], trunk[2]]
    part(hips, "pelvis", style["limb_cell"] if style["limb_cell"] else PANEL, (0.035 * leg, 0.03 * leg))
    chest = [trunk[4], trunk[5], trunk[6], trunk[7]]
    part(chest, "spine_03", MAIN, (0.03 * leg, 0.02 * leg))
    waist = trunk[3]
    ball(soup, (0, waist.middle[1], waist.middle[2]), 0.5 * (waist.a + waist.b) * 0.92, "spine_01", JOINT, segments, rings=max(2, detail["dome"]))
    neck = [trunk[8], trunk[9]]
    part(neck, "neck_01", JOINT, (gap, 0.0))


def _rigid_arm(soup, place, shape, girth, detail, lod, style, hand, mitten):
    s, e, w = place["upperarm_l"], place["lowerarm_l"], place["hand_l"]
    u0, u1, u2 = (r * g for r, g in zip(shape["upper_arm"], girth["upper_arm"]))
    f0, f1, f2 = (r * g for r, g in zip(shape["forearm"], girth["forearm"]))
    palm_w, palm_t = shape["palm"][0] * girth["hand"], shape["palm"][1] * girth["hand"]
    upper, fore = e[0] - s[0], w[0] - e[0]
    segments = detail["limb"]
    palm_z = (place["index_01_l"][2] + place["pinky_01_l"][2]) / 2
    cell = style["limb_cell"]

    def ring(x, a, b, bone, z=None, c=cell, p=2.0):
        return Ring((x, s[1], s[2] if z is None else z), a, b, {bone: 1.0}, c, power=p, stripe=c == cell)

    ball(soup, s, u0 * 1.05, "upperarm_l", JOINT, segments, rings=max(2, detail["dome"]))
    shell = [ring(s[0] + u0 * 0.9, u0 * 0.9, u0 * 0.9, "upperarm_l"), ring(s[0] + 0.45 * upper, u1, u1 * 1.04, "upperarm_l"), ring(e[0] - u2 * 1.2, u2 * 0.94, u2 * 0.94, "upperarm_l")]
    _shell(soup, shell, X, Y, segments, detail, lod, (u0 * 0.35, u2 * 0.4), stripes=[(Y, LEFT, 1)] if style["stripes"] else ())
    ball(soup, e, u2 * 1.02, "lowerarm_l", JOINT, segments, rings=max(2, detail["dome"]))
    shell = [ring(e[0] + u2 * 1.2, f0 * 0.92, f0 * 0.92, "lowerarm_l", z=e[2]), ring(e[0] + 0.32 * fore, f0, f0 * 1.04, "lowerarm_l"), ring(w[0] - f1 * 1.25, f1 * 1.02, f2 * 1.2, "lowerarm_l", z=w[2])]
    _shell(soup, shell, X, Y, segments, detail, lod, (f0 * 0.4, f2 * 0.6), stripes=[(Y, LEFT, 1)] if style["stripes"] else ())
    ball(soup, w, f2 * 1.12, "hand_l", JOINT, segments, rings=max(2, detail["dome"]))
    knuckle = place["middle_01_l"][0]
    palm = [ring(w[0] + 0.028 * hand, palm_w * 0.8, palm_t, "hand_l", z=palm_z, c=PANEL, p=3.0), ring(w[0] + 0.06 * hand, palm_w * 0.96, palm_t, "hand_l", z=palm_z, c=PANEL, p=3.0), ring(knuckle - 0.012 * hand, palm_w, palm_t * 0.95, "hand_l", z=palm_z, c=PANEL, p=3.0)]
    if mitten:
        palm.append(ring(place["middle_04_leaf_l"][0] - 0.02 * hand, palm_w * 0.9, palm_t * 0.75, "hand_l", z=palm_z, c=PANEL, p=3.0))
    _shell(soup, palm, X, Y, segments, detail, lod, (0.012 * hand, 0.012 * hand))


def _rigid_leg(soup, place, shape, girth, detail, lod, style):
    h, k, a = place["thigh_l"], place["calf_l"], place["foot_l"]
    t0, t1, t2 = (r * g for r, g in zip(shape["thigh"], girth["thigh"]))
    c0, c1 = (r * g for r, g in zip(shape["calf"], girth["calf"]))
    thigh, calf = h[1] - k[1], k[1] - a[1]
    segments = detail["limb"]
    cell = style["limb_cell"]

    def ring(y, r, bone, back=1.0):
        t = (h[1] - y) / (h[1] - a[1])
        z = h[2] + (a[2] - h[2]) * t
        return Ring((h[0], y, z), r, r, {bone: 1.0}, cell, back=r * back, stripe=True)

    ball(soup, h, t0 * 0.8, "thigh_l", JOINT, segments, rings=max(2, detail["dome"]))
    shell = [ring(h[1] - t0 * 0.75, t0 * 0.9, "thigh_l"), ring(h[1] - 0.45 * thigh, t1, "thigh_l"), ring(k[1] + t2 * 1.2, t2 * 0.96, "thigh_l")]
    _shell(soup, shell, -Y, Z, segments, detail, lod, (t0 * 0.3, t2 * 0.4), stripes=[(X, LEFT, 1)] if style["stripes"] else ())
    ball(soup, k, t2 * 1.04, "calf_l", JOINT, segments, rings=max(2, detail["dome"]))
    shell = [ring(k[1] - t2 * 1.2, c0 * 0.9, "calf_l"), ring(k[1] - 0.32 * calf, c0, "calf_l", back=1.14), ring(a[1] + c1 * 1.5, c1 * 1.04, "calf_l")]
    _shell(soup, shell, -Y, Z, segments, detail, lod, (c0 * 0.4, c1 * 0.5), stripes=[(X, LEFT, 1)] if style["stripes"] else ())
    ball(soup, (a[0], a[1], a[2]), c1 * 1.1, "foot_l", JOINT, segments, rings=max(2, detail["dome"]))
