# Module 03 — Term Grading Config Screen

The heart of the feature: the CRUD screen where you define a **term
configuration** — its academic program, school year, semester, applicable grade
levels, the **terms** (e.g. 1T / 2T / 3T), grading percentages, final-grade
formula, grade-output/transmutation settings, and the **Active/Inactive** status.
Everything downstream reads what this screen writes into `ibed_term_config` +
`ibed_term` (+ the `ibed_term_config_gradelevel` junction).

- **Screen:** `/setup/ibed-term-config`
- **Controller:** `SuperAdminController\IbedTermConfigController`

> ### Why this module is "copy the file," not "paste from this doc"
> The controller is ~1,140 lines and the view ~1,090. Hand-transcribing them into
> this guide would introduce errors and help nobody. Per the kit's premise
> ([`README.md`](README.md)), **copy the two reference files verbatim** from
> es_ldcu, then use the contract + adaptation notes below to wire and adjust them.
> Modules 01–02 inline their (small) source; this one references it.

---

## Reference implementation (es_ldcu) — copy these verbatim

| File | Path |
|------|------|
| Controller | `app/Http/Controllers/SuperAdminController/IbedTermConfigController.php` |
| View | `resources/views/superadmin/pages/setup/ibed-term-config/ibedtermconfig.blade.php` |
| Routes | `routes/web.php` (`ibed.term.config*`) |
| Sidenav | `resources/views/superadmin/inc/sidenav.blade.php` (also present in registrar / principal / academiccoor navs) |

Copy the controller to the same namespaced path and the blade to
`resources/views/superadmin/pages/setup/ibed-term-config/ibedtermconfig.blade.php`.

---

## Dependencies

- **Module 01** — every column this screen writes must exist: `ibed_term_config`
  (`isactive`, `formula_type`, `grade_point_equivalence_id`, `score_conversion_id`,
  `term_grade_display`, `final_grade_display`, `display_*`, `gradessetup_id`),
  the `ibed_term`, `ibed_term_config_gradelevel`, `ibed_grade_point_equivalence`,
  `ibed_score_conversion` tables, and the `subject_gradessetup` component columns
  (`comp4`, `comp*desc`, `components_json`, `input_mode`).
- **Module 02** — the SY term-grading toggle. A config does nothing until
  `sy.term_grading_status = 1`; this screen shows that state as the green
  **`Term Grading: ON`** badge.
- **Controller imports** (top of the reference file):
  ```php
  use Illuminate\Http\Request;
  use DB;
  use Auth;
  use App\Support\IBEDGradingDefaults;
  ```
  `IBEDGradingDefaults` arrives in **Module 05**. If you port Module 03 before 05,
  the only usage is peripheral — you can stub it or port 05 first. (The screen's
  core CRUD does not need it; it's used for previews/consistency.)
- **Standard CK tables** assumed to exist: `sy`, `semester`, `academicprogram`,
  `gradelevel`, `grades`, `gradesdetail`, `subject_plot`, `subject_gradessetup`.

---

## Routes

Add to `routes/web.php` inside the authenticated superadmin/registrar group:

```php
Route::get('/setup/ibed-term-config', 'SuperAdminController\IbedTermConfigController@index')->name('ibed.term.config');
Route::get('/setup/ibed-term-config/list', 'SuperAdminController\IbedTermConfigController@listConfigs')->name('ibed.term.config.list');
Route::get('/setup/ibed-term-config/get', 'SuperAdminController\IbedTermConfigController@getConfig')->name('ibed.term.config.get');
Route::post('/setup/ibed-term-config/save', 'SuperAdminController\IbedTermConfigController@save')->name('ibed.term.config.save');
Route::post('/setup/ibed-term-config/delete', 'SuperAdminController\IbedTermConfigController@deleteConfig')->name('ibed.term.config.delete');

// Grade component library (subject_gradessetup) — used by the config modal's component picker
Route::get('/setup/ibed-term-config/components', 'SuperAdminController\IbedTermConfigController@getGradeComponents')->name('ibed.term.config.components');
Route::get('/setup/ibed-term-config/component/{id}', 'SuperAdminController\IbedTermConfigController@getGradeComponent')->name('ibed.term.config.component.get');
Route::post('/setup/ibed-term-config/component/create', 'SuperAdminController\IbedTermConfigController@createGradeComponent')->name('ibed.term.config.component.create');
Route::post('/setup/ibed-term-config/component/update', 'SuperAdminController\IbedTermConfigController@updateGradeComponent')->name('ibed.term.config.component.update');
Route::post('/setup/ibed-term-config/component/delete', 'SuperAdminController\IbedTermConfigController@deleteGradeComponent')->name('ibed.term.config.component.delete');

// Grade Point Equivalence picker refresh (see Module 04)
Route::get('/setup/ibed-term-config/equivalence-options', 'SuperAdminController\IbedTermConfigController@equivalenceOptions')->name('ibed.term.config.equivalence.options');
```

---

## Sidenav entry

```blade
<a class="{{ Request::url() == url('/setup/ibed-term-config') ? 'active' : '' }} nav-link" href="/setup/ibed-term-config">
    <i class="nav-icon fas fa-sliders-h"></i>
    <p>Term Grading Config</p>
</a>
```

In es_ldcu this link also appears in the registrar, principal, and academic
coordinator navs — add it wherever those roles need setup access.

---

## Endpoint contract

All endpoints return JSON `{ status, message?, data? }`. `status`: `1` = ok,
`0` = validation/error, **`2` = needs a confirmation round-trip** (see save flow).

| Method | Route | Purpose |
|--------|-------|---------|
| `index()` | GET `/setup/ibed-term-config` | Renders the page. Seeds a default score conversion (`ensureDefaultScoreConversion`), loads SYs, academic programs (**excludes college id 6**), semesters, all grade levels (filtered client-side by program), active equivalences, and score conversions. |
| `listConfigs()` | GET `…/list` | JSON list of configs (optional `acadprogid`, `syid` filters), each with its `terms[]` and an `applicable_levels_label` (`"All levels"` when the junction is empty). **Returns inactive configs too** — a management list must show them. |
| `getConfig()` | GET `…/get?id=` | Single config + `terms[]` + `applicable_levels[]` (level ids) for the edit form. |
| `save()` | POST `…/save` | Create or update a config + its terms + level junction. Heavy validation; two-step confirmation (see below). |
| `deleteConfig()` | POST `…/delete` | Soft-delete a config (guarded against configs already in use). |
| `getGradeComponents()` / `getGradeComponent($id)` | GET `…/components` | Component-setup library (`subject_gradessetup`) for the modal's WW/PT/QA/component picker; `parseComponents()` normalizes `components_json`/legacy columns. |
| `createGradeComponent()` / `updateGradeComponent()` / `deleteGradeComponent()` | POST `…/component/*` | CRUD for the component library. |
| `equivalenceOptions()` | GET `…/equivalence-options` | Refreshes the Grade Point Equivalence picker after the Grade Equivalency tab (Module 04) edits rows. |

---

## `save()` — validation & flow (the part to understand)

Order of checks (each returns `status:0`, HTTP 422 on failure unless noted):

1. **School year** — `syid` must exist.
2. **Academic program** — required; **college (id 6) rejected**.
3. **SHS whole-year rule** — if `acadprogid == 5` (Senior High) and a semester is
   set → rejected. *SHS term configs must be whole-year (`semid` blank/NULL).*
4. **Description** required; **≥ 1 term** required.
5. **Per-term** — `term_no` 1–50, unique; non-empty description + short code.
   `grading_perc` (if given) 0–100. **≥ 1 active term** required.
6. **Grading-% rule** — for active terms: either *none* have a percentage (formula
   handles weighting) or *all* do and they total **100 ± 0.01**.
7. **Formula code** — validated by `validateFormulaCode()`. ⚠️ **Security:** the
   formula is `eval()`'d downstream (in grade generation), so the validator is a
   strict whitelist — only `$qN` term tokens and `0-9 + - * / ( ) .`, ≤ 500 chars,
   balanced parentheses, must reference ≥ 1 term, and **every `$qN` must be an
   active term number**. Keep this validator intact when porting.
8. **Grade-output ids** — `grade_point_equivalence_id` / `score_conversion_id`, if
   given, must exist (both optional).
9. **Applicable levels** — normalized to ints; each must belong to `acadprogid`.
   **Empty list = applies to ALL levels of the program.**
10. **Duplicate guard** — no two active configs for the same
    (program, semester, SY) may cover overlapping grade levels. Empty-level configs
    expand to the whole program, so they overlap everything in that bucket.

Two **confirmation** responses (HTTP 200, `status: 2`) — the frontend re-POSTs
with a force flag once the user says yes:

- **`requires_grade_confirmation`** — a *newly added* level already has student
  grades (`gradesdetail.qg` present) for that SY. Re-submit with `force_grades=1`.
- **`requires_plot_confirmation`** — SHS level(s) still have semester-plotted
  subjects, so terms won't take effect yet. Re-submit with `force_plot=1`.

**Persistence** (transactional): insert/update `ibed_term_config`; upsert
`ibed_term` rows and **soft-delete terms not in the payload**; sync the
`ibed_term_config_gradelevel` junction (empty submitted list ⇒ all rows
soft-deleted ⇒ "all levels").

---

## Modal fields → payload

The config modal POSTs to `…/save`:

| Field | Payload key | Notes |
|-------|-------------|-------|
| Academic Program | `acadprogid` | college (6) rejected |
| Applicable School Year | `syid` | required |
| Semester | `semid` | blank = FULL YEAR; **required blank for SHS** |
| Applicable Grade Levels | `applicable_levels[]` | empty = all levels of program |
| Description | `description` | required |
| Status | `isactive` | 1 = Active, 0 = Inactive |
| Terms (Preset: 3 Terms / 4 Quarters) | `terms[]` (`term_no`,`description`,`short_code`,`grading_perc`,`is_active`,`sort_order`,`id?`) | ≥1 active |
| Final Formula (display) | `final_formula` | human label |
| Final Formula Code | `final_formula_code` | `($q1+$q2+$q3)/3` |
| Grade component setup | `gradessetup_id` | links WW/PT/QA / components |
| Grade Point Equivalence | `grade_point_equivalence_id` | optional (Module 04) |
| Score Conversion | `score_conversion_id` | optional; a default is auto-seeded |
| Term/Final grade display | `term_grade_display`, `final_grade_display` | `raw\|transmuted\|letter\|numerical` |
| Display toggles | `display_transmuted_grade`, `display_letter_grade`, `display_final_grade`, `display_grade_remarks_description` | tinyint flags |
| Force flags (confirmation round-trips) | `force_grades`, `force_plot` | sent on re-submit |

---

## Porting notes / gotchas

1. **Academic-program ids are literal.** `5` = Senior High (whole-year rule +
   SHS plot check), `6` = College (excluded everywhere). Confirm the target's
   `academicprogram` ids match; adjust the `[6]` exclusion and `=== 5` checks if
   not.
2. **`isactive` is the Status field** — the config-level Active/Inactive from this
   session's audit. The whole grading layer honors it (Module 05's
   `activeConfigQuery`), so keep the field wired in both save and the modal.
3. **Keep `validateFormulaCode()` intact** — it is the security boundary for an
   `eval()`'d expression. Do not loosen the whitelist.
4. **The confirmation flow needs matching frontend JS.** The reference blade
   handles `status:2` by showing a SweetAlert and re-POSTing with
   `force_grades`/`force_plot`. If you rewrite the frontend, preserve that.
5. **Management endpoints intentionally show inactive configs.** `listConfigs`
   and `getConfig` do **not** filter `isactive` — that's correct (you must see
   inactive rows to manage them). Do not "fix" this.
6. **Layout/plugins.** The blade uses the superadmin AdminLTE layout, jQuery,
   DataTables, Select2, and SweetAlert2. Adapt `@extends`/`@section` names and
   confirm those plugins are loaded, same as Module 01/02.
7. **`ensureDefaultScoreConversion()`** seeds a `Percentage Score` = `(R/H)*100`
   default row on first `index()` load — harmless and idempotent.
8. **Grade component library** (`getGradeComponents` etc.) reads
   `subject_gradessetup` columns added in Module 01; if you skip component/dynamic
   ECR, these endpoints still work but the picker will just list existing setups.

---

## Verification

1. Visit `/setup/ibed-term-config`. The list renders; with Module 02 active on the
   SY, the **`Term Grading: ON`** badge shows.
2. **Add Configuration** → pick a program (e.g. `HIGH SCHOOL`), the active SY,
   leave Semester blank, choose a level, **Preset: 3 Terms**, set the formula
   `($q1+$q2+$q3)/3`, Status = Active → **Save**. Row appears with
   `applicable_levels_label` and its terms.
3. **Grading-% rule** — give the 3 terms 33/33/34 → saves; make them 30/30/30 →
   rejected ("must total 100%").
4. **SHS rule** — pick `SENIOR HIGH SCHOOL` with a Semester set → rejected
   ("must cover the WHOLE YEAR").
5. **Duplicate guard** — create a second config for the same program/SY/level →
   rejected with the conflicting level names.
6. **Confirmation flow** — target a level that already has grades → `status:2`
   grade-confirmation dialog; confirm → saves with `force_grades=1`.
7. DB check:
   ```sql
   SELECT id, acadprogid, semid, description, isactive, final_formula_code FROM ibed_term_config WHERE deleted=0;
   SELECT config_id, term_no, short_code, grading_perc, is_active FROM ibed_term WHERE deleted=0 ORDER BY config_id, sort_order;
   SELECT config_id, levelid FROM ibed_term_config_gradelevel WHERE deleted=0;
   ```
8. Set a config to **Inactive**, reopen the list → it still appears (management
   view), but term resolution (Module 05) will ignore it.

Once configs save and validate correctly, proceed to **Module 04 — Grade
Equivalency / transmutation tables** (the `grade_point_equivalence_id` /
`score_conversion_id` this screen references).
