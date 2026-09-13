# WeChat macOS Send Skill

A fast, locally verified skill for sending a single WeChat message from macOS.

- One `send` call for normal use
- Local contact and draft verification
- No screenshot round-trips during normal sending
- Prevents uncertain automatic retries

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
```

For the full skill instructions, safety rules, setup, and troubleshooting, see [SKILL.md](SKILL.md).
