"""Load and save layout / profile files (FR-4, FR-13).

`load_layout` either returns a fully valid `Layout` or raises `LayoutError`
listing every problem found (FR-6).
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml
from pydantic import ValidationError

from .models import Issue, Layout, check_layout


class LayoutError(Exception):
    """A layout file is unreadable or invalid. `issues` holds every problem found."""

    def __init__(self, source: str, issues: list[Issue]):
        self.source = source
        self.issues = issues
        lines = "\n".join(f"  {issue}" for issue in issues)
        super().__init__(f"{source}: {len(issues)} problem(s)\n{lines}")


def _loc_to_path(loc: tuple[Any, ...]) -> str:
    """Turn a pydantic error location like ('grid', 'displays', 3, 'gpu') into 'grid.displays[3].gpu'."""
    path = ""
    for part in loc:
        if isinstance(part, int):
            path += f"[{part}]"
        else:
            path += f".{part}" if path else str(part)
    return path


def parse_layout(data: Any, source: str = "<data>") -> Layout:
    """Validate already-parsed YAML/JSON data and return a Layout."""
    if not isinstance(data, dict):
        raise LayoutError(source, [Issue("", "the file must contain a mapping (key: value pairs) at the top level")])

    try:
        layout = Layout.model_validate(data)
    except ValidationError as exc:
        issues = [Issue(_loc_to_path(err["loc"]), err["msg"]) for err in exc.errors()]
        raise LayoutError(source, issues) from None

    issues = check_layout(layout)
    errors = [i for i in issues if i.severity == "error"]
    if errors:
        raise LayoutError(source, issues)
    return layout


def load_layout(path: str | Path) -> Layout:
    """Read a YAML (or JSON) layout file from disk and validate it."""
    path = Path(path)
    source = str(path)
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise LayoutError(source, [Issue("", f"cannot read file: {exc.strerror or exc}")]) from None

    try:
        data = yaml.safe_load(text)
    except yaml.YAMLError as exc:
        where = ""
        mark = getattr(exc, "problem_mark", None)
        if mark is not None:
            where = f" (line {mark.line + 1}, column {mark.column + 1})"
        raise LayoutError(source, [Issue("", f"invalid YAML{where}")]) from None

    return parse_layout(data, source)


def dump_layout(layout: Layout) -> str:
    """Serialise a Layout to YAML text, in the same format `load_layout` reads."""
    data = layout.model_dump(mode="json", exclude_none=True)
    return yaml.safe_dump(data, sort_keys=False, default_flow_style=None, width=100)


def save_layout(layout: Layout, path: str | Path) -> None:
    Path(path).write_text(dump_layout(layout), encoding="utf-8")
