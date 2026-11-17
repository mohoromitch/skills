---
name: md-to-pdf
description: Use when the user asks to turn markdown files into a PDF file, to combine several markdown docs or notes into one PDF or "book", or when a markdown file has Mermaid blocks that must appear as diagrams in a PDF. Also use when the user types /md-to-pdf. For an upload to a tablet or reMarkable, use send-to-tablet instead.
version: 1.0.0
---

# md-to-pdf

## Overview

The skill turns one or more markdown files into a print-quality PDF with pandoc and LuaLaTeX. This is the route swift-book-pdf uses for the Swift book. The bundled `scripts/build.sh` produces a title page, a contents page, PDF bookmarks, and running headers. It wraps code blocks, sizes table columns from their content, links input files to each other, and renders Mermaid diagrams as vector graphics. The page is 180 by 240 mm, the reMarkable Paper Pro screen. Headings use one accent colour, `#006400` by default.

## When to use

- "Combine these docs into a PDF", "make a PDF of this note", "make a book of these notes".
- A markdown file has a Mermaid block that must appear as a diagram in the PDF.

Not for HTML output, slide decks, or Google Docs exports. This skill does not upload. To put the PDF on the tablet, pass it to the `send-to-tablet` skill.

## Workflow

1. **Collect the inputs.** List the `.md` files in the order the reader needs. Numeric prefixes sort correctly with a `[0-9]*.md` glob. Pick the mode:
   - Several files: book mode. The H1 of each file becomes a chapter.
   - One file: `--single`. Its H1 becomes the title.
2. **Choose the metadata.** Book mode needs `--title`. Add `--subtitle`, `--author`, and one `--part BASE=TITLE` per natural group of files. Do not invent groups the files do not have.
3. **Build.**

   ```bash
   SKILL=~/.claude/skills/md-to-pdf/scripts
   "$SKILL/build.sh" --out OUT.pdf --title "..." --part 00-intro="Part one" FILES...
   "$SKILL/build.sh" --single --out OUT.pdf FILE.md
   ```

   The script checks for pandoc, lualatex, latexmk, npx, and Chrome. It stops with an install hint if it cannot find one of them. You install nothing else. Mermaid CLI runs through `npx`.
4. **Verify before you report.** Run the inspector, then open the PNG files with the Read tool:

   ```bash
   uv run --quiet --with pymupdf python "$SKILL/pdfinspect.py" OUT.pdf --render 1 --render 2 --render-find "Architecture" --render-find "Results table"
   ```

   `--render N` renders page N. `--render-find PHRASE` renders the last page that contains the phrase. Repeat the flag once per phrase: one phrase from a diagram label and one from a wide table. The PNG files land in `/tmp/pdf-pages/`.

   Check six things. The page count is plausible. The font list contains HelveticaNeue and SFMono. The build printed `missing-character lines: 0`. Diagram text is legible. Tables fit the page. A heading that introduces a table or a diagram sits on the same page as it. Overfull lines under 20pt inside tables are fine. Larger ones mean a token the filter cannot break.
5. **Report** the output path, the page count, the diagram count, and the overfull and missing-glyph counts. If the build failed, quote the first `!` line from the `.log` file in the build dir. If the user wants the PDF on the tablet, send it with the `send-to-tablet` skill.

## Quick reference

| Need | Flag or file |
|---|---|
| Heading colour | `--accent 006400` |
| Part divider before a chapter | `--part 10-verdicts="Phase 2"` |
| Deeper contents | `--toc-depth 3` |
| Keep intermediates in a known place | `--build-dir DIR` |
| Other page size | `geometry:` in `scripts/metadata-*.yaml` |
| Other fonts | `\setmainfont` and `\setmonofont` in `scripts/preamble.tex` |
| Diagram theme | `scripts/mermaid-config.json` |

## What the filter already does

- The filter renders a wide `flowchart LR` a second time as top-down and keeps the layout with the larger text.
- The filter adds break points to inline code at `_ . / - :`, at CamelCase joins, and every 10 characters of a long hash.
- The filter sizes table columns from their content, with a floor for the longest word that cannot break. Tables with 6 or more columns use a smaller font.
- The filter turns a link to a sibling input file, such as `[x](02-data.md)`, into an internal link.
- The filter strips U+FE0F variation selectors. Symbols the text font lacks fall back to Apple Symbols, Menlo, and Hiragino Sans.

## Common mistakes

- **Plain pandoc instead of the script:** `pandoc --pdf-engine=lualatex` alone leaves csv blocks unwrapped and stretches small diagrams. It also shrinks wide flowcharts to 3pt text and reads lists after paragraphs as prose. Always go through `build.sh`.
- **Unsorted files:** the shell glob order is the chapter order. Check it before you build.
- **Two H1 headings in one file:** only the first becomes the chapter label. Use `--single` for a lone file.
- **Success without a rendered page:** the overfull count does not catch a diagram that shrank to 3pt text. Open the PNG.
- **`title:` in `metadata-*.yaml`:** the build script owns title, subtitle, author, and date through its flags.
