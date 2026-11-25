<#
.SYNOPSIS
    Drive NVIDIA Mosaic from the command line with configureMosaic.exe (no Control Panel).

.DESCRIPTION
    Actions:
      Help     configureMosaic help: the commands and options this driver supports
      Query    GPUs, displays and current grids                          (read-only)
      Test     check the wall layout without applying it                 (read-only)
      Save     print the current setup as a command line (listconfigcmd) (read-only)
      Apply    save current setup, test, ask, then set the wall layout   (CHANGES DISPLAYS)
      Disable  save current setup, ask, then turn Mosaic off             (CHANGES DISPLAYS)

    Every command, its exit code, timing and output are saved under windows\results\
    and appended to windows\results\mosaic-cli-log.txt, so the exact command that
    worked is on record.

    configureMosaic exit codes (NVIDIA readme): 0 success, 1 success with warnings,
    2 invalid command or parameters.

    WALL SETTINGS: the parameter defaults below describe the target wall. Edit them in
    Notepad if the wall changes, or override them on the command line.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File mosaic-cli.ps1 -Action Test
.EXAMPLE
    ... -Action Apply -Outputs "0,0 0,1 0,2 1,0 1,1 2,0 2,1 3,0 3,1"
.EXAMPLE
    ... -Action Test -ExtraArgs "overlapcol=-40"   (check the option name with -Action Help)
#>
param(
    [ValidateSet("Help", "Query", "Test", "Save", "Apply", "Disable")]
    [string]$Action = "Query",

    # ---------------- WALL SETTINGS (defaults) ----------------
    [int]$Rows = 1,
    [int]$Cols = 9,
    [int]$Width = 3840,          # native panel resolution (landscape); -Rotate makes it portrait
    [int]$Height = 2160,
    [int]$Refresh = 60,
    [ValidateSet(0, 90, 180, 270)]
    [int]$Rotate = 90,
    # Displays as "GPU,port" in row-major order (left to right for a 1x9 row).
    # Leave EMPTY to let configureMosaic choose the order (recommended for the first try),
    # then check the order with testpattern.html and fill this in if it is wrong.
    # 3/2/2/2 example: -Outputs "0,0 0,1 0,2 1,0 1,1 2,0 2,1 3,0 3,1"
    [string[]]$Outputs = @(),
    # Extra set/test options (e.g. overlap/bezel) once -Action Help shows their names.
    [string[]]$ExtraArgs = @(),
    # -----------------------------------------------------------

    [string]$ToolPath = "",
    [string]$OutDir = "",
    [int]$SetTimeoutSec = 300,
    [switch]$Yes
)

$ErrorActionPreference = "Continue"

# Accept "0,0 0,1 0,2" as one string (what `powershell -File` passes) as well as a real array.
$Outputs = @($Outputs | ForEach-Object { $_ -split '\s+' } | Where-Object { $_ })
$ExtraArgs = @($ExtraArgs | ForEach-Object { $_ -split '\s+' } | Where-Object { $_ })

# ---------------------------------------------------------------------------
# Find configureMosaic.exe
# ---------------------------------------------------------------------------

function Find-Tool {
    if ($ToolPath) {
        if (Test-Path $ToolPath) { return (Resolve-Path $ToolPath).Path }
        throw "configureMosaic.exe not found at -ToolPath $ToolPath"
    }
    $local = Join-Path $PSScriptRoot "configureMosaic.exe"
    if (Test-Path $local) { return $local }
    $cmd = Get-Command configureMosaic.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($r in @("$env:ProgramFiles\NVIDIA Corporation", "${env:ProgramFiles(x86)}\NVIDIA Corporation")) {
        if ($r -and (Test-Path $r)) {
            $hit = Get-ChildItem -Path $r -Recurse -Filter "configureMosaic.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
    }
    throw "configureMosaic.exe not found. Put it next to this script or pass -ToolPath."
}

# ---------------------------------------------------------------------------
# Results folder, log, and command runner
# ---------------------------------------------------------------------------

if (-not $OutDir) { $OutDir = Join-Path $PSScriptRoot "results" }
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runDir = Join-Path $OutDir "$stamp-mosaic-$($Action.ToLower())"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$logFile = Join-Path $OutDir "mosaic-cli-log.txt"

function Exit-Meaning($code) {
    switch ("$code") {
        "0" { return "success" }
        "1" { return "success with warnings" }
        "2" { return "invalid command or parameters" }
        default { return "see output" }
    }
}

function Run-Mosaic {
    # Run configureMosaic with the given arguments, show and save the output.
    param([string]$Name, [string[]]$ArgList, [int]$TimeoutSec = 60, [switch]$Quiet)
    $argString = ($ArgList -join ' ')
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $script:Tool
    $psi.Arguments = $argString
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    Write-Host ""
    Write-Host "> configureMosaic.exe $argString" -ForegroundColor Yellow
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $p = [System.Diagnostics.Process]::Start($psi)
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { $p.Kill() } catch {}
        $code = "TIMEOUT"
    } else {
        $p.WaitForExit()
        $code = $p.ExitCode
    }
    $sw.Stop()
    $secs = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    $out = $outTask.Result
    $err = $errTask.Result

    $text = "COMMAND: `"$($script:Tool)`" $argString`r`nTIME: $(Get-Date -Format o)`r`n" +
            "EXIT: $code ($(Exit-Meaning $code))`r`nSECONDS: $secs`r`n--- STDOUT ---`r`n$out`r`n--- STDERR ---`r`n$err"
    $text | Out-File -FilePath (Join-Path $runDir "$Name.txt") -Encoding utf8
    "$(Get-Date -Format o)`t$Action`t$Name`texit=$code`t${secs}s`tconfigureMosaic.exe $argString" |
        Out-File -FilePath $logFile -Encoding utf8 -Append

    if (-not $Quiet) {
        if ($out) { Write-Host $out }
        if ($err) { Write-Host $err -ForegroundColor Red }
    }
    $color = "Green"
    if ("$code" -ne "0") { $color = "Red" }
    if ("$code" -eq "1") { $color = "Yellow" }
    Write-Host "exit $code ($(Exit-Meaning $code)) in $secs s" -ForegroundColor $color
    return "$code"
}

function Grid-Args {
    $a = @("rows=$Rows", "cols=$Cols", "res=$Width,$Height,$Refresh")
    if ($Rotate -ne 0) { $a += "rotate=$Rotate" }
    if ($Outputs.Count -gt 0) {
        if ($Outputs.Count -ne ($Rows * $Cols)) {
            throw "-Outputs has $($Outputs.Count) entries but the grid needs $($Rows * $Cols). (NVIDIA: if you give any display you must give all of them.)"
        }
        foreach ($o in $Outputs) {
            if ($o -notmatch '^\d+,\d+(,[a-z]+)?$') { throw "Bad output '$o': expected GPU,port such as 0,1" }
            $a += "out=$o"
        }
    }
    return $a + $ExtraArgs
}

function Confirm-Change([string]$what) {
    if ($Yes) { return $true }
    Write-Host ""
    Write-Host "About to $what. The displays may go black for a while." -ForegroundColor Yellow
    Write-Host "The current setup was saved in: $runDir\before-listconfigcmd.txt"
    $answer = Read-Host "Type YES to continue"
    return ($answer -eq "YES")
}

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

try {
    $script:Tool = Find-Tool
    $fv = (Get-Item $script:Tool).VersionInfo
    Write-Host "configureMosaic.exe: $($script:Tool)  (version $($fv.FileVersion))"
    Write-Host "Results: $runDir"

    switch ($Action) {
        "Help"  { Run-Mosaic "help" @("help") | Out-Null }
        "Query" { Run-Mosaic "query" @("query") | Out-Null }
        "Save"  { Run-Mosaic "listconfigcmd" @("listconfigcmd") | Out-Null }

        "Test" {
            $code = Run-Mosaic "test" (@("test") + (Grid-Args))
            if ($code -eq "0" -or $code -eq "1") { Write-Host "Layout accepted by the driver (nothing was changed)." -ForegroundColor Green }
            else { Write-Host "Layout rejected (nothing was changed). Read the output above." -ForegroundColor Red }
        }

        "Apply" {
            $grid = Grid-Args
            Run-Mosaic "before-listconfigcmd" @("listconfigcmd") -Quiet | Out-Null
            Run-Mosaic "before-query" @("query") -Quiet | Out-Null
            $code = Run-Mosaic "test" (@("test") + $grid)
            if (-not ($code -eq "0" -or $code -eq "1")) {
                Write-Host "Test failed, so nothing was applied." -ForegroundColor Red
                break
            }
            if (-not (Confirm-Change "apply: configureMosaic.exe set $($grid -join ' ')")) {
                Write-Host "Cancelled; nothing was changed."
                break
            }
            $code = Run-Mosaic "set" (@("set") + $grid) -TimeoutSec $SetTimeoutSec
            Write-Host "Waiting 10 s for the displays to settle..."
            Start-Sleep -Seconds 10
            Run-Mosaic "after-query" @("query") -Quiet | Out-Null
            Run-Mosaic "after-listconfigcmd" @("listconfigcmd") | Out-Null
            if ($code -eq "0" -or $code -eq "1") {
                Write-Host "Applied. Check the wall with testpattern.html (press 2 for display order)." -ForegroundColor Green
            } else {
                Write-Host "Set failed. To go back, run the command saved in before-listconfigcmd.txt, or -Action Disable." -ForegroundColor Red
            }
        }

        "Disable" {
            Run-Mosaic "before-listconfigcmd" @("listconfigcmd") -Quiet | Out-Null
            if (-not (Confirm-Change "turn Mosaic off")) { Write-Host "Cancelled; nothing was changed."; break }
            Run-Mosaic "disable" @("disable") -TimeoutSec $SetTimeoutSec | Out-Null
            Start-Sleep -Seconds 5
            Run-Mosaic "after-query" @("query") -Quiet | Out-Null
        }
    }
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    "$(Get-Date -Format o)`t$Action`tERROR`t$($_.Exception.Message)" | Out-File -FilePath $logFile -Encoding utf8 -Append
    exit 2
}
