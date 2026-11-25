# Milestones, Testing and Acceptance

## M0: Research spike (on the Windows Mosaic machine)
- Install or locate `configureMosaic.exe`, and record the driver and tool versions.
- Capture the output of help, a GPU/display query, and the current-topology query, both with Mosaic on and off. Save it to `tests/fixtures/`.
- Manually apply the real 1×9 portrait grid with bezel correction and record the exact command that worked.
- Find out: whether admin rights are needed, how long an apply takes, and the overlap/bezel limits.
- **Hardware limits (first):** confirm that Mosaic supports a 1×9 grid of rotated 4K displays across 4 GPUs: the total surface (about 19,440×3,840), the outputs used per GPU, and whether the 3/2/2/2 split is allowed.
- **Frame lock:** confirm the RTX PRO Sync board model and firmware, and that it can connect all 4 GPUs at once. Find out whether any NVIDIA command-line tool can set frame lock; if not, get the NVAPI SDK and confirm that the GSync calls work from a small ctypes test. Record the sync status with lock on and off as fixtures.
- **Kit:** `windows/` contains a read-only collector, a test pattern and a findings form that run without Claude (see `windows/README.md`).
- **Exit:** the filled-in `windows/m0-findings.md` and the results zips, plus a notes file on the tool's syntax and the frame lock route (option 1, 2 or 3 in the architecture); answers to the open questions about the backend.

## M1: Models and config (cross-platform)
- `models.py`, `config.py`, schema validation, and loading and saving YAML in both directions.
- Tests: valid and invalid layout files, with all issues reported (FR-4, FR-6).

## M2: Backend parsing and command building (cross-platform)
- `parse_query` against the fixtures; `build_set_args` for each grid feature (FR-8).
- `FakeBackend`.
- Tests: golden tests of layout → expected argument list.

## M3: Validation against hardware and the CLI
- `validate.py` (FR-5), `cli.py` with `query`, `validate` and `apply --dry-run`.
- Tests: CLI tests using `FakeBackend`.

## M4: Real apply, verify, snapshot and restore
- `service.py` and `profiles.py`, with exit codes (NFR-7) and logging (NFR-6).
- Manual test on the real wall (see the acceptance criteria below).

## M4b: Frame lock
- `nvapi_sync.py` (or a command-line wrapper, depending on what M0 found), `sync status/enable/disable`, and the sync step built into apply (FR-17 to FR-23).
- Tests: parsing the sync status and building the config on fixtures; the ordering of the apply flow checked with fakes.

## M5: Operation
- A README with setup steps, an operator quick-reference card, and the session-record format (NFR-10). Packaging as an `.exe` is optional.

## Testing strategy
- **Unit tests** (pytest): everything except `subprocess` runs on macOS or Linux CI.
- **Fixture tests**: real tool output, versioned by driver release.
- **Hardware tests**: a manual checklist run on the target machine before each release.

## Acceptance criteria (v1)
1. `mosaicctl query` correctly lists every GPU and display on the target machine.
2. A layout with a wrong display count or an unsupported mode fails `validate` with clear messages, and makes no change.
3. `mosaicctl apply research-wall.yaml` turns non-Mosaic displays into the specified grid, and verification passes.
4. Bezel correction, overlap and rotation changes show visibly on the wall and in `query`.
5. `save`, then a manual change, then `restore` brings back the original setup.
6. After a failed or bad apply, `restore last-known` recovers the previous setup.
7. `--dry-run` never changes the displays.
8. After `apply`, `sync status` shows every GPU locked to the specified timing server, with no tearing between displays (checked visually with a moving vertical-bar test pattern).
9. Disconnecting a GPU's sync cable is reported as loss of lock by `sync status --watch`.
