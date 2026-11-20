<#
=============================================================
 run_pipeline.ps1 - run the whole data warehouse in one command
=============================================================
 What it does, in order:
   1. bronze_load    CSV files -> bronze tables
   2. silver_load    bronze -> silver (cleaning)
   3. silver_checks  quality checks on silver
   4. gold_refresh   (re)create the gold star schema views
   5. gold_checks    quality checks on gold

 Every run and every step is logged in etl.pipeline_runs and
 etl.step_log. If a step fails, the run stops, the error is
 logged, the remaining steps are marked 'skipped', and the
 script exits with code 1 (so a scheduler or CI job sees the
 failure).

 Usage (from any folder):
   .\run_pipeline.ps1              load and test
   .\run_pipeline.ps1 -Rebuild     drop and recreate the whole
                                   database first (deletes all
                                   data and the run history)
   .\run_pipeline.ps1 -ShowOutput  also print psql's full output

 Connection:
   Defaults to localhost:5432, user postgres, database
   datawarehouse. Override with parameters, or with the
   standard PGHOST / PGPORT / PGUSER environment variables.
   The password is read by psql from pgpass.conf or the
   PGPASSWORD environment variable; it never appears here.

 Works on Windows PowerShell 5.1 and PowerShell 7 (pwsh),
 including on Linux.
=============================================================
#>
[CmdletBinding()]
param(
    [switch]$Rebuild,
    [switch]$ShowOutput,
    [string]$DbHost   = $(if ($env:PGHOST) { $env:PGHOST } else { 'localhost' }),
    [int]   $Port     = $(if ($env:PGPORT) { [int]$env:PGPORT } else { 5432 }),
    [string]$User     = $(if ($env:PGUSER) { $env:PGUSER } else { 'postgres' }),
    [string]$Database = 'datawarehouse',
    [string]$PsqlPath
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------
# Setup
# ---------------------------------------------------------------

# Find psql: explicit path, then PATH, then the default Windows install folder
if (-not $PsqlPath) {
    $cmd = Get-Command psql -ErrorAction SilentlyContinue
    if ($cmd) {
        $PsqlPath = $cmd.Source
    } else {
        $found = Get-ChildItem 'C:\Program Files\PostgreSQL\*\bin\psql.exe' -ErrorAction SilentlyContinue |
                 Sort-Object FullName -Descending | Select-Object -First 1
        if ($found) { $PsqlPath = $found.FullName }
    }
}
if (-not $PsqlPath -or -not (Test-Path $PsqlPath)) {
    throw 'psql not found. Add PostgreSQL''s bin folder to PATH, or pass -PsqlPath.'
}

# Talk to psql in UTF-8 both ways
$env:PGCLIENTENCODING = 'UTF8'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = $utf8
$previousConsoleEncoding = [Console]::OutputEncoding
[Console]::OutputEncoding = $utf8

# File paths in the SQL scripts are relative to the project root
Push-Location $PSScriptRoot

# ---------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------

# Run psql with either a file or a SQL string. SQL is sent through
# stdin, which avoids Windows command-line quoting problems.
function Invoke-Psql {
    param(
        [string]$Db = $Database,
        [string]$File,
        [string]$Sql,
        [switch]$Scalar
    )
    $psqlArgs = @('-h', $DbHost, '-p', $Port, '-U', $User, '-d', $Db,
                  '-w', '-X', '-q', '-v', 'ON_ERROR_STOP=1', '-P', 'footer=off')
    if ($Scalar) { $psqlArgs += @('-A', '-t') }
    if ($File)   { $psqlArgs += @('-f', $File) }

    # psql writes NOTICEs to stderr; in Windows PowerShell 5.1 that
    # must not be treated as a script error, only the exit code counts.
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($Sql) { $out = $Sql | & $PsqlPath @psqlArgs 2>&1 }
        else      { $out = & $PsqlPath @psqlArgs 2>&1 }
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    $text = (@($out) | ForEach-Object { "$_" }) -join "`n"
    [pscustomobject]@{ ExitCode = $code; Output = $text.Trim() }
}

# Same, but stop the script if it fails (for setup and logging calls)
function Invoke-PsqlOrThrow {
    param([string]$Db = $Database, [string]$File, [string]$Sql, [switch]$Scalar)
    $r = Invoke-Psql -Db $Db -File $File -Sql $Sql -Scalar:$Scalar
    if ($r.ExitCode -ne 0) {
        throw "psql failed ($File$Sql):`n$($r.Output)"
    }
    return $r.Output
}

# Turn a PowerShell string into a safe SQL string literal
function ConvertTo-SqlLiteral {
    param([string]$Value)
    if ($null -eq $Value) { return 'NULL' }
    return "'" + $Value.Replace("'", "''") + "'"
}

function Write-Banner {
    param([string]$Text)
    Write-Host ''
    Write-Host ('=' * 56)
    Write-Host " $Text"
    Write-Host ('=' * 56)
}

# ---------------------------------------------------------------
# The pipeline steps
#   Layer: whose rows to count after the step (for the log)
# ---------------------------------------------------------------
$steps = @(
    @{ Name = 'bronze_load';   Layer = 'bronze'; File = 'scripts/bronze/load_bronze.sql' },
    @{ Name = 'silver_load';   Layer = 'silver'; Sql  = 'CALL silver.load_silver();' },
    @{ Name = 'silver_checks'; Layer = $null;    File = 'tests/quality_checks_silver.sql' },
    @{ Name = 'gold_refresh';  Layer = 'gold';   File = 'scripts/gold/ddl_gold.sql' },
    @{ Name = 'gold_checks';   Layer = $null;    File = 'tests/quality_checks_gold.sql' }
)

$exitCode = 0
$runTimer = [Diagnostics.Stopwatch]::StartNew()

try {
    Write-Banner "Data warehouse pipeline  ->  $User@${DbHost}:$Port/$Database"

    # -----------------------------------------------------------
    # Optional: rebuild everything from scratch
    # -----------------------------------------------------------
    if ($Rebuild) {
        Write-Host ''
        Write-Host 'Rebuild: recreating the database and all tables...'
        Invoke-PsqlOrThrow -Db 'postgres' -File 'scripts/00_init_database.sql' | Out-Null
        foreach ($f in 'scripts/bronze/ddl_bronze.sql', 'scripts/silver/ddl_silver.sql') {
            Invoke-PsqlOrThrow -File $f | Out-Null
            Write-Host "  created  $f"
        }
    }

    # -----------------------------------------------------------
    # Deploy code objects. All of these are safe to re-run:
    # they keep data and log history.
    # -----------------------------------------------------------
    Invoke-PsqlOrThrow -File 'scripts/etl/ddl_etl.sql' | Out-Null
    Invoke-PsqlOrThrow -File 'scripts/silver/proc_load_silver.sql' | Out-Null

    # -----------------------------------------------------------
    # Start the run
    # -----------------------------------------------------------
    $rebuildSql = if ($Rebuild) { 'true' } else { 'false' }
    $runId = Invoke-PsqlOrThrow -Scalar -Sql "INSERT INTO etl.pipeline_runs (rebuild) VALUES ($rebuildSql) RETURNING run_id;"
    $runId = [int64]($runId -split "`n")[0]

    Write-Host ''
    Write-Host "Run #$runId"
    Write-Host ''

    $failed = $false
    $order = 0

    foreach ($step in $steps) {
        $order++
        $name = $step.Name

        # Once a step has failed, the rest are skipped (and logged as such)
        if ($failed) {
            Invoke-PsqlOrThrow -Sql "INSERT INTO etl.step_log (run_id, step_order, step_name, status) VALUES ($runId, $order, '$name', 'skipped');" | Out-Null
            Write-Host ("  [SKIP]  {0,-15}" -f $name) -ForegroundColor DarkGray
            continue
        }

        $stepId = Invoke-PsqlOrThrow -Scalar -Sql "INSERT INTO etl.step_log (run_id, step_order, step_name, status, started_at) VALUES ($runId, $order, '$name', 'running', now()) RETURNING step_id;"
        $stepId = [int64]($stepId -split "`n")[0]

        $timer = [Diagnostics.Stopwatch]::StartNew()
        $result = Invoke-Psql -File $step.File -Sql $step.Sql
        $timer.Stop()
        $seconds = '{0,6:N2}s' -f $timer.Elapsed.TotalSeconds

        if ($ShowOutput -and $result.Output) {
            Write-Host $result.Output -ForegroundColor DarkGray
        }

        if ($result.ExitCode -eq 0) {
            $rowsSql = 'NULL'
            $rowsText = ''
            if ($step.Layer) {
                $rows = Invoke-PsqlOrThrow -Scalar -Sql "SELECT etl.count_rows('$($step.Layer)');"
                $rowsSql = [int64]$rows
                $rowsText = '{0,10:N0} rows in {1}' -f [int64]$rows, $step.Layer
            }
            Invoke-PsqlOrThrow -Sql "UPDATE etl.step_log SET status = 'success', finished_at = now(), duration_ms = (EXTRACT(EPOCH FROM now() - started_at) * 1000)::int, rows_in_layer = $rowsSql WHERE step_id = $stepId;" | Out-Null
            Write-Host ("  [ OK ]  {0,-15} {1}  {2}" -f $name, $seconds, $rowsText) -ForegroundColor Green
        }
        else {
            $failed = $true
            # Keep the most useful lines: errors and failed checks
            $lines = $result.Output -split "`n"
            $important = @($lines | Where-Object { $_ -match 'ERROR|FAIL' })
            if ($important.Count -eq 0) { $important = @($lines | Select-Object -Last 20) }
            $message = ($important -join "`n").Trim()
            if ($message.Length -gt 4000) { $message = $message.Substring(0, 4000) }

            Invoke-PsqlOrThrow -Sql "UPDATE etl.step_log SET status = 'failed', finished_at = now(), duration_ms = (EXTRACT(EPOCH FROM now() - started_at) * 1000)::int, message = $(ConvertTo-SqlLiteral $message) WHERE step_id = $stepId;" | Out-Null
            Write-Host ("  [FAIL]  {0,-15} {1}" -f $name, $seconds) -ForegroundColor Red
            foreach ($l in $important) { Write-Host "          $l" -ForegroundColor Red }
        }
    }

    # -----------------------------------------------------------
    # Finish the run
    # -----------------------------------------------------------
    $status = if ($failed) { 'failed' } else { 'success' }
    Invoke-PsqlOrThrow -Sql "UPDATE etl.pipeline_runs SET status = '$status', finished_at = now(), duration_ms = (EXTRACT(EPOCH FROM now() - started_at) * 1000)::int WHERE run_id = $runId;" | Out-Null

    $runTimer.Stop()
    if ($failed) {
        Write-Banner ("Run #{0} FAILED after {1:N1}s  (details: etl.step_log)" -f $runId, $runTimer.Elapsed.TotalSeconds)
        $exitCode = 1
    } else {
        Write-Banner ("Run #{0} succeeded in {1:N1}s" -f $runId, $runTimer.Elapsed.TotalSeconds)
    }
}
catch {
    # Setup or logging itself failed (e.g. database not reachable)
    Write-Host ''
    Write-Host "PIPELINE ERROR: $($_.Exception.Message)" -ForegroundColor Red
    $exitCode = 2
}
finally {
    Pop-Location
    [Console]::OutputEncoding = $previousConsoleEncoding
}

exit $exitCode
