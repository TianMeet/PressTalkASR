#!/usr/bin/env bash
set -euo pipefail

# If invoked via `sh script.sh`, re-exec with bash to ensure consistent behavior.
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi

MODE="${1:-local}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

APP_NAME="${APP_NAME:-PressTalkASR}"
INFO_PLIST="${INFO_PLIST:-${ROOT_DIR}/Sources/PressTalkASR/Info.plist}"
DIST_DIR="${DIST_DIR:-${ROOT_DIR}/dist}"
BUILD_CONFIG="${BUILD_CONFIG:-release}"
SIGN_ID="${SIGN_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
CLEAN_BUILD="${CLEAN_BUILD:-0}"

usage() {
    cat <<'EOF'
Usage:
  ./scripts/package.sh [local|release]

Modes:
  local    Build + ad-hoc sign + dmg (default)
  release  Build + Developer ID sign + dmg + optional notarization

Environment variables:
  SIGN_ID         Required in release mode.
                  Example: Developer ID Application: Your Name (TEAMID)
  NOTARY_PROFILE  Optional. If provided in release mode, submit and staple notarization.
                  Create once with:
                  xcrun notarytool store-credentials "AC_NOTARY" --apple-id ... --team-id ... --password ...
  CLEAN_BUILD     1 to run `swift package clean` before build.
  APP_NAME        Defaults to PressTalkASR
  INFO_PLIST      Defaults to Sources/PressTalkASR/Info.plist
  DIST_DIR        Defaults to dist
EOF
}

log() {
    printf '[package] %s\n' "$1" >&2
}

fail() {
    printf '[package] error: %s\n' "$1" >&2
    exit 1
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

setup_local_caches() {
    export CLANG_MODULE_CACHE_PATH="${ROOT_DIR}/.build/clang-module-cache"
    export SWIFTPM_MODULECACHE_OVERRIDE="${ROOT_DIR}/.build/swiftpm-module-cache"
    mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"
}

swift_cmd() {
    xcrun swift "$@"
}

assert_xcode_selected() {
    if ! xcodebuild -version >/dev/null 2>&1; then
        fail "xcodebuild unavailable. Run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    fi
}

version_from_plist() {
    /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null || echo "0.0.0"
}

bundle_id_from_plist() {
    /usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$INFO_PLIST" 2>/dev/null || echo "unknown.bundle.id"
}

build_binary() {
    if [[ "$CLEAN_BUILD" == "1" ]]; then
        log "cleaning Swift package build cache"
        (cd "$ROOT_DIR" && swift_cmd package clean) >&2
    fi

    log "building (${BUILD_CONFIG})"
    (cd "$ROOT_DIR" && swift_cmd build -c "$BUILD_CONFIG") >&2

    local binary
    binary="$(find "$ROOT_DIR/.build" -type f -path "*/${BUILD_CONFIG}/${APP_NAME}" -print -quit || true)"
    [[ -n "$binary" ]] || fail "build output not found for ${APP_NAME}"
    printf '%s\n' "$binary"
}

create_app_bundle() {
    local binary_path="$1"
    local app_dir="$2"

    rm -rf "$app_dir"
    mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
    cp "$INFO_PLIST" "$app_dir/Contents/Info.plist"
    cp "$binary_path" "$app_dir/Contents/MacOS/${APP_NAME}"
    chmod +x "$app_dir/Contents/MacOS/${APP_NAME}"
}

sign_app_local() {
    local app_dir="$1"
    log "ad-hoc signing app"
    codesign --force --deep --sign - "$app_dir"
}

sign_app_release() {
    local app_dir="$1"
    [[ -n "$SIGN_ID" ]] || fail "release mode requires SIGN_ID"
    log "Developer ID signing app: ${SIGN_ID}"
    codesign --force --deep --options runtime --timestamp --sign "$SIGN_ID" "$app_dir"
}

verify_app_signature() {
    local app_dir="$1"
    log "verifying app signature"
    codesign --verify --deep --strict --verbose=2 "$app_dir"
}

notarize_app_if_needed() {
    local app_dir="$1"
    [[ -n "$NOTARY_PROFILE" ]] || return 0

    local zip_path="${DIST_DIR}/${APP_NAME}.zip"
    log "zipping app for notarization"
    rm -f "$zip_path"
    ditto -c -k --keepParent "$app_dir" "$zip_path"

    log "submitting app for notarization (profile: ${NOTARY_PROFILE})"
    xcrun notarytool submit "$zip_path" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$app_dir"
}

create_dmg() {
    local app_dir="$1"
    local dmg_path="$2"
    log "creating dmg: $(basename "$dmg_path")"
    rm -f "$dmg_path"
    hdiutil create -volname "$APP_NAME" -srcfolder "$app_dir" -ov -format UDZO "$dmg_path" >/dev/null
}

sign_dmg_if_release() {
    local dmg_path="$1"
    [[ "$MODE" == "release" ]] || return 0
    log "signing dmg"
    codesign --force --timestamp --sign "$SIGN_ID" "$dmg_path"
}

notarize_dmg_if_needed() {
    local dmg_path="$1"
    [[ "$MODE" == "release" ]] || return 0
    [[ -n "$NOTARY_PROFILE" ]] || return 0
    log "submitting dmg for notarization"
    xcrun notarytool submit "$dmg_path" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$dmg_path"
}

main() {
    case "$MODE" in
        local|release) ;;
        -h|--help|help)
            usage
            exit 0
            ;;
        *)
            usage
            fail "invalid mode: ${MODE}"
            ;;
    esac

    need_cmd xcrun
    need_cmd xcodebuild
    need_cmd codesign
    need_cmd hdiutil
    need_cmd /usr/libexec/PlistBuddy
    assert_xcode_selected
    setup_local_caches

    [[ -f "$INFO_PLIST" ]] || fail "Info.plist not found: $INFO_PLIST"

    mkdir -p "$DIST_DIR"

    local version bundle_id arch binary_path app_dir dmg_name dmg_path
    version="$(version_from_plist)"
    bundle_id="$(bundle_id_from_plist)"
    arch="$(uname -m)"
    app_dir="${DIST_DIR}/${APP_NAME}.app"

    log "app=${APP_NAME} version=${version} bundleID=${bundle_id} mode=${MODE}"

    binary_path="$(build_binary)"
    log "binary=${binary_path}"

    create_app_bundle "$binary_path" "$app_dir"

    if [[ "$MODE" == "release" ]]; then
        sign_app_release "$app_dir"
    else
        sign_app_local "$app_dir"
    fi
    verify_app_signature "$app_dir"

    notarize_app_if_needed "$app_dir"

    if [[ "$MODE" == "release" ]]; then
        dmg_name="${APP_NAME}-${version}.dmg"
    else
        dmg_name="${APP_NAME}-${version}-${arch}.dmg"
    fi
    dmg_path="${DIST_DIR}/${dmg_name}"

    create_dmg "$app_dir" "$dmg_path"
    sign_dmg_if_release "$dmg_path"
    notarize_dmg_if_needed "$dmg_path"

    log "done"
    log "app: ${app_dir}"
    log "dmg: ${dmg_path}"
}

main "$@"
