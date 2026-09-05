# 3-Term Grading — Port Kit

A per-module implementation kit for adding the **3-term grading** feature to
another CK school ERP project. Copy this whole `three-term-port-kit/` folder into
the target repo's `docs/`, then work the module guides in order.

Each guide is **self-contained and copy-paste ready**: it lists the files to
create/edit, the routes and sidenav entries to wire, and the exact code, with
porting notes for where school databases differ.

---

## Reference implementation

Every module in this kit was extracted from and should be diffed against the
canonical implementation:

- **Repo:** `es_ldcu` (`CK-PUB-DEV/es_ldcu`) — local path `C:\laragon\www\es_ldcu`
- **Feature branch context:** `feat/taborin/3-term` line of work
- **Companion docs in `es_ldcu/docs/`:**
  - [`THREE_TERM_CONVERSION_GUIDE.md`](../THREE_TERM_CONVERSION_GUIDE.md) — operational runbook (how an admin converts a level)
  - [`IBED_ECR_STATE.md`](../IBED_ECR_STATE.md) — how grades are stored/read
  - [`IBED_DYNAMIC_ECR_FEATURE.md`](../IBED_DYNAMIC_ECR_FEATURE.md) — component/dynamic ECR
  - [`registrar-three-term-checklist.md`](../registrar-three-term-checklist.md), [`teacher-three-term-checklist.md`](../teacher-three-term-checklist.md) — dev verification checklists

When a guide says *"reference implementation,"* it means the file at that path in
`es_ldcu`. Keep paths relative to the project root (e.g.
`app/Http/Controllers/SuperAdminController/…`) so they resolve in any target repo.

---

## How to use this kit

1. Copy `three-term-port-kit/` into the target project's `docs/`.
2. Confirm the target is a CK school ERP (same Laravel base: `sy`, `gradelevel`,
   `subject_plot`, `sh_classsched`, `grades`, `gradesdetail`, `subject_gradessetup`,
   AdminLTE superadmin layout). This kit assumes that shape.
3. Work the modules **in the order below** — later modules assume the schema and
   config screens from earlier ones exist.
4. For each module: create/edit the listed files, run the module's verification,
   then tick it off.

---

## Module order

| # | Module | Guide | Status |
|---|--------|-------|--------|
| 01 | **Term Grading Migration page** (schema runner) | [`01-term-grading-migration.md`](01-term-grading-migration.md) | ✅ written |
| 02 | School Year term-grading toggle (`term_grading_status`) | [`02-sy-term-grading-toggle.md`](02-sy-term-grading-toggle.md) | ✅ written |
| 03 | Term Grading Config screen (`ibed_term_config` CRUD) | [`03-term-grading-config.md`](03-term-grading-config.md) | ✅ written |
| 04 | Grade Equivalency / transmutation tables | [`04-grade-equivalency.md`](04-grade-equivalency.md) | ✅ written |
| 05 | Term resolution helpers (`IBEDGradingDefaults`, `IbedGradeEquivalency`) | [`05-term-resolution-helpers.md`](05-term-resolution-helpers.md) | ✅ written |
| P2 | **Subject Plot term/whole-year plotting (SHS)** | [`P2-subject-plot-term.md`](P2-subject-plot-term.md) | ✅ written |
| 07 | Teacher ECR — term mode + dynamic/component ECR | [`07-teacher-ecr-term.md`](07-teacher-ecr-term.md) | ✅ written |
| 09 | Final grading + master sheets (term columns) | [`09-final-grading-mastersheets.md`](09-final-grading-mastersheets.md) | ✅ written |
| 10 | Report cards / SF9 (term layout) | [`10-report-cards-sf9.md`](10-report-cards-sf9.md) | ✅ written |
| 11 | SF10 Permanent Record (term layout — SHS + JHS) | [`11-sf10-permanent-record.md`](11-sf10-permanent-record.md) | ✅ written |
| 12 | Static → Dynamic ECR Conversion (per-class convert/revert button) | [`12-static-to-dynamic-ecr-conversion.md`](12-static-to-dynamic-ecr-conversion.md) | 📝 spec (to-build) |
| P1 | **Portal surface: Principal Section Info** (term-aware schedules) | [`P1-principal-section-info.md`](P1-principal-section-info.md) | ✅ written |
| P3 | **SHS Cluster Plotting** (cluster term conversion) | [`P3-shs-cluster-plotting-term.md`](P3-shs-cluster-plotting-term.md) | ✅ written |
| P4 | **SHS Subject Picking** (term-aware individual picking) | [`P4-shs-subject-picking.md`](P4-shs-subject-picking.md) | ✅ written |
| P5 | **SHS Bulk Subject Picking** (term-aware bulk picking) | [`P5-shs-bulk-subject-picking.md`](P5-shs-bulk-subject-picking.md) | ✅ written |
| P6 | **Teacher Home Schedule** (term-aware teacher portal schedule table) | [`P6-teacher-home-schedule.md`](P6-teacher-home-schedule.md) | ✅ written |
| P7 | **Class Schedule / Teacher ECR** (term-aware schedule tabs + ECR modal) | [`P7-class-schedule-term.md`](P7-class-schedule-term.md) | ✅ written |
| P8 | **Teacher Final Grades** (term-aware FG page: period swap, FG formula, grade headers) | [`P8-teacher-final-grades.md`](P8-teacher-final-grades.md) | ✅ written |
| P9 | **System Grading** (term-aware: Whole Year filter, section/subject queries, term tabs, dynamic ECR) | [`P9-system-grading-term.md`](P9-system-grading-term.md) | ✅ written |
| P10 | **Teacher Grade Summary** (term-aware: TERM_MAP, quarter picker relabeling, column headers, print semid=0) | [`P10-teacher-grade-summary.md`](P10-teacher-grade-summary.md) | ✅ written |
| P11 | **Teacher Pending Grades** (term-aware: period loop, quarter picker relabeling, semid gating, submit) | [`P11-teacher-pending-grades.md`](P11-teacher-pending-grades.md) | ✅ written |
| P12 | **Grade Status** (term-aware: semid fix, portable SHS checks, computed badge) | [`P12-grade-status-term.md`](P12-grade-status-term.md) | ✅ written |
| — | **Reference: Per-portal updates** (what changes in each portal) | [`PER-PORTAL-UPDATES.md`](PER-PORTAL-UPDATES.md) | ✅ written |
| — | **Appendix: Hybrid deployment** (two DBs, both editable — sync) | [`HYBRID-DEPLOYMENT.md`](HYBRID-DEPLOYMENT.md) | ✅ written |

> **Start with Module 01.** It is the foundation — nothing else works until the
> schema exists.
>
> **Split across two instances/databases?** Do Modules 01–10 in *each* repo, then
> read the [Hybrid deployment appendix](HYBRID-DEPLOYMENT.md) for keeping the term
> config consistent across both databases.

---

## Conventions in each guide

- **Reference implementation** — the exact `es_ldcu` file(s) the module came from.
- **Files** — create/edit list with full or skeleton source.
- **Routes / Sidenav** — snippets to paste, with placement notes.
- **Porting notes** — where target schools legitimately differ (column names,
  `AFTER` anchors, layout/section names) and how to adapt.
- **Verification** — how to confirm the module works before moving on.

All schema changes in this feature are **additive and idempotent** — re-running
is safe; existing tables/columns are skipped.
