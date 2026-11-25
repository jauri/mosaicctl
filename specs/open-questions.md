# Decisions and Open Questions

## Decisions (2026-11-25)

| # | Topic | Decision |
|---|---|---|
| Q1 | Hardware | One PC, 4× RTX PRO 4000 Blackwell, displays split 3/2/2/2 (the exact cabling is set when wiring). |
| Q1c | Wall | 1×9 grid, portrait (rotation 90), 3840×2160 @ 60 Hz per panel. |
| Q2 | Driver | The current production-branch driver, with its version recorded in M0. |
| Q3 | Frame lock | Required, in scope for v1. |
| Q4 | Display ID | GPU/output index plus an optional EDID serial check. |
| Q5 | Operation | An operator at the console; prompts by default, `--yes` to skip them. |
| Q6 | Admin | Running as Administrator is fine; changing commands check for it. |
| Q8 | Bezel | One value for the whole grid. |
| Q9 | Context | A research installation; no library restrictions. |
| Q10 | Future expansion | None planned; keep v1 simple. |
| Q11 | Sync board | NVIDIA RTX PRO Sync (the Blackwell-era board). |
| Q12 | Sync source | Internal (one display/GPU is the timing server). |
| Q13 | Multi-PC | No, one PC. |
| Q14 | Stereo / VRR | Neither. |
| Q15 | Session records | `%LOCALAPPDATA%\mosaicctl\sessions\`, with a `--record-dir` override. |

## Risks to check in M0

| # | Risk | What happens if it fails |
|---|---|---|
| R1 | Mosaic may not allow a ~19,440×3,840 surface, or a 1×9 grid across 4 GPUs. | Change the layout (for example drop to fewer panels or a different split) before building anything. |
| R2 | The RTX PRO Sync board may not connect all 4 GPUs in one system. | Frame lock would need different hardware. |
| R3 | `configureMosaic.exe` may not handle frame lock. | Use the NVAPI ctypes route (option 2 in the architecture), which is more work. |
| R4 | Applying 4K × 9 across 4 GPUs may take a long time or need a reboot or retries. | Adjust the timeouts and the settle/retry logic in the apply flow. |
