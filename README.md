# 6soz

6soz is a multi-system emulator host written in Zig. It currently provides frontends for the NES, Game Boy, and Game Boy Color. The host application uses [raylib](https://github.com/raysan5/raylib) for cross-platform video, audio, and input.

## Architecture

The project is split into decoupled packages and host layers so frontend code,
emulator orchestration, and core emulation can evolve independently:

- **`6soz`**: Host application, CLI tools, web entrypoint, and raylib frontend.
- **`src/common`**: Shared host contracts and state codec helpers.
- **`src/host`**: System facade and emulator-facing host logic.
- **`src/frontend/raylib`**: Window, rendering, audio, and input adapters.
- **`src/cli`**: Native run, benchmark, and smoke-check entrypoints.
- **`src/web`**: Browser entrypoint and custom Emscripten shell.
- **`6soz-nes`**: NES emulator core backend.
- **`6soz-gameboy`**: Game Boy (DMG) and Game Boy Color (CGB) emulator core backend.
- **`6soz-mos6502`**: Standalone MOS 6502 / Ricoh 2A03 CPU module used by the NES core.
- **`6soz-lr35902`**: Standalone Sharp LR35902 CPU module used by the Game Boy core.

## Images

|                                      |                                      |
| ------------------------------------ | ------------------------------------ |
| ![mario](images/mario.png)           | ![donkeykong](images/donkeykong.png) |
| ![battlecity](images/battlecity.png) | ![mariobros](images/mariobros.png)   |

## Requirements

* Zig 0.16.0

## Build

```sh
zig build
```

## Web Build

Build the browser version with:

```sh
zig build web -Doptimize=ReleaseFast
```

The web build writes `zig-out/web/index.html` plus the generated JavaScript,
WebAssembly, and data files. Serve `zig-out/web` over HTTP and open
`index.html`; the browser build currently boots the NES emulator directly into
`roms/nes/ravens_gate_mmc1.nes`.

## Run

```sh
Usage: 6soz <system> <rom_path> [--boot-rom <path>] [--model auto|dmg|cgb]
```

*Note: `gameboy` can be shortened to `gb`.*

**NES Examples:**
```sh
zig build run -Doptimize=ReleaseFast -- nes roms/mario.nes
```

**Game Boy Examples:**
```sh
zig build run -Doptimize=ReleaseFast -- gb roms/game.gb --boot-rom boot/dmg.bin
zig build run -Doptimize=ReleaseFast -- gb roms/game.gbc --boot-rom boot/cgb.bin --model cgb
```

The host stores battery-backed save data next to the ROM as `<rom_path>.sav`.
Save states are stored next to the ROM as `<rom_path>.state`; press `F5` to
write a state and `F8` to load it. Game Boy and Game Boy Color games require a
matching legally obtained boot ROM before they can start or load states.

## Benchmark

Run the headless benchmark executable with:

```sh
zig build bench -Doptimize=ReleaseFast -- <system> <rom_path> [frames_count] [--boot-rom <path>]
```

For example:

```sh
zig build bench -Doptimize=ReleaseFast -- nes roms/mario.nes 1000
zig build bench -Doptimize=ReleaseFast -- gb roms/game.gb 1000 --boot-rom boot/dmg.bin
```

## Compatibility Smoke Checks

Run headless load/step/save-state checks over one NES ROM or a directory of
NES ROMs:

```sh
zig build smoke -- nes roms/nes --frames 2
```

## License

This project is licensed under the [MIT Licence](LICENCE).
