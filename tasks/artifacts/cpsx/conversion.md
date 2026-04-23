# Goal

We are working on [this](https://github.com/jotego/jtcores/issues/511) github issue.

## Description

The cores: cps1, cps15 and cps2 were designed before the `mem.yaml` architecture was in place. They use a core-specific module to handle SDRAM access: jtcps1_sdram.

This module is responsible of

- download process: when the FPGA receives the game stream of data. This data is the .rom file that `jtframe mra` produces in the project `rom` folder.
- connecting each module (main, video, sound) to the SDRAM and multiplex access to it.

These functions were taken over by `mem.yaml`, which is based on templates and the `jtframe mem` utility. All other cores at the time were converted and all new cores since then have been designed to use `mem.yaml`. But the old CPSx cores were not straightforward to convert. The github issue lists some of these.

## Tests

You will need to run long simulations with `jtsim -load` and check that video and sound are not broken. You need to test each core: cps1, cps15 and cps2. But not all games. These are some suggestions of games to test:

- cps1: 1941
- cps15: dino. Use `jtsim -inputs reg.cab` to get the coin inserted, which will produce a sound
- cps2: mpang

In the folder `/nobackup/regression/` you have subfolder for each core and each game, then a `valid` folder that contains expected simulation frames and a video of a reference simulation. For example `/nobackup/regression/cps2/mpang/valid/frames.zip` contains the reference frames for cps2 mpang.

If the image content has moved a bit in and appears say one frame ahead or after, that is fine. The kind of failures you will find when working on this will always be quite severe, like no boot, no image, no sound...

Video and bootup confirmation can usually be achieved with maybe 500 frames: `jtsim -video 500`. But sound confirmation will normally require a longer simulation, like 2000 frames. These simulations will take anywhere from 10 to 40 minutes. Wait patiently. They will not hang up.

For initial bootup/video confirmation, you can skip the sound output in the sim to speed it up: `jtsim -q`

### Compilation

Apart from testing simulation, a `jtcore <corename>` compilation must be executed on each one of them to validate the conversion as there are errors that may only appear during actual FPGA compilation. This is the last step in verification.

## One core at a time

A possible approach to this is to convert one core at a time, while keeping the others alive. They share a lot of files so if you go that route, you first need to decouple the core you will start with from the rest and then convert it. The non-converted cores should still work

## Keeping Track

This is going to be a long task. Keep notes of what you are doing and what you have to do next. Keep notes of the successful changes. This will let you finish the task and, in case you get stuck, it will help me go over your work and suggest the next step.

# Task

Examine the issue, the `mem.yaml` documentation and related templates and make a plan for this conversion. Append the plan to this file, and after that, start executing it.

# Plan - 2026-04-23

## Current Findings

- Issue `jotego/jtcores#511` is no longer blocked by header-driven bank selection. That part already landed in JTFRAME through the `BALUT/LUTSH` path used by `jtframe_dwnld`.
- The still-relevant CPS-specific gaps are:
  - `mem.yaml` still cannot express the per-slot SDRAM `LATCH` setting used by `jtcps1_sdram`.
  - CPS1/CPS1.5 still need the sound CPU payload moved out of bank 0 so the download path no longer depends on the old variable `SND_OFFSET` logic.
  - CPS game modules still instantiate `jtcps1_sdram`, so they are not yet using the generated `jt<core>_game_sdram` wrapper.
- `cores/cps1/cfg/xmem.yaml` is only a draft. It still uses unsupported fields (`region`, `latch`) and cannot be used as-is.
- `cores/cps15/cfg/macros.def` and `cores/cps2/cfg/macros.def` explicitly force `GAMETOP=jtcps15_game` / `jtcps2_game`. Those overrides will block the generated wrapper until removed or updated.
- The CPS MRA headers already contain the information needed by the generated downloader:
  - CPS1: `[header].offset.regions=["audiocpu","oki","gfx"]`
  - CPS1.5/CPS2: `[header].offset.regions=["audiocpu","qsound","gfx","firmware"]`
- The custom downloader logic in `jtcps1_prom_we.v` is not fully obsolete. After migration, the game modules still need local logic for:
  - `cfg_we`
  - `kabuki_we`
  - CPS2 key writes / joystick mode
  - Pang3 CPU-data decryption during download
  - EEPROM dump/load handling

## Execution Order

1. Extend JTFRAME `mem.yaml` support so the generated wrapper can represent the existing CPS SDRAM timing behavior.
   - Add a `latch` field to `SDRAMBus`.
   - Thread that field through the parser and `game_sdram.v` so ROM/VRAM/object slots can set `SLOTn_LATCH`.
   - Keep this change backward compatible for all existing mem-managed cores.

2. Convert CPS1 first, while keeping CPS1.5 and CPS2 on `jtcps1_sdram`.
   - Create `cores/cps1/cfg/mem.yaml`.
   - Keep the SDRAM layout equivalent to the current core except for the planned audio CPU relocation.
   - Move the sound CPU payload to bank 1 so CPS1 no longer depends on the old variable offset download path.
   - Replace the `jtcps1_sdram` instantiation in `jtcps1_game.v` with:
     - direct use of generated SDRAM ports
     - local header/download side-effect logic (`cfg_we`, Pang3 decrypt if needed)
     - local EEPROM instantiation
   - Verify `jtframe mem cps1`, `jtsim` boot/video first, then longer sound confirmation, then `jtcore cps1`.

3. Convert CPS1.5 next, reusing the CPS1 structure.
   - Add `cores/cps15/cfg/mem.yaml` (likely sharing a common fragment where possible).
   - Remove/update `GAMETOP=jtcps15_game` so the wrapper becomes active.
   - Move the sound CPU payload to bank 1 and keep QSound samples / firmware behavior intact.
   - Keep Kabuki handling in the handwritten game logic.
   - Verify `jtframe mem cps15`, `jtsim` with `dino` plus `reg.cab`, then `jtcore cps15`.

4. Convert CPS2 last.
   - Add `cores/cps2/cfg/mem.yaml`.
   - Remove/update `GAMETOP=jtcps2_game`.
   - Keep CPS2-specific object RAM, object bank selection, QSound firmware, and key writes in the handwritten game logic.
   - Preserve the MiST/SiDi latch-sensitive object path in the generated slot parameters.
   - Verify `jtframe mem cps2`, `jtsim` with `mpang`, then `jtcore cps2`.

5. Finish with regression-oriented cleanup.
   - Compare each converted core against the reference frames/videos under `/nobackup/regression`.
   - Record which sims/builds passed and any remaining deltas directly in this file.

## Execution Notes

- 2026-04-23: Read `README.md`, `modules/jtframe/doc/jtframe-mem.md`, `modules/jtframe/doc/sdram.md`, the CPS core READMEs, issue `#511`, and the related issue comments.
- 2026-04-23: Confirmed that header-driven bank selection is already supported by `jtframe_dwnld` via `BALUT/LUTSH`, so the first safe implementation step is the missing per-slot `latch` support in JTFRAME.
- 2026-04-23: Added generic `latch` support to JTFRAME `mem.yaml` parsing/templates and documented it. Verified with `go test ./mem/...` under `modules/jtframe/src/jtframe`.
- 2026-04-23: Added `cores/cps1/cfg/mem.yaml`, removed the explicit CPS1 `GAMETOP` override so `JTFRAME_MEMGEN` can select `jtcps1_game_sdram`, and split `jtcps1_game.v` so CPS1 uses the generated SDRAM wrapper while CPS1.5/CPS2 stay on `jtcps1_sdram`.
- 2026-04-23: Moved the CPS1-only side effects into `jtcps1_game.v` for the mem-managed path:
  - header/config write pulse (`cfg_we`)
  - Pang3 download-byte decryption through `post_data`
  - EEPROM dump/load handling
  - direct wiring for the combined RAM/VRAM writable SDRAM slot
- 2026-04-23: `jtframe mem cps1 -t mist` and `-t mister` now complete. The generated wrapper/interface issues found during the first `jtcore cps1 -t mist -q` attempt were fixed:
  - removed redundant explicit `cs:` names for the CPS1 gfx buses in `mem.yaml`
  - reduced the CPS1 object-address width by one bit (the old shared helper kept a redundant leading zero for the CPS2 path)
  - fixed legacy `snd_vu` / `snd_peak` wiring so `JTFRAME_MEMGEN` no longer relies on implicit nets
- 2026-04-23: `jtcore cps1 -t mist -q` no longer fails in the CPS1 lint stage, but the Quartus step is currently blocked by an environment/tool issue: `quartus_sh -v` hangs before the actual compile starts. This needs to be retried once the Quartus environment is responsive.
- 2026-04-23: The legacy CPS1 `ver/game/sim.sh` path is not suitable after this conversion because it preloads SDRAM using `rom2hex.cc`, which still emits the old bank layout (sound+PCM together, gfx in bank 3 only). For converted CPS1 verification, the correct path is direct `jtsim -load`.
- 2026-04-23: Added `tasks/scripts/jtcfgstr-compat.sh` because the old CPS sim wrappers still expect the removed `jtcfgstr` CLI shape. Also fixed `cores/cps1/ver/game/rom2hex.cc` by adding `<cstdint>` so the helper still builds on the current host compiler.
- 2026-04-23: Direct CPS1 video smoke test:
  - command: `jtsim -setname 1941 -load -q -video 500 -d SKIP_RAMCLR -d JTFRAME_SIM_ROMRQ_NOCHECK -d VIDEO_START=2`
  - result: completed in `12'45"` at `59.64 Hz`
  - frame dump milestones looked plausible enough for a first boot/video pass (`frame_00170.jpg`, `frame_00323.jpg`, `frame_00502.jpg` all appeared, matching the README expectation that visible output starts around frame 170)
  - however, this is not yet a full CPS1 pass because of the bank dump issue below
- 2026-04-23: Direct CPS1 sound smoke test:
  - command: `jtsim -setname ffight -load -inputs ../ffight/reg.cab -frame 400 -d SKIP_RAMCLR -d JTFRAME_SIM_ROMRQ_NOCHECK -d VIDEO_START=2`
  - result: completed in `17'55"` at `59.64 Hz`
  - generated `test.wav` remained silent (`mean_volume: -91.0 dB`, `max_volume: -91.0 dB`) across ~7.3 seconds of captured audio, so CPS1 audio is not validated yet
- 2026-04-23: Key blocker found from the direct `jtsim -load` dumps:
  - `sdram_bank0.bin`: non-zero
  - `sdram_bank1.bin`: non-zero
  - `sdram_bank2.bin`: non-zero
  - `sdram_bank3.bin`: all zero bytes
  - this strongly suggests the CPS1 download mapping is still wrong for the gfx region even though the `.rom` header itself looks sane (`00 04 40 04 40 05 ff ff ff ff`)
  - likely next debug step: inspect how `BALUT` consumes the CPS1 header bytes during `jtframe_dwnld` and confirm whether bank 3 is being skipped or if gfx is accidentally landing in bank 2
- 2026-04-23: Kept the JTFRAME generic behavior unchanged after review: a core must choose either fixed `JTFRAME_BA?_START` bank selection or header-driven `BALUT`, not both. CPS1 stays on `BALUT`.
  - added `JTFRAME_BA1_START=0x200000`, `JTFRAME_BA2_START=0x220000`, `JTFRAME_BA3_START=0x2A0000` to `cores/cps1/cfg/macros.def`
  - mapped CPS1 `rom.regions` in `mame2mra.toml` to those starts (`audiocpu`, `oki`, and both `gfx` definitions) using the existing `/nobackup/jtmisc/jtbin/mra` comments as the source of truth; the chosen values cover the largest normal CPS1 layouts while ignoring the intentional `cps1mult` outlier
  - verified the reverted JTFRAME path with `go test ./mem/...`
- 2026-04-23: Final CPS1 `BALUT` fix:
  - the first attempt still left `sdram_bank3.bin` empty because `jtframe_dwnld` treats the first header offset word as the bank-0 placeholder and uses the next three words as the thresholds for banks 1-3
  - changed the CPS1 header offset region list from `["audiocpu","oki","gfx"]` to `["maincpu","audiocpu","oki","gfx"]`
  - regenerated `1941.rom`; the header now begins `00 00 00 08 80 08 80 0a ff ff`, which decodes to the expected thresholds for bank 1 (`0x0800`), bank 2 (`0x0880`), and bank 3 (`0x0a80`)
  - `jtframe mem cps1 -t mist` still emits `BALUT/LUTSH` in the generated wrapper, confirming CPS1 remains on header-driven bank selection
  - `jtframe mra cps1 --setname 1941 --skipPocket` now only warns about the intentional `cps1mult` outlier
- 2026-04-23: Quick direct `1941` re-check after the corrected `BALUT` header ordering:
  - command: `jtsim -setname 1941 -load -q -video 80 -d SKIP_RAMCLR -d JTFRAME_SIM_ROMRQ_NOCHECK -d VIDEO_START=2`
  - ROM transfer completed at frame 49 and dumped all four SDRAM banks
  - bank dump summary:
    - `sdram_bank0.bin`: `1759112` non-zero bytes
    - `sdram_bank1.bin`: `128050` non-zero bytes
    - `sdram_bank2.bin`: `513719` non-zero bytes
    - `sdram_bank3.bin`: `1765024` non-zero bytes
  - this confirms the gfx payload is no longer missing from bank 3

## Next Steps

1. Re-run the `1941` 500-frame video smoke with the corrected `BALUT` header ordering and compare the frame milestones again against `/nobackup/regression/cps1/1941/valid/frames.zip`.
2. Re-run a deterministic CPS1 sound smoke (`ffight` with `reg.cab` or another fast-input set) and require a non-silent `test.wav` before calling CPS1 done.
3. Retry `jtcore cps1` after the Quartus environment issue (`quartus_sh -v` hanging) is resolved.
4. Once CPS1 is stable, review CPS1.5 and CPS2 header region ordering before converting their handwritten SDRAM paths, because they also rely on `BALUT`.
