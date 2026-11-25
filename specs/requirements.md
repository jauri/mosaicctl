# Requirements

IDs are referenced from the other spec files and the tests.

## Functional

### Discovery and query
- **FR-1** List the NVIDIA GPUs in the system and the display outputs connected to each one.
- **FR-2** Report whether Mosaic is currently enabled and, if so, the current grid: rows, columns, per-display resolution and refresh rate, display order, bezel/overlap values and rotation.
- **FR-3** Offer human-readable output (default) and JSON output (`--json`) for scripting.

### Validation
- **FR-4** Validate a layout file against the schema (types, required fields, ranges) without touching the hardware.
- **FR-5** Validate a layout against the detected hardware:
  - the number of displays required equals `rows × cols` and every referenced output exists and is connected;
  - the requested resolution and refresh rate are supported by every display in the grid;
  - the layout fits within the Mosaic limits of the GPU or driver (to be found out via the backend).
- **FR-6** Validation reports **all** problems it finds, not just the first one, and exits non-zero if there are any.

### Apply
- **FR-7** Apply a layout file to create or replace the Mosaic topology.
- **FR-8** Support per-grid settings: rows, cols, resolution, refresh rate, rotation (0/90/180/270), horizontal and vertical bezel correction or overlap in pixels (positive = bezel gap, negative = overlap), and the display-to-cell mapping.
- **FR-9** Always run validation (FR-4, FR-5) before applying; `--force` skips only the hardware checks.
- **FR-10** `--dry-run` prints the exact backend command(s) that would be run, without running them.
- **FR-11** After applying, re-query and verify that the live topology matches the layout; report any differences.
- **FR-12** Disable Mosaic (go back to individual displays).

### Profiles
- **FR-13** Save the current live topology to a profile file in the same format as a layout file, so that it can be re-applied.
- **FR-14** Restore (apply) a saved profile by name or path.
- **FR-15** List the saved profiles in the profile directory.
- **FR-16** Before every apply, automatically snapshot the current topology as `last-known.yaml`, so that `mosaicctl restore last-known` can undo a bad change.

### Frame lock
- **FR-17** Detect the sync board(s): whether one is present, its firmware version, which GPU(s) it is attached to, and the status of its ports.
- **FR-18** Report the live sync state: whether frame lock is enabled, which display or GPU is the timing server and which are clients, whether each GPU is locked, and the sync rate.
- **FR-19** Configure frame lock from the layout's `sync` section: choose the timing server display and make every other display on all 4 GPUs a client, with internal sync as the source.
- **FR-20** Order of operations on apply: disable frame lock → apply Mosaic → wait for the displays to settle → re-enable frame lock → verify lock. A sync failure is reported separately from a Mosaic failure.
- **FR-21** Validation (FR-5) also checks: the board is present if the layout asks for sync; every GPU used by the grid is connected to the sync board (all 4); and every display runs the same refresh rate.
- **FR-22** `mosaicctl sync status` can be run on its own, as a quick health check during experiments, with an optional `--watch` mode that re-checks every N seconds and flags loss of lock.
- **FR-23** Include the frame-lock state in saved profiles and the `last-known` snapshot.

## Non-functional

- **NFR-1 Platform:** Windows 11 x64, Python 3.12+, and an RTX PRO Blackwell driver that supports Mosaic and frame lock.
- **NFR-2 Dependencies:** any well-maintained libraries may be used. The proposed stack is `pydantic` (models and validation), `PyYAML`, `typer` (CLI), `rich` (tables and status output) and `pytest`. Packaging as a single `.exe` with PyInstaller is optional.
- **NFR-3 Backend isolation:** all knowledge of `configureMosaic.exe` syntax and output parsing lives in one module, so it can be swapped (for example for NVAPI later) without changing the CLI or config code.
- **NFR-4 Testability:** everything except the backend runner can be unit-tested on any OS, including macOS dev machines, using recorded `configureMosaic.exe` output as fixtures.
- **NFR-5 Safety:** never change the display configuration without validating first; always keep a restorable snapshot; `--dry-run` everywhere a change is possible.
- **NFR-6 Logging:** every backend command, its exit code and its stdout/stderr go to a log file (default `%LOCALAPPDATA%\mosaicctl\mosaicctl.log`), with `-v` to also show them on the console.
- **NFR-7 Exit codes:** `0` success, `1` validation failure, `2` backend/driver error, `3` post-apply verification mismatch, `64` usage error.
- **NFR-8 Operator use:** it is designed for an operator at the console. Changing commands show a summary and ask for confirmation; `--yes` skips the prompt for scripted use.
- **NFR-10 Reproducibility (research):** every apply writes a timestamped JSON record (layout, driver version, sync board firmware, the result of the post-apply verification) to `%LOCALAPPDATA%\mosaicctl\sessions\`, which `--record-dir` can override. This lets an experiment session state the display configuration it ran under.
- **NFR-11 Driver:** target the current NVIDIA production-branch driver for RTX PRO. The tested version is recorded in the fixtures and the README, and the tool warns when it runs on a different driver version.
- **NFR-9 Privileges:** running as Administrator is acceptable. Changing commands (`apply`, `disable`, `restore`, `sync enable/disable`) check for elevation at startup and refuse with a clear message if it is missing. Read-only commands (`query`, `validate`, `sync status`) should work without elevation where the driver allows it.
