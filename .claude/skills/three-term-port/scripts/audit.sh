#!/usr/bin/env bash
# 3-term port — read-only repo audit.
#
# Reports which kit modules appear implemented (by code presence) and flags
# ibed_term_config reads that are NOT guarded by activeConfigQuery /
# whereConfigActive (invariant #1). This NEVER edits anything.
#
# Usage (from the target repo root):
#   bash .claude/skills/three-term-port/scripts/audit.sh                  # all modules
#   bash .claude/skills/three-term-port/scripts/audit.sh /path/to/repo    # all modules, another repo
#   bash .claude/skills/three-term-port/scripts/audit.sh 07               # one module: implemented? + needs update?
#   bash .claude/skills/three-term-port/scripts/audit.sh 07 /path/to/repo # one module, another repo
#
# A module argument (01-11, P1-P12, with or without a leading zero, P
# case-insensitive) narrows the "Modules:" section to that module's own
# detectors AND appends a "Needs update?" section that shells out to
# changelog-audit.sh for that module — so one command answers both "is this
# module here at all" and "is it missing a later fix/feature on top of the
# base port". See changelog-audit.sh for that section's own heuristic caveats
# (identifier presence, not behavior).
#
# Note: this checks CODE only. The schema (Module 01) lives in the database and
# must be verified separately (e.g. via the migration page's "Check Status").

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

norm_module() { # normalize "7" / "07" / "p2" / "P2" -> "7" / "P2"
  echo "$1" | sed 's/^0*//' | sed 's/^[pP]/P/'
}

is_module_arg() {
  [[ "$1" =~ ^[0-9]{1,2}$ ]] || [[ "$1" =~ ^[pP][0-9]{1,2}$ ]]
}

MODULE=""
MODULE_DISPLAY=""
if [ $# -gt 0 ] && is_module_arg "$1"; then
  MODULE="$(norm_module "$1")"
  # zero-pad numeric modules back to the kit's own "07" style; P-modules (P2,
  # P12) already display fine unpadded.
  if [[ "$MODULE" =~ ^[0-9]+$ ]]; then
    MODULE_DISPLAY=$(printf '%02d' "$MODULE")
  else
    MODULE_DISPLAY="$MODULE"
  fi
  shift
fi
ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { echo "cannot cd to $ROOT"; exit 1; }

say() { printf '%s\n' "$*"; }

MODULE_CHECKS_PRINTED=0

check() { # label, pattern, path
  local label="$1" pat="$2" path="$3"
  local modtag
  modtag="$(norm_module "${label%% *}")"
  if [ -n "$MODULE" ] && [ "$modtag" != "$MODULE" ]; then
    return
  fi
  MODULE_CHECKS_PRINTED=$((MODULE_CHECKS_PRINTED + 1))
  if grep -rqIs -- "$pat" $path 2>/dev/null; then
    say "  [x] $label"
  else
    say "  [ ] $label"
  fi
}

checkfile() { # label, filename-glob
  local label="$1" glob="$2"
  local modtag
  modtag="$(norm_module "${label%% *}")"
  if [ -n "$MODULE" ] && [ "$modtag" != "$MODULE" ]; then
    return
  fi
  MODULE_CHECKS_PRINTED=$((MODULE_CHECKS_PRINTED + 1))
  if find . -type f -name "$glob" 2>/dev/null | grep -q .; then
    say "  [x] $label"
  else
    say "  [ ] $label"
  fi
}

say "== 3-term port audit =="
say "repo: $(pwd)"
if [ -n "$MODULE" ]; then
  say "module: $MODULE_DISPLAY"
fi
say "(code presence only — schema/DB verified separately via the migration page)"
say ""
say "Modules:"
check "01 Migration  (TermGradingMigrationController)"      "class TermGradingMigrationController" "app"
check "02 SY toggle  (activateTermGrading)"                 "function activateTermGrading"         "app"
check "03 Term config (IbedTermConfigController)"           "class IbedTermConfigController"       "app"
check "04 Grade equiv (IbedGradeEquivalencyController)"     "class IbedGradeEquivalencyController" "app"
check "05 Resolver   (IBEDGradingDefaults)"                 "class IBEDGradingDefaults"            "app"
check "05 Resolver   (IbedGradeEquivalency support)"        "class IbedGradeEquivalency"           "app"
check "05 Guard      (activeConfigQuery defined)"           "function activeConfigQuery"           "app"
check "P2 SHS plot   (bulkConvertToWholeYear)"              "function bulkConvertToWholeYear"      "app"
check "P2 term subset (bulkConvertTerms)"                   "function bulkConvertTerms"            "app"
check "P2 subset resolve (resolvePlotTermNos)"              "function resolvePlotTermNos"          "app"
check "07 Dynamic ECR (IBEDECRController)"                  "class IBEDECRController"              "app"
check "07 Gate       (hasIbedComponents)"                   "function hasIbedComponents"           "app"
checkfile "08 Grade view (ibed_gradeview blade)"            "ibed_gradeview*.blade.php"
check "09 Final calc (computeFinalFromFormula)"             "function computeFinalFromFormula"     "app"
check "10 SF9 terms  (resolveShsSf9Terms)"                  "resolveShsSf9Terms"                   "app"
check "P1 Sec-info read guard (get_schedule_2)"            "shsHasTermPlotting(\$syid, \$levelid->levelid)" "app"
check "P1 Sec-info write norm (semidMatch)"                "\$semidMatch = function"              "app"
check "P1 Sec-info dropdown (SEC_TERM_MAP)"                "SEC_TERM_MAP"                          "resources"
if [ -n "$MODULE" ] && [ "$MODULE_CHECKS_PRINTED" -eq 0 ]; then
  say "  (no code-presence detector defined for module $MODULE_DISPLAY yet in this script —"
  say "   see the \"Needs update?\" section below instead, or add one here.)"
fi
say ""

if [ -n "$MODULE" ]; then
  say "Needs update? (module $MODULE_DISPLAY changelog entries vs. this repo, heuristic):"
  if [ -x "$SCRIPT_DIR/changelog-audit.sh" ] || [ -f "$SCRIPT_DIR/changelog-audit.sh" ]; then
    bash "$SCRIPT_DIR/changelog-audit.sh" "$MODULE" 2>&1 | sed 's/^/  /'
  else
    say "  changelog-audit.sh not found next to audit.sh — skipping."
  fi
  say ""
fi

say "Invariant #1 — ibed_term_config reads and their guard:"
files=$(grep -rlIs -- "table('ibed_term_config'" app resources 2>/dev/null | grep -v "ibed_term_config_gradelevel" || true)
if [ -z "$files" ]; then
  say "  (no ibed_term_config reads found)"
else
  for f in $files; do
    if grep -qIs -- "activeConfigQuery\|whereConfigActive" "$f"; then
      say "  [x guard]     $f"
    else
      say "  [! NO GUARD]  $f"
    fi
  done
  say ""
  say "  '[! NO GUARD]' = file reads ibed_term_config but never calls activeConfigQuery/"
  say "  whereConfigActive. Inspect each: a GRADING or REPORT read there likely ignores the"
  say "  Inactive status (invariant #1) and must be wrapped. SETUP/CRUD-list screens"
  say "  (IbedTermConfigController list/get, RegistrarV2 setup list) are legitimately"
  say "  unguarded — they must show inactive configs to manage them."
  say ""
  say "  Heuristic: the guard check is per-file, so a file with several reads may guard"
  say "  some and miss others. Open the flagged files and check each ibed_term_config read."
fi
say ""

say "Invariant #1b — bare ibed_term (child table) reads by id:"
say "  ibed_term has no isactive of its own — a read keyed only by ibed_term.id (e.g. a"
say "  termid selected earlier in a request) must join back to ibed_term_config and go"
say "  through activeConfigQuery(), or a term whose parent config was later deactivated"
say "  stays resolvable forever. This misses table('ibed_term_config' reads (Invariant #1"
say "  above already covers those) and any join('ibed_term_config' already present in the"
say "  same statement (nothing to add there)."
termfiles=$(grep -rlIs -- "table('ibed_term'" app resources 2>/dev/null || true)
if [ -z "$termfiles" ]; then
  say "  (no bare ibed_term reads found)"
else
  for f in $termfiles; do
    # resolveConfigForLevel()/resolveShsPeriods()/resolveTermLabelsForLevel() already call
    # activeConfigQuery() internally, so a config_id sourced from one of them is pre-vetted -
    # count that as guarded too, not just a literal activeConfigQuery/whereConfigActive call
    # in the same file.
    if grep -qIs -- "join.*ibed_term_config\|activeConfigQuery\|whereConfigActive\|resolveConfigForLevel\|resolveShsPeriods\|resolveTermLabelsForLevel" "$f"; then
      say "  [x guard]     $f"
    else
      say "  [! NO GUARD]  $f"
    fi
  done
  say ""
  say "  '[x guard]' here includes files that source config_id from resolveConfigForLevel()/"
  say "  resolveShsPeriods()/resolveTermLabelsForLevel() rather than a literal"
  say "  activeConfigQuery() call - those resolvers already apply the guard internally."
  say "  Still open '[! NO GUARD]' files: check whether the ibed_term.config_id used there"
  say "  truly came from an unguarded source."
fi
