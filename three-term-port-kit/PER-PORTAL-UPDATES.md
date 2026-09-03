# Per-Portal Updates for 3-Term Grading

A portal-centric view of the feature: for **each portal**, which screens change,
which kit module covers them, and what to verify. Use this for rollout/QA one
portal at a time, and to decide which portal's changes belong in which repo (see
the [Hybrid deployment appendix](HYBRID-DEPLOYMENT.md)).

Module numbers refer to the guides in this kit ([README](README.md)).

---

## Portal × module matrix

| Portal | 01 Mig | 02 SY | 03 Config | 04 Equiv | 05 Resolver | 06 Plot | 07 ECR | 08 View | 09 Final/MS | 10 SF9 |
|--------|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|
| **Superadmin** | ✅ | ✅ | ✅ | ✅ | ✅¹ | ✅ | ✅ | ✅ | ✅ | — |
| **Registrar** | ✅² | ✅ | ✅ | ✅ | ✅¹ | ✅ | — | ✅ | ✅ MS | ✅ |
| **Principal** | — | — | ✅ | ✅ | ✅¹ | ✅ | — | ✅ | ✅ MS³ | — |
| **Academic Coord** | — | — | ✅ | ✅ | ✅¹ | ✅ | — | ✅ | ✅ MS³ | — |
| **Teacher** | — | — | — | — | ✅¹ | — | ✅⁴ | ✅ | ✅ | — |
| **Student / Parent** | — | — | — | — | ✅¹ | — | — | view | — | ✅ view |

¹ **Module 05 is shared infrastructure** — the resolver Support classes are used by
every portal's grading code; they aren't a "screen," but they must be present
wherever any portal resolves terms. ² Migration lives under superadmin; run it on
whichever DB each deployment uses. ³ Master sheets are reachable from oversight
portals. ⁴ ECR management (`/classschedule`) is admin-facing; teachers enter grades
via the grading grid (Module 08) and finalize via Module 09.

---

## Superadmin

The widest surface — the admin does setup, plotting, class records, and posting.

| Screen / route | Module | What changes |
|----------------|--------|--------------|
| `/superadmin/term-grading-migration` | 01 | **New** page — runs the additive schema. |
| `/setup/schoolyear` | 02 | Activate/Deactivate IBED Term Grading on the SY. |
| `/setup/ibed-term-config` | 03 + 04 | **New** Term Grading Config + Grade Equivalency setup. |
| `/setup/subject/plot` | 06 | "Convert all to Whole Year" banner for SHS. |
| `/classschedule` | 07 + 08 | Quarterly/Term-Based tabs; dynamic vs static ECR; class-record modal viewer. |
| `/grades` (posting) | 08 | Grade-view modals rendered term/component-aware. |

**Verify:** migration runs clean; a config saves; SHS converts to whole-year;
`/classschedule` splits classes into the right tab and downloads the right ECR.

---

## Registrar (local repo in a hybrid)

Owns grading **setup** and **report cards**.

| Screen / route | Module | What changes |
|----------------|--------|--------------|
| `/setup/schoolyear` | 02 | **Owns** the term-grading toggle. |
| `/setup/ibed-term-config` | 03 + 04 | Term config + equivalency setup (registrar nav). |
| `/setup/subject/plot`, `/setup/subject/shs-cluster-plotting` | 06 | Whole-year conversion (subject + cluster). |
| SF9 (`/reports_schoolform9/{id}`), Form 10 (`reportsschoolform10*`) | 10 | SF9 SHS senior renders term columns; Form 10 per scope note. |
| `/grades`, master sheets (`grades/report/mastersheet*`) | 08 + 09 | Term columns in sheets; term/component grade views. |

**Verify:** config + equivalency save; SF9 for a term-mode SHS class shows 1T/2T/3T;
master sheet term columns; report average == final grade.

---

## Principal

Oversight + shared setup/plotting.

| Screen / route | Module | What changes |
|----------------|--------|--------------|
| `/setup/ibed-term-config` | 03 + 04 | Config setup is exposed here too (principal nav) — **can edit**. |
| `/setup/subject/plot`, `.../shs-cluster-plotting` | 06 | Whole-year conversion visible/usable. |
| `/grades`, grade monitoring | 08 | Term/component-aware grade views. |

**Verify:** a config edited here resolves the same everywhere (esp. in a hybrid —
see sync); grade monitoring shows the term layout.

---

## Academic Coordinator

Same footprint as Principal.

| Screen / route | Module | What changes |
|----------------|--------|--------------|
| `/setup/ibed-term-config` | 03 + 04 | Config setup exposed here (academic-coord nav) — **can edit**. |
| `/setup/subject/plot`, `.../shs-cluster-plotting` | 06 | Whole-year conversion. |
| `/grades`, grade monitoring | 08 | Term/component-aware grade views. |

**Verify:** same as Principal.

---

## Teacher (online repo in a hybrid)

Grade **entry** and **finalization**.

| Screen / route | Module | What changes |
|----------------|--------|--------------|
| `/grades/index` → `/subjects/{id}/{syid}/{gradelevelid}/{sectionid}/{semid}` | 08 | System-grading grid: period buttons show terms (`$ibedTerms`) vs quarters; component grid when configured. |
| Class Record / ECR (`/ibed-ecr/*`, `/ecr/*`) | 07 | Dynamic item-level ECR download/upload/view when the class has `components_json`. |
| `/teacher/finalgrades` | 09 | Final grading grid: 1T/2T/3T columns + Final. |
| Grade Summary (`grade/summary`), observed values, ranking | 08/09 | Term-aware summaries (blades wrapped with `activeConfigQuery`). |

**Verify:** a term-mode class shows term buttons; entering per-term scores writes
`gradesdetail` (quarter = term_no); final grade matches the config formula; the
component ECR round-trips into `ibed_ecr_item_grade` + `gradesdetail`.

---

## Student / Parent

Read-only consumers of the term layout.

| Screen / route | Module | What changes |
|----------------|--------|--------------|
| `/student/enrollment/record/reportcard` (+ `/reportcard/grades`) | 10 (view) | Report card should show the term layout for term-mode levels. |

**Verify:** a term-mode student's report card shows terms, not quarters, and the
average matches the registrar SF9. (This is a **consumer** — it inherits the layout
once Module 10 is done; confirm the student/parent blade branches on the same
`isTermGrading`/`shsTerms` flags.)

---

## Hybrid split (which portal → which repo)

For a two-instance hybrid (see [HYBRID-DEPLOYMENT.md](HYBRID-DEPLOYMENT.md)):

- **Local repo:** Superadmin, **Registrar** — migration on local DB, SY toggle,
  config/equivalency setup, plotting, master sheets, SF9/Form 10.
- **Online repo:** **Principal, Academic Coord, Teacher** — migration on online DB,
  config/equivalency setup (they edit too), plotting, ECR, grade view, final
  grading. Student/parent report views live wherever those portals are served.
- **Both:** Module 05 resolver (byte-identical) + Module 01 schema (each DB) +
  `activeConfigQuery`/`isactive` at every config read. Keep the config data synced
  across the two DBs.

---

## Cross-cutting checks (all portals)

1. **Same class, same period model everywhere.** A class is term-mode or quarter
   consistently across every portal that shows it — the whole point of routing all
   resolution through Module 05.
2. **Inactive config is disregarded everywhere.** Set a config Inactive → every
   portal falls back to quarters. This holds only if **every** config read (in
   every portal, in every repo) is wrapped with `activeConfigQuery()`.
3. **`quarter` == `term_no`** in storage — every portal reads/writes term grades
   under the `quarter` column reused as the term index.
