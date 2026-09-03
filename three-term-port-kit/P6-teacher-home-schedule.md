# Module P6 — Teacher Portal Home Page Schedule

The teacher portal home page (`/home`) shows a "Class Schedule" DataTable with
every subject the logged-in teacher is assigned to — across all academic
programs (GS/JHS, SHS subject-plot schedules, SHS cluster-plot schedules, and
College). In term mode, the SHS rows must include whole-year schedules
(subject plots and cluster plots with `semid = NULL`) alongside any
semester-stamped rows, so the teacher sees their complete load regardless of
whether a level has been converted to terms.

This is a **portal-surface** module (not one of the core 01–10 layers). It
consumes the resolvers from **Module 05** — specifically `shsTermLevels()` and
`semesterScope()`.

## Goal — what this port must achieve

After this port, the teacher home page schedule table correctly displays all
assigned schedules for both semester-based and term-based SHS levels. Concretely:

1. **Subject-plot schedules (SHS).** The `shs_sched()` method uses
   `IBEDGradingDefaults::semesterScope()` to include whole-year plots
   (`semid = NULL`) for term-mode levels, while still filtering by semester for
   non-term levels.
2. **Cluster-plot schedules (SHS).** The cluster-plot query in `shs_sched()`
   uses per-level term detection (`shsConfiguredTerms`) to decide whether to
   filter by `semid` or `whereNull('cp.semid')` for each SHS level (14/15).
3. **GS/JHS schedules.** Unchanged — `gs_sched()` uses `assignsubj` /
   `classsched` which have no semester dimension.
4. **College schedules.** Unchanged — the college query already filters by
   semester.
5. **Merged output.** All schedule sources merge into a single `all_sched` array
   returned by the `schedule()` method, filtering out any `store_error()`
   sentinels.

**Acceptance criteria (all must hold):**

- [ ] Semester-only SY: teacher sees SHS subject-plot schedules filtered by the
      active semester, same as before.
- [ ] Term-mode SY+level: teacher sees SHS subject-plot schedules where
      `semid IS NULL` (whole-year) alongside any remaining semester rows for
      non-term levels.
- [ ] Cluster-plot schedules: teacher sees cluster-plot assignments with their
      `sh_cluster_plot_schedule` time/day entries — for term-mode levels, plots
      with `semid = NULL` are included.
- [ ] Cluster section assignments: when `sh_cluster_section_assignment` exists,
      the section name comes from that table; otherwise falls back to the
      cluster name.
- [ ] GS/JHS and College schedules: unaffected — still appear correctly.
- [ ] Enrolled count: cluster-plot enrolled count comes from
      `sh_cluster_subject_picking`, not `sh_enrolledstud`.
- [ ] Mixed SY: one SHS level on semesters, another on terms — both display
      correctly in the same table.

> **Report back after applying (do this in chat).** When the port is done, post
> the acceptance criteria as a **ticked checklist** — **✅** applied and verified,
> **✔️** code applied but runtime/live-page test still pending, **⬜** skipped or
> not applicable (say why). Never mark ✅ something you didn't apply.

## Behaviors by level / config state

| Level / config state | Expected behavior |
|----------------------|-------------------|
| **No term config** | Legacy semester mode — SHS schedules filter by `semid` (or `semid IS NULL` for whole-year core subjects). |
| **Term config, not plotted** | `shsTermLevels()` returns empty (resolveShsPeriods requires plotting gate) — behaves like legacy. |
| **Term config, whole-year plotted** | Full term mode — `semesterScope` skips the semester filter for term-mode levels, so all whole-year subject-plot and cluster-plot schedules appear. |
| **4-quarter-shaped config** | `resolveShsPeriods` excludes it (no plotting gate or count check upstream) — stays on semester mode. |

## PREFLIGHT — check the repo FIRST

Before editing, verify these symbols/files exist in the target repo:

```bash
# Module 05 foundation
grep -r "class IBEDGradingDefaults" app/Support/
grep -r "shsTermLevels\|semesterScope" app/Support/
grep -r "shsConfiguredTerms" app/Support/

# Target controller
grep -rl "TeacherProfileController" app/Http/Controllers/
grep -n "function schedule\|function shs_sched\|function gs_sched" \
    app/Http/Controllers/SuperAdminController/TeacherProfileController.php

# Cluster section scope (optional — used for section display)
grep -r "class ShsClusterSectionScope" app/Support/

# Target view
grep -rl "teachersched_table\|Class Schedule" resources/views/teacher/home.blade.php
```

If `shsTermLevels` or `semesterScope` are missing, apply **Module 05** first.

## Files to check and update

| # | File | What to do |
|---|------|------------|
| 1 | `app/Http/Controllers/SuperAdminController/TeacherProfileController.php` | Update `shs_sched()` with term-aware queries for both subject-plot and cluster-plot schedules |
| 2 | `resources/views/teacher/home.blade.php` | No changes required — the blade already renders whatever `all_sched` contains |

## Changes

### Change 1 — `shs_sched()`: term-aware subject-plot query

**File:** `app/Http/Controllers/SuperAdminController/TeacherProfileController.php`

At the top of `shs_sched()`, resolve which SHS levels are in term mode:

```php
$termLevels = \App\Support\IBEDGradingDefaults::shsTermLevels($syid);
```

Then use `semesterScope()` on the main `sh_classsched` query instead of a
plain `where('semid', $semid)`:

```php
$sched = DB::table('sh_classsched')
    ->where('sh_classsched.syid', $syid)
    ->where(\App\Support\IBEDGradingDefaults::semesterScope(
        $semid,
        $termLevels,
        'sh_classsched.semid',
        'sh_classsched.glevelid'
    ))
    ->where('sh_classsched.deleted', 0);
```

`semesterScope()` does the branching internally: for levels in `$termLevels`,
it drops the semester filter entirely (showing all rows regardless of semid);
for other levels, it matches `semid = $semid OR semid IS NULL` (the latter
catches whole-year core subjects).

The same `semesterScope` call is repeated for the per-subject schedule-detail
fetch and for the strand subject-plot lookup later in the loop:

```php
// Schedule detail fetch (inside the foreach)
$sched = DB::table('sh_classsched')
    ->where('sh_classsched.syid', $syid)
    ->where(\App\Support\IBEDGradingDefaults::semesterScope(
        $semid, $termLevels, 'sh_classsched.semid', 'sh_classsched.glevelid'
    ))
    // ...

// Strand subject_plot lookup
$subjstrand = DB::table('subject_plot')
    ->where('deleted', 0)
    ->where(\App\Support\IBEDGradingDefaults::semesterScope(
        $semid, $termLevels, 'semid', 'levelid'
    ))
    // ...
```

### Change 2 — `shs_sched()`: cluster-plot query with per-level term gating

**File:** `app/Http/Controllers/SuperAdminController/TeacherProfileController.php`

After the subject-plot loop, the method queries `sh_cluster_plot` to include
cluster-assigned subjects. The semester/term logic uses per-level detection:

```php
$grade11TermMode = !empty(\App\Support\IBEDGradingDefaults::shsConfiguredTerms($syid, 14)['terms']);
$grade12TermMode = !empty(\App\Support\IBEDGradingDefaults::shsConfiguredTerms($syid, 15)['terms']);

$clusterPlots = DB::table('sh_cluster_plot as cp')
    ->where('cp.deleted', 0)
    ->where('cp.syid', $syid)
    ->where(function ($q) use ($semid, $grade11TermMode, $grade12TermMode) {
        $q->where(function ($qq) use ($semid, $grade11TermMode) {
            $qq->where('cp.levelid', 14);
            if ($grade11TermMode) {
                $qq->whereNull('cp.semid');
            } else {
                $qq->where(function ($legacy) use ($semid) {
                    $legacy->where('cp.semid', $semid)
                        ->orWhere('s.type', 1); // core subjects
                });
            }
        })->orWhere(function ($qq) use ($semid, $grade12TermMode) {
            $qq->where('cp.levelid', 15);
            if ($grade12TermMode) {
                $qq->whereNull('cp.semid');
            } else {
                $qq->where('cp.semid', $semid);
            }
        })->orWhere(function ($qq) use ($semid) {
            $qq->whereNotIn('cp.levelid', [14, 15])
                ->where('cp.semid', $semid);
        });
    })
    // ... joins and selects
```

For each level, the query checks term mode: if true, it filters for
`semid IS NULL` (whole-year plots); if false, it uses the semester filter.
Non-SHS levels always use the semester filter.

### Change 3 — Cluster schedule/teacher/enrolled batch fetches

**File:** `app/Http/Controllers/SuperAdminController/TeacherProfileController.php`

Once the cluster plot IDs are collected, three batch queries run:

1. **Schedules:** `sh_cluster_plot_schedule` — day, time_start, time_end, room.
2. **Teachers:** `sh_cluster_plot_teacher` — one row per teacher per quarter/term.
3. **Enrolled count:** `sh_cluster_subject_picking` — count per plotid.

```php
if ($clusterPlotIds->count() > 0) {
    $clusterSchedules = DB::table('sh_cluster_plot_schedule as sched')
        ->whereIn('sched.plotid', $clusterPlotIds)
        ->where('sched.deleted', 0)
        ->leftJoin('days as d', 'd.id', '=', 'sched.day_of_week')
        // ... select time_start as stime, time_end as etime, etc.

    $clusterTeachers = DB::table('sh_cluster_plot_teacher as cpt')
        ->whereIn('cpt.plotid', $clusterPlotIds)
        ->where('cpt.deleted', 0)
        ->join('teacher as t', 't.id', '=', 'cpt.teacherid')
        // ... select teacher details

    $clusterEnrolled = DB::table('sh_cluster_subject_picking')
        ->whereIn('clusterplotid', $clusterPlotIds)
        ->where('deleted', 0)
        ->groupBy('clusterplotid')
        ->select('clusterplotid', DB::raw('count(*) as cnt'))
        ->get();
}
```

These are term-agnostic — they fetch data for whatever plot IDs passed the
term/semester filter in Change 2.

### Change 4 — Cluster section assignment (optional)

**File:** `app/Http/Controllers/SuperAdminController/TeacherProfileController.php`

When `ShsClusterSectionScope::isReady()` is true (the
`sh_cluster_section_assignment` table exists), the cluster-plot query joins it
to get the section name:

```php
$hasClusterSection = \App\Support\ShsClusterSectionScope::isReady();

$clusterPlots = ...
    ->when($hasClusterSection, function ($q) {
        return $q->leftJoin('sh_cluster_section_assignment as csa', function ($join) {
            $join->on('csa.clusterplotid', '=', 'cp.id');
            $join->where('csa.deleted', 0);
        })->leftJoin('sections as sec', function ($join) {
            $join->on('sec.id', '=', 'csa.sectionid');
            $join->where('sec.deleted', 0);
        });
    })
```

The section name falls back to the cluster name when no assignment exists:

```php
$clusterItem->sectionname = $clusterItem->sectionname ?: $clusterItem->clustername;
```

### Change 5 — `schedule()` aggregation with sentinel filtering

**File:** `app/Http/Controllers/SuperAdminController/TeacherProfileController.php`

The `schedule()` method merges all sources and strips `store_error()` sentinels:

```php
public static function schedule(Request $request)
{
    // ...
    $gs = self::gs_sched($request);
    $shs = self::shs_sched($request);

    $all_sched = array();
    foreach (array($college, $gs, $shs) as $group) {
        foreach ($group as $item) {
            if (isset($item->status)) {
                continue; // skip store_error() sentinel
            }
            array_push($all_sched, $item);
        }
    }
    return $all_sched;
}
```

No term-specific changes needed here — it passes through whatever `shs_sched`
returns.

### Change 6 — Blade: no changes required

**File:** `resources/views/teacher/home.blade.php`

The blade's DataTable renders whatever rows the `/scheduling/teacher/schedule`
API returns. It uses `rowData.sectionname`, `rowData.subjdesc`,
`rowData.schedule` (array of `{start, end, day}`), and `rowData.enrolled`.
Cluster-plot rows already conform to this shape (set up in Change 3/4), so no
blade modifications are needed.

The JS fetches with the active `syid` and `semid` — the controller handles the
term-mode branching server-side.

---

## Dependencies

- **Module 01** — schema (`ibed_term`, `ibed_term_config`, `sh_cluster_plot`
  tables).
- **Module 05** — `IBEDGradingDefaults::shsTermLevels()`,
  `IBEDGradingDefaults::semesterScope()`,
  `IBEDGradingDefaults::shsConfiguredTerms()`.
- **Module P2** — subject-plot whole-year conversion (sets
  `subject_plot.semid = NULL` for term-mode levels).
- **Module P3** — cluster-plot whole-year conversion (sets
  `sh_cluster_plot.semid = NULL`).

---

## Porting notes / gotchas

1. **`semesterScope()` handles the branching.** Don't hand-roll a separate
   term-mode check for the subject-plot query — `semesterScope` already knows
   which levels are term-mode and skips the semester filter for them. It also
   includes `semid IS NULL` rows for non-term levels (whole-year core subjects).

2. **Cluster-plot term gating is per-level, not via `semesterScope`.** The
   cluster-plot query uses explicit `shsConfiguredTerms` checks per level (14/15)
   because it needs to branch on `cp.semid` (cluster plots) rather than
   `sh_classsched.semid` (class schedules), and because cluster-plot term mode
   uses `shsConfiguredTerms` directly (config-only, no plotting gate).

3. **Level IDs 14/15 are school-specific.** Verify in the target school's
   `gradelevel` table and adjust the hard-coded IDs.

4. **`ShsClusterSectionScope::isReady()`** checks whether the
   `sh_cluster_section_assignment` table exists. If the target repo doesn't have
   this table, the join is skipped and the section name falls back to the cluster
   name. This is safe — the `when($hasClusterSection, ...)` pattern handles it.

5. **`$filterTeacherId` vs `$teacherid`.** The `shs_sched()` method saves the
   original teacher filter as `$filterTeacherId` at the top, because the
   per-subject loop reassigns `$teacherid` to null while building teacher info.
   The cluster-plot teacher filter uses `$filterTeacherId` to correctly scope by
   the logged-in teacher.

6. **Enrolled count for cluster plots** comes from `sh_cluster_subject_picking`
   (how many students picked that elective), not from `sh_enrolledstud` (section
   enrollment). This is correct — cluster subjects are picked, not enrolled in
   the traditional sense.

7. **The `schedule()` method filters out `store_error()` sentinels.** If
   `gs_sched` or `shs_sched` throws an exception caught by a `store_error()`
   wrapper, the sentinel (which has a `status` property) is excluded from the
   merged output so it doesn't break the DataTable rendering.

8. **Wrap every `ibed_term_config` read with `activeConfigQuery()`.** The
   `shsConfiguredTerms()` resolver already goes through `activeConfigQuery`
   internally, but any direct `ibed_term_config` or `ibed_term` query added
   to the schedule controller must also be wrapped. A bare
   `where('deleted', 0)` read without the guard resurfaces an Inactive
   config — the #1 source of "terms showing where they shouldn't" (Module 05
   invariant).

9. **`shs_sched()`'s enrolled-count logic has TWO places that can zero a
   real class — check both.** It resolves the section's strand(s) from
   `sh_sectionblockassignment`, then (only when that list isn't empty)
   narrows it further to whichever strand(s) the *subject* is plotted for
   via `subject_plot`. Two related gaps, same root cause as known-pitfalls.md
   #17 (a class scheduled via `grading_percentage_id` with no `subject_plot`
   row at all):
   - **Empty section-strand list.** es_ldcu gates the narrowing with
     `if (count($strand) > 0) {...} else {...count all enrolled...}` — a
     target repo's copy can be missing that `else`, always attempting to
     narrow even an empty list and always landing on 0. This part is a
     direct, verified port straight from es_ldcu.
   - **Non-empty section-strand list, but the subject has zero active
     `subject_plot` rows.** Even with the `else` above ported, the
     narrowing step itself has no fallback in es_ldcu either — if the
     subject_plot query for that subject/level returns nothing (not
     because the subject doesn't apply to this section's strand, but
     because it has no plot row at all), the narrowed `$strand` becomes
     empty and the enrolled count still zeroes. This is a genuine gap in
     the reference too, not something to silently "fix" as a port — confirm
     with the user before adding a tolerant fallback here (check
     `subject_plot` existence for the subject/level with no strand filter;
     only trust the narrowed list when at least one active plot row
     exists, otherwise keep the section's original strand list).

---

## Verification

1. **Semester-mode SHS level:** Log in as a teacher assigned to an SHS section
   with no term config. Verify the Class Schedule table shows the correct
   subject-plot schedules filtered by the active semester.

2. **Term-mode SHS level:** Log in as a teacher assigned to a term-mode SHS
   section (whole-year plotted via P2). Verify:
   - Subject-plot schedules with `semid = NULL` appear in the table.
   - Time, day, section, and enrolled count display correctly.

3. **Cluster-plot schedules:** Log in as a teacher assigned to cluster-plot
   subjects (via `sh_cluster_plot_teacher`). Verify:
   - Cluster-plot rows appear with the correct subject name, section/cluster
     name, schedule (from `sh_cluster_plot_schedule`), and enrolled count (from
     `sh_cluster_subject_picking`).
   - In term mode, whole-year cluster plots (`semid = NULL`) appear.

4. **Mixed SY:** In the same school year, have one SHS level on semesters and
   another on terms. Verify both display correctly without cross-contamination.

5. **GS/JHS schedules:** Verify GS/JHS rows still appear correctly — they
   should be unaffected by the SHS term changes.

6. **No schedule:** A teacher with no assignments should see an empty table
   with "No data available" — not an error.
