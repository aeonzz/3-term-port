#!/usr/bin/env bash
#
# Copy the 3-term port kit (docs + skill) into a Laragon project.
#
# Copies:
#   three-term-port-kit/            -> <project>/docs/three-term-port-kit/
#   .claude/skills/three-term-port/ -> <project>/.claude/skills/three-term-port/
#
# Prompts before overwriting any file that already exists in the target.
#
# Usage:
#   ./deploy-kit.sh <laragon-project-name>       e.g. ./deploy-kit.sh es_apmc
#   ./deploy-kit.sh --dest <full-path>           non-Laragon target
#   ./deploy-kit.sh --www  <path> <project>      custom www root
#   ./deploy-kit.sh --force <project>            overwrite without prompting
#   ./deploy-kit.sh --skip-existing <project>    keep target copies
#   ./deploy-kit.sh                              list available Laragon projects

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WWW="C:/laragon/www"
DEST=""
PROJECT=""
FORCE=0
SKIP_EXISTING=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dest)          DEST="$2"; shift 2 ;;
    --www)           WWW="$2"; shift 2 ;;
    --force)         FORCE=1; shift ;;
    --skip-existing) SKIP_EXISTING=1; shift ;;
    -h|--help)       sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)              echo "unknown option: $1" >&2; exit 1 ;;
    *)               PROJECT="$1"; shift ;;
  esac
done

# --- resolve destination ---------------------------------------------------
if [ -z "$DEST" ]; then
  if [ -z "$PROJECT" ]; then
    echo "Usage: ./deploy-kit.sh <project-name>   (folder under $WWW)"
    echo "   or: ./deploy-kit.sh --dest <full-path-to-project-root>"
    if [ -d "$WWW" ]; then
      echo
      echo "Projects in $WWW:"
      for d in "$WWW"/*/; do [ -d "$d" ] && echo "  $(basename "$d")"; done
    fi
    exit 1
  fi
  DEST="$WWW/$PROJECT"
fi

if [ ! -d "$DEST" ]; then
  echo "Target project not found: $DEST" >&2
  exit 1
fi

echo "Source: $SRC"
echo "Target: $DEST"
echo

# --- pairs: "<from>|<to-relative-to-DEST>" -------------------------------
PAIRS=(
  "$SRC/three-term-port-kit|docs/three-term-port-kit"
  "$SRC/.claude/skills/three-term-port|.claude/skills/three-term-port"
)

added=0; overwrote=0; skipped=0

for pair in "${PAIRS[@]}"; do
  from="${pair%%|*}"
  to="$DEST/${pair##*|}"

  if [ ! -d "$from" ]; then
    echo "  (missing in source, skipping: $from)"
    continue
  fi

  echo "=> $to"

  while IFS= read -r -d '' file; do
    rel="${file#"$from"/}"
    target="$to/$rel"

    if [ -f "$target" ]; then
      if cmp -s "$file" "$target"; then
        skipped=$((skipped + 1)); continue
      fi
      if [ "$SKIP_EXISTING" -eq 1 ]; then
        echo "  skip (exists) $rel"; skipped=$((skipped + 1)); continue
      fi
      if [ "$FORCE" -eq 0 ]; then
        printf "  overwrite '%s'? [y/N/a=all] " "$rel"
        read -r ans </dev/tty || ans=""
        case "$ans" in
          a|A) FORCE=1 ;;
          y|Y) ;;
          *)   echo "  skipped $rel"; skipped=$((skipped + 1)); continue ;;
        esac
      fi
      mkdir -p "$(dirname "$target")"
      cp -f "$file" "$target"
      echo "  overwrote $rel"
      overwrote=$((overwrote + 1))
    else
      mkdir -p "$(dirname "$target")"
      cp -f "$file" "$target"
      echo "  added     $rel"
      added=$((added + 1))
    fi
  done < <(find "$from" -type f -print0)
done

echo
echo "Done. added=$added  overwrote=$overwrote  skipped(unchanged/kept)=$skipped"
echo "Next: cd \"$DEST\" and run  /three-term-port"
