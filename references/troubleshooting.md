# Advanced / Troubleshooting

These commands are diagnostic tools, not part of normal message sending. Do not run them before or after a routine `send` unless troubleshooting is actually requested or needed.

## Diagnostic commands

Environment/window check:

```bash
scripts/run.sh doctor
```

Select and locally OCR-verify a contact without drafting or sending:

```bash
scripts/run.sh check 'Example Contact'
```

Exercise contact verification plus exact draft verification, then clear the draft without sending:

```bash
scripts/run.sh dryrun 'Example Contact' 'test message'
```

Use `dryrun` only when validating a new Mac/WeChat layout or diagnosing draft verification. A successful dry-run ends with `DRYRUN_OK`.

## Known failures

`ACCESSIBILITY_DENIED`: grant Accessibility permission to the actual execution host, then restart that host process.

`CAPTURE_FAILED` / `IMAGE_LOAD_FAILED`: grant Screen Recording (or Screen & System Audio Recording) permission and confirm a normal WeChat main window is open.

`CONTACT_VERIFY_FAILED`: the skill searched but local Vision OCR could not safely match the requested chat header. Do not guess. In troubleshooting mode, re-run with `WECHAT_KEEP_DEBUG=1` and inspect the local temporary captures, or use `check` after bringing WeChat into a normal visible state.

The OCR matcher is exact after case/width folding and whitespace removal. For ASCII-only names of at least three characters it tolerates only one extra trailing OCR character (for cases such as `A.B.C` being read as `A.B.CR`). Chinese names and all other cases remain exact. It does not use broad fuzzy matching.

`composer_not_empty`: a compose box already contains a copied text or rich draft. The skill refuses to overwrite it. Resolve the draft manually or ask the user what to do.

`DRAFT_VERIFY_FAILED` / `PRE_SEND_DRAFT_MISMATCH`: the exact clipboard-pasted message could not be read back identically. Stop without sending.

`SEND_UNVERIFIED_DRAFT_REMAINS`: Send was clicked once but the compose box did not become empty in time. Do not click again automatically.

`RECENT_SEND_UNCERTAIN_DO_NOT_RETRY`: a matching send entered the local `pending` state recently but did not reach verified `sent`. This is intentionally sticky for a short window; inspect WeChat before any retry.

`already_sent_recently`: a matching recipient/message was already verified as sent recently. Treat this as a successful idempotent result. Only use `WECHAT_ALLOW_REPEAT=1` for an explicitly requested intentional duplicate.

## Attachment errors

Read [attachment behavior](attachments.md) for offline `validate-image` and
`validate-file` commands and live acceptance requirements.

- `attachment_not_readable_regular_file`: resolve the intended local file; directories are not supported.
- `attachment_not_decodable_image` / `animated_image_use_send_file`: image mode requires a supported single-frame image. Do not silently change to file mode without confirming the user's intended representation.
- `attachment_staging_failed` / `attachment_clipboard_write_failed`: local preparation failed; no Send click is attempted.
- `attachment_focus_lost` / `attachment_composer_unverifiable` / `attachment_window_changed`: focus, layout, a sheet, or an inaccessible composer prevented verification. Do not click through a dialog.
- `attachment_draft_verify_failed` / `attachment_pre_send_mismatch`: the copied rich draft did not match the authorized attachment. A draft may remain; stop and inspect manually.
- `send_unconfirmed_attachment_remains`: Send was clicked once but the draft did not clear. Never click again automatically.
- `another_operation_in_progress`: another helper invocation holds the UI-operation lock.
- `recent_state_write_failed`: the helper could not persist the operation state. If this occurred after paste or Send, treat the result as uncertain.

For attachments, `pending` is stored before paste. Even a pre-Send error after that
point must not be treated as permission to retry: a client may submit on paste.
