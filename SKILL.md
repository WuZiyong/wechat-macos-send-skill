---
name: wechat-macos-send
description: Send one explicitly authorized WeChat text, image, or local file from macOS with one local execution. The helper verifies the conversation and draft, sends once, and checks that the composer cleared. Use for one-recipient send requests; not bulk or unsolicited outreach.
metadata:
  short-description: Fast verified WeChat sending on macOS
---

# WeChat macOS Send v2

Use the local `wechatctl` helper through `scripts/run.sh`.

## Normal mode: one send call

For an ordinary explicit request to send one message, make exactly one execution:

```bash
scripts/run.sh send 'RECIPIENT' 'MESSAGE'
scripts/run.sh send-image 'RECIPIENT' '/absolute/path/photo.png'
scripts/run.sh send-file 'RECIPIENT' '/absolute/path/report.pdf'
```

Choose exactly one command for the authorized payload. `send-image` pastes decoded
image data; use `send-file` when the original file bytes, filename, or animation
must be preserved. One attachment per call, with no caption or additional text.
Resolve the user's intended local file before calling; never substitute a different
file or send a path string as the message. Read [attachment behavior](references/attachments.md)
when handling image/file requests for supported layouts and verification limits.

Do not run `doctor`, `check`, `dryrun`, `validate-*`, screenshots, or other pre/post-flight commands in normal mode. Each send operation already performs the local contact, draft, send, and post-send verification internally.

A successful send returns one compact line such as:

```text
SENT contact=RECIPIENT elapsed_ms=2840
```

Only use a send command when the current user explicitly authorizes both the recipient and text or attachment. Authorization covers one send attempt only; do not infer permission for retries, follow-ups, other contacts, or bulk messaging.

If any send command returns an error, stop. Never automatically rerun an uncertain or timed-out send because that could duplicate a message. Attachment attempts become pending before paste; errors may leave a draft or a client-specific dialog. Do not click through, resend, or switch modes automatically.

Report `SENT` as local send verification, not proof that the recipient received or read the message.

## Advanced / Troubleshooting

Only enter troubleshooting mode when the user explicitly asks to diagnose/test/setup the skill, or when a send returns a definite setup/pre-send error that needs investigation. Read [references/troubleshooting.md](references/troubleshooting.md) for `doctor`, `check`, `dryrun`, debug captures, and known failure handling. For first-time installation and macOS permissions, read [references/setup.md](references/setup.md).
