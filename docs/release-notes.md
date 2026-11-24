A native macOS menu bar app for Home Assistant: rooms built from your Areas, device screens for lights, climate, covers, fans, media, locks, alarms and sensors, and a layout you can edit in Settings or right in the panel.

## Install

1. Download **HomePanel-x.y.z.dmg** below, open it, and drag **HomePanel** to **Applications**.
2. Open HomePanel. macOS says it can't check it for malicious software, because this build isn't notarized by Apple (that needs a paid developer account). Click **Done**.
3. Open **System Settings → Privacy & Security**, scroll down to the message about HomePanel, and click **Open Anyway**. Confirm with your password or Touch ID.
4. HomePanel opens Settings with a short setup: find your Home Assistant, paste a long-lived access token, pick your rooms.

You only do steps 2–3 once. Requires macOS 26 or later; runs on Apple silicon and Intel Macs.

Prefer not to run an un-notarized app? Build it yourself from source; the README explains how.

**Checksum:** the `.sha256` file holds the DMG's SHA-256. Check it with `shasum -a 256 HomePanel-x.y.z.dmg`.

**After updating:** macOS may ask once whether HomePanel can use its saved token in your keychain. Choose **Always Allow**.
