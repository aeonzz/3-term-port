# Module P8 — Teacher Final Grades Page

The Teacher Final Grades page (`/teacher/finalgrades`) lets teachers view,
edit, and submit final grades for every subject they're assigned to — SHS
subject-plot classes, GS/JHS assigned-subject classes, and SHS cluster-plot
electives. In term mode the page adapts its period labels, column headers,
grade-status cards, final-grade averaging formula, grade-header creation,
and semester filter visibility to match the configured term count and labels
instead of the fixed 4-quarter layout.

This is a **portal-surface** module (not one of the core 01–10 layers). It
consumes resolvers from **Module 05** — `shsConfiguredTerms()`,
`resolveShsPeriods()`, `resolveTermLabelsForLevel()`, `semesterScope()`,
`shsTermLevels()`, and `activeConfigQuery()` — and depends on **P2**
(subject-plot whole-year conversion) and **P3** (cluster-plot whole-year
conversion) for the data it reads.

> **Ported into `sjhsli_online` in two passes — see known-pitfalls #15.**
> `sjhsli_online`'s copy of this page had no `selected_sched()`-style unified
> class selector and no cluster-plot concept at all, unlike the reference this
> kit doc's Changes 6–11 are lifted from. Pass 1 adapted term-mode logic
> (period maps, FG formulas, header gating) onto the target's existing
> `#filter_subjects`/`#filter_section` + `all_sched.filter(...)` pattern
> without touching cluster support. Pass 2 (done, on the user's explicit
> "full parity" request) built the reference's `selected_sched()` /
> `selected_subject_rows()` / `matches_selected_subject()` /
> `matches_selected_room()` / `can_edit_quarter()` architecture on top of that,
> added the `#filter_room` dropdown, wired `clusterplotid` through every AJAX
> call, and un-deferred `teachingload()`'s cluster items — verified live
> end-to-end against a real cluster-plot assignment. Still deferred: the
> grade-descriptor column (Change 11) — orthogonal to cluster support, but
> touches multiple row-render call sites with colspan implications, held back
> to keep that change's own risk surface isolated. It's an additive
> follow-up, not a blocker.

## Goal — what this port must achieve

After this port, the final grades page correctly handles both quarter-based
and term-based classes within the same school year. Concretely:

1. **Term map (blade).** The blade builds a `TERM_MAP` JS object keyed by
   SY → level → `{term_count, terms[]}`. SHS levels use
   `shsConfiguredTerms()`; non-SHS levels use `activeConfigQuery()` +
   `configAppliesToLevel()`. This drives all client-side period decisions.
2. **Teaching load (controller).** `teachingload()` uses `shsTermLevels()` +
   `semesterScope()` for the SHS schedule query so term-mode classes with
   `semid = NULL` appear. Subject-plot existence check uses
   `resolveShsPeriods()` per item to match `whereNull('semid')` in term mode.
3. **Grade-status headers (controller).** `gradestatus()` creates grade
   headers with `semid = NULL` and `quarter = 1..N` (where N = term count)
   for term-mode classes. Existing semester-keyed headers are re-keyed to
   `semid = NULL` when the level enters term mode.
4. **Enrolled learners (controller).** `enrolled_learners()` gates all
   semester filters — `subject_plot`, `sh_enrolledstud`, `student_specsubj`,
   and `grades` header reads — with term-mode checks so `semid = NULL` rows
   are found.
5. **Period UI swap (blade).** When a term-mode class is selected, the
   quarter-status cards relabel from "1st Quarter" to the configured term
   labels, excess cards (beyond `term_count`) are hidden, column headers
   update, and the semester filter disappears.
6. **Final-grade formula (blade).** The FG computation averages only the
   configured term count (not always 4), hiding unused quarter columns.
7. **Cluster-plot support.** Cluster-plot electives use per-level
   `shsConfiguredTerms()` to gate the `sh_cluster_plot` query by
   `semid IS NULL` in term mode, and restrict grade headers to the
   teacher's assigned quarters intersected with the term span.

**Acceptance criteria (all must hold):**

- [ ] Semester-only SY: page works exactly as before — 4-quarter layout, semester
      filter visible, FG = average of 4 quarters (or 2 for SHS per semester).
- [ ] Term-mode SHS level: quarter-status cards show term labels, excess cards
      hidden, column headers show term labels, FG averages only `term_count`
      periods, semester filter hidden.
- [ ] Term-mode JHS/GS level: same period swap via `resolveTermLabelsForLevel`
      fallback in the blade's term map.
- [ ] Grade headers: in term mode, new headers created with `semid = NULL` and
      `quarter = 1..term_count`. Existing semester-keyed headers re-keyed.
- [ ] Cluster-plot electives: term-mode cluster plots show with correct term
      labels. Teacher can only edit quarters matching their
      `sh_cluster_plot_teacher` assignments (intersected with term span).
- [ ] Save grades: `save_grades()` correctly reads/writes grades with
      `semid = NULL` for term-mode classes.
- [ ] Mixed SY: one level on quarters, another on terms — switching between them
      updates the period display correctly.
- [ ] 4-quarter-shaped config: excluded from term mode by upstream resolvers —
      stays on 4-quarter layout.

> **Report back after applying (do this in chat).** When the port is done, post
> the acceptance criteria as a **ticked checklist** — **✅** applied and verified,
> **✔️** code applied but runtime/live-page test still pending, **⬜** skipped or
> not applicable (say why). Never mark ✅ something you didn't apply.

## Behaviors by level / config state

| Level / config state | Expected behavior |
|----------------------|-------------------|
| **No term config** | Legacy quarter mode — 4 quarter-status cards, 4 column headers, FG = avg of applicable quarters. |
| **Term config, not plotted (SHS)** | `resolveShsPeriods` returns non-term — stays on quarter mode. Term map may have entry but `semid` on the schedule isn't NULL, so `selected_term_cfg()` returns null. |
| **Term config, whole-year plotted (SHS)** | Full term mode — period labels swapped, excess cards hidden, FG averages `term_count` periods, grade headers use `semid = NULL`. |
| **Term config (JHS/GS)** | Term map populated via `activeConfigQuery` — same period swap behavior. |
| **4-quarter-shaped config** | Upstream resolvers exclude it — stays on quarter mode. |

## PREFLIGHT — check the repo FIRST

Before editing, verify these symbols/files exist in the target repo:

```bash
# Module 05 foundation
grep -r "class IBEDGradingDefaults" app/Support/
grep -r "shsTermLevels\|semesterScope\|shsConfiguredTerms\|resolveShsPeriods" app/Support/
grep -r "activeConfigQuery" app/Support/
grep -r "class IbedGradeEquivalency" app/Support/

# Target controller
grep -rl "TeacherFinalGrade" app/Http/Controllers/
grep -n "function teachingload\|function gradestatus\|function enrolled_learners\|function save_grades" \
    app/Http/Controllers/TeacherControllers/TeacherFinalGrade.php

# Target view
grep -rl "finalgrade" resources/views/teacher/grading/

# Cluster section scope (optional)
grep -r "class ShsClusterSectionScope" app/Support/
```

If `shsTermLevels`, `semesterScope`, or `activeConfigQuery` are missing,
apply **Module 05** first.

## Files to check and update

| # | File | What to do |
|---|------|------------|
| 1 | `app/Http/Controllers/TeacherControllers/TeacherFinalGrade.php` | Add term-mode helpers, update `teachingload()`, `gradestatus()`, `enrolled_learners()`, `save_grades()` with term gating |
| 2 | `resources/views/teacher/grading/finalgrade.blade.php` | Build `TERM_MAP` in PHP, add JS period swap (`apply_period_mode`), FG formula branching, semester filter hide |

## Changes

### Change 1 — Controller: term-mode detection helpers

**File:** `app/Http/Controllers/TeacherControllers/TeacherFinalGrade.php`

Add private helpers for checking term mode at the config level (used where
the plotting gate is unnecessary, e.g. cluster plots whose `semid` is already
NULL):

```php
private static function shsConfiguredTermMode($syid, $levelid): bool
{
    if (!$syid || !$levelid) return false;
    $cfg = \App\Support\IBEDGradingDefaults::shsConfiguredTerms($syid, $levelid);
    return !empty($cfg['terms']);
}

private static function shsConfiguredTermCount($syid, $levelid): int
{
    if (!$syid || !$levelid) return 0;
    $cfg = \App\Support\IBEDGradingDefaults::shsConfiguredTerms($syid, $levelid);
    return count($cfg['terms'] ?? []);
}

private static function configuredTermMode($syid, $levelid): bool
{
    // Same as shsConfiguredTermMode — used for JHS/GS levels
    if (!$syid || !$levelid) return false;
    $cfg = \App\Support\IBEDGradingDefaults::shsConfiguredTerms($syid, $levelid);
    return !empty($cfg['terms']);
}

private static function configuredTermCount($syid, $levelid): int
{
    if (!$syid || !$levelid) return 0;
    $cfg = \App\Support\IBEDGradingDefaults::shsConfiguredTerms($syid, $levelid);
    return count($cfg['terms'] ?? []);
}
```

Also add `clusterGradeContext()` for resolving cluster-plot context and
`teacherCanAccessClusterQuarter()` for per-quarter access control.

### Change 2 — Controller: `teachingload()` with `semesterScope`

**File:** `app/Http/Controllers/TeacherControllers/TeacherFinalGrade.php`

Use `shsTermLevels()` + `semesterScope()` on the main SHS schedule query:

```php
$shsTermLevels = \App\Support\IBEDGradingDefaults::shsTermLevels($syid);

$sched = DB::table('sh_classsched')
    ->where('sh_classsched.syid', $syid)
    ->where('sh_classsched.deleted', 0)
    ->where('sh_classsched.teacherid', $teacherid)
    ->when($semid, function ($query) use ($semid, $shsTermLevels) {
        return $query->where(\App\Support\IBEDGradingDefaults::semesterScope(
            $semid, $shsTermLevels,
            'sh_classsched.semid', 'sh_classsched.glevelid'
        ));
    })
    // ... joins
```

Per-item subject-plot existence check uses `resolveShsPeriods()` to match
`whereNull('semid')` in term mode vs `where('semid', $item->semid)` in
semester mode.

### Change 3 — Controller: `teachingload()` cluster-plot query

**File:** `app/Http/Controllers/TeacherControllers/TeacherFinalGrade.php`

Cluster-plot query uses per-level `shsConfiguredTerms()` to gate by
`whereNull('cp.semid')` for term-mode levels:

```php
->when($semid, function ($q) use ($syid, $semid) {
    $grade11TermMode = !empty(\App\Support\IBEDGradingDefaults::shsConfiguredTerms($syid, 14)['terms']);
    $grade12TermMode = !empty(\App\Support\IBEDGradingDefaults::shsConfiguredTerms($syid, 15)['terms']);
    return $q->where(function ($scope) use ($semid, $grade11TermMode, $grade12TermMode) {
        $scope->where(function ($level) use ($semid, $grade11TermMode) {
            $level->where('cp.levelid', 14);
            if ($grade11TermMode) {
                $level->whereNull('cp.semid');
            } else {
                $level->where('cp.semid', $semid);
            }
        })->orWhere(function ($level) use ($semid, $grade12TermMode) {
            // ... same pattern for level 15
        })->orWhere(function ($level) use ($semid) {
            $level->whereNotIn('cp.levelid', [14, 15])->where('cp.semid', $semid);
        });
    });
})
```

Each cluster-plot item gets `assigned_quarters` (the teacher's quarters) and
`plot_quarters` (all teachers' quarters) from `sh_cluster_plot_teacher`.

### Change 4 — Controller: `gradestatus()` term-aware header creation

**File:** `app/Http/Controllers/TeacherControllers/TeacherFinalGrade.php`

`gradestatus()` determines term mode via three paths:

- **Cluster context:** `($semid === null) && shsConfiguredTermMode()`
- **SHS (non-cluster):** `resolveShsPeriods()` (full plotting gate)
- **JHS/GS:** `configuredTermMode()`

In term mode, it creates `term_count` grade headers with `semid = NULL` and
`quarter = 1..term_count`. If headers exist but carry a semester ID, they're
re-keyed to `semid = NULL`:

```php
if ($isTermMode) {
    for ($x = 1; $x <= $termCount; $x++) {
        $check = DB::table('grades')
            ->where('levelid', $levelid)->where('syid', $syid)
            ->where('sectionid', $sectionid)->where('subjid', $subjid)
            ->where('quarter', $x)->where('deleted', 0)->get();

        $hasWholeYearKey = collect($check)->contains(fn($r) => $r->semid === null);

        if (count($check) == 0) {
            DB::table('grades')->insertGetId([
                'syid' => $syid, 'levelid' => $levelid,
                'sectionid' => $sectionid, 'subjid' => $subjid,
                'quarter' => $x, 'deleted' => 0, 'semid' => null,
                // ...
            ]);
        } else if (!$hasWholeYearKey) {
            // Re-key existing semester header to NULL
            DB::table('grades')->whereIn('id', collect($check)->pluck('id')->all())
                ->update(['semid' => null, /* ... */]);
        }
    }
}
```

For cluster-plot electives, the headers are scoped to the teacher's assigned
quarters (intersected with the plot's period span) instead of the full term
count.

The final `gradestatus` read query also branches:

```php
->when($isTermMode, function ($q) { return $q->whereNull('semid'); })
->when(!$isTermMode && ($levelid == 14 || $levelid == 15), function ($q) use ($semid) {
    return $q->where('semid', $semid);
})
```

### Change 5 — Controller: `enrolled_learners()` term gating

**File:** `app/Http/Controllers/TeacherControllers/TeacherFinalGrade.php`

The `enrolled_learners()` method gates semester filters per term mode:

- **`subject_plot` strand lookup:** `whereNull('semid')` in term mode,
  `where('semid', $semid)->orWhereNull('semid')` otherwise.
- **`sh_enrolledstud` query:** drops semester filter in term mode.
- **`student_specsubj` (ADDITIONAL subjects):** drops `semid` filter in
  term mode for both the main query and the join.
- **`grades` header read:** `whereNull('semid')` in term mode.

### Change 6 — Blade: `TERM_MAP` construction

**File:** `resources/views/teacher/grading/finalgrade.blade.php`

The `@php` block builds `$termMap` keyed by `syid → levelid →
{term_count, terms[]}`:

```php
$termMap = [];
$termGradingSYs = DB::table('sy')->where('term_grading_status', 1)->get();

foreach ($termGradingSYs as $termSy) {
    // 1. Build acadTerms from activeConfigQuery — covers JHS/GS
    $termConfigs = \App\Support\IBEDGradingDefaults::activeConfigQuery(
        DB::table('ibed_term_config')
            ->where('syid', $termSy->id)->where('deleted', 0)
    )->get();

    foreach ($termConfigs as $cfg) {
        // ... build $acadTerms[$cfg->acadprogid] from ibed_term rows
    }

    // 2. Map to levels
    foreach ($gradelevels as $level) {
        if (in_array($level->id, [14, 15])) {
            // SHS: use shsConfiguredTerms (config-only, no plotting gate)
            $periods = \App\Support\IBEDGradingDefaults::shsConfiguredTerms($termSy->id, $level->id);
            if (empty($periods['terms'])) continue;
            $levelMap[$level->id] = ['term_count' => ..., 'terms' => ...];
        } else {
            // JHS/GS: use acadprog-based config + configAppliesToLevel
            if (isset($acadTerms[$level->acadprogid])) {
                if (!\App\Support\IbedGradeEquivalency::configAppliesToLevel(...)) continue;
                $levelMap[$level->id] = ...;
            }
        }
    }
}
```

Passed to JS as:
```javascript
window.TERM_MAP = @json((object) $termMap);
window.TERM_GRADING_SY_IDS = @json($termGradingSyIds);
```

### Change 7 — Blade: `get_term_cfg()` and `selected_term_cfg()`

**File:** `resources/views/teacher/grading/finalgrade.blade.php`

```javascript
function get_term_cfg(syid, levelid) {
    return window.TERM_MAP && window.TERM_MAP[syid] && window.TERM_MAP[syid][levelid]
        ? window.TERM_MAP[syid][levelid] : null;
}

function selected_term_cfg(filter_data) {
    if (!filter_data.length) return null;
    var row = filter_data[0];
    var cfg = get_term_cfg($('#filter_sy').val(), row.levelid);
    if (!cfg) return null;
    // Only use term mode if the schedule has semid = NULL (whole-year)
    return row.semid == null || row.semid === '' ? cfg : null;
}
```

The `semid == null` check is critical — it's the client-side equivalent of
the SHS plotting gate. A level with term config but semester-stamped schedules
isn't treated as term mode.

### Change 8 — Blade: `apply_period_mode()` for UI swap

**File:** `resources/views/teacher/grading/finalgrade.blade.php`

```javascript
function apply_period_mode(syid, levelid, selectedCfg) {
    var cfg = selectedCfg || null;

    for (var x = 1; x <= 4; x++) {
        var label = get_period_label(cfg, x, 'Quarter');
        var $card = $('.grade_status[data-quarter="' + x + '"]').closest('.card');
        var $submit = $('.submit_grades[data-quarter="' + x + '"]');

        if (cfg && x > cfg.term_count) {
            $card.attr('hidden', 'hidden').hide();
        } else {
            $card.removeAttr('hidden').show();
            // Relabel: "1st Quarter Status" → "1st Term Status" (or configured label)
            // ...
        }

        $('#dq' + x).text(cfg ? label : PERIOD_ORDINALS[x]);
        if (cfg && x > cfg.term_count) {
            $('#dq' + x).attr('hidden', 'hidden');
        } else {
            $('#dq' + x).removeAttr('hidden');
        }
    }

    // Swap modal label
    $('#modal_period_label').text(cfg ? 'Term' : 'Quarter');
    // Hide semester filter in term mode
    if (cfg) {
        $('#filter_semester').closest('.form-group').hide();
    } else {
        $('#filter_semester').closest('.form-group').show();
    }
}
```

### Change 9 — Blade: final-grade formula branching

**File:** `resources/views/teacher/grading/finalgrade.blade.php`

In the `students()` function, the FG computation branches on `termCfg`:

```javascript
if (termCfg) {
    var termSum = 0;
    var completeTerms = true;
    for (var termIndex = 0; termIndex < termCfg.term_count; termIndex++) {
        var termNo = termCfg.terms[termIndex].term_no;
        var termGrade = [qgrade1, qgrade2, qgrade3, qgrade4][termNo - 1];
        if (termGrade === '') { completeTerms = false; }
        else { termSum += parseInt(termGrade); }
    }
    for (var hideTerm = termCfg.term_count + 1; hideTerm <= 4; hideTerm++) {
        termHidden[hideTerm] = 'hidden="hidden"';
    }
    if (completeTerms) {
        fg = parseFloat(termSum / termCfg.term_count).toFixed();
        remarks = fg >= 75 ? 'PASSED' : 'FAILED';
    }
}
```

This replaces the fixed 4-quarter or 2-quarter-per-semester averaging with
a dynamic `term_count`-based formula.

### Change 10 — Blade: cluster-plot elective FG override

**File:** `resources/views/teacher/grading/finalgrade.blade.php`

Cluster-plot electives compute FG from only the quarters the plot actually
runs (from `plot_quarters`), intersected with the current period span
(`_fgSpan`):

```javascript
var _fgSpan = [1, 2, 3, 4];
if (termCfg) {
    _fgSpan = [];
    for (var _fs = 1; _fs <= termCfg.term_count; _fs++) {
        _fgSpan.push(_fs);
    }
} else if (levelid == 14 || levelid == 15) {
    _fgSpan = (semid == null || semid == '') ? [1,2,3,4] : (semid == 1 ? [1,2] : [3,4]);
}

if (_electivePlotQuarters && _electivePlotQuarters.length) {
    _electiveFgQuarters = _electivePlotQuarters.filter(function(q) {
        return _fgSpan.indexOf(q) !== -1;
    });
}
```

This prevents an elective that runs one quarter from requiring all 3 terms to
have a grade before showing a final grade.

### Change 11 — Blade: grade equivalency / descriptor map

**File:** `resources/views/teacher/grading/finalgrade.blade.php`

A `GRADE_EQUIV_MAP` is built per SY + level using
`IBEDGradingDefaults::resolveConfigForLevel()` and its
`grade_point_equivalence_id` → `ibed_grade_point_scale` rows. When a config
has `display_grade_remarks_description` enabled, the FG table shows a
"Descriptor" column with the matching remarks text.

---

## Dependencies

- **Module 01** — schema (`ibed_term`, `ibed_term_config`, `grades`,
  `gradesdetail` tables).
- **Module 04** — grade equivalency (`ibed_grade_point_scale`,
  `IbedGradeEquivalency::configAppliesToLevel()`).
- **Module 05** — `IBEDGradingDefaults::shsTermLevels()`,
  `IBEDGradingDefaults::semesterScope()`,
  `IBEDGradingDefaults::shsConfiguredTerms()`,
  `IBEDGradingDefaults::resolveShsPeriods()`,
  `IBEDGradingDefaults::activeConfigQuery()`,
  `IBEDGradingDefaults::resolveConfigForLevel()`.
- **Module P2** — subject-plot whole-year conversion.
- **Module P3** — cluster-plot whole-year conversion.

---

## Porting notes / gotchas

1. **Two term-mode detection paths.** The blade's `TERM_MAP` uses
   `shsConfiguredTerms()` (config-only) for SHS levels and
   `activeConfigQuery()` + `configAppliesToLevel()` for JHS/GS. The
   controller's `gradestatus()` uses `resolveShsPeriods()` (config + plotting
   gate) for non-cluster SHS, but `shsConfiguredTermMode()` (config-only) for
   cluster plots. This split is intentional — cluster plots already have
   `semid = NULL` as their own term-mode signal.

2. **`selected_term_cfg()` checks `semid == null`.** The client-side function
   only returns a term config if the schedule row has a null `semid`. This is
   the blade-level plotting gate — a level with term config but
   semester-stamped schedules stays on quarter mode visually.

3. **Grade header re-keying.** `gradestatus()` re-keys existing
   semester-stamped grade headers to `semid = NULL` when the level enters
   term mode. This is critical — without it, `enrolled_learners()` reads
   headers with `whereNull('semid')` and finds nothing, so the grid shows
   no grades.

4. **`grades.quarter` stores term_no in term mode.** This is the project-wide
   invariant (Module 05 invariant #2) — term 1 → `quarter = 1`, term 2 →
   `quarter = 2`, etc. No separate `term_no` column exists.

5. **Elective FG uses `plot_quarters` intersected with `_fgSpan`.** A cluster
   elective that runs in quarter 2 only would need `_fgSpan` to include 2
   for the FG to be computable. In term mode, `_fgSpan = [1..term_count]`.

6. **Cluster-plot teacher access control.** `can_edit_quarter()` checks
   `assigned_quarters` (the logged-in teacher's quarters) to disable grade
   cells for quarters the teacher isn't assigned to. `teacherCanAccessClusterQuarter()`
   enforces the same on the server side.

7. **`semid` in `gradestatus()` for cluster plots.** The cluster context's
   `semid` comes from `sh_cluster_plot.semid` — NULL for term-mode plots.
   Grade headers for cluster electives use the plot's own `semid` (NULL or
   a semester id), not a hardcoded NULL.

8. **Level IDs 14/15 are school-specific.** Verify in the target school's
   `gradelevel` table.

9. **`activeConfigQuery()` in the blade.** The term map build uses
   `activeConfigQuery()` to wrap the `ibed_term_config` query — this ensures
   only `isactive = 1` configs are considered. Bare `deleted = 0` reads are
   the #1 source of ghost term configs.

---

## Verification

1. **Quarter-mode SHS level:** Select a subject in a non-term SY. Verify 4
   quarter-status cards, 4 column headers, semester filter visible. Edit a
   grade and save — verify it persists.

2. **Term-mode SHS level:** Select a subject in a term-configured,
   whole-year-plotted SY+level. Verify:
   - Quarter-status cards relabel to term labels (e.g., "1st Term Status").
   - Excess cards (beyond `term_count`) are hidden.
   - Column headers show term labels.
   - Semester filter is hidden.
   - FG averages only `term_count` periods.
   - Grade headers in the DB have `semid = NULL`.

3. **Term-mode JHS/GS level:** Select a JHS subject with term config. Verify
   the same period swap — term labels, hidden excess cards, correct FG
   formula.

4. **Cluster-plot elective (term mode):** Select a cluster-plot subject in
   term mode. Verify:
   - Only the teacher's assigned quarters are editable.
   - FG uses `plot_quarters` intersected with the term span.
   - Grade headers use `semid = NULL`.

5. **Grade save and submit:** In term mode, save a grade and verify the
   `gradesdetail` row is written under the correct `semid = NULL` header.
   Submit and verify status updates.

6. **Mixed SY:** In the same school year, have one level on quarters and
   another on terms. Switch between subjects at each level — verify the
   period display updates correctly without cross-contamination.

7. **Grade descriptor column:** If a grade equivalency config with
   `display_grade_remarks_description` exists, verify the Descriptor column
   appears and shows the correct remarks text for each FG.
