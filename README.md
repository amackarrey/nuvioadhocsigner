# Nuvio macOS installer and local signer

This repository has one script that installs and locally signs `Nuvio.app` on
macOS. You download the official Nuvio DMG, run one Terminal command, and wait
for Nuvio to open.

The script keeps the original or previously installed app as a backup. It does
not disable Gatekeeper, SIP, or XProtect.

Only use a Nuvio DMG downloaded from a source you trust. Local signing does not
check whether an app is safe.

## Setup

### Step 1: Prepare the Nuvio DMG

This step is required for a new installation from the GitHub release.

1. Download the macOS DMG from the
   [official Nuvio Desktop releases](https://github.com/NuvioMedia/NuvioDesktop/releases).
2. Leave the DMG in your Downloads folder.
3. Do not open the DMG or drag `Nuvio.app` into Applications. The script handles
   both parts for you.
4. Quit Nuvio if it is running.

The script removes quarantine from the DMG and mounts it read-only before it
installs Nuvio. You do not need to run a separate `xattr` command.

If `Nuvio.app` is already in your Applications folder and you do not want to
install a new DMG, skip Step 1 and follow [Sign an installed copy](#sign-an-installed-copy).

### Step 2: Run the installer and signer

1. Open **Finder > Applications > Utilities > Terminal**.
2. Paste this command and press Return:

```bash
curl -fsSL https://raw.githubusercontent.com/amackarrey/nuvioadhocsigner/main/resign_nuvio.sh -o "$HOME/Downloads/install_nuvio.sh" && bash "$HOME/Downloads/install_nuvio.sh"
```

This one command downloads the signer from this repository and runs it. The
script then:

- Finds the newest Nuvio DMG in Downloads.
- Removes quarantine from that DMG and mounts it read-only.
- Checks the Nuvio bundle ID before making changes.
- Copies, locally signs, and verifies the app.
- Keeps a backup in Applications.
- Opens Nuvio when installation succeeds.

Wait for Terminal to print `Done.`. If a check fails, the script stops and
keeps the previous app.

You can [read the script](https://github.com/amackarrey/nuvioadhocsigner/blob/main/resign_nuvio.sh)
before running it.

## Choose a specific DMG

If Downloads contains more than one Nuvio DMG, pass the exact file to the
script:

```bash
bash "$HOME/Downloads/install_nuvio.sh" "/path/to/Nuvio-macOS-arm64-version.dmg"
```

You can type `bash "$HOME/Downloads/install_nuvio.sh" ` with a space at the
end, drag the DMG into Terminal, and press Return.

## Sign an installed copy

If `Nuvio.app` is already in Applications, quit Nuvio and run this command. It
downloads the signer and selects the installed app directly, even if an old
Nuvio DMG is still in Downloads.

```bash
curl -fsSL https://raw.githubusercontent.com/amackarrey/nuvioadhocsigner/main/resign_nuvio.sh -o "$HOME/Downloads/install_nuvio.sh" && bash "$HOME/Downloads/install_nuvio.sh" "/Applications/Nuvio.app"
```

## Backups

The first backup uses this path:

```text
/Applications/Nuvio-original.app
```

If that path already exists, the script uses
`/Applications/Nuvio-original-2.app`, then `Nuvio-original-3.app`, and so on.
It does not overwrite an existing backup.

To restore a backup:

1. Quit Nuvio.
2. Open the Applications folder.
3. Rename `Nuvio.app` to `Nuvio-signed.app`.
4. Rename the backup you want to restore to `Nuvio.app`.
5. Open `Nuvio.app`.

## Common errors

`Nuvio is running`

Quit Nuvio and run the same command again.

`The Nuvio DMG could not be mounted`

Delete the incomplete DMG, download it again from the official release page,
and rerun the command.

`Expected one Nuvio app in the DMG`

The selected DMG does not contain the expected app. Download the macOS DMG
from the official Nuvio release page.

`Permission denied`

The current account cannot write to the Applications folder. Sign in with an
administrator account and run the same command again.

## What the script changes

The script validates the bundle ID `com.nuvio.media.desktop`, creates a
temporary copy, and removes quarantine from that copy. It re-signs regular
macOS executables that use the old Nuvio Team ID and re-signs the embedded
TorrServer binaries inside the application JAR. It then verifies the complete
app before replacing the installed copy.

If installation fails after the previous app was moved, the script tries to
restore it automatically.

## Limits

- The signature is for local use.
- The script does not notarize Nuvio.
- A future Nuvio update may replace the signed app.
- This repository does not contain or distribute Nuvio.

This project is unofficial and is not affiliated with Nuvio or Apple.

## Credits

This project was adapted from
[mournami/resign-rave-macos](https://github.com/mournami/resign-rave-macos).
