# nuvioadhocsigner

This script creates a locally signed copy of `Nuvio.app` so it can run on your
Mac. It saves the original app as `/Applications/Nuvio-original.app`, then puts
the signed copy at `/Applications/Nuvio.app`.

Only use a Nuvio app downloaded from a source you trust. Local signing does not
check whether an app is safe.

Repository: [amackarrey/nuvioadhocsigner](https://github.com/amackarrey/nuvioadhocsigner)

## Before you start

- These instructions are for macOS.
- Quit Nuvio if it is open.
- Keep the original backup until the signed app works.
- Do not run the script twice without moving or restoring the existing backup.

## Step 1: Open the Nuvio DMG

> Already have `Nuvio.app` in **Finder > Applications**? Skip Steps 1 and 2.
> Start at Step 3.

1. Download the Nuvio DMG from a source you trust.
2. Open Finder and click **Downloads**.
3. Double-click the downloaded DMG.
4. Click **Open** if macOS asks for confirmation.
5. Wait for the DMG window to appear.

If the DMG does not open, use the [DMG troubleshooting](#dmg-troubleshooting)
section below.

## Step 2: Drag Nuvio into Applications

1. Find `Nuvio.app` in the DMG window.
2. Drag `Nuvio.app` onto the **Applications** folder shown in that window.
3. Wait for the copy to finish.
4. Eject the Nuvio disk image from the Finder sidebar.
5. Open **Finder > Applications** and check that `Nuvio.app` is there.
6. Do not open Nuvio yet.

## Step 3: Download the signer

Choose one method. Use Git if it is already installed. Otherwise, use the ZIP
method.

### Option A: Use Git

1. Open **Finder > Applications > Utilities > Terminal**.
2. Copy the command below.
3. Paste it into Terminal and press Return.

```bash
cd "$HOME/Downloads" && git clone https://github.com/amackarrey/nuvioadhocsigner.git && cd nuvioadhocsigner
```

This downloads the signer into your Downloads folder and opens that folder in
Terminal.

If Terminal says `destination path already exists`, run this instead:

```bash
cd "$HOME/Downloads/nuvioadhocsigner" && git pull
```

If macOS asks to install command line developer tools, follow the prompt. Run
the Git command again after the installation finishes.

### Option B: Download the ZIP

1. Click [Download nuvioadhocsigner as a ZIP](https://github.com/amackarrey/nuvioadhocsigner/archive/refs/heads/main.zip).
2. Open Finder and click **Downloads**.
3. Double-click `nuvioadhocsigner-main.zip`. Your browser may have already
   extracted it.
4. Open Terminal.
5. Type `cd` followed by one space. Do not press Return yet.
6. Drag the `nuvioadhocsigner-main` folder from Finder into Terminal.
7. Press Return.

After using either method, run:

```bash
ls
```

You should see these two files:

```text
README.md
resign_nuvio.sh
```

## Step 4: Run the signer

Make sure Nuvio is closed. Copy these three lines, paste them into Terminal,
and press Return:

```bash
chmod +x ./resign_nuvio.sh
xattr -d com.apple.quarantine ./resign_nuvio.sh 2>/dev/null || true
./resign_nuvio.sh
```

The process may take a little while. Keep Terminal open and wait until it
prints:

```text
Done.
```

The script stops without replacing Nuvio if a safety check fails.

After signing the regular app files, the script also signs the embedded
TorrServer files used for P2P streaming. Debrid users do not need to do
anything for this step.

## Step 5: Open Nuvio

Paste this command into Terminal and press Return:

```bash
open "/Applications/Nuvio.app"
```

The signed app is now `/Applications/Nuvio.app`. The app from before signing is
saved here:

```text
/Applications/Nuvio-original.app
```

Keep that backup until you are sure the signed app works.

## DMG troubleshooting

Try this first:

1. Hold Control and click the DMG in Finder.
2. Click **Open**.
3. Click **Open** again if macOS asks.

If it still does not open:

1. Rename the downloaded DMG to `Nuvio.dmg`.
2. Open Terminal.
3. Paste these commands one at a time:

```bash
xattr -d com.apple.quarantine "$HOME/Downloads/Nuvio.dmg" 2>/dev/null || true
open "$HOME/Downloads/Nuvio.dmg"
```

No output from the first command is normal. The second command should open the
DMG. Continue with Step 2.

Do not use `chmod +x` on a DMG. A DMG is a disk image, not a program.

## Common errors

`Source app does not exist`

`Nuvio.app` is not in the Applications folder. Return to Step 2.

`Backup path already exists`

The script found `/Applications/Nuvio-original.app` from an earlier run. Do not
delete it unless you are certain you no longer need the original app. Move it
somewhere safe or restore it before running the script again.

`Permission denied`

Make sure Terminal is inside the signer folder, then run:

```bash
chmod +x ./resign_nuvio.sh
```

## Restore the original app

You can restore the original app in Finder:

1. Quit Nuvio.
2. Open the Applications folder.
3. Rename `Nuvio.app` to `Nuvio-signed.app`.
4. Rename `Nuvio-original.app` to `Nuvio.app`.
5. Open `Nuvio.app`.

This keeps the signed copy instead of deleting it.

## What the script does

1. Checks that the app is Nuvio by reading its bundle ID.
2. Creates a temporary copy of the app.
3. Removes quarantine from the temporary copy.
4. Re-signs the regular macOS executable files.
5. Extracts and re-signs both macOS TorrServer files inside the application JAR.
6. Places the TorrServer files back into the JAR and verifies them.
7. Re-signs and verifies the complete app.
8. Moves the original app to `/Applications/Nuvio-original.app`.
9. Installs the signed copy as `/Applications/Nuvio.app`.

The script does not move the original app until the signed copy passes its
checks. If installation fails, it tries to restore the original automatically.

## Technical defaults

- Installed app: `/Applications/Nuvio.app`
- Original backup: `/Applications/Nuvio-original.app`
- Expected bundle ID: `com.nuvio.media.desktop`
- Old Team ID: `8QBDZ766S3`

You can provide different source and backup paths:

```bash
./resign_nuvio.sh \
  "/Applications/Nuvio.app" \
  "/Applications/Nuvio-original.app"
```

Both paths must be absolute, different, and end with `.app`.

## Limits

- The new signature is for local use only.
- The script does not notarize Nuvio.
- The script does not disable Gatekeeper, SIP, or XProtect.
- A future Nuvio update may replace the signed app.
- This repository does not contain or distribute Nuvio.

This project is unofficial and is not affiliated with Nuvio or Apple.

## Credits

This project was adapted from
[mournami/resign-rave-macos](https://github.com/mournami/resign-rave-macos)
and written with help from AI.
