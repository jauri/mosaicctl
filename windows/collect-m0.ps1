<#
.SYNOPSIS
    mosaicctl M0 data collector for the Windows Mosaic machine.

.DESCRIPTION
    READ-ONLY. This script never changes display, Mosaic or frame lock settings.
    It records GPUs, displays, driver versions, the sync board, configureMosaic.exe
    output and NVAPI information into a timestamped folder and a .zip file, so the
    results can be carried back to the development machine.

    Run it once per state you want to capture, with a different -Label each time,
    for example: baseline, mosaic-on, framelock-on.

.PARAMETER Label
    Short name for the current state. Letters, digits, - and _ only.

.PARAMETER ToolPath
    Full path to configureMosaic.exe, if the script cannot find it by itself.

.PARAMETER OutDir
    Where to write results. Defaults to a "results" folder next to this script.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File collect-m0.ps1 -Label mosaic-on
#>
param(
    [string]$Label = "snapshot",
    [string]$ToolPath = "",
    [string]$OutDir = ""
)

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

# ---------------------------------------------------------------------------
# Output folder and helpers
# ---------------------------------------------------------------------------

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$safeLabel = ($Label -replace '[^A-Za-z0-9_-]', '_')
if (-not $OutDir) { $OutDir = Join-Path $PSScriptRoot "results" }
$runDir = Join-Path $OutDir "$stamp-$safeLabel"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$summary = New-Object System.Collections.Generic.List[string]

function Note([string]$msg) {
    Write-Host $msg
    $summary.Add($msg)
}

function Section([string]$title) {
    Write-Host ""
    Write-Host "== $title ==" -ForegroundColor Cyan
    $summary.Add("")
    $summary.Add("== $title ==")
}

function Save-Text([string]$name, $content) {
    $path = Join-Path $runDir $name
    ($content | Out-String -Width 4096) | Out-File -FilePath $path -Encoding utf8
}

function Invoke-Capture {
    # Run a program, capture stdout/stderr/exit code/elapsed time, save to <Name>.txt.
    param(
        [string]$Name,
        [string]$Exe,
        [string[]]$ArgList = @(),
        [int]$TimeoutSec = 60
    )
    $quoted = $ArgList | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }
    $argString = ($quoted -join ' ')
    $header = "COMMAND: `"$Exe`" $argString`r`nTIME: $(Get-Date -Format o)`r`n"
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Exe
        $psi.Arguments = $argString
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $p = [System.Diagnostics.Process]::Start($psi)
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            try { $p.Kill() } catch {}
            $exit = "TIMEOUT after $TimeoutSec s"
        } else {
            $p.WaitForExit()
            $exit = $p.ExitCode
        }
        $sw.Stop()
        $text = $header + "EXIT: $exit`r`nELAPSED_MS: $($sw.ElapsedMilliseconds)`r`n" +
                "--- STDOUT ---`r`n" + $outTask.Result + "`r`n--- STDERR ---`r`n" + $errTask.Result
        Save-Text "$Name.txt" $text
        return "$exit"
    } catch {
        Save-Text "$Name.txt" ($header + "FAILED TO START: $($_.Exception.Message)")
        return "failed: $($_.Exception.Message)"
    }
}

function Try-Step([string]$title, [scriptblock]$block) {
    # Run one collection step; a failure is recorded but never stops the script.
    try { & $block }
    catch { Note "  ! $title failed: $($_.Exception.Message)" }
}

# ---------------------------------------------------------------------------
# 1. System
# ---------------------------------------------------------------------------

Section "System"
Try-Step "System" {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
               ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    Note "  Label:        $Label"
    Note "  Time:         $(Get-Date -Format o)"
    Note "  OS:           $($os.Caption) $($os.Version) build $($os.BuildNumber)"
    Note "  Machine:      $($cs.Manufacturer) $($cs.Model)"
    Note "  PowerShell:   $($PSVersionTable.PSVersion)  64-bit: $([Environment]::Is64BitProcess)"
    Note "  Administrator: $isAdmin"
    Save-Text "system.txt" (($os | Format-List * | Out-String) + ($cs | Format-List * | Out-String))
}

# ---------------------------------------------------------------------------
# 2. GPUs (Windows view and nvidia-smi)
# ---------------------------------------------------------------------------

Section "GPUs"
Try-Step "Win32_VideoController" {
    $vc = Get-CimInstance Win32_VideoController
    foreach ($v in $vc) {
        Note "  $($v.Name) | driver $($v.DriverVersion) | $($v.CurrentHorizontalResolution)x$($v.CurrentVerticalResolution) @ $($v.CurrentRefreshRate) Hz"
    }
    Save-Text "video-controllers.txt" ($vc | Format-List *)
}

$smi = $null
foreach ($c in @("$env:SystemRoot\System32\nvidia-smi.exe",
                 "$env:ProgramFiles\NVIDIA Corporation\NVSMI\nvidia-smi.exe")) {
    if (Test-Path $c) { $smi = $c; break }
}
if (-not $smi) {
    $cmd = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
    if ($cmd) { $smi = $cmd.Source }
}
if ($smi) {
    Note "  nvidia-smi: $smi"
    Invoke-Capture "nvidia-smi-L" $smi @("-L") | Out-Null
    Invoke-Capture "nvidia-smi-q" $smi @("-q") | Out-Null
    Invoke-Capture "nvidia-smi-csv" $smi @("--query-gpu=index,name,pci.bus_id,driver_version,vbios_version,serial,display_mode,display_active", "--format=csv") | Out-Null
    Try-Step "nvidia-smi summary" {
        $csv = Get-Content (Join-Path $runDir "nvidia-smi-csv.txt") | Where-Object { $_ -match '^\d+,' }
        foreach ($line in $csv) { Note "  $line" }
        Note "  GPU count (nvidia-smi): $($csv.Count)"
    }
} else {
    Note "  ! nvidia-smi.exe not found"
}

# ---------------------------------------------------------------------------
# 3. Monitors (EDID identity, connection type) and desktop screens
# ---------------------------------------------------------------------------

Section "Monitors"
Try-Step "WmiMonitorID" {
    function Decode($arr) { if ($arr) { (($arr | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join '') } else { "" } }
    $conn = @{}
    Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorConnectionParams -ErrorAction SilentlyContinue |
        ForEach-Object { $conn[$_.InstanceName] = $_.VideoOutputTechnology }
    # VideoOutputTechnology: 10 = DisplayPort external, 11 = DisplayPort embedded, 5 = HDMI, 4 = DVI
    $rows = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{
            Manufacturer = Decode $_.ManufacturerName
            Model        = Decode $_.UserFriendlyName
            ProductCode  = Decode $_.ProductCodeID
            Serial       = Decode $_.SerialNumberID
            Year         = $_.YearOfManufacture
            OutputTech   = $conn[$_.InstanceName]
            Active       = $_.Active
            InstanceName = $_.InstanceName
        }
    }
    foreach ($r in $rows) { Note "  $($r.Manufacturer) $($r.Model) serial=$($r.Serial) tech=$($r.OutputTech)" }
    Note "  Monitor count (EDID): $(@($rows).Count)"
    $models = @($rows | Select-Object -ExpandProperty Model -Unique)
    if ($models.Count -gt 1) { Note "  ! More than one monitor model found: $($models -join ', ')" }
    $rows | Export-Csv -NoTypeInformation -Path (Join-Path $runDir "monitors.csv")
    Save-Text "monitors.txt" ($rows | Format-Table -AutoSize)
}

Section "Desktop screens"
Try-Step "Screens" {
    # Ask for physical pixels so DPI scaling does not distort the numbers.
    Add-Type -Namespace M0 -Name Dpi -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();' -ErrorAction SilentlyContinue
    [M0.Dpi]::SetProcessDPIAware() | Out-Null
    Add-Type -AssemblyName System.Windows.Forms
    $screens = [System.Windows.Forms.Screen]::AllScreens
    foreach ($s in $screens) {
        $b = $s.Bounds
        Note "  $($s.DeviceName) primary=$($s.Primary) bounds=$($b.X),$($b.Y) $($b.Width)x$($b.Height)"
    }
    Note "  Screen count: $($screens.Count)  (with Mosaic on, the wall should appear as ONE screen)"
    Save-Text "screens.txt" ($screens | Format-List *)
}

# ---------------------------------------------------------------------------
# 4. Plug-and-play devices (displays, monitors, sync board)
# ---------------------------------------------------------------------------

Section "PnP devices"
Try-Step "PnP" {
    $pnp = Get-PnpDevice -ErrorAction Stop
    $disp = $pnp | Where-Object { $_.Class -in @("Display", "Monitor") }
    Save-Text "pnp-display-monitor.txt" ($disp | Format-Table Status, Class, FriendlyName, InstanceId -AutoSize)
    $sync = $pnp | Where-Object { $_.FriendlyName -match 'sync|frame ?lock|genlock' -or $_.InstanceId -match 'sync' }
    if ($sync) {
        foreach ($d in $sync) { Note "  Possible sync device: $($d.FriendlyName) [$($d.Status)] $($d.InstanceId)" }
    } else {
        Note "  No device with 'sync' in its name was found in PnP (the board may still be visible via NVAPI below)."
    }
    Save-Text "pnp-sync-candidates.txt" ($sync | Format-List *)
}

# ---------------------------------------------------------------------------
# 5. NVAPI probe (read-only: initialise, driver version, GPUs, sync devices)
# ---------------------------------------------------------------------------

Section "NVAPI"
$nvapiSource = @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;

public static class NvProbe {
    [DllImport("nvapi64.dll", EntryPoint = "nvapi_QueryInterface", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr QueryInterface(uint id);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int NoArgFn();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int ErrMsgFn(int status, byte[] text);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int DriverFn(out uint version, byte[] branch);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int EnumHandlesFn(IntPtr[] handles, out uint count);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int GpuNameFn(IntPtr gpu, byte[] name);

    // Interface IDs from NVIDIA's public nvapi_interface.h.
    const uint ID_Initialize      = 0x0150E828;
    const uint ID_Unload          = 0xD22BDD7E;
    const uint ID_GetErrorMessage = 0x6C2D048C;
    const uint ID_DriverVersion   = 0x2926AAAD; // NvAPI_SYS_GetDriverAndBranchVersion
    const uint ID_EnumGpus        = 0xE5AC921F; // NvAPI_EnumPhysicalGPUs
    const uint ID_GpuFullName     = 0xCEEE8E9F; // NvAPI_GPU_GetFullName
    const uint ID_EnumSync        = 0xD9639601; // NvAPI_GSync_EnumSyncDevices

    private static T Fn<T>(uint id) where T : class {
        IntPtr p = QueryInterface(id);
        if (p == IntPtr.Zero) return null;
        return Marshal.GetDelegateForFunctionPointer(p, typeof(T)) as T;
    }

    private static string Str(byte[] b) {
        int n = Array.IndexOf(b, (byte)0);
        if (n < 0) n = b.Length;
        return Encoding.ASCII.GetString(b, 0, n);
    }

    private static string Status(int s) {
        if (s == 0) return "OK";
        ErrMsgFn f = Fn<ErrMsgFn>(ID_GetErrorMessage);
        if (f == null) return "status " + s;
        byte[] buf = new byte[64];
        f(s, buf);
        return "status " + s + " (" + Str(buf) + ")";
    }

    public static List<string> Run() {
        List<string> o = new List<string>();
        NoArgFn init = Fn<NoArgFn>(ID_Initialize);
        if (init == null) { o.Add("NvAPI_Initialize not found"); return o; }
        int s = init();
        o.Add("NvAPI_Initialize: " + Status(s));
        if (s != 0) return o;

        DriverFn drv = Fn<DriverFn>(ID_DriverVersion);
        if (drv != null) {
            uint ver; byte[] branch = new byte[64];
            s = drv(out ver, branch);
            if (s == 0) o.Add(string.Format("Driver: {0}.{1:00}  branch: {2}", ver / 100, ver % 100, Str(branch)));
            else o.Add("Driver version: " + Status(s));
        }

        EnumHandlesFn enumGpus = Fn<EnumHandlesFn>(ID_EnumGpus);
        GpuNameFn gpuName = Fn<GpuNameFn>(ID_GpuFullName);
        if (enumGpus != null) {
            IntPtr[] gpus = new IntPtr[64]; uint n;
            s = enumGpus(gpus, out n);
            o.Add("Physical GPUs: " + (s == 0 ? n.ToString() : Status(s)));
            for (int i = 0; s == 0 && i < n; i++) {
                byte[] name = new byte[64];
                string nm = (gpuName != null && gpuName(gpus[i], name) == 0) ? Str(name) : "?";
                o.Add("  GPU " + i + ": " + nm);
            }
        }

        EnumHandlesFn enumSync = Fn<EnumHandlesFn>(ID_EnumSync);
        if (enumSync == null) {
            o.Add("NvAPI_GSync_EnumSyncDevices not available in this driver");
        } else {
            IntPtr[] sync = new IntPtr[64]; uint n;
            s = enumSync(sync, out n);
            o.Add("Sync devices (GSync_EnumSyncDevices): " + (s == 0 ? n.ToString() : Status(s)));
        }

        NoArgFn unload = Fn<NoArgFn>(ID_Unload);
        if (unload != null) unload();
        return o;
    }
}
'@
Try-Step "NVAPI" {
    if (-not [Environment]::Is64BitProcess) { throw "run from 64-bit PowerShell (nvapi64.dll)" }
    if (-not ("NvProbe" -as [type])) { Add-Type -TypeDefinition $nvapiSource -Language CSharp }
    $lines = [NvProbe]::Run()
    foreach ($l in $lines) { Note "  $l" }
    Save-Text "nvapi.txt" $lines
}

# ---------------------------------------------------------------------------
# 6. configureMosaic.exe (read-only commands only)
# ---------------------------------------------------------------------------

Section "configureMosaic.exe"
$found = New-Object System.Collections.Generic.List[string]
if ($ToolPath -and (Test-Path $ToolPath)) { $found.Add((Resolve-Path $ToolPath).Path) }
Try-Step "search" {
    $cmd = Get-Command configureMosaic.exe -ErrorAction SilentlyContinue
    if ($cmd) { $found.Add($cmd.Source) }
    $roots = @($PSScriptRoot,
               "$env:ProgramFiles\NVIDIA Corporation",
               "${env:ProgramFiles(x86)}\NVIDIA Corporation")
    foreach ($r in $roots) {
        if ($r -and (Test-Path $r)) {
            Get-ChildItem -Path $r -Recurse -Filter "configureMosaic*.exe" -ErrorAction SilentlyContinue |
                ForEach-Object { $found.Add($_.FullName) }
        }
    }
    $store = "$env:SystemRoot\System32\DriverStore\FileRepository"
    if (Test-Path $store) {
        Get-ChildItem -Path $store -Directory -Filter "nv*" -ErrorAction SilentlyContinue | ForEach-Object {
            Get-ChildItem -Path $_.FullName -Recurse -Filter "configureMosaic*.exe" -ErrorAction SilentlyContinue |
                ForEach-Object { $found.Add($_.FullName) }
        }
    }
}
$tools = @($found | Select-Object -Unique)
if ($tools.Count -eq 0) {
    Note "  ! configureMosaic.exe not found. Get it from NVIDIA, put it next to this script, and run again"
    Note "    (or pass -ToolPath C:\path\to\configureMosaic.exe)."
} else {
    foreach ($t in $tools) {
        $fv = (Get-Item $t).VersionInfo
        Note "  Found: $t  (file version $($fv.FileVersion), product $($fv.ProductVersion))"
    }
    $tool = $tools[0]
    Note "  Using: $tool"
    # Only commands that print information. Nothing here sets or disables Mosaic.
    $readOnly = @(
        @{ Name = "cm-noargs";              Args = @() },
        @{ Name = "cm-help";                Args = @("help") },
        @{ Name = "cm-dash-help";           Args = @("-help") },
        @{ Name = "cm-query";               Args = @("query") },
        @{ Name = "cm-query-current";       Args = @("query", "current") },
        @{ Name = "cm-query-gpus";          Args = @("query", "gpus") },
        @{ Name = "cm-query-displays";      Args = @("query", "displays") },
        @{ Name = "cm-query-topos";         Args = @("query", "topos") },
        @{ Name = "cm-listconfigcommands";  Args = @("listconfigcommands") }
    )
    foreach ($c in $readOnly) {
        $exit = Invoke-Capture $c.Name $tool $c.Args 60
        Note ("  {0,-24} exit {1}" -f (($c.Args -join ' ') -replace '^$', '(no args)'), $exit)
    }
}

# ---------------------------------------------------------------------------
# 7. Python (needed later to run mosaicctl itself) and recent driver events
# ---------------------------------------------------------------------------

Section "Python"
Try-Step "Python" {
    $py = Get-Command py.exe, python.exe -ErrorAction SilentlyContinue | Where-Object { $_.Source -notmatch 'WindowsApps' }
    if ($py) {
        foreach ($p in $py) { Note "  $($p.Source): $(& $p.Source --version 2>&1)" }
    } else {
        Note "  Python not found (it will be needed to run mosaicctl; 3.12 or newer from python.org)."
    }
}

Section "Driver events (last 7 days)"
Try-Step "Events" {
    $ev = Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'nvlddmkm'; StartTime = (Get-Date).AddDays(-7) } -MaxEvents 200 -ErrorAction SilentlyContinue
    Note "  nvlddmkm events: $(@($ev).Count)"
    Save-Text "events-nvlddmkm.txt" ($ev | Format-List TimeCreated, Id, LevelDisplayName, Message)
}

# ---------------------------------------------------------------------------
# Finish
# ---------------------------------------------------------------------------

Save-Text "summary.txt" $summary
$zip = "$runDir.zip"
Try-Step "zip" { Compress-Archive -Path (Join-Path $runDir "*") -DestinationPath $zip -Force }

Write-Host ""
Write-Host "Done. Results folder: $runDir" -ForegroundColor Green
if (Test-Path $zip) { Write-Host "Zip to bring back:   $zip" -ForegroundColor Green }
Write-Host "Read summary.txt first. Nothing on this machine was changed."
