# Appendix — Hybrid Deployment: What to Update in Each Repo

For schools split across two instances, each with its **own database**:

- **Local repo** — the **registrar** portal.
- **Online repo** — the **principal, academic coordinator, and teacher** portals.
- Both expose the Term Grading Config, and both may edit it → the config must be
  kept consistent across the two databases.

This appendix tells you **which modules to apply to which repo**. Do the named
modules (from this kit) in each repo per the split below, then keep the two
databases consistent (last section).

---

## The split at a glance

| Module | Local (registrar) | Online (principal/coord/teacher) | Why |
|--------|:--:|:--:|-----|
| 01 Migration (schema) | ✅ run on local DB | ✅ run on online DB | schema must exist in **both** DBs |
| 05 Resolution helpers | ✅ | ✅ | **foundation — byte-identical in both** |
| 02 SY term-grading toggle | ✅ owns it | reads only | `registrar.setup.schoolyear` is registrar |
| 03 Term config setup | ✅ (registrar nav) | ✅ (principal + coord navs) | **both edit it** |
| 04 Grade equivalency | ✅ | ✅ | part of the config setup family |
| 06 Subject-plot whole-year (SHS) | ✅ if plotting is done locally | ✅ if plotting is done online | apply where SHS plotting happens; the **data** must reach both DBs |
| 07 Teacher ECR (term + component) | — | ✅ | teacher portal |
| 08 Grade-view layout | ✅ registrar view of class record | ✅ teacher/principal/coord | shared viewer; apply on each side that renders it |
| 09 Final grading + master sheets | ✅ master sheets (reports) | ✅ final grading (teacher) | reports local; grade entry online |
| 10 Report cards / SF9 | ✅ | — | `RegistrarControllers\FormReportsController` |

> If a portal isn't served by a repo, skip that repo's copy of the module — but
> **never skip Modules 01 and 05 on either side.**

---

## Local repo (registrar) — update these

1. **[Module 01]** Apply the schema to the **local** database (run the migration
   page, or the SQL, against the local DB).
2. **[Module 05]** Add/port `IBEDGradingDefaults` + `IbedGradeEquivalency` — the
   **exact same version** as the online repo (see foundation rule below).
3. **[Module 02]** SY term-grading toggle on `registrar.setup.schoolyear`
   (`SYSetupController@activateTermGrading` / `deactivateTermGrading`). Registrar
   **owns** the toggle.
4. **[Module 03 + 04]** Term Grading Config + Grade Equivalency setup screens
   (`IbedTermConfigController`, `IbedGradeEquivalencyController`) — the registrar
   nav already links `/setup/ibed-term-config`.
5. **[Module P2]** If SHS subject plotting is done from the registrar/local side,
   add the whole-year conversion (`SubjectPlotController` term methods + banner).
6. **[Module 09 – master sheets]** `MasterSheetController` term columns (registrar
   runs the sheet reports). Wrap its config reads with `activeConfigQuery`.
7. **[Module 10]** Report cards / SF9 term layout
   (`FormReportsController@reportsschoolform9` + `resolveShsSf9Terms` + the SF9
   blade). Registrar-only.
8. **Consumers of grades** (master sheets, SF9) read `gradesdetail` — those rows
   are entered **online**, so the local DB must receive them (grade-data sync,
   below).

---

## Online repo (principal / academic coord / teacher) — update these

1. **[Module 01]** Apply the schema to the **online** database.
2. **[Module 05]** Add/port `IBEDGradingDefaults` + `IbedGradeEquivalency` — the
   **exact same version** as the local repo.
3. **[Module 03 + 04]** Term Grading Config + Grade Equivalency setup screens —
   the principal and academic-coordinator navs already link
   `/setup/ibed-term-config`, so this side edits them too.
4. **[Module P2]** If SHS plotting is done online, add the whole-year conversion.
5. **[Module 07]** Teacher ECR — `TeacherECRController@schedule` (`is_term_mode` +
   `has_ibed_components` stamping), `hasIbedComponents()`, and the dynamic
   `IBEDECRController` (download/upload/view/save). Teacher portal.
6. **[Module 08]** Grade-view layout — the class-schedule modal viewer and the
   system-grading grid (`TeacherGradingV2@showGrades`, `ibed_gradeview.blade.php`).
7. **[Module 09 – final grading]** `TeacherFinalGrade` + `finalgrade.blade.php`
   term columns + `GenerateGrade` final computation. Wrap config reads with
   `activeConfigQuery`.
8. **SY toggle:** online **reads** `sy.term_grading_status` (it arrives via sync);
   it does not need the toggle UI unless you want it there too.

---

## Both repos — shared foundation (must match)

These are the pieces that, if they differ between the two repos/DBs, silently make
a class term-mode on one portal and quarter on the other:

1. **Module 01 schema** — run on **both** databases (identical columns/tables).
2. **Module 05 Support classes** — `IBEDGradingDefaults` and `IbedGradeEquivalency`
   must be **byte-identical** in both repos. Pin them to the **same commit/tag**;
   any resolver drift diverges results even with identical data.
3. **The `activeConfigQuery` / `isactive` rule** — every `ibed_term_config` read on
   a grading/report path, in **both** repos, must go through
   `IBEDGradingDefaults::activeConfigQuery()`. The guard runs per-DB/per-repo, so
   both sides must honor it or an *Inactive* config resurfaces on one portal.

---

## Keeping the two databases consistent

Because the DBs are separate and both sides edit the config, the config content
must be synced. Two rules make this safe:

- **Sync by business key, never by `id`.** Both DBs auto-increment ids
  independently, so `id=5` locally ≠ `id=5` online. Resolution (Module 05) keys on
  `(syid, acadprogid, level, semid, isactive)`, never on a cross-DB id — so ids
  don't need to match, only **content** must. When syncing, upsert by business key
  and **remap foreign keys** (`ibed_term.config_id`,
  `ibed_term_config_gradelevel.config_id`, `ibed_term_config.grade_point_equivalence_id`
  / `score_conversion_id`) to the target DB's own ids.
- **Partition who edits what.** Module 03's duplicate guard already forbids
  overlapping active configs within one DB; agree a convention so each side edits
  only non-overlapping academic programs/levels. Then "both edit" never means both
  touch the same config, and a periodic two-way content sync (last-write-wins on
  `updateddatetime`, soft-deletes propagated) just keeps them mirrored.

**Sync these (config):** `ibed_term_config`, `ibed_term`,
`ibed_term_config_gradelevel`, `ibed_grade_point_equivalence`,
`ibed_grade_point_scale`, `ibed_score_conversion`, and the `sy.term_grading_status`
flag (+ `subject_gradessetup` component setups if edited on both sides).

**Sync these (grades, so registrar reports see online-entered scores — usually
online → local):** `grades`, `gradesdetail`, `ibed_ecr_item_grade` — same
business-key + FK-remap approach; schedule separately (higher volume).

> The repo already declares an unused peer connection `mysql2`
> (`DB_HOST_2` / `DB_DATABASE_2`) — the natural handle for a scheduled sync command.
> The sync job itself is **net-new** (nothing implements it yet). Want a starter
> command? Ask — it's real new code, best built and tested deliberately.

---

## Per-repo checklist

**Local repo (registrar)**
- [ ] Module 01 schema on local DB
- [ ] Module 05 Support classes (== online repo commit)
- [ ] Modules 02, 03, 04 (SY toggle + config + equivalency setup)
- [ ] Module P2 (if plotting local), Module 09 master sheets, Module 10 SF9
- [ ] `activeConfigQuery` at every config read

**Online repo (principal/coord/teacher)**
- [ ] Module 01 schema on online DB
- [ ] Module 05 Support classes (== local repo commit)
- [ ] Modules 03, 04 (config + equivalency setup — principal/coord edit them)
- [ ] Modules 06 (if plotting online), 07 ECR, 08 grade view, 09 final grading
- [ ] `activeConfigQuery` at every config read

**Both / cross-cutting**
- [ ] Editing scope partitioned by program/level across the two sides
- [ ] Two-way config sync (business key + FK remap + LWW + soft-delete)
- [ ] Grade-data sync (online → local) for reports
- [ ] Reconciliation check: same config business key resolves the same period model
      on registrar reports and the teacher portal
