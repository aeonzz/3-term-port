# Module P3 — SHS Cluster Plotting (term conversion)

The **cluster-plotting counterpart of P2**. Where P2 converts per-subject
`subject_plot` rows, this converts **clustered** SHS setups
(`sh_cluster_plot` / `sh_cluster_subject_picking`) from semester-based plotting to
**whole-year** so `shsHasTermPlotting()` can turn the level into term mode. It's the
"Convert Term Setup" flow on the SHS Cluster Plotting screen.

- **Screen:** `/setup/subject/shs-cluster-plotting` (superadmin) and
  `/principal/setup/subject/shs-cluster-plotting` (principal) — same controller.
- **Controller:** `SuperAdminController\SHSClusterPlottingController` (`index`,
  `termConversionPreview`, `termConversionConvert`).

This is a **superadmin/principal setup surface** (consumed by Module 05; a peer of
P2). It **augments** the existing cluster-plotting screen — it does not reimplement
clustering.

## Goal — what this port must achieve

After this port, an admin can take a cluster-plotted SHS level to **whole-year term
plotting** from the cluster screen, with a **preview** of exactly what will change
before committing. Concretely:

1. **A "Convert Term Setup" preview** (`termConversionPreview`) that reports the
   level's real state — configured terms + how many cluster plots / picking rows are
   still semester-stamped vs already whole-year — so nothing is a surprise.
2. **One-click conversion** (`termConversionConvert`) that flips every semester-stamped
   `sh_cluster_plot` **and** `sh_cluster_subject_picking` to whole-year
   (`semid = NULL`, old value saved in `prev_semid`, `sh_cluster_plot.termid = NULL`)
   — so `shsHasTermPlotting` turns true and the level enters term mode everywhere.
3. **A term map on the page** (`$shsClusterTermMap`) so the UI knows, per SY/level,
   which levels are term-configured and can render the cluster grid term-aware
   (`cpIsTermMode`).
4. **Schema safety** — the convert only touches columns that exist
   (`Schema::hasColumn` guards on `sh_cluster_plot.prev_semid`,
   `sh_cluster_subject_picking.prev_semid`); nothing runs half-wired.
5. **No junior-level impact** — the routes validate `levelid in [14,15]`.

**Acceptance criteria (all must hold):**

- [ ] The **Convert Term Setup** modal previews configured terms + counts
      (semester plots, whole-year plots, term-specific, picking/teacher/schedule rows).
- [ ] **Convert to Term Setup** → every semester-stamped `sh_cluster_plot.semid` and
      `sh_cluster_subject_picking.semid` becomes `NULL`; `sh_cluster_plot.termid = NULL`;
      old values saved in `prev_semid`.
- [ ] After convert, `shsHasTermPlotting($syid, levelid)` is true (combined with P2 if
      the level also has per-subject plots) and the level shows Term-Based downstream.
- [ ] **Period filter** swaps to **Term** (label + configured terms) for a
      term-configured SHS level, and back to **Semester** otherwise.
- [ ] Plotting a cluster subject in term mode stores `sh_cluster_plot.semid = NULL` +
      the chosen `termid`.
- [ ] A teacher assigned to specific terms (1T/2T/3T) creates one
      `sh_cluster_plot_teacher` row per term (`quarter` = term_no).
- [ ] **Plot Whole Section** assigns the section (`sh_cluster_section_assignment`) and
      auto-picks its enrolled students into `sh_cluster_subject_picking`
      (`source_section_assignment_id` set); unplotting removes exactly those.
- [ ] A level with **no term config** shows the preview as *not ready* (no terms) — no
      conversion offered.
- [ ] Junior levels / non-14-15 requests are rejected by validation.
- [ ] Convert refuses / degrades safely if the `prev_semid` columns are missing.

> **Report back after applying (do this in chat).** When the port is done, post the
> acceptance criteria / changes as a **ticked checklist** — **✅** applied and verified,
> **✔️** code applied but runtime/live-page test still pending, **⬜** skipped or not
> applicable (say why). Never mark ✅ something you didn't apply; prefer ✔️ when you
> only lint/compile-verified. List the changes too, e.g.:
>
> - ✅ Routes (`term-conversion/preview`, `term-conversion/convert`)
> - ✅ `SHSClusterPlottingController` (`termConversionPreview`, `termConversionConvert`, `index` term map)
> - ✅ Blade "Convert Term Setup" modal + `SHS_CLUSTER_TERM_MAP` / `cpIsTermMode`

## Behaviors by level / config state

| Level / config state | Preview (`termConversionPreview`) | After convert | `shsHasTermPlotting` |
|----------------------|-----------------------------------|---------------|:--------------------:|
| **Non-SHS / not 14-15** | request rejected (`in:14,15`) | — | n/a |
| **SHS, no term config** | `ready:false` (no terms) — nothing to convert | — | false |
| **SHS, term config, cluster plots semester-stamped** | `ready:true`, `semester_plots > 0` | plots + picking → `semid NULL`, `termid NULL` | false → **true** |
| **SHS, term config, already whole-year** | `ready:true`, `semester_plots = 0` | nothing to change | **true** |
| **SHS, 4-quarter-shaped config** | Excluded from the term map (`count !== 4`) — page stays on semester mode | — | unchanged |

### The 4-quarter ("Q4-shaped") config

A config with exactly 4 terms just re-describes the standard 4 quarters — it's not a
genuine term restructuring. The term map (`$shsClusterTermMap`) excludes it with a
`count($cfg['terms']) !== 4` guard, matching the subject-plot page (P2). This means the
cluster-plotting page stays on the semester dropdown for 4-quarter configs. The
`termConversionPreview` and `termConversionConvert` endpoints still use
`shsConfiguredTerms()` without this guard — a deliberate choice so `bulkTermStatus`
reports the real plotted state — but the UI won't offer the term controls.

## Symptoms it fixes

- A clustered SHS level has a term config but its cluster plots are still
  semester-stamped, so `shsHasTermPlotting` stays false and the level never enters
  term mode — with no cluster-side tool to convert them.
- No preview of what a cluster conversion will touch before committing.

## Reference implementation

| Piece | Path / symbol |
|-------|---------------|
| **Source of truth** | `es_ldcu` (this repo); diff against `../es_bcc` for newer behavior |
| Controller | `app/Http/Controllers/SuperAdminController/SHSClusterPlottingController.php` → `index` (builds `$shsClusterTermMap`), `termConversionPreview`, `termConversionConvert` |
| View | `resources/views/superadmin/pages/setup/shs-cluster-plotting/index.blade.php` (Convert Term Setup modal + `SHS_CLUSTER_TERM_MAP` / `cpIsTermMode` JS) |
| Resolvers | `IBEDGradingDefaults::shsConfiguredTerms`, `shsHasTermPlotting` (Module 05) |

## Dependencies

- **Module 01** columns/table: `sh_cluster_plot.termid`, `sh_cluster_plot.prev_semid`,
  `sh_cluster_subject_picking.prev_semid`, `sh_cluster_section_assignment` (table).
- **Module 05** resolver Support classes present.
- **P2** is the per-subject sibling; a level may need **both** (per-subject plots and
  cluster plots) whole-year before `shsHasTermPlotting` is fully true.
- Standard cluster tables: `sh_cluster_plot`, `sh_cluster_plot_teacher`,
  `sh_cluster_plot_schedule`, `sh_cluster_subject_picking`.

> **Reference-repo drift (found porting to sjhsli_online, 2026-08-27):** the current
> es_ldcu `termConversionPreview`/`termConversionConvert` also call a private
> `clusterGradeHeaderRealignment($syid, $levelid, $userId=null, $now=null, $apply=false)`
> helper — **not previously documented here**. A cluster elective's `grades` header
> row carries the plot id in `grades.sectionid`; when a plot moves to whole-year
> (`semid` cleared) its existing semester-stamped grade headers are left orphaned on
> the old semester unless realigned too. The helper, in both preview (`$apply=false`,
> just counts) and convert (`$apply=true`) modes: for each cluster plot, finds
> `grades` rows matching `syid/levelid/sectionid=plot.id/subjid=plot.subjectid` with
> `semid` still set; skips (counts as `skipped`) any that would clash with an
> existing whole-year header for the same `quarter`; otherwise clears `semid` (and on
> apply, updates `updatedby`/`updateddatetime`). Preview surfaces this as
> `grade_headers_to_update` / `grade_header_conflicts` (rendered in the modal as
> "Grade headers to realign"); convert's response message includes the realigned/kept
> counts. **Port this helper too** — see Change 3 below. Also note: the `index()`
> `$shsClusterTermMap` snippet in Change 4 was missing the `id` key on each term
> entry, even though Change 5b's JS reads `t.id` for the option value — always
> include `'id' => $term['id']` alongside `term_no`/`label`.

---

## Files to check & update

| # | File | Symbol / region | Change |
|---|------|-----------------|--------|
| 1 | *(Module 01)* migration | `sh_cluster_plot.termid/prev_semid`, `sh_cluster_subject_picking.prev_semid`, `sh_cluster_section_assignment` | Ensure present |
| 2 | `routes/web.php` | cluster term routes | Add `term-conversion/preview`, `term-conversion/convert` |
| 3 | `SHSClusterPlottingController.php` | `termConversionPreview`, `termConversionConvert` | Add the methods |
| 4 | `SHSClusterPlottingController.php` | `index` | Build `$shsClusterTermMap` and pass to the view |
| 5 | `shs-cluster-plotting/index.blade.php` | "Convert Term Setup" modal + JS | Add the modal, `SHS_CLUSTER_TERM_MAP`, `cpIsTermMode` |
| 5b | `shs-cluster-plotting/index.blade.php` | **period filter** (`#cpSemesterFilter`, `#cpPeriodFilterLabel`) | Swap Semester→Term for term-configured levels (Change 5b) |
| 6 | `modals/cluster-plot-modal.blade.php` + `create`/`update` | plot semid/termid, **per-teacher term checkboxes**, **Plot Whole Section** | Term-aware modal (Change 6) |
| 7 | `SHSClusterPlottingController.php` + `routes/web.php` | `assignSection`/`unassignSection`/`listSectionAssignments`/`sectionsForLevel` + `sh_cluster_section_assignment` | Section→elective auto-pick (Change 6c) |

---

## PREFLIGHT — check the repo FIRST (do not skip)

```bash
cd <repo-root>
CC=app/Http/Controllers/SuperAdminController/SHSClusterPlottingController.php
V=resources/views/superadmin/pages/setup/shs-cluster-plotting/index.blade.php

# controller methods (APPLIED if printed):
grep -n "function termConversionPreview" "$CC"
grep -n "function termConversionConvert" "$CC"
grep -n "shsClusterTermMap"              "$CC"

# routes:
grep -n "term-conversion/preview\|term-conversion/convert" routes/web.php

# blade UI:
grep -n "SHS_CLUSTER_TERM_MAP\|termConversionModal\|Convert Term Setup" "$V"

# schema (DB): SHOW COLUMNS FROM sh_cluster_plot LIKE 'prev_semid';  -- must exist
#              SHOW COLUMNS FROM sh_cluster_subject_picking LIKE 'prev_semid';
```

**Decision rule:** each symbol that prints is already applied → skip it. If the
`sh_cluster_*` `prev_semid` columns or `sh_cluster_section_assignment` are missing, do
**Module 01** first. If `shsConfiguredTerms` / `shsHasTermPlotting` are missing, do
**Module 05** first. Read the enclosing code before editing; adapt if diverged.

> ⚠️ **Cluster table names are literal:** `sh_cluster_plot` (has `semid`, `termid`,
> `prev_semid`, `gradingsetupid`), `sh_cluster_subject_picking` (has `semid`,
> `prev_semid`), `sh_cluster_plot_teacher`, `sh_cluster_plot_schedule`. Confirm against
> the target schema. Only SHS levels 14/15 apply.

---

## Change 2 — Routes

```php
Route::get('/cluster-plot/term-conversion/preview', 'SuperAdminController\SHSClusterPlottingController@termConversionPreview');
Route::post('/cluster-plot/term-conversion/convert', 'SuperAdminController\SHSClusterPlottingController@termConversionConvert');
```

(The screen itself is already routed at `/setup/subject/shs-cluster-plotting` and
`/principal/setup/subject/shs-cluster-plotting`.)

## Change 3 — Controller methods

### `termConversionPreview(Request)` — GET `…/term-conversion/preview?syid=&levelid=`

Validates `levelid in [14,15]`. Reads `shsConfiguredTerms($syid,$levelid)`; returns a
JSON preview:

```json
{ "success": true, "data": {
  "ready": true,                       // has configured terms
  "config_id": 12, "terms": [ … ],
  "counts": {
    "plots_total": 11, "semester_plots": 2, "whole_year_plots": 9,
    "term_specific_plots": 0, "teacher_rows": …, "schedule_rows": …,
    "picking_rows": …, "picking_rows_with_semester": …
  }
}}
```

`ready:false` (no configured terms) → the modal shows nothing to convert.

### `termConversionConvert(Request)` — POST `…/term-conversion/convert`

Validates `levelid in [14,15]`. In a transaction, for the level's cluster plots that
are semester-stamped:

- **`sh_cluster_plot`** → `prev_semid = semid` (if the column exists), `semid = NULL`,
  `termid = NULL`.
- **`sh_cluster_subject_picking`** → `prev_semid = semid` (if the column exists),
  `semid = NULL`.

Guarded with `Schema::hasColumn` on each `prev_semid` (and `updateddatetime`/`updatedby`
where present). Copy both methods verbatim from
`SHSClusterPlottingController@termConversionPreview` / `@termConversionConvert`.

Both methods also call `clusterGradeHeaderRealignment()` (private helper, same class —
see the drift note under Dependencies above). Copy it verbatim too; without it, preview
never reports `grade_headers_to_update`/`grade_header_conflicts` and convert leaves
semester-stamped `grades` headers behind for plots that move to whole-year.

### `index()` — build the term map

Add, before rendering the view:

```php
$shsClusterTermMap = [];
foreach ($schoolYears as $syRow) {
    foreach ([14, 15] as $shsLevelId) {
        $cfg = \App\Support\IBEDGradingDefaults::shsConfiguredTerms($syRow->id, $shsLevelId);
        if (!empty($cfg['terms']) && count($cfg['terms']) !== 4) {
            $shsClusterTermMap[$syRow->id][$shsLevelId] = array_map(function ($term) {
                return ['id' => $term['id'], 'term_no' => (int) $term['term_no'], 'label' => $term['label']];
            }, $cfg['terms']);
        }
    }
}
return view('superadmin.pages.setup.shs-cluster-plotting.index', compact(/* …, */ 'shsClusterTermMap'));
```

## Change 5 — Blade "Convert Term Setup" modal + JS

Add to `shs-cluster-plotting/index.blade.php`:

- A **"Convert Term Setup"** button (`#openTermConversionModal`) and the modal
  (`#termConversionModal`) with a preview area (`#tcTerms`, `#tcSemesterPlots`,
  `#tcWholeYearPlots`, …) and a confirm button (`#confirmTermConversionBtn`).
- JS: `window.SHS_CLUSTER_TERM_MAP = @json($shsClusterTermMap ?? [])` and a
  `window.cpIsTermMode` flag the cluster grid reads to render term-aware. On modal
  open → GET `…/term-conversion/preview`; on confirm → POST `…/term-conversion/convert`,
  then reload the grid.

Copy the modal + handlers verbatim from the reference blade; adapt layout/toast helpers.

## Change 5b — Period filter for term-configured levels (`cpIsTermMode`)

This is the term-configured-level filter: **when the selected SHS level is
term-configured, the cluster page's period dropdown (`#cpSemesterFilter`) swaps its
label Semester → Term and lists the configured terms** instead of semesters. Same idea
as P1's `SEC_TERM_MAP` and P2's `#filter_term`, on the cluster screen.

**PREFLIGHT** (blade — apply only if missing):

```bash
V=resources/views/superadmin/pages/setup/shs-cluster-plotting/index.blade.php
grep -n "SHS_CLUSTER_TERM_MAP\|cpIsTermMode\|cpPeriodFilterLabel\|cpSemesterFilter" "$V"
```

**Markup** — the period filter has a swappable label + a real-semester default:

```blade
<div class="col-md-2 form-group is_senior mb-0">
    <label for="" id="cpPeriodFilterLabel">Semester</label>
    <select class="form-control select2" id="cpSemesterFilter">
        @foreach ($semester as $item)
            <option value="{{ $item->id }}" {{ $item->isactive == 1 ? 'selected="selected"' : '' }}>{{ $item->semester }}</option>
        @endforeach
    </select>
</div>
```

**JS** — on SY/level change, read `SHS_CLUSTER_TERM_MAP[syid][levelid]`; if it has
terms → **term mode** (label "Term", options = `Whole Year` + the terms); else →
**semester mode** (label "Semester", options = `CP_SEMESTERS`). Preserve the current
selection; reset to `''` when *entering* term mode.

```javascript
window.SHS_CLUSTER_TERM_MAP = @json($shsClusterTermMap ?? []);
window.CP_SEMESTERS = @json($semester);   // {id,label} — for semester mode
window.cpIsTermMode = false;

function cpApplyPeriodFilter() {
    var syid = $('#cpSchoolYearFilter').val();
    var levelid = $('#cpAcadLevelFilter').val();
    var $filter = $('#cpSemesterFilter');
    var previous = $filter.val();
    var wasTermMode = window.cpIsTermMode;
    var terms = (levelid && (window.SHS_CLUSTER_TERM_MAP||{})[syid]) ? window.SHS_CLUSTER_TERM_MAP[syid][levelid] : null;
    var nextIsTermMode = !!(terms && terms.length);
    var html = '';

    if (nextIsTermMode) {
        window.cpIsTermMode = true;
        $('#cpPeriodFilterLabel').text('Term');
        html += '<option value="">Whole Year</option>';
        terms.forEach(function (t) { html += '<option value="' + t.id + '">' + t.label + '</option>'; });
    } else {
        window.cpIsTermMode = false;
        $('#cpPeriodFilterLabel').text('Semester');
        (window.CP_SEMESTERS || []).forEach(function (s) { html += '<option value="' + s.id + '">' + s.label + '</option>'; });
    }

    $filter.html(html);
    if (nextIsTermMode && !wasTermMode) {
        $filter.val('');
    } else if (previous != null && $filter.find('option[value="' + previous + '"]').length) {
        $filter.val(previous);
    }
    $filter.trigger('change.select2');
}
```

Wire `cpApplyPeriodFilter()` to run on load and on `#cpSchoolYearFilter` /
`#cpAcadLevelFilter` change. Downstream, `cpIsTermMode` also drives: creating a cluster
plot sends `term_mode` + the chosen period, and the grade-status/period columns are
relabelled by term (`Q1..Q4` → the term labels).

> **Note:** the map is **config-only** (`shsConfiguredTerms`, built in `index()` as
> `$shsClusterTermMap`) — it lists a level's terms as soon as a config exists, so you
> can pick a term while still setting things up. The *runtime* gate
> (`shsHasTermPlotting` / `resolveShsPeriods`) still requires the cluster plots to be
> whole-year before the level is term mode everywhere. `CP_SEMESTERS` is the JS
> semester list for semester mode (add it from `@json($semester)` if not present).

---

## Change 6 — "Plot Cluster Subject" modal (term fields)

The create/edit modal (`modals/cluster-plot-modal.blade.php` + `create`/`update` +
`assignSection`) gains three term-aware behaviors when the level is in term mode
(`cpIsTermMode`). Copy the modal + handlers verbatim; the term-specific parts:

**PREFLIGHT:**
```bash
CC=app/Http/Controllers/SuperAdminController/SHSClusterPlottingController.php
M=resources/views/superadmin/pages/setup/shs-cluster-plotting/modals/cluster-plot-modal.blade.php
grep -n "function assignSection\|function unassignSection\|function pickedStudents\|shsClusterTermMode" "$CC"
grep -n "Plot Whole Section\|cpIsTermMode\|source_section_assignment" "$M" routes/web.php
grep -n "section-assignments\|sections-for-level\|picked-students" routes/web.php
```

### 6a. The plot itself is whole-year, pinned to a term

On `create`/`update`, term mode decides `semid`/`termid`:

```php
$isTermMode = $this->shsClusterTermMode($request->syid, $levelid);
// ...
'semid'  => $isTermMode ? null : $request->semid,        // whole-year in term mode
'termid' => $isTermMode ? ($request->input('termid') ?: null) : null,  // the term picked in the filter
```

So a cluster plot created in term mode is `semid NULL` + the chosen `termid` (from
`#cpSemesterFilter`), never a semester. `shsClusterTermMode()` is the cluster wrapper
around the term gate.

### 6b. Per-teacher term (the `1T / 2T / 3T` checkboxes)

In term mode, each **Teacher** row shows term checkboxes (built from
`SHS_CLUSTER_TERM_MAP` → `cpPeriods`). A teacher is stored **one row per term** in
`sh_cluster_plot_teacher`, using the existing **`quarter`** column reused as the
**term_no** (the feature-wide `quarter == term_no` convention):

```php
DB::table('sh_cluster_plot_teacher')->insert([
    'plotid'    => $newPlotId,
    'teacherid' => $t->teacherid,
    'quarter'   => $t->quarter,   // = term_no in term mode (1T→1, 2T→2, 3T→3)
    'deleted'   => 0, 'createddatetime' => $now, 'createdby' => $userId,
]);
```

This lets **different teachers teach different terms** of the same cluster subject.
When a specific term is selected in the period filter, the teacher row is **locked**
to that term (`lockedTermNo`); with the filter on "Whole Year" the checkboxes let you
pick any subset of terms. (Quarter-mode clusters keep `quarter` = the actual quarter.)

### 6c. "Plot Whole Section" — section → elective auto-pick

The **Plot Whole Section** field assigns an entire section to the elective and
auto-enrolls its students. Routes:

```php
Route::get('/cluster-plot/picked-students',       '…@pickedStudents');
Route::get('/cluster-plot/sections-for-level',    '…@sectionsForLevel');
Route::get('/cluster-plot/section-assignments',   '…@listSectionAssignments');
Route::post('/cluster-plot/section-assignments',  '…@assignSection');
Route::delete('/cluster-plot/section-assignments/{id}', '…@unassignSection');
```

> **Drift (found porting to sjhsli_online, 2026-08-27):** the reference blade's
> `getSectionMismatches()` (used by the save-time "these picked students aren't in
> the selected section" warning) calls `GET /cluster-plot/picked-students`, mapped to
> a `pickedStudents(Request)` method — **not previously listed here**. It's a
> read-only listing of everyone currently picked into a plot (individually or via a
> section assignment) with their current section, used only for that mismatch
> check. Add it alongside the other four routes/methods.
>
> ⚠️ **Route registration order.** All five of these routes are single path segments
> after `/cluster-plot/` (`picked-students`, `sections-for-level`,
> `section-assignments`) and **must be registered before**
> `Route::get('/cluster-plot/{id}', '…@show')` in the same group — Laravel matches
> routes in registration order, and `{id}` matches any single segment, so registering
> `show` first silently swallows these (e.g. `sections-for-level` resolves to
> `show('sections-for-level')` instead of `sectionsForLevel()`). The existing P2
> routes `term-conversion/preview` / `term-conversion/convert` are two segments, so
> they don't collide with `{id}` regardless of order — only the new single-segment
> Change 6c routes are at risk.

`assignSection`:
- writes a row to **`sh_cluster_section_assignment`** (`clusterplotid`, `sectionid`,
  `syid`) — the table from **Module 01**; if it's missing it returns *"Section-to-
  elective plotting is not set up yet — run the pending migration."*
- resolves the section's enrolled students via `getSectionStudentIds($syid, $semid,
  $levelid, $sectionid, $isTermMode)` — **term-aware** — and auto-picks them into
  **`sh_cluster_subject_picking`**, tagging each auto-created pick with
  **`source_section_assignment_id`** so `unassignSection` can remove exactly those.
- Guards: a section can be plotted to an elective only once, and an elective can hold
  only one section at a time.

The blade captures the section-assignment intent while editing and calls
`assignSection` / `unassignSection` for the **delta** after the plot saves
(`syncSectionAssignment`). Term mode feeds through to which students are picked.

> **Term relevance:** in term mode the plot is whole-year (`semid NULL`), so
> `getSectionStudentIds` must resolve enrolled students the whole-year way
> (`$isTermMode = true`) rather than by semester — otherwise a whole-year elective would
> pick no one. Keep the `$isTermMode` argument wired through.

---

## Porting notes / gotchas

1. **SHS-only (levels 14/15).** Both endpoints validate `in:14,15`.
2. **`Schema::hasColumn` guards** on `prev_semid` mean a target missing those columns
   won't fatal — but the undo trail won't be saved. Prefer running Module 01 first.
3. **Cluster ≠ per-subject.** This converts `sh_cluster_plot` /
   `sh_cluster_subject_picking`; **P2** converts `subject_plot`. A level using both
   needs both converted before `shsHasTermPlotting` is fully true.
4. **No separate cluster "revert" in the reference** — undo relies on `prev_semid`
   being present; if your rollout needs a revert button, add one mirroring P2's
   `bulkRevertToSemester` against the cluster tables.
5. **Q4-shaped config** — the preview does not special-case a 4-term config (see note).

6. **Wrap every `ibed_term_config` read with `activeConfigQuery()`.** The
   `shsConfiguredTerms()` resolver already goes through `activeConfigQuery`
   internally (note: `bulkTermStatus` deliberately reads config-only without
   this guard for the banner — see line 89). Any new direct `ibed_term_config`
   or `ibed_term` query added to the cluster-plotting controller must be
   wrapped. A bare `where('deleted', 0)` read without the guard resurfaces an
   Inactive config — the #1 source of "terms showing where they shouldn't"
   (Module 05 invariant).

---

## Verification

1. On `/setup/subject/shs-cluster-plotting` (or the principal route), select a
   term-configured, cluster-plotted SHS level → **Convert Term Setup** shows the terms
   and `semester_plots > 0`.
2. **Convert to Term Setup** → confirm:
   ```sql
   SELECT semid, prev_semid, termid, COUNT(*) FROM sh_cluster_plot
     WHERE syid=? AND levelid=14 AND deleted=0 GROUP BY semid, prev_semid, termid;   -- semid NULL
   SELECT semid, prev_semid, COUNT(*) FROM sh_cluster_subject_picking
     WHERE /* level scope */ deleted=0 GROUP BY semid, prev_semid;                    -- semid NULL
   ```
3. `shsHasTermPlotting($syid, 14)` is true (with P2 done for any per-subject plots) →
   the level shows Term-Based on `/classschedule` and term columns downstream.
4. A level with **no term config** → preview `ready:false`, no conversion.
5. A non-14/15 request → rejected by validation.

With cluster plots term-plotted, the level's SHS classes can enter term mode
(**Module 07**) alongside the per-subject path (**P2**).
