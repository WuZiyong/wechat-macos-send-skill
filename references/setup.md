# Setup and permissions

This skill targets macOS with the desktop WeChat app installed and already logged in. It uses only local macOS components: Accessibility/CGEvent, `screencapture`, Vision OCR, AppKit pasteboard, and a precompiled Swift helper.

## Requirements

- `/Applications/WeChat.app`
- Xcode Command Line Tools providing `/usr/bin/swiftc`
- macOS Vision framework (built in)
- Accessibility permission for the process that launches the helper
- Screen Recording / Screen & System Audio Recording permission so the helper can capture the WeChat window for local OCR

Image/file sends additionally require an inline rich composer exposed as an
Accessibility text area. Read [attachment behavior](attachments.md) before testing
these modes on a new WeChat version. Separate attachment confirmation dialogs are
not supported. `zsh scripts/test.sh` builds the helper and runs isolated attachment
tests without opening WeChat or sending messages; live acceptance is separate.

If running directly from Terminal, grant Terminal the permissions. If ChatGPT controls the Mac through Remote Desktop Commander, the authorized Node/remote process may also need Accessibility permission.

## Install and build once

Copy the whole skill folder into `~/.codex/skills/wechat-macos-send`, then compile once:

```bash
~/.codex/skills/wechat-macos-send/scripts/build.sh
```

The shareable package intentionally relies on source + `build.sh` rather than a prebuilt machine-specific executable. `scripts/run.sh` will also build automatically if the binary is missing or either Swift source is newer.

For installation diagnostics, use the commands in [troubleshooting.md](troubleshooting.md). They are advanced checks and are not part of routine sending.

## Fast remote use

For normal messaging, make a single remote process call:

```bash
~/.codex/skills/wechat-macos-send/scripts/run.sh send 'RECIPIENT' 'MESSAGE'
```

Intermediate screenshots stay in a local temporary directory and are deleted on normal exit. The remote caller receives only a compact one-line result. This removes the multiple screenshot/upload/reasoning round trips used by v1.

On the tested Mac, local contact search + OCR verification completed in roughly 1.1–1.3 seconds after warm-up, and contact + exact draft verification completed in roughly 2.4 seconds. A real send adds only the final click and local post-send checks, so expect a few seconds when WeChat and the remote relay are healthy. First execution after reboot can be slower while macOS loads Vision/AppKit frameworks.
