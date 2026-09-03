# Module P10 — Teacher Grade Summary (Term-Aware)

The Teacher Grade Summary page (`/teacher/grade/summary`) shows an advisory
teacher a cross-subject view of grades for an entire section — the **Master
Sheet** (all subjects × students, one quarter/term at a time) and the
**Grading Sheet** (one subject × students, all quarters/terms side by side).
A companion page (`/teacher/grade/summary/quarter`) shows the **Summary of
Quarterly Grades** — similar to the Grading Sheet but accessible from a
separate route.

In term mode the quarter picker becomes a term picker ("1st Term / 2nd Term /
3rd Term" or configured labels), the column headers relabel from Q1–Q4 to
term labels, excess columns hide (a 3-term config hides the 4th column), the
semester dropdown is hidden (term mode spans the whole year), and print
exports pass `semid=0` for whole-year SHS.

This is a **portal-surface** module (not one of the core 01–10 layers). It
consumes resolvers from **Module 05** — `activeConfigQuery()`,
`resolveShsPeriods()`, `shsConfiguredTerms()`, and
`IbedGradeEquivalency::configAppliesToLevel()` from **Module 04**.

## Goal — what this port must achieve

After this port, the teacher grade summary page correctly displays term-based
grades alongside quarter-based grades within the same school year. Concretely:

1. **TERM_MAP construction (server-side `@php` block).** Build a
   `$termMap[syid][levelid]` lookup from `activeConfigQuery`-wrapped
   `ibed_term_config` reads, with SHS levels using `resolveShsPeriods()` +
   cluster-plot fallback, and JHS/GS levels using `configAppliesToLevel()`.
   Expose as `window.TERM_MAP` via `@json`.
2. **`getActiveTermCfg()` JS helper.** Client-side function returning the
   term config for the selected SY + level, or null (quarter mode).
3. **Quarter picker relabeling.** When `getActiveTermCfg()` returns a term
   config, the `#quarter` dropdown populates with term labels instead of
   quarter labels ("Select Term" instead of "Select Quarter").
4. **Column header relabeling.** The grading sheet's Q1–Q4 headers relabel
   to term labels via `periodTitle()`, and excess columns hide via
   `periodVisible()`.
5. **Semester dropdown hiding.** In term mode for SHS, the semester dropdown
   is hidden (term classes span the whole year).
6. **Print exports with `semid=0`.** Master sheet and grading sheet print
   links pass `semid=0` when in SHS term mode.

**Acceptance criteria (all must hold):**

- [ ] Quarter-mode level: quarter picker shows Q1–Q4 (or semester-scoped
      Q1/Q2 or Q3/Q4 for SHS), grading sheet headers show Q1–Q4, semester
      dropdown visible for SHS.
- [ ] Term-mode SHS level: quarter picker shows configured term labels +
      "Final Rating", grading sheet headers show term labels, semester
      dropdown hidden, Q4 column hidden for 3-term config.
- [ ] Term-mode JHS/GS level: quarter picker shows term labels + "Final
      Rating", grading sheet headers show term labels, Q4 column hidden
      for 3-term config.
- [ ] Cluster-plot SHS with term config but no subject-plot: SHS
      `resolveShsPeriods` returns non-term, but cluster-plot fallback
      detects `sh_cluster_plot.semid IS NULL` and enables term mode.
- [ ] Print master sheet: opens with correct `semid` (0 for SHS term mode,
      real semid otherwise).
- [ ] Print grading sheet: same `semid` logic as master sheet.
- [ ] Summary of Quarterly Grades page (`/teacher/grade/summary/quarter`):
      same term-aware behavior as the main grade summary.
- [ ] SY switch from term-mode to non-term: columns and picker revert to
      quarter labels.

> **Report back after applying (do this in chat).** When the port is done, post
> the acceptance criteria as a **ticked checklist** — **✅** applied and verified,
> **✔️** code applied but runtime/live-page test still pending, **⬜** skipped or
> not applicable (say why). Never mark ✅ something you didn't apply.

## Behaviors by level / config state

| Level / config state | Expected behavior |
|----------------------|-------------------|
| **No term config** | Legacy quarter mode — Q1/Q2/Q3/Q4 picker and headers, semester dropdown visible for SHS. |
| **Term config, not plotted (SHS)** | `resolveShsPeriods` returns non-term. Cluster-plot fallback checks `sh_cluster_plot.semid IS NULL` — if found, enables term mode. Otherwise stays on quarters. |
| **Term config, whole-year plotted (SHS)** | Full term mode — term picker labels, term column headers, semester hidden, print passes `semid=0`. |
| **Term config (JHS/GS)** | Term tabs from `configAppliesToLevel`. Term picker and column headers relabeled. |
| **4-quarter-shaped config** | Upstream resolvers exclude it for SHS. For JHS/GS, `configAppliesToLevel` may include it — 4 term columns shown with term labels. |

## PREFLIGHT — check the repo FIRST

Before editing, verify these symbols/files exist in the target repo:

```bash
# Module 05 foundation
grep -r "class IBEDGradingDefaults" app/Support/
grep -r "activeConfigQuery\|resolveShsPeriods\|shsConfiguredTerms" app/Support/

# Module 04 (grade equivalency)
grep -r "configAppliesToLevel" app/Support/

# Target controller
grep -n "teacher_grade_summary\|teacher_grade_summary_quarter" \
    app/Http/Controllers/TeacherControllers/TeacherGradingV4.php

# Target views
ls resources/views/teacher/grading/grade_summary/grading_summary.blade.php
ls resources/views/teacher/grading/grade_summary/grading_summary_quarter.blade.php

# Routes
grep -n "teacher/grade/summary" routes/web.php
```

If `activeConfigQuery`, `resolveShsPeriods`, or `configAppliesToLevel` are
missing, apply **Module 05** and **Module 04** first.

## Files to check and update

| # | File | What to do |
|---|------|------------|
| 1 | `resources/views/teacher/grading/grade_summary/grading_summary.blade.php` | Add `$termMap` construction, `TERM_MAP` JS, `getActiveTermCfg()`, `periodTitle()`, `periodVisible()`, term-aware quarter picker, column relabeling, semester hiding, print `semid=0` |
| 2 | `resources/views/teacher/grading/grade_summary/grading_summary_quarter.blade.php` | Same `$termMap`/JS term helpers as above, applied to the Summary of Quarterly Grades view |
| 3 | `app/Http/Controllers/TeacherControllers/TeacherGradingV4.php` | No changes needed — controller just returns views |
| 4 | `app/Models/Teacher/TeacherData.php` | `get_all_sections` / `get_sections_sh` — no term changes needed (already returns all schedules regardless of semester; semid filter is commented out) |

## Changes

### Change 1 — Blade: `$termMap` construction (server-side `@php` block)

**File:** `resources/views/teacher/grading/grade_summary/grading_summary.blade.php`

At the top of the `@section('content')` block, build a `$termMap` keyed by
`[syid][levelid]`:

```php
@php
    $termMap = [];
    $termOrdinalWords = [1 => '1st', 2 => '2nd', 3 => '3rd', 4 => '4th', 5 => '5th', 6 => '6th'];
    $termGradingSYs = DB::table('sy')->where('term_grading_status', 1)->get();

    foreach ($termGradingSYs as $termSy) {
        $acadTerms = [];
        $termConfigs = \App\Support\IBEDGradingDefaults::activeConfigQuery(
            DB::table('ibed_term_config')
                ->where('syid', $termSy->id)
                ->where('deleted', 0)
                ->orderByRaw('CASE WHEN semid IS NULL THEN 0 ELSE 1 END ASC')
        )->get();

        foreach ($termConfigs as $cfg) {
            if (isset($acadTerms[$cfg->acadprogid])) continue;

            $terms = DB::table('ibed_term')
                ->where('config_id', $cfg->id)
                ->where('is_active', 1)
                ->where('deleted', 0)
                ->orderBy('sort_order')
                ->orderBy('term_no')
                ->get();

            if ($terms->count() > 0) {
                $termList = [];
                foreach ($terms as $term) {
                    $fallback = ($termOrdinalWords[$term->term_no] ?? $term->term_no . 'th') . ' Term';
                    $label = $term->short_code ?: ($term->description ?: $fallback);
                    $termList[] = ['term_no' => (int) $term->term_no, 'label' => $label];
                }
                $acadTerms[$cfg->acadprogid] = [
                    'config_id' => $cfg->id,
                    'term_count' => count($termList),
                    'terms' => $termList,
                ];
            }
        }

        if (!empty($acadTerms)) {
            $levelMap = [];
            $gradelevels = DB::table('gradelevel')->select('id', 'acadprogid')->get();
            foreach ($gradelevels as $level) {
                if (in_array($level->id, [14, 15])) {
                    // SHS: resolveShsPeriods first, then cluster-plot fallback
                    $periods = \App\Support\IBEDGradingDefaults::resolveShsPeriods($termSy->id, $level->id);
                    if (empty($periods['isTermMode'])) {
                        $configuredPeriods = \App\Support\IBEDGradingDefaults::shsConfiguredTerms($termSy->id, $level->id);
                        $hasClusterTermPlot = DB::table('sh_cluster_plot')
                            ->where('syid', $termSy->id)
                            ->where('levelid', $level->id)
                            ->where('deleted', 0)
                            ->whereNull('semid')
                            ->exists();
                        if (!empty($configuredPeriods['terms']) && $hasClusterTermPlot) {
                            $periods = [
                                'isTermMode' => true,
                                'termCount' => $configuredPeriods['termCount'],
                                'terms' => $configuredPeriods['terms'],
                            ];
                        }
                    }
                    if (!empty($periods['isTermMode'])) {
                        $levelMap[$level->id] = [
                            'term_count' => $periods['termCount'],
                            'terms' => $periods['terms'],
                        ];
                    }
                    continue;
                }

                // JHS/GS: config + configAppliesToLevel
                if (isset($acadTerms[$level->acadprogid])
                    && \App\Support\IbedGradeEquivalency::configAppliesToLevel(
                        $acadTerms[$level->acadprogid]['config_id'], $level->id
                    )) {
                    $levelMap[$level->id] = [
                        'term_count' => $acadTerms[$level->acadprogid]['term_count'],
                        'terms' => $acadTerms[$level->acadprogid]['terms'],
                    ];
                }
            }

            if (!empty($levelMap)) {
                $termMap[$termSy->id] = $levelMap;
            }
        }
    }
@endphp
```

The SHS branch includes a **cluster-plot fallback**: when `resolveShsPeriods`
returns non-term (no whole-year subject plots), it checks if any cluster plots
exist with `semid IS NULL` for that level. If so and a term config exists, it
enables term mode. This handles levels that have only cluster electives
converted to whole-year.

### Change 2 — JS: `TERM_MAP` and term helper functions

**File:** `resources/views/teacher/grading/grade_summary/grading_summary.blade.php`

Expose the map and define the client-side helpers:

```javascript
window.TERM_MAP = @json((object) $termMap);
var TERM_MAP = window.TERM_MAP;

function getActiveTermCfg(){
    var levelid = $('#gradelevel').val()
    var syid = $('#syid').val()
    return (TERM_MAP && TERM_MAP[syid] && TERM_MAP[syid][levelid])
        ? TERM_MAP[syid][levelid] : null;
}
window.getActiveTermCfg = getActiveTermCfg;

function periodTitle(n, cfg){
    if(cfg && cfg.terms){
        var match = cfg.terms.filter(function(term){ return term.term_no == n })
        if(match.length){ return match[0].label }
    }
    return 'Q'+n
}

function periodVisible(n, cfg){
    return cfg ? (n <= cfg.term_count) : true
}
```

- `getActiveTermCfg()` returns `{term_count, terms: [{term_no, label}]}`
  when the current SY + level combination has a term config, or `null` for
  quarter mode.
- `periodTitle(n, cfg)` returns the term label for period `n` (e.g., "1st
  Term") or falls back to `"Q" + n` when in quarter mode.
- `periodVisible(n, cfg)` returns `false` for period numbers beyond the
  configured term count (hides Q4 column in a 3-term config).

### Change 3 — JS: quarter picker term relabeling

**File:** `resources/views/teacher/grading/grade_summary/grading_summary.blade.php`

On grade-level change, the quarter picker rebuilds with term-aware labels:

```javascript
$(document).on('change','#gradelevel',function(){
    // ... section repopulation ...

    $('#quarter').empty();
    if($(this).val() == 14 || $(this).val() == 15){
        var shs_term_cfg = (window.getActiveTermCfg) ? window.getActiveTermCfg() : null
        if(shs_term_cfg){
            // Term mode — show term labels, hide semester
            $('#quarter').append('<option value="">Select Term</option>')
            $.each(shs_term_cfg.terms, function(i, term){
                if(term.term_no <= shs_term_cfg.term_count){
                    $('#quarter').append('<option value="'+term.term_no+'">'+term.label+'</option>')
                }
            })
            $('#quarter').append('<option value="5">Final Rating</option>')
            $('#semester_holder').attr('hidden','hidden')
        } else {
            // Quarter mode — semester-scoped quarters
            $('#quarter').append('<option value="">Select Quarter</option>')
            if($('#semester').val() == 1){
                $('#quarter').append('<option value="1">1st Quarter</option>')
                $('#quarter').append('<option value="2">2nd Quarter</option>')
                $('#quarter').append('<option value="5">Final Rating</option>')
            } else {
                $('#quarter').append('<option value="3">3rd Quarter</option>')
                $('#quarter').append('<option value="4">4th Quarter</option>')
                $('#quarter').append('<option value="5">Final Rating</option>')
            }
            $('#semester_holder').removeAttr('hidden')
        }
        $('#strand_holder').removeAttr('hidden')
    } else {
        // JHS/GS — check for term config
        var term_cfg = (window.getActiveTermCfg) ? window.getActiveTermCfg() : null
        if(term_cfg){
            $('#semester_holder').attr('hidden','hidden')
            $('#quarter').append('<option value="">Select Term</option>')
            $.each(term_cfg.terms, function(i, term){
                if(term.term_no <= term_cfg.term_count){
                    $('#quarter').append('<option value="'+term.term_no+'">'+term.label+'</option>')
                }
            })
        } else {
            $('#semester_holder').removeAttr('hidden')
            $('#quarter').append('<option value="">Select Quarter</option>')
            $('#quarter').append('<option value="1">1st Quarter</option>')
            $('#quarter').append('<option value="2">2nd Quarter</option>')
            $('#quarter').append('<option value="3">3rd Quarter</option>')
            $('#quarter').append('<option value="4">4th Quarter</option>')
        }
        $('#quarter').append('<option value="5">Final Rating</option>')
        $('#strand_holder').attr('hidden','hidden')
    }
})
```

For SHS term mode the semester dropdown is hidden (`$('#semester_holder').attr('hidden','hidden')`) because term-based classes span the whole school year.

### Change 4 — JS: grading sheet column header relabeling

**File:** `resources/views/teacher/grading/grade_summary/grading_summary.blade.php`

The grading sheet table applies `periodTitle()` and `periodVisible()` to
Q1–Q4 column headers:

```javascript
function applyQuarterHeader(){
    var cfg = getActiveTermCfg()
    for(var n = 1; n <= 4; n++){
        $('.gs_q'+n).text(periodTitle(n, cfg))
        if(periodVisible(n, cfg)){
            $('.gs_q'+n).removeAttr('hidden')
        } else {
            $('.gs_q'+n).attr('hidden','hidden')
        }
    }
}

$(document).on('change','#gradelevel , #syid , #semester', function(){
    applyQuarterHeader()
})
```

When the DataTable is rebuilt (`loaddatatable_gradingsheet`), the column
definitions also use `periodTitle` and `periodVisible`:

```javascript
function loaddatatable_gradingsheet(data){
    var cfg = getActiveTermCfg()

    // ... DataTable config ...
    "columnDefs": [
        {"title":"Student Name","targets":0},
        {"title":periodTitle(1,cfg),"targets":1,"visible":periodVisible(1,cfg)},
        {"title":periodTitle(2,cfg),"targets":2,"visible":periodVisible(2,cfg)},
        {"title":periodTitle(3,cfg),"targets":3,"visible":periodVisible(3,cfg)},
        {"title":periodTitle(4,cfg),"targets":4,"visible":periodVisible(4,cfg)},
        {"title":"Final Rating","targets":5},
        {"title":"Remarks","targets":6},
    ]
    // ...
}
```

Post-render, the SHS semester-based column hiding is skipped when in term
mode:

```javascript
if((select_gl == 14 || select_gl == 15) && !cfg){
    // Semester-based: hide opposite-semester columns
    if($('#semester').val() == 1){
        $('.gs_q3').attr('hidden','hidden')
        $('.gs_q4').attr('hidden','hidden')
    } else {
        $('.gs_q1').attr('hidden','hidden')
        $('.gs_q2').attr('hidden','hidden')
    }
} else {
    // Term mode or JHS: show/hide based on term_count
    for(var n = 1; n <= 4; n++){
        if(periodVisible(n, cfg)){
            $('.gs_q'+n).removeAttr('hidden')
        } else {
            $('.gs_q'+n).attr('hidden','hidden')
        }
    }
}
```

### Change 5 — JS: print exports with `semid=0`

**File:** `resources/views/teacher/grading/grade_summary/grading_summary.blade.php`

The master sheet and grading sheet print buttons pass `semid=0` when in SHS
term mode:

```javascript
$(document).on('click','#print_ms',function(){
    var gradelevel = $('#gradelevel').val();
    var section = $('#section').val();
    var quarter  = $('#quarter').val();
    var syid  = $('#syid').val();
    var semid = 1
    if(gradelevel == 14 || gradelevel == 15){
        var semid = $('#semester').val()
        var shs_term_cfg = (window.getActiveTermCfg) ? window.getActiveTermCfg() : null
        if(shs_term_cfg){ semid = 0 }
    }
    var strand  = $('#strand').val();
    // ... validation ...
    window.open("/grades/report/mastersheet?gradelevel="+gradelevel+"&section="
        +section+"&quarter="+quarter+"&sy="+syid+"&semid="+semid+'&strand='+strand);
})
```

The same `semid=0` pattern applies to `#print_ms_excel` and `#print_gs`.

### Change 6 — Summary of Quarterly Grades page (same pattern)

**File:** `resources/views/teacher/grading/grade_summary/grading_summary_quarter.blade.php`

This blade uses the **exact same** `$termMap` construction, `TERM_MAP` JS,
`getActiveTermCfg()`, `periodTitle()`, `periodVisible()`, and
`applyQuarterHeader()` pattern as the main grade summary. The key differences:

- **SHS `resolveShsPeriods` without cluster-plot fallback.** This blade uses
  only `resolveShsPeriods` (no `shsConfiguredTerms` + cluster-plot check).
  This means a level with only cluster-plot whole-year conversion won't
  enable term mode on this page.
- **Strand data source.** Uses `sh_sectionblockassignment` only (no
  `sh_enrolledstud` merge), so strand data may be more limited.

Otherwise the quarter picker relabeling, column header relabeling, and
semester hiding logic is identical.

---

## Dependencies

- **Module 01** — schema (`ibed_term`, `ibed_term_config`, `sy`, `gradelevel`
  tables).
- **Module 04** — `IbedGradeEquivalency::configAppliesToLevel()`.
- **Module 05** — `IBEDGradingDefaults::activeConfigQuery()`,
  `IBEDGradingDefaults::resolveShsPeriods()`,
  `IBEDGradingDefaults::shsConfiguredTerms()`.
- **Module P2** — subject-plot whole-year conversion (SHS `resolveShsPeriods`
  requires `subject_plot.semid IS NULL`).
- **Module P3** — cluster-plot whole-year conversion (cluster-plot fallback
  checks `sh_cluster_plot.semid IS NULL`).

---

## Porting notes / gotchas

1. **`$termMap` is built in a `@php` block, not the controller.** The
   controller just returns the view — all term resolution logic is inline in
   the blade. For a cleaner architecture, consider moving this to the
   controller or a view composer, but the reference implementation keeps it
   inline.

2. **Cluster-plot fallback in `grading_summary.blade.php` only.** The main
   grade summary blade has a cluster-plot fallback (checking
   `sh_cluster_plot.semid IS NULL` when `resolveShsPeriods` returns
   non-term). The `grading_summary_quarter` blade does NOT have this
   fallback. If the target needs it on both pages, copy the same logic.

3. **`TERM_MAP` is SY-keyed.** Switching the SY dropdown picks up a
   different `$termMap[syid]` entry, so the page correctly transitions
   between term-mode and quarter-mode SYs without reload.

4. **`window.getActiveTermCfg` is globally exported.** Both blades expose it
   on `window` so the print handlers can check it without passing the config
   through. If the target has a module system (webpack), this pattern may
   need adaptation.

5. **`periodVisible(n, cfg)` hides excess columns.** A 3-term config hides
   the Q4 column. The DataTable `visible` property on column definitions
   must match the `periodVisible` check, otherwise DataTable column indexes
   shift and data lands in the wrong column.

6. **Semester-based column hiding is skipped in term mode.** The grading
   sheet normally hides Q3/Q4 for semester 1 and Q1/Q2 for semester 2 (SHS
   only). In term mode, this logic is skipped entirely — all configured
   term columns are shown, because term-based classes span both semesters.

7. **`semid=0` for SHS print exports.** The print handlers check
   `getActiveTermCfg()` and override `semid` to `0` when in term mode.
   The print endpoint must handle `semid=0` correctly (see Module 09 for
   master sheet and grading sheet report handling).

8. **The `reset_data_table()` function uses fixed Q1–Q4 headers.** When the
   DataTable is reset (no data loaded), it shows Q1/Q2/Q3/Q4 column titles
   regardless of term mode. This is cosmetic — the real headers are applied
   when data loads via `loaddatatable()` or `loaddatatable_gradingsheet()`.

9. **Master sheet status colors.** The master sheet DataTable uses
   `createdCell` to color-code cells by `grades[n].status`:
   - `status == 4` → `bg-info` (Posted)
   - `status == 1` → `bg-success` (Submitted)
   - `status == 2` → `bg-primary` (Approved)
   - `status == 3` → `bg-warning` (Pending)
   - `status == 5` → `bg-danger` (Returned/Rejected)
   - `status == 6` → `bg-indigo`
   - else → `bg-secondary` (Not Submitted)

   This logic is term-agnostic — it colors based on the `status` value from
   the server regardless of whether the quarter value maps to a term.

10. **Wrap every `ibed_term_config` read with `activeConfigQuery()`.** The
    `$termMap` construction already goes through `activeConfigQuery`
    internally, but any new direct `ibed_term_config` or `ibed_term` query
    added to these blades must also be wrapped. A bare `where('deleted', 0)`
    read without the guard resurfaces an Inactive config — the #1 source of
    "terms showing where they shouldn't" (Module 05 invariant).

---

## Verification

1. **Quarter-mode level:** Select a non-term SY and a grade level. Verify
   the quarter picker shows "Select Quarter" with Q1–Q4 options (or
   semester-scoped for SHS). Grading sheet headers show Q1/Q2/Q3/Q4.
   Semester dropdown is visible for SHS.

2. **Term-mode SHS level:** Select a term-configured SY and Grade 11 or 12.
   Verify:
   - Quarter picker shows "Select Term" with configured labels + "Final
     Rating".
   - Semester dropdown is hidden.
   - Grading sheet headers show term labels (e.g., "1st Term", "2nd Term",
     "3rd Term") and Q4 column is hidden for 3-term config.
   - Master sheet loads correctly with term-period data.

3. **Term-mode JHS/GS level:** Select a JHS level with term config. Verify
   quarter picker shows term labels and grading sheet headers relabel.

4. **Print master sheet (term mode):** Click PDF. Verify the print URL
   includes `semid=0` for SHS term mode. Report renders with correct
   term columns.

5. **Print grading sheet (term mode):** Click PRINT GRADING SHEET. Verify
   the print URL includes `semid=0` for SHS term mode.

6. **SY switch:** Switch from a term-mode SY to a non-term SY. Verify
   columns revert to Q1–Q4 and semester dropdown reappears for SHS.

7. **Summary of Quarterly Grades page:** Navigate to
   `/teacher/grade/summary/quarter`. Verify same term-aware behavior as the
   main grade summary (term labels, column hiding, semester hiding).

8. **Mixed levels:** In the same SY, check a term-mode level and a
   quarter-mode level. Each should display correctly per its config.
