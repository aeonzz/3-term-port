# Module P2 — Subject Plot: Term / Whole-Year Plotting (SHS)

The **plotting gate** for SHS term mode. Module 05's `shsHasTermPlotting()` returns
true only when *every* Senior High subject is plotted **whole-year**
(`subject_plot.semid IS NULL`). This module adds, to the existing Subject Plot
screen: a status banner + one-click conversions (**Convert all to Whole Year**,
**Convert to Terms**, and **revert**), the per-plot **term-subset** model
(`subject_plot_term`), and the resolver that reads it. Junior levels need nothing
here — they're inherently whole-year.

This is a **superadmin setup surface** (consumed by Module 05; required before
Module 07 can put SHS classes in term mode). It **augments** the existing Subject
Plot screen — it does not reimplement plotting.

## Goal — what this port must achieve

After this port, an admin can take a Senior High level from the legacy per-semester
plotting to **whole-year term plotting** (the gate `shsHasTermPlotting` needs), decide
**which terms each subject runs in**, and undo it — all from the Subject Plot screen,
with the state accurately surfaced. Concretely, the port delivers:

1. **A status banner** that reads the level's real state — configured terms vs how
   many plots/schedules are still semester-stamped — and only nudges conversion when
   it's actually a term restructuring (a 4-quarter-shaped config is revert-only).
2. **Convert all to Whole Year** — one action flips every `subject_plot` **and**
   `sh_classsched` for the level to whole-year (`semid = NULL`, old value saved in
   `prev_semid`), dedupes duplicate plots, so `shsHasTermPlotting` turns true and the
   level enters term mode everywhere.
3. **Convert to Terms** — set each subject's **term availability**: whole-year, a
   single term (`termid`), or a genuine **subset** like `1T + 3T` (via
   `subject_plot_term`). Idempotent re-save.
4. **Revert** — bulk and per-plot revert restore the saved `prev_semid`, so a mistaken
   conversion is exactly undoable.
5. **A resolver** (`resolvePlotTermNos`) that turns each plot into its term_no set
   (subset rows win → `termid` → whole-year) for every downstream consumer.
6. **Schema safety** — conversions hard-refuse until Module 01's columns/table exist
   (`prev_semid`, nullable `sh_classsched.semid`, `subject_plot_term`); nothing runs
   half-wired.
7. **No junior-level impact** — only SHS levels 14/15 are touched.

**Acceptance criteria (all must hold):**

- [ ] Selecting a term-configured, semester-plotted SHS level shows the banner
      (`termstatus` → `isTermPlotted:false`, `semesterPlots > 0`).
- [ ] **Convert all to Whole Year** → every `subject_plot.semid` and matching
      `sh_classsched.semid` is `NULL`; `isTermPlotted:true`; banner clears.
- [ ] **Convert to Terms** with a subset (e.g. 1T + 3T) → that plot has `termid = NULL`
      and one `subject_plot_term` row per selected term; a single pick sets `termid`; a
      full pick stays whole-year (no rows).
- [ ] `resolvePlotTermNos` returns: all terms (whole-year), `[term_no]` (single), the
      subset (rows).
- [ ] **Revert** restores `prev_semid` and clears the subset.
- [ ] A **4-quarter-shaped** config offers **revert-only** (no convert nudge).
- [ ] Junior levels are unaffected; conversions refuse if the schema isn't migrated.

> **Report back after applying (do this in chat).** When the port is done, post the
> acceptance criteria / changes as a **ticked checklist** so the user sees what landed —
> **✅** applied and verified, **✔️** code applied but runtime/live-page test still
> pending, **⬜** skipped or not applicable (say why). Never mark ✅ something you didn't
> apply; prefer ✔️ when you only lint/compile-verified. List the changes too, e.g.:
>
> - ✅ Routes (termstatus / convert-wholeyear / convert-terms / revert)
> - ✅ `SubjectPlotController` methods (bulkTermStatus, bulkConvertToWholeYear, bulkConvertTerms, revert)
> - ✅ `IBEDGradingDefaults::resolvePlotTermNos` + `hasPlotTermTable`
> - ✅ Subject Plot banner UI · ⬜ cluster variant (if not needed)

## Behaviors by level / config state

The banner (`bulkTermStatus`) and the resolvers drive everything, so the same code
gives the right result per state. ("Whole-year plotted" = every `subject_plot` row
for the level has `semid IS NULL`.)

| Level / config state | `bulkTermStatus` banner | `shsHasTermPlotting` | Result |
|----------------------|-------------------------|:--------------------:|--------|
| **Non-SHS (junior/elem)** | `{applicable:false}` | n/a | Nothing to do — junior levels are inherently whole-year |
| **SHS, no term config** | `{applicable:false}` | — | Plain semester plotting; no banner |
| **SHS, genuine term config (3T), semester-plotted** | warning: *"configured for 3 terms but X still semester"* + **Convert** | false | Not term mode yet → **Convert all to Whole Year** (or Convert to Terms) |
| **SHS, genuine term config (3T), whole-year plotted** | nothing to convert (already whole-year) | **true** | Term mode active; level shows Term-Based everywhere |
| **SHS, 4-quarter-shaped config, semester-plotted** | **revert-only** (a 4-term config isn't a genuine restructuring) | false | No "Convert" nudge; the level stays on quarters/semesters as intended |
| **SHS, 4-quarter-shaped config, whole-year plotted** | revert-only (still no convert nudge) | true | `resolveShsPeriods` **does** treat it as term mode (4 periods) even though the Subject Plot banner won't push it — see note |
| **Partial / half-converted** (some plots whole-year, some semester) | banner counts both; **Convert** finishes it | false until all `semid` NULL | Convert the stragglers; revert-only surfaces leftover `prev_semid` rows |

### The 4-quarter ("Q4-shaped") config — read this

A config with **4 terms shaped like the standard quarters** (`Q1–Q4`) is often created
just to attach grade-equivalence / score-conversion output settings, not to genuinely
restructure into terms. The two screens intentionally diverge:

- **Subject Plot (`bulkTermStatus`, this module):** special-cases a 4-term config and
  offers **revert only** — it will not nudge you to "Convert all to Whole Year",
  because a 4-quarter shape isn't a term restructuring.
- **Resolvers (`resolveShsPeriods`, Module 05):** do **not** special-case term count —
  so if such a level *is* whole-year plotted, it still resolves as **term mode** (4
  periods), and consumer screens (Section Info, ECR, final grades) render 4 term-labeled
  periods.

Practical guidance: if the intent is plain quarters, **do not whole-year-plot** that
level (leave its subjects semester-plotted), or don't create a 4-term config for it.
Only whole-year-plot a level whose config is a genuine term restructuring.

## Symptoms it fixes

- A SHS level has a 3-term config but classes still grade in quarters, and the
  Subject Plot page shows *"configured for N terms but X class schedule(s) still
  stamped to a semester."*
- No way to plot a subject to a **subset** of terms (e.g. 1T + 3T) — `termid` holds
  only one term.
- After converting, no way to revert a mistaken conversion.
- Switching the **Term** dropdown (Whole year / 1T / 2T / 3T) on the Subject Plot
  table has no visible effect — a semester-stamped straggler appears identically
  under every term choice, because `list()` was never taught to filter on `termid`/
  `term_mode` (Change 7).

## Reference implementation

| Piece | Path / symbol |
|-------|---------------|
| **Source of truth** | `es_ldcu` (this repo). For newer behavior, diff against `../es_bcc`. |
| Subject-plot methods | `app/Http/Controllers/SuperAdminController/SubjectPlotController.php` → `bulkTermStatus`, `bulkConvertToWholeYear`, `bulkConvertTerms`, `bulkRevertToSemester`, `revertPlotToSemester`, and the plot-save rules in `create` / `update` |
| Cluster methods | `app/Http/Controllers/SuperAdminController/SHSClusterPlottingController.php` → `termConversionPreview`, `termConversionConvert` |
| Resolver | `IBEDGradingDefaults::resolvePlotTermNos`, `hasPlotTermTable`, `shsHasTermPlotting`, `shsConfiguredTerms` |
| Views | `resources/views/superadmin/pages/setup/subjectplot.blade.php`, `.../shs-cluster-plotting/index.blade.php` |
| Routes | `routes/web.php` (subject-plot term routes; `cluster-plot/term-conversion/*`) |

## Dependencies

- **Module 01** columns/tables: `subject_plot.termid`, `subject_plot.prev_semid`,
  **`subject_plot_term` table**, `sh_classsched.prev_semid`, **`sh_classsched.semid`
  NULLABLE**, and (clusters) `sh_cluster_plot.termid/prev_semid`,
  `sh_cluster_subject_picking.prev_semid`.
- **Module 05** — `shsConfiguredTerms()` / `shsHasTermPlotting()` drive the banner;
  `resolvePlotTermNos()` reads this module's output.
- Standard tables: `subject_plot`, `sh_classsched`, `sh_strand`, `grades`,
  `gradelevel`, `sh_subjects` (core vs elective `type`), cluster tables.

---

## Files to check & update

| # | File | Symbol / region | Change |
|---|------|-----------------|--------|
| 1 | *(Module 01)* migration | `subject_plot_term` CREATE TABLE | Ensure the table exists (this module needs it) |
| 2 | `routes/web.php` | subject-plot term routes | Add `termstatus`, `convert-wholeyear`, `convert-terms`, `revert-semester`, `{id}/revert-semester` |
| 3 | `SubjectPlotController.php` | `bulkTermStatus`, `bulkConvertToWholeYear`, `bulkConvertTerms`, `bulkRevertToSemester`, `revertPlotToSemester` | Add the methods |
| 4 | `SubjectPlotController.php` | `create` / `update` | Ensure plot-save normalizes `semid`/`termid` (see rules) |
| 5 | `IBEDGradingDefaults.php` | `resolvePlotTermNos`, `hasPlotTermTable` | Add (Module 05) — reads `subject_plot_term` |
| 6 | `subjectplot.blade.php` | banner + Convert / Convert-to-Terms / revert controls | Add the banner UI |
| 6b | `subjectplot.blade.php` | **plot-form Term filter** (`SHS_TERM_CFG`, `#filter_term`) | Swap Semester→Term dropdown for term-configured levels (Change 4b) |
| 7 | `SHSClusterPlottingController.php` | `termConversionPreview/Convert` | Add (cluster variant) |
| 8 | `SubjectPlotController.php` | `list`, `list_ajax` | Add `$termid`/`$termMode` params + filtering (Change 7) — **not just Change 4b's create-time picker** |
| 8b | `subjectplot.blade.php` | `subjectplot_list()` | Send `termid`/`term_mode` so the displayed table actually respects the Term dropdown (Change 7) |

---

## PREFLIGHT — check the repo FIRST (do not skip)

Run before editing. Parts may already be present. Apply **only** what's missing.

```bash
cd <repo-root>
SP=app/Http/Controllers/SuperAdminController/SubjectPlotController.php
GD=app/Support/IBEDGradingDefaults.php
V=resources/views/superadmin/pages/setup/subjectplot.blade.php

# --- subject_plot_term table (Module 01) — schema check (DB): ---
#   SHOW TABLES LIKE 'subject_plot_term';   -- must exist

# --- controller methods (APPLIED if printed): ---
grep -n "function bulkTermStatus"        "$SP"
grep -n "function bulkConvertToWholeYear" "$SP"
grep -n "function bulkConvertTerms"      "$SP"   # the per-plot term-subset conversion
grep -n "function bulkRevertToSemester"  "$SP"
grep -n "function revertPlotToSemester"  "$SP"

# --- plot-form Term filter (blade — Change 4b): ---
grep -n "SHS_TERM_CFG\|term_filter_wrapper\|filter_term" "$V"

# --- resolver (Module 05): ---
grep -n "function resolvePlotTermNos" "$GD"
grep -n "function hasPlotTermTable"   "$GD"

# --- routes: ---
grep -n "plot/convert-wholeyear\|plot/convert-terms\|plot/termstatus" routes/web.php

# --- banner UI in the blade: ---
grep -n "convert-wholeyear\|termstatus\|Convert all to Whole Year" "$V"

# --- list() term-aware filtering (Change 7 — APPLIED if BOTH print): ---
grep -n '\$termMode = 0' "$SP"                          # list() signature param
grep -n "term_mode:" "$V"                                # subjectplot_list() payload
```

**Decision rule:** each symbol that prints is already applied → skip it. If
`subject_plot_term` is missing, do **Module 01** first. If `shsHasTermPlotting` /
`resolveShsPeriods` are missing, do **Module 05** first. Read the enclosing code
around any match before editing; adapt if the surrounding structure has diverged.

> ⚠️ **Table/column names are literal** and SHS-specific: `sh_classsched.glevelid`
> (not `levelid`), `subject_plot.levelid`, `subject_plot.gradessetup`. Cluster setup
> lives on `sh_cluster_plot.gradingsetupid`. Confirm against the target schema.

---

## The per-plot period model (core concept)

A whole-year SHS `subject_plot` row expresses *which terms a subject runs in* via
**four shapes**:

| Shape | `semid` | `termid` | `subject_plot_term` rows | Means |
|-------|:------:|:--------:|:------------------------:|-------|
| **Semester (legacy)** | set | NULL | — | plotted to one semester (pre-term layout) |
| **Whole year** | NULL | NULL | none | runs in **all** active terms |
| **Single term** | NULL | `<term id>` | none | runs in exactly that one term |
| **Term subset** | NULL | NULL | one row per term | runs in exactly those terms (e.g. 1T + 3T) |

`subject_plot.termid` holds a **single** term, so a **multi-term subset** can only
live in `subject_plot_term` (a full selection is stored as whole-year — no rows — so
rows here always mean a genuine subset). **`shsHasTermPlotting` only cares about
`semid`:** a level is term-plotted when every plot has `semid IS NULL`.

---

## Change 2 — Routes

Add alongside the existing subject-plot routes:

```php
Route::get('/superadmin/setup/subject/plot/termstatus', 'SuperAdminController\SubjectPlotController@bulkTermStatus');
Route::post('/superadmin/setup/subject/plot/convert-wholeyear', 'SuperAdminController\SubjectPlotController@bulkConvertToWholeYear');
Route::post('/superadmin/setup/subject/plot/convert-terms', 'SuperAdminController\SubjectPlotController@bulkConvertTerms');
Route::post('/superadmin/setup/subject/plot/revert-semester', 'SuperAdminController\SubjectPlotController@bulkRevertToSemester');
Route::post('/superadmin/setup/subject/plot/{id}/revert-semester', 'SuperAdminController\SubjectPlotController@revertPlotToSemester');

// Cluster variant
Route::get('/cluster-plot/term-conversion/preview', 'SuperAdminController\SHSClusterPlottingController@termConversionPreview');
Route::post('/cluster-plot/term-conversion/convert', 'SuperAdminController\SHSClusterPlottingController@termConversionConvert');
```

---

## Change 4 — Plot-save rules (`create` / `update`)

The plot save must normalize the period so the four shapes stay consistent:

- **`semid` empty → NULL** ("Whole year" in the form's Semester dropdown).
- **`termid` empty → NULL**, and **`termid` is only stored when `semid` is NULL**:
  the insert uses `'termid' => $semid === null ? $termid : null`. A semester-plotted
  row never carries a term.
- **SHS core** (`sh_subjects.type = 1`) may be whole-year with no strand and no
  semester; **electives must have a strand**.
- The duplicate guard accounts for `termid` when `semid` is NULL.

The per-plot **subset** (2+ terms) is produced by **Convert to Terms** below, not the
single-subject form.

## Change 4b — Plot-form **Term filter** for term-configured levels (`SHS_TERM_CFG`)

This is the setup-form filter that makes the single-subject form term-aware: **when
the selected SHS grade level is term-configured, the form swaps its Semester dropdown
for a Term dropdown** (`#filter_term`), so you plot directly to a term (or whole-year).

**PREFLIGHT** (blade — apply only if missing):

```bash
V=resources/views/superadmin/pages/setup/subjectplot.blade.php
grep -n "SHS_TERM_CFG" "$V"            # JS map
grep -n "term_filter_wrapper\|filter_term" "$V"   # the Term dropdown
```

**How it works:**

1. **Config-only term map** (server, `@php`): built from `shsConfiguredTerms()` for
   every `sy.term_grading_status = 1` and SHS level — keyed `[$syid][$levelid] =
   [{id,label}, …]`. **It is config-only on purpose** (NOT gated on whole-year
   plotting): you're *in the middle of plotting*, so the form must offer terms before
   `shsHasTermPlotting` can be true. The runtime gate (`resolveShsPeriods`) still
   requires whole-year plotting downstream.
   ```php
   $shsTermCfg = []; // [syid][levelid] => [{id,label}]
   foreach (DB::table('sy')->where('term_grading_status', 1)->pluck('id') as $termSyId) {
       foreach ([14, 15] as $shsLevelId) {
           $cfg = \App\Support\IBEDGradingDefaults::shsConfiguredTerms($termSyId, $shsLevelId);
           if (!empty($cfg['terms'])) {
               $shsTermCfg[$termSyId][$shsLevelId] = array_map(function ($t) {
                   return ['id' => (int) $t['id'], 'label' => $t['label']];
               }, $cfg['terms']);
           }
       }
   }
   ```
   ```blade
   <div class="col-md-3 form-group mb-0" id="term_filter_wrapper" hidden>
       <label for="">Term</label>
       <select class="form-control select2" id="filter_term"></select>
   </div>
   ```
   ```javascript
   window.SHS_TERM_CFG = @json($shsTermCfg ?? []);
   ```
2. **Reveal on SY/level change:** if `SHS_TERM_CFG[syid][level]` has terms → **term
   mode**: hide the Semester selector, show `#filter_term` populated with a **"Whole
   year"** option + the configured terms. Else → **semester mode**: hide/clear
   `#filter_term`, restore the Semester selector.
   ```javascript
   var cfg = ((window.SHS_TERM_CFG || {})[syid] || {})[lvl];
   if (cfg && cfg.length > 0) {
       $('#filter_semester').val("").change().closest('.form-group').attr('hidden','hidden');
       var $t = $('#filter_term').empty().append('<option value="">Whole year</option>');
       $.each(cfg, function (i, t) { $t.append('<option value="'+t.id+'">'+t.label+'</option>'); });
       $('#term_filter_wrapper').removeAttr('hidden');
   } else {
       $('#term_filter_wrapper').attr('hidden','hidden');
       $('#filter_term').val("").empty();
       $('#filter_semester').closest('.form-group').removeAttr('hidden');
   }
   ```
3. **Plotting in term mode** sends `semid = ''` (→ NULL, whole-year), `termid =
   $('#filter_term').val()` (a term id, or `''` = whole-year), and `term_mode = 1`.
   That lands the **single-term** shape (or whole-year) from Change 4's save rules.

> This filter creates the **whole-year** and **single-term** shapes directly. The
> **subset** shape (1T + 3T) still comes from **Convert to Terms** (`bulkConvertTerms`)
> — a single dropdown can't express a subset. The dropdown's `"Whole year"` value maps
> to `semid = NULL, termid = NULL`; a term value maps to `semid = NULL, termid = <id>`.

---

## Change 3 — Controller methods

### `bulkTermStatus(Request)` — GET `…/plot/termstatus?syid=&levelid=`

Drives the banner. **SHS levels 14/15 only** (else `{applicable:false}`). Reads
`shsConfiguredTerms()`; `{applicable:false}` when no genuine term config. A **4-term**
(quarter-shaped) config returns a **revert-only** payload if leftover converted data
exists, else nothing. Otherwise returns:

```json
{
  "applicable": true, "levelname": "GRADE 11",
  "termCount": 3, "termLabels": ["1T","2T","3T"],
  "semesterPlots": 2, "wholeYearPlots": 9, "revertable": 0,
  "byStrand": { "ABM": 1, "STEM": 1 }, "collisions": 0, "gradeCount": 0,
  "semesterScheds": 2, "wholeYearScheds": 12, "revertableScheds": 0,
  "isTermPlotted": false, "schema_ready": true
}
```

Banner shows the *"configured for N terms but X still semester"* warning when
`semesterPlots`/`semesterScheds > 0` and `isTermPlotted:false`. `schema_ready:false`
= Module 01 columns missing. `gradeCount` surfaces existing grades to weigh
conversion.

### `bulkConvertToWholeYear(Request)` — POST `…/plot/convert-wholeyear`

The headline action — copy verbatim. **SHS-only.** Sets every plot's
`semid = NULL`, `termid = NULL` (old semester → `prev_semid`), matching
`sh_classsched.semid = NULL`, retires duplicate whole-year plots.

```php
public static function bulkConvertToWholeYear(Request $request)
{
    $syid = $request->input('syid');
    $levelid = $request->input('levelid');

    if (empty($syid) || empty($levelid) || !in_array((int) $levelid, [14, 15], true)) {
        return response()->json(['status' => 0, 'message' => 'Senior High grade level and school year are required.'], 422);
    }

    if (!Schema::hasColumn('subject_plot', 'prev_semid') || !Schema::hasColumn('sh_classsched', 'prev_semid')) {
        return response()->json(['status' => 0, 'message' => 'Run the term grading schema migration first.'], 422);
    }

    $semidInfo = DB::table('information_schema.columns')
        ->where('table_schema', DB::getDatabaseName())
        ->where('table_name', 'sh_classsched')
        ->where('column_name', 'semid')
        ->first();

    if (!$semidInfo || strtoupper((string) $semidInfo->IS_NULLABLE) !== 'YES') {
        return response()->json(['status' => 0, 'message' => 'sh_classsched.semid must allow NULL before conversion. Run the schema migration item first.'], 422);
    }

    DB::beginTransaction();
    try {
        $now = \Carbon\Carbon::now('Asia/Manila');
        $uid = auth()->user()->id;

        $plots = DB::table('subject_plot')
            ->where('syid', $syid)->where('levelid', $levelid)->where('deleted', 0)
            ->whereNotNull('semid')->orderBy('id')
            ->get(['id', 'subjid', 'strandid', 'semid']);

        $pendingScheds = DB::table('sh_classsched')
            ->where('syid', $syid)->where('glevelid', $levelid)->where('deleted', 0)
            ->whereNotNull('semid')->count();

        if ($plots->isEmpty() && $pendingScheds === 0) {
            DB::rollBack();
            return response()->json(['status' => 0, 'message' => 'There is nothing to convert; this grade level is already plotted and scheduled for the whole year.']);
        }

        $converted = 0; $merged = 0; $seen = [];

        foreach ($plots as $plot) {
            $key = $plot->subjid . '|' . $plot->strandid;

            if (isset($seen[$key])) {
                DB::table('subject_plot')->where('id', $plot->id)
                    ->update(['deleted' => 1, 'deletedby' => $uid, 'deleteddatettime' => $now]);
                $merged++;
                continue;
            }
            $seen[$key] = true;

            DB::table('subject_plot')->where('id', $plot->id)
                ->update(['prev_semid' => $plot->semid, 'semid' => null, 'termid' => null, 'updatedby' => $uid, 'updateddatetime' => $now]);
            $converted++;
        }

        $scheds = DB::table('sh_classsched')
            ->where('syid', $syid)->where('glevelid', $levelid)->where('deleted', 0)
            ->whereNotNull('semid')->pluck('id');

        $schedConverted = 0;
        if ($scheds->isNotEmpty()) {
            $schedConverted = DB::table('sh_classsched')->whereIn('id', $scheds)
                ->update(['prev_semid' => DB::raw('semid'), 'semid' => null, 'updatedby' => $uid, 'updateddatetime' => $now]);
        }

        $year = DB::table('sy')->where('id', $syid)->value('sydesc');
        $levelname = DB::table('gradelevel')->where('id', $levelid)->value('levelname');

        self::create_logs(auth()->user()->name . ' converted ' . $converted . ' subject plot(s) and '
            . $schedConverted . ' class schedule(s) of ' . $levelname
            . ' to WHOLE YEAR for school year ' . $year . ($merged ? ' (' . $merged . ' duplicate(s) retired)' : ''), null);

        DB::commit();

        $parts = [];
        if ($converted) { $parts[] = $converted . ' subject(s) are now plotted for the whole year'; }
        if ($schedConverted) { $parts[] = $schedConverted . ' class schedule(s) now run the whole year'; }

        return response()->json([
            'status' => 1,
            'converted' => $converted,
            'merged' => $merged,
            'schedconverted' => $schedConverted,
            'message' => implode(' and ', $parts) . ($merged ? ', ' . $merged . ' duplicate plot(s) were retired' : '') . '.',
        ]);
    } catch (\Exception $e) {
        DB::rollBack();
        return response()->json(['status' => 0, 'message' => $e->getMessage()], 500);
    }
}
```

> `self::create_logs(...)` is the reference audit helper; swap/drop for your project.
> The `subject_plot` soft-delete column is `deleteddatettime` (double-t) — match your
> schema.

### `bulkConvertTerms(Request)` — POST `…/plot/convert-terms`

The richer conversion: moves plots off their semester **and** sets each plot's term
availability from a `terms` payload (`{ "<plot_id>": [term_id, …] }`). **SHS-only**;
requires `shsConfiguredTerms()` and **`hasPlotTermTable()`**. Per plot writes one of:

- **selection ≥ all terms** → whole year (`termid = NULL`, no rows).
- **selection == 1 term** → single term (`termid = <term>`, no rows) — `pinned++`.
- **subset (2+, not all)** → `termid = NULL` + one `subject_plot_term` row per term —
  `pinned++`.

Always rewrites the mapping (soft-deletes old rows first) so a re-save is
**idempotent**; a plot absent from the payload keeps its availability; empty
selection = whole year. Retires duplicate semester pairs (`merged`). Also nulls
`sh_classsched.semid` (saving `prev_semid`). Response includes
`converted`/`pinned`/`merged`/`schedconverted`/`isTermPlotted`. Copy verbatim from
`SubjectPlotController@bulkConvertTerms`.

### `bulkRevertToSemester(Request)` — POST `…/plot/revert-semester`

Inverse of convert: for tool-converted rows (`semid IS NULL AND prev_semid IS NOT
NULL`), restore `semid = prev_semid`, clear `prev_semid`; same for `sh_classsched`.
Only touches tool-converted rows. **SHS-only.**

### `revertPlotToSemester($id, Request)` — POST `…/plot/{id}/revert-semester`

Per-subject revert of a single `subject_plot` row (guards `semid IS NULL AND
prev_semid IS NOT NULL`).

### Cluster variant — `termConversionPreview` / `termConversionConvert`

Same idea for **clustered** SHS setups (validated `levelid in [14,15]`): preview
counts, then convert `sh_cluster_plot` / `sh_cluster_subject_picking` to whole-year
via their `prev_semid` columns. Screen: `/setup/subject/shs-cluster-plotting`.

---

## Change 5 — Resolver (`resolvePlotTermNos`, Module 05)

Consumers turn a plot into its term_no set with
`IBEDGradingDefaults::resolvePlotTermNos($plotTermid, $shsPeriods, $plotId)`:

1. Not term mode → `[]`.
2. **`subject_plot_term` has rows for `$plotId`** → exactly those terms' `term_no`s
   (the subset). Foreign ids ignored; if nothing survives, fall through.
3. Else **`termid` set** → `[that term_no]` (single term). Inactive/foreign termid →
   whole-year (defensive).
4. Else (`termid` NULL) → **all** active `term_no`s (whole year).

`hasPlotTermTable()` is a memoized `Schema::hasTable('subject_plot_term')`, so DBs
without the table fall back to the `termid`-only logic (no fatal).

---

## Change 6 — Banner UI

On level select, GET `…/plot/termstatus`. When `applicable && !isTermPlotted &&
semesterPlots+semesterScheds > 0`, render the warning bar:

> *"GRADE 11 is configured for 3 terms (1T / 2T / 3T), but 2 class schedule(s) are
> still stamped to a semester…"* + **[Convert all to Whole Year]** and, when the
> `subject_plot_term` table exists, **[Convert to Terms]** (per-plot term checkboxes
> → POST `convert-terms`). When `revertOnly`/`revertable > 0`, offer revert. The
> single-subject form's **Semester** dropdown carries a **"Whole year"** option
> (value `""` → `semid NULL`).

Copy the bar + handlers from the reference blade; adapt layout/toast helpers.

## Change 7 — `list()` term-aware filtering (the displayed table, not just the create form)

**This is easy to miss because it was never captured here until 2026-09-03 — see the
Changelog.** Change 4b makes the plot **form** term-aware (you can plot directly to a
term when creating a subject), but on its own that's cosmetic for the **displayed
table**: without this change, switching the Term dropdown (`#filter_term`) between
"Whole year" / 1T / 2T / 3T does **nothing** — the table keeps showing every plot for
the level regardless of `semid`, including legacy semester-stamped stragglers (e.g. a
non-core subject plotted while the config was still inactive). That's misleading: a
subject sitting at a real `semid` can appear to "already be whole-year" simply because
nothing is filtering it out.

**Root cause:** `subjectplot_list()` (the AJAX call that populates the table) only
ever sends `semid: $('#filter_semester').val()` — and `#filter_semester` is hidden and
forced to `""` in term mode (see Change 4b step 2). In PHP, `'' != null` is `false`, so
`SubjectPlotController::list()`'s existing `if ($semid != null) { ... }` guard is
skipped entirely whenever term mode is on — no filter is applied at all, term or
otherwise. `termid`/`term_mode` are never sent because `list()` doesn't accept them.

**Fix — `list()` gains two params and filters on them** (signature order matters; the
two new params are the last positional ones so existing callers stay unaffected if
they don't pass them):

```php
public static function list(
    $id = null, $subjid = null, $levelid = null, $sort = null, $syid = null,
    $semid = null, $strandid = null, $subjlist = array(), $issp = false,
    $acadprog = null, $termid = null, $termMode = 0
) {
    $termid = ($termid === '' || $termid === null) ? null : $termid;
    $termMode = (int) $termMode === 1;
    // ...existing $subjectplot query builder...

    if ($termMode && ($levelid == 14 || $levelid == 15 || $acadprog == 5)) {
        $subjectplot = $subjectplot->whereNull('subject_plot.semid');
    }
    if ($termid != null && ($levelid == 14 || $levelid == 15 || $acadprog == 5)) {
        // A multi-term subject (subject_plot_term rows) carries termid NULL, same as a
        // genuinely whole-year plot, so a plain "termid IS NULL" test would match it in
        // EVERY term. Mirrors resolvePlotTermNos()'s precedence.
        $hasTermTable = \App\Support\IBEDGradingDefaults::hasPlotTermTable();

        $subjectplot = $subjectplot->where(function ($q) use ($termid, $hasTermTable) {
            $q->where('subject_plot.termid', $termid); // pinned to this term

            if ($hasTermTable) {
                $q->orWhereExists(function ($sub) use ($termid) {
                    $sub->select(DB::raw(1))->from('subject_plot_term')
                        ->whereColumn('subject_plot_term.plot_id', 'subject_plot.id')
                        ->where('subject_plot_term.term_id', $termid)
                        ->where('subject_plot_term.deleted', 0);
                }); // listed for this term in the multi-term mapping
                $q->orWhere(function ($q2) {
                    $q2->whereNull('subject_plot.termid')
                        ->whereNotExists(function ($sub) {
                            $sub->select(DB::raw(1))->from('subject_plot_term')
                                ->whereColumn('subject_plot_term.plot_id', 'subject_plot.id')
                                ->where('subject_plot_term.deleted', 0);
                        });
                }); // genuinely whole-year: no pin and no mapping at all
            } else {
                $q->orWhereNull('subject_plot.termid');
            }
        });
    }
    // ...rest of list() unchanged...
}
```

`list_ajax()` must forward the two new request params in the same order:

```php
$termid = $request->get('termid');
$termMode = $request->get('term_mode');
// ...
return self::list($id, $subjid, $levelid, $sort, $syid, $semid, $strandid, array(), $issp, $acadprog, $termid, $termMode);
```

And `subjectplot_list()` (the blade JS) must send both, plus `term_mode` computed the
same way the reveal logic in Change 4b does:

```javascript
data: {
    syid: $('#filter_sy').val(),
    levelid: $('#filter_gradelevel').val(),
    semid: $('#filter_semester').val(),
    termid: $('#filter_term').val(),
    term_mode: $('#term_filter_wrapper').is(':hidden') ? 0 : 1,
    strandid: $('#filter_strand').val(),
    issp: true
},
```

> ⚠️ `list()` is also called internally by `create()`/`update()`/`copy_to()` to return
> the refreshed table after a save — those call sites don't need to pass the new
> params (they default to `null`/`0`, i.e. no term filtering), matching pre-change
> behavior. Only `list_ajax()` (driven by the visible Term dropdown) needs to forward
> them.

## Grading-setup link (drives Module 07)

`subject_plot.gradessetup` → `subject_gradessetup` (`components_json`) is what makes
a plotted class component-based (dynamic ECR). A plot pointing at a setup with a
non-empty `components_json` (in `component_scores` mode) is what flips
`hasIbedComponents()` true in Module 07 — plotting and the ECR path are linked here.

---

## Porting notes / gotchas

1. **SHS-only (levels 14/15).** Every bulk method rejects other levels. Junior levels
   don't plot per-semester, so never need conversion.
2. **Schema hard-gates.** `bulkConvertToWholeYear` refuses unless `prev_semid` exists
   and `sh_classsched.semid` is nullable; `bulkConvertTerms` refuses unless
   `subject_plot_term` exists (`hasPlotTermTable`).
3. **`termid` only when whole-year.** On save, `termid` is forced NULL whenever `semid`
   is set.
4. **Subset ⇒ rows; full/single ⇒ no rows.** Preserve so `resolvePlotTermNos` reads
   correctly.
5. **`prev_semid` is the undo trail** — convert saves it, revert reads it back and
   clears it. Don't repurpose.
6. **Dedup on convert** — duplicate semester rows of the same subject/strand collapse
   to one whole-year plot (`merged++`).
7. **4-quarter configs excluded** from the convert nudge — only revert-only surfaces.
8. ⚠️ **Existing grades.** Converting re-scopes classes from a semester to whole-year.
   Confirm no stranded semester grades first (`gradeCount` surfaces this; see
   `THREE_TERM_CONVERSION_GUIDE.md §5b`).
9. **`create_logs` / `deleteddatettime`** are reference-specific — adapt.

10b. **Change 4b (create-form term picker) is not Change 7 (list filtering).** Porting
    only Change 4b leaves the displayed subject table unfiltered by term — it looks
    like nothing is wrong (the form works, plots save correctly) until a semester-
    stamped row shows up under every Term choice indiscriminately. Port both.

10. **Wrap every `ibed_term_config` read with `activeConfigQuery()`.** The
    `shsConfiguredTerms()` resolver already goes through `activeConfigQuery`
    internally, but any direct `ibed_term_config` or `ibed_term` query added
    to the subject-plot controller must also be wrapped. A bare
    `where('deleted', 0)` read without the guard resurfaces an Inactive
    config — the #1 source of "terms showing where they shouldn't" (Module 05
    invariant).

---

## Verification

1. With a SHS 3-term config active (Modules 02–05) and subjects still semester-plotted,
   open `/setup/subject/plot`, select the SHS level → the *"configured for N terms but
   X still semester"* banner shows; `…/plot/termstatus` returns `isTermPlotted:false`,
   `semesterPlots > 0`.
2. **Convert all to Whole Year** → banner clears; re-fetch shows `semesterPlots:0`,
   `isTermPlotted:true`. Every plot's `semid` is NULL.
3. **Convert to Terms** with a subset (e.g. 1T + 3T) → that plot has `termid = NULL`
   and two `subject_plot_term` rows; a single pick sets `termid`; a full pick stays
   whole-year.
4. DB check:
   ```sql
   SELECT id, semid, prev_semid, termid FROM subject_plot WHERE syid=? AND levelid=14 AND deleted=0;  -- semid all NULL
   SELECT plot_id, term_id FROM subject_plot_term WHERE deleted=0;                                    -- subset rows
   SELECT semid, prev_semid, COUNT(*) FROM sh_classsched WHERE syid=? AND glevelid=14 AND deleted=0 GROUP BY semid, prev_semid;
   ```
5. `resolvePlotTermNos(termid, resolveShsPeriods($syid,14), plotId)` returns all terms
   for whole-year, `[term_no]` for single, the subset for a `subject_plot_term` plot.
6. `resolveShsPeriods($syid, 14)` now returns `isTermMode:true` — the level flips to
   **Term-Based** on `/classschedule` and shows term columns in Final Grading.
7. **Revert** restores the semesters, clears `prev_semid`, and the subset no longer
   applies.
8. **Change 7 — list filtering.** With one plot still semester-stamped (`semid` set)
   and the rest whole-year, select the level and switch **Term** to "Whole year" →
   the semester-stamped plot must **not** appear. Switch to a specific term (e.g. 1T)
   → only plots whole-year, pinned to that term, or in a `subject_plot_term` subset
   including it should appear. `curl` the endpoint directly to confirm:
   `…/plot/list?syid=&levelid=14&termid=&term_mode=1` (whole year) vs
   `…/plot/list?syid=&levelid=14&termid=<id>&term_mode=1` (one term) should return
   different subject sets whenever a semester straggler or single-term pin exists.

With SHS levels term-plotted, proceed to **Module 07 — Teacher ECR**.

---

## Changelog

### 2026-09-03 — Missing `Schema` facade import broke the whole-year status banner

`SubjectPlotController.php` never imported `Illuminate\Support\Facades\Schema`. Since
the controller lives in the `App\Http\Controllers\SuperAdminController` namespace,
every bare `Schema::hasColumn(...)` call (5 call sites: `bulkTermStatus`,
`bulkConvertToWholeYear`, `bulkRevertToSemester`, `revertPlotToSemester`) resolved to
the non-existent `App\Http\Controllers\SuperAdminController\Schema` and threw a fatal
"class not found" error — a 500 on every `…/plot/termstatus` request. The status
banner (Change 6) and its Convert/Revert actions were silently non-functional; the
port looked complete (every symbol a PREFLIGHT grep checks for was present) but
nothing in this module actually ran. es_ldcu's copy of this file has always had the
import; this was a port-time omission, not a source-repo bug.

**Fix:** add `use Illuminate\Support\Facades\Schema;` to the file's `use` block.

**Lesson for future ports:** a PREFLIGHT/audit grep that checks "does the function
exist" cannot catch a missing import — that only fails at runtime. Actually call the
endpoint (or load the page) before marking this module verified; `php -l` doesn't
catch it either (it's a valid-syntax fatal, not a parse error).

**Files touched:**

| File | Change |
|------|--------|
| `SubjectPlotController.php` | Added `use Illuminate\Support\Facades\Schema;` to the `use` block |

### 2026-09-03 — `list()` never learned to filter by term (Change 7, new)

Change 4b (the create-form Term picker) was documented and ported, but the
**displayed subject table** was never made term-aware — that gap wasn't written up
anywhere in this module, in either this repo's or es_ldcu's copy of this doc, even
though es_ldcu's actual codebase has had the fix since commit `cffc9d020` ("feat: shs
three-term grading, plotting, and promotion flow", 2026-07-24). Switching the Term
dropdown had no effect on the table: `subjectplot_list()` only ever sent
`semid: $('#filter_semester').val()`, which is forced to `""` in term mode, and PHP's
`'' != null` is `false` — so `SubjectPlotController::list()`'s semid filter silently
no-opped, returning every plot for the level regardless of its real `semid`. A
semester-stamped straggler (e.g. a non-core subject plotted while the level's term
config was momentarily inactive) would appear identically under "Whole year" and every
term, looking indistinguishable from a genuinely whole-year plot.

**Fix:** added `$termid`/`$termMode` params to `list()` with the filtering logic
ported from es_ldcu (term mode → `whereNull('semid')`; a specific term → pinned
`termid` match, `subject_plot_term` subset match, or genuinely-whole-year fallback),
forwarded them through `list_ajax()`, and updated `subjectplot_list()` to send
`termid`/`term_mode`. See **Change 7** above for the full diff.

**Files touched:**

| File | Change |
|------|--------|
| `SubjectPlotController.php` | `list()` gained `$termid`/`$termMode` params + filtering; `list_ajax()` forwards `termid`/`term_mode` |
| `subjectplot.blade.php` | `subjectplot_list()` now sends `termid: $('#filter_term').val()` and `term_mode: $('#term_filter_wrapper').is(':hidden') ? 0 : 1` |
