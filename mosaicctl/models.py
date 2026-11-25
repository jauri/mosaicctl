"""Data models for layout / profile files (specs/config-format.md).

Pydantic handles types, required fields and simple ranges. Rules that span
several fields (display count, duplicate cells, sync server membership) live in
`check_layout`, so that every problem can be reported at once (FR-6) instead of
stopping at the first failing validator.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

Rotation = Literal[0, 90, 180, 270]


class _Model(BaseModel):
    # Unknown keys are errors: a typo like `refresh: 60` must not be silently ignored.
    model_config = ConfigDict(extra="forbid", frozen=True)


class Mode(_Model):
    """Per-display timing. Width/height are the panel's native (unrotated) resolution."""

    width: int = Field(gt=0)
    height: int = Field(gt=0)
    refresh_hz: float = Field(gt=0)


class Bezel(_Model):
    """Gap between neighbouring displays in pixels; negative means overlap."""

    horizontal_px: int = 0
    vertical_px: int = 0


class OutputRef(_Model):
    """A physical connector: GPU index and output index, as reported by `mosaicctl query`."""

    gpu: int = Field(ge=0)
    output: int = Field(ge=0)

    def key(self) -> tuple[int, int]:
        return (self.gpu, self.output)

    def label(self) -> str:
        return f"gpu {self.gpu} output {self.output}"


class DisplayCell(OutputRef):
    """One grid cell mapped to a physical output. Row 0 is the top, col 0 is the left."""

    row: int = Field(ge=0)
    col: int = Field(ge=0)
    edid_serial: str | None = None


class Grid(_Model):
    rows: int = Field(ge=1)
    cols: int = Field(ge=1)
    mode: Mode
    rotation: Rotation = 0
    bezel: Bezel = Bezel()
    displays: list[DisplayCell]

    @property
    def surface_size(self) -> tuple[int, int]:
        """Total desktop size in pixels (width, height), after rotation and bezel correction."""
        w, h = self.mode.width, self.mode.height
        if self.rotation in (90, 270):
            w, h = h, w
        return (
            self.cols * w + (self.cols - 1) * self.bezel.horizontal_px,
            self.rows * h + (self.rows - 1) * self.bezel.vertical_px,
        )


class SyncConfig(_Model):
    """Frame lock settings. v1 supports internal sync only."""

    enabled: bool
    source: Literal["internal"] = "internal"
    server: OutputRef | None = None
    require_lock: bool = True


class Layout(_Model):
    version: Literal[1]
    name: str = Field(pattern=r"^[a-z0-9-]+$")
    description: str | None = None
    grid: Grid
    sync: SyncConfig | None = None


@dataclass(frozen=True)
class Issue:
    """One validation problem. `path` points into the layout file, e.g. `grid.displays[3].gpu`."""

    path: str
    message: str
    severity: Literal["error", "warning"] = "error"

    def __str__(self) -> str:
        where = f"{self.path}: " if self.path else ""
        return f"{self.severity}: {where}{self.message}"


def check_layout(layout: Layout) -> list[Issue]:
    """Cross-field rules from config-format.md. Returns every issue found (FR-6)."""
    issues: list[Issue] = []
    grid = layout.grid
    expected = grid.rows * grid.cols

    if expected < 2:
        issues.append(Issue("grid", "a Mosaic grid needs at least 2 displays (rows x cols >= 2)"))

    if len(grid.displays) != expected:
        issues.append(
            Issue(
                "grid.displays",
                f"expected {expected} displays for a {grid.rows}x{grid.cols} grid, "
                f"got {len(grid.displays)}",
            )
        )

    seen_cells: dict[tuple[int, int], int] = {}
    seen_outputs: dict[tuple[int, int], int] = {}
    for i, d in enumerate(grid.displays):
        path = f"grid.displays[{i}]"
        if d.row >= grid.rows or d.col >= grid.cols:
            issues.append(
                Issue(path, f"cell (row {d.row}, col {d.col}) is outside the {grid.rows}x{grid.cols} grid")
            )
        cell = (d.row, d.col)
        if cell in seen_cells:
            issues.append(
                Issue(path, f"cell (row {d.row}, col {d.col}) is already used by grid.displays[{seen_cells[cell]}]")
            )
        else:
            seen_cells[cell] = i
        if d.key() in seen_outputs:
            issues.append(
                Issue(path, f"{d.label()} is already used by grid.displays[{seen_outputs[d.key()]}]")
            )
        else:
            seen_outputs[d.key()] = i

    sync = layout.sync
    if sync is not None and sync.enabled:
        if sync.server is None:
            issues.append(Issue("sync.server", "a timing server display is required when sync is enabled"))
        elif sync.server.key() not in seen_outputs:
            issues.append(
                Issue("sync.server", f"timing server {sync.server.label()} is not one of grid.displays")
            )

    return issues
