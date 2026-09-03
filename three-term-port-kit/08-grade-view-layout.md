# Module 08 — Grade-View Layout (shared: class-schedule modal + system grading)

The **grade layout** a user actually looks at — the period selector (terms
`1T/2T/3T` vs quarters) and the score grid (component/item vs static WW-PT-QA) —
is a **shared concern** rendered by two different controller/blade families and
embedded in several screens. It must render **consistently** everywhere: the same
class is term-or-quarter, component-or-static, no matter which screen shows it.

This module documents that shared layer so the two surfaces you named agree:

- **Class-schedule modal** — `/classschedule` (`teacherinformation.blade.php`), the
  read-only ECR grid injected into `#ecr_view_holder`.
- **System grading** — the teacher grading grid: `/grades/index`
  (`GradeController@index`) → subject list, and
  `/subjects/{id}/{syid}/{gradelevelid}/{sectionid}/{semid}`
  (`TeacherGradingV2@showGrades`) → the per-class grading grid.

> Depends on **Module 05** (term resolution + component gate) and **Module 07**
> (the ECR `view` endpoints and `has_ibed_components` gate). Copy the referenced
> blades/controller methods verbatim; this guide is the layout contract + wiring.

---

## Two render families (both must agree)

| Family | Where it shows | Controller → View | Period source | Grid source |
|--------|----------------|-------------------|---------------|-------------|
| **ECR viewer** | class-schedule modal, grade-posting modal, term-grading, college portal | `IBEDECRController@view` → `ibed_gradeview.blade.php` (dynamic) · `TeacherECRController@view_ecr` → static grid | `resolveShsPeriods` / `resolveActiveTerms` | `components_json` (dynamic) vs static WW/PT/QA |
| **Teacher grading grid** | system grading | `TeacherGradingV2@showGrades` → `teacher.grading.teachergrading.blade.php` · `GradeController@index` → `teacher.grading.v1.*` | `$ibedTerms` (config terms, `activeConfigQuery`-wrapped) | `components_json` gate (dynamic IBED grid vs legacy grid) |

Both read the **same two decisions** as the ECR (Module 07):
`is_term_mode` → term columns vs quarter columns, and `has_ibed_components`
(`components_json` non-empty, `component_scores` mode) → component grid vs static.
If they disagree, one screen shows terms while another shows quarters for the same
class — the exact class-schedule-vs-final-grading mismatch this feature had to fix.

---

## Reference implementation (es_ldcu)

| Piece | Path |
|-------|------|
| Dynamic ECR view (grid) | `app/.../IBEDECRController.php` → `view()`; `resources/views/superadmin/pages/teacher/ibed_gradeview.blade.php` (~1,090 lines) |
| Static ECR view | `app/.../TeacherECRController.php` → `view_ecr()` |
| Class-schedule modal | `resources/views/superadmin/pages/teacher/teacherinformation.blade.php` (`#ecr_modal`, `#ecr_view_holder`) |
| System-grading grid | `app/Http/Controllers/TeacherControllers/TeacherGradingV2.php` → `showGrades()`; `resources/views/teacher/grading/teachergrading.blade.php` (~860 lines) |
| System-grading landing | `app/Http/Controllers/TeacherControllers/GradeController.php` → `index()`; `resources/views/teacher/grading/v1/index.blade.php`, `showsubjects.blade.php` |
| Routes | `routes/web.php` — `/ibed-ecr/view`, `/ecr/view`, `/grades/index`, `/subjects/{id}/{syid}/{gradelevelid}/{sectionid}/{semid}` |

---

## A) Class-schedule modal (ECR viewer)

The modal holds an empty `#ecr_view_holder`; selecting a class + quarter AJAX-loads
the rendered grid HTML into it, choosing the endpoint by the Module 07 gate:

```js
// has_ibed_components == 1  -> dynamic grid ; else static
var url = is_ibed_ecr ? '/ibed-ecr/view' : '/ecr/view';
$.get(url, { syid, semid, levelid, subjid, sectionid, quarter, clusterplotid }, function (html) {
    $('#ecr_view_holder').html(html);   // server returns the grid HTML (a rendered blade)
});
```

- `IBEDECRController@view` returns the `ibed_gradeview` blade (component grid with
  `ibed-ig-cell` IG cells, per-student rows, `.exclude` checkboxes, submit). It
  reads back **`ibed_ecr_item_grade`** for item scores and tolerates SHS headers
  saved with `semid = NULL` (the Module 07 tie-breaker case) so it never renders a
  blank grid over real scores.
- `?meta_only=1` returns just the status strip (last uploaded / submitted / posted).
- `TeacherECRController@view_ecr` returns the static grid for non-component classes,
  term-columned when `is_term_mode`.

Copy the `#ecr_modal` markup + the load/submit handlers from
`teacherinformation.blade.php`; adapt toast/layout helpers.

---

## B) System grading (teacher grading grid)

`TeacherGradingV2@showGrades($id,$syid,$gradelevelid,$sectionid,$semid)` builds the
per-class grid and passes **`$ibedTerms`** to `teachergrading.blade.php`:

- It detects the component setup (`subject_plot` / `sh_cluster_plot` →
  `subject_gradessetup.components_json`); when present + `component_scores`, it
  resolves the term set for the period selector **through the active-config guard**:
  ```php
  $termConfig = \App\Support\IBEDGradingDefaults::activeConfigQuery(
      DB::table('ibed_term_config')->where('syid', $syid)->where('acadprogid', $acadprogid)->where('deleted', 0)
      // (+ semid / whole-year ordering)
  )->first();
  // then ibed_term rows (is_active=1), filtered to the plot's assigned term_nos
  ```
- The blade renders the **period buttons** from `$ibedTerms` (term
  `description` / `term_no`) when present, else the fixed 4 quarter buttons:
  ```blade
  @if (isset($ibedTerms) && $ibedTerms->count() > 0)
      @foreach ($ibedTerms as $loop_i => $term)
          <button name="quarter" value="{{ $term->term_no }}" ...>{{ $term->description }}</button>
      @endforeach
  @else
      {{-- 1st/2nd/3rd/4th Quarter buttons --}}
  @endif
  ```
  Note the `quarter` field carries the **term_no** in term mode — the grade header's
  `quarter` column doubles as the term index, so downstream storage is unchanged.

`GradeController@index` (`/grades/index`) is the subject-list landing
(`teacher.grading.v1.index` / `showsubjects`) that links into `showGrades`.

---

## The consistency contract

For any one class, all surfaces must agree on:

1. **Period model** — terms vs quarters. Both families resolve it from the **same**
   `ibed_term_config` (Module 03) through the **same** helpers/guard
   (`activeConfigQuery`, `resolveShsPeriods` / `resolveActiveTerms`). Never hand-roll
   a second term lookup that skips `isactive` or the SHS plotting gate.
2. **Grid model** — component vs static. Both use the **same** `components_json` +
   `input_mode == 'component_scores'` gate as Module 07's `hasIbedComponents()`.
3. **SHS `semid`-NULL tolerance** — viewers must match a header whose `semid` is
   NULL *or* the class semid, so a class graded before the plot conversion still
   renders its real scores.

---

## Porting notes / gotchas

1. **Wrap every config read with `activeConfigQuery()`** — `showGrades` already
   does; keep it. A direct `deleted=0`-only read here reintroduces the inactive-
   config bug (this session's audit) and can show terms on a config you parked
   Inactive.
2. **`quarter` == `term_no` in term mode.** The grid reuses the header's `quarter`
   column as the term index. Don't add a separate term column to storage — the
   period buttons just post `term_no` as `quarter`.
3. **Assigned-terms filter.** `showGrades` filters `$ibedTerms` to the plot's
   assigned term_nos (whole-year ⇒ all). Preserve so a single-term subject shows
   only its term button.
4. **Two blade families, one gate.** `ibed_gradeview.blade.php` (ECR modal) and
   `teachergrading.blade.php` (system grading) are separate ~1,000/~860-line blades.
   Copy both; keep their term/component branching in sync — a change to the gate
   must land in both or the surfaces drift.
5. **`view` returns HTML, not JSON.** The modal injects the response as markup;
   don't wrap it in a JSON envelope. `meta_only` is the one status-strip exception.
6. **College portal** (`ctportal/grade_monitoring`, `grade_upload`) embeds the same
   ECR `view` — if the target has a college portal, it inherits the layer for free
   once the endpoints exist.

---

## Verification

1. **Class-schedule modal** — open a term-mode component class on `/classschedule`;
   the modal shows term period tabs and the component grid (IG cells), scores
   matching `ibed_ecr_item_grade`. A static class shows the static grid; a
   quarter class shows quarter columns.
2. **System grading** — open the same class via `/grades/index` →
   `/subjects/{id}/{syid}/{gradelevelid}/{sectionid}/{semid}`; the period buttons
   are the **same terms** (`1T/2T/3T`), not quarters, and the grid model matches.
3. **Consistency** — for one class, class-schedule modal and system grading agree on
   terms-vs-quarters and component-vs-static. (This is the mismatch class this
   feature exists to prevent.)
4. **Inactive config** — set the term config Inactive (Module 03); both surfaces
   fall back to quarters. Re-activate → both show terms again.
5. **SHS pre-conversion header** — a class whose `grades.semid` is NULL still renders
   its real scores in the modal (no blank grid).

With the viewing layer consistent, proceed to **Module 09 — Final grading & master
sheets** and **Module 10 — Report cards / SF9**, the remaining read surfaces.
