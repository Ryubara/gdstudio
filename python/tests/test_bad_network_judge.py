"""The 3D Third Person bad-network gate's judge (`tools/net/bad_network.py`) and relay: which snaps it attributes to a
stall of the commands' way, and that each way of the relay draws its stalls from its own generator (gdstudio #1110)."""

import importlib.util
import sys
from pathlib import Path

NET = Path(__file__).resolve().parents[2] / "templates" / "3d-third-person" / "game" / "tools" / "net"


def _load(name: str):
    # No `__pycache__` in the template: a made game's layout check refuses the folder (test_layout.py).
    was, sys.dont_write_bytecode = sys.dont_write_bytecode, True
    try:
        spec = importlib.util.spec_from_file_location(name, NET / f"{name}.py")
        module = importlib.util.module_from_spec(spec)
        sys.modules[name] = module
        spec.loader.exec_module(module)
    finally:
        sys.dont_write_bytecode = was
    return module


bad_network = _load("bad_network")
relay = _load("relay")


def _report(**changes) -> dict:
    """A stall run's report as the predicting bot writes it, all within the limits."""
    report = {
        "slot": 3,
        "rtt_ms": 240,
        "lost": 0,
        "stalls": 0,
        "skipped_ticks": 0,
        "snaps": 1,
        "size_snaps_m": [],
        "worst_error_m": 1.6,
        "end_gap_m": 0.005,
        "corrected_m": 15.0,
        "corrections": 210,
    }
    report.update(changes)
    return report


def _failures(report: dict, network) -> list[str]:
    return bad_network.judge_client(report, network).failures()


def _stalls(up: int = 23):
    return bad_network.Network(seconds=30, stalls_up=up, stalls_down=12)


def test_a_burst_after_up_stalls_is_a_snap_the_gate_allows():
    # The two-core local run: the join and two snaps of 2.6 and 2.8 m after up stalls close together.
    report = _report(snaps=3, size_snaps_m=[2.6, 2.828], worst_error_m=2.828)
    assert _failures(report, _stalls()) == []


def test_the_failed_runner_run_still_fails_on_its_gap_and_corrections():
    # main's run on 31cc1793: the snaps were bursts, but 1.65 m off after standing and 75.5 m of corrections are not.
    report = _report(snaps=3, size_snaps_m=[2.6, 2.947], worst_error_m=2.947, end_gap_m=1.6477, corrected_m=75.512)
    failures = _failures(report, _stalls())
    assert not [f for f in failures if "snaps" in f]
    assert any("settled" in f for f in failures)
    assert any("corrected" in f for f in failures)


def test_a_size_snap_without_up_stalls_is_a_loop_that_does_not_settle():
    report = _report(snaps=2, size_snaps_m=[2.7])
    assert any("snaps" in f for f in _failures(report, _stalls(up=0)))


def test_a_snap_past_the_stall_worst_error_is_never_a_burst():
    report = _report(snaps=2, size_snaps_m=[4.2], worst_error_m=4.2)
    failures = _failures(report, _stalls())
    assert any("snaps" in f for f in failures)
    assert any("worst error" in f for f in failures)


def test_no_more_bursts_than_up_stalls():
    report = _report(snaps=4, size_snaps_m=[2.6, 2.7, 2.8])
    assert any("snaps" in f for f in _failures(report, _stalls(up=2)))


def test_a_report_without_size_snaps_is_judged_as_before():
    # The browser page's report has no `size_snaps_m`: only the join and the client's stalls.
    report = _report(snaps=2)
    del report["size_snaps_m"]
    assert any("snaps" in f for f in _failures(report, _stalls()))


def test_each_way_of_the_relay_draws_from_its_own_generator():
    first = relay.Relay("127.0.0.1", 1, 0.1, stall_chance=0.01, seed=1)
    second = relay.Relay("127.0.0.1", 1, 0.1, stall_chance=0.01, seed=1)
    # However many draws the way down took, the way up's next draws are the same.
    for _ in range(17):
        second._rngs[False].random()
    assert [first._rngs[True].random() for _ in range(50)] == [second._rngs[True].random() for _ in range(50)]
    assert first._rngs[True].random() != first._rngs[False].random()
