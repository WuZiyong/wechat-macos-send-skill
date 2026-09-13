---
name: wechat-macos-send
description: Send one explicitly authorized WeChat message from macOS with one fast local execution. The helper searches the recipient, verifies the conversation title and exact draft locally, sends once, and confirms the composer cleared. Use for explicit one-recipient WeChat send requests; do not use for bulk or unsolicited outreach.
metadata:
  short-description: Fast verified WeChat sending on macOS
---

# WeChat macOS Send v2

Use the local `wechatctl` helper through `scripts/run.sh`.

## Normal mode: one send call

For an ordinary explicit request to send one message, make exactly one execution:

```bash
scripts/run.sh send 'RECIPIENT' 'MESSAGE'
```

Do not run `doctor`, `check`, `dryrun`, screenshots, or other pre/post-flight commands in normal mode. The `send` operation already performs the local contact, draft, send, and post-send verification internally.

A successful send returns one compact line such as:

```text
SENT contact=RECIPIENT elapsed_ms=2840
```

Only use `send` when the current user explicitly authorizes both the recipient and message. Authorization covers one send attempt only; do not infer permission for retries, follow-ups, other contacts, or bulk messaging.

If `send` returns an error, stop. Never automatically rerun an uncertain or timed-out send because that could duplicate a message.

## Advanced / Troubleshooting

Only enter troubleshooting mode when the user explicitly asks to diagnose/test/setup the skill, or when a send returns a definite setup/pre-send error that needs investigation. Read [references/troubleshooting.md](references/troubleshooting.md) for `doctor`, `check`, `dryrun`, debug captures, and known failure handling. For first-time installation and macOS permissions, read [references/setup.md](references/setup.md).
