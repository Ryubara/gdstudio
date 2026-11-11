"""The sound-effects recipe's parts that need no package: cost, budget, names and the data file's promises."""

import importlib.util
import json
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("sfx", ROOT / "tools" / "audio" / "sfx.py")
sfx = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sfx)


@pytest.fixture
def data() -> dict:
    return sfx.load()


def test_a_request_costs_forty_credits_a_second_in_the_plan(data):
    assert sfx.request_cost(data, 0.5) == 20
    assert sfx.request_cost(data, 5.0) == 200
    assert sfx.request_cost(data, 12.0) == 480


def test_no_length_outside_the_api_range_is_requested(data):
    with pytest.raises(ValueError):
        sfx.request_cost(data, 0.2)
    with pytest.raises(ValueError):
        sfx.request_cost(data, 31.0)


def test_the_plan_of_the_set_is_2940_credits_and_inside_the_budget(data, tmp_path):
    rows = sfx.plan_rows(data, tmp_path)
    assert sum(r["credits"] for r in rows) == 2940
    assert sfx.check_budget(data, tmp_path, rows) == (0, 2940)
    assert data["budget"] <= 4000


def test_a_plan_over_the_budget_is_refused(data, tmp_path):
    data["budget"] = 2000
    with pytest.raises(SystemExit, match="over budget"):
        sfx.check_budget(data, tmp_path, sfx.plan_rows(data, tmp_path))


def test_a_cached_take_costs_nothing_and_the_ledger_counts_what_was_billed(data, tmp_path):
    (tmp_path / "coin_pickup_t1.mp3").write_bytes(b"x")
    (tmp_path / "coin_pickup_t1.json").write_text(json.dumps({"credits": 20, "billed": 5}))
    rows = {r["take"]: r for r in sfx.plan_rows(data, tmp_path, "coin_pickup")}
    assert rows["coin_pickup_t1"]["credits"] == 0
    assert rows["coin_pickup_t2"]["credits"] == 20
    assert sfx.spent_in_cache(data, tmp_path) == 5


def test_the_ledger_falls_back_to_the_planned_cost(data, tmp_path):
    (tmp_path / "wind_soft_t1.json").write_text(json.dumps({"credits": 480}))
    assert sfx.spent_in_cache(data, tmp_path) == 480


def test_an_unknown_sound_in_only_is_refused(data):
    with pytest.raises(SystemExit):
        sfx.chosen(data, "coin_pickup,nope")


def test_the_data_file_keeps_the_issue_s_promises(data):
    sounds = {s["name"]: s for s in data["sounds"]}
    assert sounds["coin_pickup"]["min_seconds"] == 0.3
    assert sounds["coin_pickup"]["max_seconds"] <= 0.4
    assert sounds["footstep_soft"]["min_files"] >= 4
    assert 10 <= sounds["wind_soft"]["min_seconds"] <= sounds["wind_soft"]["max_seconds"] <= 12
    assert sounds["wind_soft"]["loop"] is True
    for sound in sounds.values():  # a length is always given: auto length costs more
        assert sound["seconds"] >= data["min_seconds"]
        assert sound["takes"] >= 1
    for sound in sounds.values():
        assert (ROOT / sound["folder"]).parts[-4:-1] == ("game", "assets", "audio")


def test_the_set_is_asked_of_the_newest_sound_effects_model(data):
    assert data["model"] == "eleven_text_to_sound_v3"
    assert all(sfx.model_of(data, s) == "eleven_text_to_sound_v3" for s in data["sounds"])


def test_encode_cuts_only_the_picked_takes_and_names_fixed_files():
    sound = {"name": "x", "takes": 4, "use_takes": [2, 4], "prefix": "x"}
    assert sfx.used_takes(sound) == ["x_t2", "x_t4"]
    assert sfx.used_takes({"name": "y", "takes": 2}) == ["y_t1", "y_t2"]
    assert sfx.file_names({"prefix": "x"}, 2) == ["x_1.ogg", "x_2.ogg"]
    assert sfx.file_names({"names": ["a.ogg", "b.ogg"], "prefix": "x"}, 1) == ["a.ogg"]
    with pytest.raises(SystemExit):
        sfx.file_names({"name": "z", "names": ["a.ogg"], "prefix": "x"}, 2)


def test_a_changed_prompt_leaves_the_takes_made_with_the_old_one(data):
    sound = {"prompt": "new", "take_prompts": {"1": "old"}}
    assert sfx.prompt_of(sound, "impact_t1") == "old"
    assert sfx.prompt_of(sound, "impact_t5") == "new"
    for s in data["sounds"]:  # every picked take exists
        assert all(1 <= n <= s["takes"] for n in s.get("use_takes", []))


def test_the_licence_follows_the_plan_the_take_was_made_on(data):
    licence, attribution = sfx.licence_of(data, "free")
    assert "not licensed for commercial use" in licence and attribution
    licence, attribution = sfx.licence_of(data, "starter")
    assert "`starter`" in licence and "commercial use" in licence and attribution is None
    assert "isolated audio files" in licence
