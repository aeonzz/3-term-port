# Module 01 — Term Grading Migration Page

The **foundation** module. A superadmin screen that applies every additive
schema change the 3-term feature needs — tables and columns — as an idempotent,
click-to-run migration. Nothing else in this kit works until this is done.

- **URL:** `/superadmin/term-grading-migration`
- **What the operator sees:** a "Check Status" button that lists every schema
  item as *Added / Skipped / Pending / Error*, and a "Run Selected" button that
  applies the checked pending items. Existing tables/columns are auto-skipped.

---

## Reference implementation (es_ldcu)

| Piece | Path |
|-------|------|
| Controller | `app/Http/Controllers/SuperAdminController/TermGradingMigrationController.php` |
| View | `resources/views/superadmin/pages/migration/term_grading_migration.blade.php` |
| Routes | `routes/web.php` (`term.grading.migration*`) |
| Sidenav entry | `resources/views/superadmin/inc/sidenav.blade.php` |
| Base tables (dependency) | `app/Http/Controllers/SuperAdminController/SuperAdminController.php` (steps 9–10 create `ibed_term_config` + `ibed_term`) |

---

## Dependency: base `ibed_term_config` + `ibed_term` tables

The migration page **ALTERs** `ibed_term_config` (adds columns) but does not
create it. In es_ldcu those two base tables are created by a different superadmin
routine. To make this module **self-sufficient in the target repo**, fold their
creation into the runner (two extra `table` steps — provided in the controller
below). DDL for reference:

```sql
CREATE TABLE IF NOT EXISTS ibed_term_config (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    syid INT UNSIGNED NOT NULL,
    semid INT UNSIGNED DEFAULT NULL,
    acadprogid TINYINT UNSIGNED NOT NULL,
    gradessetup_id INT UNSIGNED DEFAULT NULL,
    description VARCHAR(100) NOT NULL,
    final_formula VARCHAR(255) DEFAULT NULL,
    final_formula_code VARCHAR(500) DEFAULT NULL,
    deleted TINYINT UNSIGNED NOT NULL DEFAULT 0,
    createdby INT UNSIGNED DEFAULT NULL,
    createddatetime TIMESTAMP NULL DEFAULT NULL,
    updatedby INT UNSIGNED DEFAULT NULL,
    updateddatetime TIMESTAMP NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS ibed_term (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    config_id INT UNSIGNED NOT NULL,
    term_no TINYINT UNSIGNED NOT NULL,
    description VARCHAR(100) NOT NULL,
    short_code VARCHAR(20) NOT NULL,
    grading_perc DECIMAL(5,2) DEFAULT NULL,
    is_active TINYINT UNSIGNED NOT NULL DEFAULT 1,
    sort_order TINYINT UNSIGNED NOT NULL DEFAULT 0,
    deleted TINYINT UNSIGNED NOT NULL DEFAULT 0,
    createdby INT UNSIGNED DEFAULT NULL,
    createddatetime TIMESTAMP NULL DEFAULT NULL,
    updatedby INT UNSIGNED DEFAULT NULL,
    updateddatetime TIMESTAMP NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

> If the target repo already creates these elsewhere, you may skip folding them
> in — but folding them in is harmless (idempotent) and keeps the page standalone.

---

## How it works

- `index()` renders the page.
- `status()` (POST) loops `migrationSteps()` and, per step, inspects the schema
  (`Schema::hasTable` / `hasColumn` / `information_schema` for nullability &
  indexes) and returns a status: **skipped** (already present), **pending**
  (runnable), or **error** (table missing, etc.).
- `run()` (POST) applies only the **selected** step keys, wrapped in
  `SET FOREIGN_KEY_CHECKS=0/1`, each step guarded so an existing object is
  skipped rather than erroring. Fully **idempotent**.
- Step types: `table` (CREATE TABLE IF NOT EXISTS), `column` (ADD COLUMN if
  missing, optional `AFTER`), `modify_column` (MODIFY to allow NULL if not
  already), `index` (ADD INDEX if missing).

---

## File 1 — Controller

Create `app/Http/Controllers/SuperAdminController/TermGradingMigrationController.php`.

Copy verbatim. The `migrationSteps()` array below **includes the two base-table
steps** (`create_ibed_term_config`, `create_ibed_term`) at the top so the page is
self-sufficient; drop them if your repo already creates those tables.

```php
<?php

namespace App\Http\Controllers\SuperAdminController;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class TermGradingMigrationController extends \App\Http\Controllers\Controller
{
    public function index()
    {
        return view('superadmin.pages.migration.term_grading_migration');
    }

    public function status()
    {
        try {
            $results = [];
            foreach ($this->migrationSteps() as $step) {
                $results[] = $this->stepStatus($step);
            }
            return response()->json(['status' => 1, 'message' => 'Migration status checked.', 'results' => $results]);
        } catch (\Exception $e) {
            return response()->json(['status' => 0, 'message' => $e->getMessage(), 'results' => []], 500);
        }
    }

    public function run(Request $request)
    {
        @set_time_limit(0);
        $results = [];
        $selected = $this->selectedSteps($request);

        if (empty($selected)) {
            return response()->json(['status' => 0, 'message' => 'Please select at least one migration item to run.', 'results' => []], 422);
        }

        try {
            DB::statement('SET NAMES utf8mb4');
            DB::statement('SET FOREIGN_KEY_CHECKS=0');
        } catch (\Exception $e) {
            $results[] = $this->result('Database session setup', 'error', $e->getMessage());
            return response()->json(['status' => 0, 'message' => 'Unable to prepare the database session.', 'results' => $results], 500);
        }

        try {
            foreach ($this->migrationSteps() as $step) {
                if (!in_array($step['key'], $selected)) {
                    continue;
                }
                $this->runStep($results, $step);
            }
        } finally {
            try {
                DB::statement('SET FOREIGN_KEY_CHECKS=1');
            } catch (\Exception $e) {
                $results[] = $this->result('Restore foreign key checks', 'error', $e->getMessage());
            }
        }

        $errors = 0;
        foreach ($results as $row) {
            if ($row['status'] === 'error') { $errors++; }
        }

        return response()->json([
            'status' => $errors === 0 ? 1 : 0,
            'message' => $errors === 0 ? 'Database migration completed.' : 'Database migration completed with errors.',
            'results' => $results,
        ], $errors === 0 ? 200 : 500);
    }

    private function selectedSteps(Request $request)
    {
        $selected = $request->input('steps', []);
        if (!is_array($selected)) { return []; }
        $valid = [];
        foreach ($this->migrationSteps() as $step) { $valid[] = $step['key']; }
        return array_values(array_intersect($selected, $valid));
    }

    private function runStep(&$results, $step)
    {
        if ($step['type'] === 'table') {
            $this->createTable($results, $step['table'], $step['sql']);
            return;
        }
        if ($step['type'] === 'column') {
            $this->addColumn($results, $step['table'], $step['column'], $step['definition'], $step['after'] ?? null);
            return;
        }
        if ($step['type'] === 'modify_column') {
            $this->modifyColumn($results, $step['table'], $step['column'], $step['definition'], $step['label']);
            return;
        }
        if ($step['type'] === 'index') {
            $this->addIndex($results, $step['table'], $step['index'], $step['columns']);
        }
    }

    private function stepStatus($step)
    {
        if ($step['type'] === 'table') {
            $exists = Schema::hasTable($step['table']);
            return $this->statusResult($step, $exists ? 'skipped' : 'pending', $exists ? 'Table already exists.' : 'Table will be created.', !$exists);
        }
        if (!Schema::hasTable($step['table'])) {
            return $this->statusResult($step, 'error', 'Table does not exist.', false);
        }
        if ($step['type'] === 'column') {
            $exists = Schema::hasColumn($step['table'], $step['column']);
            return $this->statusResult($step, $exists ? 'skipped' : 'pending', $exists ? 'Column already exists.' : 'Column will be added.', !$exists);
        }
        if ($step['type'] === 'modify_column') {
            if (!Schema::hasColumn($step['table'], $step['column'])) {
                return $this->statusResult($step, 'error', 'Column does not exist.', false);
            }
            $column = DB::table('information_schema.columns')
                ->where('table_schema', DB::getDatabaseName())
                ->where('table_name', $step['table'])
                ->where('column_name', $step['column'])
                ->first();
            if (!$column) {
                return $this->statusResult($step, 'error', 'Unable to inspect column metadata.', false);
            }
            $alreadyNullable = strtoupper((string) $column->IS_NULLABLE) === 'YES';
            return $this->statusResult($step, $alreadyNullable ? 'skipped' : 'pending', $alreadyNullable ? 'Column already allows NULL.' : 'Column will be modified to allow NULL.', !$alreadyNullable);
        }
        if ($step['type'] === 'index') {
            $exists = DB::table('information_schema.statistics')
                ->where('table_schema', DB::getDatabaseName())
                ->where('table_name', $step['table'])
                ->where('index_name', $step['index'])
                ->exists();
            if ($exists) {
                return $this->statusResult($step, 'skipped', 'Index already exists.', false);
            }
            foreach ($step['columns'] as $column) {
                if (!Schema::hasColumn($step['table'], $column)) {
                    return $this->statusResult($step, 'error', 'Column `' . $column . '` does not exist.', false);
                }
            }
            return $this->statusResult($step, 'pending', 'Index will be added.', true);
        }
        return $this->statusResult($step, 'error', 'Unknown migration step type.', false);
    }

    private function statusResult($step, $status, $message, $runnable)
    {
        return ['key' => $step['key'], 'label' => $step['label'], 'status' => $status, 'message' => $message, 'runnable' => $runnable];
    }

    private function migrationSteps()
    {
        return [
            // --- BASE TABLES (fold-in so the page is self-sufficient) ---
            ['key' => 'create_ibed_term_config', 'type' => 'table', 'table' => 'ibed_term_config', 'label' => 'ibed_term_config (CREATE TABLE)', 'sql' => "CREATE TABLE IF NOT EXISTS `ibed_term_config` (
                `id` int unsigned NOT NULL AUTO_INCREMENT,
                `syid` int unsigned NOT NULL,
                `semid` int unsigned DEFAULT NULL,
                `acadprogid` tinyint unsigned NOT NULL,
                `gradessetup_id` int unsigned DEFAULT NULL,
                `description` varchar(100) NOT NULL,
                `final_formula` varchar(255) DEFAULT NULL,
                `final_formula_code` varchar(500) DEFAULT NULL,
                `deleted` tinyint unsigned NOT NULL DEFAULT '0',
                `createdby` int unsigned DEFAULT NULL,
                `createddatetime` timestamp NULL DEFAULT NULL,
                `updatedby` int unsigned DEFAULT NULL,
                `updateddatetime` timestamp NULL DEFAULT NULL,
                PRIMARY KEY (`id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"],
            ['key' => 'create_ibed_term', 'type' => 'table', 'table' => 'ibed_term', 'label' => 'ibed_term (CREATE TABLE)', 'sql' => "CREATE TABLE IF NOT EXISTS `ibed_term` (
                `id` int unsigned NOT NULL AUTO_INCREMENT,
                `config_id` int unsigned NOT NULL,
                `term_no` tinyint unsigned NOT NULL,
                `description` varchar(100) NOT NULL,
                `short_code` varchar(20) NOT NULL,
                `grading_perc` decimal(5,2) DEFAULT NULL,
                `is_active` tinyint unsigned NOT NULL DEFAULT '1',
                `sort_order` tinyint unsigned NOT NULL DEFAULT '0',
                `deleted` tinyint unsigned NOT NULL DEFAULT '0',
                `createdby` int unsigned DEFAULT NULL,
                `createddatetime` timestamp NULL DEFAULT NULL,
                `updatedby` int unsigned DEFAULT NULL,
                `updateddatetime` timestamp NULL DEFAULT NULL,
                PRIMARY KEY (`id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"],

            // --- SUPPORT TABLES ---
            ['key' => 'create_ibed_term_config_gradelevel', 'type' => 'table', 'table' => 'ibed_term_config_gradelevel', 'label' => 'ibed_term_config_gradelevel (CREATE TABLE)', 'sql' => "CREATE TABLE IF NOT EXISTS `ibed_term_config_gradelevel` (
                `id` bigint unsigned NOT NULL AUTO_INCREMENT,
                `config_id` bigint unsigned NOT NULL,
                `levelid` int DEFAULT NULL,
                `deleted` tinyint(1) NOT NULL DEFAULT '0',
                `createdby` bigint DEFAULT NULL,
                `createddatetime` datetime DEFAULT NULL,
                `updatedby` bigint DEFAULT NULL,
                `updateddatetime` datetime DEFAULT NULL,
                PRIMARY KEY (`id`), KEY `idx_cfg` (`config_id`), KEY `idx_level` (`levelid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"],
            ['key' => 'create_ibed_grade_point_equivalence', 'type' => 'table', 'table' => 'ibed_grade_point_equivalence', 'label' => 'ibed_grade_point_equivalence (CREATE TABLE)', 'sql' => "CREATE TABLE IF NOT EXISTS `ibed_grade_point_equivalence` (
                `id` int unsigned NOT NULL AUTO_INCREMENT,
                `grade_description` varchar(150) DEFAULT NULL,
                `syid` int unsigned DEFAULT NULL, `acadprogid` int unsigned DEFAULT NULL,
                `levelid` int unsigned DEFAULT NULL, `semid` int unsigned DEFAULT NULL,
                `isactive` tinyint unsigned NOT NULL DEFAULT '1',
                `apply_transmutation_to_terms` tinyint unsigned NOT NULL DEFAULT '0',
                `deleted` tinyint unsigned NOT NULL DEFAULT '0',
                `createdby` int unsigned DEFAULT NULL, `createddatetime` timestamp NULL DEFAULT NULL,
                `updatedby` int unsigned DEFAULT NULL, `updateddatetime` timestamp NULL DEFAULT NULL,
                `deletedby` int unsigned DEFAULT NULL, `deleteddatetime` timestamp NULL DEFAULT NULL,
                PRIMARY KEY (`id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"],
            ['key' => 'create_ibed_grade_point_scale', 'type' => 'table', 'table' => 'ibed_grade_point_scale', 'label' => 'ibed_grade_point_scale (CREATE TABLE)', 'sql' => "CREATE TABLE IF NOT EXISTS `ibed_grade_point_scale` (
                `id` int unsigned NOT NULL AUTO_INCREMENT,
                `grade_point_equivalency` int unsigned DEFAULT NULL,
                `percent_equivalence` varchar(50) DEFAULT NULL, `grade_point` varchar(50) DEFAULT NULL,
                `letter_equivalence` varchar(50) DEFAULT NULL, `transmuted_grade` varchar(50) DEFAULT NULL,
                `grade_remarks` varchar(150) DEFAULT NULL, `is_failed` tinyint unsigned NOT NULL DEFAULT '0',
                `deleted` tinyint unsigned NOT NULL DEFAULT '0',
                `createdby` int unsigned DEFAULT NULL, `createddatetime` timestamp NULL DEFAULT NULL,
                `updatedby` int unsigned DEFAULT NULL, `updateddatetime` timestamp NULL DEFAULT NULL,
                `deletedby` int unsigned DEFAULT NULL, `deleteddatetime` timestamp NULL DEFAULT NULL,
                PRIMARY KEY (`id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"],
            ['key' => 'create_ibed_score_conversion', 'type' => 'table', 'table' => 'ibed_score_conversion', 'label' => 'ibed_score_conversion (CREATE TABLE)', 'sql' => "CREATE TABLE IF NOT EXISTS `ibed_score_conversion` (
                `id` int unsigned NOT NULL AUTO_INCREMENT,
                `name` varchar(150) NOT NULL, `formula` varchar(255) NOT NULL,
                `is_default` tinyint unsigned NOT NULL DEFAULT '0', `deleted` tinyint unsigned NOT NULL DEFAULT '0',
                `createdby` int unsigned DEFAULT NULL, `createddatetime` timestamp NULL DEFAULT NULL,
                `updatedby` int unsigned DEFAULT NULL, `updateddatetime` timestamp NULL DEFAULT NULL,
                PRIMARY KEY (`id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"],
            ['key' => 'create_ibed_ecr_item_grade', 'type' => 'table', 'table' => 'ibed_ecr_item_grade', 'label' => 'ibed_ecr_item_grade (CREATE TABLE)', 'sql' => "CREATE TABLE IF NOT EXISTS `ibed_ecr_item_grade` (
                `id` int unsigned NOT NULL AUTO_INCREMENT,
                `grades_id` int NOT NULL, `studid` int NOT NULL DEFAULT '0',
                `component_code` varchar(50) NOT NULL DEFAULT '', `sub_component_code` varchar(50) NOT NULL DEFAULT '',
                `item_index` int NOT NULL DEFAULT '0', `score` decimal(8,2) DEFAULT NULL,
                `deleted` tinyint NOT NULL DEFAULT '0',
                `createdby` int DEFAULT NULL, `createddatetime` datetime DEFAULT NULL,
                `updatedby` int DEFAULT NULL, `updateddatetime` datetime DEFAULT NULL,
                PRIMARY KEY (`id`),
                KEY `idx_lookup` (`grades_id`,`studid`,`component_code`,`sub_component_code`,`item_index`),
                KEY `idx_header` (`grades_id`,`deleted`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"],
            ['key' => 'create_sh_cluster_section_assignment', 'type' => 'table', 'table' => 'sh_cluster_section_assignment', 'label' => 'sh_cluster_section_assignment (CREATE TABLE)', 'sql' => "CREATE TABLE IF NOT EXISTS `sh_cluster_section_assignment` (
                `id` int NOT NULL AUTO_INCREMENT,
                `clusterplotid` int DEFAULT NULL, `sectionid` int DEFAULT NULL, `syid` int DEFAULT NULL,
                `deleted` tinyint DEFAULT '0', `deletedby` int DEFAULT NULL, `deleteddatetime` datetime DEFAULT NULL,
                `createdby` int DEFAULT NULL, `createddatetime` datetime DEFAULT NULL,
                `updatedby` int DEFAULT NULL, `updateddatetime` datetime DEFAULT NULL,
                PRIMARY KEY (`id`), KEY `idx_lookup` (`clusterplotid`,`sectionid`,`syid`,`deleted`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"],

            // --- ibed_term_config COLUMNS ---
            ['key' => 'column_ibed_term_config_ecr_sheet_title', 'type' => 'column', 'table' => 'ibed_term_config', 'column' => 'ecr_sheet_title', 'definition' => "`ecr_sheet_title` varchar(255) DEFAULT NULL", 'after' => 'final_formula_code', 'label' => 'ibed_term_config.ecr_sheet_title (ALTER)'],
            ['key' => 'column_ibed_term_config_formula_type', 'type' => 'column', 'table' => 'ibed_term_config', 'column' => 'formula_type', 'definition' => "`formula_type` varchar(20) DEFAULT 'weighted'", 'after' => 'ecr_sheet_title', 'label' => 'ibed_term_config.formula_type (ALTER)'],
            ['key' => 'column_ibed_term_config_grade_point_equivalence_id', 'type' => 'column', 'table' => 'ibed_term_config', 'column' => 'grade_point_equivalence_id', 'definition' => "`grade_point_equivalence_id` int unsigned DEFAULT NULL", 'after' => 'updateddatetime', 'label' => 'ibed_term_config.grade_point_equivalence_id (ALTER)'],
            ['key' => 'column_ibed_term_config_score_conversion_id', 'type' => 'column', 'table' => 'ibed_term_config', 'column' => 'score_conversion_id', 'definition' => "`score_conversion_id` int unsigned DEFAULT NULL", 'after' => 'grade_point_equivalence_id', 'label' => 'ibed_term_config.score_conversion_id (ALTER)'],
            ['key' => 'column_ibed_term_config_term_grade_display', 'type' => 'column', 'table' => 'ibed_term_config', 'column' => 'term_grade_display', 'definition' => "`term_grade_display` varchar(20) NOT NULL DEFAULT 'transmuted'", 'after' => 'score_conversion_id', 'label' => 'ibed_term_config.term_grade_display (ALTER)'],
            ['key' => 'column_ibed_term_config_final_grade_display', 'type' => 'column', 'table' => 'ibed_term_config', 'column' => 'final_grade_display', 'definition' => "`final_grade_display` varchar(20) NOT NULL DEFAULT 'transmuted'", 'after' => 'term_grade_display', 'label' => 'ibed_term_config.final_grade_display (ALTER)'],
            ['key' => 'column_ibed_term_config_display_transmuted_grade', 'type' => 'column', 'table' => 'ibed_term_config', 'column' => 'display_transmuted_grade', 'definition' => "`display_transmuted_grade` tinyint unsigned NOT NULL DEFAULT '1'", 'after' => 'final_grade_display', 'label' => 'ibed_term_config.display_transmuted_grade (ALTER)'],
            ['key' => 'column_ibed_term_config_display_letter_grade', 'type' => 'column', 'table' => 'ibed_term_config', 'column' => 'display_letter_grade', 'definition' => "`display_letter_grade` tinyint unsigned NOT NULL DEFAULT '0'", 'after' => 'display_transmuted_grade', 'label' => 'ibed_term_config.display_letter_grade (ALTER)'],
            ['key' => 'column_ibed_term_config_display_final_grade', 'type' => 'column', 'table' => 'ibed_term_config', 'column' => 'display_final_grade', 'definition' => "`display_final_grade` tinyint unsigned NOT NULL DEFAULT '1'", 'after' => 'display_letter_grade', 'label' => 'ibed_term_config.display_final_grade (ALTER)'],
            ['key' => 'column_ibed_term_config_display_grade_remarks_description', 'type' => 'column', 'table' => 'ibed_term_config', 'column' => 'display_grade_remarks_description', 'definition' => "`display_grade_remarks_description` tinyint unsigned NOT NULL DEFAULT '0'", 'after' => 'display_final_grade', 'label' => 'ibed_term_config.display_grade_remarks_description (ALTER)'],
            ['key' => 'column_ibed_term_config_gradessetup_id', 'type' => 'column', 'table' => 'ibed_term_config', 'column' => 'gradessetup_id', 'definition' => "`gradessetup_id` int unsigned NULL DEFAULT NULL", 'after' => 'acadprogid', 'label' => 'ibed_term_config.gradessetup_id (ALTER)'],
            ['key' => 'column_ibed_term_config_isactive', 'type' => 'column', 'table' => 'ibed_term_config', 'column' => 'isactive', 'definition' => "`isactive` tinyint unsigned NOT NULL DEFAULT '1'", 'after' => 'term_grade_display', 'label' => 'ibed_term_config.isactive (ALTER)'],

            // --- subject_gradessetup COLUMNS (component grading) ---
            ['key' => 'column_subject_gradessetup_comp4', 'type' => 'column', 'table' => 'subject_gradessetup', 'column' => 'comp4', 'definition' => "`comp4` int NULL DEFAULT NULL", 'label' => 'subject_gradessetup.comp4 (ALTER)'],
            ['key' => 'column_subject_gradessetup_comp1desc', 'type' => 'column', 'table' => 'subject_gradessetup', 'column' => 'comp1desc', 'definition' => "`comp1desc` varchar(255) NULL DEFAULT NULL", 'label' => 'subject_gradessetup.comp1desc (ALTER)'],
            ['key' => 'column_subject_gradessetup_comp2desc', 'type' => 'column', 'table' => 'subject_gradessetup', 'column' => 'comp2desc', 'definition' => "`comp2desc` varchar(255) NULL DEFAULT NULL", 'after' => 'comp1desc', 'label' => 'subject_gradessetup.comp2desc (ALTER)'],
            ['key' => 'column_subject_gradessetup_comp3desc', 'type' => 'column', 'table' => 'subject_gradessetup', 'column' => 'comp3desc', 'definition' => "`comp3desc` varchar(255) NULL DEFAULT NULL", 'after' => 'comp2desc', 'label' => 'subject_gradessetup.comp3desc (ALTER)'],
            ['key' => 'column_subject_gradessetup_comp4desc', 'type' => 'column', 'table' => 'subject_gradessetup', 'column' => 'comp4desc', 'definition' => "`comp4desc` varchar(255) NULL DEFAULT NULL", 'after' => 'comp3desc', 'label' => 'subject_gradessetup.comp4desc (ALTER)'],
            ['key' => 'column_subject_gradessetup_components_json', 'type' => 'column', 'table' => 'subject_gradessetup', 'column' => 'components_json', 'definition' => "`components_json` text NULL DEFAULT NULL", 'after' => 'comp4desc', 'label' => 'subject_gradessetup.components_json (ALTER)'],
            ['key' => 'column_subject_gradessetup_input_mode', 'type' => 'column', 'table' => 'subject_gradessetup', 'column' => 'input_mode', 'definition' => "`input_mode` varchar(30) NULL DEFAULT 'component_scores'", 'after' => 'components_json', 'label' => 'subject_gradessetup.input_mode (ALTER)'],

            // --- subject_plot / sh_classsched (SHS whole-year plotting) ---
            ['key' => 'column_subject_plot_termid', 'type' => 'column', 'table' => 'subject_plot', 'column' => 'termid', 'definition' => "`termid` int DEFAULT NULL", 'label' => 'subject_plot.termid (ALTER)'],
            ['key' => 'column_subject_plot_prev_semid', 'type' => 'column', 'table' => 'subject_plot', 'column' => 'prev_semid', 'definition' => "`prev_semid` int NULL DEFAULT NULL", 'after' => 'semid', 'label' => 'subject_plot.prev_semid (ALTER)'],
            // Per-plot TERM availability (SHS): subject_plot.termid holds a single term, so a
            // MULTI-term subset (e.g. 1T+3T) lives here. No rows => fall back to termid
            // (NULL = whole year). See Module P2 (bulkConvertTerms / resolvePlotTermNos).
            ['key' => 'create_subject_plot_term', 'type' => 'table', 'table' => 'subject_plot_term', 'label' => 'subject_plot_term (CREATE TABLE)', 'sql' => "CREATE TABLE IF NOT EXISTS `subject_plot_term` (
                `id` int unsigned NOT NULL AUTO_INCREMENT,
                `plot_id` int unsigned NOT NULL,
                `term_id` int unsigned NOT NULL,
                `deleted` tinyint unsigned NOT NULL DEFAULT '0',
                `createdby` int unsigned DEFAULT NULL,
                `createddatetime` timestamp NULL DEFAULT NULL,
                `updatedby` int unsigned DEFAULT NULL,
                `updateddatetime` timestamp NULL DEFAULT NULL,
                PRIMARY KEY (`id`),
                KEY `idx_plot` (`plot_id`), KEY `idx_term` (`term_id`), KEY `idx_plot_live` (`plot_id`,`deleted`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"],
            ['key' => 'column_sh_classsched_prev_semid', 'type' => 'column', 'table' => 'sh_classsched', 'column' => 'prev_semid', 'definition' => "`prev_semid` int NULL DEFAULT NULL", 'after' => 'semid', 'label' => 'sh_classsched.prev_semid (ALTER)'],
            ['key' => 'modify_sh_classsched_semid_nullable', 'type' => 'modify_column', 'table' => 'sh_classsched', 'column' => 'semid', 'definition' => "`semid` int NULL DEFAULT NULL", 'label' => 'sh_classsched.semid nullable (MODIFY)'],

            // --- SHS enrolled student term tracking ---
            ['key' => 'column_sh_enrolledstud_promotion_status_per_terms', 'type' => 'column', 'table' => 'sh_enrolledstud', 'column' => 'promotion_status_per_terms', 'definition' => "`promotion_status_per_terms` text DEFAULT NULL", 'label' => 'sh_enrolledstud.promotion_status_per_terms (ALTER)'],
            ['key' => 'column_sh_enrolledstud_active_term_id', 'type' => 'column', 'table' => 'sh_enrolledstud', 'column' => 'active_term_id', 'definition' => "`active_term_id` int unsigned DEFAULT NULL", 'after' => 'promotion_status_per_terms', 'label' => 'sh_enrolledstud.active_term_id (ALTER)'],

            // --- SHS cluster plotting ---
            ['key' => 'column_sh_cluster_plot_termid', 'type' => 'column', 'table' => 'sh_cluster_plot', 'column' => 'termid', 'definition' => "`termid` int NULL DEFAULT NULL", 'label' => 'sh_cluster_plot.termid (ALTER)'],
            ['key' => 'column_sh_cluster_plot_prev_semid', 'type' => 'column', 'table' => 'sh_cluster_plot', 'column' => 'prev_semid', 'definition' => "`prev_semid` int NULL DEFAULT NULL", 'after' => 'semid', 'label' => 'sh_cluster_plot.prev_semid (ALTER)'],
            ['key' => 'column_sh_cluster_subject_picking_prev_semid', 'type' => 'column', 'table' => 'sh_cluster_subject_picking', 'column' => 'prev_semid', 'definition' => "`prev_semid` int NULL DEFAULT NULL", 'after' => 'semid', 'label' => 'sh_cluster_subject_picking.prev_semid (ALTER)'],
            ['key' => 'column_sh_cluster_subject_picking_source_section_assignment_id', 'type' => 'column', 'table' => 'sh_cluster_subject_picking', 'column' => 'source_section_assignment_id', 'definition' => "`source_section_assignment_id` int NULL DEFAULT NULL", 'after' => 'prev_semid', 'label' => 'sh_cluster_subject_picking.source_section_assignment_id (ALTER)'],

            // --- grades / gradesdetail component-grade columns ---
            ['key' => 'column_grades_cghr1', 'type' => 'column', 'table' => 'grades', 'column' => 'cghr1', 'definition' => "`cghr1` int NULL DEFAULT NULL", 'label' => 'grades.cghr1 (ALTER)'],
            ['key' => 'column_grades_cghr2', 'type' => 'column', 'table' => 'grades', 'column' => 'cghr2', 'definition' => "`cghr2` int NULL DEFAULT NULL", 'after' => 'cghr1', 'label' => 'grades.cghr2 (ALTER)'],
            ['key' => 'column_grades_cghr3', 'type' => 'column', 'table' => 'grades', 'column' => 'cghr3', 'definition' => "`cghr3` int NULL DEFAULT NULL", 'after' => 'cghr2', 'label' => 'grades.cghr3 (ALTER)'],
            ['key' => 'column_grades_cghrtotal', 'type' => 'column', 'table' => 'grades', 'column' => 'cghrtotal', 'definition' => "`cghrtotal` int NULL DEFAULT NULL", 'after' => 'cghr3', 'label' => 'grades.cghrtotal (ALTER)'],
            ['key' => 'column_gradesdetail_cgtotal', 'type' => 'column', 'table' => 'gradesdetail', 'column' => 'cgtotal', 'definition' => "`cgtotal` int NULL DEFAULT NULL", 'label' => 'gradesdetail.cgtotal (ALTER)'],
            ['key' => 'column_gradesdetail_cgws', 'type' => 'column', 'table' => 'gradesdetail', 'column' => 'cgws', 'definition' => "`cgws` float NULL DEFAULT NULL", 'after' => 'cgtotal', 'label' => 'gradesdetail.cgws (ALTER)'],
            ['key' => 'column_gradesdetail_cgps', 'type' => 'column', 'table' => 'gradesdetail', 'column' => 'cgps', 'definition' => "`cgps` float NULL DEFAULT NULL", 'after' => 'cgws', 'label' => 'gradesdetail.cgps (ALTER)'],
            ['key' => 'column_gradesdetail_cg1', 'type' => 'column', 'table' => 'gradesdetail', 'column' => 'cg1', 'definition' => "`cg1` int NULL DEFAULT NULL", 'after' => 'cgps', 'label' => 'gradesdetail.cg1 (ALTER)'],
            ['key' => 'column_gradesdetail_cg2', 'type' => 'column', 'table' => 'gradesdetail', 'column' => 'cg2', 'definition' => "`cg2` int NULL DEFAULT NULL", 'after' => 'cg1', 'label' => 'gradesdetail.cg2 (ALTER)'],
            ['key' => 'column_gradesdetail_cg3', 'type' => 'column', 'table' => 'gradesdetail', 'column' => 'cg3', 'definition' => "`cg3` int NULL DEFAULT NULL", 'after' => 'cg2', 'label' => 'gradesdetail.cg3 (ALTER)'],
            ['key' => 'column_gradesdetail_cg4', 'type' => 'column', 'table' => 'gradesdetail', 'column' => 'cg4', 'definition' => "`cg4` int NULL DEFAULT NULL", 'after' => 'cg3', 'label' => 'gradesdetail.cg4 (ALTER)'],
            ['key' => 'column_gradesdetail_transmuted_grade', 'type' => 'column', 'table' => 'gradesdetail', 'column' => 'transmuted_grade', 'definition' => "`transmuted_grade` decimal(8,2) NULL DEFAULT NULL", 'after' => 'qg', 'label' => 'gradesdetail.transmuted_grade (ALTER)'],
            ['key' => 'column_gradesdetail_letter_grade', 'type' => 'column', 'table' => 'gradesdetail', 'column' => 'letter_grade', 'definition' => "`letter_grade` varchar(30) NULL DEFAULT NULL", 'after' => 'transmuted_grade', 'label' => 'gradesdetail.letter_grade (ALTER)'],

            // --- master switch ---
            ['key' => 'column_sy_term_grading_status', 'type' => 'column', 'table' => 'sy', 'column' => 'term_grading_status', 'definition' => "`term_grading_status` tinyint(1) NOT NULL DEFAULT '0'", 'label' => 'sy.term_grading_status (ALTER)'],
        ];
    }

    private function createTable(&$results, $table, $sql)
    {
        try {
            $alreadyExists = Schema::hasTable($table);
            DB::statement($sql);
            $results[] = $this->result($table . ' (CREATE TABLE)', $alreadyExists ? 'skipped' : 'success', $alreadyExists ? 'Table already exists.' : 'Table created successfully.');
        } catch (\Exception $e) {
            $results[] = $this->result($table . ' (CREATE TABLE)', 'error', $e->getMessage());
        }
    }

    private function addColumn(&$results, $table, $column, $definition, $after = null)
    {
        $label = $table . '.' . $column . ' (ALTER)';
        try {
            if (!Schema::hasTable($table)) { $results[] = $this->result($label, 'error', 'Table does not exist.'); return; }
            if (Schema::hasColumn($table, $column)) { $results[] = $this->result($label, 'skipped', 'Column already exists.'); return; }
            $afterClause = '';
            if ($after !== null && Schema::hasColumn($table, $after)) { $afterClause = ' AFTER `' . $after . '`'; }
            DB::statement('ALTER TABLE `' . $table . '` ADD COLUMN ' . $definition . $afterClause);
            $results[] = $this->result($label, 'success', 'Column added successfully.');
        } catch (\Exception $e) {
            $results[] = $this->result($label, 'error', $e->getMessage());
        }
    }

    private function modifyColumn(&$results, $table, $column, $definition, $label = null)
    {
        $label = $label ?: $table . '.' . $column . ' (MODIFY)';
        try {
            if (!Schema::hasTable($table)) { $results[] = $this->result($label, 'error', 'Table does not exist.'); return; }
            if (!Schema::hasColumn($table, $column)) { $results[] = $this->result($label, 'error', 'Column does not exist.'); return; }
            $columnInfo = DB::table('information_schema.columns')
                ->where('table_schema', DB::getDatabaseName())
                ->where('table_name', $table)->where('column_name', $column)->first();
            if ($columnInfo && strtoupper((string) $columnInfo->IS_NULLABLE) === 'YES') {
                $results[] = $this->result($label, 'skipped', 'Column already allows NULL.'); return;
            }
            DB::statement('ALTER TABLE `' . $table . '` MODIFY COLUMN ' . $definition);
            $results[] = $this->result($label, 'success', 'Column modified successfully.');
        } catch (\Exception $e) {
            $results[] = $this->result($label, 'error', $e->getMessage());
        }
    }

    private function addIndex(&$results, $table, $indexName, $columns)
    {
        $label = $table . '.' . $indexName . ' (INDEX)';
        try {
            if (!Schema::hasTable($table)) { $results[] = $this->result($label, 'error', 'Table does not exist.'); return; }
            $exists = DB::table('information_schema.statistics')
                ->where('table_schema', DB::getDatabaseName())
                ->where('table_name', $table)->where('index_name', $indexName)->exists();
            if ($exists) { $results[] = $this->result($label, 'skipped', 'Index already exists.'); return; }
            foreach ($columns as $column) {
                if (!Schema::hasColumn($table, $column)) { $results[] = $this->result($label, 'error', 'Column `' . $column . '` does not exist.'); return; }
            }
            $columnList = '`' . implode('`,`', $columns) . '`';
            DB::statement('ALTER TABLE `' . $table . '` ADD INDEX `' . $indexName . '` (' . $columnList . ')');
            $results[] = $this->result($label, 'success', 'Index added successfully.');
        } catch (\Exception $e) {
            $results[] = $this->result($label, 'error', $e->getMessage());
        }
    }

    private function result($label, $status, $message)
    {
        return ['label' => $label, 'status' => $status, 'message' => $message];
    }
}
```

---

## File 2 — View

Create `resources/views/superadmin/pages/migration/term_grading_migration.blade.php`.

> **Porting note (layout):** the reference view does `@extends('superadmin.layouts.app2')`
> and uses `@section('content')`, `@section('pagespecificscripts')`,
> `@section('footerjavascript')`, plus AdminLTE + jQuery + SweetAlert2 (`Swal`)
> which the superadmin layout already loads. If the target project's superadmin
> layout uses different names, adapt the `@extends`/`@section` lines and confirm
> jQuery/SweetAlert are available. Everything inside is framework-agnostic.

```blade
@extends('superadmin.layouts.app2')

@section('pagespecificscripts')
    <style>
        .migration-page .card { border: 1px solid #e4e7ec; }
        .migration-page .card-header { background: #fff; border-bottom: 1px solid #e4e7ec; }
        .migration-page .page-title { font-size: 1.35rem; font-weight: 600; color: #2f3a4a; }
        .migration-page .page-subtitle { font-size: .85rem; color: #6c757d; }
        .migration-page .script-summary li { margin-bottom: .25rem; }
        .migration-page #migration_results_table { font-size: .82rem; }
        .migration-page #migration_results_table th { background: #f7f8fa; border-top: 0; }
        .migration-page .status-pill { font-size: .72rem; min-width: 68px; }
        .migration-page .step-check { width: 36px; text-align: center; }
        .migration-page pre { white-space: pre-wrap; font-size: .78rem; max-height: 260px; overflow: auto; }
    </style>
@endsection

@section('content')
    <section class="content-header migration-page">
        <div class="container-fluid">
            <div class="row mb-2">
                <div class="col-sm-6">
                    <h1 class="page-title m-0">Term Grading Migration</h1>
                    <div class="page-subtitle">IBED term grading, grade equivalency, ECR item grades, and component grading columns.</div>
                </div>
                <div class="col-sm-6">
                    <ol class="breadcrumb float-sm-right">
                        <li class="breadcrumb-item"><a href="/home">Home</a></li>
                        <li class="breadcrumb-item active">Term Grading Migration</li>
                    </ol>
                </div>
            </div>
        </div>
    </section>

    <section class="content migration-page">
        <div class="container-fluid">
            <div class="row">
                <div class="col-md-4">
                    <div class="card h-100">
                        <div class="card-header">
                            <h3 class="card-title mb-0"><i class="fas fa-database text-primary mr-1"></i> Term Grading Script</h3>
                        </div>
                        <div class="card-body">
                            <p class="text-muted mb-2">This runner applies the additive schema changes for the 3-term grading feature. Existing tables and columns are skipped.</p>
                            <ul class="script-summary pl-3 mb-3">
                                <li>Creates missing IBED term config support tables.</li>
                                <li>Adds grade equivalency and score conversion tables.</li>
                                <li>Adds term columns to subject plot and cluster plot.</li>
                                <li>Adds optional section scoping to cluster plots.</li>
                                <li>Adds component grade columns to grades and gradesdetail.</li>
                            </ul>
                            <button type="button" class="btn btn-outline-primary btn-block" id="btn_check_status">
                                <i class="fas fa-search mr-1"></i> Check Status
                            </button>
                            <button type="button" class="btn btn-primary btn-block" id="btn_run_selected" disabled>
                                <i class="fas fa-play mr-1"></i> Run Selected
                            </button>
                            <small class="text-muted d-block mt-2">Run this only on the intended school database after backup/review.</small>
                        </div>
                    </div>
                </div>
                <div class="col-md-8">
                    <div class="card h-100">
                        <div class="card-header d-flex align-items-center justify-content-between">
                            <h3 class="card-title mb-0"><i class="fas fa-list text-primary mr-1"></i> Results</h3>
                            <span class="badge badge-secondary" id="migration_summary">Not run</span>
                        </div>
                        <div class="card-body p-0">
                            <div class="table-responsive">
                                <table class="table table-sm table-hover mb-0" id="migration_results_table">
                                    <thead>
                                        <tr>
                                            <th class="step-check"><input type="checkbox" id="check_all_steps" disabled></th>
                                            <th width="36%">Step</th>
                                            <th width="12%" class="text-center">Status</th>
                                            <th width="50%">Message</th>
                                        </tr>
                                    </thead>
                                    <tbody id="migration_results_body">
                                        <tr>
                                            <td colspan="4" class="text-center text-muted py-4">Check status before running migration items.</td>
                                        </tr>
                                    </tbody>
                                </table>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </section>
@endsection

@section('footerjavascript')
    <script>
        $(document).ready(function() {
            var CSRF_TOKEN = $('meta[name="csrf-token"]').attr('content');

            function statusBadge(status) {
                if (status === 'success') { return '<span class="badge badge-success status-pill">Added</span>'; }
                if (status === 'skipped') { return '<span class="badge badge-secondary status-pill">Skipped</span>'; }
                if (status === 'pending') { return '<span class="badge badge-warning status-pill">Pending</span>'; }
                return '<span class="badge badge-danger status-pill">Error</span>';
            }

            function escapeHtml(value) { return $('<div>').text(value || '').html(); }

            function updateRunButton() {
                $('#btn_run_selected').prop('disabled', $('.migration-step-checkbox:checked').length === 0);
            }

            function renderResults(results, selectable) {
                if (!results || results.length === 0) {
                    $('#migration_results_body').html('<tr><td colspan="4" class="text-center text-muted py-4">No result rows returned.</td></tr>');
                    $('#check_all_steps').prop('checked', false).prop('disabled', true);
                    updateRunButton();
                    return;
                }
                var rows = '';
                var successCount = 0, skippedCount = 0, errorCount = 0, pendingCount = 0, runnableCount = 0;
                $.each(results, function(index, item) {
                    if (item.status === 'success') { successCount++; }
                    if (item.status === 'skipped') { skippedCount++; }
                    if (item.status === 'error') { errorCount++; }
                    if (item.status === 'pending') { pendingCount++; }
                    if (item.runnable) { runnableCount++; }
                    var checkbox = '';
                    if (selectable && item.runnable) {
                        checkbox = '<input type="checkbox" class="migration-step-checkbox" value="' + escapeHtml(item.key) + '" checked>';
                    }
                    rows += '<tr>' +
                        '<td class="step-check">' + checkbox + '</td>' +
                        '<td>' + escapeHtml(item.label) + '</td>' +
                        '<td class="text-center">' + statusBadge(item.status) + '</td>' +
                        '<td>' + escapeHtml(item.message) + '</td>' +
                    '</tr>';
                });
                $('#migration_results_body').html(rows);
                $('#check_all_steps').prop('disabled', !selectable || runnableCount === 0).prop('checked', selectable && runnableCount > 0);
                $('#migration_summary')
                    .removeClass('badge-secondary badge-success badge-danger')
                    .addClass(errorCount > 0 ? 'badge-danger' : (pendingCount > 0 ? 'badge-secondary' : 'badge-success'))
                    .text(successCount + ' added, ' + skippedCount + ' skipped, ' + pendingCount + ' pending, ' + errorCount + ' errors');
                updateRunButton();
            }

            $('#btn_check_status').on('click', function() {
                var $btn = $(this);
                $btn.prop('disabled', true).html('<i class="fas fa-spinner fa-spin mr-1"></i> Checking...');
                $('#btn_run_selected').prop('disabled', true);
                $('#migration_summary').removeClass('badge-success badge-danger').addClass('badge-secondary').text('Checking');
                $('#migration_results_body').html('<tr><td colspan="4" class="text-center text-muted py-4">Checking migration status...</td></tr>');
                $.ajax({
                    type: 'POST', url: '/superadmin/term-grading-migration/status', data: { _token: CSRF_TOKEN },
                    success: function(res) { renderResults(res.results || [], true); },
                    error: function(xhr) {
                        var res = xhr.responseJSON || {};
                        renderResults(res.results || [], false);
                        Swal.fire({ type: 'error', title: 'Status Check Failed', text: res.message || 'Unable to check migration status.' });
                    },
                    complete: function() { $btn.prop('disabled', false).html('<i class="fas fa-search mr-1"></i> Check Status'); }
                });
            });

            $('#check_all_steps').on('change', function() {
                $('.migration-step-checkbox').prop('checked', $(this).prop('checked'));
                updateRunButton();
            });

            $(document).on('change', '.migration-step-checkbox', function() {
                var total = $('.migration-step-checkbox').length;
                var checked = $('.migration-step-checkbox:checked').length;
                $('#check_all_steps').prop('checked', total > 0 && total === checked);
                updateRunButton();
            });

            $('#btn_run_selected').on('click', function() {
                var $btn = $(this);
                var selected = $('.migration-step-checkbox:checked').map(function() { return $(this).val(); }).get();
                if (!selected.length) {
                    Swal.fire({ type: 'warning', title: 'No Items Selected', text: 'Please select at least one pending migration item.' });
                    return;
                }
                Swal.fire({
                    title: 'Run selected migration items?',
                    text: 'This will apply the checked additive schema changes to the current database.',
                    type: 'warning', showCancelButton: true, confirmButtonText: 'Run Selected', cancelButtonText: 'Cancel'
                }).then(function(result) {
                    if (!result.value) { return; }
                    $btn.prop('disabled', true).html('<i class="fas fa-spinner fa-spin mr-1"></i> Running...');
                    $('#migration_summary').removeClass('badge-success badge-danger').addClass('badge-secondary').text('Running');
                    $('#migration_results_body').html('<tr><td colspan="4" class="text-center text-muted py-4">Running selected migration items...</td></tr>');
                    $.ajax({
                        type: 'POST', url: '/superadmin/term-grading-migration/run', data: { _token: CSRF_TOKEN, steps: selected },
                        success: function(res) {
                            renderResults(res.results || [], false);
                            Swal.fire({ type: 'success', title: 'Migration Complete', text: res.message || 'Selected migration items completed.' });
                        },
                        error: function(xhr) {
                            var res = xhr.responseJSON || {};
                            renderResults(res.results || [], false);
                            Swal.fire({ type: 'error', title: 'Migration Finished With Errors', text: res.message || 'Please review the result table.' });
                        },
                        complete: function() { $btn.html('<i class="fas fa-play mr-1"></i> Run Selected'); updateRunButton(); }
                    });
                });
            });
        });
    </script>
@endsection
```

---

## File 3 — Routes

Add to `routes/web.php`, inside the superadmin-authenticated group (same group
that guards your other `/superadmin/*` pages):

```php
Route::get('/superadmin/term-grading-migration', 'SuperAdminController\TermGradingMigrationController@index')->name('term.grading.migration');
Route::post('/superadmin/term-grading-migration/status', 'SuperAdminController\TermGradingMigrationController@status')->name('term.grading.migration.status');
Route::post('/superadmin/term-grading-migration/run', 'SuperAdminController\TermGradingMigrationController@run')->name('term.grading.migration.run');
```

> If the target repo uses the array/`[Controller::class, 'method']` route style,
> convert accordingly. The POST routes rely on the standard `web` middleware
> group for CSRF (`_token` is posted from the view).

---

## File 4 — Sidenav entry

Add to the superadmin sidenav (`resources/views/superadmin/inc/sidenav.blade.php`
in es_ldcu), near the other migration/utility links:

```blade
<li class="nav-item">
    <a class="{{ Request::url() == url('/superadmin/term-grading-migration') ? 'active' : '' }} nav-link"
        href="/superadmin/term-grading-migration">
        <i class="nav-icon fas fa-database"></i>
        <p>Term Grading Migration</p>
    </a>
</li>
```

---

## Schema inventory (what this page applies)

**Tables created (9):** `ibed_term_config`, `ibed_term`,
`ibed_term_config_gradelevel`, `ibed_grade_point_equivalence`,
`ibed_grade_point_scale`, `ibed_score_conversion`, `ibed_ecr_item_grade`,
`sh_cluster_section_assignment`, `subject_plot_term` (per-plot term subsets — see
Module P2).

**Columns added:**

| Table | Columns |
|-------|---------|
| `ibed_term_config` | `ecr_sheet_title`, `formula_type`, `grade_point_equivalence_id`, `score_conversion_id`, `term_grade_display`, `final_grade_display`, `display_transmuted_grade`, `display_letter_grade`, `display_final_grade`, `display_grade_remarks_description`, `gradessetup_id`, `isactive` |
| `subject_gradessetup` | `comp4`, `comp1desc`…`comp4desc`, `components_json`, `input_mode` |
| `subject_plot` | `termid`, `prev_semid` |
| `sh_classsched` | `prev_semid`, **`semid` → NULLABLE (MODIFY)** |
| `sh_enrolledstud` | `promotion_status_per_terms`, `active_term_id` |
| `sh_cluster_plot` | `termid`, `prev_semid` |
| `sh_cluster_subject_picking` | `prev_semid`, `source_section_assignment_id` |
| `grades` | `cghr1`, `cghr2`, `cghr3`, `cghrtotal` |
| `gradesdetail` | `cgtotal`, `cgws`, `cgps`, `cg1`…`cg4`, `transmuted_grade`, `letter_grade` |
| `sy` | `term_grading_status` |

---

## Porting notes / gotchas

1. **Table names are literal.** The runner assumes CK-standard names
   (`sh_classsched`, `sh_cluster_plot`, `sh_cluster_subject_picking`,
   `sh_enrolledstud`, `subject_plot`, `subject_gradessetup`, `grades`,
   `gradesdetail`, `sy`). If a target school renamed any of these, update the
   `table` values in the matching steps.
2. **`AFTER` anchors are best-effort.** `addColumn()` only appends `AFTER x` when
   column `x` exists; otherwise the column is added at the end — safe either way.
   Notably `gradesdetail.transmuted_grade` anchors `AFTER qg`; if `qg` doesn't
   exist in the target, it lands at the end (fine).
3. **`sh_*` tables may be absent** on a school with no Senior High. Those steps
   will show **Error → "Table does not exist."** That's expected; skip them if the
   school has no SHS. The junior-only term flow doesn't need them.
4. **Idempotent & additive** — safe to re-run; existing objects are skipped. No
   data is modified, only schema. Still, run on the intended DB after a backup.
5. **`isactive` matters downstream.** Several grading paths only honor an
   *Inactive* term config when `ibed_term_config.isactive` exists. Do **not** skip
   `column_ibed_term_config_isactive`. (See es_ldcu
   `IBEDGradingDefaults::activeConfigQuery()`.)
6. **Access control** — place the routes behind the same superadmin auth
   middleware as the rest of `/superadmin/*`. The page runs DDL; it must not be
   publicly reachable.

---

## Verification

1. Visit `/superadmin/term-grading-migration`.
2. Click **Check Status** → every item lists as **Skipped** (already present) or
   **Pending** (will be added). No unexpected **Error** rows (except `sh_*` on a
   no-SHS school).
3. Select the pending items → **Run Selected** → confirm. Summary shows
   *"N added, M skipped, 0 errors."*
4. Click **Check Status** again → previously pending items now show **Skipped**.
5. Spot-check in the DB:
   ```sql
   SHOW COLUMNS FROM sy LIKE 'term_grading_status';
   SHOW COLUMNS FROM ibed_term_config LIKE 'isactive';
   SHOW COLUMNS FROM sh_classsched LIKE 'semid';   -- Null = YES
   SHOW TABLES LIKE 'ibed_ecr_item_grade';
   ```

Once green, proceed to **Module 02 — School Year term-grading toggle**.
