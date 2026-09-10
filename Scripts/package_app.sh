#!/bin/zsh
set -euo pipefail

CONFIG="${1:-release}"
INSTALL_MODE="${2:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Translex.app"
BUNDLE_ID="com.picmao.translex"
CANONICAL_APP="/Applications/Translex.app"

resolve_signing_identity() {
    if [[ -n "${TRANSLEX_SIGNING_IDENTITY:-}" ]]; then
        print -r -- "$TRANSLEX_SIGNING_IDENTITY"
        return
    fi

    local identities
    identities=(${(f)"$(security find-identity -v -p codesigning | sed -nE 's/^[[:space:]]*[0-9]+\) ([0-9A-F]{40}) "Apple Development:.*$/\1/p')"})
    if (( ${#identities[@]} == 1 )); then
        print -r -- "$identities[1]"
        return
    fi
    if [[ "${TRANSLEX_ALLOW_ADHOC_SIGNING:-0}" == "1" ]]; then
        print -r -- "-"
        return
    fi

    print -u2 "Expected exactly one Apple Development signing identity; found ${#identities[@]}."
    print -u2 "Set TRANSLEX_SIGNING_IDENTITY explicitly, or TRANSLEX_ALLOW_ADHOC_SIGNING=1 for an explicit fallback."
    return 1
}

verify_app() {
    local app_path="$1"
    [[ "$(plutil -extract CFBundleIdentifier raw "$app_path/Contents/Info.plist")" == "$BUNDLE_ID" ]]
    [[ -x "$app_path/Contents/MacOS/Translex" ]]
    codesign --verify --deep --strict --verbose=2 "$app_path"
}

install_canonical_app() {
    local destination="$CANONICAL_APP"
    local candidate="/Applications/.Translex.app.new.$$"
    local backup="/Applications/.Translex.app.old.$$"

    if [[ -e "$destination" ]]; then
        local existing_id
        existing_id="$(plutil -extract CFBundleIdentifier raw "$destination/Contents/Info.plist" 2>/dev/null || true)"
        if [[ "$existing_id" != "$BUNDLE_ID" ]]; then
            print -u2 "Refusing to replace $destination because its bundle identifier is '$existing_id'."
            return 1
        fi
        if pgrep -f "^$destination/Contents/MacOS/Translex$" >/dev/null 2>&1; then
            print -u2 "Quit the canonical Translex app before replacing it."
            return 1
        fi
    fi

    rm -rf "$candidate" "$backup"
    ditto "$APP" "$candidate"
    verify_app "$candidate"

    if [[ -e "$destination" ]]; then
        mv "$destination" "$backup"
        if ! mv "$candidate" "$destination"; then
            mv "$backup" "$destination"
            return 1
        fi
        rm -rf "$backup"
    else
        mv "$candidate" "$destination"
    fi
    verify_app "$destination"
}

if [[ -n "$INSTALL_MODE" && "$INSTALL_MODE" != "--install" ]]; then
    print -u2 "Usage: Scripts/package_app.sh [debug|release] [--install]"
    exit 2
fi

cd "$ROOT"
swift build -c "$CONFIG"
"$ROOT/Scripts/generate_icon.sh" >/dev/null
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
SIGNING_IDENTITY="$(resolve_signing_identity)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/TranslexApp" "$APP/Contents/MacOS/Translex"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/Translex.icns" "$APP/Contents/Resources/Translex.icns"
chmod +x "$APP/Contents/MacOS/Translex"

plutil -lint "$APP/Contents/Info.plist" >/dev/null
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    codesign --force --sign - --timestamp=none "$APP"
else
    codesign --force --options runtime --sign "$SIGNING_IDENTITY" --timestamp=none "$APP"
fi
verify_app "$APP"

if [[ "$INSTALL_MODE" == "--install" ]]; then
    install_canonical_app
    echo "$CANONICAL_APP"
else
    echo "$APP"
fi
