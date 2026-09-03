# Module 04 — Grade Equivalency & Score Conversion

The **transmutation layer**. Two setup surfaces that feed the term config's
`grade_point_equivalence_id` / `score_conversion_id` (Module 03):

- **A) Grade Point Equivalence** (`ibed_grade_point_equivalence`) + its child
  **scale rows** (`ibed_grade_point_scale`) — a repeater mapping percent ranges to
  grade points / letters / transmuted grades / remarks / pass-fail.
- **B) Score Conversion** (`ibed_score_conversion`) — the PS (percentage score)
  formula, e.g. `(R/H)*100`, where `R` = raw, `H` = highest possible.

This is **setup only** — it defines the tables the ECR and grade pipeline read; it
does not itself compute grades.

- **Standalone screen:** `/setup/ibed-grade-equivalency`
- **Also embedded** as the **Grade Equivalency tab** inside the Module 03 Term
  Grading Config page (same partials, `@include`d).
- **Controller:** `SuperAdminController\IbedGradeEquivalencyController`

> Like Module 03, this is a **copy-the-files** module (593-line controller + ~960
> lines of blade/partials). Copy the reference files verbatim; wire and adapt with
> the contract below. The two small, security-relevant Support helpers are inlined
> here so the module stands even if you port it before Module 05.

---

## Reference implementation (es_ldcu) — copy these verbatim

| File | Path |
|------|------|
| Controller | `app/Http/Controllers/SuperAdminController/IbedGradeEquivalencyController.php` |
| Wrapper view | `resources/views/superadmin/pages/setup/ibed-term-config/ibedgradeequivalency.blade.php` |
| Body partial | `resources/views/superadmin/pages/setup/ibed-term-config/partials/_ibedgradeequivalency_body.blade.php` |
| Scripts partial | `resources/views/superadmin/pages/setup/ibed-term-config/partials/_ibedgradeequivalency_scripts.blade.php` |
| Styles partial | `resources/views/superadmin/pages/setup/ibed-term-config/partials/_ibedgradeequivalency_styles.blade.php` |
| Seed (optional) | `resources/views/superadmin/pages/setup/ibed-term-config/partials/grade-equivalence-seed/` — starter equivalence templates, if present |
| Routes | `routes/web.php` (`ibed.grade.equivalency*`, `ibed.score.conversion*`) |

The **3 partials are shared**: the standalone wrapper `@include`s all three, and
the Module 03 config page `@include`s the same three to render its "Grade
Equivalency" tab. Copy the partials once; both pages use them.

---

## Dependencies

- **Module 01** — tables `ibed_grade_point_equivalence`, `ibed_grade_point_scale`,
  `ibed_score_conversion` (all created by the migration page).
- **Two static helpers from `App\Support\IbedGradeEquivalency`** (full class is
  Module 05, but this module needs exactly these two — inlined below):
  `isSafeScoreConversionFormula()` and `parsePercentRangeBounds()`.
- **Controller imports:**
  ```php
  use Illuminate\Http\Request;
  use App\Support\IbedGradeEquivalency;
  use DB;
  use Auth;
  ```
- Standard CK tables: `sy`, `semester`, `academicprogram`, `gradelevel`.

### Required Support helpers (inline these if porting before Module 05)

Add to `app/Support/IbedGradeEquivalency.php` (or a temporary holder):

```php
/**
 * Whitelist validator for a score-conversion formula.
 * Allows ONLY the variables R and H, digits, whitespace and + - * / ( ) . tokens.
 */
public static function isSafeScoreConversionFormula(?string $formula): bool
{
    if ($formula === null || trim($formula) === '') {
        return false;
    }
    // Substitute the only two allowed identifiers, then ensure nothing but the
    // arithmetic whitelist remains (rejects other letters/functions/quotes/etc.).
    $expr = str_replace(['R', 'H'], ['1', '1'], strtoupper($formula));
    return preg_match('/^[\d\s\.\+\-\*\/\(\)]+$/', $expr) === 1;
}

/**
 * Parse a percent_equivalence string into [min, max] numeric bounds.
 * Supports ranges ("75-85"), open-ended ("90-" / "below 75" / "90 and above"),
 * and single values ("100"). Returns [null, null] when unparseable.
 */
public static function parsePercentRangeBounds(?string $percent): array
{
    $percent = trim((string) $percent);
    if ($percent === '') {
        return [null, null];
    }
    preg_match_all('/\d+(?:\.\d+)?/', $percent, $matches);
    $numbers = array_map('floatval', $matches[0] ?? []);
    $lower   = strtolower($percent);

    if (strpos($lower, 'below') !== false && count($numbers) >= 1) {
        return [null, $numbers[0]];
    }
    if (strpos($lower, 'above') !== false && count($numbers) >= 1) {
        return [$numbers[0], null];
    }
    if (count($numbers) === 1 && preg_match('/\d+(?:\.\d+)?\s*-\s*$/', $percent)) {
        return [$numbers[0], null];
    }
    if (count($numbers) >= 2) {
        return [$numbers[0], $numbers[1]];
    }
    if (count($numbers) === 1) {
        return [$numbers[0], $numbers[0]];
    }
    return [null, null];
}
```

---

## Routes

Add to `routes/web.php` in the authenticated superadmin/registrar group:

```php
// A) Grade point equivalence + scale rows
Route::get('/setup/ibed-grade-equivalency', 'SuperAdminController\IbedGradeEquivalencyController@index')->name('ibed.grade.equivalency');
Route::get('/setup/ibed-grade-equivalency/list', 'SuperAdminController\IbedGradeEquivalencyController@listEquivalences')->name('ibed.grade.equivalency.list');
Route::get('/setup/ibed-grade-equivalency/get', 'SuperAdminController\IbedGradeEquivalencyController@getEquivalence')->name('ibed.grade.equivalency.get');
Route::post('/setup/ibed-grade-equivalency/save', 'SuperAdminController\IbedGradeEquivalencyController@saveEquivalence')->name('ibed.grade.equivalency.save');
Route::post('/setup/ibed-grade-equivalency/delete', 'SuperAdminController\IbedGradeEquivalencyController@deleteEquivalence')->name('ibed.grade.equivalency.delete');

// B) Score conversion (PS formula)
Route::get('/setup/ibed-score-conversion/list', 'SuperAdminController\IbedGradeEquivalencyController@listScoreConversions')->name('ibed.score.conversion.list');
Route::post('/setup/ibed-score-conversion/save', 'SuperAdminController\IbedGradeEquivalencyController@saveScoreConversion')->name('ibed.score.conversion.save');
Route::post('/setup/ibed-score-conversion/delete', 'SuperAdminController\IbedGradeEquivalencyController@deleteScoreConversion')->name('ibed.score.conversion.delete');
```

The **Term Grading Config** page also refreshes the equivalence picker via
`…/ibed-term-config/equivalence-options` (declared in Module 03).

> **Sidenav:** the reference has no dedicated sidenav link — the screen is reached
> as the **Grade Equivalency tab** on the Term Grading Config page. Add a standalone
> nav link to `/setup/ibed-grade-equivalency` only if you want it separately.

---

## Table schema (created in Module 01)

| Table | Key columns |
|-------|-------------|
| `ibed_grade_point_equivalence` | `grade_description`, `syid`, `acadprogid`, `levelid`, `semid`, `isactive`, `apply_transmutation_to_terms`, soft-delete/audit |
| `ibed_grade_point_scale` | `grade_point_equivalency` (FK → equivalence id), `percent_equivalence`, `grade_point`, `letter_equivalence`, `transmuted_grade`, `grade_remarks`, `is_failed` |
| `ibed_score_conversion` | `name`, `formula`, `is_default` |

`apply_transmutation_to_terms` decides whether the equivalence transmutes per-term
grades (1) or only the final (0) — the ECR reads this to color/transmute cells.

---

## Endpoint contract

JSON `{ status, message?, data? }`. `status`: `1` ok, `0` error.

| Method | Route | Purpose |
|--------|-------|---------|
| `index()` | GET `/setup/ibed-grade-equivalency` | Renders the page; **seeds a default score conversion** (`ensureDefaultScoreConversion` → `Percentage Score = (R/H)*100`); loads program/semester/level pickers (college id 6 excluded). |
| `listEquivalences()` | GET `…/list?acadprogid=` | Equivalences for the **active SY** (+ optional program filter), each with its `scales[]`. |
| `getEquivalence()` | GET `…/get?id=` | Single equivalence + `scales[]` for edit. |
| `saveEquivalence()` | POST `…/save` | Create/update equivalence + scale rows (repeater); soft-deletes scales not in payload. |
| `deleteEquivalence()` | POST `…/delete` | Soft-delete equivalence + all its scales. |
| `listScoreConversions()` | GET `/setup/ibed-score-conversion/list` | All score conversions (default first). |
| `saveScoreConversion()` | POST `…/save` | Create/update a PS formula row (whitelist-validated); enforces single default. |
| `deleteScoreConversion()` | POST `…/delete` | Soft-delete a conversion — **the default row cannot be deleted**. |

---

## `saveEquivalence()` — validation & flow

1. Active SY required (equivalences are scoped to the active SY on create).
2. `grade_description` required; **college (acadprogid 6) rejected**.
3. **≥ 1 scale row** required. Per row:
   - `percent_equivalence` required and must parse via
     `parsePercentRangeBounds()` to at least one bound; if both bounds parse,
     `min ≤ max`. Accepts `"75-85"`, open `"90-"` / `"below 75"` / `"90 and above"`,
     or single `"100"`.
   - `grade_point` required and numeric (e.g. `1.0`).
   - `letter_equivalence`, `transmuted_grade`, `grade_remarks` optional;
     `is_failed` tinyint flag.
4. **Persist** (transactional): insert/update the equivalence header; upsert scale
   rows and **soft-delete scales not in the payload**.

## `saveScoreConversion()` — validation & flow

1. `name` required (≤150). `formula` required (≤255).
2. ⚠️ **Security:** `formula` is `eval()`'d downstream, so it must pass
   `IbedGradeEquivalency::isSafeScoreConversionFormula()` — only `R`, `H`, digits,
   and `+ - * / ( ) .`. **Keep this check intact.**
3. **Single default** — saving with `is_default=1` unsets every other row's default.
4. `deleteScoreConversion()` refuses to delete the default (a default must always
   exist; `ensureDefaultScoreConversion()` guarantees one).

---

## Porting notes / gotchas

1. **Partials are shared with Module 03.** The same `_ibedgradeequivalency_*`
   partials render both the standalone page and the config page's tab. The scripts
   partial is written to **not** redeclare `CSRF_TOKEN` / `const Toast` (the
   wrapper/config page declares those once) — otherwise you get a fatal
   `const Toast` redeclaration when both live on one page. Preserve that split when
   adapting.
2. **Layout auto-selects** by portal/user type in the wrapper blade
   (`registrar.layouts.app` vs `superadmin.layouts.app2`). Adapt those layout names
   to the target project.
3. **Plugins:** DataTables + SweetAlert2, loaded by the layout. Confirm present.
4. **Keep `isSafeScoreConversionFormula()` strict** — security boundary for an
   `eval()`'d formula, same rule class as Module 03's `validateFormulaCode()`.
5. **`ensureDefaultScoreConversion()`** seeds `(R/H)*100` on first load — idempotent.
6. **Equivalences are active-SY scoped on create** (`listEquivalences`/create use
   the active SY). If a target needs cross-SY equivalences, adjust the scope.
7. **`apply_transmutation_to_terms`** must be surfaced in the form — the ECR and
   term/final display depend on it (Modules 07–08).
8. **College (id 6) excluded** everywhere here too; confirm the target's
   `academicprogram` ids.

---

## Verification

1. Open `/setup/ibed-grade-equivalency` (or the Grade Equivalency tab on the config
   page). A default **Percentage Score** conversion already exists.
2. **Add an equivalence** — description, program, add scale rows like
   `90-100 → 1.0`, `85-89 → 1.25`, … `below 75 → 5.0 (is_failed)`. Save → it lists
   with its scales.
3. **Percent parsing** — a row `"75-85"` saves; `"85-75"` is rejected
   (lower > upper); a non-numeric grade point is rejected.
4. **Score conversion** — add `(R/H)*100` → saves. Try `system('x')` or a formula
   with letters other than R/H → rejected.
5. **Single default** — mark a second conversion default → the first loses its
   default flag. Try to delete the default → refused.
6. Back on **Term Grading Config** (Module 03), the new equivalence appears in the
   **Grade Point Equivalence** picker (via `equivalence-options`) and can be linked
   to a config.
7. DB check:
   ```sql
   SELECT id, grade_description, acadprogid, isactive, apply_transmutation_to_terms FROM ibed_grade_point_equivalence WHERE deleted=0;
   SELECT grade_point_equivalency, percent_equivalence, grade_point, is_failed FROM ibed_grade_point_scale WHERE deleted=0 ORDER BY grade_point_equivalency, id;
   SELECT id, name, formula, is_default FROM ibed_score_conversion WHERE deleted=0;
   ```

With transmutation tables in place, proceed to **Module 05 — Term resolution
helpers** (`IBEDGradingDefaults` + `IbedGradeEquivalency`), the shared brain that
every grading screen reads.

---

## Changelog

### 2026-09-01 — DepEd Strengthening quick-fill preset

Added a third scale-row preset button, **DepEd Strengthening**, alongside the
existing **DepEd Descriptors** and **DepEd Transmutation** presets in the Add/Edit
Grade Equivalence modal. Front-end only — it just fills the scale-rows repeater;
the save path and DB schema are unchanged.

**Files touched (both partials, shared by the standalone page and the Module 03 tab):**

| File | Change |
|------|--------|
| `partials/_ibedgradeequivalency_body.blade.php` | New button `#btnEqPresetDepedStrengthening` in the scales toolbar, between "DepEd Transmutation" and "Add Scale Row". |
| `partials/_ibedgradeequivalency_scripts.blade.php` | Added `getStrengtheningRemark()`, `getStrengtheningLetter()`, the 41-row `DEPED_STRENGTHENING_TABLE`, `buildDepedStrengtheningRows()`, and the `#btnEqPresetDepedStrengthening` click handler (confirm → `applyEqPreset`). |

**What it fills** — the DepEd Strengthening adjusted transmutation table (41 rows),
mapping initial-grade ranges to transmuted grades, with:
- Passing mark **75** (rows transmuting below 75 flagged `is_failed`).
- Letters A/B/C/D/E and Filipino qualitative descriptors
  (Advancing / Benchmarking / Connecting / Developing / Emerging).
- Ranges stored as verbatim 2-decimal strings (e.g. `99.50-100.00`), which
  `parsePercentRangeBounds()` handles unchanged.

**Porting note:** this reuses the existing preset plumbing (`applyEqPreset`,
`scaleRowHtml`, `validateEquivalenceForm`). No routes, controller, migration, or
Support-helper changes are required — copy the two partials and the button/handler
come with them. It does **not** include the unrelated `syncTermConfigEquivalencyOptions`
refresh refactor some downstream repos carry; the standard `refreshEquivalenceOptions`
call path is left intact.
