# WeChat macOS Send Skill

A fast, locally verified skill for sending a single WeChat message from macOS.

- One `send` call for normal use
- Local contact and draft verification
- No screenshot round-trips during normal sending
- Prevents uncertain automatic retries

## Install the local helper

```bash
git clone https://github.com/WuZiyong/wechat-macos-send-skill.git \
  ~/.codex/skills/wechat-macos-send
```

Build once:

```bash
~/.codex/skills/wechat-macos-send/scripts/build.sh
```

## ChatGPT / Codex plugin

This repository also contains a portable Agent Plugin manifest and a repo marketplace entry.

Requirements:
- Remote Desktop Commander installed and connected to the authorized Mac.
- The local helper above installed on that Mac.

Add this GitHub repository as a plugin marketplace:

```bash
codex plugin marketplace add WuZiyong/wechat-macos-send-skill --ref main
```

Restart the ChatGPT desktop app, open the Plugins Directory, choose **WuZiyong WeChat Tools**, and install **WeChat macOS Send**.

> Local/repo marketplaces are for supported local clients such as the ChatGPT desktop app and Codex. Web ChatGPT requires a published plugin or a Developer-mode MCP connection.

## Direct usage

```bash
~/.codex/skills/wechat-macos-send/scripts/run.sh send 'RECIPIENT' 'MESSAGE'
```

For the full local skill instructions, safety rules, setup, and troubleshooting, see [SKILL.md](SKILL.md).
