# mosaicctl

A Python command-line tool to configure an NVIDIA Mosaic display wall with frame lock
on Windows, from a YAML layout file. The target is a 1×9 row of portrait 4K displays
driven by 4× RTX PRO 4000 Blackwell GPUs and an RTX PRO Sync board.

**Status:** M1 (layout models and validation) is done. M0 (the hardware session on the
Windows machine) is next. The full specification is in [`specs/`](specs/README.md).

## Repository layout

```
specs/      specification: requirements, config format, architecture, milestones, decisions
mosaicctl/  the Python package (models.py, config.py so far)
layouts/    layout files; research-wall.yaml is the target wall
tests/      pytest tests
windows/    M0 kit for the Windows machine (runs without Python or Claude)
```

## Running steps

### 1. Development setup (Mac, Linux or Windows)

You need Python 3.12 or newer.

```bash
git clone <this repo>
cd mosaicctl
python3 -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -e ".[dev]"
```

### 2. Run the tests

```bash
python -m pytest                   # or: .venv/bin/python -m pytest
```

All tests run on any OS; none of them touch real hardware.

### 3. Check a layout file

Until the command-line interface exists (milestone M3), you can validate a layout from Python:

```bash
python -c "from mosaicctl.config import load_layout; l = load_layout('layouts/research-wall.yaml'); print(l.name, l.grid.surface_size)"
```

An invalid file raises `LayoutError`, which lists every problem with its location,
for example `grid.displays[4].gpu`.

### 4. M0 session on the Windows Mosaic machine (no Python needed)

The full checklist is in [`windows/README.md`](windows/README.md). In short:

1. Copy the `windows/` folder to the Windows PC. If Windows blocks the files, right-click each one → Properties → **Unblock**.
2. Double-click `Run-Collect.cmd` and enter the label `baseline`. The collector is read-only and never changes settings.
3. Set up Mosaic from the command line: double-click `Run-Mosaic.cmd` and choose `1` Help, `2` Query, `3` Test (changes nothing), then `4` Apply (asks before changing). Then collect `mosaic-on`.
4. Open `testpattern.html` fullscreen (F11) and press `2`: check that the cell order reads 0–8 and that the bezel line is straight.
5. Set up frame lock. `configureMosaic.exe` most likely can't do this, so for now use NVIDIA Control Panel; check that all 4 GPUs are on the sync board. Then collect `framelock-on`.
6. On the test pattern, press `1`: the moving bars should cross every display gap cleanly.
7. Fill in `windows/m0-findings.md` as you go, and take screenshots.
8. Bring back the `windows/results/*.zip` files, the findings form and the screenshots.

The Mosaic script also takes options in PowerShell (custom display order, extra set options):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File windows\mosaic-cli.ps1 -Action Test -Outputs "0,0 0,1 0,2 1,0 1,1 2,0 2,1 3,0 3,1"
```

Every Mosaic command and its result is logged to `windows\results\mosaic-cli-log.txt`.

You can also run the collector from PowerShell directly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File windows\collect-m0.ps1 -Label mosaic-on
# optional: -ToolPath C:\path\to\configureMosaic.exe   -OutDir D:\m0-results
```

`windows/results/` is listed in `.gitignore` because the results contain the PC name and
the monitor serial numbers. Share them inside the team only.

## Milestones

| | Milestone | Status |
|---|---|---|
| M0 | Hardware research session on Windows | kit ready, session pending |
| M1 | Models and config validation | done |
| M2 | Backend: build and parse `configureMosaic.exe` commands | waiting for M0 output |
| M3 | Hardware validation and the CLI (`query`, `validate`, `apply --dry-run`) | not started |
| M4 | Real apply, verify, snapshot/restore; frame lock (M4b) | not started |
| M5 | Operator docs and session records | not started |

See [`specs/milestones.md`](specs/milestones.md) for details.
