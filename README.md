# skills

Personal agent skills for Claude Code.

## Install

Link each skill into the Claude Code skills folder:

```bash
for s in send-to-tablet md-to-pdf; do ln -s ~/Developer/skills/$s ~/.claude/skills/$s; done
```

## `send-to-tablet`

The skill renders a markdown file to a PDF for an e-ink tablet and uploads it to the reMarkable cloud. The default profile fits the reMarkable Paper Pro screen. It has 18 mm side margins so the toolbar does not cover text, and it shows links as blue underlined text. The skill also uploads a ready PDF as is.

Claude sends a file when you ask. Claude asks first when you mention that you will read something later, or when it finishes a long document for you.

**Requirements:**

- `rmapi`, paired with the tablet: `go install github.com/ddvk/rmapi@latest`, then run `rmapi` once.
- `pandoc`, `npx`, and Google Chrome, for markdown input.

**Settings:** `TABLET_FOLDER` sets the default folder on the tablet (`/Claude`). `TABLET_PROFILE` sets the page profile (`remarkable-paper-pro`). To add a device, add a CSS file in `send-to-tablet/profiles/`.

## `md-to-pdf`

The skill turns one or more markdown files into a print-quality PDF with pandoc and LuaLaTeX. Book mode makes one chapter per file, with a title page and a contents page. Single mode formats one document. Mermaid blocks become vector diagrams. The page fits the reMarkable Paper Pro screen. To put the PDF on the tablet, send it with `send-to-tablet`.

**Requirements:** `pandoc`, `lualatex` and `latexmk` (MacTeX), `npx`, and Google Chrome.
