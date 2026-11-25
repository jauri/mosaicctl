# M0 Windows Session Kit

Everything in this folder runs on the Windows Mosaic machine **without Claude and
without Python**. It checks the two big risks, R1 (can Mosaic drive a 1×9 portrait 4K
wall on 4 GPUs?) and R2 (can the sync board frame-lock all 4 GPUs?), and records the
raw tool output we need to write the real `mosaicctl` backend.

| File | What it is |
|---|---|
| `Run-Collect.cmd` | Double-click to run the collector. It asks for a label. |
| `collect-m0.ps1` | The collector itself. **Read-only**: it never changes any display, Mosaic or sync setting. |
| `testpattern.html` | Moving bars and cell numbers, for checking frame lock, display order and bezels by eye. |
| `m0-findings.md` | A form to fill in during the session (print it, or edit it in Notepad). |

## Before you go

- Copy this whole `windows` folder to the Windows PC (USB stick, Dropbox, etc.).
- If Windows blocks the scripts because they came from another computer, right-click each file → Properties → tick **Unblock**. `Run-Collect.cmd` already bypasses the PowerShell execution policy, for this script only.
- Have `configureMosaic.exe` available. If the collector can't find it (step 1 will tell you), download NVIDIA's Mosaic command-line utility for your RTX PRO driver, put it in this folder, and run the collector again.
- Bring a phone to take photos of the wall and screenshots of NVIDIA Control Panel.

## The session

Each **Collect** step means: double-click `Run-Collect.cmd` and type the label shown.
Each run creates `results\<time>-<label>\` and a matching `.zip`.

1. **Collect `baseline`** before changing anything.
   Check `summary.txt`: it should show 4 GPUs, 9 monitors, the driver version, and whether `configureMosaic.exe` and a sync device were found.
   - Fill in section A of `m0-findings.md`.

2. **Set up Mosaic by hand.** In NVIDIA Control Panel → *Workstation* → *Set up Mosaic*, create a 1×9 grid with portrait rotation at 3840×2160 @ 60 Hz.
   - Time how long the apply takes (stopwatch), and note any error or limit message. **This tests R1.**
   - If the 1×9 grid is refused, note exactly what the message says and what the largest working option is (for example a smaller grid, or a different GPU split).
   - Take screenshots of each page of the wizard.
   - Fill in section B.

3. **Collect `mosaic-on`.** `summary.txt` should now show **one** desktop screen of about 19440×3840.

4. **Check display order and bezels.** Open `testpattern.html` in Chrome or Edge, press F11 (or click) for fullscreen, then press `2`.
   - The cell numbers should read 0 to 8 from left to right, one per panel.
   - The yellow diagonal should look straight across the panels; if it kinks at the gaps, the bezel correction needs adjusting.
   - Photograph the wall. Fill in section C.

5. **Set up frame lock.** In NVIDIA Control Panel → *Workstation* → *Synchronize displays* (the page name may differ slightly), make one display the timing server and the others clients.
   - Confirm that the sync board shows **all 4 GPUs** connected. **This tests R2.**
   - Screenshot the sync page, including the status indicators.
   - Fill in section D.

6. **Collect `framelock-on`.**

7. **Check sync by eye.** On the test pattern, press `1` (moving bars).
   - With frame lock working, each white bar and the red diagonal cross every panel gap in one clean line.
   - Press ↑ a few times to speed the bars up; steps or tears at the gaps mean the displays are not locked.
   - Optional: turn frame lock off, watch the difference, then **Collect `framelock-off`** and turn it back on.
   - Fill in section E.

8. **Optional: check administrator rights.** Right-click `Run-Collect.cmd` → *Run as administrator* and **Collect `admin`**. Compare its `summary.txt` with `framelock-on` (some driver queries only work elevated).

9. **Optional: if Python 3.12+ is installed**, copy the whole project over and run the M1 tests:
   ```
   py -m pip install -e ".[dev]"
   py -m pytest
   ```

## Bring back

- Every `results\*.zip` file.
- The filled-in `m0-findings.md`.
- The screenshots and photos.

On the Mac, put them in `PythonProject/windows/results/`. The raw command outputs
become the test fixtures for milestone M2.

## Privacy note

The results include the PC name, the monitor serial numbers and the driver details.
That's fine inside the team, but check before posting them anywhere public.

## If something goes wrong

- The collector never stops partway through. A failed step is listed with a `!` in `summary.txt`, and the rest still runs.
- If a `configureMosaic` command shows `TIMEOUT`, open its `cm-*.txt` file to see what it printed.
- If the displays go black after step 2 or 5, wait about 30 seconds; Mosaic changes can take a while across 4 GPUs. If they stay black, reboot, or use the NVIDIA Control Panel from a remote desktop session to disable Mosaic.
