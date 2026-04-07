<p align="center">
  <img src="docs/phonograph.png" width="160" alt="JamBox icon">
</p>

# JamBox

A simple music player for macOS 14+. Point it at a folder of music and let it roll.

## Features

- **Gapless playback.** The whole point. Tracks flow into each other with no audible seam.
- **Local files only.** No accounts, no streaming, no library import. Pick a folder, get a track list.
- **Wide format support.** mp3, m4a, flac, aiff, wav, alac, aac.
- **Album art.** Pulled from embedded metadata or a `cover`/`folder`/`album`/`front` image in the folder.
- **Folders persist.** Your picked folders stick around across launches.

## Install

Download the latest `JamBox-*.dmg` from the [Releases page](../../releases), open it, and drag **JamBox.app** to the Applications shortcut.

**First launch.** macOS will block the app the first time with a "cannot be checked for malicious software" message. JamBox isn't signed by a paid Apple Developer account, so Gatekeeper objects. There's a `READ ME FIRST.txt` in the DMG with full instructions. The fastest fix is to open Terminal and run:

```
xattr -dr com.apple.quarantine /Applications/JamBox.app
```

Then double-click JamBox normally. You only need to do this once.

## Using it

1. Launch the app.
2. Add a folder (probably `~/Music`).
3. Double-click a track to play. Use the bottom bar to pause, skip, or scrub.

## Themes

Three themes are available under **JamBox → Theme** in the menu bar:

- **Light** (default) — clean and minimal
- **Dark** — VSCode-inspired dark grays with a blue accent
- **Candy** — vibrant pink and orange

Your choice persists across launches.

## Replacing the app icon

Drop any square-ish image at a path of your choice and run:

```
python3 scripts/make_icon.py path/to/new_image.png
```

The script crops the white border, applies an anti-aliased circular mask (assuming circular source art — for non-circular icons, see the comment in the script for how to switch back to a squircle mask), regenerates all the required pixel sizes, and rewrites `Contents.json`. Then rebuild the app.

Requires Pillow: `pip3 install --user Pillow`. There's also `scripts/test_make_icon.py` which exercises the script end-to-end against a synthetic fixture.
