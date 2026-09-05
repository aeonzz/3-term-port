# Module P7 — Class Schedule / Teacher ECR Page

The Class Schedule page (`/classschedule`) is the superadmin / teacher view
that lists every subject a teacher is assigned to — SHS subject-plot classes,
GS/JHS assigned-subject classes, and SHS cluster-plot electives — with an
ECR modal for viewing, uploading, downloading, and submitting class records.
In term mode the page splits the schedule into two tabs ("Quarterly Classes"
and "Term-Based Classes"), swaps the ECR modal's quarter picker to a term
picker, and routes ECR downloads/uploads through the v2 (term-aware) endpoint.

This is a **portal-surface** module (not one of the core 01–10 layers). It
consumes the resolvers from **Module 05** — specifically `resolveShsPeriods()`
(SHS) and `resolveTermLabelsForLevel()` (JHS/GS) — and depends on **P2**
(subject-plot whole-year conversion) and **P3** (cluster-plot whole-year
conversion) for the data it reads.

## Goal — what this port must achieve

After this port, the class schedule page correctly displays and allows ECR
operations for both quarter-based and term-based classes within the same
school year. Concretely:

1. **Schedule query gating (SHS).** The controller uses per-level
   `resolveShsPeriods()` to skip the semester filter for term-mode SHS levels,
   so whole-year subject-plot schedules (`semid = NULL`) appear.
2. **Schedule query gating (cluster plots).** Cluster-plot queries use
   per-level term detection to filter by `semid IS NULL` for term levels.
3. **Per-item term metadata.** Each schedule item gets `is_term_mode` (0/1)
   and `terms` (array of `{term_no, label}`) so the blade can branch per row.
4. **Tab split.** The blade splits `all_sched` into quarterly vs term-based
   arrays and renders them in separate tabs with count badges.
5. **ECR modal period swap.** When a term-based class is selected, the
   quarter dropdown repopulates with term labels and the label reads "Term"
   instead of "Quarter".
6. **ECR endpoint routing.** Term-based classes route ECR view/upload/download
   through the v2 endpoints (`/ecr/viewv2`, `/ecr/uploadv2`, `/ecr/downloadv2`)
   or through the IBED component ECR (`/ibed-ecr/*`) when applicable.
7. **JHS/GS term support.** The controller also checks
   `resolveTermLabelsForLevel()` for non-SHS levels, so JHS classes with term
   config also get the `is_term_mode` flag and term labels.
8. **ECR modal sidebar wiring.** The modal sidebar (left panel) drives the
   complete ECR workflow — filter, view, upload, download, submit, and status
   display — all branching on `is_ibed_ecr` (component-based vs legacy) and
   `is_term_ecr` (term vs quarter). The sidebar's Grade Status / Last date
   Uploaded / Grade Submitted fields load from `/ibed-ecr/view?meta_only=1`
   for component ECR classes, and the Submit button routes through
   `/gradesSubmit/{quarter}` (component) or `ecr_endpoint('submit')` (legacy,
   with v2 suffix for term mode).
9. **Per-quarter IBED re-check.** When the term/quarter picker changes, an
   AJAX call to `/ecr/check-ibed` re-checks `has_ibed_components` for that
   specific quarter — because a class that switched to the dynamic ECR in one
   quarter may still use legacy ECR in another.

**Acceptance criteria (all must hold):**

- [ ] Semester-only SY: all classes appear under "Quarterly Classes" tab, ECR
      modal shows quarter picker (1st–4th Quarter), semester filter visible.
- [ ] Term-mode SHS level: term-mode classes appear under "Term-Based Classes"
      tab with correct count badge. ECR modal shows term picker with configured
      term labels. Semester filter hidden when viewing term tab.
- [ ] Term-mode JHS level: JHS classes with term config also appear under
      "Term-Based Classes" tab with term labels from
      `resolveTermLabelsForLevel()`.
- [ ] Cluster-plot electives: term-mode cluster plots appear under "Term-Based
      Classes" tab with correct enrolled count (from
      `sh_cluster_subject_picking`).
- [ ] ECR download/upload: term-based classes use v2 endpoints; component-based
      ECR classes use `/ibed-ecr/*` endpoints.
- [ ] Mixed SY: one level on quarters, another on terms — both display correctly
      in their respective tabs.
- [ ] 4-quarter-shaped config: excluded from term mode (per `resolveShsPeriods`
      / `resolveTermLabelsForLevel` upstream guards) — stays under "Quarterly
      Classes".
- [ ] ECR modal sidebar — component ECR: Filter loads the dynamic component
      table via `/ibed-ecr/view`, Grade Status / Last date Uploaded / Grade
      Submitted populate from `/ibed-ecr/view?meta_only=1`, Submit routes
      through `/gradesSubmit/{quarter}` (GET), Download opens
      `/ibed-ecr/download`.
- [ ] ECR modal sidebar — legacy ECR (term): Filter loads via
      `/ecr/viewv2`, Submit routes through `/ecr/submitv2` (POST), Download
      opens `/ecr/downloadv2`.
- [ ] ECR modal sidebar — legacy ECR (quarter): Filter loads via
      `/ecr/view`, Submit routes through `/ecr/submit` (GET), Download opens
      `/ecr/download`.
- [ ] Per-quarter IBED re-check: changing the term/quarter picker fires
      `/ecr/check-ibed` and updates `is_ibed_ecr` for that quarter.
- [ ] Submit button state: for component ECR, Submit is disabled until at least
      one student checkbox is checked; for legacy ECR, Submit is always enabled
      after filter. Ungraded students trigger a warning count in the
      confirmation dialog.

> **Report back after applying (do this in chat).** When the port is done, post
> the acceptance criteria as a **ticked checklist** — **✅** applied and verified,
> **✔️** code applied but runtime/live-page test still pending, **⬜** skipped or
> not applicable (say why). Never mark ✅ something you didn't apply.

## Behaviors by level / config state

| Level / config state | Expected behavior |
|----------------------|-------------------|
| **No term config** | Legacy quarter mode — class under "Quarterly Classes" tab, ECR modal shows 1st–4th Quarter (SHS: filtered by semester). |
| **Term config, not plotted (SHS)** | `resolveShsPeriods` returns non-term — stays under "Quarterly Classes" tab. |
| **Term config, whole-year plotted (SHS)** | Full term mode — class under "Term-Based Classes" tab, ECR modal shows term labels, ECR routed through v2. |
| **Term config (JHS/GS)** | `resolveTermLabelsForLevel` detects term mode — class under "Term-Based Classes" tab with term labels. |
| **4-quarter-shaped config** | Upstream resolvers exclude it — stays under "Quarterly Classes" tab. |

## PREFLIGHT — check the repo FIRST

Before editing, verify these symbols/files exist in the target repo:

```bash
# Module 05 foundation
grep -r "class IBEDGradingDefaults" app/Support/
grep -r "resolveShsPeriods\|resolveTermLabelsForLevel" app/Support/

# Target controller
grep -rl "TeacherECRController" app/Http/Controllers/
grep -n "function schedule" \
    app/Http/Controllers/SuperAdminController/TeacherECRController.php

# Target view
grep -rl "teacherinformation" resources/views/superadmin/pages/teacher/

# Route
grep -n "classschedule\|teacher/schedule" routes/web.php
```

If `resolveShsPeriods` or `resolveTermLabelsForLevel` are missing, apply
**Module 05** first.

## Files to check and update

| # | File | What to do |
|---|------|------------|
| 1 | `app/Http/Controllers/SuperAdminController/TeacherECRController.php` | Update `schedule()` with term-aware query gating and per-item term metadata |
| 2 | `resources/views/superadmin/pages/teacher/teacherinformation.blade.php` | Add tab split UI, ECR modal period swap, v2 endpoint routing |

## Changes

### Change 1 — `schedule()`: per-level SHS term detection for subject-plot queries

**File:** `app/Http/Controllers/SuperAdminController/TeacherECRController.php`

At the top of `schedule()`, resolve term mode for both SHS levels:

```php
$g11TermMode = !empty(\App\Support\IBEDGradingDefaults::resolveShsPeriods($syid, 14)['isTermMode']);
$g12TermMode = !empty(\App\Support\IBEDGradingDefaults::resolveShsPeriods($syid, 15)['isTermMode']);
```

Use per-level branching on the main `sh_classsched` query to skip the semester
filter for term-mode levels:

```php
$sched = DB::table('sh_classsched')
    ->where('sh_classsched.syid', $syid)
    ->where(function ($q) use ($semid, $g11TermMode, $g12TermMode) {
        $q->where(function ($sub) use ($semid, $g11TermMode) {
            $sub->where('sh_classsched.glevelid', 14);
            if (!$g11TermMode) {
                $sub->where('sh_classsched.semid', $semid);
            }
        })->orWhere(function ($sub) use ($semid, $g12TermMode) {
            $sub->where('sh_classsched.glevelid', 15);
            if (!$g12TermMode) {
                $sub->where('sh_classsched.semid', $semid);
            }
        });
    })
    ->where('sh_classsched.deleted', 0)
    ->where('sh_classsched.teacherid', $teacherid)
    // ... joins and selects
```

This ensures that for a term-mode SHS level, whole-year schedules
(`semid = NULL`) are included alongside any semester-stamped rows.

### Change 2 — `schedule()`: per-item term-mode resolution in the loop

**File:** `app/Http/Controllers/SuperAdminController/TeacherECRController.php`

Inside the `foreach ($subject as $item)` loop, for SHS items
(`acadprogid == 5`), resolve term mode per-item:

```php
$itemTermMode = !empty(\App\Support\IBEDGradingDefaults::resolveShsPeriods($syid, $item->levelid)['isTermMode']);
```

Then gate all semester-dependent queries with `->when(!$itemTermMode, ...)`
/ `->when($itemTermMode, ...)`:

```php
// subject_plot strand lookup
$subjstrand = DB::table('subject_plot')
    ->where('subject_plot.subjid', $item->subjid)
    ->where('subject_plot.levelid', $item->levelid)
    ->where('subject_plot.syid', $syid)
    ->when(!$itemTermMode, function ($q) use ($semid) {
        return $q->where('subject_plot.semid', $semid);
    })
    ->when($itemTermMode, function ($q) {
        return $q->whereNull('subject_plot.semid');
    })
    // ...

// sh_enrolledstud counts
->when(!$itemTermMode, function ($q) use ($semid) {
    return $q->where('sh_enrolledstud.semid', $semid);
})

// sh_classsched detail fetch
->when(!$itemTermMode, function ($q) use ($semid) {
    return $q->where('sh_classsched.semid', $semid);
})
```

### Change 3 — `schedule()`: cluster-plot query with per-level term gating

**File:** `app/Http/Controllers/SuperAdminController/TeacherECRController.php`

After the subject-plot loop, query cluster-plot electives with the same
per-level term branching:

```php
$grade11TermMode = !empty(\App\Support\IBEDGradingDefaults::resolveShsPeriods($syid, 14)['isTermMode']);
$grade12TermMode = !empty(\App\Support\IBEDGradingDefaults::resolveShsPeriods($syid, 15)['isTermMode']);

$clusterPlots = DB::table('sh_cluster_plot as cp')
    ->where('cp.deleted', 0)
    ->where('cp.syid', $syid)
    ->where(function ($q) use ($semid, $grade11TermMode, $grade12TermMode) {
        $q->where(function ($qq) use ($semid, $grade11TermMode) {
            $qq->where('cp.levelid', 14);
            if ($grade11TermMode) {
                $qq->whereNull('cp.semid');
            } else {
                $qq->where('cp.semid', $semid);
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
    ->whereExists(function ($sub) use ($requested_teacherid) {
        $sub->select(DB::raw(1))
            ->from('sh_cluster_plot_teacher as cpt')
            ->whereColumn('cpt.plotid', 'cp.id')
            ->where('cpt.teacherid', $requested_teacherid)
            ->where('cpt.deleted', 0);
    })
    // ... joins and selects
```

Cluster-plot enrolled count comes from `sh_cluster_subject_picking`, not
`sh_enrolledstud`.

### Change 4 — `schedule()`: term metadata stamp with caching

**File:** `app/Http/Controllers/SuperAdminController/TeacherECRController.php`

After all schedule items are collected, stamp each with `is_term_mode` and
`terms`. Use a cache keyed by `levelid|semid` to avoid redundant resolver
calls:

```php
$termCache = [];
foreach ($subject as $schedItem) {
    $levelid = $schedItem->levelid ?? null;
    $cacheKey = $levelid . '|' . $semid;

    if (!array_key_exists($cacheKey, $termCache)) {
        $periods = [];
        $isTermMode = false;

        if (in_array((int) $levelid, [14, 15], true)) {
            $shs = \App\Support\IBEDGradingDefaults::resolveShsPeriods($syid, $levelid);
            if (!empty($shs['isTermMode']) && !empty($shs['terms'])) {
                foreach ($shs['terms'] as $shsTerm) {
                    $periods[] = [
                        'term_no' => (int) $shsTerm['term_no'],
                        'label' => $shsTerm['label'],
                    ];
                }
                $isTermMode = true;
            }
        }

        if (!$periods) {
            $termLabels = \App\Support\IBEDGradingDefaults::resolveTermLabelsForLevel($syid, $levelid);
            if (!empty($termLabels['isTermGrading'])) {
                foreach ($termLabels['terms'] as $term) {
                    $periods[] = [
                        'term_no' => (int) $term['term_no'],
                        'label' => $term['label'],
                    ];
                }
                $isTermMode = true;
            }
        }

        $termCache[$cacheKey] = ['periods' => $periods, 'is_term_mode' => $isTermMode];
    }

    $schedItem->terms = $termCache[$cacheKey]['periods'];
    $schedItem->is_term_mode = $termCache[$cacheKey]['is_term_mode'] ? 1 : 0;
}
```

This covers **both SHS and JHS/GS** term detection in a single pass. The SHS
path uses `resolveShsPeriods` (config + plotting gate); the JHS/GS fallback
uses `resolveTermLabelsForLevel` (config only, excludes 4-quarter configs).

### Change 5 — `schedule()`: `has_ibed_components` stamp

**File:** `app/Http/Controllers/SuperAdminController/TeacherECRController.php`

Each schedule item also gets `has_ibed_components` (0/1), which determines
whether the ECR modal renders the legacy raw-grade ECR or the dynamic
component-based ECR:

```php
$schedItem->has_ibed_components = self::hasIbedComponents(
    $schedItem->levelid,
    $schedItem->subjid,
    $syid,
    $schedItem->sectionid ?? null,
    $schedItem->semid ?? null,
    !empty($schedItem->is_cluster)
) ? 1 : 0;
```

This is independent of term mode — a term-mode class may or may not have IBED
components.

### Change 6 — Blade: tab split UI

**File:** `resources/views/superadmin/pages/teacher/teacherinformation.blade.php`

Add tabs in the card header:

```html
<ul class="nav nav-tabs" id="sched_tabs">
    <li class="nav-item">
        <a class="nav-link active" href="#" data-mode="quarter">Quarterly Classes
            <span class="badge badge-secondary ml-1" id="count_quarter">0</span></a>
    </li>
    <li class="nav-item" id="tab_term_wrapper" style="display:none">
        <a class="nav-link" href="#" data-mode="term">Term-Based Classes
            <span class="badge badge-secondary ml-1" id="count_term">0</span></a>
    </li>
</ul>
```

In JS, track `sched_mode` and split `all_sched` on load:

```javascript
var sched_mode = 'quarter';

$(document).on('click', '#sched_tabs .nav-link', function(e) {
    e.preventDefault()
    sched_mode = $(this).attr('data-mode')
    $('#sched_tabs .nav-link').removeClass('active')
    $(this).addClass('active')
    load_gradesetup_datatable()
})
```

In `load_gradesetup_datatable()`, filter by `is_term_mode`:

```javascript
var quarter_sched = all_sched.filter(function(item) {
    return item.is_term_mode != 1
})
var term_sched = all_sched.filter(function(item) {
    return item.is_term_mode == 1
})

$('#count_quarter').text(quarter_sched.length)
$('#count_term').text(term_sched.length)
$('#tab_term_wrapper').toggle(term_sched.length > 0)

// Auto-switch back to quarter tab if no term classes
if (term_sched.length == 0 && sched_mode == 'term') {
    sched_mode = 'quarter'
    $('#sched_tabs .nav-link').removeClass('active')
    $('#sched_tabs .nav-link[data-mode="quarter"]').addClass('active')
}

// Term-based classes span the whole school year, so semester does not filter them.
$('#filter_sem_wrapper').toggle(sched_mode != 'term')

$("#subjectplot_table").DataTable({
    destroy: true,
    data: sched_mode == 'term' ? term_sched : quarter_sched,
    // ... column definitions
})
```

### Change 7 — Blade: ECR modal period swap

**File:** `resources/views/superadmin/pages/teacher/teacherinformation.blade.php`

When a schedule row is clicked to open the ECR modal, check `is_term_mode`
and `terms` to swap the quarter picker:

```javascript
is_ibed_ecr = (temp_sched[0] && temp_sched[0].has_ibed_components == 1);
is_term_ecr = (temp_sched[0] && temp_sched[0].is_term_mode == 1);

$('#label_period').text(period_noun())
$('#filter_quarter').empty();
$('#filter_quarter').append('<option value="">Select ' + period_noun() + '</option>');

if (is_term_ecr) {
    $.each(temp_sched[0].terms, function(a, term) {
        $('#filter_quarter').append('<option value="' + term.term_no + '">' +
            term.label + '</option>');
    })
} else if (temp_sched[0].levelid == 14 || temp_sched[0].levelid == 15) {
    // SHS semester-based: show only the 2 quarters for the active semester
    if ($('#filter_sem').val() == 1) {
        $('#filter_quarter').append('<option value="1">1st Quarter</option>');
        $('#filter_quarter').append('<option value="2">2nd Quarter</option>');
    } else {
        $('#filter_quarter').append('<option value="3">3rd Quarter</option>');
        $('#filter_quarter').append('<option value="4">4th Quarter</option>');
    }
} else {
    // JHS/GS quarter-based: show all 4
    $('#filter_quarter').append('<option value="1">1st Quarter</option>');
    $('#filter_quarter').append('<option value="2">2nd Quarter</option>');
    $('#filter_quarter').append('<option value="3">3rd Quarter</option>');
    $('#filter_quarter').append('<option value="4">4th Quarter</option>');
}
```

The `period_noun()` helper returns "Term" or "Quarter":

```javascript
function period_noun() {
    return is_term_ecr ? 'Term' : 'Quarter'
}
```

### Change 8 — Blade: ECR endpoint routing

**File:** `resources/views/superadmin/pages/teacher/teacherinformation.blade.php`

Term-based classes route through v2 endpoints:

```javascript
function ecr_endpoint(action) {
    return '/ecr/' + action + (is_term_ecr ? 'v2' : '')
}
```

This affects `/ecr/view` → `/ecr/viewv2`, `/ecr/upload` → `/ecr/uploadv2`,
`/ecr/download` → `/ecr/downloadv2`, and `/ecr/submit` → `/ecr/submitv2`.

Component-based ECR classes (`is_ibed_ecr == true`) always use the
`/ibed-ecr/*` endpoints regardless of term mode.

### Change 9 — Blade: ECR modal sidebar layout and meta display

**File:** `resources/views/superadmin/pages/teacher/teacherinformation.blade.php`

The ECR modal is a `modal-xl` with a left sidebar (`col-md-3`) and a right
content area (`col-md-9`). The sidebar contains:

```html
<!-- Top: ECR Format dropdown + Download button -->
<select id="ecr_format">...</select>
<button id="download_ecr">Download ECR</button>
<hr>

<!-- Class info -->
<p id="label_gradelevel">--</p>
<p id="label_section">--</p>
<p id="label_subject">--</p>  <!-- appends "Component-based ECR" badge if is_ibed_ecr -->
<p id="label_subjectcode">--</p>
<hr>

<!-- Period picker + action buttons -->
<label id="label_period">Quarter</label>  <!-- swaps to "Term" via period_noun() -->
<select id="filter_quarter">...</select>  <!-- repopulated per is_term_ecr -->
<button id="ecr_filter">Filter</button>
<button id="ecr_submit" disabled>Submit</button>
<hr>

<!-- Status fields (populated by load_ecr_meta for component ECR) -->
<p id="label_dateuploaded">--</p>
<p id="label_status">--</p>
<p id="label_datesubmitted">--</p>
```

When `.view_classrecord` is clicked (opening the modal for a schedule row):

1. `is_ibed_ecr` and `is_term_ecr` are set from `temp_sched[0]`.
2. Sidebar labels are populated from the schedule item.
3. Subject label appends a `<span class="badge badge-info">Component-based ECR</span>`
   badge if `is_ibed_ecr`.
4. The period picker is repopulated based on mode (see Change 7).
5. For cluster-plot items without component ECR, upload is disabled (legacy
   `/ecr/upload` has no `clusterplotid` handling).
6. The upload form's `action` is set to `ecr_endpoint('upload')`.
7. The strand picker is shown if the subject has multiple strands (SHS only,
   non-cluster).

**`load_ecr()` itself — the function that actually fetches the class record
into `#ecr_view_holder`:**

```javascript
function load_ecr() {
    $.ajax({
        url: is_ibed_ecr ? '/ibed-ecr/view' : ecr_endpoint('view'),
        type: 'GET',
        // Re-fetched with identical params right after a submit, and must
        // never be allowed to reflect a cached pre-submit response.
        cache: false,
        data: {
            semid: $('#filter_sem').val(),
            syid: $('#filter_sy').val(),
            quarter: $('#filter_quarter').val(),
            levelid: temp_sched[0].levelid,
            subjid: temp_sched[0].subjid,
            sectionid: temp_sched[0].sectionid,
            clusterplotid: selected_clusterplotid,
            ecrformat: $('#ecr_format').val(),
            // This modal is a preview/download surface, not the teacher's own
            // grading page — it must not expose live Save/Submit editing. The
            // actual grading interface is System Grading or the ECR Excel
            // upload/download flow, not this Class Record popup.
            readonly: 1
        },
        success: function(data) { /* ... renders into #ecr_view_holder ... */ }
    })
}
```

`readonly: 1` is the important part — without it, `IBEDECRController::view()`
defaults `$readOnly` to `false` and the dynamic component-ECR partial
(`ibed_gradeview.blade.php`) renders its full editable form: live score
inputs and the in-table "Save Grades" / "Submit Grades" buttons, inside what
is supposed to be a read-only preview. The partial's own `$readOnly &&
$gradesId` branch already renders correctly (Select All/Deselect All only,
no Save/Submit) — the bug is purely a missing request parameter, easy to
port past unnoticed because `load_ecr()`'s full body is otherwise assumed
"already correct" and not spelled out like `load_ecr_meta()`'s is below.
Legacy (non-component) ECR classes are unaffected — the legacy view has no
live-editing controls to begin with.

### Change 10 — Blade: ECR meta display (`load_ecr_meta`)

**File:** `resources/views/superadmin/pages/teacher/teacherinformation.blade.php`

When the filter button is clicked, component-ECR classes also call
`load_ecr_meta()` to populate the sidebar status fields:

```javascript
$(document).on('click', '#ecr_filter', function() {
    if ($('#filter_quarter').val() == "") {
        Toast.fire({ type: 'warning', title: 'Select a ' + period_noun().toLowerCase() + '!' });
        return false;
    }
    load_ecr()
    if (is_ibed_ecr) {
        load_ecr_meta()
    }
})

function load_ecr_meta() {
    $.ajax({
        url: '/ibed-ecr/view',
        type: 'GET',
        cache: false,  // prevent stale post-submit reads
        data: {
            semid: $('#filter_sem').val(),
            syid: $('#filter_sy').val(),
            quarter: $('#filter_quarter').val(),
            levelid: temp_sched[0].levelid,
            subjid: temp_sched[0].subjid,
            sectionid: temp_sched[0].sectionid,
            clusterplotid: selected_clusterplotid,
            meta_only: 1
        },
        success: function(meta) {
            $('#label_dateuploaded').text(meta.uploadeddatetime || '--')
            $('#label_status').text(meta.status_text || '--')
            $('#label_datesubmitted').text(meta.date_submitted || '--')
        }
    })
}
```

The `meta_only: 1` param makes the server return only the status metadata
(upload date, grade status text, submission date) without the full class
record HTML. This is separate from `load_ecr()` which fetches the full table.

Legacy ECR classes have no equivalent meta endpoint — their sidebar status
fields stay at `--`.

### Change 11 — Blade: ECR submit wiring with component/legacy/term branching

**File:** `resources/views/superadmin/pages/teacher/teacherinformation.blade.php`

The submit button (`#ecr_submit`) handler branches on both `is_ibed_ecr` and
`is_term_ecr`:

```javascript
$(document).on('click', '#ecr_submit', function() {
    // Warn about ungraded students (component ECR only)
    var ungradedCount = 0
    if (is_ibed_ecr) {
        $('#ecr_view_holder .ibed-ig-cell').each(function() {
            if ($(this).text().trim() === '') { ungradedCount++ }
        })
    }
    // ... SweetAlert2 confirmation dialog with ungraded warning ...

    // URL and data branching:
    var submitUrl = is_ibed_ecr
        ? ('/gradesSubmit/' + $('#filter_quarter').val())   // component ECR
        : ecr_endpoint('submit')                           // legacy: /ecr/submit or /ecr/submitv2

    var submitData = is_ibed_ecr ? {
        syid, quarter, gradelevelid, subjectid, section,   // component ECR param names
        semid, clusterplotid, dataHolder: 'submit', excluded
    } : {
        syid, quarter, levelid, subjid, sectionid,         // legacy ECR param names
        clusterplotid, excluded
    }

    $.ajax({
        url: submitUrl,
        type: is_ibed_ecr ? 'GET' : (is_term_ecr ? 'POST' : 'GET'),
        // ...
        success: function(data) {
            if (is_ibed_ecr) {
                // /gradesSubmit returns bare 1 on success
                Toast.fire({ type: 'success', title: 'Grades submitted.' })
                update_sidenav()
                load_ecr()   // refresh the table + meta
                return
            }
            // Legacy: data[0].status / data[0].message response shape
            // ...
        }
    })
})
```

Key branching points:

| | Component ECR (`is_ibed_ecr`) | Legacy quarter | Legacy term (`is_term_ecr`) |
|---|---|---|---|
| **Submit URL** | `/gradesSubmit/{quarter}` | `/ecr/submit` | `/ecr/submitv2` |
| **HTTP method** | GET | GET | POST |
| **Param names** | `gradelevelid`, `subjectid`, `section` | `levelid`, `subjid`, `sectionid` | `levelid`, `subjid`, `sectionid` |
| **Response shape** | bare `1` | `[{status, message}]` | `[{status, message}]` |
| **Extra params** | `dataHolder: 'submit'` | — | — |

### Change 12 — Blade: submit button state management

**File:** `resources/views/superadmin/pages/teacher/teacherinformation.blade.php`

The Submit button's enabled/disabled state is managed by
`updateEcrSubmitState()`:

```javascript
function updateEcrSubmitState() {
    var $checkboxes = $('#ecr_view_holder .exclude')
    if ($checkboxes.length === 0) {
        // Legacy ECR / raw-grade dynamic ECR: no checkboxes → always enabled
        $('#ecr_submit').removeAttr('disabled')
        return
    }
    // Component ECR: disabled unless at least one student is checked
    var hasSelection = $checkboxes.filter(':not(:disabled):checked').length > 0
    $('#ecr_submit').prop('disabled', !hasSelection)
}
```

This runs on:
- `load_ecr()` success (after table renders).
- `.exclude` checkbox change events (individual student toggles).
- `.select_all` click (header checkbox).
- `.ibed-select-all` / `.ibed-deselect-all` clicks and `.ibed-select-all-header`
  change (component ECR partial's own select/deselect links — deferred one
  tick via `setTimeout` so the partial's own handler finishes first).

When the quarter/term picker changes, Submit is disabled and the view is
cleared, pending a new Filter click.

### Change 13 — Blade: per-quarter IBED re-check on period change

**File:** `resources/views/superadmin/pages/teacher/teacherinformation.blade.php`

When the term/quarter picker value changes, an AJAX call re-checks whether
the selected quarter uses the component-based ECR:

```javascript
$(document).on('change', '#filter_quarter', function() {
    $('#ecr_submit').attr('disabled', 'disabled')
    $('#input_ecr').val("")
    $('#upload_ecr_button').attr('disabled', 'disabled')
    $('#ecr_view_holder').empty()
    // ... placeholder table

    if (temp_sched[0] && $('#filter_quarter').val() != "") {
        $.ajax({
            url: '/ecr/check-ibed',
            type: 'GET',
            data: {
                syid: $('#filter_sy').val(),
                semid: $('#filter_sem').val(),
                quarter: $('#filter_quarter').val(),
                levelid: temp_sched[0].levelid,
                subjid: temp_sched[0].subjid,
                sectionid: temp_sched[0].sectionid,
                clusterplotid: selected_clusterplotid
            },
            success: function(resp) {
                is_ibed_ecr = (resp.has_ibed_components == 1);
            }
        })
    }
})
```

This prevents a class that switched to the dynamic ECR in one quarter from
having all its other quarters incorrectly routed through the component ECR
endpoints.

### Change 14 — Blade: download ECR routing

**File:** `resources/views/superadmin/pages/teacher/teacherinformation.blade.php`

The `#download_ecr` button handler branches three ways:

```javascript
$(document).on('click', '#download_ecr', function() {
    if (is_ibed_ecr) {
        // Component ECR: server builds one sheet per term for the current semester
        window.open('/ibed-ecr/download?syid=...&semid=...&quarter=...&levelid=...' +
            '&sectionid=...&subjid=...' +
            (selected_clusterplotid ? '&clusterplotid=...' : ''));
        return;
    }

    if (selected_clusterplotid != null) {
        // Cluster-plot legacy: always includes clusterplotid
        window.open(ecr_endpoint('download') + '?syid=...&clusterplotid=...');
        return;
    }

    if (temp_sched[0].levelid == 14 || temp_sched[0].levelid == 15) {
        // SHS non-cluster: show strand picker modal, then download with strandid
        $('#select_strand').modal()
        // ... populate strand buttons
    } else {
        // JHS/GS: direct download
        window.open(ecr_endpoint('download') + '?syid=...');
    }
})
```

All non-component-ECR downloads use `ecr_endpoint('download')` which appends
`v2` for term-mode classes.

Cluster-plot items also have a direct download button in the DataTable
(`.download_cluster_ecr`) that follows the same `is_ibed_ecr` / `is_term_mode`
branching per item.

---

## Dependencies

- **Module 01** — schema (`ibed_term`, `ibed_term_config` tables).
- **Module 05** — `IBEDGradingDefaults::resolveShsPeriods()`,
  `IBEDGradingDefaults::resolveTermLabelsForLevel()`.
- **Module P2** — subject-plot whole-year conversion (sets
  `subject_plot.semid = NULL` and `sh_classsched.semid = NULL` for term-mode
  levels).
- **Module P3** — cluster-plot whole-year conversion (sets
  `sh_cluster_plot.semid = NULL`).
- **Module 07** — term-aware ECR v2 endpoints (`/ecr/viewv2`,
  `/ecr/uploadv2`, `/ecr/downloadv2`, `/ecr/submitv2`) and the IBED
  component ECR (`/ibed-ecr/*`).

---

## Porting notes / gotchas

1. **Two resolver paths: SHS vs JHS/GS.** SHS levels use `resolveShsPeriods`
   (which requires both config AND whole-year plotting). JHS/GS levels use
   `resolveTermLabelsForLevel` (config only). The controller's term-metadata
   stamp checks SHS first, then falls back to JHS/GS. Don't collapse them —
   they have different gates.

2. **`requested_teacherid` vs `$teacherid`.** The `schedule()` method saves
   the original teacher filter as `$requested_teacherid` at the top, because
   the per-subject loop reassigns `$teacherid` to null while building teacher
   info. The cluster-plot teacher filter uses `$requested_teacherid`.

3. **Level IDs 14/15 are school-specific.** Verify in the target school's
   `gradelevel` table. The SHS semester-based quarter picker also hard-codes
   these levels for the 2-quarter-per-semester split.

4. **The `is_term_mode` flag drives three behaviors in the blade:**
   - Tab assignment (quarterly vs term-based).
   - ECR modal period picker (quarter labels vs term labels).
   - ECR endpoint routing (v1 vs v2).

5. **`has_ibed_components` is orthogonal to term mode.** A term-mode class
   may use the legacy raw-grade ECR or the dynamic component-based ECR. The
   blade checks both flags independently: `is_ibed_ecr` for endpoint routing
   (`/ibed-ecr/*` vs `/ecr/*`), and `is_term_ecr` for v1 vs v2 within the
   `/ecr/*` path.

6. **Semester filter visibility.** When viewing the "Term-Based Classes" tab,
   the semester dropdown is hidden (`$('#filter_sem_wrapper').toggle(sched_mode != 'term')`)
   because term-based classes span the whole school year.

7. **The `$termCache` prevents redundant resolver calls.** Each unique
   `levelid|semid` combination is resolved once and reused for all schedule
   items at that level. This is important because a teacher may have many
   subjects at the same level.

8. **Cluster-plot enrolled count** comes from `sh_cluster_subject_picking`
   (how many students picked that elective), not from `sh_enrolledstud`.

9. **ECR submit endpoint.** For IBED component-based ECR, the submit goes
   through `/gradesSubmit/{quarter}` (a GET) regardless of term mode. For
   legacy ECR, term-based classes use `POST /ecr/submitv2`. The blade switches
   on `is_ibed_ecr` first, then `is_term_ecr`.

10. **Submit button param names differ.** The component ECR submit uses
    `gradelevelid`, `subjectid`, `section` (matching the teacher grading page's
    `/gradesSubmit` expectations). The legacy ECR submit uses `levelid`,
    `subjid`, `sectionid`. Mixing them up produces silent 500s.

11. **`/ecr/check-ibed` re-check on quarter change.** The `is_ibed_ecr` flag
    is set once per class when the schedule loads — but a class can switch to
    the dynamic ECR mid-year (one quarter has components, another doesn't).
    The re-check on `#filter_quarter` change prevents mis-routing.

12. **`load_ecr_meta()` only fires for component ECR.** Legacy ECR has no
    `meta_only` endpoint equivalent. The sidebar status fields (`Grade Status`,
    `Last date Uploaded`, `Grade Submitted`) stay at `--` for legacy classes.

13. **`cache: false` on both `load_ecr()` and `load_ecr_meta()`.** Without it,
    a repeat GET with identical params (e.g., reloading right after a submit)
    can serve the browser cache instead of fresh server data, showing
    pre-submit checkbox states and status text.

14. **Cluster upload disabled for legacy ECR.** The legacy `/ecr/upload`
    endpoint has no `clusterplotid` handling. Upload is disabled
    (`$('#input_ecr').attr('disabled')`) when `selected_clusterplotid != null
    && !is_ibed_ecr`. The component ECR's upload is clusterplotid-aware
    throughout.

15. **Wrap every `ibed_term_config` read with `activeConfigQuery()`.** The
    controller's term resolution (via `resolveShsPeriods` / `resolveTermLabelsForLevel`)
    already goes through `activeConfigQuery` internally, but any direct
    `ibed_term_config` query added to the schedule controller or the ECR
    modal JS endpoints must also be wrapped. A bare `where('deleted', 0)`
    read without the `activeConfigQuery` guard resurfaces an Inactive config
    and is the #1 source of "terms showing where they shouldn't." This is a
    project-wide invariant (see Module 05).

16. **`schedule()` must not gate class inclusion — or enrolled-student
    counting — on a live `subject_plot` row existing.** A target repo's copy
    of this method can pick up an extra `if ($check_if_exist_in_plot > 0)`
    check around its `sh_classsched`/`assignsubj` loops that **es_ldcu's real
    `schedule()` does not have at all** (it pushes every scheduled item
    unconditionally) — this silently drops a real, actively-taught class the
    moment its `subject_plot` row goes missing or gets soft-deleted (a
    subject-catalog cleanup, e.g.), even though the same class shows up fine
    on other pages (like `/grades/getsubjects`) that don't have the gate.
    Separately, further down in the same method, the student-count logic
    (strand-derived from `subject_plot` → `sh_enrolledstud`) needs es_ldcu's
    `else` branch — count all enrolled students in the section directly when
    no strand resolves — or a plot-less class shows "0 students" even after
    it's visible again. See known-pitfalls.md #17 for the full symptom/fix;
    this is the sixth time this exact "no `grading_percentage_id`/direct
    fallback" bug shape has hit this port, so check for it by default on any
    query in this method that touches `subject_plot`.

17. **`load_ecr()` needs `readonly: 1`, not just `cache: false`.** Porting
    note #13 above covers `cache: false`; the separate `readonly: 1` param is
    easy to miss because, unlike `load_ecr_meta()`, this doc never spells out
    `load_ecr()`'s full body elsewhere — see the code block under Change 9.
    Without it, `IBEDECRController::view()` defaults `$readOnly` to `false`
    and the component-ECR partial renders its own live score inputs plus
    in-table "Save Grades" / "Submit Grades" buttons inside what is meant to
    be a read-only Class Record preview — this modal is not the teacher's
    actual grading page (that's System Grading, or the Excel upload/download
    flow). The partial's own `$readOnly && $gradesId` branch (Select
    All/Deselect All only, no Save/Submit) already handles this correctly
    once the flag is actually passed. Legacy (non-component) ECR is
    unaffected — it has no live-editing controls to begin with.

---

## Verification

1. **Quarter-mode SHS level:** Select a teacher with SHS assignments in a
   non-term SY. Verify all classes appear under "Quarterly Classes" tab. Open
   the ECR modal — quarter picker should show 1st/2nd (sem 1) or 3rd/4th
   (sem 2) quarters.

2. **Term-mode SHS level:** Select a teacher with SHS assignments in a
   term-configured, whole-year-plotted SY+level. Verify:
   - "Term-Based Classes" tab appears with correct count badge.
   - Term-mode classes are listed under that tab.
   - Semester filter is hidden when the term tab is active.
   - ECR modal shows term labels (e.g., "1st Term", "2nd Term", "3rd Term").
   - ECR download uses `/ecr/downloadv2` (or `/ibed-ecr/download` for
     component ECR).

3. **Term-mode JHS/GS level:** Select a teacher with JHS assignments in a
   term-configured SY. Verify the JHS class appears under "Term-Based Classes"
   tab with the correct term labels.

4. **Cluster-plot electives:** Select a teacher assigned to cluster-plot
   subjects. Verify cluster electives appear with the "Cluster Plot" badge,
   correct enrolled count, and correct tab assignment.

5. **Mixed SY:** In the same school year, have one level on quarters and
   another on terms. Verify the tab split and counts are correct, and
   switching between tabs re-renders the DataTable correctly.

6. **ECR modal operations:** For a term-based class, verify:
   - Download ECR works (correct endpoint).
   - Upload ECR works (correct endpoint).
   - View ECR filters by the selected term number.
   - Submit ECR works (correct endpoint and payload).

7. **No schedule:** Select a teacher with no assignments. Verify an empty
   table with no errors and no "Term-Based Classes" tab.

8. **ECR modal sidebar — component ECR (term mode):** Open a term-mode class
   with `has_ibed_components = 1`. Verify:
   - Subject label shows "Component-based ECR" badge.
   - Period picker shows term labels (e.g., "1T", "2T", "3T").
   - Filter loads the component table via `/ibed-ecr/view`.
   - The loaded table itself has **no** live score inputs and **no**
     in-table "Save Grades" / "Submit Grades" buttons — only "Select All" /
     "Deselect All" (this modal is a read-only preview; see porting note #17
     on `load_ecr()`'s `readonly` param). The **sidebar's** own `#ecr_submit`
     button (Change 11) is the only submit control left in this view — it is
     what the two bullets below are testing, not anything inside the loaded
     table.
   - Sidebar shows Grade Status, Last date Uploaded, Grade Submitted
     (from `/ibed-ecr/view?meta_only=1`).
   - Sidebar Submit routes through `/gradesSubmit/{quarter}` (GET).
   - Sidebar Submit button is disabled until at least one student checkbox is checked.
   - Ungraded students trigger a warning count in the submit confirmation.
   - After submit, sidebar status updates (re-fetches meta).
   - Download opens `/ibed-ecr/download`.

9. **ECR modal sidebar — legacy ECR (term mode):** Open a term-mode class
   without IBED components. Verify:
   - No "Component-based ECR" badge.
   - Period picker shows term labels.
   - Filter loads via `/ecr/viewv2`.
   - Sidebar status fields stay at `--` (no meta endpoint for legacy).
   - Submit routes through `/ecr/submitv2` (POST).
   - Download opens `/ecr/downloadv2`.

10. **Per-quarter IBED re-check:** Open a class where quarter 1 has IBED
    components but quarter 2 does not. Switch between them in the period
    picker — verify `is_ibed_ecr` updates and the correct endpoints are used
    for each quarter.

11. **Cluster-plot upload gating:** Open a cluster-plot elective without
    component ECR. Verify the upload file input and button are disabled. Open
    the same elective with component ECR — verify upload is enabled.
