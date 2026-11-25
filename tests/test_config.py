"""M1 tests: layout schema validation and YAML round-trip (FR-4, FR-6, FR-13)."""

from __future__ import annotations

import copy
from pathlib import Path

import pytest
import yaml

from mosaicctl.config import LayoutError, dump_layout, load_layout, parse_layout, save_layout

ROOT = Path(__file__).resolve().parent.parent
EXAMPLE = ROOT / "layouts" / "research-wall.yaml"


@pytest.fixture
def data() -> dict:
    """The example layout as plain data, so each test can break it a different way."""
    return yaml.safe_load(EXAMPLE.read_text())


def issue_paths(exc: LayoutError) -> list[str]:
    return [i.path for i in exc.issues]


def test_example_layout_is_valid():
    layout = load_layout(EXAMPLE)
    assert layout.name == "research-wall"
    assert (layout.grid.rows, layout.grid.cols) == (1, 9)
    assert len(layout.grid.displays) == 9
    assert layout.sync is not None and layout.sync.server is not None
    assert layout.sync.server.key() == (0, 0)


def test_surface_size_accounts_for_portrait_rotation():
    grid = load_layout(EXAMPLE).grid
    assert grid.surface_size == (9 * 2160, 3840)


def test_surface_size_includes_bezel(data):
    data["grid"]["bezel"]["horizontal_px"] = 40
    assert parse_layout(data).grid.surface_size == (9 * 2160 + 8 * 40, 3840)


def test_round_trip(tmp_path):
    original = load_layout(EXAMPLE)
    out = tmp_path / "copy.yaml"
    save_layout(original, out)
    assert load_layout(out) == original


def test_dump_omits_unset_optional_fields():
    text = dump_layout(load_layout(EXAMPLE))
    assert "edid_serial" not in text


def test_wrong_display_count(data):
    data["grid"]["displays"].pop()
    with pytest.raises(LayoutError) as exc:
        parse_layout(data)
    assert "grid.displays" in issue_paths(exc.value)
    assert "expected 9 displays" in str(exc.value)


def test_duplicate_cell_and_output_and_out_of_range(data):
    displays = data["grid"]["displays"]
    displays[1] = dict(displays[0])                              # duplicate cell + duplicate output
    displays[2] = {"row": 0, "col": 12, "gpu": 3, "output": 3}   # outside the grid
    with pytest.raises(LayoutError) as exc:
        parse_layout(data)
    messages = [i.message for i in exc.value.issues]
    assert any("already used" in m and "cell" in m for m in messages)
    assert any("gpu 0 output 0 is already used" in m for m in messages)
    assert any("outside the 1x9 grid" in m for m in messages)


def test_all_type_errors_reported_together(data):
    """FR-6: report every problem, not just the first one."""
    data["grid"]["rotation"] = 45
    data["grid"]["mode"]["refresh_hz"] = -1
    data["name"] = "Research Wall"
    data["grid"]["displays"][4]["gpu"] = "two"
    with pytest.raises(LayoutError) as exc:
        parse_layout(data)
    paths = issue_paths(exc.value)
    assert "grid.rotation" in paths
    assert "grid.mode.refresh_hz" in paths
    assert "name" in paths
    assert "grid.displays[4].gpu" in paths


def test_unknown_key_is_rejected(data):
    data["grid"]["mode"]["refresh"] = 60
    with pytest.raises(LayoutError) as exc:
        parse_layout(data)
    assert "grid.mode.refresh" in issue_paths(exc.value)


def test_missing_required_field(data):
    del data["grid"]["mode"]
    with pytest.raises(LayoutError) as exc:
        parse_layout(data)
    assert "grid.mode" in issue_paths(exc.value)


def test_unsupported_version(data):
    data["version"] = 2
    with pytest.raises(LayoutError) as exc:
        parse_layout(data)
    assert "version" in issue_paths(exc.value)


def test_sync_server_must_be_in_grid(data):
    data["sync"]["server"] = {"gpu": 3, "output": 3}
    with pytest.raises(LayoutError) as exc:
        parse_layout(data)
    assert "sync.server" in issue_paths(exc.value)


def test_sync_enabled_needs_server(data):
    del data["sync"]["server"]
    with pytest.raises(LayoutError) as exc:
        parse_layout(data)
    assert "sync.server" in issue_paths(exc.value)


def test_house_sync_not_supported_in_v1(data):
    data["sync"]["source"] = "house"
    with pytest.raises(LayoutError) as exc:
        parse_layout(data)
    assert "sync.source" in issue_paths(exc.value)


def test_sync_section_is_optional(data):
    del data["sync"]
    assert parse_layout(data).sync is None


def test_disabled_sync_needs_no_server(data):
    data["sync"] = {"enabled": False}
    assert parse_layout(data).sync.enabled is False


def test_single_display_grid_rejected(data):
    data["grid"]["cols"] = 1
    data["grid"]["displays"] = data["grid"]["displays"][:1]
    data["sync"]["server"] = {"gpu": 0, "output": 0}
    with pytest.raises(LayoutError) as exc:
        parse_layout(data)
    assert "grid" in issue_paths(exc.value)


def test_invalid_yaml(tmp_path):
    bad = tmp_path / "bad.yaml"
    bad.write_text("grid: [unclosed\n")
    with pytest.raises(LayoutError) as exc:
        load_layout(bad)
    assert "invalid YAML" in str(exc.value)


def test_missing_file(tmp_path):
    with pytest.raises(LayoutError) as exc:
        load_layout(tmp_path / "nope.yaml")
    assert "cannot read file" in str(exc.value)


def test_top_level_must_be_mapping():
    with pytest.raises(LayoutError):
        parse_layout(["not", "a", "mapping"])


def test_layout_is_immutable():
    layout = load_layout(EXAMPLE)
    with pytest.raises(Exception):
        layout.name = "other"  # type: ignore[misc]


def test_parse_does_not_mutate_input(data):
    before = copy.deepcopy(data)
    parse_layout(data)
    assert data == before
