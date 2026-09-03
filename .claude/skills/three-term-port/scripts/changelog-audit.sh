#!/usr/bin/env bash
# changelog-audit.sh — per-changelog-entry implementation check against the repo.
#
# audit.sh checks whether a MODULE looks implemented (a handful of hand-picked
# class/function signatures). This script is finer-grained: for every
# changelog entry (### YYYY-MM-DD — Title) in every module's ## Changelog
# section, it pulls the inline-code identifiers (`LikeThis`) mentioned in that
# entry's own text and greps the target repo for each one. It reports how many
# of an entry's identifiers were found, so entries with 0 hits are flagged as
# likely not applied here.
#
# This is a HEURISTIC, not a verdict. It matches literal identifier strings,
# so it cannot see logic differences (an identifier can exist while the
# behavior it names is wrong, incomplete, or was later changed — see the
# "Live-calculating summary sheet" saga in this skill's own history for a
# worked example). Read the actual diff for anything not "all found" before
# trusting it. Common/short identifiers can also false-positive as "found".
#
# Usage (from the target repo root):
#   bash .claude/skills/three-term-port/scripts/changelog-audit.sh           # all modules
#   bash .claude/skills/three-term-port/scripts/changelog-audit.sh P9        # one module
set -uo pipefail

if [ -d "three-term-port-kit" ]; then
  KIT_DIR="three-term-port-kit"
elif [ -d "docs/three-term-port-kit" ]; then
  KIT_DIR="docs/three-term-port-kit"
else
  echo "ERROR: three-term-port-kit not found at repo root or under docs/. Run from the project root." >&2
  exit 1
fi

# Search scope: real source, never the kit's own docs (that would just find
# the changelog prose matching itself).
SEARCH_DIRS=()
for d in app resources routes database; do
  [ -d "$d" ] && SEARCH_DIRS+=("$d")
done
if [ "${#SEARCH_DIRS[@]}" -eq 0 ]; then
  echo "ERROR: none of app/, resources/, routes/, database/ found. Run from the target repo root." >&2
  exit 1
fi

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
  match=$(filter_module "$1") || exit 1
  FILES_TO_PROCESS+=("$match")
else
  FILES_TO_PROCESS=("${ALL_FILES[@]}")
fi

# repo_has IDENTIFIER -> 0 (found) / 1 (not found)
# -q alone (no pipe to a second grep) so pipefail can't turn an early-exit
# reader's SIGPIPE to the writer into a false "not found".
repo_has() {
  grep -rqF -- "$1" "${SEARCH_DIRS[@]}" --include='*.php' --include='*.js' --include='*.blade.php' \
    2>/dev/null
}

echo "═══════════════════════════════════════════════════════════════"
echo "  3-TERM PORT KIT — CHANGELOG AUDIT"
echo "  (heuristic: identifier presence, not behavior — verify anything"
echo "   below \"all found\" against the real commit before trusting it)"
echo "═══════════════════════════════════════════════════════════════"
echo ""

total_entries=0
missing_entries=0
partial_entries=0

for file in "${FILES_TO_PROCESS[@]}"; do
  filepath="$KIT_DIR/$file"
  [ -f "$filepath" ] || continue

  changelog_line=$(grep -n '^## Changelog' "$filepath" 2>/dev/null | head -1 | cut -d: -f1 || true)
  [ -z "$changelog_line" ] && continue

  mod_id="${file%%-*}"
  title=$(grep -m1 '^# ' "$filepath" | sed 's/^# //')

  # Line numbers of every "### YYYY-MM-DD — ..." heading from the Changelog section on
  mapfile -t entry_lines < <(tail -n +"$changelog_line" "$filepath" | grep -n '^### ' | cut -d: -f1)
  [ "${#entry_lines[@]}" -eq 0 ] && continue

  total_lines=$(wc -l < "$filepath")
  printed_header=0

  for idx in "${!entry_lines[@]}"; do
    start_rel="${entry_lines[$idx]}"
    start_abs=$((changelog_line + start_rel - 1))
    if [ $((idx + 1)) -lt "${#entry_lines[@]}" ]; then
      next_rel="${entry_lines[$((idx + 1))]}"
      end_abs=$((changelog_line + next_rel - 2))
    else
      end_abs=$total_lines
    fi

    entry_title=$(sed -n "${start_abs}p" "$filepath" | sed 's/^### //')
    block=$(sed -n "${start_abs},${end_abs}p" "$filepath")

    # Inline-code identifiers mentioned in this entry: no spaces, no slashes-as-paths
    # to kit docs, reasonable length. Files-touched paths (foo/Bar.php) are kept too
    # since a missing file is itself a strong "not applied" signal.
    mapfile -t idents < <(echo "$block" \
      | grep -oE '`[^` ]{3,80}`' \
      | sed -e 's/^`//' -e 's/`$//' \
      | sed -e 's/([^)]*)$//' \
      | grep -vE '^\s*$' \
      | sort -u \
      | grep -vE '\.md$')

    if [ "${#idents[@]}" -eq 0 ]; then
      continue
    fi

    found=0
    missing_list=()
    for ident in "${idents[@]}"; do
      if repo_has "$ident"; then
        found=$((found + 1))
      else
        missing_list+=("$ident")
      fi
    done
    total=${#idents[@]}

    if [ "$printed_header" -eq 0 ]; then
      echo "───────────────────────────────────────────────────────────────"
      printf "  %-6s %s\n" "$mod_id" "$title"
      echo "───────────────────────────────────────────────────────────────"
      printed_header=1
    fi

    total_entries=$((total_entries + 1))
    if [ "$found" -eq "$total" ]; then
      status="✅ all found ($found/$total)"
    elif [ "$found" -eq 0 ]; then
      status="❌ none found (0/$total) — likely NOT applied here"
      missing_entries=$((missing_entries + 1))
    else
      status="⚠️  partial ($found/$total) — verify against the commit"
      partial_entries=$((partial_entries + 1))
    fi

    printf "  %-14s %s\n" "$(echo "$entry_title" | cut -d' ' -f1)" "$(echo "$entry_title" | cut -d' ' -f3-)"
    echo "                 $status"
    if [ "${#missing_list[@]}" -gt 0 ] && [ "$found" -ne "$total" ]; then
      for m in "${missing_list[@]}"; do
        echo "                 missing: $m"
      done
    fi
    echo ""
  done
done

echo "═══════════════════════════════════════════════════════════════"
printf "  %d entries checked — %d fully missing, %d partial, %d fully found\n" \
  "$total_entries" "$missing_entries" "$partial_entries" \
  "$((total_entries - missing_entries - partial_entries))"
echo "  Heuristic only — confirm any non-\"all found\" entry against the"
echo "  actual es_ldcu commit diff before implementing or reporting on it."
echo "═══════════════════════════════════════════════════════════════"
