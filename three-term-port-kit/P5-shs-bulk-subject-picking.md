# Module P5 — SHS Bulk Subject Picking

The bulk-pick feature on the SHS Subject Picking page lets registrars select
multiple students from the table, then assign a single cluster-plot subject to
all of them in one request. In term mode the bulk insert inherits the plot's
`semid` (NULL for whole-year/term plots), keeping the convention consistent with
individual picks (P4).

This is a **portal-surface** module (not one of the core 01–10 layers). It
consumes the resolvers from **Module 05** and builds on top of **P4** (individual
subject picking).

## Goal — what this port must achieve

After this port, bulk subject picking works correctly for both semester-based and
term-based SHS levels. Concretely:

1. **Student selection.** Checkboxes on each student row plus a "Select All"
   header checkbox. Selections persist across DataTable pages. A bulk bar shows
   the count and a "Bulk Pick" button.
2. **Level validation.** Bulk pick requires all selected students to share the
   same grade level — mixed levels are rejected with a warning.
3. **Bulk pick modal.** A modal (separate from the individual pick modal) shows
   available plots for the shared level. In term mode, the available-plots
   request uses the same term gating as individual picks (`termid` param,
   `applyClusterTermScope`).
4. **Batch insert with skip logic.** The `bulkPick` endpoint loops through
   students and skips those who already picked the subject, fail prerequisites,
   or would exceed room capacity. It returns a detailed report of picked vs.
   skipped students.
5. **semid from the plot.** The insert uses `$plot->semid`, which is NULL for
   term-mode plots — the same convention as individual `pick()`.

**Acceptance criteria (all must hold):**

- [ ] Student checkboxes appear, selections persist across DataTable pages.
- [ ] "Bulk Pick" button enables only when students are selected, disables at 0.
- [ ] Mixed-level selections: SweetAlert warning, bulk pick blocked.
- [ ] Bulk pick modal loads available plots for the shared level using the same
      term/semester gating as the individual pick modal.
- [ ] `bulkPick` endpoint: `semid` is NULL for term-mode plots, populated for
      semester-mode plots.
- [ ] Skip logic: already-picked, prerequisite failures, and capacity limits are
      reported per-student in the response.
- [ ] After a successful bulk pick, the main student table and the bulk modal's
      plot list both refresh.

> **Report back after applying (do this in chat).** When the port is done, post
> the acceptance criteria as a **ticked checklist** — **✅** applied and verified,
> **✔️** code applied but runtime/live-page test still pending, **⬜** skipped or
> not applicable (say why). Never mark ✅ something you didn't apply.

## Behaviors by level / config state

| Level / config state | Expected behavior |
|----------------------|-------------------|
| **No term config** | Legacy semester mode — bulk modal's available-plots request sends `semid`, inserts use that `semid`. |
| **Term config, not plotted** | Bulk modal shows no available plots (same as individual pick — `applyClusterTermScope` finds no matches). |
| **Term config, whole-year plotted** | Full term mode — bulk modal sends `termid`, inserts store `semid = NULL` (inherited from the plot). |
| **4-quarter-shaped config** | Excluded from the term map (`count !== 4`) — page stays on semester mode. Bulk pick uses semester-based queries. |

## PREFLIGHT — check the repo FIRST

Before editing, verify these symbols/files exist in the target repo:

```bash
# Module 05 foundation
grep -r "class IBEDGradingDefaults" app/Support/
grep -r "shsConfiguredTerms" app/Support/

# P4 subject picking (this module extends it)
grep -rl "ShsSubjectPickingController\|SHSSubjectPickingController" app/Http/Controllers/
grep -n "getAvailablePlots\|applyClusterTermScope" app/Http/Controllers/RegistrarControllers/ShsSubjectPickingController.php

# Target blade
grep -n "bulkPickModal\|btnBulkPick\|bulk-pick" resources/views/registrar/shs/subjectpicking/index.blade.php
```

If `getAvailablePlots` or `applyClusterTermScope` are missing, apply **P4** first.
The bulk-pick feature reuses the same available-plots endpoint as individual
picking.

## Files to check and update

| # | File | What to do |
|---|------|------------|
| 1 | `app/Http/Controllers/RegistrarControllers/ShsSubjectPickingController.php` | Add `bulkPick()` method + route |
| 2 | `resources/views/registrar/shs/subjectpicking/index.blade.php` | Add bulk UI: checkboxes, bulk bar, bulk modal, bulk JS |
| 3 | `routes/web.php` | Add `POST /shs/subjectpicking/bulk-pick` route |

## Changes

### Change 1 — Route

**File:** `routes/web.php`

Add the bulk-pick POST route alongside the existing subject-picking routes:

```php
Route::post('/shs/subjectpicking/bulk-pick', 'RegistrarControllers\ShsSubjectPickingController@bulkPick');
```

### Change 2 — `bulkPick()` controller method

**File:** `app/Http/Controllers/RegistrarControllers/ShsSubjectPickingController.php`

The endpoint accepts `studids` (array or comma-separated string), `syid`, and
`clusterplotid`. It resolves the plot (including `semid`), then loops through
students with skip logic:

```php
public function bulkPick(Request $request)
{
    try {
        $studids = $request->input('studids', []);
        $syid = $request->input('syid');
        $clusterplotid = $request->input('clusterplotid');

        if (!is_array($studids)) {
            $studids = array_filter(explode(',', (string) $studids));
        }
        $studids = array_values(array_unique(array_filter($studids)));

        if (empty($studids)) {
            return response()->json(['success' => false, 'message' => 'No students selected.'], 422);
        }

        $plot = DB::table('sh_cluster_plot as cp')
            ->leftJoin('rooms as r', 'r.id', '=', 'cp.roomid')
            ->where('cp.id', $clusterplotid)
            ->where('cp.deleted', 0)
            ->select('cp.*', 'r.capacity as room_capacity')
            ->first();

        if (!$plot) {
            return response()->json(['success' => false, 'message' => 'Subject plot not found.'], 404);
        }

        $names = DB::table('studinfo')
            ->whereIn('id', $studids)
            ->get(['id', 'lastname', 'firstname'])
            ->keyBy('id')
            ->map(function ($s) {
                return trim($s->lastname . ', ' . $s->firstname);
            });

        $alreadyPickedStuds = DB::table('sh_cluster_subject_picking')
            ->where('clusterplotid', $clusterplotid)
            ->where('deleted', 0)
            ->whereIn('studid', $studids)
            ->pluck('studid')
            ->toArray();

        $enrolled = DB::table('sh_cluster_subject_picking')
            ->where('clusterplotid', $clusterplotid)
            ->where('deleted', 0)
            ->count();

        $prereqs = DB::table('sh_cluster_plot_prereq')
            ->where('clusterplotid', $clusterplotid)
            ->where('deleted', 0)
            ->pluck('prereqsubjid')
            ->toArray();

        $now = Carbon::now('Asia/Manila');
        $insertRows = [];
        $skipped = [];

        foreach ($studids as $studid) {
            $studName = $names[$studid] ?? ('#' . $studid);

            if (in_array($studid, $alreadyPickedStuds)) {
                $skipped[] = ['studid' => $studid, 'name' => $studName, 'reason' => 'Already picked'];
                continue;
            }

            if ($plot->room_capacity > 0 && ($enrolled + count($insertRows)) >= $plot->room_capacity) {
                $skipped[] = ['studid' => $studid, 'name' => $studName, 'reason' => 'Full'];
                continue;
            }

            if (!empty($prereqs)) {
                $passedPrereqs = DB::table('gradesdetail as gd')
                    ->join('grades as g', 'gd.headerid', '=', 'g.id')
                    ->where('gd.studid', $studid)
                    ->whereIn('g.subjid', $prereqs)
                    ->where('g.deleted', 0)
                    ->where('gd.ig', '>=', 75)
                    ->pluck('g.subjid')
                    ->unique()
                    ->toArray();

                if (!empty(array_diff($prereqs, $passedPrereqs))) {
                    $skipped[] = ['studid' => $studid, 'name' => $studName, 'reason' => 'Prerequisites not met'];
                    continue;
                }
            }

            $insertRows[] = [
                'studid'          => $studid,
                'syid'            => $syid,
                'semid'           => $plot->semid,  // NULL for term-mode plots
                'clusterplotid'   => $clusterplotid,
                'createdby'       => Auth::id(),
                'createddatetime' => $now,
                'deleted'         => 0,
            ];
        }

        if (!empty($insertRows)) {
            DB::table('sh_cluster_subject_picking')->insert($insertRows);
        }

        $picked = count($insertRows);
        $skippedCount = count($skipped);
        $message = "Picked for {$picked} student(s).";
        if ($skippedCount) {
            $message .= " Skipped {$skippedCount}.";
        }

        return response()->json([
            'success'       => true,
            'picked'        => $picked,
            'skipped'       => $skipped,
            'skipped_count' => $skippedCount,
            'message'       => $message,
        ]);

    } catch (\Exception $e) {
        return response()->json(['success' => false, 'message' => $e->getMessage()], 500);
    }
}
```

**Term-mode note:** The insert uses `$plot->semid` — for a term-mode plot
(whole-year, converted via P3), `semid` is NULL. No explicit term-mode
detection is needed in `bulkPick()` itself because the plot already carries
the correct `semid` value.

### Change 3 — Blade: student-table checkboxes

**File:** `resources/views/registrar/shs/subjectpicking/index.blade.php`

Add a checkbox column as the first column in the DataTable:

- Header: `<input type="checkbox" id="spSelectAll">` for select-all-on-page.
- Row render: `<input type="checkbox" class="sp-row-check"
  data-studid="..." data-levelid="..." data-levelname="..." data-fullname="...">`
- `drawCallback`: re-check boxes for already-selected students (selections
  persist in a `selectedStuds` JS object keyed by `studid`).

### Change 4 — Blade: bulk bar

**File:** `resources/views/registrar/shs/subjectpicking/index.blade.php`

Above the DataTable, add a bar with:

```html
<div class="d-flex align-items-center mb-2" id="spBulkBar">
    <button type="button" class="btn btn-success btn-sm" id="btnBulkPick" disabled>
        <i class="fas fa-layer-group"></i> Bulk Pick
        <span class="badge badge-light ml-1" id="bulkCount">0</span>
    </button>
    <button type="button" class="btn btn-outline-secondary btn-sm ml-2"
            id="btnClearSelection" style="display:none;">
        <i class="fas fa-times"></i> Clear Selection
    </button>
    <small class="text-muted ml-3">
        Tick students, then <strong>Bulk Pick</strong> to assign one subject to all of them.
    </small>
</div>
```

### Change 5 — Blade: bulk pick modal

**File:** `resources/views/registrar/shs/subjectpicking/index.blade.php`

A second `modal-xl` dialog (`#bulkPickModal`) with:

- Header showing student count and grade level.
- Info alert explaining the skip logic.
- Subject/cluster filter dropdowns (Select2 AJAX, same factory as individual
  pick modal).
- A container (`#bpContainer`) that renders cluster-grouped plot tables —
  identical layout to the individual pick modal but with "Pick for All" buttons
  instead of individual "Pick" buttons.

### Change 6 — JS: selection management

**File:** `resources/views/registrar/shs/subjectpicking/index.blade.php`

```javascript
var selectedStuds = {};

// Row checkbox change
$(document).on('change', '.sp-row-check', function() {
    var studid = $(this).data('studid');
    if (this.checked) {
        selectedStuds[studid] = {
            studid: studid,
            levelid: $(this).data('levelid'),
            levelname: $(this).data('levelname'),
            fullname: $(this).data('fullname'),
        };
    } else {
        delete selectedStuds[studid];
    }
    updateBulkBar();
    syncSelectAll();
});

// Select-all checkbox
$(document).on('change', '#spSelectAll', function() {
    var checked = this.checked;
    $('#spTable tbody .sp-row-check').each(function() {
        $(this).prop('checked', checked);
        var studid = $(this).data('studid');
        if (checked) {
            selectedStuds[studid] = { /* ... */ };
        } else {
            delete selectedStuds[studid];
        }
    });
    updateBulkBar();
});
```

### Change 7 — JS: bulk pick button handler

**File:** `resources/views/registrar/shs/subjectpicking/index.blade.php`

On "Bulk Pick" click:

1. Check all selected students share one `levelid`. If mixed, show a SweetAlert
   warning and return.
2. Open `#bulkPickModal`, populate count and level name.
3. Call `loadBulkPlots()` — requests `GET /shs/subjectpicking/available-plots`
   with the shared level and term params (same endpoint as individual picking).

### Change 8 — JS: `loadBulkPlots()` function

**File:** `resources/views/registrar/shs/subjectpicking/index.blade.php`

```javascript
function loadBulkPlots() {
    var levels = bulkLevelIds();
    if (!levels.length) return;
    $('#bpLoading').show();
    $('#bpEmpty').hide();
    $('#bpContainer').empty();
    $.get(API + '/available-plots', {
        syid:      $('#filter_syid').val(),
        semid:     spIsTermMode() ? '' : ($('#filter_semid').val() || ''),
        termid:    spTermId(),
        levelid:   levels[0],
        clusterid: $('#bpClusterFilter').val() || '',
        subjectid: $('#bpSubjectFilter').val() || '',
    })
    .done(function(res) { /* render cluster tables with "Pick for All" buttons */ })
    .fail(function() { /* show empty state */ });
}
```

The key term-mode detail: `semid` is sent as empty string when `spIsTermMode()`
is true, and `termid` carries the selected term (or empty for whole-year). This
matches the individual pick modal's request shape.

### Change 9 — JS: `.btn-bp-pick` handler (bulk pick POST)

**File:** `resources/views/registrar/shs/subjectpicking/index.blade.php`

```javascript
$(document).on('click', '.btn-bp-pick', function() {
    var $btn = $(this);
    var plotid = $btn.data('plotid');
    var studids = Object.keys(selectedStuds);
    if (!studids.length) return;

    $btn.prop('disabled', true).html('<span class="spinner-border spinner-border-sm"></span>');
    $.post(API + '/bulk-pick', {
        _token: csrf(),
        studids: studids,
        syid: $('#filter_syid').val(),
        clusterplotid: plotid,
    })
    .done(function(res) {
        if (res.success) {
            // SweetAlert with picked count + skipped list
            loadBulkPlots();              // refresh availability
            spTable.ajax.reload(null, false);  // refresh student table
        }
    });
});
```

Note: `semid` is **not** sent in the POST — the controller reads it from the
plot itself (`$plot->semid`), ensuring term-mode plots always produce
NULL-semid pickings.

---

## Dependencies

- **Module 01** — schema (`ibed_term`, `ibed_term_config` tables).
- **Module 05** — `IBEDGradingDefaults::shsConfiguredTerms()` resolver.
- **Module P3** — cluster plotting (whole-year plot conversion).
- **Module P4** — individual subject picking (term-mode detection helpers,
  `getAvailablePlots` endpoint, `applyClusterTermScope`, period-filter swap).

---

## Porting notes / gotchas

1. **Bulk pick reuses `getAvailablePlots`.** The same endpoint serves both the
   individual and bulk pick modals. No separate available-plots endpoint is
   needed — the only difference is the UI (individual shows per-student conflict
   detection; bulk does not, since it picks for many students at once).

2. **`$plot->semid` is the single source of truth.** The `bulkPick` endpoint
   never reads `semid` from the request. It always inherits from the plot. This
   is critical for term-mode correctness — a term-mode plot has `semid = NULL`.

3. **Prerequisite checks are per-student.** Unlike individual pick (which shows
   a "Prereq" badge and disables the button), bulk pick checks prerequisites
   server-side per student and skips failures silently, reporting them in the
   response. This means a bulk pick on a prereq-gated subject will succeed for
   qualified students and skip the rest.

4. **Capacity is checked progressively.** The loop tracks
   `$enrolled + count($insertRows)` against `$plot->room_capacity`, so later
   students in the batch may be skipped as "Full" even if earlier ones fit.

5. **No `studid` is sent to `getAvailablePlots` in bulk mode.** Unlike
   individual pick (which sends `studid` + `sectionid` for per-student conflict
   detection and "already picked" badges), the bulk modal omits these since the
   request covers multiple students. The "already picked" check happens
   server-side during the actual bulk-pick POST.

6. **Selection state lives in JS only.** The `selectedStuds` object persists
   across DataTable page navigations but is lost on full page reload or filter
   change (the `clearSelection()` call on filter change is intentional — the
   student list changes, so old selections may be stale).

7. **Wrap every `ibed_term_config` read with `activeConfigQuery()`.** The
   `shsConfiguredTerms()` resolver already goes through `activeConfigQuery`
   internally, but any direct `ibed_term_config` or `ibed_term` query added
   to the bulk-picking controller must also be wrapped. A bare
   `where('deleted', 0)` read without the guard resurfaces an Inactive
   config — the #1 source of "terms showing where they shouldn't" (Module 05
   invariant).

---

## Verification

1. **Selection mechanics:** Check boxes on page 1, navigate to page 2, come back
   — page 1 boxes should still be checked. "Select All" should toggle only the
   current page. Bulk count badge updates in real time.

2. **Mixed-level guard:** Select students from Grade 11 and Grade 12. Click
   "Bulk Pick". A SweetAlert warning should appear and the modal should not open.

3. **Semester-mode bulk pick:** Select students from a semester-mode level. Open
   the bulk modal, pick a subject. Verify `sh_cluster_subject_picking.semid` is
   the semester id.

4. **Term-mode bulk pick:** Select students from a term-mode level. Open the
   bulk modal — verify available plots are scoped by term (same as individual
   pick modal). Pick a subject. Verify `sh_cluster_subject_picking.semid` is
   NULL.

5. **Skip reporting:** Bulk-pick a subject that some students already have.
   Verify the SweetAlert shows the picked count and lists the skipped students
   with reasons.

6. **Capacity limit:** Pick a subject whose room is nearly full. Select more
   students than remaining slots. Verify the first N fit and the rest are
   skipped as "Full".

7. **Prerequisites:** Bulk-pick a prereq-gated subject for a mix of qualified
   and unqualified students. Verify qualified ones are picked and unqualified
   ones are skipped with "Prerequisites not met".
