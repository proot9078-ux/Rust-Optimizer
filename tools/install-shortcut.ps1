# ============================================================
#  PURPLE RUSH — ярлык с иконкой
#  .bat не умеет хранить свою иконку, поэтому создаём .lnk:
#  он запускает RustOptimizer.bat и берёт assets\rust-optimizer.ico.
#  Запуск: powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\install-shortcut.ps1
# ============================================================
param([switch]$DesktopOnly)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$bat  = Join-Path $root 'RustOptimizer.bat'
$ico  = Join-Path $root 'assets\rust-optimizer.ico'

if (-not (Test-Path -LiteralPath $bat)) { throw ('Не найден лаунчер: ' + $bat) }
if (-not (Test-Path -LiteralPath $ico)) { throw ('Не найдена иконка: ' + $ico) }

$shell = New-Object -ComObject WScript.Shell
$made  = New-Object System.Collections.Generic.List[string]

function New-AppShortcut {
    param([string]$Folder, [string]$Name)
    if (-not $Folder) { return }
    New-Item -ItemType Directory -Force -Path $Folder | Out-Null
    $path = Join-Path $Folder $Name
    $sc = $shell.CreateShortcut($path)
    $sc.TargetPath       = $bat
    $sc.WorkingDirectory = $root
    $sc.IconLocation     = $ico + ',0'
    $sc.Description      = 'PURPLE RUSH — RUST PERFORMANCE ENGINE'
    $sc.WindowStyle      = 1
    $sc.Save()
    $made.Add($path)
}

$desktop = [Environment]::GetFolderPath('Desktop')
New-AppShortcut $desktop 'PURPLE RUSH.lnk'

if (-not $DesktopOnly) {
    $programs = [Environment]::GetFolderPath('Programs')
    New-AppShortcut $programs 'PURPLE RUSH.lnk'
}

foreach ($p in $made) { Write-Host ('Ярлык создан: ' + $p) }
Write-Host 'Готово. Ярлык запускает .bat с самоэлевацией и фирменной иконкой.'
