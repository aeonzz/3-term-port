# Module 07 — Teacher ECR (Term Mode + Dynamic/Component ECR)

The Electronic Class Record — where teachers download the score sheet, enter
scores, and upload. The 3-term feature makes the ECR **term-aware** and adds a
**dynamic, item-level (component) ECR**. Which of **three paths** a class uses is
decided by two gates stamped on each schedule row.

- **Screen:** `/classschedule` (admin) — `teacherinformation.blade.php`.
- **Controllers:** `SuperAdminController\TeacherECRController` (schedule + static
  ECR), `SuperAdminController\IBEDECRController` (dynamic/component ECR — a **new**
  controller).

> The two ECR controllers are huge (`TeacherECRController` ~5,600 lines,
> `IBEDECRController` ~3,700). `TeacherECRController` and the classschedule blade
> **pre-exist** in a CK ERP — you add the term/component *additions* to them.
> `IBEDECRController` is **new** — copy it wholesale. This guide gives the gates
> (inlined), the routing, and the dynamic-ECR contract + storage model.

---

## The three ECR paths & two gates

Each schedule row from `TeacherECRController@schedule` carries two flags:

| Flag | Set by | Meaning |
|------|--------|---------|
| `is_term_mode` | Module 05/06 resolution (`resolveShsPeriods` / `resolveActiveTerms`) | Term layout (1T/2T/3T) vs quarter layout |
| `has_ibed_components` | `hasIbedComponents()` (below) | Dynamic item-level ECR vs static ECR |

Routing (from the blade):

| `has_ibed_components` | `is_term_mode` | Download endpoint | Controller |
|:-:|:-:|---|---|
| 1 | (either) | `/ibed-ecr/download` | `IBEDECRController` (dynamic/component) |
| 0 | 1 | `/ecr/downloadv2` | `TeacherECRController` (static **term**) |
| 0 | 0 | `/ecr/download` | `TeacherECRController` (static **quarter**) |

View mirrors this: `/ibed-ecr/view` when dynamic, else the static view endpoint.

---

## Reference implementation (es_ldcu)

| Piece | Path |
|-------|------|
| Schedule + gates + static ECR | `app/Http/Controllers/SuperAdminController/TeacherECRController.php` (`schedule`, `hasIbedComponents`, `checkHasIbedComponents`, `download_ecr`, `upload_ecr`, `view_ecr`) |
| Dynamic/component ECR (**new**) | `app/Http/Controllers/SuperAdminController/IBEDECRController.php` (`download`, `upload`, `view`, `saveScores`) |
| Classschedule UI | `resources/views/superadmin/pages/teacher/teacherinformation.blade.php` |
| Routes | `routes/web.php` (`/teacher/schedule`, `/ecr/*`, `/ibed-ecr/*`) |

> **Naming collision (found porting to sjhsli_online, 2026-08-28):** `es_ldcu` has
> no `TeacherECRv2Controller` at all — its term-aware static ECR lives *inside*
> `TeacherECRController::download_ecr()` etc. via internal branching (see the routing
> table above: `/ecr/download` handles both quarter and term). The genuinely
> term-aware "v2" controller (`resolveShsPeriods` throughout `schedule`, `submit_ecr`,
> `approve_ecr`, `post_ecr`, `pending_ecr`, `unpost_ecr`, ~6,100 lines) lives in
> **`es_bcc`**, not `es_ldcu` — check there when a target repo's routes already point
> `/ecr/downloadv2`/`uploadv2`/`viewv2` at a `TeacherECRv2Controller`. **Don't assume
> that controller already implements Module 07** just because the name and routes
> match what P7 expects: `sjhsli_online` had a `TeacherECRv2Controller` (5,346 lines)
> wired to exactly those routes that turned out to be a stale, non-term-aware
> near-duplicate of the plain `TeacherECRController` — zero `resolveShsPeriods` /
> `is_term_mode` / component-ECR logic anywhere in it. Always grep the *actual file*
> for term-mode symbols before treating a same-named/same-routed controller as done.
>
> **Porting `es_bcc`'s `TeacherECRv2Controller` into a target that already has its own
> copy (found 2026-08-28):** don't diff-and-replace the whole file — `es_bcc`'s copy
> has real, unrelated divergence baked in that must NOT be imported, most seriously
> **hardcoded `es_bcc`-specific teacher names in the signature block** that silently
> *replace* a target's own dynamic signatory lookup (`signatory` table, keyed by
> academic program) if you paste the file over wholesale — confirmed by diffing
> `sjhsli_online`'s existing controller against `es_bcc`'s. It also carries six new
> private helper methods (`ecrSubjectPlots`, `ecrComponentSetup`, `ecrClusterSubjInfo`,
> etc.) tied to an unrelated cluster-elective/component-ECR feature. The reliable
> signal for what's actually term-mode: **`es_bcc`'s copy tags every 3-term line with
> a `// ORENCIO_3TERM_WORK` comment** (48 occurrences, across `get_students`,
> `download_ecr`, `upload_ecr`, `schedule`, `view_ecr`, `submit_ecr`, `approve_ecr`,
> `post_ecr`, `pending_ecr`, `unpost_ecr`). `grep -n "ORENCIO_3TERM_WORK"` first, then
> apply only those hunks (plus their direct non-tagged prerequisites, e.g. the
> `$writer->setPreCalculateFormulas(false)` fix the SUMMARY-sheet rebuild needs to not
> crash on save) onto the target's own file, method by method — never a bulk replace.

---

## Dependencies

- **Module 01** — `ibed_ecr_item_grade` table; `subject_gradessetup` component
  columns (`components_json`, `input_mode`); `gradesdetail` component columns
  (`cg1..cg4`, `transmuted_grade`, `letter_grade`) and the standard `wwtotal`/
  `pttotal`/`qatotal`/`ig`/`qg`.
- **Module 05** — `IBEDGradingDefaults` (period resolution + `componentsFromSetup`,
  `inputModeFromSetup`) and `IbedGradeEquivalency` (transmutation for QG). The
  dynamic controller `use App\Support\IBEDGradingDefaults;`.
- **Module P2** — SHS must be term-plotted for `is_term_mode` to be true.
- Standard tables: `sh_classsched` (SHS), `classsched` (JHS), `subject_plot`,
  `sh_cluster_plot`, `grades`, `gradesdetail`, PhpSpreadsheet for Excel I/O.

---

## Routes

```php
Route::get('/teacher/schedule', 'SuperAdminController\TeacherECRController@schedule');
Route::get('/ecr/download', 'SuperAdminController\TeacherECRController@download_ecr');   // static quarter + v2 term
Route::post('/ecr/upload', 'SuperAdminController\TeacherECRController@upload_ecr');
Route::get('/ecr/view', 'SuperAdminController\TeacherECRController@view_ecr');
Route::get('/ecr/check-ibed', 'SuperAdminController\TeacherECRController@checkHasIbedComponents');

// Dynamic / component ECR (new controller)
Route::get('/ibed-ecr/download', 'SuperAdminController\IBEDECRController@download');
Route::post('/ibed-ecr/upload', 'SuperAdminController\IBEDECRController@upload');
Route::get('/ibed-ecr/view', 'SuperAdminController\IBEDECRController@view');
Route::post('/ibed-ecr/save-scores', 'SuperAdminController\IBEDECRController@saveScores');
```

(`/ecr/downloadv2` in the blade is `/ecr/download` with a `v2` suffix handled by
`download_ecr`; keep the reference's own routing convention.)

---

## Gate 1 — `hasIbedComponents()` (dynamic vs static)

Copy verbatim into `TeacherECRController`. Returns true only when the class's
grading setup has a non-empty `components_json` in `component_scores` mode **and**
no conflicting legacy scores exist (the old-data tie-breaker). Source of truth for
the setup is the *schedule's* `grading_percentage_id`, then `subject_plot`.

```php
public static function hasIbedComponents($levelid, $subjid, $syid, $sectionid = null, $semid = null, $isCluster = false, $quarter = null)
{
    // Cluster elective subjects: setup lives on sh_cluster_plot.gradingsetupid.
    // $sectionid here is actually the clusterplotid (set by the schedule builder).
    if ($isCluster && $sectionid) {
        $clusterPlot = DB::table('sh_cluster_plot')
            ->where('id', $sectionid)->where('deleted', 0)
            ->whereNotNull('gradingsetupid')->first();
        if (!$clusterPlot) { return false; }

        $setup = DB::table('subject_gradessetup')
            ->where('id', $clusterPlot->gradingsetupid)->where('deleted', 0)
            ->select('components_json', 'input_mode')->first();

        if (!$setup) return false;
        if (($setup->input_mode ?? 'component_scores') !== 'component_scores') return false;
        return !empty($setup->components_json) && $setup->components_json !== '[]';
    }

    // SHS sections: the schedule's grading_percentage_id is the source of truth.
    $setup = null;
    if ($sectionid && in_array((int) $levelid, [14, 15], true)) {
        $q = DB::table('sh_classsched')
            ->join('subject_gradessetup', function ($j) {
                $j->on('sh_classsched.grading_percentage_id', '=', 'subject_gradessetup.id')
                  ->where('subject_gradessetup.deleted', 0);
            })
            ->where('sh_classsched.syid', $syid)
            ->where('sh_classsched.glevelid', $levelid)
            ->where('sh_classsched.sectionid', $sectionid)
            ->where('sh_classsched.subjid', $subjid)
            ->where('sh_classsched.deleted', 0);
        if ($semid) { $q = $q->where('sh_classsched.semid', $semid); }
        $setup = $q->select('subject_gradessetup.components_json', 'subject_gradessetup.input_mode')->first();
    } elseif ($sectionid) {
        // JHS/elementary: classsched (no sh_ prefix, no semester column).
        $setup = DB::table('classsched')
            ->join('subject_gradessetup', function ($j) {
                $j->on('classsched.grading_percentage_id', '=', 'subject_gradessetup.id')
                  ->where('subject_gradessetup.deleted', 0);
            })
            ->where('classsched.syid', $syid)
            ->where('classsched.glevelid', $levelid)
            ->where('classsched.sectionid', $sectionid)
            ->where('classsched.subjid', $subjid)
            ->where('classsched.deleted', 0)
            ->select('subject_gradessetup.components_json', 'subject_gradessetup.input_mode')->first();
    }

    // Fall back to subject_plot for K-12 or when no schedule setup is found.
    if (!$setup || !$setup->components_json) {
        $setup = DB::table('subject_plot')
            ->join('subject_gradessetup', function ($j) {
                $j->on('subject_gradessetup.id', '=', 'subject_plot.gradessetup')
                  ->where('subject_gradessetup.deleted', 0);
            })
            ->where('subject_plot.syid', $syid)
            ->where('subject_plot.levelid', $levelid)
            ->where('subject_plot.subjid', $subjid)
            ->where('subject_plot.deleted', 0)
            ->select('subject_gradessetup.components_json', 'subject_gradessetup.input_mode')->first();
    }

    if (!$setup) { return false; }
    if (($setup->input_mode ?? 'component_scores') !== 'component_scores') { return false; }
    if (empty($setup->components_json) || $setup->components_json === '[]') { return false; }

    // Old-data tie-breaker: components_json is configured, but if the class already
    // has legacy scores in gradesdetail (wwtotal/pttotal/qatotal > 0), keep it on the
    // static ECR until re-uploaded via the dynamic ECR (which writes ibed_ecr_item_grade
    // and flips this check). $quarter scopes the check to the rendered quarter's header.
    if ($sectionid && Schema::hasTable('ibed_ecr_item_grade')) {
        $headerIds = DB::table('grades')
            ->where('syid', $syid)->where('levelid', $levelid)
            ->where('sectionid', $sectionid)->where('subjid', $subjid)->where('deleted', 0)
            ->when(in_array((int) $levelid, [14, 15], true) && $semid, fn ($q) => $q->where('semid', $semid))
            ->when($quarter !== null, fn ($q) => $q->where('quarter', $quarter))
            ->pluck('id');

        if ($headerIds->isNotEmpty()) {
            $hasNewData = DB::table('ibed_ecr_item_grade')
                ->whereIn('grades_id', $headerIds)->where('deleted', 0)->exists();
            if ($hasNewData) { return true; }

            // A zero total is not real data (TeacherGradingV2 seeds rows with 0 on open),
            // so only a positive total counts as a legacy score worth protecting.
            $hasOldData = DB::table('gradesdetail')
                ->whereIn('headerid', $headerIds)
                ->where(function ($q) {
                    $q->where('wwtotal', '>', 0)->orWhere('pttotal', '>', 0)->orWhere('qatotal', '>', 0);
                })->exists();
            if ($hasOldData) { return false; }
        }
    }

    return true; // components configured, no conflicting old data — use dynamic ECR
}
```

`checkHasIbedComponents(Request)` exposes this per-quarter to the frontend (route
`/ecr/check-ibed`) so download/upload buttons re-check for the *selected* quarter
before wiring up — because the schedule list computes the flag once per class
(no `$quarter`).

---

## Gate 2 — `is_term_mode` stamping (in `schedule()`)

`TeacherECRController@schedule` builds each row's `terms[]` + `is_term_mode` +
`has_ibed_components`. The resolution order (from this session's work):

- **SHS (14/15):** `resolveShsPeriods()` is authoritative — its `isTermMode`
  result stands. **Do not** fall back to `resolveActiveTerms` for SHS (that would
  find a config and wrongly stamp `is_term_mode=1` for a semester-plotted level).
- **Junior:** if no SHS periods, fall back to `resolveActiveTerms()`; a resolved
  config ⇒ `is_term_mode=1`.

```php
$schedItem->terms         = $termCache[$cacheKey];
$schedItem->is_term_mode  = $termCache[$cacheKey] ? 1 : 0;
$schedItem->has_ibed_components = self::hasIbedComponents(
    $schedItem->levelid, $schedItem->subjid, $syid,
    $schedItem->sectionid ?? null, $schedItem->semid ?? null,
    !empty($schedItem->is_cluster)
) ? 1 : 0;
```

Copy the full `schedule()` from the reference; the SHS-vs-junior fallback guard is
the key bit to preserve.

---

## Dynamic ECR — `IBEDECRController` (new file, copy verbatim)

Item-level, sub-component-aware Class Record. Its header docblock is the spec — read it.

**`components_json`** (3-level): component → sub_components → items, each component
a `{name, short_code, percentage}`; optional per-sub `percentage` switches PS from
pooled to weighted-average.

**Endpoints:**

| Method | Route | Purpose |
|--------|-------|---------|
| `download(Request)` | GET `/ibed-ecr/download` | Builds the Excel workbook — one sheet per configured **term** for the current semester (SHS split), item columns per component/sub/item, locked info rows, unlocked score cells, and Excel formulas for Total/PS/WS/IG/QG (QG via VLOOKUP on a hidden transmutation sheet). |
| `upload(Request)` | POST `/ibed-ecr/upload` | Parses the workbook, **re-computes everything server-side** from item scores, and persists. |
| `view(Request)` | GET `/ibed-ecr/view` | Read-only render + grade status (last upload, submitted, etc.). |
| `saveScores(Request)` | POST `/ibed-ecr/save-scores` | Inline per-item score save (teacher-portal entry path). |

**Storage model — dual write:**

1. **`ibed_ecr_item_grade`** — one row per `(grades_id, studid, component_code,
   sub_component_code, item_index)` with the raw item `score`. **HPS (max scores)
   are stored as rows with `studid = 0`.** This is the authoritative per-item store
   the dynamic viewer reads back.
2. **`gradesdetail`** (+ `grades` header) — the computed aggregates for
   backwards-compatibility: `wwtotal/pttotal/qatotal`, component columns
   (`cg1..cg4`), `ig`, `qg`, `transmuted_grade`, `letter_grade`. This keeps every
   legacy consumer (report cards, evaluation, master sheets) working unchanged.

**Computation chain** (Excel formulas, re-verified server-side on upload):
`Total = SUM(items)` → `PS = Total/HPS_Total*100` → `WS = PS*weight%/100` →
`IG = SUM(WS)` → `QG = VLOOKUP(IG, transmutation)`.

**`view()` needs its own blade partial — `superadmin.pages.teacher.ibed_gradeview.blade.php`
— copied separately.** It's easy to find `IBEDECRController.php` already present in a
target repo (e.g. copied in a prior pass, or by someone else) and assume the module is
done, but the controller compiling/existing says nothing about whether its `view()`
blade exists — a missing view fails at render time (`InvalidArgumentException: View
[...] not found`), not at parse time, so it won't show up in a static grep for the
controller's own symbols. Copy the partial verbatim (it's self-contained: no
`@extends`, and its only hardcoded endpoints — `/ibed-ecr/save-scores` and
`/gradesSubmit/{quarter}` — are routes this module already wires or that already
exist). See known-pitfalls #14.

> **`/gradesSubmit/{quarter}` "already exists" is not the same as "already
> term-mode-aware."** In `sjhsli_online` this endpoint (`TeacherControllers\
> FilterController::updateGradeStatus()`) predates the port and is shared with
> the legacy WW/PT/QA page — reusing it verbatim for the dynamic ECR's Submit
> button was the right call (no duplicate endpoint needed), but its SHS branch
> hardcoded `where('semid', $semid->id)` with no term-mode gate. A term-mode
> header carries `semid = NULL`, so that filter matched nothing: the header's
> `submitted` flag never got set, the per-student `gradesdetail.gdstatus`
> bulk-update silently no-opped regardless of which checkboxes were checked,
> and an unguarded `$get_grade_id[0]->id` a few lines later threw "Undefined
> offset: 0" once the lookup came back empty. Fixed by porting es_ldcu's own
> (already term-mode-aware) implementation of this same method verbatim —
> `resolveShsPeriods()`/`resolveTermLabelsForLevel()` gate every `grades`/
> `grading_system_pending_grade` query, a missing header returns a 422 instead
> of crashing, and re-submitting no longer downgrades an already Submitted/
> Approved/Posted student. Don't assume a "generic, table-driven" legacy
> endpoint is term-mode-safe just because it takes no config-specific
> parameters — check every `semid` filter in it.

---

## Classschedule UI (`teacherinformation.blade.php`)

Feature additions to the existing screen:

1. **Quarterly / Term-Based tabs** split by `is_term_mode` (`item.is_term_mode == 1`
   ⇒ Term-Based). Badge counts per tab. **Auto-switch:** on load, if there are 0
   quarterly rows but term-based rows exist, activate the Term-Based tab (and the
   inverse) so the visible table matches the badge.
2. **Download button** routes by gate: `has_ibed_components==1` ⇒
   `/ibed-ecr/download`; else `/ecr/download` (+`v2` when `is_term_mode==1`).
3. **View / status** uses `/ibed-ecr/view` when dynamic, else the static view. Pass
   `readonly: 1` on this request from the superadmin/registrar schedule modal — the
   dynamic partial's `$readOnly` flag is what hides the teacher-portal Save/Submit
   buttons and open score inputs; without it, a superadmin's "preview" opens the
   live editable grading grid.
4. **Per-quarter re-check** via `/ecr/check-ibed` before wiring download/upload for
   the selected quarter.

Copy these handlers from the reference blade and adapt toast/layout helpers.

---

## Porting notes / gotchas

1. **Table-name split:** SHS schedules = `sh_classsched` (has `glevelid`, `semid`);
   JHS/elementary = `classsched` (no `sh_` prefix, no `semid`). Cluster electives:
   setup on `sh_cluster_plot.gradingsetupid`. `subject_plot` uses `gradessetup`.
   Match these to the target schema.
2. **Old-data tie-breaker is deliberate** (this session's fix): a class with
   positive legacy `wwtotal/pttotal/qatotal` stays on the static ECR until
   re-uploaded through the dynamic ECR — otherwise the dynamic viewer (which only
   reads `ibed_ecr_item_grade`) would render an empty sheet over real grades.
   Keep the `> 0` (not `NOT NULL`) check — rows are seeded with 0 on page open.
   **Guarantee:** a static-format class keeps the **existing grading + existing
   `gradetransmutation`**, untouched, in **both** the ECR (`/ecr/*` →
   `TeacherECRController`) and system grading (the non-component `else` branch of
   the grading grid). The dynamic path (`IBEDECRController` + `IbedGradeEquivalency`
   transmutation) applies only when `hasIbedComponents` returns true. The feature is
   additive — it never recomputes or overwrites legacy classes.
3. **`$quarter` scoping matters** — the class-wide badge computes without it, but
   the download/upload decision must pass the selected quarter (via
   `/ecr/check-ibed`) so a class that's dynamic in one quarter and static in
   another routes each correctly.
4. **Dual write is the contract** — always write both `ibed_ecr_item_grade` (incl.
   HPS at `studid=0`) **and** `gradesdetail`. Downstream modules read `gradesdetail`
   today; migrating them to the new table is future work, not a porting step.
5. **Wrap config reads with `activeConfigQuery()`** (Module 05) — `IBEDECRController`
   already filters `isactive` at its config reads; preserve that when adapting.
6. **PhpSpreadsheet** required for Excel build/parse; confirm the vendor lib exists.
7. **Formula parity:** the server re-computes PS/WS/IG/QG on upload to match the
   Excel formulas — keep both in sync if you change the layout.

---

## Verification

1. Configure a class's `subject_gradessetup` with a `components_json` (WW/PT/QA +
   items) in `component_scores` mode. On `/classschedule`, the class shows the
   dynamic path (`has_ibed_components=1`).
2. **Download** → `/ibed-ecr/download` produces a workbook with one sheet per term
   (for the semester), item columns, HPS row, and locked/unlocked cells as spec'd.
3. Enter HPS + scores, **upload** → `/ibed-ecr/upload`. Check:
   ```sql
   SELECT grades_id, studid, component_code, sub_component_code, item_index, score
     FROM ibed_ecr_item_grade WHERE deleted=0 ORDER BY grades_id, studid LIMIT 20;   -- studid=0 rows are HPS
   SELECT headerid, wwtotal, pttotal, qatotal, ig, qg, transmuted_grade FROM gradesdetail WHERE headerid IN (...);
   ```
4. **Old-data tie-breaker** — a class already graded the legacy way
   (`wwtotal>0`) shows `has_ibed_components=0` (static) until re-uploaded via the
   dynamic ECR; after a dynamic upload (`ibed_ecr_item_grade` populated) it flips to
   dynamic.
5. **Term vs quarter** — a term-mode class (Module P2 done) downloads via
   `/ecr/downloadv2` (static term) or `/ibed-ecr/download` (dynamic term); a
   quarter class via `/ecr/download`. Tabs on `/classschedule` split correctly and
   auto-switch when one side is empty.

With scores flowing into `gradesdetail`, proceed to **Module 08 — Grade-view
layout** (the shared read-only grid used by the class-schedule modal and system
grading), then **Module 09 — Final grading & master sheets**.

---

## Changelog

### 2026-09-03 — Fix term grade double-transmutation and equivalence gating

Found and fixed two paired bugs that made the same student's TERM GRADE differ
between the web Class Record / System Grading view and the downloaded Excel,
even for the exact same saved data:

1. **Write-side:** `resolveIbedGradeEquivalence()` required the matched
   equivalence row to have `apply_transmutation_to_terms = 1` when resolving
   for `$target = 'term'` — even when the scope's `ibed_term_config` already
   pointed at exactly one ruleset via `grade_point_equivalence_id`. If that
   ruleset's flag was `0` (a school can configure only one ruleset and use it
   for both term and final grades — the flag was never meant to override an
   explicit link), the lookup silently returned nothing, and
   `resolveIbedTermGrade()`/`transmuteIbedGrade()` fell back to storing the raw,
   untransmuted Initial Grade into `gradesdetail.qg`. Every fresh save/upload
   under that config saved a raw `qg` instead of a transmuted one.
2. **Display-side:** `formatIbedSavedGradeDisplay()`, `getIbedSavedGradeDescription()`,
   `getIbedSavedTransmutedGradeDisplay()`, `getIbedSavedLetterGradeDisplay()`, and
   the `view()` pass/fail color lookup all took the already-saved `qg` and ran it
   back through `findIbedEquivalencyScaleById()` — a **percent-bracket** lookup
   meant for raw scores — as if it still needed transmuting. A `qg` that was
   already correctly transmuted (e.g. `86`) got bucketed into a *different*
   band on the second pass (e.g. `91`), a silent double-transmutation.
   These two bugs partially masked each other for freshly-written rows (a raw
   `qg` run through the display bug's redundant lookup landed back on the
   correct number by coincidence), which is why the corruption wasn't obvious
   from the UI alone — confirmed against live data mid-investigation.

Also fixed while auditing the same function: an equivalence with no scope
columns set (e.g. `acadprogid = levelid = semid = null`) was previously reachable
by *any* level/program in the school year via a school-wide scope-fallback
search — proven live: an unrelated grade-school level with **no term config at
all** was already inheriting the school's one configured equivalence for its
FINAL grade. `resolveIbedGradeEquivalence()` no longer has that fallback:
**a level's own `ibed_term_config.grade_point_equivalence_id` link is now the
single source of truth** — no config for the scope, or a config that leaves
the link null, means that level's term grade stays fully raw, full stop.

**Files touched:**

| File | Change |
|------|--------|
| `app/Http/Controllers/SuperAdminController/IBEDECRController.php` | `resolveIbedGradeEquivalence()` rewritten (55 ins / 83 del); 5 call sites switched from `findIbedEquivalencyScaleById()` to `findIbedScaleByTransmutedGrade()`. |

**What changed — by method:**

| Method | What |
|--------|------|
| `resolveIbedGradeEquivalence()` | Dropped the `apply_transmutation_to_terms` JOIN condition entirely — a config-linked equivalence now resolves regardless of the flag. Dropped the whole second-half "scope fallback" query (the `ibed_grade_point_equivalence`-direct, NULL-as-wildcard search) — if the config-join finds nothing, the function now returns `null` immediately instead of trying a broader, unscoped match. `$target` param kept for call-site compatibility but no longer affects resolution (a config's chosen ruleset applies to both `'term'` and `'final'`). |
| `view()` (`$gradeDisplays[...]['failed']` scale lookup, ~line 1276) | `findIbedEquivalencyScaleById((float)$qg, ...)` → `findIbedScaleByTransmutedGrade((float)$qg, $syid, $levelid, $semid, 'term')`. |
| `formatIbedSavedGradeDisplay()` | Same swap — now matches `$grade` (the saved `qg`) against `transmuted_grade`, not against a percent bracket. |
| `getIbedSavedGradeDescription()` | Same swap. |
| `getIbedSavedTransmutedGradeDisplay()` | Same swap. |
| `getIbedSavedLetterGradeDisplay()` | Same swap. |

**Not touched (intentionally correct already):** `formatIbedFinalGradeDisplay()` /
`transmuteIbedFinalGrade()` still use `findIbedEquivalencyScaleById()` — they
receive a genuinely raw, un-transmuted Final Grade (the average of term `qg`s),
so a percent-bracket lookup is the right operation there. `resolveIbedEcrLookupRows()`
(the Excel `TransData` sheet / JS live-calculator source) and `findIbedScaleByTransmutedGrade()`
itself were already correct and needed no changes — they're the reference
pattern the other five call sites now follow.

**Verified against the live database** (via reflection, no synthetic data):
write-side transmutation for the SHS scope now returns the correct transmuted
grade instead of the raw one; display-side on an already-transmuted `qg=86`
now returns `86`/`VS`/`Very Satisfactory` instead of `91`/`O`/`Outstanding`; an
unrelated level with no term config now resolves `null` for both `term` and
`final` (previously `final` alone leaked the school-wide equivalence); the SHS
scope's own config-linked equivalence still resolves correctly. A follow-up
dry-run audit across all 8 scopes with scored data (1,351 rows) found exactly
**one** row already corrupted by the write-side bug in this school's data —
the fix does not retroactively repair it; a separate data backfill is still
needed for rows saved while the bug was live.

**Porting note:** controller-only, no routes/views/migrations. Any other
controller or Support helper that independently resolves a Grade Point
Equivalence should be checked for the same two anti-patterns: (1) gating a
config-linked ruleset on `apply_transmutation_to_terms`, and (2) running an
already-transmuted value back through a percent-bracket scale lookup instead
of a transmuted-value lookup. `App\Support\IbedGradeEquivalency::resolveEquivalence()`
already avoids anti-pattern (1) (documented in its own comments) but was never
wired into this controller's write path — this fix makes `IBEDECRController`'s
own `resolveIbedGradeEquivalence()` follow the same rule independently rather
than delegating to it.

### 2026-09-02 — Live-calculating summary sheet + pass/fail cell shading

The downloaded dynamic ECR's summary sheet was a static download-time snapshot:
term columns copied from `gradesdetail.qg`, FINAL GRADE / REMARK computed in
PHP and written as plain values. It now recalculates inside Excel. Term columns
are cross-sheet formulas that read each student's live TERM GRADE off the term
sheets; FINAL GRADE is an Excel formula (average / configured formula /
cumulative, **never** transmuted); REMARK is `PASSED` / `FAILED` from the
matched Grade Equivalency band's *Failed* toggle; and the term-grade cells plus
the final-grade cell are shaded red (failing) / green (passing) with
conditional formatting on **both** the summary sheet and the individual term
sheets. Also fixes the summary's grade-header query so term-graded Grade 11/12
classes (headers on `semid = NULL`) resolve at all.

**Files touched:**

| File | Change |
|------|--------|
| `app/Http/Controllers/SuperAdminController/IBEDECRController.php` | TransData gains an `is_failed` column; `buildSummarySheet()` takes `$sheetContext` and emits live INDEX/MATCH + formula cells; 6 new private helpers; conditional formatting on summary + term sheets; `semid` header-query fix. |

**What changed — by area:**

| Area | Detail |
|------|--------|
| **TransData sheet** | New **column F `is_failed`** (0/1), written from each lookup row's `is_failed`. Sheet is now `A=gfrom, B=transmuted, C=grade_point, D=letter, E=remarks, F=is_failed`. |
| **Summary term columns** | Per student row: `=IFERROR(INDEX('<Term Sheet>'!$<TG>$12:$<TG>$N, MATCH($AD<row>, '<Term Sheet>'!$<HID>$12:$<HID>$N, 0)), "")` — matches the student by id in the term sheet's hidden column (rows 12..N only, skipping the row-6 meta cell). A hidden **column AD** on the summary holds each student's id as the MATCH key. `INDEX/MATCH` not `VLOOKUP` because TG sits left of the id column. Falls back to the old `qgMap` snapshot only if `$sheetContext` is absent. |
| **Summary FINAL GRADE** | `=IF(COUNT(<term cells>)=<N>, ROUND(<expr>,2), "")` where `<expr>` mirrors `computeFinalGrade()`: cumulative weighted chain (`cumulative_prev_weight`/`cumulative_curr_weight`, default 40/60), else the configured formula code (`$q1`→term cell, arithmetic-only whitelist, else falls back to AVERAGE), else `AVERAGE`. **No transmutation** — the plain number. |
| **Summary REMARK** | `=IF(COUNT(...)=<N>, IF(VLOOKUP(final, TransData!$B$2:$F$N, 5, TRUE)=1,"FAILED","PASSED"), "")`. Matches the **transmuted column (B)** because term grades are transmuted values; matches the **percent band (A)**, `is_failed` col 6, when `term_grade_display = 'raw'`. Blank when no equivalency. |
| **Pass/fail shading** | Conditional formatting, two mutually-exclusive `CONDITION_EXPRESSION` rules per range: `AND(ISNUMBER(x), IFERROR(VLOOKUP(x, <range>, <idx>, TRUE),0)=1)` → fill `FFFFC7CE` (red); `...<>1` → `FFC6EFCE` (green). Applied to the summary's term columns + FINAL GRADE column, and to each term sheet's TERM GRADE column (rows 12..lastRow). |
| **`semid` fix** | Summary's `grades` lookup changed from `where('semid', $semid)` to `where('semid', $semid)->orWhereNull('semid')` for levelid 14/15 — now identical to the term-sheet header query, so a term-graded G11/12 class (headers stored on `semid NULL`) is found. |
| **New helpers** | `ibedEcrTermSheetTitle()` (shared sheet-title sanitiser), `ecrFillCondition()`, `applyEcrPassFailShading()`, `ecrPassFailLookup()`, `ibedSummaryFinalFormulaTemplates()`, `findIbedScaleByTransmutedGrade()`. Term-sheet hidden id cell is now written as `(int)` so the summary's `MATCH` lands on a numeric key. |

**Porting note:** controller-only — no routes, views, migrations, or Support-class
changes. Needs PhpSpreadsheet's `Style\Conditional` (already available on 1.x).
The ECR **upload** parser is unaffected: it locates sheets by the hidden row-6
meta cell, never by name, and never reads the summary or TransData sheets. All
new summary/CF behaviour requires `$sheetContext` to be passed from
`downloadIbedEcr()` (it always is) and a configured Grade Equivalency with scale
rows; otherwise the sheet falls back to the static snapshot with no shading.

### 2026-09-02 — Term-aware summary sheet name & banner title

The downloaded dynamic ECR workbook's summary sheet was hardcoded to
`SUMMARY OF QUARTER GRADES` (tab) / `Summary of Quarterly Grades` (banner),
even on a genuine 3-term ECR whose per-term column headers already read
`FIRST TERM` / `SECOND TERM` / `THIRD TERM`. `buildSummarySheet()` now takes an
`$isTermMode` flag and picks the wording to match the term sheets. Cosmetic
only — no data, formulas, or layout change.

**Files touched:**

| File | Change |
|------|--------|
| `app/Http/Controllers/SuperAdminController/IBEDECRController.php` | `buildSummarySheet()` gains a `bool $isTermMode = false` param; the `downloadIbedEcr()` call site passes the existing `$isTermMode`; tab title and `writeEcrTemplateHeader()` banner string become conditional. |

**What it does** — when `$isTermMode` is true (`isGenuineIbedTermMode()` — a
resolved term config with a term count ≠ 4), the summary sheet is titled
`SUMMARY OF TERM GRADES` and its banner reads `Summary of Term Grades`;
otherwise it stays `SUMMARY OF QUARTER GRADES` / `Summary of Quarterly Grades`.
The same `$isTermMode` value already drives the `TERM GRADE` vs `Quarterly Grade`
column label in `buildIbedEcrOutputColumns()`, so the whole workbook is now
consistent. Column headers were already term-aware (`strtoupper($term->description)`).

**Porting note:** controller-only, one method signature + one call site + two
conditional strings. No routes, views, or migrations. Safe for re-upload — the
ECR upload parser (`saveScores()`) locates sheets by a hidden meta cell on row 6,
not by sheet name, so renaming the summary tab does not affect parsing. Default
`false` keeps 4-quarter ECRs byte-identical.

### 2026-09-02 — Drop legacy gradetransmutation fallback in dynamic ECR term path

Removed the fallback to the legacy `gradetransmutation` table from the dynamic
ECR's term-grading path. Previously, when no Grade Point Equivalence was
configured for a scope (SY + level + semester), the ECR silently fell back to
the static DepEd transmutation table — mixing the legacy path into the dynamic
pipeline and violating **Invariant #5** (additive & non-destructive: dynamic/term
classes use `IbedGradeEquivalency`, static/legacy classes use
`gradetransmutation`, and the two never cross). Now, when no equivalence
resolves, the ECR emits a single raw **TERM GRADE** column showing the Initial
Grade as-is, with no transmutation applied.

**Files touched:**

| File | Change |
|------|--------|
| `app/Http/Controllers/SuperAdminController/IBEDECRController.php` | 4 call sites + 2 removed methods + 1 changed method signature (43 ins, 73 del) |

**What changed — by method:**

| Method | What |
|--------|------|
| `downloadIbedEcr()` (~line 199) | Moved `resolveIbedEcrLookupRows()` call **before** `buildIbedEcrOutputColumns()` so the empty-lookup flag is available early; passes `!empty($lookupRows)` as the new `$hasEquivalence` parameter. |
| `showGrades()` (~line 1164) | Same reorder — `$lookupRows` resolved first, `$hasIbedEquivalence` flag drives both `$showDescriptionColumn` (suppressed when no equivalence) and `$ecrOutputColumns`. |
| `saveScores()` (~line 1399) | Added `$hasIbedEquivalence` check so the upload's column map mirrors the download's layout (no VLOOKUP columns when no equivalence). |
| `buildIbedEcrOutputColumns()` (~line 2484) | New `bool $hasEquivalence = true` parameter. When false, returns a single `['key'=>'transmuted', 'label'=>$transmutedLabel, 'raw'=>true]` column — no letter, grade point, or descriptor columns (they have no data source without a scale). |
| `resolveIbedEcrLookupRows()` (~line 2580) | **Removed** the `gradetransmutation` fallback branch. Now returns `[]` when no Grade Point Equivalence is configured (was: fell back to the legacy 60-row DepEd table). |
| `transmuteIbedGrade()` (~line 2598) | **Removed** the `$this->transmute($grade)` fallback. Now returns `round($grade, 2)` when no equivalence row matches — the raw Initial Grade, not a legacy-transmuted value. |
| `resolveIbedTransmutationRows()` | **Deleted entirely** — was only used by the removed fallback path. |
| `transmute()` | **Deleted entirely** — the legacy `gradetransmutation` VLOOKUP helper, no longer called from the dynamic ECR. |

**Porting note:** this is a controller-only change — no routes, views, migrations,
or Support-class changes. Copy the updated `IBEDECRController.php` (or apply the
4 call-site changes + 2 method deletions + 1 signature change manually). The
legacy `gradetransmutation` table itself is **not** touched or dropped — it remains
in use by the static/quarter grading pipeline (`TeacherGradingV2`, grade views).
The change enforces that the dynamic ECR term path never reaches into it.
