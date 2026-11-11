"""The kit's hook dispatcher (.claude/hooks) loaded for the tests, and how a test replaces a name of its guards."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from typing import Any

import pytest

HOOKS = Path(__file__).resolve().parents[2] / ".claude" / "hooks"
sys.path.insert(0, str(HOOKS))
_spec = importlib.util.spec_from_file_location("dispatch", HOOKS / "dispatch.py")
dispatch = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(dispatch)
guards = dispatch.guards
CONFIG = dispatch.load_config(None)


def patch(monkeypatch: pytest.MonkeyPatch, name: str, value: Any) -> None:
    """Replace `name` in every module of the guards package that holds it: a module that imports a name from another
    holds its own binding, so replacing it in one module alone leaves the guards of the others calling the real one."""
    held = [
        module
        for key, module in list(sys.modules.items())
        if (key == "guards" or key.startswith("guards.")) and name in vars(module)
    ]
    assert held, f"no module of the guards package has {name!r}"
    for module in held:
        monkeypatch.setattr(module, name, value)
