# 6soz

6soz is an retro emulator software, currently it only supports nes with its simples cartridge format.

## Requirements

- Zig 0.16.0

## Build

```sh
zig build
```

## Run

```sh
zig build run -Doptimize=ReleaseFast -- nes roms/mario.nes
```
