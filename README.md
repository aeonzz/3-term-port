# How to Use This — 3-Term Grading Port

This folder is a **port kit** for adding the IBED **3-term grading** feature to a
CK school ERP repo. It has two parts:

| Part | What it is |
|------|------------|
| `three-term-port-kit/` | Self-contained, copy-paste-ready module guides (the *what*) |
| `/three-term-port` skill | Guided workflow that sequences the modules and enforces invariants (the *how*) |

The kit MDs are the source of truth for what to change. The skill governs order,
scoping to a repo/portal, and verification. **Read the relevant kit file before
editing — don't work from memory.**

---

## Quick start

1. **Copy the kit into the target repo:**
   copy `three-term-port-kit/` into the target project's `docs/` folder
   (so it lives at `docs/three-term-port-kit/`).

2. **Confirm the target is a CK school ERP** — same Laravel base with tables
   `sy`, `gradelevel`, `subject_plot`, `sh_classsched`, `grades`, `gradesdetail`,
   `subject_gradessetup`, and the AdminLTE superadmin layout. The kit assumes
   this shape.

3. **From inside the target repo, run the skill:**

   ```bash
   /three-term-port
   ```

   With no argument it does a **full port**: orients, scopes to the repo/portal,
   then works modules in order.

4. **For each module:** create/edit the listed files, wire routes + sidenav,
   run the module's Verification section, tick it off.

> **Always start with Module 01** (schema migration). Nothing else works until
> the schema exists.

---

## Skill commands

| Command | What it does |
|---------|-------------|
| `/three-term-port` | Full port — orient, scope, work all modules in order |
| `/three-term-port <module>` | Jump to one module (number, P-number, or alias) |
| `/three-term-port help` | Print the quick reference and stop |
| `/three-term-port changelog` | Show changes across all modules |
| `/three-term-port changelog <module>` | Changelog for one module |
| `/three-term-port changelog audit` | Check every changelog entry's identifiers against this repo |

Examples: `/three-term-port 3`, `/three-term-port P9`, `/three-term-port "final grades"`,
`/three-term-port SF10`.

Read-only audit of what's already implemented:

```bash
bash .claude/skills/three-term-port/scripts/audit.sh
```

---

## Module order

### Core modules — do these in order

| # | Module |
|---|--------|
| 01 | Term Grading Migration page (schema runner) |
| 02 | School Year term-grading toggle (`term_grading_status`) |
| 03 | Term Grading Config screen (`ibed_term_config` CRUD) |
| 04 | Grade Equivalency / transmutation tables |
| 05 | Term resolution helpers (`IBEDGradingDefaults`, `IbedGradeEquivalency`) |
| 07 | Teacher ECR — term mode + dynamic/component ECR |
| 09 | Final grading + master sheets (term columns) |
| 10 | Report cards / SF9 (term layout) |
| 11 | SF10 Permanent Record (term layout — SHS + JHS) |

### Portal surface modules (P) — order flexible after their dependencies

| # | Module | # | Module |
|---|--------|---|--------|
| P1 | Principal Section Info | P7 | Class Schedule / Teacher ECR |
| P2 | Subject Plot (SHS) | P8 | Teacher Final Grades |
| P3 | SHS Cluster Plotting | P9 | System Grading |
| P4 | SHS Subject Picking | P10 | Teacher Grade Summary |
| P5 | SHS Bulk Subject Picking | P11 | Teacher Pending Grades |
| P6 | Teacher Home Schedule | P12 | Grade Status |

---

## Aliases

Use in place of a module number:

| Alias | Module | Alias | Module |
|-------|--------|-------|--------|
| `section info` | P1 | `class schedule` / `teacher ECR` | P7 |
| `subject plot` | P2 | `final grades` / `teacher final grades` | P8 |
| `cluster plotting` | P3 | `system grading` | P9 |
| `subject picking` | P4 | `grade summary` | P10 |
| `bulk picking` | P5 | `pending grades` | P11 |
| `teacher home schedule` | P6 | `grade status` / `badge status` | P12 |
| `SF10` / `permanent record` / `form 137` | 11 | | |

---

## Reference implementation

Every module was extracted from the canonical implementation and should be
diffed against it:

- **Repo:** `es_ldcu` (`CK-PUB-DEV/es_ldcu`) — local path `C:\laragon\www\es_ldcu`
- **Branch context:** `feat/taborin/3-term`
- **Companion docs in `es_ldcu/docs/`:**
  - `THREE_TERM_CONVERSION_GUIDE.md` — operational runbook (how an admin converts a level)
  - `IBED_ECR_STATE.md` — how grades are stored/read
  - `IBED_DYNAMIC_ECR_FEATURE.md` — component/dynamic ECR
  - `registrar-three-term-checklist.md`, `teacher-three-term-checklist.md` — dev verification checklists

When a guide says *"reference implementation,"* it means the file at that path in
`es_ldcu`. A changelog entry is a summary, not a diff — for large-file modules
(03/07/09/10) go get that entry's own commit diff from `es_ldcu` before writing
any implementation; don't rebuild from the changelog prose.

---

## What each guide contains

- **Reference implementation** — the exact `es_ldcu` file(s) the module came from
- **Files** — create/edit list with full or skeleton source
- **Routes / Sidenav** — snippets to paste, with placement notes
- **Porting notes** — where target schools legitimately differ (column names,
  `AFTER` anchors, layout/section names) and how to adapt
- **Verification** — how to confirm the module works before moving on

All schema changes are **additive and idempotent** — re-running is safe; existing
tables/columns are skipped.

---

## Split across two databases?

If registrar is local and principal/coord/teacher are online (or any two-DB
split): do Modules 01–10 in *each* repo, then follow
`three-term-port-kit/HYBRID-DEPLOYMENT.md` to keep `ibed_term_config` consistent
across both databases. See also `three-term-port-kit/PER-PORTAL-UPDATES.md` for
the portal → module map.
