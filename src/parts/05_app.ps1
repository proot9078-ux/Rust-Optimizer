# ============================================================
#  ЯРЛЫК НА РАБОЧЕМ СТОЛЕ, ИКОНКА И ЗАЩИТА ОТ ДВОЙНОГО ЗАПУСКА
#  Запуск .bat создаёт ярлык один раз и дальше не трогает его,
#  если он уже указывает на актуальный лаунчер.
# ============================================================

function Get-AppLauncherPath {
    $candidates = @()
    if ($env:RUSTOPT_LAUNCHER) { $candidates += [string]$env:RUSTOPT_LAUNCHER }
    try {
        if ($PSScriptRoot) {
            $candidates += (Join-Path (Split-Path -Parent $PSScriptRoot) 'RustOptimizer.bat')
            $candidates += (Join-Path $PSScriptRoot 'RustOptimizer.bat')
        }
    } catch {}
    foreach ($c in $candidates) {
        try {
            if ($c -and (Test-Path -LiteralPath $c)) {
                return (Resolve-Path -LiteralPath $c).Path
            }
        } catch {}
    }
    return $null
}

function Get-AppIconPath {
    try {
        if ($PSScriptRoot) {
            $p = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\rust-optimizer.ico'
            if (Test-Path -LiteralPath $p) { return (Resolve-Path -LiteralPath $p).Path }
            $p2 = Join-Path $PSScriptRoot 'assets\rust-optimizer.ico'
            if (Test-Path -LiteralPath $p2) { return (Resolve-Path -LiteralPath $p2).Path }
        }
    } catch {}
    return $null
}

# Создаёт (или обновляет) ярлык PURPLE RUSH на рабочем столе.
# Возвращает путь к .lnk либо $null, если создать нельзя.
function Install-AppShortcut {
    param([switch]$Force)
    try {
        $bat = Get-AppLauncherPath
        if (-not $bat) { return $null }
        $ico = Get-AppIconPath
        $desktop = [Environment]::GetFolderPath('Desktop')
        if (-not $desktop) { return $null }
        if (-not (Test-Path -LiteralPath $desktop)) { return $null }

        $lnk  = Join-Path $desktop 'PURPLE RUSH.lnk'
        $root = Split-Path -Parent $bat
        $iconLoc = if ($ico) { $ico + ',0' } else { $null }

        if ((Test-Path -LiteralPath $lnk) -and -not $Force) {
            try {
                $check = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
                $sameTarget = ($check.TargetPath -eq $bat)
                $sameIcon = (-not $iconLoc) -or ($check.IconLocation -eq $iconLoc)
                if ($sameTarget -and $sameIcon) { return $lnk }
            } catch {}
        }

        $shell = New-Object -ComObject WScript.Shell
        $sc = $shell.CreateShortcut($lnk)
        $sc.TargetPath       = $bat
        $sc.WorkingDirectory = $root
        if ($iconLoc) { $sc.IconLocation = $iconLoc }
        $sc.Description      = 'PURPLE RUSH — RUST PERFORMANCE ENGINE'
        $sc.WindowStyle      = 1
        $sc.Save()
        return $lnk
    } catch { return $null }
}

function Set-AppWindowIcon {
    param($Form)
    try {
        if (-not $Form -or $Form.IsDisposed) { return }
        $ico = Get-AppIconPath
        if ($ico) {
            $Form.Icon = New-Object System.Drawing.Icon($ico)
        }
    } catch {}
}

# ---------- Ручное создание ярлыка без запуска интерфейса ----------
if ($InstallShortcut) {
    $lnk = Install-AppShortcut -Force
    if ($lnk) {
        Write-Host ('OK: ' + $lnk)
        exit 0
    }
    Write-Host 'Не удалось создать ярлык: не найден RustOptimizer.bat или папка рабочего стола.'
    exit 1
}

# ---------- Один экземпляр приложения ----------
# Два одновременно запущенных окна могут мешать друг другу при записи
# cfg/состояния, поэтому второй запуск просто поднимает уже открытое окно.
$script:SingleInstance = $null
# Консольные режимы (-SelfTest, -TestUi, -Verify) не должны блокироваться
# открытым окном: иначе проверка молча завершается без отчёта.
if (-not $SelfTest -and -not $TestUi -and -not $Verify) {
    try {
        $mutexName = 'Local\PurpleRush.RustOptimizer.' + $env:USERNAME
        $mutex = New-Object System.Threading.Mutex($false, $mutexName)
        $owned = $false
        try { $owned = $mutex.WaitOne(0, $false) }
        catch [System.Threading.AbandonedMutexException] { $owned = $true }
        if (-not $owned) {
            $activated = $false
            try {
                Add-Type -Namespace PurpleRush -Name Win32 -ErrorAction SilentlyContinue -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetForegroundWindow(System.IntPtr hWnd);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
'@
                $proc = Get-Process -Name powershell -ErrorAction SilentlyContinue |
                        Where-Object { $_.MainWindowTitle -like 'PURPLE RUSH*' } |
                        Select-Object -First 1
                if ($proc -and $proc.MainWindowHandle -ne [IntPtr]::Zero) {
                    [void][PurpleRush.Win32]::ShowWindow($proc.MainWindowHandle, 9)
                    [void][PurpleRush.Win32]::SetForegroundWindow($proc.MainWindowHandle)
                    $activated = $true
                }
            } catch {}
            if (-not $activated) {
                try {
                    Add-Type -AssemblyName System.Windows.Forms
                    [void][System.Windows.Forms.MessageBox]::Show(
                        'PURPLE RUSH уже запущен. Переключитесь на открытое окно программы.',
                        'PURPLE RUSH', 'OK', 'Information')
                } catch {}
            }
            try { $mutex.Dispose() } catch {}
            exit
        }
        $script:SingleInstance = $mutex
    } catch {}
}
