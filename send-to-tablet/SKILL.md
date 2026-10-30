---
name: send-to-tablet
description: Use when the user asks to send, put, upload, or push a document, note, or PDF to their tablet or reMarkable, says they will read something later or away from the screen (on the train, on the couch, offline), or right after you finish a long-form markdown document for the user to read, such as an exploration doc, research write-up, ADR, runbook, or long note.
---

# send-to-tablet

## Overview

`scripts/send-to-tablet.sh` renders a markdown file to a PDF sized for the tablet screen, then uploads it to the reMarkable cloud with `rmapi`. The page has 18 mm side margins, so the tablet toolbar does not cover text, and links show as blue underlined text. A `.pdf` input uploads as is.

Always upload through this script. A hand-made `pandoc` or `rmapi put` call skips the margins, the Mermaid rendering, and the document name.

## When to send, offer, or skip

| Situation | Action |
|---|---|
| The user asks you to send a file to the tablet | Send it now. Do not ask again. |
| The user says they will read a file later or away from the screen | Ask: "Send `<file>` to your tablet?" Send after a yes. |
| You finish a long-form markdown doc for the user to read (about 800 words or more) | End your report with: "Send this to your tablet?" Send after a yes. |
| Chat replies, code changes, short files, or a doc the user already declined | Do not offer. |

You must make the offer after a long doc. It is not optional. Ask one time per doc. An upload without a yes publishes the file to the reMarkable cloud, so never send on a guess.

## Send

```bash
SCRIPT=~/.claude/skills/send-to-tablet/scripts/send-to-tablet.sh
"$SCRIPT" --folder "/Explore Docs" path/to/doc.md
```

- **Folder:** use `/Explore Docs` for exploration docs. Use `/Claude` (the default) for all other docs, unless the user names a folder.
- **PDF input:** pass the `.pdf` path. For a multi-file book or a LaTeX-quality single doc, build it first with the `md-to-pdf` skill, then send the PDF.
- **Check first:** add `--dry-run --out /tmp/tablet` to render without an upload, then open a page if the user asks how it looks.

The script names the tablet document after the first H1, plus the date from a `YYYY-MM-DD-` file name prefix. Report that name and the folder to the user.

## Add a device

Copy `profiles/remarkable-paper-pro.css` to `profiles/<device>.css`. Set the `@page` size to the screen size in millimetres, and set the side margins wider than the toolbar. Then use `--profile <device>` or `export TABLET_PROFILE=<device>`.

Check the margins on a dry-run PDF:

```bash
swift scripts/check-margins.swift OUT.pdf 130 1620 2160 229
```

The arguments are the minimum clear width in pixels, then the screen width, height, and pixel density. The script exits 1 if a page puts ink closer to the edge than the minimum.

## Common mistakes

- **Upload without a yes:** an offer is a question. Wait for the answer.
- **The `md-to-pdf` skill for an upload:** that skill builds PDFs but does not upload them. Send its output with this script.
- **No `--folder` for an exploration doc:** the doc lands in `/Claude` instead of next to the other exploration docs.
- **`rmapi cannot reach the reMarkable cloud`:** the tablet is not paired. Tell the user to run `! rmapi` once and enter the one-time code from my.remarkable.com.
