# workrave-mac

A one-shot script that builds [Workrave](https://github.com/rcaelers/workrave)
(the Qt UI) from source on macOS and installs a self-contained, code-signed
`Workrave.app` into `/Applications`.

Workrave has no official macOS binary, and building it by hand hits several
non-obvious snags. This script handles them so you don't have to.

## Requirements

- macOS (Apple Silicon or Intel)
- [Homebrew](https://brew.sh)
- Xcode Command Line Tools (`xcode-select --install`)

All other dependencies (Qt 6, gettext, cmake, ninja, boost, spdlog, Jinja2) are
installed by the script.

## Usage

```sh
git clone https://github.com/gitlzzz/workrave-mac.git
cd workrave-mac
./installworkrave.sh
```

The script clones Workrave into `./workrave`, builds it, and copies the result
to `/Applications/Workrave.app`. Launch it from Spotlight/Launchpad or with:

```sh
open /Applications/Workrave.app
```

## What the script solves

- **Homebrew prefix** — uses `brew --prefix` instead of hardcoded paths, so it
  works on both Apple Silicon (`/opt/homebrew`) and Intel (`/usr/local`).
- **`fmt`/`spdlog` link failure** — builds under `env -i` with a curated `PATH`
  so a non-Homebrew toolchain (e.g. Anaconda, which ships an older `fmt`) can't
  leak in and cause `fmt::v9` undefined-symbol errors at link time.
- **Jinja2 location** — installs Jinja2 into the exact Homebrew `python3` that
  cmake uses (needed for D-Bus code generation).
- **Code-signing crash on Apple Silicon** — `macdeployqt` rewrites every
  binary's rpaths, which invalidates their ad-hoc signatures; dyld then SIGKILLs
  the app on launch (`CODESIGNING, Code 2 Invalid Page`). The script re-signs the
  whole bundle inside-out and removes a self-referential symlink that breaks
  `codesign --deep`.
- **Rest-break exercises crash** — the exercises player dereferences the sound
  theme without a null check, so it SIGSEGVs (null `this` in `SoundTheme`) when
  the context's sound theme is unset. `patches/` holds a small source fix that the
  script applies to a fresh checkout after cloning.
- **Window visibility on macOS** (multi-monitor / full-screen):
  - The timer ("mini") window used `Qt::Tool`, which on macOS hides whenever
    Workrave isn't the active app. Fixed by setting the native window's
    `hidesOnDeactivate` to `NO`.
  - Break and prelude windows relied only on Qt's stay-on-top hint, so they
    wouldn't appear over full-screen apps or on other Spaces. Fixed by setting
    the native window collection behavior (`CanJoinAllSpaces |
    FullScreenAuxiliary`) and a raised level. Break windows still show on every
    monitor, which is intended.
  - On multiple monitors, each rest-break window shuffled its own exercise list,
    so every screen showed different exercises out of sync. Fixed by shuffling
    once per break and sharing that order + starting exercise across all the
    break's windows.

## Patches

Any `*.patch` in `patches/` is applied (via `git apply`) to the freshly cloned
Workrave source. These are local fixes not yet upstream; see the file header for
what each one does.

## Notes

- The app is **ad-hoc signed, not notarized**. It runs locally, but if you copy
  it to another Mac, Gatekeeper may quarantine it. Clear that with:
  `xattr -dr com.apple.quarantine /Applications/Workrave.app`
- Last verified: Workrave 1.11.0-rc.4, Qt 6.9, macOS 15.4 (Apple Silicon M3).
- Workrave itself is licensed under the GPLv3. This script is provided as-is.
