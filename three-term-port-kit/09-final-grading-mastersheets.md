# Module 09 — Final Grading & Master Sheets (term columns)

The **final-grade read surfaces**. Two things consume the per-period grades from
`gradesdetail` and present them with **term columns** (1T/2T/3T) instead of
quarters, plus the computed **final grade**:

- **Final Grading** — `/teacher/finalgrades` (`finalgrade.blade.php` +
  `TeacherFinalGrade` controller): per-class term grades + final + submit/post.
- **Master Sheets** — `MasterSheetController` (Excel/PDF class/consolidated
  sheets): term-column report generation.
- **Final-grade computation** — `App\GenerateGrade` applies the config's
  `final_formula_code` over the term grades.

> Copy-the-files module (~9,000 lines combined). `TeacherFinalGrade`,
> `MasterSheetController`, `GenerateGrade`, and `finalgrade.blade.php` mostly
> pre-exist in a CK ERP — you add the **term-awareness** and **`isactive`-safe
> config reads** documented here.

---

## Reference implementation (es_ldcu)

| Piece | Path |
|-------|------|
| Final grading view | `resources/views/teacher/grading/finalgrade.blade.php` (~2,400 lines) |
| Final grading controller | `app/Http/Controllers/TeacherControllers/TeacherFinalGrade.php` (`teachingload`, `gradestatus`, `enrolled_learners`, `save_grades`, `submit_grades`) |
| Master sheets | `app/Http/Controllers/TeacherControllers/MasterSheetController.php` (~4,300 lines) |
| Final-grade computation | `app/GenerateGrade.php` (`computeFinalFromFormula`, `evaluateArithmetic`) |
| Routes | `routes/web.php` — `/teacher/finalgrades*`, `grades/report/mastersheet*` |

---

## Dependencies

- **Module 05** — `IBEDGradingDefaults::activeConfigQuery` (wrap every config read),
  `resolveShsPeriods` / `resolveTermLabelsForLevel` / `shsConfiguredTerms`, and
  `IbedGradeEquivalency::configAppliesToLevel` / `transmute`.
- **Module 07** — scores already in `gradesdetail` (`ig`/`qg` per period, where
  `grades.quarter` doubles as the **term_no** in term mode).
- **Module 08** — the on-screen grade view; final grading is the submit/post layer
  on top.
- Standard tables: `grades`, `gradesdetail`, `gradelevel`, `sy`, `ibed_term_config`,
  `ibed_term`.

---

## How term columns get built

Both surfaces build a **per-academic-program term map** from the active config,
then render one column per term. The pattern (from `finalgrade.blade.php`, mirrored
in `MasterSheetController`):

```php
// 1) Resolve the config — ALWAYS through the isactive guard (Module 05)
$termConfigs = \App\Support\IBEDGradingDefaults::activeConfigQuery(
    DB::table('ibed_term_config')->where('syid', $termSy->id)->where('deleted', 0)
        ->orderByRaw('CASE WHEN semid IS NULL THEN 0 ELSE 1 END ASC')
)->get();

// 2) For each config, load its active terms
$terms = DB::table('ibed_term')->where('config_id', $cfg->id)
    ->where('is_active', 1)->where('deleted', 0)
    ->orderBy('sort_order')->orderBy('term_no')->get();

// 3) Map by academic program; a level uses it only if the config applies to it
if (\App\Support\IbedGradeEquivalency::configAppliesToLevel($cfg->id, $level->id)) {
    // render columns: 1T / 2T / 3T (labels = short_code ?: description ?: ordinal.' Term')
}
```

- The map is keyed by `acadprogid`; a grade level renders term columns only when
  `configAppliesToLevel($configId, $levelid)` is true (else it stays on quarters).
- Column data per term reads `gradesdetail` for `grades.quarter == term_no`
  (the same term_no==quarter reuse from Module 08).

---

## Final-grade computation — `GenerateGrade`

`GenerateGrade` loads the config's `final_formula_code` + active term_nos (through
`activeConfigQuery`), collects each term's grade, and computes the final:

```php
$termConfig = \App\Support\IBEDGradingDefaults::activeConfigQuery(
    DB::table('ibed_term_config')->where('syid', $activeSy->id)
        ->where('acadprogid', $acadprogid)->whereNull('semid')->where('deleted', 0)
)->first();
$formulaCode   = $termConfig->final_formula_code ?? null;   // e.g. ($q1+$q2+$q3)/3
$activeTermNos = /* ibed_term term_nos, else [1,2,3,4] */;

$gradesByTerm = [];
foreach ($activeTermNos as $n) { $gradesByTerm[$n] = $quarterGrades->{'quarter'.$n} ?? null; }
$final = self::computeFinalFromFormula($gradesByTerm, $formulaCode);
```

### `computeFinalFromFormula($gradesByTermNo, $formulaCode)` — copy verbatim

```php
public static function computeFinalFromFormula(array $gradesByTermNo, ?string $formulaCode): ?float
{
    if (!$formulaCode) {
        $nonNull = array_filter($gradesByTermNo, function ($v) { return $v !== null; });
        if (empty($nonNull)) return null;
        return round(array_sum($nonNull) / count($nonNull), 2);   // no formula => plain average
    }

    // SECURITY: the formula is stored data. It is PARSED as arithmetic below and NEVER
    // executed. Whitelist first gate: $qN terms, numbers, + - * / ( ) and spaces.
    if (!preg_match('/^[\s0-9\.\+\-\*\/\(\)]*(\$q\d+[\s0-9\.\+\-\*\/\(\)]*)+$/', $formulaCode)) {
        return null;
    }

    // Every referenced term must have a grade, else final is not yet computable.
    preg_match_all('/\$q(\d+)/', $formulaCode, $m);
    foreach (array_unique(array_map('intval', $m[1])) as $n) {
        if (!isset($gradesByTermNo[$n]) || $gradesByTermNo[$n] === null) return null;
    }

    $result = self::evaluateArithmetic($formulaCode, $gradesByTermNo);
    return $result === null ? null : round($result, 2);
}
```

> **Important:** unlike the score-conversion formula (Module 04, `eval`'d),
> the final formula is **parsed by `evaluateArithmetic`, never executed** — copy
> `evaluateArithmetic` too (a small shunting-yard/recursive arithmetic evaluator in
> `GenerateGrade`). No formula ⇒ plain average of the term grades. A missing term
> grade ⇒ final is `null` (not yet complete).

---

## Controller endpoints (final grading)

| Method | Route | Purpose |
|--------|-------|---------|
| `teachingload` | GET `teacher/get/teacheingload` | Classes for the teacher (term/quarter aware). |
| `gradestatus` | GET `teacher/get/gradestatus` | Per-period submit/post status. |
| `enrolled_learners` | GET `teacher/get/students` | Roster + per-term grades from `gradesdetail`. |
| `save_grades` | GET `teacher/finalgrades/savegrades` | Persist entered grades. |
| `submit_grades` | GET `teacher/submit/grades` | Submit/lock for posting. |

The view (`finalgrade.blade.php`) uses the `acadTerms` map above to render term
columns and a Final column; the JS filters rows per selected term
(`term.term_no == quarter`).

---

## Master sheets

`MasterSheetController` generates class/consolidated Excel + PDF sheets. Its three
config-resolution sites (`~776`, `~1420`, `~1738`) each:

1. Resolve the config through `activeConfigQuery(...)` (**isactive-safe** — this
   session's fix), ordered whole-year first.
2. Gate on `configAppliesToLevel($cfg->id, $gradelevel)`.
3. Load `ibed_term` (active) → build `$msTermLabels[term_no] = short_code ?:
   description ?: ordinal.' Term'` and emit one column per term; otherwise the sheet
   keeps the 4-quarter layout.

Reports (`excel_mastersheet`, `excel_composite`, `finalcomposite`, `bysubject`,
`consolidated_pdf`, GSA/LP, `studentawards`) all read `gradesdetail` per
`quarter`(=term_no) and the final via the same formula path.

---

## Porting notes / gotchas

1. **Wrap every `ibed_term_config` read with `activeConfigQuery()`** — final
   grading (`finalgrade.blade:~60`), `GenerateGrade` (`~150`), and MasterSheet
   (`~776/1420/1738`). This is exactly the set fixed in es_ldcu's isactive audit; a
   bare `deleted=0` read shows term columns for a config you parked Inactive.
2. **`quarter` == `term_no`.** Term grades live in `gradesdetail`/`grades` under the
   `quarter` column reused as the term index — no separate term column. Read/write
   with `grades.quarter = <term_no>`.
3. **Final formula is parsed, not eval'd.** Keep `computeFinalFromFormula` +
   `evaluateArithmetic` intact; don't "simplify" to `eval`. No formula ⇒ average;
   missing any referenced term ⇒ `null`.
4. **`configAppliesToLevel` gate per level.** A program-wide config with explicit
   grade-level scoping must only term-column the levels it applies to; others stay
   on quarters. Don't skip this check when building columns.
5. **Term labels** — `short_code ?: description ?: (ordinal.' Term')`, ordered by
   `sort_order` then `term_no`. Keep consistent with Modules 05/08 so all surfaces
   show the same labels.
6. **SHS whole-year config preference** — order configs `semid IS NULL` first
   (whole-year), matching Module 05's resolver.

---

## Verification

1. For a term-mode level (Modules 02–07 done), open `/teacher/finalgrades` → the
   grid shows **1T / 2T / 3T** columns + **Final**, not quarters.
2. Enter/scores present per term → the **Final** matches the config formula
   (`($q1+$q2+$q3)/3` etc.); with **no** formula it's the average; with a **missing**
   term it's blank.
3. Set the config **Inactive** → final grading and master sheets fall back to
   quarters (proves the `activeConfigQuery` wrap). Re-activate → terms return.
4. A level **not** in the config's applicable set still shows quarters even though a
   term config exists for the program (`configAppliesToLevel`).
5. Generate a **master sheet** (`grades/report/mastersheet/excel`) → term columns
   with the same labels; consolidated/final composite read the same computed final.
6. DB spot-check:
   ```sql
   SELECT g.quarter AS term_no, gd.qg FROM grades g
     JOIN gradesdetail gd ON gd.headerid = g.id
    WHERE g.sectionid=? AND g.subjid=? AND g.deleted=0 ORDER BY g.quarter;
   ```

With final grades computing and reporting in terms, proceed to **Module 10 — Report
cards / SF9 (term layout)**, the last read surface.
