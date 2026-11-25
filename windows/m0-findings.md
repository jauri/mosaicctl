# M0 Findings

Date: ____________   Operator: ____________

## A. Baseline

- Driver version / branch: ____________
- GPUs seen (count and names): ____________
- Monitors seen (count, model): ____________
- Do all 9 monitors report the same model? yes / no
- `configureMosaic.exe` found? yes / no   Path and version: ____________
- Sync device seen (PnP or NVAPI count): ____________
- Python installed? yes / no   Version: ____________

## B. Mosaic setup (R1)

- Did the 1×9 portrait 3840×2160 @ 60 Hz grid apply? yes / no
- If no, the exact error message: ____________________________________________
- Largest grid that did work: ____________
- How the 9 displays were split across the GPUs (GPU → number of displays): ____________
- How long the apply took (seconds): ______   Did the screens go black, and for how long? ______
- Was a reboot needed? yes / no
- Bezel or overlap value used, and the allowed range shown: ____________

## C. Display order and bezel (test pattern, mode 2)

- Do the cell numbers read 0 to 8 from left to right? yes / no   If not, the actual order: ____________
- Is the yellow line straight across the gaps? yes / no / needs bezel adjustment

## D. Frame lock setup (R2)

- Sync board model and firmware (shown in the Control Panel): ____________
- Are all 4 GPUs shown as connected to the board? yes / no
- Timing server display chosen: ____________
- Did every display show as locked? yes / no
- Any warnings: ____________________________________________

## E. Sync check by eye (test pattern, mode 1)

- With frame lock **on**, are the bars clean across all gaps? yes / no
- With frame lock **off**, was any tearing or stepping visible? yes / no / not tried

## F. configureMosaic.exe

- Did `listconfigcommands` (the `cm-listconfigcommands.txt` file) print a command that recreates the current setup? yes / no
- Which help or query commands produced useful output (see the `cm-*.txt` files): ____________

## G. Anything else surprising

____________________________________________________________________
____________________________________________________________________
