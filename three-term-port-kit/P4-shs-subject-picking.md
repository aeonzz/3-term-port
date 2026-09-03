# Module P4 — SHS Subject Picking

The SHS Subject Picking page lets registrars (and principals/academic
coordinators) assign elective cluster-plot subjects to individual students.
In term mode the page drops the semester filter entirely — pickings become
whole-year records (semid = NULL) and available plots are scoped by the
`applyClusterTermScope` logic that mirrors the cluster-plotting controller.

This is a **portal-surface** module (not one of the core 01–10 layers). It
consumes the resolvers from **Module 05** and depends on **P3** (cluster plotting)
having converted the relevant plots to term/whole-year mode first.

## Goal — what this port must achieve

After this port, subject picking works identically for both semester-based and
term-based SHS levels within the same school year. Concretely:

1. **Term detection.** The controller detects term mode per SY + level via
   `IBEDGradingDefaults::shsConfiguredTerms()` and gates every query accordingly.
2. **Whole-year pickings.** In term mode, `sh_cluster_subject_picking.semid` is
   stored as NULL (not a semester id). All read queries use
   `whereNull('sp.semid')` instead of filtering by semester.
3. **Plot scoping.** Available plots in term mode are filtered by
   `applyClusterTermScope()` — matching plots by `cp.termid` or by teacher
   assignments covering the selected term, with a "whole year" default that
   requires teacher coverage across all configured terms.
4. **Period filter swap.** The blade's semester dropdown swaps to a Term/Whole-Year
   picker when the selected SY+level has term config, using the same
   `SHS_SUBJECT_PICKING_TERM_MAP` pattern as the cluster-plotting page.
**Acceptance criteria (all must hold):**

- [ ] Semester-only SY+level: page works exactly as before (semester filter,
      semid-based queries).
- [ ] Term-configured SY+level: semester dropdown swaps to Term picker (with
      "Whole Year" default). Student list loads without requiring a semester
      selection.
- [ ] Individual pick: `sh_cluster_subject_picking.semid` is NULL for term-mode
      plots, populated for semester-mode plots.
- [ ] Available plots: in term mode, plots are scoped via `applyClusterTermScope`
      (by termid or teacher-assignment coverage), not by semid.
- [ ] Picking schedule: `getPickingSchedule()` drops the semid filter in term
      mode so the early-enrollment window is found.
- [ ] Mixed SY: one level on semesters, another on terms — both work correctly
      within the same school year.

> **Report back after applying (do this in chat).** When the port is done, post
> the acceptance criteria as a **ticked checklist** — **✅** applied and verified,
> **✔️** code applied but runtime/live-page test still pending, **⬜** skipped or
> not applicable (say why). Never mark ✅ something you didn't apply.

## Behaviors by level / config state

| Level / config state | Expected behavior |
|----------------------|-------------------|
| **No term config** | Legacy semester mode — semester dropdown shown, all queries filter by `semid`. |
| **Term config, not plotted** | Term picker shown but available-plots returns nothing (plots still have `semid` set — `applyClusterTermScope` finds no matches). Picking schedule may still open. |
| **Term config, whole-year plotted** | Full term mode — Term/Whole-Year picker, plots scoped by term, pickings stored with `semid = NULL`. |
| **4-quarter-shaped config** | Excluded from the term map (`count !== 4`) — page stays on semester mode, matching the subject-plot page's behavior. A 4-quarter config is a settings-only re-description of the standard layout, not a genuine term restructuring. |

## PREFLIGHT — check the repo FIRST

Before editing, verify these symbols/files exist in the target repo:

```bash
# Module 05 foundation
grep -r "class IBEDGradingDefaults" app/Support/
grep -r "shsConfiguredTerms" app/Support/

# P3 cluster plotting (applyClusterTermScope pattern)
grep -r "applyClusterTermScope\|sh_cluster_plot_teacher" app/Http/Controllers/

# Target files
grep -rl "ShsSubjectPickingController\|SHSSubjectPickingController" app/Http/Controllers/
grep -rl "subjectpicking" resources/views/
```

If `IBEDGradingDefaults::shsConfiguredTerms` is missing, stop and tell the user
to apply **Module 05** first. If there's no cluster-plotting term logic (P3),
the `applyClusterTermScope` method won't have a pattern to follow — apply P3
first.

## Files to check and update

| # | File | What to do |
|---|------|------------|
| 1 | `app/Http/Controllers/RegistrarControllers/ShsSubjectPickingController.php` | Add term-mode detection + query gating across all methods |
| 2 | `resources/views/registrar/shs/subjectpicking/index.blade.php` | Add term-map JS, period-filter swap logic |

## Changes

### Change 1 — Term-mode detection helper

**File:** `app/Http/Controllers/RegistrarControllers/ShsSubjectPickingController.php`

Add a private helper that checks whether a given SY + level has term config:

```php
private function shsPickingTermMode($syid, $levelid = null): bool
{
    if (!$syid) {
        return false;
    }

    $check = function ($level) use ($syid) {
        $cfg = \App\Support\IBEDGradingDefaults::shsConfiguredTerms($syid, $level);
        return !empty($cfg['terms']);
    };

    if ($levelid) {
        return $check($levelid);
    }

    return $check(14) || $check(15);
}
```

This mirrors the pattern in the cluster-plotting controller. When `levelid` is
provided, it checks that specific level; otherwise it checks both SHS levels
(14/15) for a "does any SHS level have terms?" answer.

### Change 2 — Student-level lookup helper

**File:** `app/Http/Controllers/RegistrarControllers/ShsSubjectPickingController.php`

```php
private function studentLevelId($studid, $syid)
{
    if (!$studid || !$syid) {
        return null;
    }

    return DB::table('sh_enrolledstud')
        ->where('studid', $studid)
        ->where('syid', $syid)
        ->where('deleted', 0)
        ->orderByDesc('id')
        ->value('levelid');
}
```

Used by `getStudentPicking` to resolve the student's level when the caller
doesn't pass it, so the term-mode check is level-specific.

### Change 3 — `getStudents()` term gating

**File:** `app/Http/Controllers/RegistrarControllers/ShsSubjectPickingController.php`

Key changes in the student-list endpoint:

- Call `$isTermMode = $this->shsPickingTermMode($syid, $levelid)`.
- Allow the request without `$semid` when in term mode (legacy requires it).
- Enrolled query: skip `semid` filter in term mode; deduplicate by
  `MAX(se.id)` per student to avoid showing one row per semester enrollment.
- Unenrolled query: skip entirely in term mode (whole-year means all enrolled
  students are visible).
- Cluster/elective batch fetches: use `whereNull('sp.semid')` in term mode
  instead of filtering by semester.

```php
$isTermMode = $this->shsPickingTermMode($syid, $levelid);

if (!$syid || (!$semid && !$isTermMode)) {
    // return empty — need either a semester or term mode
}

// Enrolled query
->when(!$isTermMode, function ($q) use ($semid) { $q->where('se.semid', $semid); })
->when($isTermMode, function ($q) use ($syid) {
    $q->whereIn('se.id', function ($sub) use ($syid) {
        $sub->from('sh_enrolledstud as se_dedup')
            ->where('se_dedup.syid', $syid)
            ->where('se_dedup.deleted', 0)
            ->groupBy('se_dedup.studid')
            ->select(DB::raw('MAX(se_dedup.id)'));
    });
})

// Cluster batch fetch
->when(!$isTermMode, function ($q) use ($semid) { $q->where('sp.semid', $semid); })
->when($isTermMode, function ($q) { $q->whereNull('sp.semid'); })

// Electives count
->when(!$isTermMode, function ($q) use ($semid) { $q->where('semid', $semid); })
->when($isTermMode, function ($q) { $q->whereNull('semid'); })
```

### Change 4 — `getStudentPicking()` term gating

**File:** `app/Http/Controllers/RegistrarControllers/ShsSubjectPickingController.php`

```php
$levelid = $request->input('levelid') ?: $this->studentLevelId($studid, $syid);
$isTermMode = $this->shsPickingTermMode($syid, $levelid);

// Picking query
->when(!$isTermMode, function ($q) use ($semid) { $q->where('sp.semid', $semid); })
->when($isTermMode, function ($q) { $q->whereNull('sp.semid'); })
```

### Change 5 — `applyClusterTermScope()` for available plots

**File:** `app/Http/Controllers/RegistrarControllers/ShsSubjectPickingController.php`

This private method mirrors the one in `SHSClusterPlottingController`. It scopes
plots to a specific term (by `cp.termid` or teacher-assignment quarter) or to
"whole year" (plots whose teacher assignments cover all configured terms):

```php
private function applyClusterTermScope($query, $syid, $levelid, $termid)
{
    if ($termid !== null && $termid !== '') {
        $termNo = DB::table('ibed_term')
            ->where('id', $termid)
            ->where('deleted', 0)
            ->value('term_no');

        return $query->where(function ($q) use ($termid, $termNo) {
            $q->where('cp.termid', $termid);
            if ($termNo !== null) {
                $q->orWhereExists(function ($sub) use ($termNo) {
                    $sub->select(DB::raw(1))
                        ->from('sh_cluster_plot_teacher as cpt_term')
                        ->whereColumn('cpt_term.plotid', 'cp.id')
                        ->where('cpt_term.quarter', $termNo)
                        ->where('cpt_term.deleted', 0);
                });
            }
        });
    }

    // Whole-year: plots with no termid whose teachers cover ALL configured terms
    $cfg = \App\Support\IBEDGradingDefaults::shsConfiguredTerms($syid, $levelid);
    $termNos = array_map('intval', array_column($cfg['terms'] ?? [], 'term_no'));

    if (empty($termNos)) {
        return $query->whereRaw('1 = 0');
    }

    $placeholders = implode(',', array_fill(0, count($termNos), '?'));
    $bindings = array_merge($termNos, [count($termNos)]);

    return $query->whereNull('cp.termid')->whereRaw(
        "(SELECT COUNT(DISTINCT cpt_whole.quarter)
          FROM sh_cluster_plot_teacher as cpt_whole
          WHERE cpt_whole.plotid = cp.id
            AND cpt_whole.deleted = 0
            AND cpt_whole.quarter IN ({$placeholders})
        ) = ?",
        $bindings
    );
}
```

### Change 6 — `getAvailablePlots()` term gating

**File:** `app/Http/Controllers/RegistrarControllers/ShsSubjectPickingController.php`

```php
$termid = $request->input('termid');
$isTermMode = $this->shsPickingTermMode($syid, $levelid);

// Plot query
->when(!$isTermMode, function ($q) use ($semid) { $q->where('cp.semid', $semid); })
->when($isTermMode, function ($q) use ($syid, $levelid, $termid) {
    $q->whereNull('cp.semid');
    $this->applyClusterTermScope($q, $syid, $levelid, $termid);
})

// Already-picked check
->when(!$isTermMode, function ($q) use ($semid) { $q->where('semid', $semid); })
->when($isTermMode, function ($q) { $q->whereNull('semid'); })
```

### Change 7 — `getPickingSchedule()` term gating

**File:** `app/Http/Controllers/RegistrarControllers/ShsSubjectPickingController.php`

```php
$isTermMode = $this->shsPickingTermMode($syid, $levelid);

// Early enrollment setup query — skip semid filter in term mode
->when(!$isTermMode, function ($q) use ($semid) { $q->where('es.semid', $semid); })
```

### Change 8 — `pick()` uses plot's semid

**File:** `app/Http/Controllers/RegistrarControllers/ShsSubjectPickingController.php`

The insert uses `$plot->semid` (which is NULL for term-mode plots):

```php
DB::table('sh_cluster_subject_picking')->insert([
    'studid'          => $studid,
    'syid'            => $syid,
    'semid'           => $plot->semid,   // NULL for term-mode plots
    'clusterplotid'   => $clusterplotid,
    'createdby'       => Auth::id(),
    'createddatetime' => $now,
    'deleted'         => 0,
]);
```

### Change 9 — Blade: term-map JS and period-filter swap

**File:** `resources/views/registrar/shs/subjectpicking/index.blade.php`

In the `@php` block at the top, build the term map:

```php
$shsSubjectPickingTermMap = [];
foreach ($sy as $syRow) {
    foreach ($shsLevels as $levelRow) {
        $cfg = \App\Support\IBEDGradingDefaults::shsConfiguredTerms($syRow->id, $levelRow->id);
        if (!empty($cfg['terms']) && count($cfg['terms']) !== 4) {
            $shsSubjectPickingTermMap[$syRow->id][$levelRow->id] = array_map(function ($t) {
                return ['id' => $t['id'], 'label' => $t['label']];
            }, $cfg['terms']);
        }
    }
}
```

The `count !== 4` guard excludes configs that merely re-describe the standard
4 quarters — same reasoning as the subject-plot page (`P2`) and the JHS
`resolveTermLabelsForLevel()`. Without this, a 4-quarter config would
incorrectly switch the page to term mode.

Pass it to JS:

```javascript
window.SHS_SUBJECT_PICKING_TERM_MAP = @json($shsSubjectPickingTermMap ?? []);
window.SHS_PICK_SEMESTERS = @json($semester->map(...));
window.SHS_PICK_ACTIVE_SEM = @json(optional($activesemester)->id);
```

Add JS helpers `spIsTermMode()`, `spTerms()`, `spTermId()`, and
`applySpPeriodMode()` that swap the semester `<select>` to a term picker when
the current SY+level has term config. The period label changes from "Semester"
to "Period". In term mode, `semid` is sent as empty string to the API (the
controller uses term mode detection instead).

---

## Dependencies

- **Module 01** — schema (`ibed_term`, `ibed_term_config` tables).
- **Module 05** — `IBEDGradingDefaults::shsConfiguredTerms()` resolver.
- **Module P3** — cluster plotting must have converted plots to whole-year /
  term mode (sets `cp.semid = NULL`, `cp.termid`, and teacher-assignment
  quarters). Without P3, `applyClusterTermScope` finds no plots.

---

## Porting notes / gotchas

1. **Level IDs are school-specific.** The fallback check `$check(14) || $check(15)`
   assumes SHS level IDs are 14 (Grade 11) and 15 (Grade 12). Verify these in the
   target school's `gradelevel` table and adjust.

2. **The unenrolled-students union is skipped in term mode.** In semester mode the
   controller unions students from other semesters who aren't enrolled in the current
   one. In term mode all enrollments are visible (whole-year), so this union is
   unnecessary and skipped.

3. **`semid = NULL` is the term-mode convention.** Both `sh_cluster_plot.semid` (from
   P3) and `sh_cluster_subject_picking.semid` (from this module) use NULL to mean
   "whole year / term mode." Any reporting query that joins these tables must handle
   NULL semid.

4. **The `pick()` method inherits semid from the plot**, not from the request.
   This ensures the picking record's semid matches the plot's mode — a term-mode
   plot always produces a NULL-semid picking.

5. **`applyClusterTermScope` is duplicated** from the cluster-plotting controller.
   Both controllers need the same logic but don't share a base class. If the target
   repo has a shared trait or service, extract it there instead.

6. **Picking schedule** (`early_enrollment_setup`): in term mode the semid filter is
   dropped. If the target school has separate enrollment windows per term, additional
   logic would be needed — the current implementation treats the enrollment window as
   SY-wide when in term mode.

7. **Wrap every `ibed_term_config` read with `activeConfigQuery()`.** The
   `shsConfiguredTerms()` resolver already goes through `activeConfigQuery`
   internally, but any direct `ibed_term_config` or `ibed_term` query added
   to the subject-picking controller must also be wrapped. A bare
   `where('deleted', 0)` read without the guard resurfaces an Inactive
   config — the #1 source of "terms showing where they shouldn't" (Module 05
   invariant).

---

## Verification

1. **Semester-mode level:** Select an SY + level with no term config. Verify the
   semester dropdown appears and student list, pickings, and available plots all
   filter by semester as before.

2. **Term-mode level:** Select an SY + level with term config (and whole-year plots
   from P3). Verify:
   - The semester dropdown swaps to a "Period" picker with "Whole Year" + term options.
   - The student list loads on page load (no semester selection required).
   - Available plots show only whole-year or term-specific plots (matching the
     cluster-plotting page's logic).
   - Picking a subject inserts with `semid = NULL`.
   - Removing a picking works.

3. **Mixed SY:** In the same school year, have one level on semesters and another on
   terms. Switch between them and verify each uses the correct mode without
   cross-contamination.

4. **Picking schedule:** Verify `getPickingSchedule` returns the correct open/closed
   status in both modes.
