# 6soz

6soz is a retro emulator software written in Zig. Currently, it supports the NES console with its simplest cartridge format.

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
zig build run -Doptimize=ReleaseFast -- nes roms/mario.nes
```

## Project Status

The emulator is currently under active development. More cartridge mappers, audio improvements, and additional platform support are planned.

## License

This project is licensed under the [MIT Licence](LICENCE).
