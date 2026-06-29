#!/bin/zsh
set -e

# Build Workrave (Qt UI) from source on macOS and install it to /Applications.
# Works on both Apple Silicon (/opt/homebrew) and Intel (/usr/local).
# adapted from https://apple.stackexchange.com/a/425118
# and https://github.com/rcaelers/workrave/issues/328

if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is required: https://brew.sh" >&2
    exit 1
fi

brew_install() {
    if brew list $1 &>/dev/null; then
        echo "${1} is already installed"
    else
        brew install $1
    fi
}

brew_install "qt"
brew_install "gettext"
brew_install "cmake"
brew_install "ninja"
brew_install "pkg-config"
brew_install "boost"
brew_install "spdlog"   # must use the same fmt as Homebrew; a mismatched fmt breaks the final link

# Homebrew prefix differs between Apple Silicon (/opt/homebrew) and Intel (/usr/local).
BREW="$(brew --prefix)"

# Jinja2 must live in the SAME python cmake will use (we pin Homebrew's python3 below).
# Distro/system-wide include paths are ignored, so installing via the wrong python fails silently.
"$BREW/bin/python3" -m pip install --break-system-packages Jinja2

if [[ ! -d ./workrave ]]; then
    git clone https://github.com/rcaelers/workrave.git
fi

SRC="$PWD/workrave"
BUILD="$SRC/build"
INSTALL="$BUILD/install"

rm -rf "$BUILD"
mkdir -p "$BUILD"

# Build inside `env -i` with a curated PATH so a non-Homebrew toolchain (e.g. Anaconda)
# that shadows Homebrew cannot leak in. Example failure: Anaconda ships fmt 9 while
# Homebrew's spdlog is built against fmt 12, producing `fmt::v9` undefined-symbol link
# errors. A Homebrew-only PATH (plus CMAKE_IGNORE_PREFIX_PATH) forces a consistent toolchain.
CLEAN_PATH="$BREW/bin:$BREW/opt/gettext/bin:/usr/bin:/bin:/usr/sbin:/sbin"

env -i HOME="$HOME" PATH="$CLEAN_PATH" \
    "$BREW/bin/cmake" \
        -S "$SRC" \
        -B "$BUILD" \
        -G Ninja \
        -DCMAKE_PREFIX_PATH="$BREW/opt/qt;$BREW" \
        -DCMAKE_IGNORE_PREFIX_PATH="/opt/anaconda3;/opt/miniconda3" \
        -DPython3_EXECUTABLE="$BREW/bin/python3" \
        -DCMAKE_INSTALL_PREFIX="$INSTALL" \
        -DWITH_UI=Qt \
        -DWITH_TESTS=OFF \
        -DWITH_TRACING=TRUE \
        -DCMAKE_BUILD_TYPE=Release

env -i HOME="$HOME" PATH="$CLEAN_PATH" "$BREW/bin/ninja" -C "$BUILD"

# macdeployqt prints harmless "Cannot resolve rpath" errors for QML/QtQuick frameworks
# that the widget-based Workrave UI never loads; the install still succeeds.
env -i HOME="$HOME" PATH="$CLEAN_PATH" "$BREW/bin/ninja" -C "$BUILD" install

APP="$INSTALL/Workrave.app"

# macdeployqt leaves a self-referential symlink (Frameworks/Frameworks -> ./Frameworks)
# that makes codesign --deep loop forever ("Too many levels of symbolic links").
rm -f "$APP/Contents/Frameworks/Frameworks"

# macdeployqt rewrites every binary's install-names/rpaths, which invalidates the
# ad-hoc signatures it then fails to fully restore. On Apple Silicon dyld SIGKILLs any
# binary with a stale signature ("CODESIGNING, Code 2 Invalid Page"), so the app crashes
# instantly on launch. Re-sign ad-hoc from the inside out: nested code first, bundle last.
find "$APP/Contents/Frameworks" "$APP/Contents/PlugIns" -name "*.dylib" -type f \
    -exec codesign --force --timestamp=none -s - {} +
find "$APP/Contents/Frameworks" -name "*.framework" -type d \
    -exec codesign --force --timestamp=none -s - {} +
codesign --force --timestamp=none -s - "$APP/Contents/MacOS/workrave"
codesign --force --timestamp=none -s - "$APP"
codesign --verify --deep --strict "$APP"

# Drop the self-contained bundle into /Applications.
rm -rf /Applications/Workrave.app
cp -R "$APP" /Applications/Workrave.app

echo "Done: /Applications/Workrave.app"
