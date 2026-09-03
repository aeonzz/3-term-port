# Known Pitfalls — 3-Term Grading

Bugs and gotchas the es_ldcu rollout actually hit. Read this before/while porting
so you don't rediscover them the hard way. Each entry: **symptom → cause → fix**,
with the module it belongs to.

---

## 1. SHS class shows "Term-Based" (or terms) when it shouldn't — Module 05/07

**Symptom:** a semester-plotted Grade 11/12 class appears under Term-Based on
`/classschedule`, or renders term columns, even though its subjects aren't
whole-year plotted.

**Cause:** the schedule builder fell through to `resolveActiveTerms()` (config-only)
after `resolveShsPeriods()` correctly returned `isTermMode = false`.
`resolveActiveTerms` finds the IBED config and wrongly stamps `is_term_mode = 1`.

**Fix:** for SHS levels (14/15), `resolveShsPeriods()` is **authoritative** — never
fall through to `resolveActiveTerms` for them. In `TeacherECRController@schedule`
the fallback must be gated: `if (!$periods && !in_array((int)$levelid,[14,15],true))`.

---

## 2. Grade grid empty / wrong tab active — Module 08

**Symptom:** on `/classschedule`, badges say "Quarterly 0 / Term-Based 2" but the
visible table shows the term rows under the Quarterly tab (or nothing).

**Cause:** the datatable renders the active tab's list, but nothing auto-switches
the active tab when the default (Quarterly) side is empty.

**Fix:** when one side is empty and the other has rows, auto-activate the non-empty
tab before rendering (both directions), so the visible table matches the badges.

---

## 3. Dynamic ECR renders blank over real legacy scores — Module 07

**Symptom:** a class that already has grades (old WW/PT/QA format) switches to the
dynamic/component ECR and shows an empty grid.

**Cause:** `has_ibed_components` flipped to true because `components_json` exists,
but the dynamic viewer only reads `ibed_ecr_item_grade` — which is empty for a class
graded the old way. The real scores sit in `gradesdetail`.

**Fix:** the old-data tie-breaker in `hasIbedComponents()` — if
`ibed_ecr_item_grade` has no rows but `gradesdetail` has a **positive** total
(`wwtotal>0 OR pttotal>0 OR qatotal>0`), keep the class on the **static** ECR until
it's re-uploaded through the dynamic ECR. Use `> 0`, **not** `whereNotNull` —
`TeacherGradingV2` seeds rows with 0 on page open, so 0 isn't real data. Scope the
check to the rendered `$quarter` when the caller knows it.

**The guarantee (invariant #5):** a static-format class keeps the **existing
grading + existing (`gradetransmutation`) transmutation**, untouched, in **both**
the ECR and system grading. The feature never recomputes or overwrites it. Only
dynamic/term classes use the new `IbedGradeEquivalency` transmutation. If you ever
see a legacy class's grades change after enabling the feature, this guard was
broken — check that `hasIbedComponents` returned false for it and that its grading
grid took the non-component (`else`) branch.

---

## 4. "Configured for N terms but X schedules still semester" banner — Module 06 (not a bug)

**Symptom:** the Subject Plot page shows a yellow banner and the level still grades
in quarters despite an active 3-term config.

**Cause:** this is **by design**. SHS needs BOTH a term config AND whole-year
plotting (`subject_plot.semid IS NULL` for every subject). Some subjects/schedules
are still semester-stamped.

**Fix (operator action, not code):** click **Convert all to Whole Year**
(`bulkConvertToWholeYear`). Confirm no existing semester grades would be stranded
first. Only after conversion does `shsHasTermPlotting()` return true and the level go
term-mode. Junior levels have no such gate.

---

## 5. Inactive config still takes effect on some screen — Module 05 (the big one)

**Symptom:** a term config set to **Inactive** still drives terms on final grading /
report card / master sheet / teacher grading, even though it's disregarded on the
setup and ECR screens.

**Cause:** that screen reads `ibed_term_config` with only `->where('deleted',0)` and
**skips the `isactive` guard**. The guard runs per-read, so one unwrapped read
resurfaces the inactive config.

**Fix:** wrap **every** grading/report read with
`IBEDGradingDefaults::activeConfigQuery(...)` (or `IbedGradeEquivalency::whereConfigActive`).
Run `scripts/audit.sh` — its invariant section flags `[! NO GUARD]` files. The es_ldcu
audit found 14 such sites (GenerateGrade, FormReports, StudentGradeEvaluation,
MasterSheet ×3, TeacherGradingV2 ×2, IBEDECRController, and 5 grading blades). The
guard is **conditional** (`Schema::hasColumn`) so DBs without the `isactive` column
don't fatal — keep it conditional, never a bare `->where('isactive',1)`.

---

## 6. Grades land in the wrong period / final can't find a term — Modules 07–09

**Symptom:** term grades don't show up, or the final grade is always null.

**Cause:** assuming a separate "term" column. There isn't one — `grades.quarter` is
**reused as the term_no** in term mode. Reading/writing under a different column
loses the data; `computeFinalFromFormula` returns null if a referenced `$qN` has no
grade.

**Fix:** always read/write term grades under `grades.quarter = <term_no>`. The
period buttons/columns post `term_no` as `quarter`.

---

## 7. Viewer shows blank for an SHS class graded before conversion — Module 08

**Symptom:** the class-record modal / grade view is empty for an SHS class that has
real scores.

**Cause:** some SHS `grades` headers were created with `semid = NULL` before the
whole-year conversion; a strict `where('semid', $semid)` match finds nothing.

**Fix:** in the viewers, match a header whose `semid` **equals the class semid OR is
NULL** for SHS levels. (`IBEDECRController@view` already does this.)

---

## 8. Formula safety — Modules 03/04/09 (don't "simplify")

Two different formula paths with different safety models — keep them straight:

- **Final-grade formula** (`GenerateGrade::computeFinalFromFormula` /
  `evaluateArithmetic`): **parsed as arithmetic, never `eval`'d.** Whitelist first
  gate (`$qN`, numbers, `+ - * / ( ) .`); every referenced term must have a grade
  or the result is null.
- **Score-conversion formula** (`IbedGradeEquivalency::applyScoreConversion`): **is
  `eval`'d**, so it's double-whitelisted (`R`, `H`, digits, operators) and falls
  back to `(R/H)*100` on anything unsafe.

**Fix:** never loosen either whitelist, and don't swap the parser for `eval` "to
simplify." The config screen's `validateFormulaCode` is the write-time gate;
`computeFinalFromFormula` is the read-time gate — keep both.

---

## 9. Hybrid: two DBs silently diverge — HYBRID-DEPLOYMENT.md

**Symptom:** a class is term-mode on the teacher portal (online) but quarter on the
registrar report (local), or vice-versa.

**Cause:** two databases, edited on both sides, out of sync — or the two repos'
Module 05 Support classes drifted.

**Fix:** sync the config by **business key with FK remap** (never by auto-increment
`id`); keep `IBEDGradingDefaults`/`IbedGradeEquivalency` **byte-identical** across
repos (pin to the same commit); and ensure grades flow online→local for reports.
See the hybrid appendix.

---

## 10. A period filter already says "Term 1/2/3" before any P-module is ported

**Symptom:** a target repo's setup screen (e.g. SHS Cluster Plotting's period
dropdown) already shows hardcoded "Term 1" / "Term 2" / "Term 3" options — looks like
term mode is already live, so it's tempting to assume the P-module is done and skip
the PREFLIGHT.

**Cause:** this is a **cosmetic label hack**, not real term-config-driven logic — a
prior dev (or an earlier partial port) hardcoded the option text/values (e.g.
`<option value="1">Term 1</option>`) directly in the blade, disconnected from
`ibed_term_config`/`ibed_term` and from any resolver. The filter still just sends a
raw id to a `semid`-style query param; it happens to coincidentally line up with a
real `semester.id` if the school only ever had semesters 1/2. Found in
`sjhsli_online`'s `shs-cluster-plotting/index.blade.php` before Module P3 — the exact
"Term 1/2/3" markup the P1 kit doc's own before/after example warns about for
`sectioninfo.blade.php`.

**Fix:** don't treat a "Term"-labeled dropdown as evidence the module is ported —
always run the PREFLIGHT greps. Replace the hardcoded options with the kit's
documented real markup (a `@foreach` over `$semester`, config-driven term/semester
switching via JS reading the module's term map), same as Module P1's
`SEC_TERM_MAP`/P2's `#filter_term`/P3's `SHS_CLUSTER_TERM_MAP` pattern.

> Recurred a second time on the same screen family: `sjhsli_online`'s SHS Subject
> Picking page (`registrar/shs/subjectpicking/index.blade.php`, Module P4) had the
> exact same hardcoded `<option value="1">Term 1</option>` placeholder on its
> `#filter_semid` dropdown before P4 was applied. Whenever porting any P-module,
> check every period/semester filter on the target screen for this pattern, not just
> the one the current module's PREFLIGHT names.

---

## 11. New single-segment route silently resolves to the wrong controller method

**Symptom:** a newly-added `Route::get('/thing/some-action', ...)` returns data from
an unrelated method (often a `show($id)`-style method), or 404s in a way that traces
back to the wrong handler running with `$id = 'some-action'`.

**Cause:** the same base path already has `Route::get('/thing/{id}', '...@show')`
registered **earlier** in the same route file/group. Laravel matches routes in
registration order, and `{id}` matches any single path segment — so a same-shape,
single-segment sibling route (`/thing/some-action`) registered *after* it never gets
a chance to match; the `{id}` route wins first with `$id` literally set to the string
`'some-action'`. Found adding Module P3's Change 6c section-assignment routes
(`/cluster-plot/sections-for-level`, `/cluster-plot/section-assignments`,
`/cluster-plot/picked-students`) after the pre-existing
`Route::get('/cluster-plot/{id}', '@show')` in `sjhsli_online`.

**Fix:** register every new single-segment static route **before** the `{id}` route
on the same base path, in the same group. Multi-segment routes
(`/thing/sub/action`) are safe regardless of order — `{id}` only ever matches one
segment, so they never collide. When adding any new route next to an existing
`{id}`-style route, check for this before wiring anything else.

---

## 12. A `hidden`-attribute banner still shows — empty — after conversion

**Symptom:** after fully converting a level to term mode, a warning banner (e.g.
Module P1's `#filter_semester_note` "still plotted per semester" alert) is still
visible on the page, but with **no text inside it** — just the icon and an empty
orange strip.

**Cause:** the banner element carries the native `hidden` HTML attribute for
show/hide AND a Bootstrap `d-flex` (or any other `display: ... !important`)
utility class in the same `class=""`. Bootstrap's utility classes compile with
`!important`, which beats the browser's own (non-`!important`) `[hidden] {
display: none }` user-agent rule — so once `d-flex` is on the element, setting
`hidden` no longer hides it; the div still renders as an empty flex box. Found in
`sjhsli_online`'s `sectioninfo.blade.php` (Module P1): the underlying term-state
logic was correct (no note text was set, because the level had genuinely finished
converting), but the banner div itself never disappeared because of this
`hidden` + `d-flex` conflict. Confirmed live in a running Chrome session:
`getComputedStyle(el).display` was `"flex"` and `visibility` was `"visible"`
despite `el.hasAttribute('hidden') === true`.

**Fix:** never combine `hidden` (or jQuery `.hide()`/`.show()`, which just toggles
inline `display: none` without `!important`) with a `display`-forcing utility
class on the *same* element. Move the utility class to an **inner** wrapper div
and keep the outer, hide/show-toggled element free of any competing `display`
utility:
```html
<div id="thing" hidden>                        <!-- toggle hidden on THIS one -->
    <div class="d-flex align-items-start">     <!-- d-flex lives here instead -->
        ...
    </div>
</div>
```
When debugging a "still visible but empty" banner, check `hasAttribute('hidden')`
**and** `getComputedStyle(el).display` together — a mismatch between them is this
exact bug, not a logic/data problem.

---

## 13. A same-named, same-routed controller isn't necessarily the same feature

**Symptom:** a module's PREFLIGHT grep for a controller name (and/or its routes)
comes back positive, so the module looks already-ported — but the actual behavior
described in the kit doc is completely absent when you check the file's contents.

**Cause:** a target repo can have its own, unrelated controller that happens to
share a name and route convention with what the kit expects — usually because a
prior dev copied it from a different reference repo for a different reason, or
built a same-named "v2" for an unrelated redesign. Found porting Module 07 to
`sjhsli_online`: the routes `/ecr/downloadv2`, `/ecr/uploadv2`, `/ecr/viewv2` were
already wired to a `TeacherECRv2Controller` — exactly what Module 07/P7 expect by
name — but that file (5,346 lines) turned out to be a stale, non-term-aware
near-duplicate of the plain `TeacherECRController`, with zero `resolveShsPeriods`,
`is_term_mode`, or component-ECR logic anywhere in it. The genuinely term-aware
version of that controller existed in a *different* reference repo (`es_bcc`, not
the primary `es_ldcu`) — the kit's primary reference didn't even have a "v2"
controller at all; it branched term-mode internally inside the plain controller.

**Fix:** a name or route match is a *hypothesis*, not confirmation. Always grep the
actual file's contents for the module's real term-mode/feature symbols
(`resolveShsPeriods`, `is_term_mode`, `shsConfiguredTerms`, etc.) before marking a
PREFLIGHT check "already applied." When a target's controller doesn't match the
primary reference (`es_ldcu`) either in structure or in content, check the
secondary reference (`es_bcc`) before assuming the feature needs to be built from
scratch — it may already exist there under the same name.

## 14. A controller existing doesn't mean its blade views exist too

**Symptom:** a dynamic/component ECR class correctly routes to `/ibed-ecr/view`
(the gate is right, the endpoint is wired, `IBEDECRController.php` is fully present
and even byte-identical to the reference repo's copy) — but clicking Filter in the
ECR modal does nothing, or the class record panel never populates. No error toast
appears because the AJAX `success` handler receives an HTML 500 error page, not the
JSON/HTML it expects, and silently no-ops on it.

**Cause:** `IBEDECRController::view()` (and `download()`) render a dedicated blade
partial — `superadmin.pages.teacher.ibed_gradeview.blade.php` — that is a *separate
file* from the controller and was never copied over. Found porting Module 07 to
`sjhsli_online`: the controller had already been added (3,761 lines, fully
term-aware, previously mistaken for "doesn't exist" — see the
`verify-missing-claims-directly` lesson) but its blade was never ported, so every
call to `view()` threw `InvalidArgumentException: View [...] not found` at render
time. A grep for the controller's own symbols (or even confirming the file compiles)
gives zero signal about this, because the missing dependency is a separate file
resolved only when the method actually runs.

**Fix:** whenever a controller under this module renders a `view(...)`, explicitly
check that blade path exists in the target repo, not just the controller file.
`IBEDECRController`'s partial is self-contained (no `@extends`, only two hardcoded
endpoints — `/ibed-ecr/save-scores` and the pre-existing `/gradesSubmit/{quarter}`
— both already available) so it can be copied verbatim from either reference repo.
Also confirm the call site passes `readonly: 1` when the caller is a
superadmin/registrar preview screen, not the teacher's own grading page — the
partial's `$readOnly` flag is what hides the live Save/Submit buttons and open
score inputs, and omitting it silently turns a "preview" into the live edit grid.

## 15. A reference blade's helper functions may not exist in the target at all

**Symptom:** a kit doc's Change snippets for a blade call a helper function
(e.g. `selected_sched()`, `can_edit_quarter()`, `selected_schedule_sectionid()`)
as if it's already there — but grepping the target blade for that function name
comes back empty. Pasting the snippet in as-is throws `ReferenceError: <fn> is
not defined` the moment the page runs.

**Cause:** the reference repo's blade may have been refactored, at some point
unrelated to the 3-term feature itself, around a unified "resolve the current
selection" helper — usually to support a feature the target repo's copy of that
page never got (found on Module P8: `es_ldcu`'s `finalgrade.blade.php` wraps
every quarter/subject lookup in `selected_sched()` so cluster-plot electives
can be selected through the same dropdowns as regular classes; the target's
copy of the page had no cluster-plot concept at all and picked "the current
class" with a plain `all_sched.filter(x => x.subjid == ... && x.sectionid ==
...)` off two separate dropdowns). The kit doc's snippets are lifted directly
from the refactored reference, so they silently assume that architecture
exists.

**Fix:** before pasting any blade snippet, grep the target for every helper
name the snippet calls. If one is missing, don't backport the reference's
whole selection architecture as a side effect of the port — that's almost
always a separate, unrelated feature (here: cluster-plot elective support on
a page that never had it) and a much bigger, riskier change than the term-mode
work actually asked for. Instead **adapt**: keep the term-mode logic (period
maps, FG formulas, header gating) but re-key each function to whatever
selection pattern the target already uses, and stop to ask the user whether
they actually want the bigger architectural change before doing it. Grep every
row-render / recalculation call site too (e.g. an inline-edit "recompute this
one grade" handler) — a fixed-quarter-count formula duplicated in more than
one place needs the same term-count fix in each, or editing a single cell will
silently revert the class to the old quarter-based number.

## 16. When a cluster item's "sectionid" is really a different table's id, every lookup that treats it as a real section will silently misfire

**Symptom:** a cluster-plot elective's grading page shows the wrong section
name (a real, unrelated section — not an error, not blank), because a query
did `where('sections.id', $sectionid)` and `$sectionid` happened to collide
with an actual row in `sections`.

**Cause:** several modules in this port (P7, P8, P9) reuse the `sectionid`
slot to carry `sh_cluster_plot.id` for cluster electives, since the target
repo (unlike the kit's reference) has no separate `clusterplotid` request
parameter threaded through every endpoint. This is a deliberate, working
adaptation for lookups that are cluster-aware (`grades.sectionid`,
`gradesdetail`, `sh_cluster_plot_teacher.plotid`) — but it's a landmine for
any lookup that ISN'T cluster-aware and blindly treats the value as a real
`sections.id`. Found on Module P9: `TeacherGradingV2::showGrades()` resolved
the page's section-name label with a bare `sections.id = $section_id`
lookup — for cluster plot id `1`, this coincidentally matched real section
id `1` and displayed its name with no error, no crash, nothing to signal
the mismatch.

**Fix:** whenever this port's `sectionid` slot doubles as a cluster plot id,
audit every read of that value for whether it assumes "this is a real
`sections.id`." Gate each one on the same `$isCluster`/`$isClusterTermMode`
flag already used elsewhere in the method, and resolve cluster-specific
values (section name, room, teacher) from the cluster plot row itself
(`sh_cluster_plot`, `sh_cluster`, `ShsClusterSectionScope`'s assignment
table) instead. This bug class won't throw or show up in a quick smoke test
— it only surfaces when the colliding ids happen to belong to genuinely
different things, so verify with an id that's unlikely to coincidentally
match (or deliberately pick a cluster plot id that collides with a *known*,
different real row, as the fix above was verified against).

## 17. A class scheduled via `grading_percentage_id` disappears (or shows 0 students) the moment its `subject_plot` row is missing or deleted

**Symptom:** a real, actively-taught class — a genuine `sh_classsched` row,
correctly assigned to a teacher, with `grading_percentage_id` set — is either
completely absent from a page that lists a teacher's/section's classes, or
present but showing "0 students" / no subjects, even though the exact same
class shows up correctly (with real enrollment) on another page for the same
teacher/section/SY. The two pages disagree about the same underlying data.

**Cause:** the affected query gates class inclusion, subject listing, or
enrolled-student counting on the **existence of an active `subject_plot`
row** for that subject/level/SY, with no fallback for a class scheduled a
different way. A `subject_plot` row can legitimately be missing or
soft-deleted — a subject-catalog cleanup, a duplicate-subject merge, or a
class that was always scheduled straight off `sh_classsched` without ever
getting plotted — while the `sh_classsched` row (and its
`grading_percentage_id`) stays real and active. Whichever query still
requires the plot row silently drops or zeroes that class; whichever query
doesn't, shows it correctly. Found **six separate times** across this port
(each independently, in a different file, always the same root shape —
check this pattern FIRST before treating a fresh occurrence as a novel bug):
`TeacherPendingGrade::peding_student_grades()`,
`TeacherGradingV2::check_pending()`, `GradePostingController::get_shssubjects()`
(Module P12), `TeacherPendingGrade::getGrades()` (Module P11), and — the pair
that prompted this entry — `TeacherECRController::schedule()` (Module P7,
`/classschedule`'s Term-Based Classes tab): first its class-inclusion gate
(`if ($check_if_exist_in_plot > 0)` around both the `sh_classsched` and
`assignsubj` loops) dropped the class from the list entirely — es_ldcu's
real `schedule()` has **no such gate at all**, it pushes every scheduled
item unconditionally; then, after restoring visibility, its student-count
logic (strand-derived from `subject_plot` → `sh_enrolledstud`) still showed
"0 students" because the strand list was empty, since es_ldcu's version has
an `else` branch (count all enrolled students in the section directly when
no strand resolves) that the target repo's copy was missing.

**Fix:** never assume a `subject_plot`-existence check is required — check
the **actual es_ldcu source** for the specific function first, every time.
Two different faithful fixes have applied depending on what es_ldcu actually
does there: (a) if es_ldcu has **no gate at all** (as in
`TeacherECRController::schedule()`'s inclusion loops), remove the gate
entirely rather than inventing a `grading_percentage_id`-OR fallback — don't
guess at a "reasonable" tolerant condition when the reference has none; (b)
if es_ldcu resolves a value (strand, subject list) from `subject_plot` but
has an explicit `else`/fallback for the empty case, port that fallback
verbatim rather than leaving the zero/empty result. Either way, verify by
finding a real class in the target DB whose `subject_plot` row is missing or
`deleted=1` but whose `sh_classsched.grading_percentage_id` is set, and
confirming it now matches across every page that's supposed to show it —
one page rendering it correctly and another not is the signal to search for
this exact pattern, not a coincidence.

**Variant — the reference has the same gap, not just the target.** Module
P6's `TeacherProfileController::shs_sched()` (Teacher Home page's Class
Schedule widget) resolves a section's strand(s) from
`sh_sectionblockassignment`, then — only when that list isn't empty —
narrows it further to whichever strand(s) the *subject itself* is plotted
for via `subject_plot`. Porting es_ldcu's `if (count($strand) > 0) {...}
else {...}` gate verbatim (fix shape (b) above) fixed the case where a
section has *no* strand assignment at all, but a real class with a genuine
strand assignment and zero `subject_plot` rows still showed 0 students
afterward — because the narrowing step itself has **no fallback in
es_ldcu either**. Confirmed by reading es_ldcu's source directly: this
specific sub-case (non-empty section strand, subject with zero plot rows)
simply doesn't have a handled path there. Since there's no reference
behavior to port for it, this required inventing new tolerant logic beyond
a direct port — done only after explaining the distinction and getting the
user's explicit go-ahead, not silently: check whether the subject has *any*
active `subject_plot` row at all (no strand filter) before trusting a
narrowed-to-empty result; if none exists, keep the section's original,
unnarrowed strand list instead of the narrowed one. The general rule this
confirms: when a "port the fallback" fix (shape (b)) doesn't fully resolve
the symptom, check whether the *reference itself* has the gap before
assuming you missed something in the port — and treat inventing new logic
as a judgment call to surface to the user, not an automatic next step.
