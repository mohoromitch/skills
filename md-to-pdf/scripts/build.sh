#!/usr/bin/env bash
# Build a PDF from markdown files with pandoc + LuaLaTeX (md-to-pdf skill).
#
# Usage:
#   build.sh --out OUT.pdf [options] FILE.md [FILE.md ...]
#
# Modes:
#   default    book: each file becomes a chapter (scrreprt, title page, TOC)
#   --single   one document: the first H1 becomes the title (scrartcl)
#
# Options:
#   --title TEXT        book title (default: output file name, dashes as spaces)
#   --subtitle TEXT     book subtitle
#   --author TEXT       author line
#   --date TEXT         date line (default: today, YYYY-MM-DD)
#   --accent HEX        heading colour, 6 hex digits (default 006400)
#   --part BASE=TITLE   insert a part divider before the chapter from BASE.md
#                       (repeatable; BASE is the file name without .md)
#   --toc-depth N       contents depth (default 2)
#   --build-dir DIR     where .tex/.log/diagram caches go
#                       (default $TMPDIR/md-to-pdf/<output stem>)
set -euo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="" TITLE="" SUBTITLE="" AUTHOR="" DATE="" ACCENT="006400" TOC_DEPTH=2 BUILD_DIR=""
SINGLE=0
PARTS=""
FILES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    --single) SINGLE=1; shift ;;
    --title) TITLE="$2"; shift 2 ;;
    --subtitle) SUBTITLE="$2"; shift 2 ;;
    --author) AUTHOR="$2"; shift 2 ;;
    --date) DATE="$2"; shift 2 ;;
    --accent) ACCENT="${2#\#}"; shift 2 ;;
    --part) PARTS="${PARTS}${2}"$'\n'; shift 2 ;;
    --toc-depth) TOC_DEPTH="$2"; shift 2 ;;
    --build-dir) BUILD_DIR="$2"; shift 2 ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    --*) echo "unknown option: $1" >&2; exit 2 ;;
    *) FILES+=("$1"); shift ;;
  esac
done
[ -n "$OUT" ] || { echo "need --out OUT.pdf" >&2; exit 2; }
[ ${#FILES[@]} -gt 0 ] || { echo "need at least one input .md" >&2; exit 2; }
[[ "$ACCENT" =~ ^[0-9A-Fa-f]{6}$ ]] || { echo "--accent needs 6 hex digits, got '$ACCENT'" >&2; exit 2; }
for f in "${FILES[@]}"; do [ -f "$f" ] || { echo "missing input: $f" >&2; exit 2; }; done

for tool in pandoc lualatex latexmk npx; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool (pandoc: brew install pandoc; lualatex/latexmk: MacTeX or BasicTeX; npx: node)" >&2; exit 2; }
done
CHROME="$(sed -n 's/.*"executablePath": *"\([^"]*\)".*/\1/p' "$SCRIPTS/puppeteer.json")"
[ -x "$CHROME" ] || { echo "Chrome not found at $CHROME; edit $SCRIPTS/puppeteer.json" >&2; exit 2; }

OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
STEM="$(basename "${OUT%.pdf}")"
BUILD="${BUILD_DIR:-${TMPDIR:-/tmp}/md-to-pdf/$STEM}"
mkdir -p "$BUILD"
[ -n "$DATE" ] || DATE="$(date +%Y-%m-%d)"
[ -n "$TITLE" ] || TITLE="$(printf '%s' "$STEM" | tr '_-' '  ')"

yaml_str() { printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"; }
{
  if [ "$SINGLE" = "0" ]; then
    printf 'title: %s\n' "$(yaml_str "$TITLE")"
    [ -n "$SUBTITLE" ] && printf 'subtitle: %s\n' "$(yaml_str "$SUBTITLE")"
    printf 'date: %s\n' "$(yaml_str "$DATE")"
  fi
  [ -n "$AUTHOR" ] && printf 'author: %s\n' "$(yaml_str "$AUTHOR")"
  true
} > "$BUILD/meta.yaml"
printf '\\definecolor{accent}{HTML}{%s}\n' "$ACCENT" > "$BUILD/accent.tex"

export MDPDF_BUILD="$BUILD"
export MDPDF_SCRIPTS="$SCRIPTS"
export MDPDF_SINGLE="$SINGLE"
export MDPDF_PARTS="$PARTS"

PANDOC_ARGS=(
  -f gfm+smart
  -t latex -s
  --lua-filter="$SCRIPTS/filter.lua"
  --include-in-header="$BUILD/accent.tex"
  --include-in-header="$SCRIPTS/preamble.tex"
  --syntax-highlighting=monochrome
  --toc --toc-depth="$TOC_DEPTH"
  --metadata-file="$BUILD/meta.yaml"
)
if [ "$SINGLE" = "1" ]; then
  PANDOC_ARGS+=(--top-level-division=section --metadata-file="$SCRIPTS/metadata-single.yaml")
else
  PANDOC_ARGS+=(--top-level-division=chapter --metadata-file="$SCRIPTS/metadata-book.yaml")
fi

pandoc "${PANDOC_ARGS[@]}" "${FILES[@]}" -o "$BUILD/$STEM.tex"

(
  cd "$BUILD"
  latexmk -lualatex -interaction=nonstopmode -halt-on-error -file-line-error \
    -silent "$STEM.tex" > "$STEM.latexmk.log" 2>&1 || {
      echo "lualatex failed; see $BUILD/$STEM.log" >&2
      grep -nE '^!|^l\.[0-9]+|Error' "$STEM.log" | head -30 >&2
      exit 1
    }
)
cp "$BUILD/$STEM.pdf" "$OUT"
echo "wrote $OUT"
echo "build dir: $BUILD"
echo "missing-character lines: $(grep -c 'Missing character' "$BUILD/$STEM.log" || true)"
echo "overfull hbox lines: $(grep -c 'Overfull \\hbox' "$BUILD/$STEM.log" || true)"
echo "mermaid diagrams: $(grep -o 'mermaid-[0-9a-f]*\.pdf' "$BUILD/$STEM.tex" | sort -u | wc -l | tr -d ' ')"
