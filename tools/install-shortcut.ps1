# ============================================================
#  PURPLE RUSH — ярлык с иконкой
#  .bat не умеет хранить свою иконку, поэтому создаём .lnk:
#  он запускает RustOptimizer.bat и берёт assets\rust-optimizer.ico.
#  Запуск: powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\install-shortcut.ps1
#  Приложение делает это автоматически при старте, скрипт нужен
#  для ручного восстановления ярлыка.
# ============================================================
param([switch]$DesktopOnly, [switch]$Quiet)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$bat  = Join-Path $root 'RustOptimizer.bat'
$ico  = Join-Path $root 'assets\rust-optimizer.ico'

function Write-Info {
    param([string]$Text)
    if (-not $Quiet) { Write-Host $Text }
}

if (-not (Test-Path -LiteralPath $bat)) { throw ('Не найден лаунчер: ' + $bat) }
if (-not (Test-Path -LiteralPath $ico)) { throw ('Не найдена иконка: ' + $ico) }

$shell = New-Object -ComObject WScript.Shell
$made  = New-Object System.Collections.Generic.List[string]

function New-AppShortcut {
    param([string]$Folder, [string]$Name)
    if (-not $Folder) { return }
    if (-not (Test-Path -LiteralPath $Folder)) { return }
    $path = Join-Path $Folder $Name
    $iconLoc = $ico + ',0'

    # Не перезаписываем ярлык, если он уже настроен правильно.
    if (Test-Path -LiteralPath $path) {
        try {
            $old = $shell.CreateShortcut($path)
            if ($old.TargetPath -eq $bat -and $old.IconLocation -eq $iconLoc) {
                $made.Add($path)
                return
            }
        } catch {}
    }

    $sc = $shell.CreateShortcut($path)
    $sc.TargetPath       = $bat
    $sc.WorkingDirectory = $root
    $sc.IconLocation     = $iconLoc
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

foreach ($p in $made) { Write-Info ('Ярлык готов: ' + $p) }
Write-Info 'Готово. Ярлык запускает .bat с самоэлевацией и фирменной иконкой.'
