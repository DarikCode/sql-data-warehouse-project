/*
=============================================================
 DDL: Pipeline run log (etl schema)
=============================================================
 Purpose:
   Records every pipeline run and every step inside it:
   when it ran, how long it took, how many rows the layer
   held afterwards, and, if it failed, the error message.

   This answers the questions a data team asks every morning:
   "Did last night's load work? How long did it take? Did the
   row counts suddenly drop?"

 Tables:
   etl.pipeline_runs  one row per run of run_pipeline.ps1
   etl.step_log       one row per step (bronze load, silver
                      load, quality checks...) of each run

 Safe to re-run: uses IF NOT EXISTS / OR REPLACE, so existing
 log history is kept.

 Why the log is written by the pipeline script, not inside the
 load procedures:
   When a procedure fails, PostgreSQL rolls back EVERYTHING it
   did, including any log rows it wrote. A failure would
   erase its own error message. Writing the log from outside,
   in separate transactions, means failures are always
   recorded.
=============================================================
*/

CREATE SCHEMA IF NOT EXISTS etl;

CREATE TABLE IF NOT EXISTS etl.pipeline_runs (
    run_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    started_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at   TIMESTAMPTZ,
    duration_ms   INT,
    status        VARCHAR(10) NOT NULL DEFAULT 'running'
                  CHECK (status IN ('running', 'success', 'failed')),
    run_by        VARCHAR(100) NOT NULL DEFAULT current_user,
    rebuild       BOOLEAN NOT NULL DEFAULT false
);

CREATE TABLE IF NOT EXISTS etl.step_log (
    step_id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_id        BIGINT NOT NULL REFERENCES etl.pipeline_runs (run_id),
    step_order    INT NOT NULL,
    step_name     VARCHAR(50) NOT NULL,
    started_at    TIMESTAMPTZ,
    finished_at   TIMESTAMPTZ,
    duration_ms   INT,
    status        VARCHAR(10) NOT NULL
                  CHECK (status IN ('running', 'success', 'failed', 'skipped')),
    rows_in_layer BIGINT,   -- total rows in the layer after the step
    message       TEXT      -- error details when a step fails
);

/*
 etl.count_rows(schema): exact total row count of every table
 and view in a schema. Used to log how many rows each layer
 holds after its load step, so a sudden drop is visible.
*/
CREATE OR REPLACE FUNCTION etl.count_rows(p_schema TEXT)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_obj    RECORD;
    v_count  BIGINT;
    v_total  BIGINT := 0;
BEGIN
    FOR v_obj IN
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = p_schema
    LOOP
        -- format(%I) quotes the names safely
        EXECUTE format('SELECT COUNT(*) FROM %I.%I', p_schema, v_obj.table_name)
        INTO v_count;
        v_total := v_total + v_count;
    END LOOP;
    RETURN v_total;
END;
$$;
