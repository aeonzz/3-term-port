# Module P1 — Principal Section Info (term-aware schedules)

Make the **Principal → Section Information** page (`/principalPortalSectionProfile/{id}`)
term-aware for SHS: schedules stay **whole-year** (`sh_classsched.semid = NULL`), the
period dropdown is **config-driven** (not a hardcoded "Term 1/2/3"), and the schedule
grid shows those whole-year schedules instead of an empty grid.

This is a **portal-surface** module (not one of the core 01–10 layers). It consumes
the resolvers from **Module 05** and the whole-year plotting from **Module P2**.

## Goal — what this port must achieve

After this port, the **Principal → Section Information** page behaves correctly for
**every** grade level — term-mode SHS, plain-semester SHS, and JHS — with the
section's schedules and grade periods driven by the term configuration instead of a
hardcoded list. Concretely, the port delivers these features:

1. **Whole-year schedules for term-mode SHS.** Adding a class schedule on a
   term-plotted SHS section stores `sh_classsched.semid = NULL` (whole-year), so the
   schedule follows the plots. It never writes a term number or the phantom
   `semid = 3` into the schedule. → *the "X class schedule(s) still stamped to a
   semester" banner on Subject Plot does not reappear after adding a schedule.*
2. **Schedules stay visible.** The Class Schedule grid (both Format 1 and Format 2)
   shows a term-mode section's whole-year schedules — never an empty grid caused by a
   `semid` filter that matches nothing.
3. **Config-driven period dropdown.** The **Term / Semester** dropdown is built from
   the resolver, per school year:
   - term-mode level → the **configured terms** (e.g. `1T / 2T / 3T`), label **"Term"**;
   - non-term / plain-semester level → the **real semesters**, label **"Semester"**;
   - and **never** offers a value (like `semid = 3`) that matches no record.
4. **Half-migrated explanation.** When a term config *applies* to the level but its
   subjects aren't whole-year-plotted yet, the page stays on semesters **and** shows a
   note explaining why (so "Semester" doesn't look like the config was ignored), with
   guidance to re-plot the subjects whole-year.
5. **Correct duplicate / conflict detection in term mode.** With `semid = NULL`, the
   add-schedule conflict and duplicate checks still work (they use the NULL-safe `<=>`
   operator instead of `= NULL`, which never matches in MySQL).
6. **No regression for non-term surfaces.** JHS sections, plain-semester SHS sections,
   and teacher/room schedule views keep their original semester behavior unchanged.
7. **(Optional, if the status table is ported) Grade Status in terms.** The Grade
   Status period columns relabel to the configured terms; without that table markup
   the relabel safely no-ops and the legacy Quarter 1–4 layout is kept.

**Acceptance criteria (all must hold):**

- [ ] Add a schedule on a term-mode SHS section → DB row has `sh_classsched.semid = NULL`.
- [ ] Format 1 **and** Format 2 show that section's schedules (not empty).
- [ ] Dropdown shows configured terms + "Term" label for a term-mode SHS level.
- [ ] Dropdown shows real semesters + "Semester" label for a JHS / non-term level.
- [ ] A config-applies-but-not-plotted level shows the warning note and stays on semesters.
- [ ] Subject Plot's "still stamped to a semester" banner does **not** reappear after an add.
- [ ] Plain-semester and teacher/room views are unchanged (regression check).

> **Report back after applying (do this in chat).** When the port is done, post the
> acceptance criteria as a **ticked checklist** so the user sees exactly what landed —
> use ✅ for each item you applied/verified, ✔️ (code applied, runtime test still
> pending) when you edited the code but couldn't click through the live page, and ⬜
> for anything skipped or not applicable (say why). Also list the three changes with
> their state, e.g.:
>
> - ✅ Change 1 — `get_schedule_2` read guard
> - ✅ Change 2 — `sh_insert_sched` normalize + NULL-safe checks
> - ✅ Change 3 — `sectioninfo.blade.php` dropdown/note/JS
>
> Never mark an item ✅ you didn't actually apply. Prefer ✔️ over ✅ when you only
> lint/compile-verified and the behavior wasn't exercised at runtime.

## Behaviors by level / config state

The page's behavior is driven entirely by the resolver, so the same code produces
the right result for each state below. "Term mode" for SHS = `resolveShsPeriods`
returns `isTermMode` (a term config applies **and** every subject is whole-year
plotted, `shsHasTermPlotting`).

| Level / config state | Dropdown | Add-schedule stores `semid` | Schedule grid (section view) | Note shown? |
|----------------------|----------|-----------------------------|------------------------------|-------------|
| **No term config** (plain SHS/JHS) | real **semesters**, label "Semester" | the posted semester id (unchanged) | filtered by semester (legacy) | no |
| **SHS + genuine term config (e.g. 3T), NOT whole-year plotted** (half-migrated) | real **semesters**, label "Semester" | posted semester id (**not** normalized — `shsHasTermPlotting` is false) | filtered by semester | **yes** — *"configured for 3 terms (1T/2T/3T), but its subjects are still plotted per semester… re-plot whole-year to switch to terms"* |
| **SHS + genuine term config (3T), whole-year plotted** (term mode) | the **configured terms** (1T/2T/3T), label "Term" | **NULL** (whole-year) | filter **skipped** → whole-year schedules show | no |
| **SHS + term config shaped as 4 quarters (Q1–Q4), NOT whole-year plotted** | real **semesters**, label "Semester" | posted semester id | filtered by semester | **yes** — *"configured for 4 terms (Q1/Q2/Q3/Q4), but its subjects are still plotted per semester…"* |
| **SHS + term config shaped as 4 quarters (Q1–Q4), whole-year plotted** | **4** period options labelled from the config (Q1–Q4), label "Term" | **NULL** (whole-year) | filter **skipped** → schedules show | no |
| **JHS + term config** (JHS can be term-graded) | terms from `resolveTermLabelsForLevel`, label "Term" | *(JHS uses the `gshs/add` path, not `sh_insert_sched`; SHS-only normalization does not apply)* | JHS schedules via `classsched`, unaffected by the SHS `semid` guard | only for SHS |

### The 4-quarter ("Q4-shaped") config — read this

A term config can be created with **4 terms shaped like the standard quarters**
(`Q1/Q2/Q3/Q4`) — often just to attach grade-equivalence / score-conversion output
settings, **not** to genuinely restructure into terms. Two things follow, and they
are intentionally different between screens:

- **On this page (Section Info):** `resolveShsPeriods` does **not** special-case a
  4-term config, so if that level is whole-year plotted it **is** term mode — the
  dropdown shows the 4 config-labelled periods ("Term"), and add-schedule stores
  `semid = NULL`. If it is **not** whole-year plotted, the page stays on semesters and
  shows the note (calling them "4 terms").
- **On Subject Plot (Module P2):** `bulkTermStatus` **does** special-case a 4-term
  config — it treats it as "not a genuine term restructuring" and offers **revert
  only** (no "Convert all to Whole Year" nudge).

So a Q4-shaped config that is *already* whole-year plotted renders as a 4-period term
layout here, while Subject Plot won't push you to convert it. That divergence is by
design; just be aware the dropdown will read "Term" with four Q-labels in that case.
If the intent was plain quarters, either don't whole-year-plot that level, or don't
create a 4-term config for it (leave those levels on the usual semester layout).

## Symptoms it fixes

- Adding a schedule on a term-mode SHS section stamps a bogus `semid` (e.g. `3` for
  "Term 3"), so the schedule drifts out of sync with the whole-year plots and
  re-triggers the *"X class schedule(s) still stamped to a semester"* banner.
- Viewing schedules in **Format 2** shows an **empty grid** (whole-year `semid NULL`
  rows don't match the `semid = 3` filter).
- The period dropdown is a hardcoded "Term 1 / Term 2 / Term 3" that sends `semid =
  1/2/3` — wrong for non-term levels (they should show real semesters) and sends a
  value (`3`) that matches no real semester.

## Reference implementation

| Piece | Path |
|-------|------|
| **Source of truth** | `../es_bcc` — copy the behavior from here |
| Controller | `app/Http/Controllers/PrincipalControllers/ScheduleController.php` → `get_schedule_2`, `sh_insert_sched` |
| View | `resources/views/principalsportal/pages/section/sectioninfo.blade.php` |
| Resolvers used | `App\Support\IBEDGradingDefaults::shsHasTermPlotting`, `resolveShsPeriods`, `resolveTermLabelsForLevel`, `resolveConfigForLevel` (Module 05) |

## Dependencies

- **Module 01** schema (esp. `sh_classsched.semid` NULLABLE, `subject_plot.semid`,
  `ibed_term_config` / `ibed_term`).
- **Module 05** resolver Support classes present.
- **Module P2** whole-year plotting available (`shsHasTermPlotting` returns true only
  when every SHS plot is whole-year).

---

## Files to check & update

| # | File | Method / region | Change |
|---|------|-----------------|--------|
| 1 | `ScheduleController.php` | `get_schedule_2` (semid filter) | Skip the `semid` filter in term mode (read guard) |
| 2 | `ScheduleController.php` | `sh_insert_sched` (setup + dup/conflict checks) | Normalize `semid → NULL` for term-plotted SHS + make the in-method `semid` comparisons NULL-safe (`<=>`) |
| 3 | `sectioninfo.blade.php` | `@php` block, dropdown markup, ready-block JS | Config-driven `SEC_TERM_MAP` dropdown + note + period-filter JS |

---

## PREFLIGHT — check the repo FIRST (do not skip)

Run these **before editing**. This module may be **partly or fully applied already**
(es_ldcu had the `$schoolyear`/`$semester` block but not the rest). For each change,
run its detector and **apply only what's missing** — never double-apply.

```bash
cd <repo-root>
F=app/Http/Controllers/PrincipalControllers/ScheduleController.php
V=resources/views/principalsportal/pages/section/sectioninfo.blade.php

# --- Change 1: read guard in get_schedule_2 ---
# APPLIED if this prints a line; MISSING if empty:
grep -n "shsHasTermPlotting(\$syid, \$levelid->levelid)" "$F"

# --- Change 2: write normalization + NULL-safe checks in sh_insert_sched ---
# APPLIED if BOTH print; MISSING if either is empty:
grep -n "\$semidMatch = function" "$F"
grep -n "shsHasTermPlotting(\$syid, \$levelid)" "$F"   # the 14/15 normalization (also matches Format-1 guard; see note)

# --- Change 3: config-driven dropdown JS in the blade ---
# APPLIED if these print; MISSING if empty:
grep -n "SEC_TERM_MAP" "$V"
grep -n "applySectionPeriodFilter" "$V"
grep -n 'id="filter_semester_label"' "$V"
```

Also confirm the prerequisites exist before touching anything:

```bash
# resolvers present (Module 05):
grep -rn "function shsHasTermPlotting" app/Support/IBEDGradingDefaults.php
# schema: sh_classsched.semid must allow NULL (Module 01) — check in DB, not code.
```

**Decision rule:** if a change's detector shows it's already applied, **skip that
change**. If prerequisites are missing, stop and do Modules 01/05/06 first. Read the
enclosing method around any match before editing — the surrounding code must look
like the "before" below; if it has diverged, adapt rather than blind-replace.

> ⚠️ **Never** convert the `->where('semid', $semid)` occurrences that live in
> **other** methods (there are several elsewhere in `ScheduleController.php`). Change 2
> touches **only** the comparisons inside `sh_insert_sched`. Confirm line numbers are
> within that method before editing (see the range-scoped approach below).

---

## Change 1 — `get_schedule_2` read guard

**Before:**
```php
        $sched_sh = $sched_sh->where('sh_classsched.syid', $syid);

        if ($semid != '' && $semid != null) {
            $sched_sh = $sched_sh->where('sh_classsched.semid', $semid);

        }
```

**After:**
```php
        $sched_sh = $sched_sh->where('sh_classsched.syid', $syid);

        // In SHS term mode classes run the whole year (semid NULL), but the section
        // profile posts the chosen TERM as semid (3T => 3) — nothing is stored under
        // that value, so filtering by it empties the Format 2 grid. Skip the semester
        // filter for a section view of a term-plotted SHS level; teacher/room views and
        // levels that are not term-plotted keep the original filter.
        $shsTermMode = false;
        if ($schedtype == 'section' && isset($levelid->levelid)) {
            $shsTermMode = \App\Support\IBEDGradingDefaults::shsHasTermPlotting($syid, $levelid->levelid);
        }

        if ($semid != '' && $semid != null && !$shsTermMode) {
            $sched_sh = $sched_sh->where('sh_classsched.semid', $semid);
        }
```

> In `get_schedule_2`, `$levelid` is the `sections` row
> (`DB::table('sections')->where('id',$sectionid)->first()`), so `$levelid->levelid`
> is the grade level. Confirm that holds in the target before applying.

> **Format 1 (`get_schedule`) note:** the same rule is already applied there in both
> es_ldcu and es_bcc via `&& shsHasTermPlotting($syid, $levelid)`. If your target
> lacks it in `get_schedule`, port it too; otherwise leave it.

---

## Change 2 — `sh_insert_sched` write normalization + NULL-safe checks

**2a. Insert the normalization + closure** right after `$conflict_list = array();`
and before `if ($allowconflict == 0) {`:

```php
        $conflict_list = array();

        // The page posts whatever the Semester filter happens to show. Once a level's
        // curriculum has been migrated to whole-year plotting, its schedules must follow the
        // plots (semid NULL) or the subject plot screen reports the two as out of sync.
        // shsHasTermPlotting() is true only when every plot for the level is already
        // whole-year, so a half-migrated level keeps its semester. The 14/15 check matters
        // because that helper is data-driven (JHS plots are naturally semid NULL too).
        if (
            ($levelid == 14 || $levelid == 15)
            && \App\Support\IBEDGradingDefaults::shsHasTermPlotting($syid, $levelid)
        ) {
            $semid = null;
        }
        // From here on $semid may legitimately be NULL, so every comparison below uses the
        // NULL-safe operator <=>. A plain `semid = NULL` is never true in MySQL, which would
        // silently disable the conflict and duplicate checks instead of matching whole-year rows.
        $semidMatch = function ($query, $column = 'semid') use ($semid) {
            return $query->whereRaw($column . ' <=> ?', [$semid]);
        };

        if ($allowconflict == 0) {
```

> In `sh_insert_sched`, `$levelid` is a **scalar** grade-level id
> (`DB::table('sections')->…->select('levelid')->first()->levelid`) — that's why the
> check reads `$levelid == 14 || $levelid == 15` (no `->levelid`).

**2b. Make the in-method `semid` comparisons NULL-safe.** Every
`->where('semid', $semid)` and `->where('sh_classsched.semid', $semid)` **inside
`sh_insert_sched`** must switch to the closure / NULL-safe form:

- `->where('semid', $semid)` → `->where($semidMatch)`
- `->where('sh_classsched.semid', $semid)` → `->whereRaw('sh_classsched.semid <=> ?', [$semid])`

**Safe way to apply (restricted to the method's line range) — do NOT `replace_all`
across the file**, because identical `->where('semid', $semid)` calls exist in other
methods. First find the method's line span, then scope the substitution to it:

```bash
F=app/Http/Controllers/PrincipalControllers/ScheduleController.php
START=$(grep -n "function sh_insert_sched" "$F" | head -1 | cut -d: -f1)
# next 'public function' after START = method end
END=$(awk -v s="$START" 'NR>s && /public (static )?function/{print NR; exit}' "$F")
echo "sh_insert_sched spans $START..$END"

# DRY RUN — review the lines that WILL change (must all be inside $START..$END):
grep -nF -e "->where('semid', \$semid)" -e "->where('sh_classsched.semid', \$semid)" "$F" \
  | awk -F: -v s="$START" -v e="$END" '$1>=s && $1<=e'

# APPLY (range-scoped):
sed -i "${START},${END} s/->where('semid', \$semid)/->where(\$semidMatch)/g" "$F"
sed -i "${START},${END} s/->where('sh_classsched.semid', \$semid)/->whereRaw('sh_classsched.semid <=> ?', [\$semid])/g" "$F"

# VERIFY the OUT-OF-RANGE occurrences were left untouched:
grep -nF -e "->where('semid', \$semid)" "$F"
```

In es_ldcu there are **5** such sites inside `sh_insert_sched` (four `->where('semid',
$semid)` conflict/dup checks + one `->where('sh_classsched.semid', $semid)`), and
**4** `->where('semid', $semid)` in a different method that must stay as-is.

**Lint after:** `php -l app/Http/Controllers/PrincipalControllers/ScheduleController.php`

---

## Change 3 — `sectioninfo.blade.php` (config-driven dropdown)

Three edits. If the `$schoolyear`/`$semester` `@php` block already exists (it did in
es_ldcu), extend it rather than adding a second block.

**3a. Extend the `@php` block** (the one that defines `$schoolyear` + `$semester`)
with the term-map builder:

```php
        // #filter_semester is submitted to the server as **semid**. Build the term options for
        // each school year in which THIS section's grade level is genuinely in term mode; every
        // other year falls back to the real semesters above. When a term config DOES apply but
        // the subjects are still plotted per semester, term mode cannot be used, so we keep the
        // semesters and explain why via $secTermNote.
        $secLevelId = $sectionInfo->levelid ?? null;
        $secAcadprogId = $sectionInfo->acadprogid ?? null;
        $secLevelName = $sectionInfo->levelname ?? 'This grade level';
        $secTermMap = []; // syid => [{term_no,label}]
        $secTermNote = []; // syid => explanation shown under the dropdown
        if (!empty($secLevelId)) {
            foreach ($schoolyear as $secSy) {
                if ((int) $secAcadprogId === 5) {
                    $secPeriods = \App\Support\IBEDGradingDefaults::resolveShsPeriods($secSy->id, $secLevelId);
                    $secIsTerm = !empty($secPeriods['isTermMode']);
                } else {
                    $secPeriods = \App\Support\IBEDGradingDefaults::resolveTermLabelsForLevel($secSy->id, $secLevelId);
                    $secIsTerm = !empty($secPeriods['isTermGrading']);
                }

                if ($secIsTerm && !empty($secPeriods['terms'])) {
                    $secTerms = [];
                    foreach ($secPeriods['terms'] as $secTerm) {
                        $secTerms[] = ['term_no' => (int) $secTerm['term_no'], 'label' => $secTerm['label']];
                    }
                    $secTermMap[$secSy->id] = $secTerms;
                    continue;
                }

                if ((int) $secAcadprogId !== 5) {
                    continue;
                }
                $secCfg = \App\Support\IBEDGradingDefaults::resolveConfigForLevel($secSy->id, $secAcadprogId, $secLevelId);
                if (!$secCfg) {
                    continue;
                }
                $secCfgTerms = DB::table('ibed_term')
                    ->where('config_id', $secCfg->id)
                    ->where('is_active', 1)
                    ->where('deleted', 0)
                    ->orderBy('sort_order')
                    ->orderBy('term_no')
                    ->pluck('short_code')
                    ->toArray();
                $secSemPlots = DB::table('subject_plot')
                    ->where('syid', $secSy->id)
                    ->where('levelid', $secLevelId)
                    ->where('deleted', 0)
                    ->whereNotNull('semid')
                    ->count();
                if (!empty($secCfgTerms)) {
                    $secTermNote[$secSy->id] = $secLevelName . ' is configured for ' . count($secCfgTerms)
                        . ' terms (' . implode(' / ', $secCfgTerms) . '), but '
                        . ($secSemPlots > 0
                            ? 'its subjects are still plotted per semester (' . $secSemPlots . ' subject plot(s))'
                            : 'no subjects are plotted for the whole year yet')
                        . ', so semester grading is still in effect. Re-plot the subjects with the Semester left blank to switch to terms.';
                }
            }
        }
```

**3b. Replace the hardcoded dropdown** (the "Term 1 / Term 2 / Term 3" `#filter_semester`
block) with a dynamic label + semester-seeded select, and add the note element after
the strand column's row:

```blade
                            <div class="col-md-2 filter_semester_holder " hidden>
                                <label for="filter_semester" id="filter_semester_label">Semester</label>
                                <select class="form-control form-control-sm select2" id="filter_semester">
                                    {{-- Real semesters as the server-rendered default; the script below
                                         swaps these for the configured terms when term mode applies. --}}
                                    @foreach ($semester as $sem)
                                        <option value="{{ $sem->id }}" {{ $loop->first ? 'selected="selected"' : '' }}>
                                            {{ $sem->semester }}</option>
                                    @endforeach
                                </select>
                            </div>
                            <div class="col-md-2 filter_semester_holder" hidden>
                                <label for="">Strand</label>
                                <select class="form-control form-control-sm select2" id="filter_strand"></select>
                            </div>
                        </div>
                        <div class="row">
                            <div class="col-md-12">
                                <div id="filter_semester_note" class="alert alert-warning d-flex align-items-start mb-0 mt-2 py-2 px-3"
                                    style="font-size:.8rem" hidden>
                                    <i class="fas fa-info-circle mt-1 mr-2"></i>
                                    <span id="filter_semester_note_text"></span>
                                </div>
                            </div>
                        </div>
```

**3c. Add the ready-block JS** right after
`if (section.acadprogid == 5) { $('.filter_semester_holder').removeAttr('hidden') }`:

```javascript
                    // ---- Period filter (term-aware) ----------------------------------------
                    var SEC_TERM_MAP = @json((object) $secTermMap);
                    var SEC_SEMESTERS = @json($semester);
                    var SEC_TERM_NOTE = @json((object) $secTermNote);

                    function applySectionPeriodFilter() {
                        var syid = $('#filter_schoolyear').val();
                        var terms = SEC_TERM_MAP[syid];

                        applySectionPeriodColumns(terms);
                        if (section.acadprogid != 5) { return; }

                        var $sel = $('#filter_semester');
                        var current = $sel.val();
                        if ($sel.hasClass('select2-hidden-accessible')) { $sel.select2('destroy'); }

                        $sel.empty();
                        if (terms && terms.length) {
                            $.each(terms, function (i, t) {
                                $sel.append('<option value="' + t.term_no + '">' + t.label + '</option>');
                            });
                            $('#filter_semester_label').text('Term');
                        } else {
                            $.each(SEC_SEMESTERS, function (i, s) {
                                $sel.append('<option value="' + s.id + '">' + s.semester + '</option>');
                            });
                            $('#filter_semester_label').text('Semester');
                        }

                        if (current && $sel.find('option[value="' + current + '"]').length) { $sel.val(current); }
                        $sel.select2();

                        var note = SEC_TERM_NOTE[syid];
                        if (note) {
                            $('#filter_semester_note_text').text(note);
                            $('#filter_semester_note').removeAttr('hidden');
                        } else {
                            $('#filter_semester_note_text').text('');
                            $('#filter_semester_note').attr('hidden', 'hidden');
                        }

                        applySectionPeriodColumns(terms);
                    }

                    // Relabel the Grade Status period columns. Degrades gracefully: on a status
                    // table without the sec-period-* markers the selectors match nothing (the
                    // legacy Quarter 1-4 layout is kept).
                    function applySectionPeriodColumns(terms) {
                        var count = (terms && terms.length) ? terms.length : 4;
                        var lastShown = count;
                        for (var n = 1; n <= 4; n++) {
                            var term = (terms && terms[n - 1]) ? terms[n - 1] : null;
                            var hasData = $('.sec-period-col.sec-period-' + n).children().length > 0;
                            var visible = n <= count || hasData;
                            $('.sec-period-head.sec-period-' + n)
                                .text(term ? term.label : (terms ? 'Q' + n : String(n))).toggle(visible);
                            $('.sec-period-col.sec-period-' + n).toggle(visible);
                            $('.sec-modal-period-head.sec-modal-period-' + n)
                                .text(term ? term.label : 'Quarter ' + n);
                            if (visible && n > lastShown) { lastShown = n; }
                        }
                        $('#sec_period_group_head').attr('colspan', lastShown);
                    }

                    $(document).ajaxComplete(function () {
                        applySectionPeriodColumns(SEC_TERM_MAP[$('#filter_schoolyear').val()]);
                    });

                    applySectionPeriodFilter();
                    // Bound BEFORE the reload handler below so the options are rebuilt first.
                    $(document).on('change', '#filter_schoolyear', applySectionPeriodFilter);
```

**Compile-check the blade** (artisan may not boot on old Symfony/PHP; compile the file
directly instead):

```bash
php -r 'error_reporting(E_ERROR|E_PARSE); require "vendor/autoload.php";
$b=new Illuminate\View\Compilers\BladeCompiler(new Illuminate\Filesystem\Filesystem, sys_get_temp_dir());
file_put_contents(sys_get_temp_dir()."/_bc.php",$b->compileString(file_get_contents(
"resources/views/principalsportal/pages/section/sectioninfo.blade.php")));'
php -l "$(php -r 'echo sys_get_temp_dir();')/_bc.php"
```

---

## Porting notes / gotchas

1. **Line-range-scope Change 2** — never `replace_all` the `->where('semid', $semid)`
   pattern; identical calls exist in other methods and would break (no `$semidMatch`
   there).
2. **`$levelid` shape differs by method** — a `sections` row in `get_schedule_2`
   (`$levelid->levelid`), a scalar in `sh_insert_sched` (`$levelid`). Use the right form.
3. **Grade Status relabel is a no-op** unless the status table carries the
   `sec-period-*` / `sec-modal-period-*` / `#sec_period_group_head` markers. es_ldcu's
   legacy table doesn't, so the columns stay "Quarter 1-4" (harmless). Fully relabeling
   is a separate, larger markup rework — out of scope here.
4. **`$sectionInfo`** must expose `levelid` / `acadprogid` / `levelname`; the `?? null`
   fallbacks keep it safe if a field is absent.
5. This is confined to `ScheduleController` + the section-info blade — it does **not**
   touch ECR, final grading, or reports.

6. **Wrap every `ibed_term_config` read with `activeConfigQuery()`.** The
   resolvers (`resolveShsPeriods`, `resolveTermLabelsForLevel`) already go
   through `activeConfigQuery` internally, but any direct `ibed_term_config`
   or `ibed_term` query added to this controller must also be wrapped. A bare
   `where('deleted', 0)` read without the guard resurfaces an Inactive config
   — the #1 source of "terms showing where they shouldn't" (Module 05
   invariant).

---

## Verification

After applying (test on a copy — behavioral change on a scheduling path):

1. **Add a schedule** on a term-mode SHS section → in the DB the new
   `sh_classsched.semid` is **NULL** (not `1/2/3`).
   ```sql
   SELECT id, semid, glevelid FROM sh_classsched WHERE sectionid=? AND deleted=0 ORDER BY id DESC LIMIT 5;
   ```
2. **Format 2** schedule grid shows the section's schedules (not empty).
3. **Dropdown** shows the configured terms (label "Term") for a term-mode SHS level;
   real semesters (label "Semester") for a JHS / non-term level; a warning note when a
   config applies but subjects aren't whole-year-plotted yet — and **no `semid = 3`**.
4. The Subject Plot **"still stamped to a semester"** banner does **not** reappear
   after adding a schedule.
5. **Regression:** a plain semester (non-term) section still filters by semester
   normally; teacher/room schedule views are unaffected.

**One-time cleanup:** existing rows saved with `semid = 3` will now display, but run
**Convert all to Whole Year** (Module P2) once on affected sections to normalize them
to `NULL`.
