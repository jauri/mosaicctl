# mosaicctl — Specification

**Status:** Draft v0.3 (2026-11-25)
**Context:** A research installation, run by an operator at the console.
**Target hardware:** one Windows PC with 4× NVIDIA RTX PRO 4000 Blackwell GPUs and an
NVIDIA RTX PRO Sync board. It drives a **1×9 row of portrait 4K displays**
(3840×2160 @ 60 Hz per panel, about a 19,440×3,840 surface) with internal frame lock.

`mosaicctl` is a Python command-line tool that configures an **NVIDIA Mosaic** display
surface on **Windows** from a declarative layout file. It wraps NVIDIA's
`configureMosaic.exe` utility so that a complex video-wall setup can be applied,
checked, saved and restored repeatably, without clicking through the NVIDIA
Control Panel.

## Problem

Setting up Mosaic by hand is slow and error-prone: the grid order, bezel correction,
overlap, rotation and timing all have to be entered correctly, and the setup is
hard to reproduce after a driver update, a hardware swap or a reboot that loses
the topology. We want a single command that puts the wall into a known state.

## Scope (v1)

- One Mosaic grid of identical displays spanning several GPUs (the target is 1×9 on 4 GPUs).
- Windows only, using `configureMosaic.exe` as the backend.
- Features:
  1. **Apply** a layout from a config file.
  2. **Query / validate**: list GPUs, displays and the current topology, and check a config against the hardware before applying it.
  3. **Save / restore** profiles of the current setup.
  4. **Grid tuning**: bezel correction, overlap, rotation, resolution and refresh rate.
  5. **Frame lock**: configure and verify frame lock through the sync board, so that all displays refresh in step.

## Out of scope (v1)

- Linux / `nvidia-settings` / xorg MetaModes.
- Using NVAPI for Mosaic itself. NVAPI is used only for frame lock, where `configureMosaic.exe` may not be enough (see architecture).
- Multiple simultaneous Mosaic grids, or a grid mixed with standalone displays.
- A GUI.
- Unattended or boot-time operation. It may still work, but it is not a v1 requirement.
- House sync / genlock, stereo 3D and G-Sync/VRR.
- Frame lock across multiple PCs.
- Any planned expansion: multi-grid, Linux, multi-PC. The design should stay simple rather than general.

## Documents

| File | Contents |
|---|---|
| [requirements.md](requirements.md) | Functional and non-functional requirements |
| [config-format.md](config-format.md) | Layout / profile file schema with examples |
| [architecture.md](architecture.md) | Modules, backend wrapper, CLI commands, error handling |
| [milestones.md](milestones.md) | Build order, testing strategy, acceptance criteria |
| [open-questions.md](open-questions.md) | Decisions still to be made |
