#!/usr/bin/env bash

set -euo pipefail

TEAM_ID="8QBDZ766S3"
EXPECTED_BUNDLE_ID="com.nuvio.media.desktop"
DEFAULT_SOURCE="/Applications/Nuvio.app"
DEFAULT_BACKUP="/Applications/Nuvio-original.app"

SOURCE="$DEFAULT_SOURCE"
BACKUP="${2:-$DEFAULT_BACKUP}"
INPUT_APP=""
DMG_PATH=""
MOUNT_POINT=""
DMG_MOUNTED=0
STAGING_DIR=""
STAGED_APP=""
ORIGINAL_MOVED=0
SIGNED_APP_INSTALLED=0

usage() {
    cat <<'EOF'
Usage:
  resign_nuvio.sh
  resign_nuvio.sh "/path/to/Nuvio.dmg"
  resign_nuvio.sh "/Applications/Nuvio.app" "/path/to/backup.app"

With no arguments, the script uses the newest Nuvio DMG in Downloads. If no
DMG is found, it signs /Applications/Nuvio.app.
EOF
}

fail() {
    echo
    echo "ERROR: $*"
    exit 1
}

read_bundle_id() {
    local app_path="$1"

    /usr/libexec/PlistBuddy \
        -c 'Print :CFBundleIdentifier' \
        "$app_path/Contents/Info.plist" 2>/dev/null || true
}

find_latest_downloaded_dmg() {
    local downloads_dir="$HOME/Downloads"
    local candidate=""
    local candidate_mtime=0
    local latest_mtime=0

    [[ -d "$downloads_dir" ]] || return 0

    while IFS= read -r -d '' candidate; do
        candidate_mtime="$(stat -f '%m' "$candidate" 2>/dev/null || printf '0')"

        if [[ "$candidate_mtime" =~ ^[0-9]+$ ]] &&
            (( candidate_mtime > latest_mtime )); then
            DMG_PATH="$candidate"
            latest_mtime="$candidate_mtime"
        fi
    done < <(find "$downloads_dir" \
        -type f \
        -maxdepth 1 \
        -iname '*nuvio*.dmg' \
        -print0)
}

choose_backup_path() {
    local requested="$1"
    local base="${requested%.app}"
    local number=2
    local candidate="$requested"

    while [[ -e "$candidate" ]]; do
        candidate="${base}-${number}.app"
        number=$((number + 1))
    done

    BACKUP="$candidate"
}

attach_dmg() {
    local attach_output=""

    if ! attach_output="$(hdiutil attach \
        -readonly \
        -nobrowse \
        -mountpoint "$MOUNT_POINT" \
        "$DMG_PATH" 2>&1)"; then
        printf '%s\n' "$attach_output" >&2
        return 1
    fi
}

cleanup() {
    local exit_code=$?

    trap - EXIT INT TERM
    set +e

    if (( ORIGINAL_MOVED == 1 && SIGNED_APP_INSTALLED == 0 )); then
        if [[ ! -e "$SOURCE" && -e "$BACKUP" ]]; then
            echo
            echo "Restoring the previous Nuvio app after an installation failure..."
            mv "$BACKUP" "$SOURCE" || {
                echo "ERROR: Automatic restore failed."
                echo "Previous app remains at: $BACKUP"
            }
        fi
    fi

    if [[ -n "$STAGING_DIR" && -d "$STAGING_DIR" ]]; then
        rm -rf -- "$STAGING_DIR"
    fi

    if (( DMG_MOUNTED == 1 )); then
        hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
    fi

    if [[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]]; then
        rmdir "$MOUNT_POINT" >/dev/null 2>&1 || true
    fi

    exit "$exit_code"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if (( $# > 2 )); then
    usage
    exit 2
fi

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
    fail "This script only runs on macOS."
fi

for REQUIRED_COMMAND in \
    basename codesign dirname ditto file find grep hdiutil mktemp mkdir mv \
    open pgrep rm rmdir stat unzip xattr zip; do
    if ! command -v "$REQUIRED_COMMAND" >/dev/null 2>&1; then
        fail "Required command is unavailable: $REQUIRED_COMMAND"
    fi
done

if [[ -n "${1:-}" ]]; then
    case "$1" in
        *.dmg | *.DMG | *.Dmg)
            DMG_PATH="$1"
            ;;
        *)
            SOURCE="$1"
            INPUT_APP="$SOURCE"
            ;;
    esac
else
    find_latest_downloaded_dmg

    if [[ -z "$DMG_PATH" ]]; then
        INPUT_APP="$SOURCE"
    fi
fi

if [[ "$SOURCE" != /* || "$BACKUP" != /* ]]; then
    fail "App and backup paths must be absolute."
fi

if [[ "$SOURCE" != *.app || "$BACKUP" != *.app ]]; then
    fail "App and backup paths must use the .app extension."
fi

if [[ "$SOURCE" == "$BACKUP" ]]; then
    fail "App and backup paths must be different."
fi

if [[ -e "$SOURCE" && -L "$SOURCE" ]]; then
    fail "The installed app must not be a symbolic link: $SOURCE"
fi

choose_backup_path "$BACKUP"

if [[ ! -x /usr/libexec/PlistBuddy ]]; then
    fail "Required command is unavailable: /usr/libexec/PlistBuddy"
fi

BACKUP_PARENT="$(dirname "$BACKUP")"
[[ -d "$BACKUP_PARENT" ]] || fail "Backup folder does not exist: $BACKUP_PARENT"

echo "Nuvio macOS installer and local signer"
echo "======================================"
echo

if [[ -n "$DMG_PATH" ]]; then
    [[ -f "$DMG_PATH" ]] || fail "DMG does not exist: $DMG_PATH"

    echo "Using downloaded DMG:"
    echo "  $DMG_PATH"
    echo
    echo "Preparing and mounting the DMG..."

    xattr -d com.apple.quarantine "$DMG_PATH" 2>/dev/null || true

    TEMP_BASE="${TMPDIR:-/tmp}"
    TEMP_BASE="${TEMP_BASE%/}"
    MOUNT_POINT="$(mktemp -d "$TEMP_BASE/nuvioadhocsigner-mount.XXXXXX")"

    if ! attach_dmg; then
        fail "The Nuvio DMG could not be mounted. Download it again and retry."
    fi

    DMG_MOUNTED=1

    FOUND_APP_COUNT=0

    while IFS= read -r -d '' CANDIDATE_APP; do
        CANDIDATE_BUNDLE_ID="$(read_bundle_id "$CANDIDATE_APP")"

        if [[ "$CANDIDATE_BUNDLE_ID" == "$EXPECTED_BUNDLE_ID" ]]; then
            INPUT_APP="$CANDIDATE_APP"
            FOUND_APP_COUNT=$((FOUND_APP_COUNT + 1))
        fi
    done < <(find "$MOUNT_POINT" \
        -type d \
        -name '*.app' \
        -prune \
        -print0)

    if (( FOUND_APP_COUNT != 1 )); then
        fail "Expected one Nuvio app in the DMG, found $FOUND_APP_COUNT."
    fi
else
    echo "No downloaded Nuvio DMG was found."
    echo "Using the installed app:"
    echo "  $SOURCE"
fi

[[ -d "$INPUT_APP" ]] || fail "Nuvio app does not exist: $INPUT_APP"
[[ ! -L "$INPUT_APP" ]] || fail "Nuvio app must not be a symbolic link."

INFO_PLIST="$INPUT_APP/Contents/Info.plist"
[[ -f "$INFO_PLIST" ]] || fail "Nuvio app has no Contents/Info.plist file."

BUNDLE_ID="$(read_bundle_id "$INPUT_APP")"

if [[ "$BUNDLE_ID" != "$EXPECTED_BUNDLE_ID" ]]; then
    echo "  Expected bundle ID: $EXPECTED_BUNDLE_ID"
    echo "  Found bundle ID: ${BUNDLE_ID:-missing}"
    fail "The selected app is not the expected Nuvio app."
fi

if pgrep -x Nuvio >/dev/null 2>&1; then
    echo
    echo "Nuvio is running. Close it, then run this command again."
    exit 1
fi

SOURCE_PARENT="$(dirname "$SOURCE")"
SOURCE_NAME="$(basename "$SOURCE")"

[[ -d "$SOURCE_PARENT" ]] || fail "Install folder does not exist: $SOURCE_PARENT"

STAGING_DIR="$(mktemp -d "$SOURCE_PARENT/.nuvioadhocsigner.XXXXXX")"
STAGED_APP="$STAGING_DIR/$SOURCE_NAME"

echo
echo "Bundle ID verified: $BUNDLE_ID"
echo "Installing to: $SOURCE"
echo "Keeping the previous or original app at: $BACKUP"

echo
echo "Creating a temporary copy..."

# ditto preserves the metadata and structure of macOS app bundles.
ditto "$INPUT_APP" "$STAGED_APP"

echo
echo "Removing quarantine from the temporary copy..."

xattr -dr com.apple.quarantine "$STAGED_APP" 2>/dev/null || true

echo
echo "Searching for Mach-O files signed by the old Nuvio Team ID..."
echo

FOUND=0
SIGNED=0

while IFS= read -r -d '' FILE_PATH; do
    if ! file -b "$FILE_PATH" 2>/dev/null | grep -q 'Mach-O'; then
        continue
    fi

    SIGNATURE_INFO="$(codesign -dv --verbose=4 "$FILE_PATH" 2>&1 || true)"

    if printf '%s\n' "$SIGNATURE_INFO" |
        grep -q "TeamIdentifier=${TEAM_ID}"; then

        FOUND=$((FOUND + 1))

        echo "[$FOUND] Re-signing:"
        echo "    $FILE_PATH"

        codesign \
            --force \
            --sign - \
            "$FILE_PATH"

        SIGNED=$((SIGNED + 1))
    fi
done < <(find "$STAGED_APP/Contents" -type f -print0)

echo
echo "Found $FOUND Mach-O file(s) with Team ID $TEAM_ID."
echo "Re-signed $SIGNED file(s)."

echo
echo "Re-signing the embedded macOS TorrServer binaries..."
echo

APP_JAR=""
APP_JAR_COUNT=0

while IFS= read -r -d '' JAR_PATH; do
    APP_JAR="$JAR_PATH"
    APP_JAR_COUNT=$((APP_JAR_COUNT + 1))
done < <(find "$STAGED_APP/Contents/app" \
    -maxdepth 1 \
    -type f \
    -name 'composeApp-desktop-*.jar' \
    -print0)

if (( APP_JAR_COUNT != 1 )); then
    fail "Expected one Nuvio desktop application JAR, found $APP_JAR_COUNT."
fi

TORRSERVER_WORK_DIR="$STAGING_DIR/torrserver-work"
TORRSERVER_VERIFY_DIR="$STAGING_DIR/torrserver-verify"
mkdir -p "$TORRSERVER_WORK_DIR" "$TORRSERVER_VERIFY_DIR"

if ! unzip -q \
    "$APP_JAR" \
    'torrserver/macos-*/TorrServer' \
    -d "$TORRSERVER_WORK_DIR"; then
    fail "Could not extract the embedded macOS TorrServer binaries."
fi

TORRSERVER_ENTRIES=()
TORRSERVER_SIGNED=0

while IFS= read -r -d '' TORRSERVER_PATH; do
    if ! file -b "$TORRSERVER_PATH" 2>/dev/null | grep -q 'Mach-O'; then
        echo "  $TORRSERVER_PATH"
        fail "An embedded TorrServer file is not a Mach-O executable."
    fi

    TORRSERVER_ENTRY="${TORRSERVER_PATH#"$TORRSERVER_WORK_DIR/"}"
    TORRSERVER_ENTRIES+=("$TORRSERVER_ENTRY")

    echo "Re-signing embedded binary:"
    echo "    $TORRSERVER_ENTRY"

    codesign \
        --force \
        --sign - \
        "$TORRSERVER_PATH"

    codesign \
        --verify \
        --strict \
        --verbose=2 \
        "$TORRSERVER_PATH"

    TORRSERVER_SIGNED=$((TORRSERVER_SIGNED + 1))
done < <(find "$TORRSERVER_WORK_DIR/torrserver" \
    -type f \
    -path '*/macos-*/TorrServer' \
    -print0)

if (( TORRSERVER_SIGNED == 0 )); then
    fail "No embedded macOS TorrServer binaries were found."
fi

(
    cd "$TORRSERVER_WORK_DIR"
    zip -q "$APP_JAR" "${TORRSERVER_ENTRIES[@]}"
)

if ! unzip -tq "$APP_JAR" >/dev/null; then
    fail "The Nuvio application JAR failed its integrity check."
fi

if ! unzip -q \
    "$APP_JAR" \
    'torrserver/macos-*/TorrServer' \
    -d "$TORRSERVER_VERIFY_DIR"; then
    fail "Could not verify the updated TorrServer binaries."
fi

TORRSERVER_VERIFIED=0

while IFS= read -r -d '' TORRSERVER_PATH; do
    SIGNATURE_INFO="$(codesign -dv --verbose=4 "$TORRSERVER_PATH" 2>&1 || true)"

    if ! printf '%s\n' "$SIGNATURE_INFO" | grep -q 'Signature=adhoc'; then
        echo "  $TORRSERVER_PATH"
        fail "Embedded TorrServer does not have an ad hoc signature."
    fi

    if printf '%s\n' "$SIGNATURE_INFO" |
        grep -q "TeamIdentifier=${TEAM_ID}"; then
        echo "  $TORRSERVER_PATH"
        fail "Embedded TorrServer still uses Team ID $TEAM_ID."
    fi

    codesign \
        --verify \
        --strict \
        --verbose=2 \
        "$TORRSERVER_PATH"

    TORRSERVER_VERIFIED=$((TORRSERVER_VERIFIED + 1))
done < <(find "$TORRSERVER_VERIFY_DIR/torrserver" \
    -type f \
    -path '*/macos-*/TorrServer' \
    -print0)

if (( TORRSERVER_VERIFIED != TORRSERVER_SIGNED )); then
    fail "Repacked TorrServer verification count does not match."
fi

echo "Re-signed and verified $TORRSERVER_VERIFIED embedded TorrServer binary file(s)."

echo
echo "Re-signing the complete app bundle..."

codesign \
    --force \
    --deep \
    --sign - \
    "$STAGED_APP"

echo
echo "Checking for remaining old Nuvio signatures..."

REMAINING=0

while IFS= read -r -d '' FILE_PATH; do
    if ! file -b "$FILE_PATH" 2>/dev/null | grep -q 'Mach-O'; then
        continue
    fi

    SIGNATURE_INFO="$(codesign -dv --verbose=4 "$FILE_PATH" 2>&1 || true)"

    if printf '%s\n' "$SIGNATURE_INFO" |
        grep -q "TeamIdentifier=${TEAM_ID}"; then

        echo "STILL SIGNED WITH OLD TEAM ID:"
        echo "    $FILE_PATH"

        REMAINING=$((REMAINING + 1))
    fi
done < <(find "$STAGED_APP/Contents" -type f -print0)

if (( REMAINING > 0 )); then
    fail "$REMAINING Mach-O file(s) still use the old Team ID."
fi

echo "No Mach-O files with Team ID $TEAM_ID remain."

echo
echo "Verifying the temporary app..."

codesign \
    --verify \
    --deep \
    --strict \
    --verbose=2 \
    "$STAGED_APP"

STAGED_BUNDLE_ID="$(read_bundle_id "$STAGED_APP")"

if [[ "$STAGED_BUNDLE_ID" != "$EXPECTED_BUNDLE_ID" ]]; then
    fail "Bundle ID changed in the temporary app."
fi

echo
echo "Keeping the original and installing the signed app..."

if [[ -e "$SOURCE" ]]; then
    mv "$SOURCE" "$BACKUP"
    ORIGINAL_MOVED=1
else
    ditto "$INPUT_APP" "$BACKUP"
fi

mv "$STAGED_APP" "$SOURCE"
SIGNED_APP_INSTALLED=1

echo
echo "Reading the installed signature..."

codesign -dv --verbose=4 "$SOURCE" 2>&1 |
    grep -E 'Identifier=|Signature=|Authority=|TeamIdentifier=' || true

echo
echo "========================================"
echo "Done."
echo
echo "Signed app:"
echo "  $SOURCE"
echo
echo "Original or previous app:"
echo "  $BACKUP"
echo
echo "Opening Nuvio..."

open "$SOURCE"

echo
echo "This script changed only the selected DMG and Nuvio app."
echo "It did not disable Gatekeeper, SIP, or XProtect."
