# Module 12 — Static → Dynamic ECR Conversion

A per-class, per-quarter **"Convert to dynamic ECR"** action that takes a class
already graded on the fixed WW/PT/QA static ECR and flips it onto the dynamic
(component/item-level) ECR **without the teacher re-keying scores** — by
migrating the existing `gradesdetail` roll-up into `ibed_ecr_item_grade` rows
against the class's **already-configured** component setup, then recomputing the
term grade through the config-driven equivalency path.

> **Status: implemented in es_ldcu** on `feat/taborin/3-term`, commit
> [`8d9c52ebd`](https://github.com/CK-PUB-DEV/es_ldcu/commit/8d9c52ebd9bf586d5049b995a8d17e6bfb27013b)
> ("feat: add static-to-dynamic ECR conversion with per-item score migration").
> The sections below describe the shipped design as of that commit; use them as
> the port reference. History lives in `git log`, not a changelog on this page.

---

## Why this exists

`TeacherECRController::hasIbedComponents()` has an **old-data tie-breaker**
(kit invariant #5): a class whose `gradesdetail` rows carry positive
`wwtotal/pttotal/qatotal` for a given quarter stays on the **static** ECR until
`ibed_ecr_item_grade` rows exist for that `grades` header. This is deliberate —
it protects finalized legacy grades from being silently re-modelled.

The side effect is a **chicken-and-egg lock**: a school that has already set up a
component `components_json` for a class, and has already graded it on the static
ECR, cannot download the dynamic template (the class still resolves to static),
and the class stays static because it was never saved through the dynamic ECR.
Today the only way out is a manual DB edit (zero the legacy totals, or
hand-insert an `ibed_ecr_item_grade` row). This module replaces that with a
guarded, previewable button.

---

## Reference implementation (es_ldcu) — files this module will touch

| Piece | Path / symbol | Change |
|-------|---------------|--------|
| Controller (new methods) | `app/Http/Controllers/SuperAdminController/IBEDECRController.php` → `convertFromStaticPreview(Request)`, `convertFromStatic(Request)`, `revertToStatic(Request)` | new endpoints: preview + commit + revert |
| Gate (read only) | `app/Http/Controllers/SuperAdminController/TeacherECRController.php` → `hasIbedComponents()` | **no change** — the migration writes `ibed_ecr_item_grade` rows, which the existing `$hasNewData` branch already honours |
| Setup resolution (read only) | the same resolve order `hasIbedComponents()` uses: `sh_classsched.grading_percentage_id` → `classsched.grading_percentage_id` → `subject_plot.gradessetup` → `sh_cluster_plot.gradingsetupid` → `subject_gradessetup` | read `components_json` + `input_mode`; **never written** |
| Equivalency | `app/Support/IbedGradeEquivalency.php` (Module 05 / 04) + `IBEDECRController::resolveIbedTermGrade()` | reused as-is for the recompute |
| View / button | `resources/views/superadmin/pages/teacher/teacherinformation.blade.php` (System Grading Class Record modal) | new **Convert to dynamic ECR** / **Revert to static** buttons, shown by state |
| Routes | `routes/web.php` (next to the existing `/ibed-ecr/*` block, ~line 6200) | `+3` routes |
| Audit table | `ibed_ecr_conversion_log` (new — Module 01 registry entry) | records the pre-conversion `gradesdetail` snapshot for revert |

**Why the System Grading modal and not the term-grading modal:**
`teacherinformation.blade.php` is the only surface where the dynamic ECR
download / view / upload are already wired (`is_ibed_ecr` branch). Put the
button there. The term-grading modal
(`resources/views/superadmin/pages/teacher/termgrading.blade.php`) has **no**
dynamic-ECR wiring at all — adding the button there is a separate, larger job
(port the whole `is_ibed_ecr` branch first, per Module 07 / P9).

---

## Dependencies

- **Module 01** — schema: `grades`, `gradesdetail`, `subject_gradessetup`,
  `ibed_ecr_item_grade`, `ibed_grade_point_scale`, `ibed_term_config`,
  `ibed_ecr_conversion_log` (new).
- **Module 04** — grade equivalency (`ibed_grade_point_scale`), the transmutation
  the recomputed grade will use.
- **Module 05** — `IBEDGradingDefaults::activeConfigQuery()`,
  `IbedGradeEquivalency`, `resolveIbedTermGrade()`.
- **Module 07** — dynamic ECR (`IBEDECRController`, `ibed_ecr_item_grade`
  read/write, `saveScores()` / `upload()` recompute path, the pooled-vs-weighted
  PS rule in the class docstring).
- **Module P9** — System Grading term port (`is_ibed_ecr`, `/ecr/check-ibed`,
  the Class Record modal this button lives in).

Do not build this until 01/04/05/07/P9 are in place and verified.

---

## Goal — what this port must achieve

After this module, a superadmin on the System Grading Class Record modal can
convert **one class, one quarter/term at a time** from the static ECR to the
dynamic ECR — **only when a component setup already exists for that class** —
keeping the existing scores, with a preview of every grade that would change
before anything is written; and can revert that conversion while the term is
still unposted.

The conversion **never touches `subject_gradessetup` or the class schedule.** The
component structure must already be configured through the normal grading-setup
UI. This module only moves scores and recomputes.

**Acceptance criteria (all must hold):**

- [ ] **Gate 1 — setup exists.** The **Convert to dynamic ECR** button appears
      only when the class's resolved `subject_gradessetup` already has
      `input_mode = 'component_scores'` **and** a non-empty `components_json`,
      **and** the class/quarter currently resolves to the **static** ECR
      (`has_ibed_components == 0`) **and** has real legacy scores
      (`wwtotal|pttotal|qatotal > 0`) in that quarter's `gradesdetail`, **and**
      there are no live `ibed_ecr_item_grade` rows for that header yet.
- [ ] **Weighted components are skipped, not blocking.** A component whose every
      sub-component carries its own `"percentage"` (the weighted-average PS form)
      can't receive a pooled legacy total without distorting its PS — so that
      *one* component is left unmapped (starts blank, PS/WS = 0) instead of
      refusing the whole conversion. The drop is never silent: it's flagged per
      component in the preview (`skip_reason: 'weighted_sub_components'`) and
      surfaced as a top-level `warning` string, and its effect (the resulting
      lower IG/QG) shows up in the per-student diff. Only when **every** component
      that has a positive legacy slot is weighted — i.e. nothing at all could be
      migrated — does the whole conversion become ineligible.
- [ ] **Gate — legacy slots map to a component.** Preview refuses if the
      `WW / PT / QA` legacy slots (those with a positive total) can't each be
      matched to exactly one component in `components_json` (by `short_code`, or
      an explicit per-repo map), or that component has scores but no recorded
      HPS. Components in the setup with no legacy slot migrate as empty, same as
      a weighted one — the preview doesn't distinguish "never had scores" from
      "had scores but couldn't take them," beyond the `skip_reason` field.
- [ ] Clicking Convert opens a **preview** (no writes): per-student
      `old QG → new QG`, old letter → new descriptor, a count of
      changed / unchanged / newly-null grades, and — when applicable — a `warning`
      naming every dropped component and its weight. Preview also lists the
      existing components (name, weight, item count, `mapped_slot`/`skip_reason`)
      and the legacy-slot → component map it resolved.
- [ ] Preview also refuses when: the quarter's grade is **approved/posted** for
      any student (`gdstatus` not in `[0, 3, null]`); or `components_json`
      component percentages don't sum to 100.
- [ ] On **Commit**, the module: writes `ibed_ecr_item_grade` HPS rows
      (`studid = 0`) and raw-score rows per student, placing each legacy component
      total on the **first item** of its mapped component (0 on the rest, HPS
      likewise); recomputes `ig / qg / transmuted_grade / letter_grade` and the
      `wwtotal/wwps/wwws …` legacy roll-up columns on the **same** `gradesdetail`
      rows; writes the audit row; and touches nothing outside that class + quarter
      (+ `semid` for SHS). **No write to `subject_gradessetup` or
      `sh_classsched`/`classsched`.**
- [ ] After commit, the same class/quarter resolves to the **dynamic** ECR
      everywhere (Class Record view, download, upload, System Grading, final
      grades, report card) via the existing `hasIbedComponents()` `$hasNewData`
      branch — **no change to that method**.
- [ ] Legacy `gradetransmutation` is **not** consulted for the recompute; the new
      grade comes from `ibed_grade_point_scale` via `resolveIbedTermGrade()`.
- [ ] **Revert to static** (shown only while the quarter is unposted)
      soft-deletes the `ibed_ecr_item_grade` rows for that header, restores the
      pre-conversion `gradesdetail` snapshot, and the class resolves back to
      static. No setup/schedule state to unwind (none was changed).
- [ ] **Revert warns before discarding post-conversion work.** The snapshot
      restored is the **one** taken when the class was originally converted —
      it does not track anything saved afterward. If the teacher used the
      dynamic ECR normally since then (`saveScores()` writing new
      `ibed_ecr_item_grade` rows), the preview's revert mode carries a
      `warning` naming how many scores would be discarded, shown under the
      button and folded into the confirmation dialog. This is **warn, then
      allow** — not a block: revert still proceeds once confirmed.
- [ ] Other quarters/terms of the same class, and other sections of the same
      subject, are untouched by either action.

> **Report back after applying (do this in chat).** When the port is done, post
> the acceptance criteria as a **ticked checklist** — **✅** applied and verified,
> **✔️** code applied but runtime/live-page test still pending, **⬜** skipped or
> not applicable (say why). Never mark ✅ something you didn't apply.

---

## Behaviors by state

| Class / quarter state | Convert button | Behavior |
|-----------------------|----------------|----------|
| **No `components_json` on resolved setup** | hidden | Nothing to convert onto. Configure the component setup first (normal grading-setup UI). |
| **Setup has `components_json`, static, legacy scores, unposted, every scored component poolable** | shown, enabled | Full preview + commit available, no warning. |
| **Setup has `components_json`, static, legacy scores, unposted, *some* scored component is weighted** | shown, **enabled** | Preview is eligible but carries a `warning`; that component's scores are dropped (starts blank) and the diff shows the resulting lower grade. Admin still confirms explicitly before Commit. |
| **Every scored component is weighted (nothing poolable)** | shown, disabled | Tooltip: "Every component with existing scores uses its own weighted breakdown, so none of them can be carried over automatically. Use the new ECR directly and enter the scores manually." |
| **Legacy slot can't be mapped to any component** | shown, disabled | Tooltip names the unmatched slot in plain terms (e.g. "There are existing 'QA' scores, but the new grading setup has no matching component for it"). |
| **Setup has `components_json`, static, no legacy scores in quarter** | hidden | Use the dynamic download directly — that path already works once a setup exists. |
| **Setup has `components_json`, some students posted/approved** | shown, disabled | Tooltip: "N student(s) already have an approved or posted grade for this period. Unpost or return those first before converting." |
| **Already dynamic (`ibed_ecr_item_grade` rows exist)** | hidden | **Revert to static** shown instead (if unposted). |

---

## The central constraint — read before designing the mapping

The static ECR **does not persist per-item HPS.** `gradesdetail` stores, per
student per component:

- up to 10 raw item scores — `ww1..ww9, ww0` / `pt1..pt9, pt0` / `qa1..qa9, qa0`
- **one** component-total HPS — `wwhps` / `pthps` / `qahps`
- the component roll-up — `wwtotal`, `wwps`, `wwws` (and pt/qa equivalents)
- `ig`, `qg`, `transmuted_grade`, `letter_grade`, `gdstatus`

The Excel template has a per-item HPS row (row 11), but only the **sum** round-trips
into `wwhps`; the individual cells are never stored. es_ldcu's static ECR is
**WW/PT/QA only** — `subject_gradessetup.comp4` exists as a weight column but there
are no `comp4*` score columns in `gradesdetail`.

**es_ldcu actually has two static controllers, and they disagree on where that
sum lives:**

| Controller | Mode | HPS column |
|---|---|---|
| `TeacherECRController` (`/ecr/download`, `/ecr/upload`, `/ecr/view`) | quarter-based | `gradesdetail.<slot>hps` — per-student row, one value repeated for the whole class |
| `TeacherECRv2Controller` (`/ecr/downloadv2`, `/ecr/uploadv2`, `/ecr/viewv2`) | term-based | `grades.<slot>hrtotal` (with per-item `<slot>hr1..<slot>hr0` alongside it) — on the **header**, not `gradesdetail`, and `gradesdetail.<slot>hps` is never written |

A term-mode class (the common case once a school is on 3-term) is graded through
the v2 controller, so `gradesdetail.wwhps` reads `0` even though the class
plainly has an HPS — it's just sitting on `grades.wwhrtotal` instead. Checking
only `gradesdetail.<slot>hps` produces a false "no recorded HPS" refusal for
every term-mode class. `resolveConversionSlotHps()` tries `gradesdetail` first
and falls back to the header column so both controllers' output resolve
correctly (§3, step "map legacy slots").

**Consequence:** there is no per-item denominator to reproduce each configured
item's PS. So the migration puts each legacy component total on **one** item of
its mapped component and leaves the rest at 0/0. For a **pooled** component this
is mathematically exact (that's why a weighted component is skipped rather than
approximated — see §2 below):

```
pooled PS = (Σ item scores) / (Σ item HPS) * 100
          = wwtotal / wwhps * 100          ← same as the static roll-up
```

`WS`, `IG = Σ(PS · weight)` are therefore unchanged; only `QG` can move, because
dynamic transmutes via `ibed_grade_point_scale` instead of legacy
`gradetransmutation`.

---

## Data mapping

### 1. Resolve the setup (read only)

Read `components_json` + `input_mode` from the **first** match of the same order
`hasIbedComponents()` uses:

1. `sh_classsched.grading_percentage_id` → `subject_gradessetup` (SHS levels
   14/15, filtered by `semid` when present)
2. `classsched.grading_percentage_id` → `subject_gradessetup` (JHS/GS)
3. `subject_plot.gradessetup` → `subject_gradessetup` (school-wide default)
4. `sh_cluster_plot.gradingsetupid` → `subject_gradessetup` (cluster electives;
   `sectionid` param is the clusterplotid)

Keep this resolution byte-identical to `hasIbedComponents()` so "which setup" can
never diverge. **Gate 1 fails** if the match has empty `components_json` or
`input_mode != 'component_scores'`.

### 2. Detect weighted components (skip, don't refuse)

For each component in `components_json`: if it has `sub_components` and **every**
sub-component carries a numeric `"percentage"`, this component is in the
weighted-average PS form (per the `IBEDECRController` class docstring /
`subComponentWeights()`). A single pooled legacy total can't be placed under it
without changing its PS.

This used to refuse the whole conversion. It doesn't anymore: the check only
matters for a component that a legacy slot is about to map onto (§3) — a
weighted component with no scored legacy slot is irrelevant either way. When a
*scored* slot's target component is weighted, that one component is **skipped**
(no HPS/score rows written for it — it starts blank, same as an unmapped
component) instead of blocking every other component's migration. It's recorded
in `dropped[]` (slot, component name, weight) and surfaced as a top-level
`warning` string plus a per-component `skip_reason: 'weighted_sub_components'` in
the preview, so the drop is visible before the admin confirms — never silent.

Only when **every** component with a scored legacy slot turns out weighted (so
`slot_map` ends up empty) does the whole conversion become ineligible — there'd
be nothing left to auto-migrate.

(A component with no `sub_components`, or with sub-components where none/only-some
carry `percentage`, is pooled — always mappable.)

### 3. Map legacy slots → components

For each legacy slot with a positive total across the class
(`WW` if any `wwtotal > 0`, likewise `PT`, `QA`):

- Match to the component in `components_json` whose `short_code` equals the slot
  code (`WW` / `PT` / `QA`), case-insensitive. **Fails** (refuses the whole
  conversion) if any positive slot has no unique match — that's a setup problem,
  not something to route around.
  - If the target repo's setups use other codes, require an explicit
    `['WW' => '<code>', 'PT' => '<code>', 'QA' => '<code>']` map (config or a
    small per-repo constant) and use that instead of a bare `short_code` compare.
- If the matched component is **weighted** (§2), skip it — don't map it, don't
  refuse.
- Otherwise require a positive HPS for that slot via `resolveConversionSlotHps()`:
  the max `gradesdetail.<slot>hps` across students with a positive `<slot>total`,
  falling back to `grades.<slot>hrtotal` (the term-mode/v2 controller's
  header-level HPS — see the central constraint above) when that's zero.
  **Fails** if neither source has one — there's nothing to divide by.

Components present in the setup but with **no** matching legacy slot (never had
static scores) are allowed and behave the same as a skipped weighted one — HPS 0,
student scores 0, flagged in the preview (`mapped_slot: null`, no `skip_reason`)
so the user knows those need to be graded in the dynamic ECR.

### 4. Migrate scores → `ibed_ecr_item_grade`

For the resolved `grades` header (`syid, levelid, sectionid, subjid, quarter`,
plus `semid` for SHS), and for each mapped `(slot → component C)`, one of two
layouts applies — `slotHasPerItemData()` picks between them per slot:

**Pooled (default; used whenever there's no per-item HPS source — quarter/v1
static, or a v2 class whose header HPS columns are empty):**

| Dynamic row | studid | item | value |
|-------------|--------|------|-------|
| HPS row | `0` | **first** item of `C` (first sub-component, first item) | `gradesdetail.<slot>hps` (or `grades.<slot>hrtotal` — see §3) |
| HPS row | `0` | every other item of `C` | `0` |
| score row | each student | first item of `C` | `gradesdetail.<slot>total` |
| score row | each student | every other item of `C` | `0` |

**Per-item (term/v2 static only — when `grades.<slot>hrtotal > 0`, meaning the
real per-item HPS columns `<slot>hr1..<slot>hr9,<slot>hr0` are populated
alongside gradesdetail's real per-item raw scores `<slot>1..<slot>9,<slot>0`):**
flatten `C`'s sub-components into an ordered item list (`flattenComponentItems()`)
and lay the legacy items onto it index-for-index —

| Dynamic row | studid | item | value |
|-------------|--------|------|-------|
| HPS row | `0` | flattened item `i` of `C` | `grades.<slot>hr<i>` |
| score row | each student | flattened item `i` of `C` | `gradesdetail.<slot><i>` |

If the legacy slot has more populated items (up to 10: suffixes `1..9, 0`) than
`C` has configured items, every index past the last one **accumulates onto the
last flattened item** rather than being dropped — pooled PS only cares about the
summed totals, not which item slot holds them, so this loses no points. This is
what makes the on-screen dynamic table look like the old one (item 1's score
under column 1, item 2's under column 2, …) instead of the whole component's
total dumped into a single column — the failure mode this mode replaced.

- **HPS agreement (pooled mode only).** Use the `<slot>hps`/`<slot>hrtotal` value
  that is non-zero and consistent across students as the single `studid = 0`
  HPS. If students disagree (legacy data is messy), take the max and flag it in
  the preview.
- Skip a mapped slot entirely (no rows) if its HPS is 0 for everyone — a 0-HPS /
  positive-total component would divide-by-zero-guard to PS 0 and *lower* IG.
  Flag it as blocking in the preview rather than silently dropping.
- A student with `0` (or absent) score for a slot gets **no row at all** for that
  slot, in either mode — matches "no data entered," not "scored zero."
- Each row: `deleted = 0`, `grades_id = <header id>`, plus whatever columns
  Module 07's `ibed_ecr_item_grade` schema requires (component code,
  sub-component code, item label, `createdby`, timestamps).

### 5. Recompute the roll-up → `gradesdetail`

Run the **same** recompute the dynamic `upload()` / `saveScores()` path uses
(Module 07), per student:

- `wwtotal/wwps/wwws`, `pttotal/ptps/ptws`, `qatotal/qaps/qaws` → re-derived
  (will match the migrated values for pooled components)
- `ig` → `round(Σ ws, 2)` (unchanged from static)
- `qg` / `transmuted_grade` → `resolveIbedTermGrade($ig, $syid, $levelid, $semid)`
  — **this is the value that can change** (config-driven `ibed_grade_point_scale`
  instead of legacy `gradetransmutation`)
- `letter_grade` → `getIbedSavedLetterGradeDisplay(...)`
- **do not** touch `gdstatus`, `headerid`, `studid`, submit/approve timestamps

Only update rows whose `gdstatus ∈ [0, 3, null]`. Re-assert "unposted" at commit
time (TOCTOU guard) even though preview already checked.

---

## Preview payload (what Commit is diffed against)

`GET /ibed-ecr/convert-from-static/preview` returns, without writing anything:

```jsonc
{
  "eligible": true,
  "mode": "convert",                    // 'convert' | 'revert' | null (button hidden)
  "reason": null,                       // set when eligible:false, or as the revert-mode note
  "warning": "Scores for \"Summative Test and Term Examination\" (50% of the grade) can't be carried over automatically because that component uses its own weighted breakdown. It will show blank until scores are re-entered in the new ECR — which will lower affected students' term grades until then.",
  "setup_source": "components_json",
  "components": [
    { "short_code": "WW", "name": "Written Works", "percentage": 30, "items": 5, "pooled": true, "mapped_slot": "WW", "skip_reason": null, "item_migration": "per_item" },
    { "short_code": "QA", "name": "Quarterly Assessment", "percentage": 20, "items": 1, "pooled": true, "mapped_slot": "QA", "skip_reason": null, "item_migration": "pooled" },
    { "short_code": "ST", "name": "Summative Test and Term Examination", "percentage": 50, "items": 3, "pooled": false, "mapped_slot": null, "skip_reason": "weighted_sub_components", "item_migration": null }
  ],
  "percentages_sum": 100,
  "slot_map": { "WW": { "component": "WW", "hps": 140, "percentage": 30, "per_item": true }, "QA": { "component": "QA", "hps": 100, "percentage": 20, "per_item": false } },
  "dropped": [ { "slot": "PT", "component": "Summative Test and Term Examination", "percentage": 50 } ],
  "students": [
    {
      "studid": 123, "name": "DELA CRUZ, JUAN M.", "gdstatus": 0,
      "old": { "ig": 88.4, "qg": 90, "letter": "O", "description": null },
      "new": { "ig": 45.2, "qg": 44, "letter": "D", "description": "Did Not Meet Expectations" },
      "changed": true
    }
  ],
  "summary": { "total": 34, "changed": 30, "unchanged": 4, "now_null": 0, "posted_blocked": 0 }
}
```

(`slot_map` values are trimmed here for brevity — the real payload doesn't drop
`sub_component`/`item_index`/`total_col`/`hps_col`, they're just internal to the
commit step and not rendered.)

`name` is resolved via the same `getStudents()` helper the dynamic ECR view uses
(right table per level: `enrolledstud`/`sh_enrolledstud`/`sh_cluster_subject_picking`),
formatted `LASTNAME, Firstname M.`; `students` is sorted by it. `old.description`
is always `null` — the legacy static controllers never wrote a descriptor for a
class's grade (only the dynamic ECR does via `getIbedSavedGradeDescription()`),
so there is nothing stored to read back; `new.description` is computed fresh
from the same function against the post-conversion grade.

The modal renders the student table by name (highlight `changed`), each grade
cell as `qg (letter - description)` when either is present, the component list
(badge each entry by `mapped_slot` / `skip_reason` — mapped, "will be empty", or
"weighted — scores dropped"), the top-level `warning` as its own callout when
present, and a required confirm checkbox whose text names any dropped components:
*"I understand N grade(s) will change and this period moves to the dynamic ECR.
Scores in &lt;component&gt; will not be migrated."* Commit is disabled until it's
ticked and `summary.posted_blocked == 0`.

**`mode: 'revert'` payloads are much shorter** — `components`/`slot_map`/
`dropped`/`students`/`summary` stay at their empty defaults; only `eligible`,
`mode`, `reason` (an informational note, not a refusal, when eligible), and
`warning` matter. `warning` here means something different than in convert
mode: it's the count of scores saved through the dynamic ECR *after* the
conversion that reverting would discard (see the Revert endpoint section
below) — the frontend folds it into the revert confirmation dialog instead of
the preview table.

---

## Endpoints

Add next to the existing `/ibed-ecr/*` block in `routes/web.php` (~line 6200):

```php
Route::get('/ibed-ecr/convert-from-static/preview', 'SuperAdminController\IBEDECRController@convertFromStaticPreview');
Route::post('/ibed-ecr/convert-from-static',         'SuperAdminController\IBEDECRController@convertFromStatic');
Route::post('/ibed-ecr/revert-to-static',            'SuperAdminController\IBEDECRController@revertToStatic');
```

Preview is a `GET` (read-only, no CSRF needed, matches the other `/ibed-ecr/view`-
style reads); commit and revert are `POST`. All three: same superadmin
middleware group the other `/ibed-ecr/*` routes sit in, params `syid, semid,
quarter, levelid, sectionid, subjid, clusterplotid?`.

### Commit (`convertFromStatic`)

1. Re-run the preview logic server-side; abort if `eligible` is false or
   `posted_blocked > 0`. Do **not** trust a client-passed diff.
2. `DB::transaction`:
   a. Snapshot the affected `gradesdetail` rows (JSON) into `ibed_ecr_conversion_log`.
   b. Insert `ibed_ecr_item_grade` HPS + score rows (§4).
   c. Recompute + update `gradesdetail` (gdstatus-guarded, §5).
   d. `grades.updatedby/updateddatetime` bump; leave `submitted` alone.
3. Return `{ status: 1, changed: N, log_id: … }`.

### Revert (`revertToStatic`)

Only if the audit row exists **and** no student in the quarter is posted/approved:

1. Soft-delete (`deleted = 1`) the `ibed_ecr_item_grade` rows for the header.
2. Restore `gradesdetail` from the audit snapshot (gdstatus-guarded).
3. Mark the audit row `reverted_at` / `reverted_by`.

After revert, `hasIbedComponents()` returns to static (no live
`ibed_ecr_item_grade` rows, legacy totals intact). Nothing else to undo — the
setup and schedule were never modified.

**The snapshot is a point-in-time capture, not a rolling backup.** It's taken
once, when the class was originally converted, and never advances — if the
class was graded normally through the dynamic ECR afterward (any `saveScores()`
call), reverting throws that work away along with the original migration,
restoring the class exactly to how it looked *before it was ever converted*.
The endpoint itself doesn't block this (only "nothing posted/approved" is a
hard guard); `buildConversionState()`'s revert branch instead compares every
live `ibed_ecr_item_grade` row's `updateddatetime`/`createddatetime` against
the conversion log's own `createddatetime`, and if anything postdates it,
returns a `warning` counting how many scores would be lost. The frontend shows
that under the Revert button and swaps the confirmation button to *"Yes,
discard those and revert"* — informed, not blocked.

### Audit table — `ibed_ecr_conversion_log` (new, Module 01 registry entry)

| Column | Purpose |
|--------|---------|
| `id` | PK |
| `grades_id` | the converted header |
| `syid, levelid, sectionid, subjid, semid, quarter` | denormalised scope |
| `setup_id` | the `subject_gradessetup` row that was read (for reference only — not modified) |
| `slot_map` | JSON `{"WW":"WW","PT":"PT","QA":"QA"}` actually used |
| `gradesdetail_snapshot` | JSON of pre-conversion rows |
| `changed_count` | grades that moved |
| `created_by`, `created_at`, `reverted_at`, `reverted_by` | lifecycle |

---

## Guards / invariants (enforce every one)

1. **Read-only on setup.** The conversion never writes `subject_gradessetup`,
   `sh_classsched`, `classsched`, `subject_plot`, or `sh_cluster_plot`. If the
   component structure is wrong, that's fixed in the grading-setup UI, not here.
2. **Scoped writes only.** Every insert/update is filtered by `grades_id` (or
   `syid+levelid+sectionid+subjid+quarter [+semid]`). Never a class-wide or
   level-wide write. Keeps kit invariant #5 intact for every *other* class.
3. **`quarter` is the term index** in term mode — the header lookup uses `quarter`
   as-is (kit invariant #2). Don't add a term column.
4. **Module 05 owns transmutation.** The recompute calls `resolveIbedTermGrade()`
   / `IbedGradeEquivalency` — never `gradetransmutation`. A static class that is
   *not* converted keeps using `gradetransmutation`, untouched (kit invariant #5).
5. **`activeConfigQuery` wrap.** Any `ibed_term_config` read added here goes
   through `IBEDGradingDefaults::activeConfigQuery()` (kit invariant #1).
6. **No status mutation.** Conversion never submits, approves, posts, or unposts.
   It refuses when a student in the quarter is already past `gdstatus` 3.
7. **Reversible until posted.** The audit snapshot is mandatory; commit fails if
   it can't be written.
8. **Idempotent-ish.** Re-running Commit on an already-converted quarter is a
   no-op that returns the existing `log_id` (detect via live `ibed_ecr_item_grade`
   rows for the header).

---

## Porting notes / gotchas

1. **Static schema varies by school — and by which static controller graded the
   class.** Some repos have `qa1..qa2` only, others `qa1..qa0`. es_ldcu itself
   has two static ECR controllers that store HPS in different places (quarter-mode
   `gradesdetail.<slot>hps` vs term-mode `grades.<slot>hrtotal` — see the central
   constraint section); check both before concluding HPS isn't recorded. **If
   truly no per-component HPS is stored anywhere, this module cannot preserve
   grades** — fall back to a "gate-flip only" mode (write a single marker
   `ibed_ecr_item_grade` row with a 0/0 placeholder so `hasIbedComponents` flips,
   show the dynamic download, make the teacher re-enter HPS + scores). Detect this
   in PREFLIGHT and tell the user which mode applies.
2. **Setup resolution must match `hasIbedComponents()` exactly.** If the target
   repo resolves the setup differently (e.g. no `sh_classsched` table), adapt both
   in lockstep or the button will offer to convert a class whose real setup has no
   `components_json`.
3. **Weighted sub-components.** The es_ldcu rule is "*every* sub-component under
   a component carries `percentage`" → weighted-average PS. Confirm the target's
   dynamic ECR uses the same rule before relying on this detection. Remember it's
   a **skip**, not a refusal — only a class where *every* scored component is
   weighted goes fully ineligible.
4. **Slot codes.** es_ldcu component `short_code`s for the DepEd three are
   `WW` / `PT` / `QA`. A target school may localise them — provide the explicit
   slot map rather than assuming.
5. **`comp4`.** es_ldcu static ECR is 3-component. If the target stores a 4th
   component's scores in `gradesdetail`, add a `COMP4` slot to Gate 3 and §4.
6. **SHS `semid`.** For levels 14/15 every query (header lookup, `gradesdetail`,
   `ibed_ecr_item_grade`) must carry `semid`. Term mode uses `semid = 0`; don't
   let a `$semid ?: 1` sneak in (see P12).
7. **Cluster electives.** When `clusterplotid` is passed, the setup lives on
   `sh_cluster_plot.gradingsetupid` and the header's `sectionid` is the
   clusterplotid — mirror `hasIbedComponents()`'s cluster branch.
8. **Don't add the button to `termgrading.blade.php`.** That modal has no dynamic
   ECR wiring; porting it is Module 07 / P9 scope, not this module.

---

## Verification

1. **Gate 1 — setup presence.**
   - A class whose resolved setup has **no** `components_json` → Convert button
     hidden. Forcing the preview returns `eligible:false, reason:"no component setup"`.
   - Configure a pooled `components_json` for that class → button appears
     (assuming static scores + unposted).
2. **Weighted component is skipped, not blocking.**
   - Setup with one scored component weighted (all sub-components carry
     `percentage`) and at least one other scored component pooled → button
     **enabled**; preview `eligible:true` with a `warning` naming the weighted
     component, that component's `skip_reason:'weighted_sub_components'`, and a
     lower `new.ig`/`new.qg` for affected students in the diff.
   - Setup where **every** scored component is weighted → button disabled,
     preview `eligible:false`, reason says nothing could be auto-migrated.
   - All-pooled setup → passes with no `warning`.
3. **Slot mapping.**
   - Setup whose components are `WW`/`PT`/`QA` → map resolves, preview lists it.
   - Rename a component's `short_code` and provide no map → preview
     `eligible:false` naming the unmatched slot.
   - Setup with an extra `RC` component and no `wwtotal`-style slot for it →
     allowed; preview flags `RC` as "will be empty".
4. **Eligibility gating.**
   - Static, has scores, unposted → button enabled.
   - Approve one student's grade for the quarter → button disabled with the unpost
     tooltip; forced preview `eligible:false`.
   - Quarter with no scores → button hidden.
   - Class already dynamic → button hidden, **Revert** shown.
5. **Preview is read-only.** Trigger preview → DB check: no new
   `ibed_ecr_item_grade` rows, `subject_gradessetup` unchanged, `sh_classsched` /
   `classsched` unchanged, `gradesdetail` unchanged.
6. **Grade preservation.** Class whose `ibed_grade_point_scale` bracket matches
   the legacy `gradetransmutation` for the relevant IG range → preview
   `changed: 0`; every `old.ig == new.ig`.
7. **Grade change surfaced.** Class where the two transmutation tables differ →
   preview lists exactly the students whose QG moves; `summary.changed` matches.
8. **Commit.**
   - Commit → class/quarter now resolves to dynamic: Class Record view renders the
     component table, dynamic download produces the item-level template with the
     migrated HPS + totals on the first item of each component, `/ecr/check-ibed`
     returns `1` for that quarter.
   - `gradesdetail`: `ig` unchanged, `qg/transmuted_grade/letter_grade` match the
     preview's `new`, `gdstatus` untouched.
   - `subject_gradessetup`, `sh_classsched`, `classsched` byte-identical to before.
   - Other quarters of the same class still resolve to **static**; another section
     of the same subject untouched.
9. **Recompute path.** Temporarily log inside `resolveIbedTermGrade()` → confirm
   it's hit during commit and `gradetransmutation` is **not** queried.
10. **Revert.**
    - Revert → `ibed_ecr_item_grade` rows for the header are `deleted = 1`,
      `gradesdetail` matches the pre-conversion snapshot, `/ecr/check-ibed`
      returns `0` again.
    - Revert is blocked once any student in the quarter is posted.
    - After converting, save a new score through the dynamic ECR, then preview
      revert → `eligible:true` with a `warning` counting that save; the
      confirmation dialog reads *"Yes, discard those and revert"*. Go through
      with it → that later save is gone, `gradesdetail` is back to the
      original pre-conversion values (not the ones from the later save).
11. **Idempotency.** Commit twice → second call returns the same `log_id`, no
    duplicate item rows.
12. **No regression.** A static class you never convert still downloads/uploads
    the static ECR and transmutes via `gradetransmutation`.


