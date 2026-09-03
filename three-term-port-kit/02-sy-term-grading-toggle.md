# Module 02 — School Year Term-Grading Toggle

The **master switch**. Every term-resolution path first checks
`sy.term_grading_status == 1` for the active school year — if it's off, no level
is ever in term mode, regardless of configs. This module adds the Activate /
Deactivate controls on the School Year setup screen.

- **Screen:** `/setup/schoolyear` → select a SY → **Activate IBED Term Grading** /
  **Deactivate IBED Term Grading** buttons.
- **Effect:** sets `sy.term_grading_status` to `1` / `0` for the selected SY.

---

## Reference implementation (es_ldcu)

| Piece | Path |
|-------|------|
| Controller methods | `app/Http/Controllers/SuperAdminController/SYSetupController.php` → `activateTermGrading()`, `deactivateTermGrading()` |
| Routes | `routes/web.php` (`/setup/schoolyear/activate-term-grading`, `/deactivate-term-grading`) |
| View (buttons + JS) | `resources/views/registrar/setup/schoolyear.blade.php` |
| SY list endpoint (feeds button state) | `SYSetupController@schoolyear` → `/setup/schoolyear/list` |

---

## Dependencies

- **Module 01** must be done — the toggle writes `sy.term_grading_status`, which
  the migration page's final step (`column_sy_term_grading_status`) adds.
- The School Year setup screen must already exist (standard CK ERP screen). This
  module **adds controls to it**, it doesn't create the page.

---

## How it works

1. The SY list (`/setup/schoolyear/list`) returns every `sy` row **including**
   `term_grading_status` (the reference endpoint does `DB::table('sy')->get()` —
   all columns, so nothing to add there).
2. When the operator selects a SY, `syncTermGradingButtons(syInfo)` shows the
   **Deactivate** button if `term_grading_status == 1`, else the **Activate**
   button.
3. Clicking Activate/Deactivate confirms via SweetAlert, then GETs the toggle
   route with `syid`. On success it re-pulls the SY list and re-syncs the buttons.

> **Note on the "Term Grading: ON" badge:** that green badge lives on the *Term
> Grading Config* screen (Module 03), which just reads `term_grading_status`.
> Module 02 owns only the toggle itself.

---

## File 1 — Controller methods

Add these two methods to the existing School Year setup controller
(`app/Http/Controllers/SuperAdminController/SYSetupController.php`). They mirror
the existing SY methods' return shape — an array whose first element is a
`stdClass` with `status` + `message`, which the view reads as `data[0]`.

```php
public static function activateTermGrading(Request $request)
{
    $id = $request->get('syid');

    try {
        DB::table('sy')
            ->where('id', $id)
            ->take(1)
            ->update([
                'updatedby' => auth()->user()->id,
                'updateddatetime' => \Carbon\Carbon::now('Asia/Manila'),
                'term_grading_status' => 1,
            ]);

        return array(
            (object) [
                'status' => 1,
                'message' => 'Term Grading Activated!',
            ]
        );
    } catch (\Exception $e) {
        return self::store_error($e);
    }
}

public static function deactivateTermGrading(Request $request)
{
    $id = $request->get('syid');

    try {
        DB::table('sy')
            ->where('id', $id)
            ->take(1)
            ->update([
                'updatedby' => auth()->user()->id,
                'updateddatetime' => \Carbon\Carbon::now('Asia/Manila'),
                'term_grading_status' => 0,
            ]);

        return array(
            (object) [
                'status' => 1,
                'message' => 'Term Grading Deactivated!',
            ]
        );
    } catch (\Exception $e) {
        return self::store_error($e);
    }
}
```

> **Porting notes:**
> - `store_error()` is an existing helper on the reference controller. If your
>   target controller doesn't have it, replace the `catch` with your project's
>   standard error response (e.g. `return [(object)['status'=>0,'message'=>$e->getMessage()]];`).
> - These are `static` because the reference controller registers routes as
>   `Controller@method` on static methods. If your controller uses instance
>   methods, drop `static` and keep the route style consistent.
> - Requires `use Illuminate\Http\Request;` and `use Illuminate\Support\Facades\DB;`
>   at the top of the controller (already present in the reference).

---

## File 2 — Routes

Add to `routes/web.php`, inside the same authenticated superadmin/registrar group
that guards `/setup/schoolyear`:

```php
Route::get('/setup/schoolyear/activate-term-grading', 'SuperAdminController\SYSetupController@activateTermGrading');
Route::get('/setup/schoolyear/deactivate-term-grading', 'SuperAdminController\SYSetupController@deactivateTermGrading');
```

> The SY list route already exists in a CK ERP; confirm it is:
> ```php
> Route::get('/setup/schoolyear/list', 'SuperAdminController\SYSetupController@schoolyear');
> ```

---

## File 3 — View (buttons + JS)

Edit the School Year setup view
(`resources/views/registrar/setup/schoolyear.blade.php`).

### 3a. Buttons — near the other per-SY action buttons

```blade
<button class="btn btn-sm" style="font-size:.8rem !important" id="activateTermGrading" hidden>
    <svg aria-hidden="true" xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="none" viewBox="0 0 24 24">
        <path stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
              d="M3 15v3c0 .5523.44772 1 1 1h9.5M3 15v-4m0 4h9m-9-4V6c0-.55228.44772-1 1-1h16c.5523 0 1 .44772 1 1v5H3Zm5 0v8m4-8v8m7.0999-1.0999L21 16m0 0-1.9001-1.9001M21 16h-5"/>
    </svg>
    Activate IBED Term Grading
</button>
<button class="btn btn-sm btn-danger" style="font-size:.8rem !important" id="deactivateTermGrading" hidden>
    <svg aria-hidden="true" xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="none" viewBox="0 0 24 24">
        <path stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
              d="M3 15v3c0 .5523.44772 1 1 1h9.5M3 15v-4m0 4h9m-9-4V6c0-.55228.44772-1 1-1h16c.5523 0 1 .44772 1 1v5H3Zm5 0v8m4-8v8m7.0999-1.0999L21 16m0 0-1.9001-1.9001M21 16h-5"/>
    </svg>
    Deactivate IBED Term Grading
</button>
```

Both start `hidden`; `syncTermGradingButtons()` reveals exactly one based on the
selected SY's status.

### 3b. Button-state sync helper — with the page's other JS state vars

```javascript
function syncTermGradingButtons(syInfo) {
    $('#activateTermGrading').attr('hidden', 'hidden')
    $('#deactivateTermGrading').attr('hidden', 'hidden')

    if (!syInfo) {
        return
    }

    if (syInfo.term_grading_status == 1) {
        $('#deactivateTermGrading').removeAttr('hidden')
    } else {
        $('#activateTermGrading').removeAttr('hidden')
    }
}
```

Call `syncTermGradingButtons(sy_info[0])` wherever a SY becomes selected. In the
reference that is:
- the row/view click handler (`$(document).on('click','.view_sy_info', …)`), and
- inside `get_sy_list()`'s success callback when a `selected_id` is set (so the
  buttons re-sync after every refresh).

### 3c. Click handlers

```javascript
// activate term grading button
$(document).on('click', '#activateTermGrading', function() {
    var sy_info = sy_list.filter(x => x.id == selected_id)

    Swal.fire({
        text: 'Are you sure you want to activate Term Grading for S.Y. ' + sy_info[0].sydesc + '?',
        type: 'warning',
        showCancelButton: true,
        confirmButtonColor: '#3085d6',
        cancelButtonColor: '#d33',
        confirmButtonText: 'Activate'
    }).then((result) => {
        if (result.value) {
            $.ajax({
                type: 'GET',
                url: '/setup/schoolyear/activate-term-grading',
                data: { syid: selected_id },
                success: function(data) {
                    if (data[0].status == 0) {
                        Toast.fire({ type: 'warning', title: data[0].message })
                    } else {
                        Toast.fire({ type: 'success', title: data[0].message })
                        get_sy_list()
                        syncTermGradingButtons({ ...sy_info[0], term_grading_status: 1 })
                    }
                },
                error: function() {
                    Toast.fire({ type: 'warning', title: 'Something went wrong!' })
                }
            })
        }
    })
})

// deactivate term grading button
$(document).on('click', '#deactivateTermGrading', function() {
    var sy_info = sy_list.filter(x => x.id == selected_id)

    Swal.fire({
        text: 'Are you sure you want to deactivate Term Grading for S.Y. ' + sy_info[0].sydesc + '?',
        type: 'warning',
        showCancelButton: true,
        confirmButtonColor: '#d33',
        cancelButtonColor: '#3085d6',
        confirmButtonText: 'Deactivate'
    }).then((result) => {
        if (result.value) {
            $.ajax({
                type: 'GET',
                url: '/setup/schoolyear/deactivate-term-grading',
                data: { syid: selected_id },
                success: function(data) {
                    if (data[0].status == 0) {
                        Toast.fire({ type: 'warning', title: data[0].message })
                    } else {
                        Toast.fire({ type: 'success', title: data[0].message })
                        get_sy_list()
                        syncTermGradingButtons({ ...sy_info[0], term_grading_status: 0 })
                    }
                },
                error: function() {
                    Toast.fire({ type: 'warning', title: 'Something went wrong!' })
                }
            })
        }
    })
})
```

> **Porting notes:**
> - Relies on page globals already present in the reference view: `sy_list`
>   (array of SY rows from `/setup/schoolyear/list`), `selected_id` (currently
>   selected SY id), plus `Swal` (SweetAlert2) and `Toast`. If your SY screen
>   names these differently, map them.
> - **`sy_list` rows must include `term_grading_status`.** The reference list
>   endpoint returns all `sy` columns, so it's automatic. If your endpoint uses an
>   explicit `->select(...)`, add `term_grading_status` to it.

---

## Porting notes / gotchas

1. **One SY at a time.** The flag is per school-year (`sy.term_grading_status`).
   Activating term grading on the active SY is what turns the feature on for
   everyone; other SYs are unaffected.
2. **Deactivate is a clean kill-switch.** Setting it back to `0` reverts every
   level to the semester/quarter layout **without deleting any config** — configs
   and terms stay on record and reactivate when you flip it back on.
3. **No SHS plotting change here.** This toggle is orthogonal to subject-plot
   whole-year conversion (that's Module P2 / the ops runbook). A SHS level still
   won't render terms until it's also term-plotted, even with the flag on.
4. **Guard the routes.** Keep them behind the same auth middleware as the rest of
   `/setup/*`; they mutate the active school year.

---

## Verification

1. Go to `/setup/schoolyear`, select the active SY.
2. If off, the **Activate IBED Term Grading** button shows. Click it → confirm →
   toast "Term Grading Activated!". The button flips to **Deactivate**.
3. Confirm in DB:
   ```sql
   SELECT id, sydesc, term_grading_status FROM sy WHERE isactive = 1;
   ```
   The active SY shows `term_grading_status = 1`.
4. Reload the page and re-select the SY — the **Deactivate** button (not Activate)
   is the one shown, proving the state persists and syncs from the list.
5. Deactivate → toast "Term Grading Deactivated!", flag returns to `0`, button
   flips back.

Once the flag toggles reliably, proceed to **Module 03 — Term Grading Config
screen**, which is where you actually define the terms and formula.
