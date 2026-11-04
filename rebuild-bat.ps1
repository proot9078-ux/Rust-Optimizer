$root  = Split-Path -Parent $MyInvocation.MyCommand.Path
$parts = Join-Path $root 'src\parts'
$ps1   = Join-Path $root 'src\RustOptimizer.ps1'
$bat   = Join-Path $root 'RustOptimizer.bat'
$dist  = Join-Path $root 'dist'
$standalone = Join-Path $dist 'RustOptimizer-standalone.bat'

# --- 1. Concatenate parts into one readable source file (UTF-8 with BOM) ---
if (Test-Path -LiteralPath $parts) {
    $files = @(Get-ChildItem -LiteralPath $parts -Filter '*.ps1' | Sort-Object Name)
    if ($files.Count -eq 0) { throw "No parts found in $parts" }
    $sb = New-Object System.Text.StringBuilder
    foreach ($f in $files) {
        $text = [IO.File]::ReadAllText($f.FullName)
        [void]$sb.AppendLine($text.TrimEnd())
        [void]$sb.AppendLine('')
    }
    [IO.File]::WriteAllText($ps1, $sb.ToString(), (New-Object System.Text.UTF8Encoding($true)))
    Write-Host ("Source built: {0} ({1} KB from {2} parts)" -f $ps1, [math]::Round((Get-Item $ps1).Length / 1KB), $files.Count)
}

# --- 2. Simple, readable launcher (for GitHub / local use) ---
$launcher = @'
@echo off
setlocal EnableExtensions
title PURPLE RUSH - RUST PERFORMANCE ENGINE
cd /d "%~dp0"
rem ============================================================
rem  PURPLE RUSH - RUST PERFORMANCE ENGINE
rem  Open source: MIT. Source: src\parts\*.ps1
rem  Right-click -> Run as administrator (recommended).
rem  First launch creates a desktop shortcut with the app icon.
rem ============================================================

if /i "%~1"=="elevated" goto run
fltmc >nul 2>&1
if errorlevel 1 (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList 'elevated' -Verb RunAs"
    exit /b
)

:run
start "" /b powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0src\RustOptimizer.ps1"
exit /b
'@
[System.IO.File]::WriteAllText($bat, $launcher, (New-Object System.Text.ASCIIEncoding))
Write-Host ("Launcher: {0} (readable, {1} bytes)" -f $bat, (Get-Item $bat).Length)

# --- 3. Optional single-file build for users who do not want a folder ---
if (-not (Test-Path -LiteralPath $dist)) { New-Item -ItemType Directory -Force -Path $dist | Out-Null }
$bytes = [System.IO.File]::ReadAllBytes($ps1)
$b64   = [System.Convert]::ToBase64String($bytes)
$lines = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $b64.Length; $i += 76) {
    $len = [Math]::Min(76, $b64.Length - $i)
    $lines.Add($b64.Substring($i, $len))
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('@echo off')
[void]$sb.AppendLine('setlocal EnableExtensions')
[void]$sb.AppendLine('title PURPLE RUSH - RUST PERFORMANCE ENGINE')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('rem ============================================================')
[void]$sb.AppendLine('rem  PURPLE RUSH - single-file launcher (self-contained)')
[void]$sb.AppendLine('rem  Right-click -> Run as administrator, or just double-click.')
[void]$sb.AppendLine('rem ============================================================')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('set "APP=%ProgramData%\RustOptimizer"')
[void]$sb.AppendLine('set "PS1=%APP%\app.ps1"')
[void]$sb.AppendLine('set "B64=%APP%\payload.b64"')
[void]$sb.AppendLine('set "RUSTOPT_LAUNCHER=%~f0"')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('rem --- self-elevation (safe: no loop) ---')
[void]$sb.AppendLine('if /i "%~1"=="elevated" goto run')
[void]$sb.AppendLine('fltmc >nul 2>&1')
[void]$sb.AppendLine('if errorlevel 1 (')
[void]$sb.AppendLine('    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath ''%~f0'' -ArgumentList ''elevated'' -Verb RunAs"')
[void]$sb.AppendLine('    exit /b')
[void]$sb.AppendLine(')')
[void]$sb.AppendLine('')
[void]$sb.AppendLine(':run')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('if not exist "%APP%" mkdir "%APP%" >nul 2>&1')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('> "%B64%" (')
[void]$sb.AppendLine('echo -----BEGIN CERTIFICATE-----')
foreach ($l in $lines) { [void]$sb.AppendLine('echo ' + $l) }
[void]$sb.AppendLine('echo -----END CERTIFICATE-----')
[void]$sb.AppendLine(')')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('certutil -decode -f "%B64%" "%PS1%" >nul 2>&1')
[void]$sb.AppendLine('del "%B64%" >nul 2>&1')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('if not exist "%PS1%" (')
[void]$sb.AppendLine('    echo [!] Payload extraction failed.')
[void]$sb.AppendLine('    pause')
[void]$sb.AppendLine('    exit /b 1')
[void]$sb.AppendLine(')')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('start "" /b powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%PS1%"')
[void]$sb.AppendLine('exit /b')

[System.IO.File]::WriteAllText($standalone, $sb.ToString(), (New-Object System.Text.ASCIIEncoding))
Write-Host ("Standalone: {0} ({1} KB, {2} b64 lines)" -f $standalone, [math]::Round((Get-Item $standalone).Length / 1KB), $lines.Count)
