# WeChat macOS Send Skill

A fast, locally verified skill for sending a single WeChat text, image, or file from macOS.

- One `send` call for normal use
- Local contact and draft verification
- No screenshot round-trips during normal sending
- Prevents uncertain automatic retries
- Image pixels and file contents are verified by copying the rich draft back locally

## Install

```bash
git clone https://github.com/WuZiyong/wechat-macos-send-skill.git \
  ~/.codex/skills/wechat-macos-send
```

Build once:

```bash
~/.codex/skills/wechat-macos-send/scripts/build.sh
```

## Usage

```bash
~/.codex/skills/wechat-macos-send/scripts/run.sh send 'RECIPIENT' 'MESSAGE'
~/.codex/skills/wechat-macos-send/scripts/run.sh send-image 'RECIPIENT' '/absolute/path/photo.png'
~/.codex/skills/wechat-macos-send/scripts/run.sh send-file 'RECIPIENT' '/absolute/path/report.pdf'
```

Attachment modes require an inline composer that exposes an Accessibility text area
and supports copying the attachment back as image data, a file URL, or RTFD. Clients
that show a separate confirmation dialog or do not expose the rich draft are not
supported by this implementation; the helper stops without clicking Send. These
paths need live validation against the target WeChat version before routine use.

`SENT` confirms local draft clearing and the conversation title, not delivery to the recipient.

Run the macOS build and isolated clipboard tests without logging into WeChat:

```bash
zsh scripts/test.sh
```

For the full skill instructions, safety rules, setup, and troubleshooting, see [SKILL.md](SKILL.md).
