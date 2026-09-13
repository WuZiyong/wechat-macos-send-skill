---
name: wechat-macos-send
description: Send one explicitly authorized WeChat message from an authorized Mac through Remote Desktop Commander and the local wechat-macos-send helper.
---

# WeChat macOS Send

Use this skill only when the current user explicitly authorizes one recipient and one exact message.

## Requirement

Remote Desktop Commander must be installed, connected, and authorized for the user's Mac. The local helper must be installed at `~/.codex/skills/wechat-macos-send` on that Mac.

If either requirement is unavailable, do not improvise another delivery path. Tell the user what connection or local installation is missing.

## Normal send

For an ordinary send request, use Remote Desktop Commander to run exactly one command on the authorized Mac:

```bash
~/.codex/skills/wechat-macos-send/scripts/run.sh send 'RECIPIENT' 'MESSAGE'
```

Do not run `doctor`, `check`, `dryrun`, screenshots, or other pre/post-flight commands during a normal send. The local `send` command already verifies the conversation title, exact draft, send action, composer clear state, and final conversation title.

A successful send returns `SENT contact=... elapsed_ms=...`.

## Safety and retries

Authorization covers one send attempt only. Never infer permission for another recipient, another message, a follow-up, or bulk outreach.

If the remote call or local send result is uncertain or times out, do not automatically retry because that could duplicate the message. If a definite pre-send error proves nothing was sent, report it. Retry only after the user explicitly asks.

If `contact_verify_failed` reports a different plausible conversation or group title, do not substitute it silently. Show the observed title and obtain explicit confirmation before retrying with that exact title.

Use Advanced/Troubleshooting commands only when the user explicitly asks to diagnose or repair the skill.
