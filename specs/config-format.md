# Layout / Profile File Format

Layouts and saved profiles share one format: YAML (JSON is also accepted, since YAML
is a superset of it). A saved profile is just a layout file that was generated
from the live system.

## Example: the target wall, 1×9 portrait 4K on 4 GPUs

The surface is 9 × 2160 = 19,440 px wide and 3,840 px tall, before bezel correction.

```yaml
version: 1
name: research-wall
description: 1x9 portrait 4K wall, 4x RTX PRO 4000 Blackwell, internal frame lock

grid:
  rows: 1
  cols: 9
  mode:
    width: 3840          # native (landscape) panel resolution
    height: 2160
    refresh_hz: 60
  rotation: 90           # 0 | 90 | 180 | 270, applied to every display (portrait = 90 or 270)
  bezel:
    horizontal_px: 0     # one value for every gap between neighbours; negative = overlap
    vertical_px: 0       # unused for a single row, kept for generality

  # Cell (row, col) -> physical output. Col 0 is the left-most display.
  # GPU and output indexes are as reported by `mosaicctl query`.
  # edid_serial is optional; if given, validation checks that the monitor matches
  # (this catches re-patched cables).
  displays:   # split 3/2/2/2 across 4 GPUs (to be confirmed when cabling)
    - { row: 0, col: 0, gpu: 0, output: 0, edid_serial: "..." }
    - { row: 0, col: 1, gpu: 0, output: 1, edid_serial: "..." }
    - { row: 0, col: 2, gpu: 0, output: 2, edid_serial: "..." }
    - { row: 0, col: 3, gpu: 1, output: 0, edid_serial: "..." }
    - { row: 0, col: 4, gpu: 1, output: 1, edid_serial: "..." }
    - { row: 0, col: 5, gpu: 2, output: 0, edid_serial: "..." }
    - { row: 0, col: 6, gpu: 2, output: 1, edid_serial: "..." }
    - { row: 0, col: 7, gpu: 3, output: 0, edid_serial: "..." }
    - { row: 0, col: 8, gpu: 3, output: 1, edid_serial: "..." }

sync:
  enabled: true
  source: internal               # v1 supports internal only
  server: { gpu: 0, output: 0 }  # timing server display; all others become clients
  require_lock: true             # apply fails (exit 3) if any GPU does not lock
```

`mosaicctl save` can generate this file from a working, hand-configured setup,
including the EDID serials, so that nobody has to type them in.

## Fields

| Field | Type | Required | Rules |
|---|---|---|---|
| `version` | int | yes | Must be `1`. Allows the format to change later. |
| `name` | str | yes | `[a-z0-9-]+`; used as the profile file name. |
| `description` | str | no | Free text. |
| `grid.rows`, `grid.cols` | int | yes | ≥ 1; `rows × cols` ≥ 2. |
| `grid.mode.width/height` | int | yes | Must be supported by every display (FR-5). |
| `grid.mode.refresh_hz` | number | yes | e.g. `59.94`, `60`. |
| `grid.rotation` | int | no (0) | One of 0, 90, 180, 270. |
| `grid.bezel.horizontal_px` | int | no (0) | Negative values mean overlap. The limits come from the driver. |
| `grid.bezel.vertical_px` | int | no (0) | Same as above. |
| `grid.displays` | list | yes | Exactly `rows × cols` entries; each (row, col) appears once; each (gpu, output) appears once. |
| `displays[].gpu` | int | yes | Index from `mosaicctl query`. |
| `displays[].output` | int | yes | Connector index on that GPU. |
| `displays[].edid_serial` | str | no | If present, validation checks that the monitor on that output matches. |
| `sync` | object | no | Leave it out for no frame lock. |
| `sync.enabled` | bool | yes (if `sync`) | |
| `sync.source` | str | no (`internal`) | Only `internal` in v1; house sync / genlock is out of scope. |
| `sync.server` | DisplayRef | yes (if enabled) | Must be one of `grid.displays`. |
| `sync.require_lock` | bool | no (true) | |

The sync field names are provisional until M0 confirms which settings the RTX PRO
Sync board and NVAPI actually expose.

## Decisions

- Displays are identified by GPU/output index, with an optional EDID serial check.
- Bezel/overlap is a single value for the whole grid.
- Every display must share the same mode. Mosaic expects identical displays, and validation warns if the EDIDs show different models.
