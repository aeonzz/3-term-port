# Module 05 — Term Resolution Helpers (the shared brain)

Two pure-logic Support classes that **every grading screen reads**. No routes, no
views — just static helpers. They answer the two questions the whole feature hangs
on: *"is this level in term mode, and what are its terms?"* and *"how do I
transmute/display a grade for this scope?"*

- `App\Support\IBEDGradingDefaults` — term/period resolution + component-grading
  defaults + the **active-config choke point**.
- `App\Support\IbedGradeEquivalency` — transmutation, score conversion, display
  settings, and per-level config applicability.

> **Copy both files verbatim** from the reference (1,400 lines combined of tightly
> tested logic). Do **not** re-transcribe by hand. This guide is the API contract +
> the rules you must preserve when adapting.

---

## Reference implementation (es_ldcu) — copy verbatim

| File | Path | Lines |
|------|------|-------|
| `IBEDGradingDefaults` | `app/Support/IBEDGradingDefaults.php` | ~800 |
| `IbedGradeEquivalency` | `app/Support/IbedGradeEquivalency.php` | ~600 |

Copy to the same `app/Support/` namespace.

---

## Where this module sits

- **Depends on Module 01** schema: `ibed_term_config` (+ `isactive`, display/format
  columns, `grade_point_equivalence_id`, `score_conversion_id`), `ibed_term`,
  `ibed_term_config_gradelevel`, `ibed_grade_point_equivalence`,
  `ibed_grade_point_scale`, `ibed_score_conversion`, `subject_gradessetup`
  component columns, and `sy.term_grading_status`.
- **Consumed by** Modules 03 & 04 (already reference it), and everything after:
  06 (subject plot), 07 (teacher ECR), 08 (final grading / master sheets), 09
  (report cards / SF9). Also by `GenerateGrade`, `StudentGradeEvaluation`,
  `TeacherGradingV2`, `MasterSheetController`, `FormReportsController`.
- **Standard tables:** `sy`, `gradelevel`, `subject_plot`.

Both classes **degrade gracefully** when the schema isn't present yet
(`Schema::hasColumn`/`hasTable` guards + `schemaAvailable()`), returning the safe
4-quarter / semester defaults — so partial ports don't fatal.

---

## Class A — `IBEDGradingDefaults`

### Term / period resolution

| Method | Signature | Purpose |
|--------|-----------|---------|
| `resolveConfigForLevel` | `($syid, $acadprogid, $levelid)` | The one config resolver. Prefers a whole-year (`semid IS NULL`) **active** config that applies to the level (`configAppliesToLevel`); level-specific beats all-levels. Routes through `activeConfigQuery()`. |
| `resolveActiveTerms` | `($syid, $levelid, $semid = null): array` | `['config', 'terms', 'formula_type', 'final_formula', 'final_formula_code']`. Falls back to `defaultTerms()` + `defaultFormula()` (4 quarters, plain average) when no config resolves. Config-only — **no** subject-plot gate. |
| `resolveTermLabelsForLevel` | `($syid, $levelid): array` | **JHS gate.** `['isTermGrading', 'termCount', 'terms']`. See the gate box below. Excludes SHS 14/15. |
| `resolveShsPeriods` | `($syid, $levelid, $strandid = null): array` | **SHS gate.** `['mode', 'isTermMode', 'configId', 'termCount', 'terms']`. Two-gate (config **and** term-plotting). See box. |
| `shsConfiguredTerms` | `($syid, $levelid): array` | SHS config-only resolution (setup layer): terms if an applicable active config exists, **without** requiring term-plotting yet. |
| `shsHasTermPlotting` | `($syid, $levelid): bool` | True only when **every** `subject_plot` row for the level is whole-year (`semid IS NULL`) and none is semester-scoped. |
| `shsTermLevels` | `($syid): array` | Which of `[14,15]` are in term mode (via `resolveShsPeriods`). |
| `resolvePlotTermNos` | `($plotTermid, array $shsPeriods): array` | Which term_no(s) a subject plot's grades belong to (whole-year ⇒ all active terms; specific term ⇒ that one; foreign ⇒ all, defensive). |
| `semesterScope` | `($semid, array $termLevels, $semidColumn, $levelColumn)` | Closure for scoping queries: term-mode levels are whole-year (`semid` NULL), non-term levels still filter by semester. |
| `defaultTerms` / `defaultFormula` | `()` | The 4-quarter fallback + `($q1+$q2+$q3+$q4)/4`. |

### The active-config choke point ⭐ (this is where the "Inactive" status is honored)

```php
public static function activeConfigQuery($query, string $alias = null)
```

Adds `isactive = 1` to any `ibed_term_config` query **iff** the column exists
(memoized `Schema::hasColumn` check, so it's cheap in per-student loops). Every
resolver funnels through it, so a config parked **Inactive** is disregarded
everywhere. Mutates and returns `$query`, so it can wrap a builder inline:

```php
$cfg = IBEDGradingDefaults::activeConfigQuery(
    DB::table('ibed_term_config')->where('syid', $syid)->where('deleted', 0)
)->first();
```

> **Consumers must route through this** (or `IbedGradeEquivalency::whereConfigActive`).
> Any direct `ibed_term_config` read that only filters `deleted=0` will pick up
> inactive configs — the exact bug fixed in es_ldcu across grade generation, report
> cards, master sheets, teacher grading, ECR and the grading blades. When porting
> Modules 07–09, wrap every config read with `activeConfigQuery()`.

### Component grading defaults (for the dynamic/component ECR, Module 07)

| Method | Purpose |
|--------|---------|
| `componentsFromSetup($setup)` | Canonical components array from `subject_gradessetup` (`components_json` → legacy `ww/pt/qa/comp4` → defaults WW30/PT30/QA40). |
| `inputModeFromSetup($setup)` | `'component_scores'` vs `'raw_grade'`. |
| `withComponentFallback($setup)` / `fallbackGradeSetup()` / `defaultComponents()` | Safe fallbacks when a setup row is missing/blank. |
| `allowScoreAboveHps(): bool` | School-wide policy memo (score may exceed item HPS?) — read via `schoolinfo.allow_score_above_hps`, defaults strict/off. |

> #### GATE — Junior levels (`resolveTermLabelsForLevel`)
> `isTermGrading = true` requires **all**: valid `$syid/$levelid`; **not** SHS 14/15;
> `sy.term_grading_status == 1`; a resolvable acadprog; an **active** applicable
> `ibed_term_config` (via `resolveConfigForLevel`); **≥ 1 active `ibed_term`**.
> No subject-plot condition — junior levels are inherently whole-year.

> #### GATE — Senior High (`resolveShsPeriods`)
> `isTermMode = true` requires **both**:
> 1. **Config gate** (`shsConfiguredTerms`): `term_grading_status == 1` + active
>    whole-year config + ≥ 1 active term; **and**
> 2. **Plotting gate** (`shsHasTermPlotting`): every SHS subject in `subject_plot`
>    is whole-year (`semid IS NULL`). One semester-scoped subject ⇒ stays semester.

---

## Class B — `IbedGradeEquivalency`

### Config-active guard (mirror of Class A's choke point)

```php
private static function whereConfigActive($query, string $alias = null)  // conditional isactive=1
```

Used by every config read in this class (`resolveEquivalence`,
`resolveDisplaySettings`, `configAppliesToLevel`, `resolveScoreConversionFormula`).

### Transmutation & display pipeline

| Method | Signature | Purpose |
|--------|-----------|---------|
| `configAppliesToLevel` | `($configId, $levelid): bool` | **Per-config Active choke point.** False for soft-deleted/inactive configs; true when the level is in scope (or the config is unscoped = all levels). |
| `resolveEquivalence` | `(array $scope, $target='term')` | The `ibed_grade_point_equivalence` chosen by the config (`grade_point_equivalence_id`), else a scope-matched active fallback. One equivalence per config; raw-vs-transmuted is a *display* choice, not a split. |
| `findScaleByEquivalenceId` / `findEquivalencyScale` | `(float $grade, $equivalenceId)` / `($grade, $scope, $target)` | Match the `ibed_grade_point_scale` row whose percent range contains `$grade` (via `parsePercentRangeBounds`). |
| `transmute` | `($grade, $scope, $target='term')` | Scale's `transmuted_grade` (numeric or string), else the grade rounded 2dp. **No legacy `gradetransmutation` fallback** — fully decoupled. |
| `resolveTermGrade` | `($grade, $scope)` | Honors `term_grade_display`: `'raw'` short-circuits, else transmute. |
| `applyScoreConversion` | `(float $raw, float $hps, ?string $formula): float` | Computes PS. ⚠️ `eval()`'d — double whitelist (formula + substituted expr), falls back to `(R/H)*100` on anything unsafe or on throw. |
| `resolveScoreConversionFormula` | `(array $scope): string` | Config-linked formula if safe, else default-flagged row, else `(R/H)*100`. Always whitelist-safe. |
| `resolveDisplaySettings` | `(array $scope)` | The config's display columns (`term_grade_display`, `final_grade_display`, `display_*`) for the scope. |
| `formatDisplay` | `($value, $mode, $scaleRow=null, $appendRemarks=false)` | Render a grade by mode: `raw` / `transmuted` / `letter` / `numerical` / `remarks`; blank fields fall back to raw. |
| `isSafeScoreConversionFormula` / `parsePercentRangeBounds` | — | Validators (also inlined in Module 04). |
| `normalizeScope` | `(array $scope): array` | Canonicalizes `['syid','acadprogid','levelid','semid']`. |

`$scope` shape used throughout: `['syid' => , 'acadprogid' => , 'levelid' => , 'semid' => ]`.

> **Transmutation split — this class is for dynamic/term classes only.** These
> helpers deliberately have **no `gradetransmutation` fallback**. A **static/legacy**
> class (no component setup, no applicable term config) must keep using the
> **existing** grading computation and the **existing `gradetransmutation`** table —
> untouched. Only dynamic/term classes route through `IbedGradeEquivalency`. Don't
> wire these helpers into the legacy static path; leaving it alone is the point
> (feature is additive, non-destructive).

---

## Porting notes / gotchas

1. **`isactive` guards are conditional by design.** Both `activeConfigQuery()` and
   `whereConfigActive()` gate on `Schema::hasColumn('ibed_term_config','isactive')`
   so multi-school databases that lack the column don't fatal — they just skip the
   filter. Keep the conditional form; **never** hardcode a bare `->where('isactive',1)`
   in a consumer.
2. **Memoization.** `activeConfigQuery()` caches the column check in a static; keep
   that — it's called in per-student loops (master sheets, grade generation).
3. **Keep the `eval()` whitelists intact** — `applyScoreConversion` and
   `isSafeScoreConversionFormula` are security boundaries. Do not loosen.
4. **No legacy `gradetransmutation` fallback.** This layer is decoupled from the old
   transmutation table on purpose. If the target still relies on the legacy table
   elsewhere, keep the two paths separate.
5. **Level ids `14`/`15` (SHS Grade 11/12) and acadprog `5`/`6`** are literal. Verify
   against the target's `gradelevel` / `academicprogram` ids and adjust the SHS
   checks + college exclusion if needed.
6. **`term_grading_status` is the master gate** — every JHS/SHS resolver returns the
   OFF/semester default unless `sy.term_grading_status == 1` (Module 02).
7. **Graceful degradation is a feature.** The `schemaAvailable()` / `hasTable` /
   `hasColumn` guards let you port this module before all consumers exist. Preserve
   them.

---

## Verification

No UI — verify by exercising the API and by watching downstream modules resolve.

1. **Syntax:** `php -l app/Support/IBEDGradingDefaults.php` and
   `php -l app/Support/IbedGradeEquivalency.php` → no errors.
2. **JHS gate** — with `term_grading_status = 1` and an active config for a junior
   level, a quick route/tinker:
   ```php
   \App\Support\IBEDGradingDefaults::resolveTermLabelsForLevel($syid, $jhsLevelId);
   // => ['isTermGrading' => true, 'termCount' => 3, 'terms' => [ {term_no, label}, ... ]]
   ```
3. **SHS gate** — before whole-year plotting, `resolveShsPeriods($syid, 14)` returns
   `isTermMode = false`; after Module P2 conversion, `true` with the terms.
4. **Active-config choke point** — set a config **Inactive**;
   `resolveConfigForLevel(...)` and `configAppliesToLevel($id, $level)` must now
   ignore it (return null / false). Flip back to Active → it resolves again.
5. **Transmutation** — with an equivalence linked to the config,
   `IbedGradeEquivalency::transmute(88, $scope, 'term')` returns the matching scale's
   transmuted grade; an unlinked scope returns the grade rounded.
6. **Score conversion** — `applyScoreConversion(45, 50, '(R/H)*100')` → `90.0`;
   `applyScoreConversion(45, 50, 'system("x")')` → falls back to `90.0` (unsafe
   formula rejected).

> A tiny throwaway debug route (like the one used during the es_ldcu investigation)
> is the fastest way to eyeball these — remove it after.

Once resolution is proven, proceed to **Module P2 — Subject Plot term / whole-year
plotting**, which supplies the SHS plotting gate this module reads.
