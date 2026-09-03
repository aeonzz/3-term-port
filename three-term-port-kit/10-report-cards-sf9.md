# Module 10 — Report Cards / SF9 (term layout)

> **Ported into `sjhsli_online`: real path differs from the reference below.**
> `FormReportsController::reportsschoolform9()` (this doc's reference) is dead
> code there — nothing links to it, and its Excel branch references an
> `sf9template` table that doesn't even exist in that database. Before assuming
> this controller is live, trace the actual UI flow: in `sjhsli_online` it's
> `registrar/reportsschoolform9preview.blade.php` → `/prinsf9print/{studid}` →
> `PrincipalControllers\DynamicPDFController::sf9pdf()` → whichever
> `reportcard_layouts` row is `isactive=1` for the acadprog (check that table
> first — only one school-specific blade is usually live, not the dozens of
> variants that exist in the codebase). `resolveShsPeriods()`'s own `terms`
> array already carries `term_no`/`label` pairs, so no separate
> `resolveShsSf9Terms()` helper was needed there. Also found and fixed a
> pre-existing crash in the live blade unrelated to this port: a "Certificate
> of Transfer" section did `collect($finalgrade)->where('semid',2)->first()`
> and dereferenced the result unguarded — null in term mode (finalgrade rows
> carry `semid=NULL`), which threw. Guard any such per-semester `$finalgrade`
> lookup the same way.
>
> **Same port applied to `sjhsli_local`** (this hybrid deployment's registrar
> repo — see `HYBRID-DEPLOYMENT.md`): the controller and blade were
> byte-identical to `sjhsli_online`'s copies before editing, so the same two
> diffs were mirrored verbatim there. One real difference worth knowing:
> `sjhsli_local`'s `StudentGradeEvaluation::sf9_grades()` gates the SF9 read on
> `gradesdetail.gdstatus IN (2,4)` when `$sf9=true`, stricter than
> `sjhsli_online`'s `(1,2,3,4)` — a synthetic test grade must be Approved/Posted
> there, not merely Submitted, or it silently won't show up. `sjhsli_local`'s
> own database (`es_sjhsl`) also has no live term-mode SHS data at all
> (`subject_plot` is never fully whole-year for levels 14/15 there, only for
> JHS) — verification for that repo used a fully synthetic, rolled-back
> transaction rather than a real class.

The last read surface: the **student report card (SF9 / Form 138)** and the
**permanent record (SF10 / Form 137)**, rendered as term columns (1T/2T/3T)
instead of quarters when the level is in term mode.

- **SF9 report card** — `FormReportsController@reportsschoolform9` →
  `registrar/pdf/pdf_schoolform9senior.blade.php`. **This is the implemented
  term-aware path** (SHS senior).
- **SF10 permanent record** — `FormReportsController@reportsschoolform10*` (per
  program: preschool / elem / junior / senior) → the `pdf_schoolform10_*` blades.
  See the scope note below on term-awareness.

> Copy-the-files module. `FormReportsController` is enormous (~17k lines) and the
> report blades are **school-specific** — you adapt the target's own SF9/SF10
> blades. This guide gives the term resolver (inlined), the render branch, and the
> honest coverage boundary.

---

## Reference implementation (es_ldcu)

| Piece | Path / symbol |
|-------|---------------|
| SF9 controller flow | `app/Http/Controllers/RegistrarControllers/FormReportsController.php` → `reportsschoolform9($id)` (term gate ~707–966), `resolveShsSf9Terms()` (~16617) |
| SF9 PDF blade | `resources/views/registrar/pdf/pdf_schoolform9senior.blade.php` (+ school variants, e.g. `buacs_pdf_schoolform9_senior`) |
| SF10 controllers | `FormReportsController@reportsschoolform10getrecords_{preschool,elem,junior,senior}` |
| SF10 PDF blades | `resources/views/registrar/pdf/pdf_schoolform10_{elem,junior,...}*.blade.php` (many school variants) |
| Routes | `routes/web.php` — `/reports_schoolform9/{id}`, `reportsschoolform10*` |

---

## Dependencies

- **Module 05** — `IBEDGradingDefaults::resolveShsPeriods` (the term gate) +
  `activeConfigQuery` (isactive-safe read) + `IbedGradeEquivalency::configAppliesToLevel`.
- **Module 09** — the computed per-term grades / final in `gradesdetail`
  (`grades.quarter` == term_no).
- Standard tables: `grades`, `gradesdetail`, `sy`, `gradelevel`, `ibed_term_config`,
  `ibed_term`.

---

## SF9 term flow

`reportsschoolform9($id)` decides term-vs-quarter for the SHS report card:

```php
$isTermGradingSHS = false;
$shsTerms = collect();

// Gate on the SHS period model (Module 05)
$shsPeriods = \App\Support\IBEDGradingDefaults::resolveShsPeriods($sf9Syid, $sf9Levelid);
if (!empty($shsPeriods['isTermMode'])) {
    $shsTerms = self::resolveShsSf9Terms($sf9Syid, $sf9Levelid);
    $isTermGradingSHS = $shsTerms->count() > 0;
}
// ... build grades per term (grades.quarter == term_no) ...

$pdf = PDF::loadview('registrar/pdf/pdf_schoolform9senior',
    compact('grades','gradelevel','getValues','student','schoolinfo','attSum','principal','isTermGradingSHS','shsTerms')
)->setPaper('8.5x11', 'landscape');
```

### `resolveShsSf9Terms($syid, $levelid)` — copy verbatim

The SF9-specific term resolver (isactive-safe — this session's audit fix):

```php
private static function resolveShsSf9Terms($syid, $levelid)
{
    $empty = collect();

    if (empty($syid) || empty($levelid)) {
        return $empty;
    }

    $sy = DB::table('sy')->where('id', $syid)->first();
    if (!$sy || (int) ($sy->term_grading_status ?? 0) !== 1) {
        return $empty;
    }

    $cfg = \App\Support\IBEDGradingDefaults::activeConfigQuery(
        DB::table('ibed_term_config')
            ->where('syid', $syid)
            ->where('acadprogid', 5)
            ->where('deleted', 0)
            ->orderByDesc('id')
    )->first();
    if (!$cfg) {
        return $empty;
    }

    if (!\App\Support\IbedGradeEquivalency::configAppliesToLevel($cfg->id, $levelid)) {
        return $empty;
    }

    return DB::table('ibed_term')
        ->where('config_id', $cfg->id)
        ->where('is_active', 1)
        ->where('deleted', 0)
        ->orderBy('sort_order')
        ->orderBy('term_no')
        ->select('term_no', 'description', 'short_code')
        ->get();
}
```

### SF9 blade term branch

`pdf_schoolform9senior.blade.php` renders term columns when the flag is set, else
the legacy quarter columns:

```blade
@if(!empty($isTermGradingSHS) && isset($shsTerms) && count($shsTerms) > 0)
    @foreach($shsTerms as $t)
        <td>{{ $t->short_code ?? $t->description }}</td>   {{-- 1T / 2T / 3T --}}
    @endforeach
@else
    {{-- legacy 1st/2nd/3rd/4th quarter columns --}}
@endif
```

Each term's grade cell reads `gradesdetail` for `grades.quarter == term_no`, and
the general average uses the Module 09 final.

---

## Scope note — what's term-aware, what isn't

- ✅ **SF9 SHS senior** (`pdf_schoolform9senior`) — the implemented term path above.
- ⚠️ **SF10 (permanent record)** and non-senior report cards — the reference SF10
  senior/junior record methods show **no** term resolution; they render the legacy
  quarter/semester layout. Treat term-awareness there as **not yet ported** —
  verify per blade against your target's needs. (The registrar dev checklist
  `../registrar-three-term-checklist.md` tracks this; SF9 was the focus, and even
  SF9 initially rendered the legacy layout until `resolveShsSf9Terms` + the blade
  branch landed.)
- Junior-level report cards: if a target needs term-mode JHS report cards, mirror
  the SF9 pattern but gate with `resolveTermLabelsForLevel` (Module 05) instead of
  `resolveShsPeriods`, and drop the hardcoded `acadprogid = 5`.

---

## Porting notes / gotchas

1. **School-specific blades.** SF9/SF10 blades come in many per-school variants
   (`_lchs`, `_dcc`, `_lhs`, `_sjaes`, `buacs_…`). Port the term branch into
   whichever variant the target actually renders — don't assume a single file.
2. **Wrap the config read with `activeConfigQuery()`** — `resolveShsSf9Terms`
   already does (the `FormReportsController:16630` audit site). A bare `deleted=0`
   read prints term columns for a config parked Inactive.
3. **`acadprogid = 5` is hardcoded** in `resolveShsSf9Terms` (SHS only). For a JHS
   report card, parameterize the program or use the junior resolver.
4. **`quarter` == `term_no`** — the report reads term grades from the `quarter`
   column reused as the term index (consistent with Modules 08–09).
5. **Gate order matters** — `resolveShsPeriods` (config **and** term-plotting) is
   the outer gate; `resolveShsSf9Terms` supplies the labels. A SHS level that's
   configured but not whole-year-plotted (Module P2 not done) correctly stays on
   quarters in the report card too.
6. **General average / remarks** come from Module 09's final computation — keep the
   report's average in sync with `computeFinalFromFormula` (don't recompute a
   different way in the blade).

---

## Verification

1. For a term-mode SHS senior class (Modules 02–09 done), generate the SF9
   (`/reports_schoolform9/{id}`) → the grade table shows **1T / 2T / 3T** columns
   and a general average, not four quarters.
2. `resolveShsPeriods($syid, 14)` is `isTermMode:true` and
   `resolveShsSf9Terms($syid, 14)` returns the 3 term rows.
3. Set the config **Inactive** (Module 03) → SF9 falls back to the quarter layout
   (proves the `activeConfigQuery` wrap). Re-activate → terms return.
4. A SHS level configured but **not** whole-year-plotted (skip Module P2) → SF9
   stays on quarters (outer `resolveShsPeriods` gate).
5. Cross-check the SF9 general average equals the Final Grading value (Module 09)
   for the same student/subject.

---

## Kit complete

Modules 01–10 cover the full 3-term feature end to end:

| Layer | Modules |
|-------|---------|
| **Schema & switches** | 01 migration · 02 SY toggle |
| **Setup** | 03 term config · 04 grade equivalency |
| **Brain** | 05 resolution helpers |
| **Plotting** | 06 subject-plot whole-year (SHS) |
| **Entry & viewing** | 07 teacher ECR · 08 grade-view layout |
| **Output** | 09 final grading + master sheets · 10 report cards / SF9 |

Work them in order per the [`README.md`](README.md). The cross-cutting rule that
ties them together: **every `ibed_term_config` read on a grading/report path must
go through `IBEDGradingDefaults::activeConfigQuery()`** (Module 05) so an *Inactive*
config is disregarded everywhere — the single most important consistency guarantee
in the feature.
