#!/usr/bin/env bash
# Render a markdown doc to a PDF sized for an e-ink tablet, or take a ready PDF,
# and upload it to the reMarkable cloud with rmapi.
#
# Usage:
#   send-to-tablet.sh [options] <doc.md|doc.pdf>
#
# Options:
#   --folder PATH    destination folder on the tablet (default: $TABLET_FOLDER or /Claude)
#   --profile NAME   page profile, profiles/NAME.css (default: $TABLET_PROFILE or
#                    remarkable-paper-pro); ignored for PDF input
#   --dry-run        render only; do not upload
#   --out DIR        with --dry-run, where to keep the PDF (default: .)
#
# Environment:
#   CHROME_BIN       Chrome binary used for Mermaid rendering and PDF printing
set -euo pipefail

usage() { sed -n '5,16p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

folder="${TABLET_FOLDER:-/Claude}"
profile="${TABLET_PROFILE:-remarkable-paper-pro}"
dry_run=0
out_dir="."
src=""
while (( $# )); do
  case "$1" in
    --folder) folder="${2:?--folder needs a path}"; shift 2 ;;
    --profile) profile="${2:?--profile needs a name}"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    --out) out_dir="${2:?--out needs a directory}"; shift 2 ;;
    -h|--help) usage ;;
    -*) echo "unknown option: $1" >&2; usage ;;
    *) [[ -z "$src" ]] || usage; src="$1"; shift ;;
  esac
done
[[ -n "$src" ]] || usage
[[ -f "$src" ]] || { echo "not a file: $src" >&2; exit 2; }
case "$src" in
  *.md) kind=md ;;
  *.pdf) kind=pdf ;;
  *) echo "expected a .md or .pdf file: $src" >&2; exit 2 ;;
esac

here="$(cd "$(dirname "$0")/.." && pwd)"
chrome="${CHROME_BIN:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"

deps=()
(( dry_run )) || deps+=(rmapi)
if [[ $kind == md ]]; then
  deps+=(pandoc npx)
  css="$here/profiles/$profile.css"
  [[ -f "$css" ]] || { echo "no profile \"$profile\"; available: $(ls "$here/profiles" | sed 's/\.css$//' | tr '\n' ' ')" >&2; exit 2; }
  [[ -x "$chrome" ]] || { echo "Chrome not found at $chrome (set CHROME_BIN)" >&2; exit 2; }
fi
for bin in ${deps[@]+"${deps[@]}"}; do
  command -v "$bin" >/dev/null || { echo "missing dependency: $bin" >&2; exit 2; }
done
if (( ! dry_run )); then
  rmapi ls / >/dev/null 2>&1 || { echo "rmapi cannot reach the reMarkable cloud; run rmapi once to pair the tablet" >&2; exit 2; }
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Name the tablet document after the H1 plus the filename date, e.g.
# "Release Plan (2026-04-16)". Slashes and colons are not safe in names.
title=""
[[ $kind == md ]] && title="$(grep -m1 '^# ' "$src" | sed 's/^# //; s#[/:]#-#g' || true)"
date="$(basename "$src" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)"
name="${title:-$(basename "$src" ".$kind")}"
# Some docs use the dated filename slug as the H1; do not repeat the date.
[[ -n "$date" && "$name" != "$date"* ]] && name="$name ($date)"
pdf="$work/$name.pdf"

if [[ $kind == pdf ]]; then
  cp "$src" "$pdf"
else
  # 1. Render Mermaid blocks to PNG. mmdc rewrites the Markdown to point at the images.
  #    Reuse the local Chrome so puppeteer does not download its own browser.
  #    Left-to-right flowcharts shrink to an unreadable strip on a portrait page, so the
  #    PDF copy draws them top-down. The source note is not changed.
  sed -E 's/^([[:space:]]*(flowchart|graph))[[:space:]]+(LR|RL)/\1 TD/' "$src" > "$work/src.md"
  cp "$work/src.md" "$work/doc.md"
  if grep -q '^```mermaid' "$work/src.md"; then
    printf '{"executablePath": "%s"}\n' "$chrome" > "$work/puppeteer.json"
    PUPPETEER_SKIP_DOWNLOAD=1 npx --loglevel=error -y -p @mermaid-js/mermaid-cli mmdc -q \
      -p "$work/puppeteer.json" -i "$work/src.md" -o "$work/doc.md" -e png -s 2 -b white
  fi

  # 2. Markdown to self-contained HTML with the profile stylesheet. Local images
  #    in the source resolve against the source file's folder.
  pandoc "$work/doc.md" -f gfm -t html5 -s --embed-resources \
    --resource-path="$work:$(cd "$(dirname "$src")" && pwd)" \
    --metadata pagetitle="${title:-$name}" -c "$css" -o "$work/doc.html"

  # 3. HTML to PDF. The page size comes from the @page rule in the profile.
  "$chrome" --headless=new --disable-gpu --no-pdf-header-footer \
    --print-to-pdf="$pdf" "file://$work/doc.html" 2>/dev/null
  [[ -s "$pdf" ]] || { echo "PDF render failed" >&2; exit 1; }
fi

if (( dry_run )); then
  mkdir -p "$out_dir"
  cp "$pdf" "$out_dir/"
  echo "Rendered: $out_dir/$name.pdf"
  exit 0
fi

# 4. Upload. mkdir fails when the folder already exists, which is fine.
rmapi mkdir "$folder" >/dev/null 2>&1 || true
rmapi put "$pdf" "$folder"
echo "Sent \"$name\" to the tablet folder $folder"
