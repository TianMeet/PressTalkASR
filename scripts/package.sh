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
PACK_CACHE_ROOT="${PACK_CACHE_ROOT:-${TMPDIR:-/tmp}/${APP_NAME}-package-cache}"
SIGN_ID="${SIGN_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
CLEAN_BUILD="${CLEAN_BUILD:-0}"
STAGING_ROOT=""

cleanup_staging() {
    if [[ -n "$STAGING_ROOT" ]]; then
        rm -rf "$STAGING_ROOT"
        STAGING_ROOT=""
    fi
}

trap cleanup_staging EXIT

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
  CLEAN_BUILD     1 to remove .build and module caches before build.
  PACK_CACHE_ROOT Override module cache root.
                  Defaults to ${TMPDIR}/${APP_NAME}-package-cache
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
    export CLANG_MODULE_CACHE_PATH="${PACK_CACHE_ROOT}/clang-module-cache"
    export SWIFTPM_MODULECACHE_OVERRIDE="${PACK_CACHE_ROOT}/swiftpm-module-cache"
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

resolve_binary_path() {
    # Prefer SwiftPM's reported bin path so we don't pick stale outputs from other triples/configs.
    local bin_dir binary
    bin_dir="$(cd "$ROOT_DIR" && swift_cmd build -c "$BUILD_CONFIG" --show-bin-path 2>/dev/null || true)"
    if [[ -n "$bin_dir" ]]; then
        binary="${bin_dir}/${APP_NAME}"
        if [[ -f "$binary" ]]; then
            printf '%s\n' "$binary"
            return 0
        fi
    fi

    binary="$(find "$ROOT_DIR/.build" -type f -path "*/${BUILD_CONFIG}/${APP_NAME}" -print -quit || true)"
    [[ -n "$binary" ]] || fail "build output not found for ${APP_NAME}"
    printf '%s\n' "$binary"
}

clean_build_state() {
    log "cleaning Swift build artifacts and module caches"
    rm -rf "$ROOT_DIR/.build"
    rm -rf "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"
    mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"
}

build_binary() {
    if [[ "$CLEAN_BUILD" == "1" ]]; then
        clean_build_state
    fi

    local build_log
    build_log="$(mktemp)"

    log "building (${BUILD_CONFIG})"
    if ! (cd "$ROOT_DIR" && swift_cmd build -c "$BUILD_CONFIG" 2>&1 | tee "$build_log") >&2; then
        rm -f "$build_log"
        fail "swift build failed"
    fi

    if grep -q "PCH was compiled with module cache path" "$build_log"; then
        log "detected stale module cache path, cleaning and retrying build once"
        clean_build_state
        if ! (cd "$ROOT_DIR" && swift_cmd build -c "$BUILD_CONFIG") >&2; then
            rm -f "$build_log"
            fail "swift build failed after cache cleanup retry"
        fi
    fi
    rm -f "$build_log"

    local binary
    binary="$(resolve_binary_path)"
    printf '%s\n' "$binary"
}

artifact_summary() {
    local path="$1"
    [[ -f "$path" ]] || fail "artifact not found: $path"

    local size_bytes size_mib sha256
    size_bytes="$(stat -f%z "$path")"
    size_mib="$(awk -v b="$size_bytes" 'BEGIN { printf "%.2f", b / 1048576 }')"
    sha256="$(shasum -a 256 "$path" | awk '{print $1}')"

    log "artifact=$(basename "$path") size=${size_mib}MiB sha256=${sha256}"
}

strip_codesign_blocking_xattrs() {
    local target="$1"
    local attempt
    # Keep file-provider metadata intact, but strip xattrs that make codesign --strict fail.
    for attempt in 1 2 3; do
        xattr -dr com.apple.FinderInfo "$target" 2>/dev/null || true
        xattr -dr com.apple.ResourceFork "$target" 2>/dev/null || true

        if ! xattr -lr "$target" 2>/dev/null | grep -Eq 'com\.apple\.(FinderInfo|ResourceFork)'; then
            break
        fi
        sleep 0.05
    done
}

create_app_bundle() {
    local binary_path="$1"
    local app_dir="$2"
    local binary_dir bundle_path bundle_name

    rm -rf "$app_dir"
    mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
    cp -X "$INFO_PLIST" "$app_dir/Contents/Info.plist"
    cp -X "$binary_path" "$app_dir/Contents/MacOS/${APP_NAME}"
    chmod +x "$app_dir/Contents/MacOS/${APP_NAME}"

    # SwiftPM executable resources are emitted as sibling *.bundle directories.
    binary_dir="$(dirname "$binary_path")"
    while IFS= read -r bundle_path; do
        bundle_name="$(basename "$bundle_path")"
        log "embedding resource bundle: ${bundle_name}"
        ditto "$bundle_path" "$app_dir/Contents/Resources/${bundle_name}"
    done < <(find "$binary_dir" -maxdepth 1 -type d -name '*.bundle' -print)

    strip_codesign_blocking_xattrs "$app_dir"
}

sign_app_local() {
    local app_dir="$1"
    log "ad-hoc signing app"
    strip_codesign_blocking_xattrs "$app_dir"
    codesign --force --deep --sign - "$app_dir"
}

sign_app_release() {
    local app_dir="$1"
    [[ -n "$SIGN_ID" ]] || fail "release mode requires SIGN_ID"
    log "Developer ID signing app: ${SIGN_ID}"
    strip_codesign_blocking_xattrs "$app_dir"
    codesign --force --deep --options runtime --timestamp --sign "$SIGN_ID" "$app_dir"
}

verify_app_signature() {
    local app_dir="$1"
    log "verifying app signature"
    strip_codesign_blocking_xattrs "$app_dir"
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
    need_cmd shasum
    need_cmd xattr
    need_cmd ditto
    need_cmd /usr/libexec/PlistBuddy
    assert_xcode_selected
    setup_local_caches

    [[ -f "$INFO_PLIST" ]] || fail "Info.plist not found: $INFO_PLIST"

    mkdir -p "$DIST_DIR"

    local version bundle_id arch binary_path app_dir staged_app_dir dmg_name dmg_path
    version="$(version_from_plist)"
    bundle_id="$(bundle_id_from_plist)"
    arch="$(uname -m)"
    app_dir="${DIST_DIR}/${APP_NAME}.app"
    STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}-package.XXXXXX")"
    staged_app_dir="${STAGING_ROOT}/${APP_NAME}.app"

    log "app=${APP_NAME} version=${version} bundleID=${bundle_id} mode=${MODE}"

    binary_path="$(build_binary)"
    log "binary=${binary_path}"

    # Assemble and sign away from the destination directory. Desktop/file-provider
    # folders can re-attach FinderInfo between signing and DMG creation, which
    # invalidates strict signature verification inside the finished image.
    create_app_bundle "$binary_path" "$staged_app_dir"

    if [[ "$MODE" == "release" ]]; then
        sign_app_release "$staged_app_dir"
    else
        sign_app_local "$staged_app_dir"
    fi
    verify_app_signature "$staged_app_dir"

    notarize_app_if_needed "$staged_app_dir"

    if [[ "$MODE" == "release" ]]; then
        dmg_name="${APP_NAME}-${version}.dmg"
    else
        dmg_name="${APP_NAME}-${version}-${arch}.dmg"
    fi
    dmg_path="${DIST_DIR}/${dmg_name}"

    create_dmg "$staged_app_dir" "$dmg_path"
    sign_dmg_if_release "$dmg_path"
    notarize_dmg_if_needed "$dmg_path"
    artifact_summary "$dmg_path"

    # Keep a convenient loose app next to the DMG, but only after the verified
    # disk image has been created from the clean staging copy.
    rm -rf "$app_dir"
    ditto --noextattr --noqtn "$staged_app_dir" "$app_dir"

    log "done"
    log "app: ${app_dir}"
    log "dmg: ${dmg_path}"
}

main "$@"
