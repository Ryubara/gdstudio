"""The three looks of the prototype mannequins (kit #1149): how a body's numbers are drawn.

A look sets how many sides and rings each part has at each level of detail, how the girths are pushed, whether the
skin bends (and so uses the twist bones) or is rigid shells on ball joints, and the palette. The palette is a 4 by 4
atlas of flat cells; a game recolours a body (a team, a faction) by swapping that one small image.
"""

## Sides of each part's tube at levels of detail 0, 1 and 2; `finger` 0 is one block for the four fingers; `dome`
## is the rings of a round end.
_SMOOTH = {"trunk": (20, 12, 8), "head": (16, 12, 8), "limb": (12, 8, 6), "finger": (6, 4, 0), "foot": (12, 8, 8), "dome": (3, 2, 1)}
_FACET = {"trunk": (8, 8, 6), "head": (8, 8, 6), "limb": (6, 6, 4), "finger": (4, 4, 0), "foot": (8, 8, 8), "dome": (1, 1, 0)}
_ONE = {
    "trunk_wide": 1.0,
    "trunk_deep": 1.0,
    "waist": 1.0,
    "chest": 1.0,
    "neck": 1.0,
    "head": 1.0,
    "upper_arm": (1, 1, 1),
    "forearm": (1, 1, 1),
    "hand": 1.0,
    "finger": 1.0,
    "thigh": (1, 1, 1),
    "calf": (1, 1),
    "foot": 1.0,
}

## Palette cells in order: main, panel, joint, left accent, right accent, visor, palm, sole, chest mark.
STYLES = {
    # A continuous skin that bends at every joint and uses the twist bones: the body to judge deformation on.
    "form": {
        "detail": _SMOOTH,
        "girth": _ONE,
        "power": {"trunk": 2.5, "head": 2.25, "limb": 2.0, "palm": 3.0, "finger": 2.0, "foot": 3.2},
        "flat": False,
        "rigid": False,
        "twist": True,
        "stripes": True,
        "visor": True,
        "chest_mark": True,
        "limb_cell": 0,
        "palette": ["#d8d5cd", "#8d9298", "#32363c", "#f08a24", "#1fa7c9", "#14171b", "#c4c8cc", "#202328", "#f2c230"],
    },
    # Rigid shells on dark ball joints, a lay figure: one bone a vertex, nothing stretches, the cheapest to skin.
    "joint": {
        "detail": _SMOOTH,
        "girth": dict(_ONE, waist=0.94, upper_arm=(0.96, 1.0, 0.96), thigh=(0.96, 1.0, 0.96)),
        "power": {"trunk": 2.4, "head": 2.2, "limb": 2.0, "palm": 3.0, "finger": 2.0, "foot": 3.0},
        "flat": False,
        "rigid": True,
        "twist": False,
        "stripes": True,
        "visor": True,
        "chest_mark": False,
        "limb_cell": 0,
        "palette": ["#e6d9be", "#c6ae86", "#383d45", "#e2552b", "#2f7fd0", "#22262c", "#efe5d0", "#57483a", "#f2c230"],
    },
    # Few flat sides and heavy forearms and calves: a low-poly hero that sits beside low-poly game art.
    "facet": {
        "detail": _FACET,
        "girth": dict(
            _ONE,
            trunk_wide=1.05,
            waist=0.9,
            chest=1.06,
            neck=1.05,
            head=1.02,
            upper_arm=(1.04, 1.0, 0.9),
            forearm=(1.32, 1.2, 1.25),
            hand=1.12,
            finger=1.18,
            thigh=(1.04, 1.0, 0.9),
            calf=(1.3, 1.12),
            foot=1.12,
        ),
        "power": {"trunk": 2.8, "head": 2.6, "limb": 2.0, "palm": 3.0, "finger": 2.6, "foot": 3.4},
        "flat": True,
        "rigid": False,
        "twist": True,
        "stripes": True,
        "visor": True,
        "chest_mark": True,
        "limb_cell": 1,
        "palette": ["#5b7da1", "#e7ebee", "#252d38", "#f08a24", "#35c2a4", "#0f1317", "#cdd5db", "#1a1f27", "#f2c230"],
    },
}
