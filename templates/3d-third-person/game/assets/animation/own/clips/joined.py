"""What a clip needs of the clips it joins (kit #1160).

A stance change starts on the standing idle's first pose and ends on the crouch idle's; a crouch stands where the
standing idle's feet are; a crouch walk is carried like its idle. Each of those reads another clip: its numbers,
the spec of its first frame, or its solved first pose. `Joined` hands them out for the variant `picks.json` names
for the other clip (the one the game ships), and solves each joined clip once.
"""

import inspect

from gdsanim import build, weight


def described(describe, rig, style, name: str, joined):
    """A description's clip: `joined` is handed to the descriptions that take it (a fourth parameter)."""
    if len(inspect.signature(describe).parameters) > 3:
        return describe(rig, style, name, joined)
    return describe(rig, style, name)


class Joined:
    """The picked variants of the clips a description joins.

    - `style(name)`: the style file picked for a shipped clip (`Idle`);
    - `clip(name)`: that clip's description, with the picked style;
    - `start(name)`: its first frame as the solver's spec with the pelvis where the weight puts it, the floor
      point the weight is over and the leg's stretch: what a transition mixes from or to;
    - `built(name)`: the clip solved, whose `frames[0]` is the exact pose a join has to meet.
    """

    def __init__(self, rig, solver, styles: dict, picks: dict, types: dict):
        self.rig, self.solver, self.styles, self.picks, self.types = rig, solver, styles, picks, types
        self._clips, self._starts, self._builts = {}, {}, {}

    def style(self, name: str):
        assert name in self.picks, f"picks.json names no variant for {name}"
        return self.styles[self.picks[name]]

    def clip(self, name: str):
        if name not in self._clips:
            _, describe = self.types[name.lower()]
            self._clips[name] = described(describe, self.rig, self.style(name), name, self)
        return self._clips[name]

    def start(self, name: str) -> dict:
        if name not in self._starts:
            clip = self.clip(name)
            spec = clip.spec(0)
            legs = spec.setdefault("leg", {})
            for s in ("l", "r"):
                if s not in legs:
                    legs[s] = clip.plan.foot(self.rig, s, 0)
            over = clip.balance(0, spec) if clip.balance is not None else None
            stretch = clip.stretch(0) if callable(clip.stretch) else clip.stretch
            if over is not None:
                weight.settle(self.solver, spec, over, stretch)
            self._starts[name] = {"spec": spec, "over": over, "stretch": stretch}
        return self._starts[name]

    def built(self, name: str):
        if name not in self._builts:
            self._builts[name] = build.build_clip(self.rig, self.solver, self.clip(name))
        return self._builts[name]
