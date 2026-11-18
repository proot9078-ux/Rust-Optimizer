# Rust Optimizer 8 — RUST + FORTNITE performance engine

[![build](https://github.com/proot9078-ux/Rust-Optimizer/actions/workflows/build.yml/badge.svg)](https://github.com/proot9078-ux/Rust-Optimizer/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)
[![C++20](https://img.shields.io/badge/C%2B%2B-20-blue.svg)](https://en.cppreference.com/w/cpp/20)
[![Windows 10/11 x64](https://img.shields.io/badge/Windows-10%2F11%20x64-0078D4.svg)](#system-requirements)
[![Release](https://img.shields.io/github/v/release/proot9078-ux/Rust-Optimizer?color=a03ce0)](https://github.com/proot9078-ux/Rust-Optimizer/releases/latest)

<p align="center">
  <img src="assets/app-icon.png" width="144" alt="Rust Optimizer icon">
</p>

Native Windows application (C++20, Win32 + Direct2D) that tunes **RUST** and
**FORTNITE** from the outside: game configs, launch options, process priority,
CPU affinity and the Windows standby list. It does **not** inject into game
processes, does not read game memory and does not ship DLLs, so it stays
compatible with Easy Anti-Cheat and BattlEye.

The previous version of this project was a PowerShell/WinForms monolith. 8.0 is
a ground-up C++ rewrite: a single self-contained `RustOptimizer.exe`, no
PowerShell runtime, no external dependencies.

## Features

| Page | What it does |
|---|---|
| **Обзор** | Hardware summary, detected game paths, autopilot (repair, clean, apply everything, vivid picture, launch RUST, close itself), game launch, standby purge |
| **RUST** | `client.cfg` tweaks (grass, SSAA, shadows, VSync, pixel light, DOF, motion blur, parallax, light shafts, chromatic aberration, GC buffer), Steam Launch Options writer (`localconfig.vdf`) with revert, picture presets + NVIDIA panel shortcut, `.rop` profile import/export |
| **FORTNITE** | `GameUserSettings.ini` + `Engine.ini` tweaks (frame limit, VSync, fullscreen, motion blur, bloom, lens flare, DOF, shadows, streaming pool), launch options |
| **Система** | Standby-list purge, Game DVR, Game Mode, HAGS, DNS flush, TCP autotuning, fullscreen optimizations, CPU affinity, SFC + DISM repair |
| **Очистка** | Scan and clean user/Windows temp folders, DirectX/NVIDIA/AMD shader caches, crash dumps and updater staging (configs and saves untouched) |
| **Профили** | Save/load/import/export tweak profiles (`.rop`) |
| **Диагностика** | One-click system/hardware/games/log report saved to `%LOCALAPPDATA%\RustOptimizer\reports` |
| **Настройки** | Six themes (dark, midnight, light, neon, RUST, ocean), mandatory updates, auto-priority, minimize-on-apply, data folders |
| **Логи** | Live session log with levels, plus the on-disk log file |

Scrolling works without a mouse wheel: drag the scrollbar, click the track, or
use the arrow keys, PageUp/PageDown and Home/End. Ctrl+1…9 switches pages, F5
checks for updates.

Every change is reversible:

* files are backed up to `%LOCALAPPDATA%\RustOptimizer\backups\<stamp>_<label>`
  before the first write;
* RUST keys are merged into the existing `client.cfg` and can be reverted;
* Steam Launch Options are written into `localconfig.vdf` only while Steam and
  RUST are closed, atomically, after a backup and with a read-back check that
  restores the original on mismatch;
* picture presets change the desktop gamma ramp through `SetDeviceGammaRamp`
  and the original ramp is saved first, so "Как в Windows" restores it exactly;
* the optimizer closes itself (after saving settings) when `RustClient.exe`
  starts — that is a UI action only, not a hook into the game.
* FORTNITE entries live inside `; >>> RO:<id> >>>` … `; <<< RO:<id> <<<`
  marker blocks that are removed on revert without touching anything else;
* registry changes only target per-user keys (`HKCU`) unless elevation is
  explicitly requested.

## Safety

* No injection, no hooks, no memory reads/writes, no overlays.
* Priorities are capped at `HIGH_PRIORITY_CLASS`; `REALTIME` is never used.
* No `system()` / `cmd.exe` calls — only `CreateProcessW` with
  `CREATE_NO_WINDOW`.
* Network access only for the GitHub release check (can be disabled in
  Settings) and for downloading an update after explicit confirmation.
* Standby purge needs an elevated process; the app asks for it on demand and
  keeps working (minus that one switch) when declined.
* The manifest requests `asInvoker`, so Windows never auto-elevates the app.

## System requirements

* Windows 10 1607+ or Windows 11, x64.
* No runtime prerequisites: the executable statically links the CRT.

## Install

1. Download `RustOptimizer-win64.zip` from
   [Releases](https://github.com/proot9078-ux/Rust-Optimizer/releases/latest).
2. Extract anywhere and run `RustOptimizer.exe`.
3. Press **Найти игры** — Steam/Epic installs are located through the registry,
   `libraryfolders.vdf`, `appmanifest_252490.acf` and Epic manifests.

Optional: run as administrator to unlock the standby-list purge.

## Build from source

Requirements: Visual Studio 2022 with the C++ workload, CMake 3.21+.

```bat
cmake -S . -B build -G "Visual Studio 17 2022" -A x64 -DRO_WARNINGS_AS_ERRORS=ON
cmake --build build --config Release --parallel
ctest --test-dir build -C Release --output-on-failure
build\Release\RustOptimizer.exe
```

The build is `/W4 /permissive- /utf-8` clean. The icon (`build\generated\app.ico`)
is generated at build time by `tools/gen_icon.cpp` (GDI+) and compiled into the
executable together with the version resource and the manifest — no binary icon
is stored in the repository.

### Command line

```text
RustOptimizer.exe --version    print the version
RustOptimizer.exe --selftest   hardware/game detection report, log paths
RustOptimizer.exe --help
```

### Mandatory self-update

Every start the app queries
`https://api.github.com/repos/proot9078-ux/Rust-Optimizer/releases/latest` and
compares the tag with its own version. There is no "later" button: when a newer
build exists the window locks into a progress card while the release is

1. downloaded into `%LOCALAPPDATA%\RustOptimizer\staging`,
2. verified against `SHA256SUMS.txt` when the release publishes one,
3. unpacked, and
4. swapped in by the `--apply-update` helper, which waits for the UI to exit,
   renames the old binary, retries `MoveFileEx` until the image is released,
   refreshes the desktop and Start menu shortcuts, launches the new build and
   deletes the old executable and the staging folder.

Failed attempts (offline, rate limit, corrupt archive) are retried automatically
with the error shown in the card, so the update always lands on a later start.
The check toggle was removed from Settings; updates are mandatory.

## Tests and CI

* `ro_tests` (Catch2) covers string/UTF-16 conversion, filesystem helpers, the
  INI engine (order/comments/marker blocks/CRLF), Steam VDF/ACF parsing, launch
  options, version comparison and GitHub release JSON parsing.
* `.github/workflows/build.yml` builds with MSVC, runs `ctest`, smoke-tests
  `--version`/`--selftest`, uploads the artifact and publishes a release on
  `v*` tags.
* `tools/release.ps1 -Version 8.0.1` builds, packages, hashes and publishes
  locally through the GitHub CLI.

## Repository layout

```text
include/ro/        public headers (core, games, tweaks, net, ui)
src/core/          strings, filesystem, JSON, logging, Win32 RAII, process,
                   affinity, memory, SHA-256, settings, hardware
src/games/         Steam/Epic locators
src/tweaks/        INI engine, RUST/FORTNITE/system tweaks, profiles
src/net/           WinHTTP client, zip, updater
src/ui/            theme, widgets, pages, window
src/icon.cpp       programmatic icon (window + .ico)
tools/             icon generator, release script
tests/             Catch2 suites
third_party/       nlohmann/json, miniz, Catch2 (vendored)
```

The legacy PowerShell sources remain under `src/` for historical reference and
are no longer shipped in releases.

## License

MIT — see [LICENSE](LICENSE).
