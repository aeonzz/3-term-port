# Module P11 — Teacher Pending Grades (term-aware)

The **Pending Grades** page lets a teacher view grades that were returned to
them (status = 3 / Pending) and re-submit them after correction. In term mode
the page must:

- iterate over the correct number of periods (term count, not hardcoded 4),
- relabel the quarter picker to show term labels,
- gate all SHS semester queries on term-mode awareness (skip `semid` filter in
  term mode, use `semid IS NULL` for whole-year plots/grades).

This is a **portal-surface** module (not one of the core 01–10 layers). It
consumes the resolvers from **Module 05**.

> **Ported into `sjhsli_online` — six more gaps found once a teacher actually
> used the page against real pending data (all confirmed identical in
> es_ldcu's own source, not porting-fidelity issues — general bugs unrelated
> to term mode, uncovered by term-mode testing):**
>
> 1. `peding_student_grades()`'s pending-subject query required BOTH the
>    `grades` header's own `status == 3` (only set by
>    `TeacherECRv2Controller::pending_ecr()` returning the *entire* class with
>    nothing excluded) AND a real per-student `gdstatus == 3`. The far more
>    common path — a teacher submitting with some students excluded via
>    `FilterController::updateGradeStatus()` — marks those students
>    `gdstatus = 3` without ever touching the header's `status`, so that
>    subject silently never appeared here even though the System Grading
>    page's own "PENDING" badge already showed it. Deliberately diverged from
>    the reference here (dropped the header-status requirement) rather than
>    mirroring its narrower, effectively-dead-for-this-scenario condition.
> 2. The subject-gathering loop only kept a class if a `subject_plot` row
>    existed. Some SHS classes are graded off `sh_classsched.grading_
>    percentage_id` instead (a setup `GradeController::getsubjects()` already
>    treats as equally valid) — that class never entered `$subject` at all,
>    regardless of fix #1.
> 3. `getGrades()`'s `$gradesetup` lookup was also `subject_plot`-only, so a
>    `grading_percentage_id`-based class still got "Grade setup is not
>    configured" after #1/#2 got it listed and selectable. Fixed with a
>    fallback mirroring `IBEDECRController::getComponentSetup()`'s
>    already-established pattern (the schedule's `grading_percentage_id` is
>    the source of truth for a directly-assigned setup).
> 4. `getGrades()` always returned the legacy static `gradestable` view,
>    never checking `components_json` — the exact same gap
>    `TeacherGradingV2::loadGrades()` had before the P9 port wired it to the
>    dynamic ECR. Mirrored that same wiring here (`check_ibed_ecr()` +
>    `/ibed-ecr/view`); the partial's existing per-student locking
>    (`gdstatus` 1/2/4 = locked) turned out to need no extra work — it
>    already keeps Approved/Posted students locked and opens only the
>    Pending ones, exactly this page's purpose.
> 5. Once #4 was wired up, the dynamic table visually overlapped the rest of
>    the page — `#students`' parent `<div>` had a hardcoded `style="height:
>    500px"` with no `overflow` rule. The legacy `gradestable` partial is
>    unaffected (it wraps itself in its own bounded, self-scrolling box), but
>    the dynamic `ibed-gv` partial renders as a normal-flow table with no
>    inner scroll box of its own — the same way it already works inside
>    `teachergrading.blade.php`'s `#tableContainer`, which has **no** height
>    constraint at all. With 30+ students the table was several times taller
>    than 500px and had nothing to clip or scroll it. Fixed by removing the
>    fixed height entirely, matching `#tableContainer`'s own unconstrained
>    wrapper — safe for the legacy view too, since it manages its own scroll
>    box independently of this parent's height.
> 6. The sidebar's "Pending Grades" badge count (`<span class="badge ...
>    student_pending">`, populated by `/teacher/get/pending` on every page
>    load) was already fully wired in this repo, identical to es_ldcu's own
>    sidenav — but the endpoint behind it,
>    `TeacherGradingV2::check_pending()`, is a **separate, independently
>    duplicated** implementation of `peding_student_grades()`'s subject-
>    gathering loop, with the exact same `subject_plot`-only gate as gap #2
>    (also confirmed identical in es_ldcu). Needed the identical
>    `grading_percentage_id` fallback applied a second time, in a second
>    file, since fixing `peding_student_grades()` alone did not touch this
>    duplicate.

## Goal — what this port must achieve

After this port the Pending Grades page works identically for term-mode and
quarter-mode classes. Concretely:

1. **Period loop uses term count.** The listing endpoint iterates over
   `termCount` periods (not 4) so only the configured terms generate pending
   flags.
2. **Quarter picker shows term labels.** When a section resolves to term mode
   the dropdown label says "Term" and lists term names from TERM_MAP instead of
   "Quarter 1 … 4".
3. **Semester filter removed in term mode.** All SHS queries (subject plot,
   grade header, enrolled students, grade insert, submit) either pass
   `semid IS NULL` (whole-year row) or skip the `semid` filter entirely in term
   mode, while keeping the existing `semid` filter for non-term SHS.

**Acceptance criteria (all must hold):**

- [ ] A teacher with a pending grade in a 3-term class sees exactly 3 period
      options (1T / 2T / 3T), not 4 quarters
- [ ] Quarter picker label changes to "Term" in term mode
- [ ] Clicking "View Pending Grades" for a term-mode class loads the correct
      grade table (no "Grade setup is not configured" error)
- [ ] Submitting a pending grade in term mode succeeds and clears the pending
      flag
- [ ] Non-term classes still show 4 quarters with "Quarter" label — no
      regression

> **Report back after applying (do this in chat).** When the port is done, post
> the acceptance criteria as a **ticked checklist** — **✅** applied and verified,
> **✔️** code applied but runtime/live-page test still pending, **⬜** skipped or
> not applicable (say why). Never mark ✅ something you didn't apply.

## Behaviors by level / config state

| Level / config state | Expected behavior |
|----------------------|-------------------|
| **JHS / no term config** | 4 quarters, "Quarter" label, standard semid handling |
| **SHS / no term config** | 4 quarters, semester-filtered queries |
| **SHS / term config, whole-year plotted** | N terms (from config), "Term" label, `semid IS NULL` for whole-year rows, semid filter skipped for enrolled students |
| **SHS / 4-quarter-shaped config** | Treated as term mode with 4 terms — functionally identical to quarters but uses term labels |

## PREFLIGHT — check the repo FIRST

Before editing, verify these symbols/files exist in the target repo:

```bash
# Module 05 foundation
grep -r "class IBEDGradingDefaults" app/Support/
grep -r "resolveShsPeriods" app/Support/

# Target files
grep -rl "class TeacherPendingGrade" app/Http/Controllers/
grep -rl "pendinggrade" resources/views/teacher/grading/
```

If any are missing, stop and tell the user which prerequisite module to apply
first.

## Reference implementation (es_ldcu)

| Piece | Path / symbol |
|-------|---------------|
| Controller | `app/Http/Controllers/TeacherControllers/TeacherPendingGrade.php` |
| View | `resources/views/teacher/grading/pendinggrade.blade.php` |
| Routes | `routes/web.php` — `teacher/pending/grades/view` (view), `teacher/pending/grade/list` (`peding_student_grades`), `teacher/pending/grade/list/getgrades/{id}` (`getGrades`), `teacher/pending/grade/submit/grades` (`submit_pending_grades`) |

## Dependencies

- **Module 01** — schema (`ibed_term_config` table).
- **Module 05** — `IBEDGradingDefaults::resolveShsPeriods()` for term detection.
- **P2** — whole-year subject plots (`semid IS NULL`) that the resolver checks.
- **P3** — cluster plotting (cluster sections use the offset-id pattern).

---

## Files to check and update

| # | File | What to do |
|---|------|------------|
| 1 | `app/Http/Controllers/TeacherControllers/TeacherPendingGrade.php` | Add term-mode detection to all 3 methods |
| 2 | `resources/views/teacher/grading/pendinggrade.blade.php` | Add `$termMap` server block, TERM_MAP JS, `get_term_cfg()`, quarter-picker relabeling, semid logic in AJAX calls |

---

## Changes

### Change 1 — `peding_student_grades()`: term-aware period loop

**File:** `app/Http/Controllers/TeacherControllers/TeacherPendingGrade.php`
— inside the `foreach($subject as $item)` loop

Instead of looping `for($x = 1; $x <= 4; $x++)`, resolve the period count
from the term config:

```php
$periods = \App\Support\IBEDGradingDefaults::resolveShsPeriods($syid, $item->levelid);
$isTermMode = ($item->levelid == 14 || $item->levelid == 15) && !empty($periods['isTermMode']);
$periodCount = $isTermMode ? (int) $periods['termCount'] : 4;

for($x = 1; $x <= $periodCount; $x++){
    // … existing pending-check logic unchanged …
}
```

**Why:** Without this, a 3-term class would only check quarters 1–3 (correct
by accident for 3 terms) but a 2-term or 5-term config would check the wrong
number of periods.

### Change 2 — `getGrades()`: term-mode semester gating

**File:** `app/Http/Controllers/TeacherControllers/TeacherPendingGrade.php`
— `getGrades()` method

Detect term mode at the top of the method:

```php
$periods = \App\Support\IBEDGradingDefaults::resolveShsPeriods($syid, $gradelevelid);
$pgTermMode = ($gradelevelid == 14 || $gradelevelid == 15) && !empty($periods['isTermMode']);
```

Then apply the term/semester gate to every SHS query that touches `semid`:

**2a — Subject-plot query** (grade setup lookup):

```php
if($gradelevelid == 14 || $gradelevelid == 15){
    $gradesetup = $gradesetup->where('strandid', $request->get('strandid'))
                              ->when(!$pgTermMode, function($q) use ($semid){
                                  return $q->where('semid', $semid);
                              })
                              ->when($pgTermMode, function($q){
                                  return $q->whereNull('semid');
                              });
}
```

**2b — Grade header query:**

```php
$grade_header = DB::table('grades')
    ->where('sectionid', $gradeSectionId)
    // ... other wheres ...
    ->when($pgTermMode, function($q){
        return $q->whereNull('semid');
    })
    ->when(!$pgTermMode && ($gradelevelid == 14 || $gradelevelid == 15), function($q) use ($semid){
        return $q->where('semid', $semid);
    })
    ->where('deleted', 0)
    ->where('subjid', $subjectid)
    ->get();
```

**2c — New grade insert** (when no `grades` row exists yet):

```php
$gradeId = DB::table('grades')->insertGetId([
    // ... other columns ...
    'semid' => $pgTermMode ? null : $semid
]);
```

**2d — SHS enrolled-student query:**

```php
$enrolledstud = DB::table('sh_enrolledstud')
    // ... joins ...
    ->when(!$pgTermMode, function($q) use ($semid){
        return $q->where('sh_enrolledstud.semid', $semid);
    })
    // ... rest unchanged ...
```

The `semid` filter is skipped entirely in term mode (whole-year enrollment
spans all terms).

**2e — Subject strand query:**

```php
$subject_strand = DB::table('subject_plot')
    ->where('syid', $syid)
    ->where('levelid', $gradelevelid)
    ->where('subjid', $subjectid)
    ->when(!$pgTermMode, function($q) use ($semid){
        return $q->where('semid', $semid);
    })
    ->when($pgTermMode, function($q){
        return $q->whereNull('semid');
    })
    ->where('deleted', 0)
    ->select('strandid')
    ->get();
```

**2f — SHS student_specsubj (additional students):**

```php
->join('sh_enrolledstud', function($join) use($syid, $semid, $pgTermMode){
    $join->on('student_specsubj.studid', '=', 'sh_enrolledstud.studid');
    $join->whereIn('sh_enrolledstud.studstatus', [1, 2, 4]);
    $join->where('sh_enrolledstud.deleted', 0);
    $join->where('sh_enrolledstud.syid', $syid);
    if(!$pgTermMode){
        $join->where('sh_enrolledstud.semid', $semid);
    }
})
// ... also:
->when(!$pgTermMode, function($q) use ($semid){
    return $q->where('student_specsubj.semid', $semid);
})
```

### Change 3 — `submit_pending_grades()`: term-mode semester gating

**File:** `app/Http/Controllers/TeacherControllers/TeacherPendingGrade.php`
— `submit_pending_grades()` method

Detect term mode:

```php
$periods = \App\Support\IBEDGradingDefaults::resolveShsPeriods($syid, $levelid);
$isTermMode = isset($levelinfo->acadprogid) && $levelinfo->acadprogid == 5
              && !empty($periods['isTermMode']);
```

Then apply to all three grade queries (detail update, header count, grade
status update):

```php
if($isTermMode){
    $detailQuery->whereNull('semid');
}else if(isset($levelinfo->acadprogid) && $levelinfo->acadprogid == 5){
    $detailQuery->where('semid', $semid);
}
```

The same `if/else if` pattern repeats for `$headerCountQuery` and
`$gradeQuery`. The `semid` value arriving from the client is `null` (string
`'null'`) in term mode — normalized at the top:

```php
if($semid == 'null' || $semid == '' || $semid == '0' || $semid === 0){
    $semid = null;
}
```

### Change 4 — Blade: `$termMap` server-side block

**File:** `resources/views/teacher/grading/pendinggrade.blade.php`
— inside the `@php` block at the top of `@section('content')`

```php
$termMap = [];
foreach ($sy as $termSy) {
    foreach ([14, 15] as $shsLevelId) {
        $periods = \App\Support\IBEDGradingDefaults::resolveShsPeriods($termSy->id, $shsLevelId);
        if (!empty($periods['isTermMode']) && !empty($periods['terms'])) {
            foreach ($periods['terms'] as $term) {
                $termMap[$termSy->id][$shsLevelId]['terms'][] = [
                    'term_no' => (int) $term['term_no'],
                    'label'   => $term['label'],
                ];
            }
            $termMap[$termSy->id][$shsLevelId]['term_count'] = (int) $periods['termCount'];
        }
    }
}
```

This is the same TERM_MAP pattern used in P10 (grade summary) but **without**
the cluster-plot fallback — the pending grades page already handles cluster
sections via the `CLUSTER_SECTION_ID_OFFSET` mechanism in the controller.

### Change 5 — Blade: TERM_MAP JS + `get_term_cfg()` helper

**File:** `resources/views/teacher/grading/pendinggrade.blade.php`
— in the `@section('footerjavascript')` block

Expose the map to JS:

```html
<script>
    window.TERM_MAP = @json((object) $termMap);
</script>
```

Inside `$(document).ready()`:

```js
function get_term_cfg(syid, levelid) {
    return window.TERM_MAP && TERM_MAP[syid] && TERM_MAP[syid][levelid]
        ? TERM_MAP[syid][levelid] : null
}
```

### Change 6 — Blade: quarter picker relabeling

**File:** `resources/views/teacher/grading/pendinggrade.blade.php`
— inside the `#filter_section` change handler

When a section is selected, the picker label and options are set based on term
config:

```js
var termCfg = get_term_cfg($('#filter_sy').val(), selected[0].levelid)

$('#filter_quarter_label').text(termCfg ? 'Term' : 'Quarter')

if (termCfg) {
    $("#filter_quarter").append('<option value="">Select Term</option>')
    $.each(termCfg.terms, function(index, term) {
        var check = selected[0].pending_quarter.filter(quarter => quarter == term.term_no)
        var pending = check.length ? '<div class="badge badge-warning">Pending</div>' : ''
        temp_quarter.push({
            'id': term.term_no,
            'text': term.label + ' ' + pending,
            'html': term.label + ' ' + pending,
        })
    })
} else {
    $("#filter_quarter").append('<option value="">Select Quarter</option>')
    for (var x = 1; x <= 4; x++) {
        var check = selected[0].pending_quarter.filter(quarter => quarter == x)
        var pending = check.length ? '<div class="badge badge-warning">Pending</div>' : ''
        temp_quarter.push({
            'id': x,
            'text': 'Quarter ' + x + ' ' + pending,
            'html': 'Quarter ' + x + ' ' + pending,
        })
    }
}
```

### Change 7 — Blade: `load_grades()` semid resolution

**File:** `resources/views/teacher/grading/pendinggrade.blade.php`
— inside the `load_grades()` function

```js
var termCfg = get_term_cfg(syid, levelid)
var semid = 1

if ((selected[0].levelid == 14 || selected[0].levelid == 15) && !termCfg) {
    semid = selected[0].semid
} else if (termCfg) {
    semid = null
}
```

This `semid` is passed to the `getGrades` AJAX call. The controller uses it
for the semester gate (Change 2).

### Change 8 — Blade: submit grades semid resolution

**File:** `resources/views/teacher/grading/pendinggrade.blade.php`
— inside the `#btnSubmit` click handler

```js
var termCfg = get_term_cfg(syid, levelid)
var semid = (selected[0].levelid == 14 || selected[0].levelid == 15) && !termCfg
    ? selected[0].semid : 1
if (termCfg) {
    semid = null
}
```

This `semid` is passed to the `submit_pending_grades` AJAX call (Change 3).

---

## Porting notes / gotchas

1. **`CLUSTER_SECTION_ID_OFFSET`** — This controller uses a
   `900000 + plotid` offset to represent cluster sections as virtual section
   ids. The term changes don't alter this mechanism, but be aware of it when
   reading the code — `$gradeSectionId` is the real id used for `grades`
   queries, while `$sectionid` may be the offset version.

2. **No cluster-plot fallback in `$termMap`** — Unlike P10 (grade summary),
   this blade's `$termMap` does not check `sh_cluster_plot.semid IS NULL` as a
   fallback for term detection. The controller handles cluster sections
   separately via the offset mechanism and `resolveShsPeriods` on the real
   level id, so the blade-level detection is sufficient.

3. **`semid` normalization** — The `submit_pending_grades` method normalizes
   incoming `semid` values (`'null'`, `''`, `'0'`, `0` → `null`). This handles
   the JS `null` being serialized to the string `'null'` in the AJAX request.
   Ensure the target repo has this normalization.

4. **`activeConfigQuery()` invariant** — This module does **not** directly
   read `ibed_term_config`. All term detection goes through
   `IBEDGradingDefaults::resolveShsPeriods()`, which uses `activeConfigQuery()`
   internally. No additional wrapping is needed here.

5. **JHS levels are unaffected** — The term-mode checks are all gated on
   `levelid == 14 || levelid == 15` (SHS). JHS levels pass through the
   original code paths unchanged.

6. **`grades.quarter` = `term_no`** — This controller reads and writes
   `quarter` for term-mode classes. The `quarter` column doubles as `term_no`
   per the kit invariant — no new column is needed.

---

## Verification

1. **Term-mode SHS class with pending grades:**
   - Open `/teacher/pending/grades/view`
   - Select a school year and subject assigned to a term-mode SHS class
   - Verify the quarter picker shows term labels (e.g. "1st Term", "2nd Term",
     "3rd Term") instead of "Quarter 1 … 4"
   - Verify the picker label reads "Term" not "Quarter"
   - Click "View Pending Grades" — the grade table should load without errors

2. **Submit pending grade in term mode:**
   - Edit a grade value and click "UPDATE GRADES"
   - Click "SUBMIT GRADES" — should succeed without errors
   - Verify the pending badge clears from the quarter picker

3. **Non-term SHS class (semester mode):**
   - Select a subject in a non-term SHS class
   - Verify the picker shows "Quarter 1 … 4" with "Quarter" label
   - Verify grades load and submit correctly

4. **JHS class:**
   - Select a JHS subject
   - Verify standard 4-quarter behavior — no term labels, no regressions

5. **Cluster-plot elective in term mode:**
   - If a teacher is assigned to a cluster-plot subject in a term-mode SHS
     level, verify it appears in the subject list and loads grades correctly
