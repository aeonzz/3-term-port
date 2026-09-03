---
name: three-term-port
description: >-
  Guided workflow for implementing or porting the IBED 3-term (term grading)
  feature to a CK school ERP repo, using the port kit in docs/three-term-port-kit/.
  Use this skill whenever the user wants to add, port, implement, roll out, or
  troubleshoot term grading / the 3-term feature — including any mention of
  ibed_term_config, term configuration, "convert quarters to terms", 1T/2T/3T,
  resolveShsPeriods / resolveTermLabelsForLevel, the dynamic/component ECR,
  term-based classes, or making a class/level term-based. Also use it for the
  hybrid two-database rollout (registrar-local vs principal/coord/teacher-online)
  and for per-portal rollout questions. Also handles targeting a single kit module
  by number — e.g. "/three-term-port 3", "implement module 7", "do step 05" — jump
  straight to that module. Use "/three-term-port help" for a quick reference of all
  modules, aliases, and commands. Prefer this skill over ad-hoc edits any time the
  task touches term-grading resolution, setup, ECR, final grades, or report cards,
  even if the user doesn't say "3-term" explicitly.
---

# 3-Term Grading — Port / Implementation Workflow

This skill orchestrates the **port kit** at `docs/three-term-port-kit/`. The kit
MDs are the source of truth for *what* to change; this skill governs *how* to
sequence the work, the invariants that must hold, and how to scope it to a repo /
portal. Read the relevant kit file before editing — don't work from memory.

## Modes

| Argument | What happens |
|----------|-------------|
| *(none)* | **Full port** — orient, scope, work modules in order |
| `<module>` | **Single module** — jump to that module (number, P-number, or alias) |
| `help` | **Help** — print usage reference and stop |
| `changelog` | **Changelog** — run the changelog script and show all module changes |
| `changelog <module>` | **Changelog (single)** — show changes for one module only |
| `changelog audit` | **Changelog audit** — check every changelog entry's identifiers against this repo |
| `changelog audit <module>` | **Changelog audit (single)** — audit one module only |

## Help command

When the argument is `help` (or `--help`, `-h`, `?`), print the following
reference block **verbatim** and stop — do not orient, audit, or start any
module work:

~~~
3-Term Port Kit — quick reference

USAGE
  /three-term-port              Full port — orient, scope, then work modules in order
  /three-term-port <module>     Jump to a single module (number, P-number, or alias)
  /three-term-port help         Show this help

MODULES (core — work in order)
  01  Migration (schema)              05  Resolution helpers
  02  SY term-grading toggle          07  Teacher ECR
  03  Term config setup               09  Final grading + master sheets
  04  Grade equivalency               10  Report cards / SF9
                                      11  SF10 Permanent Record

MODULES (P — portal surfaces, order flexible after dependencies)
  P1   Principal Section Info         P7   Class Schedule / Teacher ECR
  P2   Subject Plot (SHS)             P8   Teacher Final Grades
  P3   SHS Cluster Plotting           P9   System Grading
  P4   SHS Subject Picking            P10  Teacher Grade Summary
  P5   SHS Bulk Subject Picking       P11  Teacher Pending Grades
  P6   Teacher Home Schedule          P12  Grade Status

ALIASES (use in place of a module number)
  "section info" → P1          "class schedule" / "teacher ECR" → P7
  "subject plot" → P2          "final grades" / "teacher final grades" → P8
  "cluster plotting" → P3      "system grading" → P9
  "subject picking" → P4       "grade summary" → P10
  "bulk picking" → P5          "pending grades" → P11
  "teacher home schedule" → P6 "grade status" / "badge status" → P12
  "SF10" / "permanent record" / "form 137" → 11

AUDIT (read-only, shows what's already implemented)
  bash .claude/skills/three-term-port/scripts/audit.sh

CHANGELOG (shows all changes across modules)
  /three-term-port changelog          All modules
  /three-term-port changelog P9       Single module
  /three-term-port changelog audit    Check every entry's identifiers against this repo
  /three-term-port changelog audit 07 Audit one module only

KIT DOCS
  docs/three-term-port-kit/README.md         Module roadmap & conventions
  docs/three-term-port-kit/PER-PORTAL-UPDATES.md   Portal → module map
  docs/three-term-port-kit/HYBRID-DEPLOYMENT.md     Two-DB rollout guide
  docs/THREE_TERM_CONVERSION_GUIDE.md        Operational runbook (for admins)

COMPANION SKILLS
  /create-kit-module <id> <title>    Create a new kit module file
~~~

## Changelog command

When the argument is `changelog` (with or without a module id after it, but
**not** followed by `audit` — see "Changelog audit" below for that), run
the changelog script and print its output:

```bash
# All modules
bash .claude/skills/three-term-port/scripts/changelog.sh

# Single module
bash .claude/skills/three-term-port/scripts/changelog.sh P9
```

The script extracts changelog entries (`### YYYY-MM-DD — Title`) from each
module's `## Changelog` section and lists them. Print the output.

A changelog entry is a summary, not a diff — printing it (or being asked to
"apply" one afterward) does not mean it's safe to reproduce from that prose,
especially into a repo other than the one you're sitting in. If the entry
belongs to a large-file module (03/07/09/10) and isn't already applied in the
target, ask for the es_ldcu path and go get that **entry's own commit diff**
(not just the current file) before writing any implementation — see
"Reference source" below for how to find it. Rebuilding the described
behavior from memory of the changelog text produces code that only
approximately matches the real commit.

After printing, **commit all changed kit MD files** automatically:

1. Stage only the kit files:
   ```bash
   git add docs/three-term-port-kit/*.md
   ```
2. Check if there are staged changes (`git diff --cached --quiet` — if quiet,
   nothing to commit, skip).
3. Commit with a short one-liner — **no co-author line**:
   ```bash
   git commit -m "docs: update kit changelog"
   ```
4. Tell the user the commit was made (or that there was nothing new to commit).

Then stop — do not start any module work.

## Changelog audit

When the argument is `changelog audit` (with or without a module id after
it), run the audit script and print its output verbatim:

```bash
# All modules
bash .claude/skills/three-term-port/scripts/changelog-audit.sh

# Single module
bash .claude/skills/three-term-port/scripts/changelog-audit.sh 07
```

For every changelog entry in every module (or just the one named), the
script pulls the inline-code identifiers (`` `LikeThis` ``) mentioned in
that entry's own prose — function/class names, table columns, files touched
— and greps this repo for each one. It reports, per entry, how many of its
identifiers were found and lists the missing ones, so an entry with 0/N (or
a low ratio) surfaces as likely not applied here without you having to
manually re-derive and grep for each entry's identifiers yourself, the way
the "Live-calculating summary sheet" entry had to be checked by hand earlier
in this skill's own history.

**This is a heuristic, not a verdict — say so when reporting it.** It
matches literal identifier strings, so it:
- Cannot see behavior differences. An identifier can exist while the logic
  it names is wrong, incomplete, or was later changed elsewhere — "all
  found" is a green light to skip a deep dive, not proof the entry is
  correctly implemented. A real discrepancy (e.g. a helper that exists but
  reads the wrong equivalence target) will not show up as a missing
  identifier.
- Can false-positive on short/common identifiers (`semid`, `grades`,
  `is_failed`) that appear all over the codebase for unrelated reasons —
  this is why a "partial" match is common even for entries that are
  correctly applied, and does not by itself mean anything is wrong.
- Only checks this repo's own copy of the kit MD (each target repo keeps its
  own `three-term-port-kit/`, which can be out of sync with another repo's
  copy — a module here showing 0 changelog entries usually means this
  repo's kit doc doesn't have that module's changelog section yet, not that
  the code is unimplemented).

Treat "all found" as license to move on without re-verifying that entry.
Treat anything else (0 found, or partial) as a prompt to go read the actual
code (or, if applying it, the real commit diff per "Reference source"
below) before concluding anything — never report an entry as missing or
broken from the audit's ratio alone.

Then stop — do not start any module work (an audit finding is grounds to
offer applying or fixing an entry, not to silently start doing so).

## First: orient

1. **Run the audit** — `bash .claude/skills/three-term-port/scripts/audit.sh`
   (read-only). It reports which modules already look implemented and flags any
   `ibed_term_config` read missing the `activeConfigQuery` guard. Use it to see
   current state / resume a partial port / start debugging. (It checks code only;
   schema is a DB check — use the migration page's "Check Status".)
2. Read `docs/three-term-port-kit/README.md` — the module roadmap (01–10) and how
   the kit is used.
3. Establish scope before touching code (ask the user if unclear):
   - **Which repo / portals** does this instance serve? → read
     `docs/three-term-port-kit/PER-PORTAL-UPDATES.md` to map portals → modules.
   - **Single or hybrid deployment?** Two instances / two databases → read
     `docs/three-term-port-kit/HYBRID-DEPLOYMENT.md` for the per-repo split and the
     sync requirement.
   - **Fresh port vs. debugging an existing one?** For "why is this class showing
     quarters / terms wrong", jump to the gate rules (Module 05) and the operational
     runbook `docs/THREE_TERM_CONVERSION_GUIDE.md`.

## Work modules in order

The modules build on each other; earlier layers must exist and be verified before
later ones. Do not start a consumer module (07–10) until the schema (01) and the
resolver (05) are in place and proven.

| # | Module | Kit file | Depends on | Do it when |
|---|--------|----------|-----------|-----------|
| 01 | Migration (schema) | `01-term-grading-migration.md` | — | first, always — run on the target DB |
| 02 | SY term-grading toggle | `02-sy-term-grading-toggle.md` | 01 | after schema |
| 03 | Term config setup | `03-term-grading-config.md` | 01, 02 | after 01–02 |
| 04 | Grade equivalency / transmutation | `04-grade-equivalency.md` | 01 | with/after 03 |
| 05 | Resolution helpers (`IBEDGradingDefaults`, `IbedGradeEquivalency`) | `05-term-resolution-helpers.md` | 01 | foundation — before any consumer |
| P2 | Subject-plot whole-year + term subsets (SHS only) | `P2-subject-plot-term.md` | 01, 05 | before SHS goes term-mode |
| 07 | Teacher ECR (term + dynamic/component) | `07-teacher-ecr-term.md` | 01, 05, P2 | after 05 |
| 09 | Final grading + master sheets | `09-final-grading-mastersheets.md` | 05, 07 | after 05 |
| 10 | Report cards / SF9 | `10-report-cards-sf9.md` | 05, 09 | after 09 |
| 11 | SF10 Permanent Record (term layout — SHS + JHS) | `11-sf10-permanent-record.md` | 05, 09, 10 | after 10 — mirrors SF9 pattern for permanent record |
| P1 | Principal Section Info (term-aware schedules) | `P1-principal-section-info.md` | 01, 05, P2 | portal surface — after P2 |
| P3 | SHS Cluster Plotting (cluster term conversion) | `P3-shs-cluster-plotting-term.md` | 01, 05 | cluster sibling of P2 — before SHS cluster classes go term-mode |
| P4 | SHS Subject Picking (term-aware individual picking) | `P4-shs-subject-picking.md` | 01, 05, P3 | after P3 — picking depends on term-mode plots |
| P5 | SHS Bulk Subject Picking (term-aware bulk picking) | `P5-shs-bulk-subject-picking.md` | 01, 05, P3, P4 | after P4 — extends the picking page with bulk |
| P6 | Teacher Home Schedule (term-aware teacher portal schedule table) | `P6-teacher-home-schedule.md` | 01, 05, P2, P3 | portal surface — after P2/P3 |
| P7 | Class Schedule / Teacher ECR (term-aware schedule tabs + ECR modal) | `P7-class-schedule-term.md` | 01, 05, P2, P3, 07 | portal surface — after 07 (needs ECR v2 endpoints) |
| P8 | Teacher Final Grades (term-aware FG page: period swap, FG formula, grade headers) | `P8-teacher-final-grades.md` | 01, 05, P2, P3, 09 | portal surface — after 09 (FG page is a consumer of final-grading logic) |
| P9 | System Grading (term-aware: Whole Year filter, section/subject queries, term tabs, dynamic ECR) | `P9-system-grading-term.md` | 01, 04, 05, 07, P2, P3 | portal surface — after 07 (grading page consumes dynamic ECR) |
| P10 | Teacher Grade Summary (term-aware: TERM_MAP, quarter picker, column headers, print semid=0) | `P10-teacher-grade-summary.md` | 01, 04, 05, P2, P3 | portal surface — after P2/P3 (needs whole-year plots for term detection) |
| P11 | Teacher Pending Grades (term-aware: period loop, quarter picker relabeling, semid gating) | `P11-teacher-pending-grades.md` | 01, 05, P2, P3 | portal surface — after P2/P3 (pending grades page is a consumer of resolveShsPeriods) |
| P12 | Grade Status (term-aware: semid fix, portable SHS checks, computed badge) | `P12-grade-status-term.md` | 01, 04, 05, 07, P2, P3, P9 | portal surface — after P9 (fixes portability bugs in grade-status flow) |

> **P-modules** (`P1`, `P2`, `P3`) are portal/setup **surfaces** with the same
> apply-with-preflight format; each MD has its own `PREFLIGHT — check the repo FIRST`
> section. `P2` is the plotting gate (formerly numbered 06, still done in that slot);
> `P3` is its cluster-plotting counterpart.

For each module: **read its MD**, copy/adapt the referenced es_ldcu files, wire the
routes + sidenav, then run that module's **Verification** section before moving on.
A module's MD says exactly which files to copy verbatim vs. adapt. **Commit after
each verified module** (one short-message commit per module) so a big port stays
reviewable and revertable, and the audit script can pick up where you left off.

## Reference source (porting into another repo)

The kit references es_ldcu file paths, but when you run this **in a target repo,
es_ldcu is not checked out there**. Handle it:

- The kit MDs **inline** the small, critical pieces (gates, resolvers, formula
  helpers) — those you can apply directly from the MD.
- The **large** files (Modules 03/07/09/10 controllers + blades) are referenced,
  not reproduced. To copy them you need an es_ldcu checkout — **ask the user for its
  path** (e.g. a sibling clone) and read the files from there. Do **not** fabricate
  the contents of a large controller/blade from memory.
- After copying, always **adapt** per the "Adapt, don't assume" section — the target
  repo's table/column names, acadprog ids, and layout will differ.

**Two different jobs need two different reads from that checkout — don't
substitute one for the other:**

- **Fresh module port** (the target file doesn't have this module's code at
  all yet): read the **current state** of the file in the es_ldcu checkout and
  copy/adapt it whole. The current snapshot already contains everything.
- **Applying a single changelog entry** (module already ported, target has its
  own prior edits/divergence, only *this* entry's behavior is missing — the
  situation the "apply <changelog entry>" phrasing signals): the current file
  snapshot is **not enough**, because it doesn't tell you which lines are this
  entry versus everything else already in the file. You need the entry's
  actual **commit diff**. Find it in the es_ldcu checkout with
  `git log --oneline -- <path/to/file>`, matching the commit by the changelog
  entry's date/title, then read it with `git show <hash> -- <path/to/file>`.
  Only once you have that diff should you adapt and apply it — reconstructing
  the entry from the kit MD's changelog prose (or from the current file state
  alone) reliably drifts from what the real commit did.

## Targeting a single module

When the user names a kit number (arg to `/three-term-port`, or phrases like
"implement module 7", "do step 05", "just the SF9 one"):

1. **Map the id to its file** using the table above and open
   `docs/three-term-port-kit/<file>`. Accept `3`, `03`, "module 3", "step 3", and the
   **P-modules** `P1` / `P2` / `P3` / `P4` / `P5` / `P6` / `P7` / `P8` / `P9` / `P10` / `P11` / `P12` (also "section info" → P1, "subject plot" → P2,
   "cluster plotting" → P3, "subject picking" → P4, "bulk picking" → P5, "teacher home schedule" → P6,
   "class schedule" / "teacher ECR" → P7, "teacher final grades" / "final grades" → P8,
   "system grading" → P9, "grade summary" / "teacher grade summary" → P10,
   "pending grades" / "teacher pending grades" → P11,
   "grade status" / "badge status" → P12, "SF10" / "permanent record" / "form 137" → 11). If the id is out of range (not 01–11 or P1–P12), say so
   and show the table.
2. **Check its `Depends on` prerequisites are actually in place** before editing —
   don't assume. At minimum verify the schema (01) exists and, for consumer modules
   (P2, 07–10, P1), that Module 05's Support classes are present and `activeConfigQuery`
   exists. If a prerequisite is missing, tell the user and offer to do it first
   rather than producing a half-wired module.
3. **Implement just that module** per its MD — **P-modules begin with a `PREFLIGHT`
   section: run its detector greps first and apply only what's missing** (they may be
   partly applied already). If the module is one of the **large-file modules
   (03/07/09/10)**, do not write the implementation from the MD's prose alone —
   go get the es_ldcu path first (see "Reference source" below), and read either
   the current file (fresh port) or that piece's specific commit diff (module
   already partly applied, only some behavior missing) — whichever "Reference
   source" says fits. Then run **only that module's Verification** section.
4. Still enforce the **invariants below** — a single-module port must not break the
   `activeConfigQuery`/`isactive` rule or the `quarter == term_no` convention.
5. **Report back with a ticked checklist.** When done, post the module's acceptance
   criteria / changes to chat as a checkbox list so the user sees what landed: **✅**
   applied and verified, **✔️** code applied but runtime/live-page test still pending,
   **⬜** skipped or not applicable (say why). Never mark ✅ something you didn't apply;
   prefer ✔️ when you only lint/compile-verified.

Do not silently expand a single-module request into the full sequence. If the module
can't stand without a missing prerequisite, surface that and let the user decide.

## Non-negotiable invariants (check these every module)

These are what keep the feature consistent; most 3-term bugs trace back to breaking
one of them. For the concrete bugs the es_ldcu rollout hit (symptom → cause → fix),
read `references/known-pitfalls.md` — consult it when a class resolves to the wrong
period model, a grid renders blank, or a hybrid's two sides disagree.

1. **Every `ibed_term_config` read on a grading/report path goes through
   `IBEDGradingDefaults::activeConfigQuery()`** (or `IbedGradeEquivalency::whereConfigActive`).
   A bare `deleted=0` read resurfaces an *Inactive* config and is the #1 source of
   "terms showing where they shouldn't." When adding any new config query, wrap it.
2. **`grades.quarter` doubles as `term_no`** in term mode. Term grades are stored
   and read under the existing `quarter` column reused as the term index — never add
   a parallel term column.
3. **Module 05 is the single brain.** All term-vs-quarter decisions come from
   `resolveShsPeriods` (SHS: config **and** whole-year plotting) or
   `resolveTermLabelsForLevel` (junior: config only). Never hand-roll a second term
   lookup that skips `isactive` or the SHS plotting gate.
4. **Junior ≠ Senior.** Junior levels go term-mode on config alone. SHS (levels
   14/15) also require whole-year plotting (Module 06) — a config alone leaves them
   on the semester layout by design.
5. **Additive & non-destructive to legacy classes.** A class on the **static
   format** (`has_ibed_components == 0` / no applicable term config) must keep using
   the **existing grading computation and the existing (legacy `gradetransmutation`)
   transmutation** — in **both** the ECR and system grading. The feature never
   migrates, recomputes, or overwrites those classes. The transmutation split is:
   dynamic/term classes → `IbedGradeEquivalency` (new, config-driven); static/legacy
   classes → the existing `gradetransmutation` path, untouched. The old-data
   tie-breaker in `hasIbedComponents()` enforces the "don't touch old grades" half —
   a class with positive legacy `wwtotal/pttotal/qatotal` stays static until a
   teacher deliberately re-uploads through the dynamic ECR.

## Adapt, don't assume (per-target differences)

The kit came from es_ldcu; a target repo legitimately differs. Watch for:

- **Table/column names:** `sh_classsched` (SHS, has `glevelid`/`semid`) vs
  `classsched` (JHS); `subject_plot.gradessetup`; cluster setup on
  `sh_cluster_plot.gradingsetupid`. Confirm against the target schema.
- **Academic-program ids:** `5` = Senior High, `6` = College (excluded). Verify the
  target's `academicprogram` ids and adjust the SHS checks / college exclusion.
- **Layout/section names:** blades `@extends` the target's own superadmin/registrar
  layout; adapt `@section` names and confirm jQuery/DataTables/Select2/SweetAlert2
  are loaded.
- **School-specific report blades:** SF9/SF10 come in many per-school variants — port
  the term branch into whichever the target actually renders.

## Honesty about effort

- Modules 03, 04, 07, 09, 10 involve **large controllers/blades** — copy verbatim
  from the es_ldcu reference paths, then adapt. The MDs inline the small
  gates/helpers; they reference (not reproduce) the huge files.
- The **hybrid sync layer is net-new code** (the `mysql2` connection is declared but
  unused). Don't claim it's ported — if the user wants it, build a scheduled
  business-key sync command deliberately (see HYBRID-DEPLOYMENT.md).

## Verifying the whole thing

The end-state invariant across all portals: **one class resolves to the same period
model everywhere** (class schedule, teacher grading, final grades, report card), and
setting its config **Inactive** drops every surface back to quarters. If two surfaces
disagree, it's almost always a missed `activeConfigQuery` wrap or a Module 05 that
drifted between repos.

Companion operational guide (for admins actually converting a level, not porting the
code): `docs/THREE_TERM_CONVERSION_GUIDE.md`.
