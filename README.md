# 6soz

6soz is a multi-system emulator host written in Zig. It currently provides frontends for the NES, Game Boy, and Game Boy Color. The host application uses [raylib](https://github.com/raysan5/raylib) for cross-platform video, audio, and input.

## Architecture

The project is split into several decoupled packages to separate concerns and allow independent evolution of CPU cores and system components:

- **`6soz`**: The main host application (CLI, video, audio, input loops via raylib).
- **`6soz-nes`**: The NES emulator core backend.
- **`6soz-gameboy`**: The Game Boy (DMG) and Game Boy Color (CGB) emulator core backend.
- **`6soz-mos6502`**: A standalone MOS 6502 / Ricoh 2A03 CPU module used by the NES core.
- **`6soz-lr35902`**: A standalone Sharp LR35902 CPU module used by the Game Boy core.

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

## License

This project is licensed under the [MIT Licence](LICENCE).
