#!/usr/bin/env bash
# changelog.sh — extract per-module changelog entries from the port kit
# Usage: bash .claude/skills/three-term-port/scripts/changelog.sh [module]
#   No argument: all modules.  Argument: single module (01, P2, P12, etc.)
set -euo pipefail

if [ -d "three-term-port-kit" ]; then
  KIT_DIR="three-term-port-kit"
elif [ -d "docs/three-term-port-kit" ]; then
  KIT_DIR="docs/three-term-port-kit"
else
  echo "ERROR: three-term-port-kit not found at repo root or under docs/. Run from the project root." >&2
  exit 1
fi

# Ordered list of module files (core then P-modules)
ALL_FILES=(
  "01-term-grading-migration.md"
  "02-sy-term-grading-toggle.md"
  "03-term-grading-config.md"
  "04-grade-equivalency.md"
  "05-term-resolution-helpers.md"
  "P2-subject-plot-term.md"
  "07-teacher-ecr-term.md"
  "09-final-grading-mastersheets.md"
  "10-report-cards-sf9.md"
  "11-sf10-permanent-record.md"
  "P1-principal-section-info.md"
  "P3-shs-cluster-plotting-term.md"
  "P4-shs-subject-picking.md"
  "P5-shs-bulk-subject-picking.md"
  "P6-teacher-home-schedule.md"
  "P7-class-schedule-term.md"
  "P8-teacher-final-grades.md"
  "P9-system-grading-term.md"
  "P10-teacher-grade-summary.md"
  "P11-teacher-pending-grades.md"
  "P12-grade-status-term.md"
)

# If a module argument is given, filter to just that file
filter_module() {
  local arg="$1"
  local norm
  norm=$(echo "$arg" | sed 's/^0*//' | sed 's/^p/P/')

  for f in "${ALL_FILES[@]}"; do
    local base="${f%.md}"
    local file_id="${base%%-*}"
    local file_norm
    file_norm=$(echo "$file_id" | sed 's/^0*//' | sed 's/^p/P/')
    if [[ "$file_norm" == "$norm" ]]; then
      echo "$f"
      return 0
    fi
  done
  echo "ERROR: No module matches '$arg'. Valid: 01-05, 07, 09-11, P1-P12" >&2
  return 1
}

FILES_TO_PROCESS=()
if [ $# -gt 0 ]; then
  match=$(filter_module "$1")
  FILES_TO_PROCESS+=("$match")
else
  FILES_TO_PROCESS=("${ALL_FILES[@]}")
fi

echo "═══════════════════════════════════════════════════════════════"
echo "  3-TERM PORT KIT — CHANGELOG"
echo "═══════════════════════════════════════════════════════════════"
echo ""

total_entries=0
modules_with_entries=0

for file in "${FILES_TO_PROCESS[@]}"; do
  filepath="$KIT_DIR/$file"
  if [ ! -f "$filepath" ]; then
    continue
  fi

  # Extract module title from first H1
  title=$(grep -m1 '^# ' "$filepath" | sed 's/^# //')

  # Extract module ID from filename
  mod_id="${file%%-*}"
  mod_id="${mod_id%.md}"

  # Find the ## Changelog section and extract ### entries from it
  changelog_line=$(grep -n '^## Changelog' "$filepath" 2>/dev/null | head -1 | cut -d: -f1 || true)

  if [ -z "$changelog_line" ]; then
    continue
  fi

  # Extract ### YYYY-MM-DD entries after the Changelog heading
  entries=$(tail -n +"$changelog_line" "$filepath" \
    | grep -n '^### ' 2>/dev/null \
    | sed 's/^[0-9]*://' \
    | sed 's/^### //' \
    || true)

  if [ -z "$entries" ]; then
    continue
  fi

  modules_with_entries=$((modules_with_entries + 1))

  echo "───────────────────────────────────────────────────────────────"
  printf "  %-6s %s\n" "$mod_id" "$title"
  echo "───────────────────────────────────────────────────────────────"
  echo "  File: $file"
  echo ""

  echo "$entries" | while IFS= read -r entry; do
    # Split on " — " to get date and title
    date="${entry%% — *}"
    desc="${entry#* — }"
    if [[ "$date" == "$entry" ]]; then
      # No " — " separator found, just print as-is
      echo "  $entry"
    else
      printf "  %-12s %s\n" "$date" "$desc"
    fi
  done

  entry_count=$(echo "$entries" | wc -l)
  total_entries=$((total_entries + entry_count))

  # Show files touched from the changelog section
  files_touched=$(tail -n +"$changelog_line" "$filepath" \
    | grep -oP '`[a-zA-Z_/]+\.(php|blade\.php|js)`' 2>/dev/null \
    | sort -u | head -10 \
    || true)

  if [ -n "$files_touched" ]; then
    echo ""
    echo "  Files referenced:"
    echo "$files_touched" | while IFS= read -r f; do
      echo "    - $f"
    done
  fi

  echo ""
done

echo "═══════════════════════════════════════════════════════════════"
if [ "$modules_with_entries" -eq 0 ]; then
  echo "  No changelog entries found."
  echo "  Use /kit-changelog <commit-hash> to add entries."
else
  printf "  %d modules, %d changelog entries\n" "$modules_with_entries" "$total_entries"
fi
echo "═══════════════════════════════════════════════════════════════"
