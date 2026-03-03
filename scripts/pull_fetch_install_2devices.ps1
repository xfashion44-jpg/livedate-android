param(
    [string]$RepoRoot = ".",
    [string]$ApkPath = ".\artifacts\app-debug-apk\app-debug.apk",
    [switch]$ForceUninstallEmulator
)

$ErrorActionPreference = "Stop"

function Require-Cmd([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $Name"
    }
}

function Get-FailureHint([string]$OutputText) {
    if ($OutputText -match "unauthorized") {
        return "Hint: unauthorized (approve USB debugging on the device)"
    }
    if ($OutputText -match "INSTALL_FAILED_UPDATE_INCOMPATIBLE") {
        return "Hint: INSTALL_FAILED_UPDATE_INCOMPATIBLE (likely signing mismatch)"
    }
    if ($OutputText -match "VERSION_DOWNGRADE") {
        return "Hint: VERSION_DOWNGRADE (installed versionCode is higher)"
    }
    return "Hint: check adb output logs"
}

function Get-ApplicationIdFromGradle([string]$ProjectRoot) {
    $candidates = @(
        (Join-Path $ProjectRoot "app\build.gradle.kts"),
        (Join-Path $ProjectRoot "app\build.gradle")
    )
    foreach ($path in $candidates) {
        if (-not (Test-Path $path)) {
            continue
        }
        $content = Get-Content $path -Raw
        $m = [regex]::Match($content, 'applicationId\s*(=)?\s*"([^"]+)"')
        if ($m.Success) {
            return $m.Groups[2].Value
        }
    }
    return $null
}

Write-Host "[1/6] Checking required tools..."
Require-Cmd "git"
Require-Cmd "gh"
Require-Cmd "adb"

$resolvedRepoRoot = (Resolve-Path $RepoRoot).Path
Set-Location $resolvedRepoRoot

Write-Host "[2/6] Download latest APK via pull_and_fetch_apk.ps1..."
& powershell -ExecutionPolicy Bypass -File ".\scripts\pull_and_fetch_apk.ps1"
if ($LASTEXITCODE -ne 0) {
    throw "pull_and_fetch_apk.ps1 failed (exit=$LASTEXITCODE)"
}

Write-Host "[3/6] Validate APK path..."
if (-not (Test-Path $ApkPath)) {
    throw "APK not found: $ApkPath"
}
$resolvedApkPath = (Resolve-Path $ApkPath).Path

Write-Host "[4/6] Read connected devices..."
$adbLines = adb devices
$targetDevices = @()
foreach ($line in $adbLines) {
    if ($line -match "^(?<serial>\S+)\s+device$") {
        $targetDevices += $Matches["serial"]
        continue
    }
    if ($line -match "^(?<serial>\S+)\s+unauthorized$") {
        Write-Warning "unauthorized device found: $($Matches['serial']) -> approve USB debugging on phone"
    }
}

if (-not $targetDevices -or $targetDevices.Count -eq 0) {
    throw "No installable devices. Need adb status 'device'."
}
if ($targetDevices.Count -lt 2) {
    Write-Warning "Less than 2 devices connected. Proceeding with $($targetDevices.Count) device(s)."
}

Write-Host "[5/6] Installing update in parallel..."
$jobs = @()
foreach ($serial in $targetDevices) {
    $jobs += Start-Job -ScriptBlock {
        param($DeviceSerial, $TargetApk)
        $output = & adb -s $DeviceSerial install -r -d $TargetApk 2>&1
        [pscustomobject]@{
            Serial = $DeviceSerial
            ExitCode = $LASTEXITCODE
            Output = ($output -join [Environment]::NewLine)
        }
    } -ArgumentList $serial, $resolvedApkPath
}

Wait-Job -Job $jobs | Out-Null
$results = Receive-Job -Job $jobs
Remove-Job -Job $jobs | Out-Null

Write-Host "[6/6] Summary..."
$failedCount = 0
$applicationId = $null
if ($ForceUninstallEmulator) {
    $applicationId = Get-ApplicationIdFromGradle -ProjectRoot $resolvedRepoRoot
    if (-not $applicationId) {
        Write-Warning "applicationId not found. Emulator uninstall fallback is skipped."
    } else {
        Write-Host " - emulator fallback applicationId: $applicationId"
    }
}

foreach ($r in $results) {
    $status = if ($r.ExitCode -eq 0 -and $r.Output -match "Success") { "Success" } else { "Fail" }

    if ($status -eq "Fail" -and $r.Serial -like "emulator-*" -and $r.Output -match "VERSION_DOWNGRADE") {
        if ($ForceUninstallEmulator -and $applicationId) {
            Write-Host " - $($r.Serial): VERSION_DOWNGRADE detected -> trying uninstall + reinstall"
            & adb -s $r.Serial uninstall $applicationId | Out-Host
            $retryOutput = & adb -s $r.Serial install -r $resolvedApkPath 2>&1
            $retryExitCode = $LASTEXITCODE
            $retryText = ($retryOutput -join [Environment]::NewLine)
            $r.Output = $r.Output + [Environment]::NewLine + "[retry] " + $retryText
            if ($retryExitCode -eq 0 -and $retryText -match "Success") {
                $status = "Success"
            }
        } else {
            Write-Warning "$($r.Serial): VERSION_DOWNGRADE detected. Use -ForceUninstallEmulator."
        }
    }

    Write-Host " - $($r.Serial): $status"
    if ($status -eq "Fail") {
        $failedCount++
        $hint = Get-FailureHint -OutputText $r.Output
        Write-Host "   $hint"
        Write-Host "   Log: $($r.Output)"
    }
}

Write-Host ""
Write-Host "Done:"
Write-Host "  RepoRoot : $resolvedRepoRoot"
Write-Host "  APK      : $resolvedApkPath"
Write-Host "  Devices  : $($targetDevices -join ', ')"

if ($failedCount -gt 0) {
    exit 1
}
