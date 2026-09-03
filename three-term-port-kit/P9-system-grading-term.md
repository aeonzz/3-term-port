# Module P9 — System Grading (Term-Aware)

The System Grading flow is a three-page teacher-portal surface:

1. **Index page** (`/grades/index`) — SY + semester filter with a "Whole Year
   (3-Term SHS)" option, rendering section cards.
2. **Subjects page** (`/grades/getsubjects`) — lists subjects for a selected
   section, including cluster-plot electives in term mode.
3. **Grading page** (`/subjects/{id}/{syid}/{levelid}/{sectionid}/{semid}`) —
   the actual grade entry view with term tabs, grade-status badges, the
   dynamic component-based ECR layout (when `components_json` exists), and
   Save/Submit.

In term mode the index page adds a "Whole Year" semester option, the subjects
page shows cluster-plot electives alongside regular subjects, and the grading
page renders term tabs (e.g., "First Term / Second Term / Third Term") instead
of quarter buttons — with the dynamic component-based grade table served by
`/getgrades/{id}` using the IBED component layout.

This is a **portal-surface** module (not one of the core 01–10 layers). It
consumes resolvers from **Module 05** — `shsConfiguredTerms()`,
`resolveShsPeriods()`, `activeConfigQuery()` — and the `IbedGradeEquivalency::
configAppliesToLevel()` check from **Module 04**. It depends on **P2**
(subject-plot whole-year conversion) and **P3** (cluster-plot whole-year
conversion) for the data it reads.

> **Ported into `sjhsli_online` — see known-pitfalls #16.** `GradeController.php`
> had zero term-mode awareness (built fresh, not adapted); `TeacherGradingV2::
> showGrades()` already had a partial `ibedTerms` resolution from an earlier
> pass but was missing the cluster-teacher term filter and the grade-status
> query's semid branching entirely, and its own cluster detection matched
> `semid` exactly (missing every term-mode cluster elective). This repo has no
> distinct `clusterplotid` request parameter — cluster electives reuse the
> `sectionid` slot for `sh_cluster_plot.id` throughout (matching P7/P8's own
> adaptation), which meant one lookup (`showGrades()`'s section-name label)
> that assumed `sectionid` was always a real `sections.id` silently displayed
> the wrong section for a cluster elective. Also adapted: `sh_blocksched` (a
> block-schedule concept this repo has that the kit doc's snippets don't
> mention) needed its own whole-year gate, since it lacks a
> `grading_percentage_id` column and uses `levelid` instead of `glevelid`.
> Two more gaps found and closed after the initial port: (1) the whole-year
> `semid=0` sentinel crashed `showGrades()` outright — it was looked up
> against the `semester` table as if it were a real id; fixed by treating it
> as `NULL` directly, which is also the semantically correct value for a
> whole-year class. (2) Changes 5/10 (the dynamic component-ECR table on
> `/getgrades/{id}`) were never actually implemented — the real routed method
> (`TeacherGradingV2::getGrades()`, not the `ibedTerms`-resolving
> `showGrades()`) always rendered the legacy WW/PT/QA table regardless of
> `components_json`, even though the blade already had unused
> `window.ibedMode`/`checkAndUpdateSubmitBtn()` scaffolding for it. Wired
> `loadGrades()` to `/ecr/check-ibed` + `/ibed-ecr/view` (P7/P8's own
> endpoints, reused verbatim) instead of building a parallel implementation
> inside `getGrades()`. This also surfaced that `IBEDECRController::view()`
> never called its own (already-built, already-routed-nowhere)
> `initializeGradesHeader()` — a teacher opening a fresh quarter/term got a
> table with every cell disabled and nothing to save into. `view()` now
> calls it automatically for the non-`readonly` (teacher's own page) case.
>
> **Two more gaps found later, once a teacher actually exercised Submit
> against real term-mode data (not just Save):**
>
> (3) The dynamic ECR's Submit button reuses the pre-existing `/gradesSubmit/
> {quarter}` endpoint (`TeacherControllers\FilterController::
> updateGradeStatus()`) on the assumption that a "generic, table-driven"
> legacy endpoint needed no backend change — wrong for term-mode SHS
> specifically, since its SHS branch hardcoded `where('semid', $semid->id)`
> with no term-mode gate, so a term-mode header (`semid = NULL`) was never
> found: the submit silently no-opped (checking every row and hitting Submit
> did nothing) and an unguarded `$get_grade_id[0]->id` access threw
> "Undefined offset: 0" once the lookup came back empty. Fixed by porting
> es_ldcu's own already-term-mode-aware implementation of this method
> verbatim (read directly from the reference checkout, not inferred) — see
> `07-teacher-ecr-term.md`'s note on this same endpoint for the full detail.
>
> (4) A class converted to term mode *mid-grading-period* leaves earlier
> quarters' headers behind at their old real `semid` — `view()`'s and
> `initializeGradesHeader()`'s header lookups both tolerate this
> (`where('semid', X)->orWhereNull('semid')`, so grading itself never
> visibly breaks), but nothing corrected the stale value, and gap (3)'s now-
> strict `whereNull('semid')` submit match could never see it — making that
> quarter permanently unsubmittable for the class's lifetime. Fixed with a
> shared `reKeyStaleTermHeader()` helper, called from both header-lookup
> sites: if the level is SHS and actually in term mode but the found
> header's `semid` isn't already `NULL`, correct it in place (mirrors
> `TeacherFinalGrade`'s identical re-key fix for its own header-creation
> path). Self-heals the moment a teacher reopens or resubmits that quarter —
> no manual data fix needed. Gated behind `!readonly` in `view()` so the
> superadmin/registrar preview stays side-effect free.

## Goal — what this port must achieve

After this port, the system grading flow correctly handles both quarter-based
and term-based classes within the same school year. Concretely:

1. **Whole-year filter option (index).** The semester dropdown includes a
   "Whole Year (3-Term SHS)" option, enabled only when the selected SY has
   `term_grading_status = 1` AND at least one SHS level has a term config.
   Selecting it passes `selectedsemester=0` to the section query.
2. **Section query gating (controller).** `getsections()` detects
   `$isWholeYearSelection` and uses `whereExists(subject_plot.semid IS NULL)`
   on the SHS schedule queries, so whole-year-plotted classes appear as
   section cards. Cluster-plot electives also appear as section cards.
3. **Subject listing with clusters (controller).** `getsubjects()` uses
   `resolveShsPeriods()` to detect term mode. SHS schedule queries branch
   on `$isWholeYearSelection` and `$isTermModeGS`. Cluster-plot electives
   are queried with `whereNull('cp.semid')` in term mode, appearing
   alongside regular subjects.
4. **Term tabs (grading blade).** The grading page renders term-labeled
   buttons (from `$ibedTerms`) instead of quarter buttons. Each term button
   shows the corresponding grade status badge.
5. **Dynamic component layout (grading page).** When the subject has a
   `components_json` grading setup, the `/getgrades/{id}` endpoint returns
   the dynamic component-based ECR table (Written Works / Performance Task /
   Quarterly Assessment columns with configurable item counts). The legacy
   Update/Export buttons are hidden for this layout.
6. **Grade-status query branching.** The `showGrades()` controller queries
   grade headers with `whereNull('semid')` for cluster-plot term mode, and
   includes `orWhereNull('semid')` for SHS levels to catch orphan headers.
7. **Cluster-plot teacher term filtering.** For cluster-plot electives with
   term config, the term tabs are filtered to only the teacher's assigned
   quarters (from `sh_cluster_plot_teacher`).

**Acceptance criteria (all must hold):**

- [ ] Semester-only SY: "Whole Year" option disabled, page works as before —
      quarter buttons, semester filter, legacy or component ECR.
- [ ] Term-mode SHS level (index): "Whole Year" option enabled and selectable.
      Section cards appear for whole-year-plotted classes.
- [ ] Term-mode SHS level (subjects): regular subjects and cluster-plot
      electives all appear on the subjects page. Cluster electives show with
      "Elective" badge.
- [ ] Term-mode SHS level (grading): term tabs render with configured term
      labels and status badges. Dynamic component table loads on term
      selection. Save and Submit work through the IBED endpoints.
- [ ] Cluster-plot elective (grading): term tabs show only the teacher's
      assigned quarters/terms. Grade headers use `semid = NULL`.
- [ ] JHS/GS term mode: term tabs render from `ibedTerms` (resolved via
      `activeConfigQuery` + `configAppliesToLevel`). Dynamic component table
      loads if `components_json` exists.
- [ ] Mixed SY: one level on quarters, another on terms — both display
      correctly per their config.
- [ ] 4-quarter-shaped config: excluded by upstream resolvers — stays on
      quarter buttons.

> **Report back after applying (do this in chat).** When the port is done, post
> the acceptance criteria as a **ticked checklist** — **✅** applied and verified,
> **✔️** code applied but runtime/live-page test still pending, **⬜** skipped or
> not applicable (say why). Never mark ✅ something you didn't apply.

## Behaviors by level / config state

| Level / config state | Expected behavior |
|----------------------|-------------------|
| **No term config** | Legacy quarter mode — semester filter, quarter buttons, legacy ECR or component ECR per setup. |
| **Term config, not plotted (SHS)** | `resolveShsPeriods` returns non-term — "Whole Year" option disabled for that level, stays on quarter mode. |
| **Term config, whole-year plotted (SHS)** | Full term mode — "Whole Year" option works, section cards show, term tabs on grading page, component ECR with term labels. |
| **Term config (JHS/GS)** | Term tabs from `ibedTerms` via `activeConfigQuery`. No "Whole Year" filter needed (JHS has no semester split). |
| **4-quarter-shaped config** | Upstream resolvers exclude it — stays on quarter mode. |

## PREFLIGHT — check the repo FIRST

Before editing, verify these symbols/files exist in the target repo:

```bash
# Module 05 foundation
grep -r "class IBEDGradingDefaults" app/Support/
grep -r "shsConfiguredTerms\|resolveShsPeriods\|activeConfigQuery" app/Support/

# Module 04 (grade equivalency)
grep -r "class IbedGradeEquivalency" app/Support/
grep -r "configAppliesToLevel" app/Support/

# Target controllers
grep -rl "GradeController" app/Http/Controllers/TeacherControllers/
grep -rl "TeacherGradingV2" app/Http/Controllers/TeacherControllers/
grep -n "function index\|function getsections\|function getsubjects" \
    app/Http/Controllers/TeacherControllers/GradeController.php
grep -n "function showGrades" \
    app/Http/Controllers/TeacherControllers/TeacherGradingV2.php

# Target views
ls resources/views/teacher/grading/v1/index.blade.php
ls resources/views/teacher/grading/v1/showsubjects.blade.php
ls resources/views/teacher/grading/teachergrading.blade.php

# Routes
grep -n "grades/index\|grades/getsubjects\|/subjects/" routes/web.php | head -20
```

If `shsConfiguredTerms`, `resolveShsPeriods`, or `activeConfigQuery` are
missing, apply **Module 05** first.

## Files to check and update

| # | File | What to do |
|---|------|------------|
| 1 | `app/Http/Controllers/TeacherControllers/GradeController.php` | Add `hasWholeYearTermSetup()`, update `getsections()` with whole-year gating, update `getsubjects()` with term-mode detection and cluster-plot term queries |
| 2 | `app/Http/Controllers/TeacherControllers/TeacherGradingV2.php` | Update `showGrades()` with `ibedTerms` resolution, cluster-plot term mode, grade-status query branching |
| 3 | `resources/views/teacher/grading/v1/index.blade.php` | Add "Whole Year (3-Term SHS)" option, `data-term-status` on SY options, `sync_whole_year_option()` JS |
| 4 | `resources/views/teacher/grading/v1/showsubjects.blade.php` | Cluster-plot electives display with "Elective" badge, whole-year `subjectSemester` handling |
| 5 | `resources/views/teacher/grading/teachergrading.blade.php` | Term tabs from `$ibedTerms`, dynamic component ECR detection, `window.loadGrades` for in-place refresh |

## Changes

### Change 1 — Controller: `hasWholeYearTermSetup()` helper

**File:** `app/Http/Controllers/TeacherControllers/GradeController.php`

Add a private helper that checks if a school year has any SHS term config:

```php
private function hasWholeYearTermSetup($syid)
{
    if (empty($syid)) {
        return false;
    }

    $sy = DB::table('sy')->where('id', $syid)->first();
    if (!$sy || (int) ($sy->term_grading_status ?? 0) !== 1) {
        return false;
    }

    return !empty(\App\Support\IBEDGradingDefaults::shsConfiguredTerms($syid, 14)['terms'])
        || !empty(\App\Support\IBEDGradingDefaults::shsConfiguredTerms($syid, 15)['terms']);
}
```

This gates both `getsections()` and `getsubjects()` — when `selectedsemester
= 0` (whole year) and this returns false, no results are shown.

### Change 2 — Controller: `getsections()` whole-year query gating

**File:** `app/Http/Controllers/TeacherControllers/GradeController.php`

At the top of `getsections()`, detect the whole-year selection:

```php
$isWholeYearSelection = (string) $selectedsemester === '0';

if ($isWholeYearSelection && !$this->hasWholeYearTermSetup($selectedschoolyear)) {
    return [];
}
```

Gate the SHS schedule queries (`sh_classsched`, `sh_blocksched`) with a
`whereExists` check for a whole-year subject plot:

```php
->when($isWholeYearSelection, function($q) use ($selectedschoolyear){
    $q->whereExists(function($sub) use ($selectedschoolyear){
        $sub->select(DB::raw(1))
            ->from('subject_plot')
            ->whereColumn('subject_plot.subjid','sh_classsched.subjid')
            ->whereColumn('subject_plot.levelid','sh_classsched.glevelid')
            ->where('subject_plot.syid',$selectedschoolyear)
            ->whereNull('subject_plot.semid')
            ->whereNotNull('subject_plot.gradessetup')
            ->where('subject_plot.deleted',0);
    });
})
->when($selectedsemester, function($q) use ($selectedsemester){
    $q->where('sh_classsched.semid',$selectedsemester);
})
```

The `when($selectedsemester, ...)` falls through when `$selectedsemester = 0`
(falsy), so the semester filter is dropped for whole-year.

Lower-level (JHS/GS) `assignsubj` results are excluded from whole-year
selection: `if (!$isWholeYearSelection) { $sections = $sections->merge($assignsubjectsLower); }`.

Cluster-plot electives query uses `->where('cp.semid', $selectedsemester)`.

### Change 3 — Controller: `getsubjects()` term-mode detection

**File:** `app/Http/Controllers/TeacherControllers/GradeController.php`

At the top, detect whole-year and resolve term mode for the level:

```php
$isWholeYearSelection = (string) $selectedsemester === '0';

if ($isWholeYearSelection && !$this->hasWholeYearTermSetup($selectedschoolyear)) {
    return view('teacher.grading.v1.showsubjects')
        ->with('message', 'No term grading setup configured for this school year.');
}

$shsPeriodsGS = \App\Support\IBEDGradingDefaults::resolveShsPeriods($selectedschoolyear, $selectedlevelid);
$isTermModeGS = !empty($shsPeriodsGS['isTermMode']);
```

SHS schedule query (`sh_classsched`) branches on whole-year:

```php
->when($isWholeYearSelection, function ($q) use ($selectedschoolyear) {
    $q->where(function ($qq) use ($selectedschoolyear) {
        $qq->whereNotNull('sh_classsched.grading_percentage_id')
            ->orWhereExists(function ($sub) use ($selectedschoolyear) {
                $sub->select(DB::raw(1))
                    ->from('subject_plot')
                    ->whereColumn('subject_plot.subjid', 'sh_classsched.subjid')
                    ->whereColumn('subject_plot.levelid', 'sh_classsched.glevelid')
                    ->where('subject_plot.syid', $selectedschoolyear)
                    ->whereNull('subject_plot.semid')
                    ->whereNotNull('subject_plot.gradessetup')
                    ->where('subject_plot.deleted', 0);
            });
    });
})
->when(!$isTermModeGS && !$isWholeYearSelection, function ($q) use ($selectedsemester) {
    $q->where('sh_classsched.semid', $selectedsemester);
})
```

When `$isWholeYearSelection`, subjects that either have a schedule-level
`grading_percentage_id` OR a whole-year subject plot are included. The
semester filter is dropped.

For whole-year, all returned subjects get `subjectsemid = 0`:

```php
if ($isWholeYearSelection) {
    foreach ($subjects as $subject) {
        $subject->subjectsemid = 0;
    }
}
```

In term mode, duplicates (same subject from different semesters) are collapsed:

```php
if ($isTermModeGS) {
    $subjects = $subjects->unique('subjectid')->values();
}
```

### Change 4 — Controller: `getsubjects()` cluster-plot elective query

**File:** `app/Http/Controllers/TeacherControllers/GradeController.php`

Cluster-plot electives are queried with term-mode branching:

```php
$clusterElectives = DB::table('sh_cluster_plot as cp')
    ->join('sh_subjects as s', 's.id', '=', 'cp.subjectid')
    ->leftJoin('sh_cluster as c', 'c.id', '=', 'cp.clusterid')
    // ... ShsClusterSectionScope joins if available ...
    ->where('cp.deleted', 0)
    ->where('cp.syid', $selectedschoolyear)
    ->where('cp.levelid', $selectedlevelid)
    ->when($selectedClusterPlot, function ($q) use ($selectedClusterPlot) {
        $q->where('cp.id', $selectedClusterPlot->id);
    })
    ->when(!$selectedClusterPlot && !$isTermModeGS, function ($q) use ($selectedsemester) {
        $q->where(function($query) use ($selectedsemester){
            $query->where('cp.semid', $selectedsemester)
                ->orWhereNull('cp.semid');
        });
    })
    ->when(!$selectedClusterPlot && $isTermModeGS, function ($q) {
        $q->whereNull('cp.semid');
    })
    ->whereExists(function ($sub) use ($teacherid) {
        $sub->select(DB::raw(1))
            ->from('sh_cluster_plot_teacher as cpt')
            ->whereColumn('cpt.plotid', 'cp.id')
            ->where('cpt.teacherid', $teacherid)
            ->where('cpt.deleted', 0);
    })
    ->select(
        DB::raw('cp.id as sectionid'),
        // ... sectionname from cluster/room/ShsClusterSectionScope ...
        DB::raw('cp.levelid as glevelid'),
        'cp.syid',
        DB::raw('cp.subjectid as subjectid'),
        's.subjtitle as subjectname',
        DB::raw('cp.id as clusterplotid'),
        DB::raw('1 as is_cluster_plot')
    )
    ->distinct()
    ->get();

$subjects = $subjects->merge($clusterElectives)->values();
```

In term mode, cluster plots with `semid = NULL` are included. In semester
mode, both `semid = $selectedsemester` and `semid IS NULL` are allowed (the
`orWhereNull` catches pre-term-conversion plots that haven't been migrated).

### Change 5 — Controller: `showGrades()` term resolution and ibedTerms

**File:** `app/Http/Controllers/TeacherControllers/TeacherGradingV2.php`

The `showGrades()` method resolves `$ibedTerms` for the term tab buttons:

```php
$ibedTerms = collect();

// First: check if the subject has a component-based grading setup
$ibedSetup = DB::table('subject_plot')
    ->join('subject_gradessetup', function ($j) {
        $j->on('subject_gradessetup.id', '=', 'subject_plot.gradessetup');
        $j->where('subject_gradessetup.deleted', 0);
    })
    ->where('subject_plot.syid', $syid)
    ->where('subject_plot.levelid', $gradelevelid)
    ->where('subject_plot.subjid', $id)
    ->where('subject_plot.deleted', 0)
    ->whereNotNull('subject_gradessetup.components_json')
    ->select('subject_gradessetup.components_json')
    ->first();

// Cluster-plot fallback: check gradingsetupid on sh_cluster_plot
if (!$ibedSetup && $isCluster) {
    $ibedSetup = DB::table('sh_cluster_plot')
        ->join('subject_gradessetup', ...)
        ->whereNotNull('subject_gradessetup.components_json')
        ->first();
}

// If a component setup exists, resolve term config
if ($ibedSetup && !empty($ibedSetup->components_json) && $ibedSetup->components_json !== '[]') {
    $termConfig = \App\Support\IBEDGradingDefaults::activeConfigQuery(
        DB::table('ibed_term_config')
            ->where('syid', $syid)
            ->where('acadprogid', $acadprogid)
            ->where('deleted', 0)
            ->where(function ($q) use ($activeSem) {
                $q->where('semid', $activeSem)->orWhereNull('semid');
            })
            ->orderByRaw('CASE WHEN semid IS NULL THEN 1 ELSE 0 END ASC')
    )->first();

    if ($termConfig && IbedGradeEquivalency::configAppliesToLevel($termConfig->id, $grade_level_id)) {
        $ibedTerms = DB::table('ibed_term')
            ->where('config_id', $termConfig->id)
            ->where('is_active', 1)
            ->where('deleted', 0)
            ->orderBy('term_no')
            ->get();
    }
}
```

A second fallback runs even without `components_json` — if the first pass
found no terms but a term config exists for the level, it resolves terms
anyway (so legacy ECR classes in a term-mode level still get term tabs).

For cluster-plot electives, the terms are filtered to only the teacher's
assigned quarters:

```php
if ($isClusterPlot && $ibedTerms->isNotEmpty()) {
    $assignedTerms = DB::table('sh_cluster_plot_teacher')
        ->where('plotid', $clusterplotid)
        ->where('teacherid', $teacherRow->id)
        ->where('deleted', 0)
        ->pluck('quarter')
        ->map(fn($q) => (int) $q)
        ->unique()
        ->toArray();
    if (!empty($assignedTerms)) {
        $ibedTerms = $ibedTerms->filter(fn($t) => in_array((int) $t->term_no, $assignedTerms, true))->values();
    }
}
```

### Change 6 — Controller: `showGrades()` grade-status query

**File:** `app/Http/Controllers/TeacherControllers/TeacherGradingV2.php`

The grade status loop (1..4) branches for cluster term mode:

```php
for ($x = 1; $x <= 4; $x++) {
    $grades = DB::table('grades')
        ->where('syid', $syid)
        ->where('levelid', $gradelevelid)
        ->where('subjid', $id)
        ->where('quarter', $x)
        ->where('deleted', 0)
        ->where('sectionid', $section_id)
        ->when($isClusterTermMode, function ($q) {
            $q->whereNull('semid');
        })
        ->when(!$isClusterTermMode && ($gradelevelid == 14 || $gradelevelid == 15), function ($q) use ($activeSem) {
            $q->where(function ($qq) use ($activeSem) {
                $qq->where('semid', $activeSem)->orWhereNull('semid');
            });
        })
        ->select('id', 'quarter', 'status', 'submitted')
        ->get();
    // ... status resolution with per-student gdstatus breakdown
}
```

The `$isClusterTermMode` flag uses `whereNull('semid')` — cluster-plot term
mode grade headers always have `semid = NULL`. For non-cluster SHS, the
`orWhereNull` catches orphan headers created before the semid-adoption fix.

The status is resolved from per-student `gdstatus` counts (not just the
header's `submitted` flag). The resolution cascade:

```php
if (count($grades)) {
    $status = 'Not Submitted';

    if ($grades[0]->status == 2) {
        $status = 'Approved';
    } else if ($grades[0]->status == 3) {
        $status = 'Pending';
    } else if ($grades[0]->status == 4) {
        $status = 'Posted';
    } else {
        $detailCounts = DB::table('gradesdetail')
            ->where('headerid', $grades[0]->id)
            ->selectRaw('gdstatus, COUNT(*) as cnt')
            ->groupBy('gdstatus')
            ->pluck('cnt', 'gdstatus');
        $totalCount = $detailCounts->sum();
        $doneCount = ($detailCounts[1] ?? 0) + ($detailCounts[2] ?? 0) + ($detailCounts[4] ?? 0);
        if ($doneCount > 0) {
            $status = ($totalCount > 0 && $doneCount < $totalCount) ? 'Partial' : 'Submitted';
        }
    }

    array_push($grade_status, (object) ['quarter' => $x, 'status' => $status]);
} else {
    array_push($grade_status, (object) ['quarter' => $x, 'status' => 'Not Submitted']);
}
```

**Status values and their meaning:**

| Status | Condition | Badge color |
|--------|-----------|-------------|
| **Not Submitted** | No grade header exists, or header exists but no student has been submitted | Red (`btn-danger`) |
| **Partial** | Some students submitted (`gdstatus` in 1/2/4) but not all | Yellow (`btn-warning`) |
| **Submitted** | All students submitted | Green (`btn-success`) |
| **Approved** | Header `status == 2` (admin-approved) | Green (`btn-success`) |
| **Pending** | Header `status == 3` (awaiting approval) | Blue (`btn-info`) |
| **Posted** | Header `status == 4` (posted to report cards) | Green (`btn-success`) |

The `gdstatus` values counted as "done": `1` (submitted), `2` (approved),
`4` (posted). A student with `gdstatus = 0` or `3` is not yet done.

### Change 7 — Blade: index page "Whole Year" option

**File:** `resources/views/teacher/grading/v1/index.blade.php`

Add `data-term-status` to each SY option:

```html
@foreach (collect($schoolyears)->sortByDesc('sydesc')->values() as $schoolyear)
    <option value="{{ $schoolyear->id }}"
            data-term-status="{{ $schoolyear->term_grading_status ?? 0 }}"
            @if ($schoolyear->isactive == 1) selected @endif>
        {{ $schoolyear->sydesc }}
    </option>
@endforeach
```

Add the "Whole Year" option to the semester dropdown:

```html
<option value="0" id="whole_year_option">Whole Year (3-Term SHS)</option>
```

Add `sync_whole_year_option()` JS:

```javascript
function sync_whole_year_option() {
    var termStatus = parseInt($('#selectedschoolyear option:selected').data('term-status')) || 0;
    var hasTermSetup = termStatus === 1;
    $('#whole_year_option').prop('disabled', !hasTermSetup);

    if (!hasTermSetup && $('#selectedsemester').val() == '0') {
        var fallbackSemester = $('#selectedsemester option:not([value="0"]):first').val();
        $('#selectedsemester').val(fallbackSemester).trigger('change.select2');
    }
}
```

Called on page load and on SY change. Disables the option when the SY has no
`term_grading_status = 1`, and falls back to the first real semester if the
user was on "Whole Year" when switching to a non-term SY.

Section cards include `clusterplotid` in the link when it's a cluster section:

```javascript
var clusterplotid = value.clusterplotid ? '&clusterplotid=' + value.clusterplotid : ''
// href includes clusterplotid in the query string
```

### Change 8 — Blade: subjects page cluster display

**File:** `resources/views/teacher/grading/v1/showsubjects.blade.php`

Each subject card links to the grading page with `$subjectSemester`:

```php
@php
    $isElective = isset($subject->is_cluster_plot) && $subject->is_cluster_plot;
    $subjectSemester = isset($subject->subjectsemid) && $subject->subjectsemid !== null
        ? $subject->subjectsemid : $selectedsemester;
@endphp
<a href="/subjects/{{ $subject->subjectid }}/{{ $subject->syid }}/{{ $subject->glevelid }}/{{ $subject->sectionid }}/{{ $subjectSemester }}@if($isElective)?clusterplotid={{ $subject->clusterplotid }}@endif">
```

For whole-year (`$selectedsemester = 0`), subjects get `subjectsemid = 0`
from the controller, so the link passes `semid=0` to `showGrades()`.

Cluster-plot electives display an "Elective" badge:

```html
@if($isElective)<span class="badge badge-info">Elective</span>@endif
```

### Change 9 — Blade: grading page term tabs

**File:** `resources/views/teacher/grading/teachergrading.blade.php`

The term tab buttons replace the fixed quarter buttons when `$ibedTerms` is
populated. Both SHS and non-SHS levels check for `$ibedTerms`:

```blade
@if ($gradeLevelid == 14 || $gradeLevelid == 15)
    @if (isset($ibedTerms) && $ibedTerms->count() > 0)
        @foreach ($ibedTerms as $loop_i => $term)
            <button name="quarter" value="{{ $term->term_no }}" class="btn btn-success"
                {{ $loop_i === 0 ? 'id="clickme"' : '' }}>
                {{ $term->description }} <br>
                <span class="badge data_stat" value="{{ $term->term_no }}">
                    {{ collect($grade_status)->where('quarter', $term->term_no)->first()->status ?? '' }}
                </span>
            </button>
        @endforeach
    @elseif ($activeSem == 1)
        {{-- 1st/2nd Quarter buttons --}}
    @elseif($activeSem == 2)
        {{-- 3rd/4th Quarter buttons --}}
    @endif
@else
    @if (isset($ibedTerms) && $ibedTerms->count() > 0)
        @foreach ($ibedTerms as $loop_i => $term)
            {{-- Same term button pattern for JHS/GS --}}
        @endforeach
    @elseif (count($gradessetup) == 0)
        {{-- All 4 quarter buttons --}}
    @else
        {{-- Conditional quarter buttons per gradessetup first/second/third/fourth --}}
    @endif
@endif
```

The term buttons use `value="{{ $term->term_no }}"`, which maps to
`grades.quarter` (the project-wide `quarter == term_no` invariant). The first
term button gets `id="clickme"` for auto-click on page load.

### Change 10 — Blade: dynamic component ECR detection

**File:** `resources/views/teacher/grading/teachergrading.blade.php`

When `loadGrades()` receives the dynamic component-based ECR table (detected
by the `ibed-gv` class in the HTML), it injects the table as-is and keeps the
legacy Update/Export/Submit buttons disabled:

```javascript
function loadGrades() {
    $.ajax({
        url: '/getgrades/' + subjectid,
        type: "GET",
        data: { strandid, syid, gradelevelid, sectionid, subjectid, quarter, semid, clusterplotid },
        success: function(data) {
            $('#tableContainer').empty();
            if (typeof data === 'string' && data.indexOf('ibed-gv') !== -1) {
                // Dynamic component-based ECR table — has its own Save/Submit
                $('#tableContainer').append(data)
            } else {
                // Legacy WW/PT/QA table — enable shared buttons
                $('#updateGrade').removeAttr('disabled')
                $('#btnSubmit').removeAttr('disabled')
                $('#tableContainer').append(data)
            }
        }
    })
}

// Exposed so the dynamic-ECR partial can refresh in-place after Save/Submit
window.loadGrades = loadGrades;
```

The `window.loadGrades` export is critical — without it, the dynamic ECR
partial's own Save/Submit would reload the whole page, losing `curQuarter`
(which is never in the URL) and dumping the teacher back on unselected tabs.

### Change 11 — Blade: term tab status badge styling

**File:** `resources/views/teacher/grading/teachergrading.blade.php`

Each term tab button renders a `<span class="badge data_stat">` badge showing
the status text from `$grade_status`. The badge text is server-rendered from
the controller's status resolution (Change 6):

```blade
@foreach ($ibedTerms as $loop_i => $term)
    <button name="quarter" value="{{ $term->term_no }}" class="btn btn-success"
        {{ $loop_i === 0 ? 'id="clickme"' : '' }}>
        {{ $term->description }} <br>
        <span class="badge data_stat" value="{{ $term->term_no }}">
            {{ collect($grade_status)->where('quarter', $term->term_no)->first()->status ?? '' }}
        </span>
    </button>
@endforeach
```

The button styling behavior:

- **All buttons start as `btn-success`** (green background).
- **On click**, all buttons reset to `#28a745` (green), and the selected
  button gets `#1e7e34` (dark green) to indicate the active term.
- **The badge text** shows the status string: "Submitted", "Partial",
  "Not Submitted", "Approved", "Pending", or "Posted".
- **`#clickme`** on the first term button triggers an auto-click on page
  load, selecting the first term and calling `loadGrades()` automatically.

The `$grade_status` array is built by the controller's 1..4 loop (Change 6),
which maps `quarter` values to `term_no` values — so
`collect($grade_status)->where('quarter', $term->term_no)` correctly looks up
the status for each term.

---

## Dependencies

- **Module 01** — schema (`ibed_term`, `ibed_term_config`, `grades`,
  `gradesdetail`, `subject_gradessetup` tables).
- **Module 04** — grade equivalency (`IbedGradeEquivalency::configAppliesToLevel()`).
- **Module 05** — `IBEDGradingDefaults::shsConfiguredTerms()`,
  `IBEDGradingDefaults::resolveShsPeriods()`,
  `IBEDGradingDefaults::activeConfigQuery()`.
- **Module 07** — the dynamic component ECR (the `/getgrades/{id}` endpoint
  and the IBED grade-view partial with `ibed-gv` layout).
- **Module P2** — subject-plot whole-year conversion (sets
  `subject_plot.semid = NULL`).
- **Module P3** — cluster-plot whole-year conversion (sets
  `sh_cluster_plot.semid = NULL`).

---

## Porting notes / gotchas

1. **`selectedsemester = 0` is the whole-year sentinel.** It's not a real
   semester ID — it's a convention this flow uses to signal "show me
   whole-year/term classes." The controller checks
   `(string) $selectedsemester === '0'` to detect it.

2. **`hasWholeYearTermSetup()` is double-gated.** It checks both
   `sy.term_grading_status = 1` AND `shsConfiguredTerms()` returning terms
   for at least one SHS level. This prevents the "Whole Year" option from
   appearing when the SY flag is on but no actual term config exists.

3. **`getsections()` cluster-plot query uses bare `where('cp.semid', $selectedsemester)`.** When `$selectedsemester = 0`, this becomes
   `where('cp.semid', 0)`. Term-mode cluster plots have `semid = NULL`, so
   they won't appear in the section list via this path. However, the
   `getsubjects()` cluster query IS properly term-gated with
   `whereNull('cp.semid')`. The section list shows the section card (from the
   `sh_classsched` query), and the subjects page shows the cluster elective.

4. **`getsubjects()` checks `grading_percentage_id` first.** For whole-year
   selection, the SHS schedule query includes subjects that have a
   schedule-level `grading_percentage_id` set (even without a subject plot
   row). This covers classes that use the schedule's own grading setup
   instead of the school-wide default subject plot.

5. **`ibedTerms` resolution has two passes.** The first pass only resolves
   terms if a `components_json` grading setup exists. The second pass
   resolves terms regardless — this ensures that legacy ECR classes in a
   term-mode level still get term tabs.

6. **Cluster-plot teacher filtering.** For cluster electives,
   `sh_cluster_plot_teacher.quarter` is intersected with `$ibedTerms` to
   show only the terms the teacher is assigned to. A teacher assigned to
   quarter 2 only sees the "2nd Term" tab.

7. **`window.loadGrades` prevents full-page reload.** The dynamic ECR
   partial calls `window.loadGrades()` after Save/Submit instead of
   `location.reload()`. A full reload loses `curQuarter` (never in the URL),
   resetting the view to no term selected.

8. **Grade-status `orWhereNull('semid')` for SHS.** Some SHS grade headers
   were created with `semid = NULL` before the "adopt orphan header" fix.
   The status query includes `orWhereNull` to catch these, so their status
   reads correctly instead of showing "Not Submitted."

9. **JHS/GS term tabs.** JHS/GS levels don't have the SHS semester split,
   but they DO get term tabs from `$ibedTerms` if a term config applies
   via `configAppliesToLevel()`. The blade checks `$ibedTerms->count() > 0`
   for both SHS and non-SHS levels.

10. **Level IDs 14/15 are school-specific.** Verify in the target school's
    `gradelevel` table.

11. **`ShsClusterSectionScope` is optional.** The cluster elective query in
    `getsubjects()` conditionally joins `sh_cluster_section_assignment` if
    the scope class exists. Without it, the cluster's section name falls
    back to cluster name / subject title.

12. **`/gradesSubmit/{quarter}` needs the same term-mode gate as everything
    else.** It's a pre-existing, shared endpoint (Module 07 assumes it's
    already wired and needs no changes) — but "shared" and "term-mode-safe"
    aren't the same thing. Check every `semid` filter in it against a real
    term-mode header (`semid = NULL`) before trusting a Submit button that
    calls it. See the adaptation note above and `07-teacher-ecr-term.md`.

13. **A header's `semid` can go stale mid-term-mode-conversion.** If a level
    converts to term mode after a class already has quarter headers (created
    while it was still semester-mode), those headers keep their old real
    `semid` forever unless something re-keys them — the tolerant `where
    (semid, X)->orWhereNull(semid)` lookups used elsewhere will happily keep
    reading/writing a stale header, masking the problem until a *strict*
    `whereNull('semid')` consumer (like the submit endpoint in #12) can't
    find it. `reKeyStaleTermHeader()` fixes this at the two header-lookup
    sites in `IBEDECRController` (`view()` and `initializeGradesHeader()`) —
    any new header-lookup added later needs the same treatment, or the same
    class of bug reappears somewhere else.

---

## Verification

1. **Semester-only SY:** Select a non-term SY. Verify "Whole Year" option is
   disabled in the dropdown. Select a semester — section cards and subjects
   appear as before. Open a subject — quarter buttons show, grades load.

2. **Term-mode SHS (index):** Select a term-configured SY. Verify "Whole
   Year (3-Term SHS)" option is enabled. Select it — section cards appear
   for whole-year-plotted levels.

3. **Term-mode SHS (subjects):** Click a section card. Verify:
   - Regular subjects appear as cards.
   - Cluster-plot electives appear with "Elective" badge.
   - Links pass `semid=0` and `clusterplotid` correctly.

4. **Term-mode SHS (grading):** Click a subject. Verify:
   - Term tabs show configured labels (e.g., "First Term", "Second Term",
     "Third Term") with status badges.
   - Clicking a term tab loads the dynamic component table (if
     `components_json` exists) or the legacy WW/PT/QA table.
   - Save Grades and Submit Grades work from the component table.
   - After submit, the tab refreshes in-place (no full page reload).

5. **Cluster-plot elective (grading):** Open a cluster-plot elective in term
   mode. Verify:
   - Only the teacher's assigned terms show as tabs.
   - Grade table loads with correct students.
   - Save and Submit work correctly.

6. **JHS/GS term mode:** Select a JHS level with term config. Verify term
   tabs appear on the grading page with correct labels.

7. **Mixed SY:** In the same SY, have one level on terms and another on
   quarters. Verify both display correctly in their respective modes.

8. **SY switch:** Switch from a term-mode SY to a non-term SY. Verify
   "Whole Year" option disables and the semester falls back to the first
   available real semester.
