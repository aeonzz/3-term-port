# Module 11 — SF10 Permanent Record (term layout)

The **SF10 (School Form 10 / Learner's Permanent Academic Record)** — formerly
Form 137 — renders a student's complete grade history across all school years
and levels. This module covers **both SHS and JHS** SF10 paths:

- **SHS (senior):** Currently structured as **2 semesters × 2 quarters** per
  level (Q1+Q2 for 1st sem, Q3+Q4 mapped to Q1+Q2 for 2nd sem). In term mode,
  each level should show a **single whole-year section** with **N term columns**
  (1T/2T/3T) instead of the semester split.
- **JHS (junior):** Currently structured as **4 quarters** per level (Q1/Q2/Q3/Q4),
  no semester concept. In term mode, the 4 hardcoded quarter columns should
  become **N dynamic term columns**.

**Status: NOT YET PORTED.** Module 10 already notes that SF10 shows "no term
resolution" and should be treated as not yet ported. This module documents the
scope of work needed to make SF10 term-aware, following the SF9 pattern from
Module 10.

> Copy-the-files module. Both controller methods
> (`reportsschoolform10getrecords_senior` and `_junior`) are >500 lines each
> with many school-specific branches, and the grade table / PDF blades are
> school-specific. This guide gives the architecture, the change sites, and
> the pattern to follow — but the actual edit will touch multiple
> school-specific code paths.

---

## Reference implementation (es_ldcu)

| Piece | Path / symbol |
|-------|---------------|
| SF10 index (student list) | `app/Http/Controllers/Form10Controller.php` |
| **SHS controller** | `app/Http/Controllers/RegistrarControllers/FormReportsController.php` → `reportsschoolform10getrecords_senior()` (~9614), `reportsschoolform10view()` (~2324) |
| **JHS controller** | `FormReportsController.php` → `reportsschoolform10getrecords_junior()` (~6099) |
| SF10 view page (senior) | `resources/views/registrar/forms/form10/viewsenior.blade.php`, `resources/views/teacher/forms/form10/viewsenior.blade.php` |
| SF10 view page (junior) | `resources/views/registrar/forms/form10/viewjunior.blade.php`, `resources/views/teacher/forms/form10/viewjunior.blade.php` |
| SF10 grade table (SHS) | `resources/views/registrar/forms/form10/shs/gradestable.blade.php` (+ `gradestable_v2.blade.php`) |
| SF10 grade table (v3) | `resources/views/registrar/forms/form10/v3/records_shs.blade.php` |
| **SF10 grade table (JHS)** | `resources/views/registrar/forms/form10/jhs/gradestable.blade.php` |
| SF10 PDF export (senior) | `resources/views/registrar/pdf/pdf_schoolform10_senior.blade.php` (+ school variants: `_taborin`, `_seniorbct`, `_seniorlhs`, `_seniorsjaes`, `_seniormcs`) |
| **SF10 PDF export (junior)** | `resources/views/registrar/pdf/pdf_schoolform10_junior.blade.php` (+ school variants: `_juniordcc`, `_juniorlhs`, `_juniorsjaes`, `_juniorxai`) |
| SF10 PDF export routing | `FormReportsController` → selects template by school abbreviation (~11106–11140) |
| Routes | `routes/web.php` — `/reports_schoolform10/getrecordssenior`, `/reports_schoolform10/getrecordsjunior`, `/form10`, `reportsschoolform10*` |
| Grade fetching | `app/Http/Controllers/SuperAdminController/StudentGradeEvaluation.php` → `sf9_grades()`, `sf9_grades_gv2()` |
| Grade fetching (alt) | `app/Models/Principal/GenerateGrade.php` → `reportCardV3()`, `reportCardV5()` |

---

## Dependencies

- **Module 01** — schema (`ibed_term_config`, `ibed_term` tables).
- **Module 05** — `IBEDGradingDefaults::resolveShsPeriods()` for SHS term
  detection, `IBEDGradingDefaults::resolveTermLabelsForLevel()` for JHS term
  detection, `activeConfigQuery()` for safe config reads.
- **Module 09** — computed per-term grades in `gradesdetail`
  (`grades.quarter` == `term_no`).
- **Module 10** — the SF9 term pattern this module should mirror (specifically
  `resolveShsSf9Terms()` and the SF9 blade's term branch).

---

## How it works today (no term awareness)

### A. SHS path — Controller flow (`reportsschoolform10getrecords_senior`)

1. **Enumerate grade levels** for the student's academic program.
2. **Loop over enrollment records** (`$schoolyears` from `sh_enrolledstud`) —
   each row represents a *semester* enrollment (distinct `syid` + `semid`).
3. **Fetch grades** per school year + semester — delegates to school-specific
   grade methods (`sf9_grades`, `sf9_grades_gv2`, `reportCardV3`, etc.).
4. **Filter grades by semester** — `collect($grades)->where('semid', $sy->semid)`.
5. **Map quarters to Q1/Q2** per semester:
   - 1st semester: `q1 = quarter1`, `q2 = quarter2`
   - 2nd semester: `q1 = quarter3`, `q2 = quarter4`
6. **Compute final grade** — `(q1 + q2) / 2`.
7. **Check sf10grades_addinauto** for manual grade overrides (per semester,
   per quarter).
8. **Return grade table blade** with semester-structured data.

### SHS grade table blade (`shs/gradestable.blade.php`)

- Two semester blocks per level: 1st sem subjects, then 2nd sem subjects.
- Each block has hardcoded **Q1 + Q2 columns** + Final Grade + Action Taken.
- "Sem" header shows "1st" or "2nd".
- Subjects filtered by `semid` (1 or 2).

### SHS PDF blade (`pdf_schoolform10_senior.blade.php`)

- Same semester layout — renders per-semester grade tables.
- Hardcoded "Quarter" header with Q1/Q2 columns.
- Grades filtered by `semid`.
- General average computed per semester.

### B. JHS path — Controller flow (`reportsschoolform10getrecords_junior`)

1. **Enumerate grade levels** for the student (junior-high levels from
   `gradelevel`).
2. **Loop over enrollment records** (`$schoolyears` from `enrolledstud` — note:
   **not** `sh_enrolledstud`) — each row represents a *school-year* enrollment
   (no semester split; JHS enrollments are per SY, not per semester).
3. **Fetch grades** per school year — delegates to school-specific grade methods
   (same `sf9_grades`, `sf9_grades_gv2`, `reportCardV3`, etc.).
4. **No semester filtering** — JHS grades are not semester-gated.
5. **Map quarter columns directly:**
   - `q1 = quarter1`, `q2 = quarter2`, `q3 = quarter3`, `q4 = quarter4`
6. **Compute final grade** — `($grade->q1 + $grade->q2 + $grade->q3 + $grade->q4) / 4`.
7. **Check sf10grades_addinauto** for manual grade overrides (per quarter 1–4,
   no `semid` filter).
8. **Return grade table blade** with 4-quarter-structured data.

### JHS grade table blade (`jhs/gradestable.blade.php`)

- One block per level (no semester split).
- Hardcoded **4 quarter columns**: "1st", "2nd", "3rd", "4th" + Final Grade +
  Remarks.
- Grade data accessed as `$grade->q1` through `$grade->q4`.
- `$grade->finalrating` for the final grade.
- Supports both auto-generated (`$eachrecord->type == 1`, read-only display)
  and manual records (editable `input` fields).
- JS `btn-saverecord` handler collects `input-q1` through `input-q4` for save.

### JHS PDF blade (`pdf_schoolform10_junior.blade.php`)

- Same 4-quarter layout — renders per-level grade tables.
- Hardcoded `quarter1`/`quarter2`/`quarter3`/`quarter4` columns.
- No semester filter.
- 5 variants: default, `_juniordcc`, `_juniorlhs`, `_juniorsjaes`, `_juniorxai`.

### JHS view page ("Add new record" modal)

**File:** `resources/views/registrar/forms/form10/viewjunior.blade.php`

The "Add New Record" modal (`#modal-addnew`, line ~511) has **no semester
picker** — only grade level + school year, which is correct for JHS's
whole-year enrollment model.

---

## What needs to change for term mode

### Key difference: SHS vs JHS term detection

| | SHS | JHS |
|---|---|---|
| **Resolver** | `resolveShsPeriods()` (config + whole-year plot gate) | `resolveTermLabelsForLevel()` (config only, no plot gate) |
| **Term helper** | `resolveShsSf9Terms()` | returns labels directly from config |
| **Today's structure** | 2 semesters × 2 quarters | 4 quarters (no semester) |
| **Term mode structure** | 1 whole-year block × N terms | 1 block × N terms |
| **Enrollment table** | `sh_enrolledstud` | `enrolledstud` |
| **Complexity** | Must merge 2 semester rows into 1 whole-year | Already whole-year — simpler |

### Architecture decision

**SHS term mode** — a level's SF10 record should display as:

| Before (semester mode) | After (term mode) |
|------------------------|-------------------|
| **1st Sem:** Q1, Q2, Final, Remarks | **Whole Year:** 1T, 2T, 3T, Final, Remarks |
| **2nd Sem:** Q1, Q2, Final, Remarks | *(no second block)* |
| Subjects split by semester | All subjects in one block (whole-year plot) |
| `grades.quarter` 1/2 → sem 1, 3/4 → sem 2 | `grades.quarter` 1/2/3 → term_no directly |
| Final = (Q1+Q2)/2 | Final = average of N terms |

**JHS term mode** — a level's SF10 record should display as:

| Before (4-quarter mode) | After (term mode) |
|-------------------------|-------------------|
| Q1, Q2, Q3, Q4, Final, Remarks | 1T, 2T, 3T, Final, Remarks |
| 4 hardcoded quarter columns | N dynamic term columns |
| `grades.quarter` 1/2/3/4 → quarter index | `grades.quarter` 1/2/3 → term_no directly |
| Final = (Q1+Q2+Q3+Q4)/4 | Final = average of N terms |

### Change sites — SHS (Sites 1–9)

#### Site 1 — Controller: term detection

**File:** `FormReportsController.php` → `reportsschoolform10getrecords_senior()`

At the top of the per-schoolyear loop (`foreach($schoolyears as $sy)`), detect
term mode for the enrollment's SY + level:

```php
$shsPeriods = \App\Support\IBEDGradingDefaults::resolveShsPeriods($sy->syid, $sy->levelid);
$isTermMode = !empty($shsPeriods['isTermMode']);
$shsTerms = collect();
if ($isTermMode) {
    $shsTerms = self::resolveShsSf9Terms($sy->syid, $sy->levelid);
    $isTermMode = $shsTerms->count() > 0;
}
```

This reuses the `resolveShsSf9Terms()` helper already in `FormReportsController`
(from Module 10's SF9 work, ~line 16617).

#### Site 2 — Controller: semester loop consolidation

Currently `$schoolyears` contains one row per semester enrollment. In term
mode, a student's two semester rows (semid=1 and semid=2 for the same SY +
level) should be **merged into one whole-year record**. Either:

- **Option A (recommended):** After fetching `$schoolyears`, group by
  `syid + levelid` when term mode is detected, and process each group once
  instead of once per semester.
- **Option B:** Keep the per-semester loop but skip the 2nd-semester iteration
  when term mode is active (handle all terms in the 1st pass).

#### Site 3 — Controller: grade fetching (term-aware)

The school-specific grade methods (`sf9_grades`, `reportCardV3`, etc.) already
receive `$syid` and `$strand` but are semester-filtered downstream. In term
mode:

- Pass `semid = null` (or omit it) so the grade method returns grades for all
  terms.
- The grade data comes back with `quarter1`…`quarter4` or similar — in term
  mode, `quarter1` = 1T grade, `quarter2` = 2T grade, `quarter3` = 3T grade,
  and `quarter4` is null (for 3-term).
- **Do not** remap quarter3/4 to q1/q2. In term mode, each quarter column maps
  directly to its term number.

#### Site 4 — Controller: final grade computation

Replace the hardcoded `(q1 + q2) / 2` with:

```php
if ($isTermMode) {
    $termGrades = array_filter([$subject->quarter1, $subject->quarter2, $subject->quarter3, ...], fn($g) => $g !== null && $g > 0);
    $qg = count($termGrades) > 0 ? array_sum($termGrades) / count($termGrades) : null;
} else {
    $qg = ($subject->q1 + $subject->q2) / 2;
}
```

#### Site 5 — Controller: sf10grades_addinauto (manual overrides)

The manual override table `sf10grades_addinauto` is queried per semester +
quarter. In term mode, query by `term_no` instead of quarter, and skip the
`semid` filter:

```php
$chekifaddinautoexist = DB::table('sf10grades_addinauto')
    ->where('studid', $studinfo->id)
    ->where('subjid', $subject->subjid)
    ->where('levelid', $sy->levelid)
    ->where('syid', $sy->syid)
    ->when(!$isTermMode, function($q) use ($sy) {
        return $q->where('semid', $sy->semid);
    })
    ->where('deleted', 0)
    ->get();
```

#### Site 6 — Controller: attendance

`sf10attendance` is currently queried with `semid`. In term mode, either:
- Query without `semid` filter (show whole-year attendance), or
- Map term periods to attendance months (school-specific).

#### Site 7 — Grade table blade: dynamic term columns

**File:** `resources/views/registrar/forms/form10/shs/gradestable.blade.php`
(and `gradestable_v2.blade.php`, `v3/records_shs.blade.php`)

Pass `$isTermMode` and `$shsTerms` to the blade. Add a term branch:

```blade
@if(!empty($isTermMode) && count($shsTerms) > 0)
    {{-- Single whole-year block with N term columns --}}
    <tr>
        <th>Indication</th>
        <th>Subjects</th>
        @foreach($shsTerms as $t)
            <th>{{ $t->short_code ?? $t->description }}</th>
        @endforeach
        <th>Final Grade</th>
        <th>Action Taken</th>
    </tr>
@else
    {{-- Legacy semester layout: Q1, Q2, Final, Action --}}
@endif
```

Replace the "Sem" header with the term label, and the two-semester block with
a single whole-year block.

#### Site 8 — PDF blade: dynamic term columns

**File:** `resources/views/registrar/pdf/pdf_schoolform10_senior.blade.php`
(and all school variants)

Same pattern as Site 7 — add a term branch that renders N term columns instead
of the hardcoded Q1/Q2 semester layout.

#### Site 9 — View page: "Add new record" modal

**File:** `resources/views/registrar/forms/form10/viewsenior.blade.php`

The "Add New Record" modal (line ~596) has a hardcoded semester picker:
```html
<select id="select-addnewsemid">
    <option value="1">1st Sem</option>
    <option value="2">2nd Sem</option>
</select>
```

In term mode, this should either be hidden (whole-year records don't have a
semester) or replaced with a term picker.

### Change sites — JHS (Sites 10–15)

JHS is **simpler** than SHS because there's no semester consolidation — the
record is already whole-year. The changes are about replacing the hardcoded
4-quarter columns with dynamic N-term columns.

#### Site 10 — JHS controller: term detection

**File:** `FormReportsController.php` → `reportsschoolform10getrecords_junior()`

At the top of the per-schoolyear loop, detect term mode using
`resolveTermLabelsForLevel` (Module 05) — **not** `resolveShsPeriods`, which
requires the SHS whole-year plotting gate:

```php
$termLabels = \App\Support\IBEDGradingDefaults::resolveTermLabelsForLevel($sy->syid, $sy->levelid);
$isTermMode = !empty($termLabels);
```

`resolveTermLabelsForLevel` returns an array of term label objects (or empty
array / null if not in term mode). It reads `ibed_term_config` via
`activeConfigQuery()` — no extra wrapping needed.

#### Site 11 — JHS controller: grade column mapping

Currently grades are mapped as:
```php
$grade->q1 = $grade->quarter1;
$grade->q2 = $grade->quarter2;
$grade->q3 = $grade->quarter3;
$grade->q4 = $grade->quarter4;
```

In term mode, `quarter1`/`quarter2`/`quarter3` map directly to term 1/2/3
grades (consistent with `grades.quarter` = `term_no`). `quarter4` is null for
3-term configs. **No remapping needed** — just don't assume there are always
exactly 4 grade columns.

#### Site 12 — JHS controller: final grade computation

Replace the hardcoded 4-quarter average:

```php
if ($isTermMode) {
    $termGrades = array_filter(
        [$grade->quarter1, $grade->quarter2, $grade->quarter3, $grade->quarter4],
        fn($g) => $g !== null && $g > 0
    );
    $finalGrade = count($termGrades) > 0
        ? array_sum($termGrades) / count($termGrades)
        : null;
} else {
    $finalGrade = ($grade->q1 + $grade->q2 + $grade->q3 + $grade->q4) / 4;
}
```

#### Site 13 — JHS controller: sf10grades_addinauto (manual overrides)

The manual override table is queried per quarter 1–4. In term mode, `quarter`
serves as `term_no` and there is no `semid` to filter on (JHS has no semester
concept anyway, so this may already work without change). Verify the query:

```php
$chekifaddinautoexist = DB::table('sf10grades_addinauto')
    ->where('studid', $studinfo->id)
    ->where('subjid', $subject->subjid)
    ->where('levelid', $sy->levelid)
    ->where('syid', $sy->syid)
    ->where('deleted', 0)
    ->get();
```

In term mode, the override `quarter` column = `term_no` (1, 2, or 3 for
3-term), consistent with the kit invariant.

#### Site 14 — JHS grade table blade: dynamic term columns

**File:** `resources/views/registrar/forms/form10/jhs/gradestable.blade.php`

Pass `$isTermMode` and `$termLabels` to the blade. The blade currently renders
hardcoded columns for 1st/2nd/3rd/4th quarters. Add a term branch:

```blade
@if(!empty($isTermMode) && count($termLabels) > 0)
    {{-- Dynamic N-term columns --}}
    <tr>
        <th style="width: 30%;">Subjects</th>
        @foreach($termLabels as $t)
            <th>{{ $t->short_code ?? $t->description }}</th>
        @endforeach
        <th style="width: 8%;">Final</th>
        <th style="width: 15%;">Remarks</th>
    </tr>
@else
    {{-- Legacy 4-quarter layout: 1st, 2nd, 3rd, 4th, Final, Remarks --}}
    <tr>
        <th style="width: 30%;">Subjects</th>
        <th>1st</th>
        <th>2nd</th>
        <th>3rd</th>
        <th>4th</th>
        <th style="width: 8%;">Final</th>
        <th style="width: 15%;">Remarks</th>
    </tr>
@endif
```

Also update the grade data cells — in term mode, render only N term grade
cells (not always 4), and update the JS `btn-addrow` handler to append the
correct number of grade input fields.

#### Site 15 — JHS PDF blade: dynamic term columns

**File:** `resources/views/registrar/pdf/pdf_schoolform10_junior.blade.php`
(and all school variants: `_juniordcc`, `_juniorlhs`, `_juniorsjaes`,
`_juniorxai`)

Same pattern as Site 14 — add a term branch that renders N term columns
instead of the hardcoded `quarter1`/`quarter2`/`quarter3`/`quarter4` layout.

The PDF blade references `$grade->quarter1` through `$grade->quarter4`
directly (lines ~332–335, ~348–351, ~641–644, ~657–660). In term mode:
- Render only the term columns that exist (based on `$termLabels` count).
- `quarter4` will be null for 3-term configs — don't render it.

---

## Porting notes / gotchas

1. **School-specific branches.** `reportsschoolform10getrecords_senior` has
   many `if/elseif` branches keyed on `schoolinfo.abbreviation` (`sihs`,
   `sjaes`, `svai`, `spct`, `hcb`, `csl`, `lhs`, `bct`, `mcs`, etc.). Each
   branch uses a different grade-fetching method. The term-mode changes must
   be applied to **every branch that the target school uses**, not just the
   default `else` branch.

2. **Multiple blade variants.** There are 6+ PDF blade variants for SF10
   senior (`_taborin`, `_seniorbct`, `_seniorlhs`, `_seniorsjaes`,
   `_seniormcs`, default). Port the term branch into whichever variant the
   target school renders.

3. **`sf9_grades` / `sf9_grades_gv2` term awareness.** Check whether these
   methods already return term-indexed grades (they may if Module 09's grade
   computation already stores term grades as `quarter = term_no`). If so, the
   controller change is mainly about *how it reads* the returned data (don't
   remap quarter3→q1 in term mode). If not, these methods need their own
   term-mode update.

4. **`sf10grades_addinauto` schema.** The manual override table currently has
   `quarter` and `semid` columns. In term mode, `quarter` serves as `term_no`
   and `semid` should be null, consistent with the `grades` table convention.
   Verify the table allows `semid = NULL`.

5. **`activeConfigQuery()` invariant.** `resolveShsSf9Terms` already wraps
   config reads with `activeConfigQuery()`. Any new `ibed_term_config` query
   must do the same.

6. **JHS is simpler than SHS.** JHS records are already whole-year (no semester
   consolidation needed). The JHS change is structurally easier: replace the
   hardcoded 4-quarter columns with dynamic N-term columns. No semester-row
   merging, no `semid` filtering, no "skip 2nd pass" logic.

7. **JHS school-specific branches.** `reportsschoolform10getrecords_junior`
   has school-specific branches similar to the SHS method (`sihs`/`sjaes`/
   `gbbc`, `hcb`, `bct`, `lhs`/`ndm`, `apmc`, `fmcma`, default). Apply the
   term-mode changes to the branch that matches the target school.

8. **JHS PDF blade variants.** There are 5 PDF blade variants for SF10 junior
   (default, `_juniordcc`, `_juniorlhs`, `_juniorsjaes`, `_juniorxai`). Port
   the term branch into whichever variant the target school renders.

9. **JHS uses `enrolledstud`, not `sh_enrolledstud`.** JHS enrollment records
   come from the `enrolledstud` table (no semester column), while SHS uses
   `sh_enrolledstud` (with `semid`). Don't confuse the two when adding term
   detection logic.

10. **JHS term detection: `resolveTermLabelsForLevel`, not `resolveShsPeriods`.**
    JHS levels must use `resolveTermLabelsForLevel` (config only, no plotting
    gate). Using `resolveShsPeriods` for JHS would incorrectly require
    whole-year plotting, which is an SHS-only concept.

11. **`grades.quarter` = `term_no`** — consistent with the kit invariant,
    term grades are stored under the existing `quarter` column reused as the
    term index. This applies to both SHS and JHS.

12. **JHS grade table blade JS.** The `btn-addrow` handler in
    `jhs/gradestable.blade.php` appends hardcoded `input-q1` through
    `input-q4` fields. In term mode, the handler must be updated to append
    only N term input fields matching the term count.

13. **Effort estimate.** This is a **large** change due to the school-specific
    branching in both SHS and JHS methods. For a single target school, focus
    on:
    - The one grade-fetching branch that matches the target's `abbreviation`
    - The one grade table blade used by the target
    - The one PDF blade variant used by the target
   
    Don't try to port all variants at once.

---

## Verification

1. **Term-mode SHS student SF10 view:**
   - Open SF10 for an SHS student enrolled in a term-mode level
   - Verify the grade table shows N term columns (e.g. 1T, 2T, 3T) in a
     single whole-year block instead of 2 semesters × 2 quarters
   - Verify all term grades appear in the correct columns

2. **Final grade computation:**
   - Verify final grade = average of N term grades (not hardcoded to 2)
   - Verify a student with only partial term grades shows the correct partial
     average or blanks

3. **SF10 PDF export:**
   - Export the SF10 as PDF
   - Verify the printed layout shows term columns instead of Q1/Q2

4. **Non-term SHS student:**
   - View SF10 for a student in a non-term SHS level
   - Verify the legacy semester layout is unchanged (Q1/Q2 per semester)

5. **Mixed history:**
   - View SF10 for a student who was in a semester-mode SY and then moved to
     a term-mode SY
   - Verify the older records show the semester layout and the newer records
     show the term layout

6. **Manual grade overrides (SHS):**
   - Add a manual override (`sf10grades_addinauto`) for a term-mode SHS student
   - Verify it appears correctly in the term column

### JHS verification

7. **Term-mode JHS student SF10 view:**
   - Open SF10 for a JHS student enrolled in a term-mode level
   - Verify the grade table shows N term columns (e.g. 1T, 2T, 3T) instead
     of the hardcoded 1st/2nd/3rd/4th quarter columns
   - Verify all term grades appear in the correct columns

8. **JHS final grade computation:**
   - Verify final grade = average of N term grades (not hardcoded to 4)
   - Verify a student with only partial term grades shows the correct partial
     average or blanks

9. **JHS SF10 PDF export:**
   - Export the SF10 as PDF for a JHS term-mode student
   - Verify the printed layout shows term columns instead of Q1/Q2/Q3/Q4

10. **Non-term JHS student:**
    - View SF10 for a student in a non-term JHS level
    - Verify the legacy 4-quarter layout is unchanged (1st/2nd/3rd/4th)

11. **JHS mixed history:**
    - View SF10 for a JHS student who was in a quarter-mode SY and then moved
      to a term-mode SY
    - Verify the older records show the 4-quarter layout and the newer records
      show the term layout

12. **Manual grade overrides (JHS):**
    - Add a manual override (`sf10grades_addinauto`) for a term-mode JHS student
    - Verify it appears correctly in the term column

13. **JHS "Add New Record" modal:**
    - Open the "Add New Record" modal for a JHS student
    - Verify it still works correctly (no semester picker needed — JHS has no
      semester concept)
