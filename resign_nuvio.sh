#!/usr/bin/env bash

set -euo pipefail

TEAM_ID="8QBDZ766S3"
EXPECTED_BUNDLE_ID="com.nuvio.media.desktop"

SOURCE="${1:-/Applications/Nuvio.app}"
BACKUP="${2:-/Applications/Nuvio-original.app}"

STAGING_DIR=""
STAGED_APP=""
ORIGINAL_MOVED=0
SIGNED_APP_INSTALLED=0

cleanup() {
    local exit_code=$?

    if (( ORIGINAL_MOVED == 1 && SIGNED_APP_INSTALLED == 0 )); then
        if [[ ! -e "$SOURCE" && -e "$BACKUP" ]]; then
            echo
            echo "Restoring the original app after an installation failure..."
            mv "$BACKUP" "$SOURCE" || {
                echo "ERROR: Automatic restore failed."
                echo "Original app remains at: $BACKUP"
            }
        fi
    fi

    if [[ -n "$STAGING_DIR" && -d "$STAGING_DIR" ]]; then
        rm -rf -- "$STAGING_DIR"
    fi

    return "$exit_code"
}

trap cleanup EXIT

echo "Nuvio macOS local re-sign"
echo "========================"
echo
echo "Installed app: $SOURCE"
echo "Original backup: $BACKUP"
echo

for REQUIRED_COMMAND in codesign ditto file find mktemp mv unzip xattr zip; do
    if ! command -v "$REQUIRED_COMMAND" >/dev/null 2>&1; then
        echo "ERROR: Required command is unavailable: $REQUIRED_COMMAND"
        exit 1
    fi
done

if [[ "$SOURCE" != /* || "$BACKUP" != /* ]]; then
    echo "ERROR: Source and backup paths must be absolute."
    exit 1
fi

if [[ ! -d "$SOURCE" ]]; then
    echo "ERROR: Source app does not exist:"
    echo "  $SOURCE"
    exit 1
fi

if [[ -L "$SOURCE" ]]; then
    echo "ERROR: Source app must not be a symbolic link."
    exit 1
fi

if [[ "$SOURCE" != *.app || "$BACKUP" != *.app ]]; then
    echo "ERROR: Source and backup must both use the .app extension."
    exit 1
fi

if [[ "$SOURCE" == "$BACKUP" ]]; then
    echo "ERROR: Source and backup paths must be different."
    exit 1
fi

if [[ -e "$BACKUP" ]]; then
    echo "ERROR: Backup path already exists:"
    echo "  $BACKUP"
    echo
    echo "Move the existing backup elsewhere before running this script again."
    exit 1
fi

INFO_PLIST="$SOURCE/Contents/Info.plist"

if [[ ! -f "$INFO_PLIST" ]]; then
    echo "ERROR: Source app has no Contents/Info.plist file."
    exit 1
fi

BUNDLE_ID="$(/usr/libexec/PlistBuddy \
    -c 'Print :CFBundleIdentifier' \
    "$INFO_PLIST" 2>/dev/null || true)"

if [[ "$BUNDLE_ID" != "$EXPECTED_BUNDLE_ID" ]]; then
    echo "ERROR: The selected app is not the expected Nuvio app."
    echo "  Expected bundle ID: $EXPECTED_BUNDLE_ID"
    echo "  Found bundle ID: ${BUNDLE_ID:-missing}"
    exit 1
fi

SOURCE_PARENT="$(dirname "$SOURCE")"
SOURCE_NAME="$(basename "$SOURCE")"
STAGING_DIR="$(mktemp -d "$SOURCE_PARENT/.nuvioadhocsigner.XXXXXX")"
STAGED_APP="$STAGING_DIR/$SOURCE_NAME"

echo "Bundle ID verified: $BUNDLE_ID"

echo
echo "[1/9] Creating a temporary copy..."

# ditto preserves the metadata and structure of macOS app bundles.
ditto "$SOURCE" "$STAGED_APP"

echo
echo "[2/9] Removing quarantine from the temporary copy..."

xattr -dr com.apple.quarantine "$STAGED_APP" 2>/dev/null || true

echo
echo "[3/9] Searching for Mach-O files signed by the old Nuvio Team ID..."
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
echo "[4/9] Re-signing the embedded macOS TorrServer binaries..."
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
    echo "ERROR: Expected one Nuvio desktop application JAR, found $APP_JAR_COUNT."
    exit 1
fi

TORRSERVER_WORK_DIR="$STAGING_DIR/torrserver-work"
TORRSERVER_VERIFY_DIR="$STAGING_DIR/torrserver-verify"
mkdir -p "$TORRSERVER_WORK_DIR" "$TORRSERVER_VERIFY_DIR"

if ! unzip -q \
    "$APP_JAR" \
    'torrserver/macos-*/TorrServer' \
    -d "$TORRSERVER_WORK_DIR"; then
    echo "ERROR: Could not extract the embedded macOS TorrServer binaries."
    exit 1
fi

TORRSERVER_ENTRIES=()
TORRSERVER_SIGNED=0

while IFS= read -r -d '' TORRSERVER_PATH; do
    if ! file -b "$TORRSERVER_PATH" 2>/dev/null | grep -q 'Mach-O'; then
        echo "ERROR: Embedded TorrServer file is not a Mach-O executable:"
        echo "  $TORRSERVER_PATH"
        exit 1
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
    echo "ERROR: No embedded macOS TorrServer binaries were found."
    exit 1
fi

(
    cd "$TORRSERVER_WORK_DIR"
    zip -q "$APP_JAR" "${TORRSERVER_ENTRIES[@]}"
)

if ! unzip -tq "$APP_JAR" >/dev/null; then
    echo "ERROR: The Nuvio application JAR failed its integrity check."
    exit 1
fi

if ! unzip -q \
    "$APP_JAR" \
    'torrserver/macos-*/TorrServer' \
    -d "$TORRSERVER_VERIFY_DIR"; then
    echo "ERROR: Could not verify the updated TorrServer binaries."
    exit 1
fi

TORRSERVER_VERIFIED=0

while IFS= read -r -d '' TORRSERVER_PATH; do
    SIGNATURE_INFO="$(codesign -dv --verbose=4 "$TORRSERVER_PATH" 2>&1 || true)"

    if ! printf '%s\n' "$SIGNATURE_INFO" | grep -q 'Signature=adhoc'; then
        echo "ERROR: Embedded TorrServer does not have an ad hoc signature:"
        echo "  $TORRSERVER_PATH"
        exit 1
    fi

    if printf '%s\n' "$SIGNATURE_INFO" |
        grep -q "TeamIdentifier=${TEAM_ID}"; then
        echo "ERROR: Embedded TorrServer still uses Team ID $TEAM_ID:"
        echo "  $TORRSERVER_PATH"
        exit 1
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
    echo "ERROR: Repacked TorrServer verification count does not match."
    exit 1
fi

echo "Re-signed and verified $TORRSERVER_VERIFIED embedded TorrServer binary file(s)."

echo
echo "[5/9] Re-signing the complete app bundle..."

codesign \
    --force \
    --deep \
    --sign - \
    "$STAGED_APP"

echo
echo "[6/9] Checking for remaining old Nuvio signatures..."

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
    echo
    echo "ERROR: $REMAINING Mach-O file(s) still use the old Team ID."
    exit 1
fi

echo "No Mach-O files with Team ID $TEAM_ID remain."

echo
echo "[7/9] Verifying the temporary app..."

codesign \
    --verify \
    --deep \
    --strict \
    --verbose=2 \
    "$STAGED_APP"

STAGED_BUNDLE_ID="$(/usr/libexec/PlistBuddy \
    -c 'Print :CFBundleIdentifier' \
    "$STAGED_APP/Contents/Info.plist" 2>/dev/null || true)"

if [[ "$STAGED_BUNDLE_ID" != "$EXPECTED_BUNDLE_ID" ]]; then
    echo "ERROR: Bundle ID changed in the temporary app."
    exit 1
fi

echo
echo "[8/9] Backing up the original and installing the signed app..."

mv "$SOURCE" "$BACKUP"
ORIGINAL_MOVED=1

mv "$STAGED_APP" "$SOURCE"
SIGNED_APP_INSTALLED=1

echo
echo "[9/9] Reading the installed signature..."

codesign -dv --verbose=4 "$SOURCE" 2>&1 |
    grep -E 'Identifier=|Signature=|Authority=|TeamIdentifier=' || true

echo
echo "========================================"
echo "Done."
echo
echo "Ad hoc signed app:"
echo "  $SOURCE"
echo
echo "Original app backup:"
echo "  $BACKUP"
echo
echo "Launch Nuvio with:"
printf "  open %q\n" "$SOURCE"
echo
echo "NOTE:"
echo "  Nuvio was signed for this Mac only, so do not distribute it; this script did not change SIP, XProtect, or Gatekeeper settings."
