# Architecture

No future expansion is planned, so the design stays deliberately simple. The backend
interfaces exist only so that tests can swap in fakes, not to support other platforms.

## Package layout

```
mosaicctl/
  __main__.py        # entry point: python -m mosaicctl
  cli.py             # argparse subcommands -> calls into the service layer
  models.py          # dataclasses / pydantic: Layout, Grid, Mode, DisplayRef, Topology, HardwareInfo
  config.py          # load/save YAML, schema validation (FR-4)
  validate.py        # layout vs. hardware checks (FR-5, FR-6) -> list[Issue]
  service.py         # orchestration: apply, verify, snapshot, restore
  profiles.py        # profile directory, list/save/load, last-known snapshot
  backend/
    base.py          # MosaicBackend + SyncBackend protocols (interfaces)
    configure_mosaic.py  # wraps configureMosaic.exe: builds args, runs, parses output
    nvapi_sync.py    # frame lock via NVAPI GSync functions (ctypes on nvapi64.dll)
    fake.py          # in-memory fakes of both backends for tests and dry runs
tests/
  fixtures/          # recorded configureMosaic.exe outputs from real hardware
```

## Backend interface

```python
class MosaicBackend(Protocol):
    def query_hardware(self) -> HardwareInfo: ...      # GPUs, outputs, supported modes
    def query_topology(self) -> Topology | None: ...   # None = Mosaic disabled
    def apply(self, layout: Layout, dry_run: bool = False) -> list[str]: ...  # returns the commands run
    def disable(self, dry_run: bool = False) -> list[str]: ...
```

`ConfigureMosaicBackend`:
- Finds `configureMosaic.exe` in this order: `--tool-path`, then the `MOSAICCTL_TOOL` environment variable, then `PATH`, then the default install locations.
- Turns a `Layout` into command-line arguments (pure function `build_set_args(layout) -> list[str]`, unit-tested heavily).
- Runs it with `subprocess.run([...], capture_output=True, timeout=...)`, never with `shell=True`.
- Parses the `query` output into models (pure function `parse_query(text) -> ...`, tested against fixtures).
- Known commands (from NVIDIA's readme and forum posts, still to be checked against the installed version): `query`, `test`, `set`, `disable`, `listconfigcmd`, `help`. Grid options include `rows=`, `cols=`, `res=W,H,Hz`, `rotate=`, and `out=GPU,port` (row-major; if you give any display you must give all of them), with `nextgrid` for multiple grids. Output is XML on stdout. Exit codes: 0 success, 1 success with warnings, 2 invalid command or parameters.
- **`test` before `set`:** the backend runs `test` with the same arguments before every `set`. This backs FR-9 with the driver's own check, on top of our validation.
- **`listconfigcmd`** prints the current setup as a command line; use it for the `last-known` snapshot (FR-16) alongside our YAML.
- The M0 kit's `windows/mosaic-cli.ps1` is a working prototype of this backend in PowerShell. Its log of commands that worked becomes the golden test data for `build_set_args`.
- **The exact syntax and output format must still be checked against the installed driver version** (run its built-in help) before implementing. Record the version in the fixtures.

## Frame lock backend

`configureMosaic.exe` handles the Mosaic topology. It is not yet confirmed whether it
(or another NVIDIA command-line tool) can also configure frame lock on RTX PRO
Blackwell. M0 decides which of these we use:

1. **Preferred if available:** an NVIDIA command-line option for sync, wrapped in the same way as Mosaic.
2. **Otherwise:** a small ctypes binding to the NVAPI GSync functions in `nvapi64.dll`: enumerate the sync devices, get and set the sync topology, get and set the control parameters, and get the sync status. This needs the NVAPI SDK headers for the struct layouts.
3. **Fallback:** status and verification only through NVAPI, with configuration done once in the NVIDIA Control Panel and checked by the tool.

```python
class SyncBackend(Protocol):
    def query_devices(self) -> list[SyncDevice]: ...   # FR-17
    def query_status(self) -> SyncStatus: ...          # FR-18
    def apply(self, sync: SyncConfig, dry_run: bool = False) -> list[str]: ...  # FR-19
    def disable(self, dry_run: bool = False) -> list[str]: ...
```

## Apply flow

```
load layout ─► schema validate ─► query hardware + sync devices ─► validate vs hardware
   │ issues? → print all, exit 1
   ▼
snapshot current topology + sync state → profiles/last-known.yaml
   ▼
confirm with operator (summary of changes)    (dry-run: print commands, stop)
   ▼
sync.disable() ─► mosaic.apply(layout) ─► wait for displays to settle (timeout)
   │ error → exit 2, print how to restore last-known
   ▼
sync.apply(layout.sync) ─► poll until locked (timeout)
   ▼
verify topology + lock ─► mismatch / no lock → exit 3
   ▼
write session record (NFR-10), exit 0
```

## CLI

Built with `typer`; tables and status output use `rich`.

```
mosaicctl query [--json]                     # FR-1, FR-2
mosaicctl validate LAYOUT [--offline]        # FR-4 (+FR-5 unless --offline)
mosaicctl apply LAYOUT [--dry-run] [--force] [--yes]   # FR-7..FR-11, FR-16
mosaicctl disable [--dry-run] [--yes]        # FR-12
mosaicctl save NAME                          # FR-13
mosaicctl restore NAME|PATH [--dry-run] [--yes]        # FR-14
mosaicctl profiles                           # FR-15
mosaicctl sync status [--watch SECONDS] [--json]       # FR-17, FR-18, FR-22
mosaicctl sync enable LAYOUT [--dry-run] [--yes]       # FR-19 (sync section only)
mosaicctl sync disable [--dry-run] [--yes]
Global: -v/--verbose, --tool-path PATH, --profile-dir DIR, --log-file PATH
```

The profile directory defaults to `%APPDATA%\mosaicctl\profiles`.

## Error handling

- `ValidationError` holds a list of `Issue(path, message, severity)` and is printed as a table.
- `BackendError` holds the command, exit code, stdout and stderr; it maps to exit code 2.
- A changing command without `--yes` asks for confirmation, showing a summary of the change (old grid → new grid).
- Applying a layout can blank the displays for several seconds. The tool warns about this, and the operator needs another way to see the console (for example a remote session) if things go wrong; this is documented.
