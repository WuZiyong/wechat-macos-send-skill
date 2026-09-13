# Image and file messages

Use one local command per explicitly authorized recipient and attachment:

```bash
scripts/run.sh send-image 'RECIPIENT' '/absolute/path/photo.png'
scripts/run.sh send-file 'RECIPIENT' '/absolute/path/report.pdf'
```

`send-image` decodes a single-frame image with ImageIO and puts an `NSImage` on the
pasteboard. It verifies decoded pixels rather than comparing TIFF/PNG encodings.
Image metadata and original encoding are not preserved. Images over 40 million
pixels or with either dimension over 16,384 are rejected as a local resource bound.
Animated/multi-frame images must use `send-file` to preserve their original bytes.

`send-file` accepts one readable regular file (including zero-byte files), snapshots
it locally, and pastes its file URL. Paths with spaces or Chinese characters work
when quoted. Directories and missing/unreadable paths are rejected before activating
WeChat. The helper does not compress, download, or split files, and WeChat may impose
its own size/type restrictions. File mode verifies a file draft; if WeChat converts
an image file to an image draft, it stops rather than silently changing message type.

## Local verification

The existing contact search and title OCR are retained. For attachments the helper
also requires the focused Accessibility element to be a text area in the main
WeChat window, with no sheet. It refuses to overwrite a copied text or rich draft.
After paste, it copies the composer back and requires exactly one matching item:

- Images: equal dimensions and SHA-256 of normalized sRGB RGBA pixels.
- Files: matching filename and SHA-256 of bytes, not just the displayed name.
- RTFD: exactly one attachment with no caption, with the same content checks.

It rechecks the title and draft immediately before clicking Send once, then checks
that the composer cleared and the title still matches. These checks do not verify
server delivery, read receipts, or file upload completion. The empty-composer check
still relies on a copy operation leaving its clipboard sentinel unchanged.

Only inline, copyable rich composers are supported. Separate confirmation windows,
inaccessible input controls, and non-copyable attachment cards fail closed. No
confirmation-button guessing or OCR-only filename fallback is attempted. A client
that submits on paste may already have sent the attachment before verification
fails, so do not retry any uncertain attempt. Live validation on the target macOS
and WeChat version is required; isolated tests cannot prove client compatibility.

## Deduplication and local files

The existing 120-second recent-operation record is reused. Attachment keys include
recipient, message kind, basename, and content hash, so changed bytes at the same
path are not mistaken for the previous message. A single helper process may operate
at a time. The recent record still holds only the last operation, not a send history.

An attachment send writes `pending` before pasting and changes it to `sent` only
after local post-send verification. A state-write error stops the operation. The
process restores materialized clipboard representations on normal and handled-error
exits (including an originally empty clipboard); forced termination cannot restore it.

File snapshots live in `~/Library/Caches/wechat-macos-send/attachments/<UUID>/` with
private directory/file permissions. They are retained for asynchronous reads by
WeChat; a later attachment operation removes snapshots older than seven days.
This is local retention, not immediate deletion or encrypted storage. Images are
held in memory. Source files are never modified by the helper.

## Offline checks and live acceptance

When the user requests diagnostics, these checks do not open WeChat or change the clipboard:

```bash
scripts/run.sh validate-image '/absolute/path/photo.png'
scripts/run.sh validate-file '/absolute/path/report.pdf'
```

There is deliberately no attachment `dryrun`: on some client layouts, pasting may
itself submit an attachment. The existing text `dryrun` remains available.

Before routine use, test on a Mac with explicit authorization for each actual send.
Record the macOS/WeChat versions and check a PNG, JPEG, and a file with spaces/Chinese
characters in its name. Verify the received payload manually, that existing text and
attachment drafts are preserved, and that repeating the same request within 120
seconds does not duplicate it. Also test focus changes, unsupported confirmation
dialogs, and a disconnected client; errors must not trigger automatic retries.
