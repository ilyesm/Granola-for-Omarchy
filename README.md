# Granola for Omarchy

Fork of [tirtha4/Granola-for-Linux](https://github.com/tirtha4/Granola-for-Linux) as an [Omarchy](https://omarchy.org/) plugin: a top-bar widget plus a Linux build of [Granola](https://www.granola.ai).

Granola only ships for macOS and Windows. It is an Electron app, so the macOS `.dmg` already holds the JavaScript. This repo swaps in the Linux runtime, rebuilds the native modules, and puts a status icon on the Omarchy bar.

No Wine, no VM, no emulation.

## Install on Omarchy

```bash
omarchy plugin add https://github.com/ilyesm/Granola-for-Omarchy.git --enable
```

That clones the plugin into `~/.config/omarchy/plugins/ilyesm.granola` and places **Granola** on the top bar (right by default). Then:

1. Click the bar icon → **I** or the missing-app prompt to install the desktop app, **or** run `./granola-linux.sh` from this repo (downloads the latest `.dmg` if you do not pass one).
2. Open Granola from the bar (right-click, or **O** in the panel) and sign in.

The bar widget:

| | |
|---|---|
| Left click | Panel with the current/next meeting, people, location, and coming-up list |
| Switch / right click | Start a recording (`granola://new-document?auto_transcribe=1`) |
| Super+Shift+R | Same recording action, as a Hyprland global bind (Wayland cannot use Electron globalShortcut) |
| Middle click | Refresh |
| Recording | Icon pulses and turns the urgent color while Granola has a microphone capture |

Upcoming events are read from Granola’s encrypted local database (SQLCipher) using the key in `Granola Safe Storage` on the session keyring. Notes stay in Granola. If a newer Granola `.dmg` is on granola.ai, the panel offers **Update**.

Update later with `omarchy plugin update ilyesm.granola`. Remove with `omarchy plugin remove ilyesm.granola`. Uninstall the desktop app with `./uninstall.sh` (`--purge` also drops `~/.config/Granola`).

## Install the desktop app only

You do not need the bar widget to run Granola:

```bash
./granola-linux.sh
# or: ./granola-linux.sh "Granola - AI Notepad.dmg"
```

Needs `g++` 11+, `node`, `npm`, `python3`, `curl`, `make`, and a modern `7zz` (LZFSE). Distro `p7zip` cannot read the `.dmg`. On x86-64 or aarch64 the script fetches the matching Electron runtime.

Tested on Pop!_OS (Granola 7.452.1, Electron 42.7.0) and Arch Linux ARM / Omarchy on Apple Silicon (Granola 7.576.0, Electron 44.0.0).

Set `INSTALL_DIR=` to install somewhere other than `~/Applications/granola`.

## What works

| | |
|---|---|
| ✅ | Notes, editor, sync, AI features, and search. The core app. |
| ✅ | Sign-in with Google, Microsoft, or SSO |
| ✅ | Encrypted local database that survives restarts |
| ✅ | Microphone recording |
| ✅ | Omarchy bar: next meeting, coming up, recording switch |
| ✅ | Global record hotkey on Hyprland (`Super+Shift+R`) |
| ✅ | Manual update from the bar when a newer `.dmg` is published |
| ⚠️ | System audio is Chromium/PipeWire `getDisplayMedia`, not Core Audio. The launcher enables `WebRTCPipeWireCapturer`; the other side of a call is still weaker than macOS. |
| ❌ | Apple Calendar (EventKit). Google and Microsoft calendars still work, since those run on the server. |

## Build it yourself

If you would rather not run the script, the conversion takes six steps:

1. Extract the `.dmg` with a modern `7zz`. The `p7zip` in most distros cannot read its LZFSE compression.
2. Read the Electron version out of `Electron Framework.framework/.../Info.plist`, then download that exact Linux build.
3. Unzip the Linux runtime into your install folder and delete `resources/default_app.asar`.
4. Copy `app.asar`, `app.asar.unpacked`, and `icons/` from the bundle into the runtime's `resources/`. Skip every Mac binary, since they all sit behind `darwin` checks.
5. Patch the platform string inside `app.asar` so it reports `Windows`. Granola's API returns a 500 error for `platform=linux`, so sign-in fails without this.
6. Rebuild `better-sqlite3-multiple-ciphers` from the C++ source inside `app.asar.unpacked` using g++ 11 or newer. Granola's version adds an `updateHook()` that no public build has.

On linux-arm64 the script also compiles `electron-click-drag-plugin` (no upstream prebuild). Four of those steps fail with errors that do not point at the real cause. `granola-linux.sh` has the exact commands, with comments explaining each one.

## Notes

- Nothing here gets around licensing or sign-in. You use your own account and the app talks to Granola's real servers. The only patch is a platform label that their API refuses to accept.
- Granola's code belongs to Granola. Do not commit `app.asar` or the `.dmg`. The `.gitignore` covers both.
- Running the script again is safe. It wipes and rebuilds the install folder and leaves your notes in `~/.config/Granola` alone.
- `./uninstall.sh --purge` also removes the local notes cache and login.
