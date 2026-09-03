# Module P12 — Grade Status (Principal Portal) Term Support

> **This file replaces an earlier version that did not match es_ldcu.** The
> original draft described portability fixes to `IBEDECRController.php` and
> `teachergrading.blade.php` (hardcoded level IDs, `?: 1` vs `?? 1`, a
> hardcoded "Submitted" badge) — **none of that exists in es_ldcu**. It was
> invented/aspirational content, caught and reverted during the sjhsli_online
> port (see git history around the revert of `IBEDECRController.php` on this
> module). This rewrite documents the **real** es_ldcu route this module
> covers, verified by direct source read.

## What this module actually is

The Principal Portal's **Grade Status** page — route `/grades`, controller
`app/Http/Controllers/SuperAdminController/GradePostingController.php`, view
`resources/views/superadmin/pages/teacher/gradeposting.blade.php`. This is a
school-wide dashboard (not per-class) with three panels:

1. **ECR List** — status counts (Not Submitted/Submitted/Coor Approved/
   Approved/Pending/Posted) × Period 1–4, school-wide.
2. **Student List** — the same status counts, but counted per enrolled
   student rather than per class.
3. **Grades Information** — one row per section+subject+teacher, with a
   status cell per period (`subjectplot_table`, populated by
   `load_gradesetup_datatable()`).

Clicking a count in ECR List opens `#modal_3` (class-level list,
`datatable_3`); clicking a count in Student List opens `#modal_4`
(student-level list, `datatable_4`). Clicking a status link in the Grades
Information table opens `#ecr_modal` (a legacy/static class-record viewer —
**out of scope for this module**, see "Explicitly not touched" below).

es_ldcu's version of this page and controller is fully term-mode aware; the
sjhsli_online copy (and any other repo forked before this feature existed)
has **none** of that awareness — every period column and status query
assumes plain quarters. This module ports that awareness over.

## Dependencies

- **Module 01** (schema), **Module 05** (`IBEDGradingDefaults` resolvers).
- **Module P2** (whole-year subject-plot term subsets) — SHS term-mode
  detection depends on it.
- **Module P9** (System Grading term port) — not a hard code dependency, but
  do it first; this module assumes the same `IBEDGradingDefaults` helpers
  are already proven against real data.

## PREFLIGHT — check the repo FIRST

```bash
grep -n "class GradePostingController" app/Http/Controllers/SuperAdminController/GradePostingController.php
grep -n "isTermGradingLevel\|isShsTermMode" app/Http/Controllers/SuperAdminController/GradePostingController.php
grep -n "termGradingConfigs\|rowPeriodLabel\|selectedSyIsTermGrading" resources/views/superadmin/pages/teacher/gradeposting.blade.php
grep -r "class IBEDGradingDefaults" app/Support/
```

If `isTermGradingLevel`/`isShsTermMode` are already present in the
controller and `rowPeriodLabel` is already present in the blade, this module
is already applied — check what's missing rather than re-doing it wholesale.

## Controller changes — `GradePostingController.php`

Add two private static helpers (exact es_ldcu syntax):

```php
private static function isTermGradingLevel($syid, $levelid){
    if(in_array((int) $levelid, [14, 15])){ return false; }
    $terms = \App\Support\IBEDGradingDefaults::resolveTermLabelsForLevel($syid, $levelid);
    return !empty($terms['isTermGrading']);
}

private static function isShsTermMode($syid, $levelid = null){
    if($levelid != null){
        if(!in_array((int) $levelid, [14, 15])){ return false; }
        $periods = \App\Support\IBEDGradingDefaults::resolveShsPeriods($syid, $levelid);
        return !empty($periods['isTermMode']);
    }
    foreach([14, 15] as $shsLevel){
        if(self::isShsTermMode($syid, $shsLevel)){ return true; }
    }
    return false;
}
```

> `isTermGradingLevel()` deliberately returns `false` for levels 14/15 —
> SHS term detection goes through `isShsTermMode()`/`resolveShsPeriods()`
> instead (the whole-year-plotting gate), never through the junior/GS
> config-only resolver. This split is intentional and matches Module 05's
> "Junior ≠ Senior" invariant — don't collapse the two helpers into one.

**`get_shssubjects($syid, $semid)`** — the subject list query used to build
the "Grades Information" rows for SHS:
- Replace the plain `->where('subject_plot.semid', $semid)` with a
  `IBEDGradingDefaults::semesterScope()`-gated version so whole-year
  term-mode plots (`semid IS NULL`) aren't dropped.
- **Add the `$scheduledSubjects` merge** — a second query over
  `sh_classsched` + `sh_subjects` + `sh_enrolledstud` (semesterScope-gated,
  hard-matching `sh_enrolledstud.semid = $semid`) that picks up classes
  graded via `sh_classsched.grading_percentage_id` with no (or a deleted)
  `subject_plot` row. Merge with the subject_plot-sourced list, dedupe by
  `levelid-subjid-strandid-semid`, sort by `plotsort`. **This merge is not
  optional** — without it, a class whose `subject_plot` row is
  soft-deleted (a real, common state) silently vanishes from the page
  entirely rather than showing with a status. This is the same
  `grading_percentage_id` fallback bug class found repeatedly elsewhere
  in this port (Module P9/P11's pending-grades and grading-summary
  queries) — expect it here too.

**`get_grades($syid, $withdetails=false)`** — add `'semid'` to the
unconditional `->select(...)` list. Without it, the per-row `semid` field
the blade's JS needs for term-config lookup is silently absent.

**`all_grades()`** and **`per_student_grades_status()`** — both need:
- The `$shsteacher`/schedule query's semester filter gated through
  `semesterScope()` the same way as `get_shssubjects()`.
- `$isTermGrading = self::isTermGradingLevel($syid, $item->levelid);` and a
  grades filter (`->filter(fn($g) => $g->semid === null || $g->semid === '')`)
  applied right before the status-resolution loop, so term-mode grade rows
  (stored with `semid = NULL`) are the ones actually being read.
- In `per_student_grades_status()`'s `for($x=1;$x<=4;$x++)` loop, add
  `if($isTermGrading && $termCount > 0 && $x > $termCount){ continue; }` so
  period columns beyond the configured term count are skipped server-side
  too (the blade's `rowPeriodIsApplicable()` handles the same gate
  client-side — both are needed, the blade for rendering, this for the
  underlying counts).

## Blade changes — `gradeposting.blade.php`

**Term-config data for the JS.** Right after the existing `$sy`/`$semester`
`@php` declarations, build:

```php
$termGradingConfigs = []; // [syid][levelid] => ['termCount' => int, 'labels' => [term_no => label]]
$termGradingSyIds = [];   // syids that have ANY active term config
```

populated by looping every SY × gradelevel and calling
`IBEDGradingDefaults::shsConfiguredTerms($syid, $levelid)` for 14/15 and
`resolveTermLabelsForLevel($syid, $levelid)` otherwise (`shsConfiguredTerms`
is config-only — it does **not** apply the whole-year plotting gate, since
this page shows configured term structure regardless of a specific class's
plotting state).

**JS helpers**, added inside the page's first `$(document).ready()`:

```javascript
function selectedSyIsTermGrading(){
    return termGradingSyIds.indexOf(String($('#filter_sy').val())) !== -1;
}
function rowTermConfig(rowData){
    if(!selectedSyIsTermGrading()){ return null; }
    var syConfig = termGradingConfigs[String($('#filter_sy').val())] || {};
    return syConfig[String(rowData.levelid)] || null;
}
function rowPeriodLabel(rowData, period){
    var config = rowTermConfig(rowData);
    if(config){
        if(period > parseInt(config.termCount)){ return 'N/A'; }
        if(config.labels && config.labels[String(period)] != undefined){ return config.labels[String(period)]; }
        return period + 'T';
    }
    return 'Q' + period;
}
function rowPeriodIsApplicable(rowData, period){
    if(rowData.clusterplotid != undefined && rowData.assigned_quarters != undefined){
        return rowData.assigned_quarters.map(String).indexOf(String(period)) !== -1;
    }
    var config = rowTermConfig(rowData);
    if(config){ return period <= parseInt(config.termCount); }
    return true;
}
function aggregatePeriodLabel(period){
    if(selectedSyIsTermGrading()){ return 'Period ' + period; }
    var ordinalLabels = {1:'1st Quarter',2:'2nd Quarter',3:'3rd Quarter',4:'4th Quarter'};
    return ordinalLabels[period];
}
window.populateGradePeriodFilter = function(selectId, labelId, selectedPeriod){
    var labelText = selectedSyIsTermGrading() ? 'Period' : 'Quarter';
    var placeholder = 'Select ' + labelText;
    var selectedValue = selectedPeriod != undefined ? String(selectedPeriod) : String($(selectId).val() || '');
    $(labelId).text(labelText);
    $(selectId).empty();
    $(selectId).append('<option value="" selected>'+placeholder+'</option>');
    for(var period = 1; period <= 4; period++){
        $(selectId).append('<option value="'+period+'">'+aggregatePeriodLabel(period)+'</option>');
    }
    if(selectedValue != ''){ $(selectId).val(selectedValue).change(); }
}
```

> This page has **no** `semid=0` "Whole Year" sentinel concept at all —
> unlike the Teacher Grading page (P9). `$('#filter_sem').val()` is read
> directly everywhere with no wrapper needed; term-mode classes surface via
> `semesterScope()`'s server-side tolerance regardless of which real
> semester the Principal has selected.

**Modal quarter-filter labels.** `#modal_3` and `#modal_4` each have a
"Quarter" `<label>` next to their period `<select>` — give them
`id="filter_quarter_label_3"` / `id="filter_quarter_label_4"`, then replace
the plain `.val(x).change()` calls in the `.view_list_2` (opens modal_3) and
`.view_student_list` (opens modal_4) click handlers with
`window.populateGradePeriodFilter('#filter_quarter_3', '#filter_quarter_label_3', temp_quarter)`
(and the `_4` equivalent). The **main page's own** `Quarter` filter has no
id on its label in es_ldcu either — leave it alone.

**`load_gradesetup_datatable()`'s per-cell `createdCell` for the period
columns (3–6):**
- Compute `var period = col - 2` and `var periodLabel = rowPeriodLabel(rowData, period)` up front.
- Add an early return: `if(!rowPeriodIsApplicable(rowData, period)){ innerHTML = 'N/A'; return; }`
- Everywhere the cell previously showed `'&nbsp;'` as the subtext, show
  `periodLabel` instead (e.g. `NOT SUBMITTED` / `PENDING` rows), and for the
  submitted/status-link case append `periodLabel + ' &bull; ' + date` and add
  a `data-clusterplotid` attribute when `rowData.clusterplotid` is set.
- Keep the existing legacy SHS semester-exclusion block
  (`if(rowData.levelid == 14 || rowData.levelid == 15){ ... }`), but **guard
  it with `if(rowTermConfig(rowData)){ all_status.push(...); } else if(...)`**
  — when a term config applies, always count the row; otherwise fall back to
  the old `$('#filter_sem').val()`-based Q1/Q2 vs Q3/Q4 exclusion unchanged.

**Static headers.** The ECR List and Student List widgets' `<th>` cells say
`Q1`/`Q2`/`Q3`/`Q4` — change to `Period 1`/`Period 2`/`Period 3`/`Period 4`.
The main "Grades Information" table's headers likely say `Quarter 1..4` (or
similar) — same change, to `Period 1..4`. es_ldcu uses the neutral "Period
N" wording on all three so a school-wide aggregate that mixes quarter- and
term-mode classes underneath never shows a mismatched label. `load_all_grade_status()`
(the widget population function) needs **no** logic change — it just counts
by numeric `quarter` column, same as before; only the static header text
changes.

## Class Record modal (`#ecr_modal`) — dynamic ECR support

The "Class Record" popup opened from a status link in the Grades Information
table (`.view_status` click handler → `load_ecr()`) is **not** purely
static — es_ldcu branches it the same way the Class Schedule page (P7)
branches its own ECR viewer:

**Controller — `all_grades()`.** Each section-row pushed onto `$data` gets a
computed field:

```php
'has_ibed_components'=> \App\Http\Controllers\SuperAdminController\TeacherECRController::hasIbedComponents(
    $item->levelid, $subjitem->subjid, $syid, $item->id, $semid, false
) ? 1 : 0
```

(the cluster-row branch, if cluster-plot support is ever ported, passes
`true` for the last `$isCluster` argument and the cluster's `clusterplotid`
in place of `sectionid` — see "Not touched" below.)

**Blade — `.view_status` click handler.**
- `grades_info = all_grades.filter(...)` should also match on
  `data-clusterplotid` when present (harmless no-op without cluster
  support — `rowData.clusterplotid` is simply `undefined` and the check is
  skipped).
- After building the default 1st–4th Quarter options, check
  `var termConfig = rowTermConfig(grades_info[0])`: if it applies, clear the
  `<select>`, relabel `Quarter` → `Period` via
  `$('#filter_quarter').closest('.form-group').find('label').text('Period')`,
  and populate options `1..termConfig.termCount` using `rowPeriodLabel()`.
  Otherwise keep the existing legacy Quarter/SHS-semester-exclusion options
  unchanged.

**Blade — `load_ecr()`.** Rewrite to match es_ldcu exactly:
- Read `currentGrade` from `grades_info[0].grades` filtered by the selected
  quarter/period, and populate `#label_dateuploaded`, `#label_status`,
  `#label_datesubmitted` from it (a fresh fork's version typically never
  wires these at all, leaving them permanently blank).
- Disable all four action buttons, then re-enable exactly one based on
  `currentGrade.stattext` (`SUBMITTED`/`COOR APPROVED`/`PENDING` →
  `#approve_grade`; `APPROVED` → `#post_grade`; `POSTED` → `#unpost_grade`).
- The AJAX call's `url` becomes
  `grades_info[0].has_ibed_components == 1 ? '/ibed-ecr/view' : '/ecr/view'`,
  and its `data` gains `clusterplotid: grades_info[0].clusterplotid || ''`
  and `readonly: 1` (the readonly flag keeps `IBEDECRController::view()`
  side-effect free for this preview surface — it already supports this
  parameter from Module 07).

No new routes are needed — `/ibed-ecr/view` (`IBEDECRController@view`) and
`/ecr/view` (the legacy viewer) already exist once Module 07 is applied.

## Explicitly not touched by this module

- **Cluster-plot support in `all_grades()`** — es_ldcu's version has a full
  `sh_cluster_plot`/`sh_cluster_plot_teacher` query block (assigned-quarter
  gating, `clusterplotid` on each row) that a fresh fork's `all_grades()`
  entirely lacks. `rowPeriodIsApplicable()`, the cell's `data-clusterplotid`
  attribute, and the modal's `has_ibed_components`/`clusterplotid`
  plumbing are all written to consume this data **if present**, but porting
  the query block itself is a separate, larger task — decide with the user
  before doing it.
- **`get_grades($withdetails=true)`'s missing `addSelect`** — es_ldcu (and
  likely the target repo, if copied from it) never actually adds
  `studid`/`gdstatus`/`qg` via `addSelect` when `$withdetails` is true. This
  looks like a pre-existing, unrelated bug in the reference itself — don't
  "fix" it as part of this module unless asked.

## Known inherited limitation — do not "fix" this

`isTermGradingLevel()` always returns `false` for levels 14/15 by design
(SHS term detection is `isShsTermMode()`'s job). This means the old
`if($semid == 2 && ($x == 1 || $x == 2)){ $isincluded = false; }`-style
semester-exclusion logic inside `per_student_grades_status()`/`all_grades()`
is **never** skipped for term-mode SHS — so a 3-term SHS class's 3rd term
period never appears in the Student List's per-student breakdown regardless
of which semester filter the Principal has selected. This is a genuine,
verified limitation **in es_ldcu itself**, not something a target repo needs
to fix beyond faithfully porting the same behavior. Per the "port
faithfully, don't invent fixes" rule that applies to every module in this
kit, leave it as-is unless the user asks for it to be corrected.

## Verification

1. **Quarter-mode class (any level without an active term config):**
   Grades Information row shows `Q1`/`Q2`/`Q3`/`Q4` subtext under each
   period cell, all four periods active, ECR/Student List widget headers
   read "Period 1–4" (label only — counts unaffected).
2. **Term-mode JHS/GS class:** period cells beyond `termCount` show `N/A`;
   applicable cells show the term's configured label (falls back to `NT`
   for `N` = term_no when no explicit label is set) as subtext.
3. **Term-mode SHS class (levelid 14/15, whole-year plotted, active
   config):** same as above — confirm this only activates when
   `resolveShsPeriods()`/`shsConfiguredTerms()` actually returns a config
   for that specific level, not just because the SY has term grading
   enabled for a *different* SHS level (grade 11 and grade 12 can be
   independently term-mode or not on the same SY).
4. **Semester-mode SHS class (14/15, no term config or not plotted):**
   confirm the legacy `$('#filter_sem').val()`-based Q1/Q2-vs-Q3/Q4
   exclusion still applies unchanged (no regression).
5. **`#modal_3`/`#modal_4` drill-downs:** open both from an ECR
   List/Student List count; confirm the Quarter/Period label and options
   swap correctly via `populateGradePeriodFilter`.
6. **Console clean:** no JS errors on page load, filter, or modal open.
7. **Deleted `subject_plot` row case:** a class scheduled via
   `sh_classsched.grading_percentage_id` whose `subject_plot` row is
   soft-deleted still appears in the Grades Information table (proves the
   `$scheduledSubjects` merge is wired in).
8. **Class Record modal — dynamic ECR:** click a status link for a class with
   dynamic component grading (`grading_percentage_id` set and a real
   `subject_gradessetup.components_json`); confirm `#ecr_modal` opens the
   `/ibed-ecr/view` layout (student roster, per-component score columns, a
   "N of M students submitted" banner) with the `Period` label and
   term-labeled options, and that `Grade Status`/`Last date Uploaded`/`Grade
   Submitted` are populated (not blank) with the correct Approve/Post/
   Pending/Unpost button enabled to match the current status. Click a status
   link for a class without dynamic components and confirm it still opens
   the legacy `/ecr/view` layout unchanged.
