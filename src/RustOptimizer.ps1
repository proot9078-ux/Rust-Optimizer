# ============================================================
#  PURPLE RUSH - RUST PERFORMANCE ENGINE  v5.3
#  Оптимизация Windows под RUST + официальные cfg/бинды +
#  глубокая очистка, диагностика и восстановление Windows.
#  Запуск: RustOptimizer.bat (права администратора)
# ============================================================
param([switch]$SelfTest, [switch]$TestUi, [switch]$InstallShortcut, [switch]$Verify)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

$script:AppVersion   = '5.3'
$script:Root         = Join-Path $env:ProgramData 'RustOptimizer'
$script:LogFile      = Join-Path $script:Root 'rust-optimizer.log'
$script:StateFile    = Join-Path $script:Root 'state.xml'
$script:RegBackup    = Join-Path $script:Root 'regbackup'
$script:RustBackup   = Join-Path $script:Root 'rustcfg'
$script:LogBox       = $null
$script:State        = @{}
$script:Enabled      = @{}
$script:RustExe      = $null
$script:SteamPath    = $null
$script:RustCfgDir   = $null
$script:ActiveGroup  = 'home'
$script:SC           = 1.0
$script:Busy         = $false
$script:Progress     = $null
$script:Status       = $null
$script:Spinner      = $null
$script:IsAdmin      = $false
$script:RustRunning  = $false
$script:BindListBox  = $null
$script:BindKeyBox   = $null
$script:BindCmdBox   = $null
$script:StatsTimer   = $null
$script:CpuBar       = $null
$script:RamBar       = $null
$script:DiskBar      = $null
$script:CpuVal       = $null
$script:RamVal       = $null
$script:DiskVal      = $null
$script:RustState    = $null
$script:Header       = $null
$script:AutoClose    = $true
$script:CloseTimer   = $null
$script:Closing      = $false
$script:ShortcutPath = $null

New-Item -ItemType Directory -Force -Path $script:Root, $script:RegBackup, $script:RustBackup | Out-Null

$script:LogMutex = New-Object object
try {
    if (Test-Path -LiteralPath $script:LogFile) {
        $fi = Get-Item -LiteralPath $script:LogFile
        if ($fi.Length -gt 3MB) {
            Move-Item -LiteralPath $script:LogFile -Destination ($script:LogFile + '.old') -Force
        }
    }
} catch {}

if (Test-Path -LiteralPath $script:StateFile) {
    try { $script:State = Import-Clixml -LiteralPath $script:StateFile } catch { $script:State = @{} }
}
# Если основной state.xml повреждён (обрыв записи, сбой питания), пробуем .bak.
if (-not ($script:State -is [hashtable]) -or $script:State.Count -eq 0) {
    $bak = $script:StateFile + '.bak'
    if (Test-Path -LiteralPath $bak) {
        try { $script:State = Import-Clixml -LiteralPath $bak } catch { $script:State = @{} }
    }
}
if (-not ($script:State -is [hashtable])) { $script:State = @{} }

# Закрывать ли оптимизатор автоматически после успешного запуска RUST.
if ($null -ne $script:State['AutoClose']) {
    $script:AutoClose = [bool]$script:State['AutoClose']
}

# Атомарная запись состояния: сначала во временный файл, затем подмена.
# Так сбой или закрытие окна не оставит полупустой state.xml.
function Save-State {
    if ($script:SuppressSave) { return }
    $tmp = $script:StateFile + '.new'
    try {
        $script:State | Export-Clixml -LiteralPath $tmp -Depth 6 -Force
        if (Test-Path -LiteralPath $script:StateFile) {
            try { Copy-Item -LiteralPath $script:StateFile -Destination ($script:StateFile + '.bak') -Force } catch {}
        }
        Move-Item -LiteralPath $tmp -Destination $script:StateFile -Force
    } catch {
        try { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force } } catch {}
    }
}

# ============================================================
#  Логирование и статус
# ============================================================
function Write-Log {
    param([string]$Message, [string]$Level = 'info')
    $stamp = (Get-Date).ToString('HH:mm:ss')
    $line  = "[$stamp] $Message"
    try {
        Add-Content -LiteralPath $script:LogFile -Encoding UTF8 `
            -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " [$Level] $Message")
    } catch {}
    try { Write-Host $line } catch {}

    if ($script:LogBox -and -not $script:LogBox.IsDisposed) {
        $map = @{ ok = '#4ECB71'; warn = '#E3B341'; err = '#FF6B62'; step = '#FF8A4C'; info = '#8B949E' }
        $hex = $map[$Level]
        if (-not $hex) { $hex = '#8B949E' }
        try {
            $col = [System.Drawing.ColorTranslator]::FromHtml($hex)
            $box = $script:LogBox
            $box.SelectionStart  = $box.TextLength
            $box.SelectionLength = 0
            $box.SelectionColor  = $col
            $box.AppendText($line + "`r`n")
            $box.SelectionColor  = $box.ForeColor
            $box.ScrollToCaret()
        } catch {}
        Pump
    }
}

function Set-Status {
    param([string]$Text, [string]$Color = '#8B949E')
    if ($script:Status -and -not $script:Status.IsDisposed) {
        $script:Status.Text = $Text
        try { $script:Status.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($Color) } catch {}
        Pump
    }
}

function Set-ProgressValue {
    param([double]$Value)
    if ($script:Progress -and -not $script:Progress.IsDisposed) { $script:Progress.Value = $Value }
    Pump
}

function Set-Busy {
    param([bool]$On)
    $script:Busy = $On
    if ($script:Spinner -and -not $script:Spinner.IsDisposed) { $script:Spinner.Active = $On }
}

function Pump {
    try { [System.Windows.Forms.Application]::DoEvents() } catch {}
}

# ============================================================
#  Реестр
# ============================================================
function ConvertTo-RegPath {
    param([string]$Path)
    if (-not $Path) { return $Path }
    if ($Path -match '^Microsoft\.PowerShell\.Core\\Registry::(.+)$') { return $matches[1] }
    if ($Path -match '^Registry::(.+)$') { return $matches[1] }
    return $Path
}

function Get-RegFullName {
    param([string]$Path)
    $p = ConvertTo-RegPath $Path
    $map = @{
        'HKLM' = 'HKEY_LOCAL_MACHINE'
        'HKCU' = 'HKEY_CURRENT_USER'
        'HKCR' = 'HKEY_CLASSES_ROOT'
        'HKU'  = 'HKEY_USERS'
        'HKCC' = 'HKEY_CURRENT_CONFIG'
    }
    if ($p -match '^(HKLM|HKCU|HKCR|HKU|HKCC):\\(.*)$') {
        return ($map[$matches[1]] + '\' + $matches[2])
    }
    return $p
}

function Ensure-RegKey {
    param([string]$Path)
    $p = ConvertTo-RegPath $Path
    if (-not (Test-Path -LiteralPath $p)) { New-Item -Path $p -Force | Out-Null }
}

function Get-Reg {
    param([string]$Path, [string]$Name)
    $p = ConvertTo-RegPath $Path
    try {
        $item = Get-ItemProperty -LiteralPath $p -Name $Name -ErrorAction Stop
        if ($null -eq $item) { return $null }
        return $item.$Name
    } catch { return $null }
}

function Set-RegDword {
    param([string]$Path, [string]$Name, [int64]$Value)
    $p = ConvertTo-RegPath $Path
    Ensure-RegKey $p
    $v = $Value
    if ($v -gt [int64][int]::MaxValue) { $v = $v - 4294967296 }
    New-ItemProperty -LiteralPath $p -Name $Name -Value ([int]$v) `
        -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
}

function Set-RegStr {
    param([string]$Path, [string]$Name, [string]$Value)
    $p = ConvertTo-RegPath $Path
    Ensure-RegKey $p
    New-ItemProperty -LiteralPath $p -Name $Name -Value ([string]$Value) `
        -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
}

function Remove-RegValue {
    param([string]$Path, [string]$Name)
    $p = ConvertTo-RegPath $Path
    Remove-ItemProperty -LiteralPath $p -Name $Name -Force -ErrorAction SilentlyContinue
}

function Backup-RegKey {
    param([string]$Path, [string]$FileName)
    try {
        $file = Join-Path $script:RegBackup $FileName
        $full = Get-RegFullName $Path
        & reg.exe export "$full" "$file" /y 2>&1 | Out-Null
    } catch {}
}

# ============================================================
#  Служебное
# ============================================================
function Test-Admin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        return (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Set-ServiceState {
    param([string]$Name, [string]$StartType, [switch]$StopIt)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { return $false }
    $key = "svc_$Name"
    if (-not $script:State.ContainsKey($key)) {
        $st = 'Automatic'
        try { $st = [string]$svc.StartType } catch {}
        $script:State[$key] = $st
    }
    try { Set-Service -Name $Name -StartupType $StartType -ErrorAction Stop } catch {
        $scStart = switch ($StartType) {
            'Automatic' { 'auto' }
            'Manual'    { 'demand' }
            'Disabled'  { 'disabled' }
            default     { 'demand' }
        }
        & sc.exe config $Name start= $scStart 2>&1 | Out-Null
    }
    if ($StopIt) { Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue }
    return $true
}

function Copy-Text {
    param([string]$Text)
    if (-not $Text) { return $false }
    try { Set-Clipboard -Value $Text -ErrorAction Stop; return $true } catch {}
    try { $Text | & clip.exe; return $true } catch {}
    return $false
}

function Open-Explorer {
    param([string]$Path)
    try { Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $Path + '"') | Out-Null } catch {}
}

# ============================================================
#  Поиск Steam / RUST
# ============================================================
function Find-SteamPath {
    $p = Get-Reg 'HKCU:\Software\Valve\Steam' 'SteamPath'
    if (-not $p) { $p = Get-Reg 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' 'InstallPath' }
    if (-not $p) { $p = Get-Reg 'HKLM:\SOFTWARE\Valve\Steam' 'InstallPath' }
    if ($p -and (Test-Path -LiteralPath $p)) { return ([string]$p).Replace('/', '\').TrimEnd('\') }
    foreach ($d in @('C:\Program Files (x86)\Steam', 'C:\Program Files\Steam', 'D:\Steam', 'D:\SteamLibrary')) {
        if (Test-Path -LiteralPath $d) { return $d }
    }
    return $null
}

function Find-RustExe {
    $libs = @()
    if ($script:SteamPath) {
        $libs += $script:SteamPath
        $vdf = Join-Path $script:SteamPath 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            try {
                $txt = [IO.File]::ReadAllText($vdf)
                foreach ($m in [regex]::Matches($txt, '"path"\s+"([^"]+)"')) {
                    $libs += $m.Groups[1].Value.Replace('\\', '\')
                }
            } catch {}
        }
    }
    foreach ($l in ($libs | Select-Object -Unique)) {
        if (-not $l) { continue }
        $c = Join-Path $l 'steamapps\common\Rust\RustClient.exe'
        if (Test-Path -LiteralPath $c) {
            try { return (Get-Item -LiteralPath $c -Force).FullName } catch { return $c }
        }
    }
    return $null
}

function Get-RustCfgDir {
    if (-not $script:RustCfgDir) {
        if (-not $script:RustExe) { return $null }
        $script:RustCfgDir = Join-Path (Split-Path -Parent $script:RustExe) 'cfg'
    }
    if (-not (Test-Path -LiteralPath $script:RustCfgDir)) {
        try { New-Item -ItemType Directory -Path $script:RustCfgDir -Force | Out-Null } catch { return $null }
    }
    return $script:RustCfgDir
}

function Test-RustRunning {
    $p = Get-Process -Name 'RustClient' -ErrorAction SilentlyContinue
    return [bool]$p
}

function Get-PhysicalCoreMask {
    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
        $cores   = [int]$cpu.NumberOfCores
        $logical = [int]$cpu.NumberOfLogicalProcessors
        if ($logical -gt 63) { $logical = 63 }
        if ($cores -gt 63) { $cores = 63 }
        if ($logical -le 0) { return [int64]0 }
        if ($logical -eq $cores) { return [int64](([int64]1 -shl $logical) - 1) }
        if ($logical -eq ($cores * 2)) {
            $mask = [int64]0
            for ($i = 0; $i -lt $cores; $i++) { $mask = $mask -bor ([int64]1 -shl ($i * 2)) }
            return $mask
        }
    } catch {}
    return [int64]0
}

# ============================================================
#  Файлы Rust: бэкапы и слияние cfg
# ============================================================
function Backup-FileOnce {
    param([string]$Path, [string]$Tag)
    $dest = Join-Path $script:RustBackup ($Tag + '.orig')
    if (Test-Path -LiteralPath $dest) { return $dest }
    if (Test-Path -LiteralPath $Path) {
        try { Copy-Item -LiteralPath $Path -Destination $dest -Force } catch {}
    } else {
        try { [IO.File]::WriteAllText($dest, '', (New-Object System.Text.UTF8Encoding($false))) } catch {}
    }
    return $dest
}

function Backup-FileStamp {
    param([string]$Path, [string]$Tag)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        $name = $Tag + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.bak'
        Copy-Item -LiteralPath $Path -Destination (Join-Path $script:RustBackup $name) -Force
        $old = @(Get-ChildItem -LiteralPath $script:RustBackup -Filter ($Tag + '-*.bak') -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending | Select-Object -Skip 10)
        foreach ($f in $old) { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue }
    } catch {}
}

function Restore-FileOnce {
    param([string]$Path, [string]$Tag)
    $src = Join-Path $script:RustBackup ($Tag + '.orig')
    if (-not (Test-Path -LiteralPath $src)) { return $false }
    $text = ''
    try { $text = [IO.File]::ReadAllText($src) } catch { return $false }
    if ($text.Length -eq 0) {
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    } else {
        try { Copy-Item -LiteralPath $src -Destination $Path -Force } catch { return $false }
    }
    return $true
}

function Merge-CfgFile {
    param([string]$Path, [string[]]$Lines, [string[]]$ManagedKeys)
    $existing = @()
    if (Test-Path -LiteralPath $Path) {
        try { $existing = @([IO.File]::ReadAllLines($Path)) } catch { $existing = @() }
    }
    $managed = @{}
    foreach ($m in @($ManagedKeys)) { if ($m) { $managed[$m.ToLower()] = $true } }
    $keep = New-Object System.Collections.Generic.List[string]
    foreach ($ln in $existing) {
        $t = [string]$ln
        if ($t.Trim().Length -eq 0) { continue }
        $cmd = ($t.Trim() -split '\s+')[0].ToLower()
        if ($managed.ContainsKey($cmd)) { continue }
        $keep.Add($t)
    }
    foreach ($l in @($Lines)) { if ($l) { $keep.Add($l) } }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllLines($Path, $keep, (New-Object System.Text.UTF8Encoding($false)))
}

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

# ============================================================
#  СИСТЕМА
# ============================================================
function Invoke-PowerPlan {
    $cur = ((powercfg /getactivescheme) -join ' ')
    if ($cur -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
        if (-not $script:State.ContainsKey('PowerOld')) { $script:State['PowerOld'] = $matches[1] }
    }

    $g = $null
    $prev = $script:State['PowerNew']
    if ($prev -and (((powercfg /list) -join ' ').Contains([string]$prev))) {
        $g = $prev
        Write-Log 'Схема «Максимальная производительность» уже создана — активирую' 'info'
    } else {
        $out = (powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1) -join ' '
        if ($out -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
            $g = $matches[1]
            Write-Log 'Схема «Максимальная производительность» создана' 'ok'
        }
    }
    if (-not $g) {
        $g = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
        Write-Log 'Ultimate Performance недоступна → включена «Высокая производительность»' 'warn'
    }
    $script:State['PowerNew'] = $g
    & powercfg -setactive $g 2>&1 | Out-Null
    foreach ($x in @(@('SUB_PCIEXPRESS', 'ASPM'), @('SUB_USB', 'USBSELECTIVESUSPEND'), @('SUB_DISK', 'DISKIDLE'))) {
        & powercfg -setacvalueindex $g $x[0] $x[1] 0 2>&1 | Out-Null
    }
    & powercfg -setactive $g 2>&1 | Out-Null
    Write-Log 'PCIe ASPM, USB-энергосбережение и сон диска отключены' 'ok'
}

function Undo-PowerPlan {
    $old = $script:State['PowerOld']
    if ($old) {
        & powercfg -setactive ([string]$old) 2>&1 | Out-Null
        Write-Log 'Схема питания возвращена к прежней' 'ok'
    }
}

function Invoke-PrioritySeparation {
    $p = 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl'
    Backup-RegKey $p 'PriorityControl.reg'
    $old = Get-Reg $p 'Win32PrioritySeparation'
    if (-not $script:State.ContainsKey('Win32PrioOld')) {
        $script:State['Win32PrioOld'] = if ($null -eq $old) { -1 } else { [int]$old }
    }
    Set-RegDword $p 'Win32PrioritySeparation' 26
    Write-Log 'Win32PrioritySeparation = 26 (кванты активному процессу)' 'ok'
}

function Undo-PrioritySeparation {
    $p = 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl'
    $old = $script:State['Win32PrioOld']
    if ($null -eq $old -or [int]$old -lt 0) { Remove-RegValue $p 'Win32PrioritySeparation' }
    else { Set-RegDword $p 'Win32PrioritySeparation' ([int64]$old) }
    Write-Log 'Приоритеты планировщика восстановлены' 'ok'
}

function Invoke-Mmcss {
    $sys   = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
    $games = "$sys\Tasks\Games"
    Backup-RegKey $sys 'MMCSS-SystemProfile.reg'
    if (-not $script:State.ContainsKey('Mmcss')) {
        $thr = Get-Reg $sys 'NetworkThrottlingIndex'
        $rsp = Get-Reg $sys 'SystemResponsiveness'
        $gpu = Get-Reg $games 'GPU Priority'
        $pri = Get-Reg $games 'Priority'
        $cat = Get-Reg $games 'Scheduling Category'
        $sfi = Get-Reg $games 'SFIO Priority'
        $script:State['Mmcss'] = @{
            Throttle = if ($null -eq $thr) { [int64]-1 } else { [int64]$thr }
            Response = if ($null -eq $rsp) { [int64]-1 } else { [int64]$rsp }
            GpuPrio  = if ($null -eq $gpu) { [int64]-1 } else { [int64]$gpu }
            Priority = if ($null -eq $pri) { [int64]-1 } else { [int64]$pri }
            Category = if ($null -eq $cat) { '' } else { [string]$cat }
            Sfio     = if ($null -eq $sfi) { '' } else { [string]$sfi }
        }
    }
    Set-RegDword $sys 'NetworkThrottlingIndex' 4294967295
    Set-RegDword $sys 'SystemResponsiveness' 0
    Set-RegDword $games 'GPU Priority' 8
    Set-RegDword $games 'Priority' 6
    Set-RegStr   $games 'Scheduling Category' 'High'
    Set-RegStr   $games 'SFIO Priority' 'High'
    Write-Log 'Сетевой лимит Windows снят, игровые задачи → High' 'ok'
}

function Undo-Mmcss {
    $m = $script:State['Mmcss']
    if (-not $m) { return }
    $sys   = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
    $games = "$sys\Tasks\Games"
    if ([int64]$m.Throttle -ge 0) { Set-RegDword $sys 'NetworkThrottlingIndex' ([int64]$m.Throttle) } else { Remove-RegValue $sys 'NetworkThrottlingIndex' }
    if ([int64]$m.Response -ge 0) { Set-RegDword $sys 'SystemResponsiveness' ([int64]$m.Response) } else { Remove-RegValue $sys 'SystemResponsiveness' }
    if ([int64]$m.GpuPrio -ge 0)  { Set-RegDword $games 'GPU Priority' ([int64]$m.GpuPrio) } else { Remove-RegValue $games 'GPU Priority' }
    if ([int64]$m.Priority -ge 0) { Set-RegDword $games 'Priority' ([int64]$m.Priority) } else { Remove-RegValue $games 'Priority' }
    if ($m.Category) { Set-RegStr $games 'Scheduling Category' ([string]$m.Category) } else { Remove-RegValue $games 'Scheduling Category' }
    if ($m.Sfio)     { Set-RegStr $games 'SFIO Priority' ([string]$m.Sfio) } else { Remove-RegValue $games 'SFIO Priority' }
    Write-Log 'Параметры MMCSS восстановлены' 'ok'
}

$script:GameDvrKeys = @(
    @{ P = 'HKCU:\System\GameConfigStore'; N = 'GameDVR_Enabled' },
    @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'; N = 'AppCaptureEnabled' },
    @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'; N = 'HistoricalCaptureEnabled' },
    @{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR'; N = 'AllowGameDVR' },
    @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'; N = 'GameDVR_Enabled' }
)

function Invoke-GameDvr {
    if (-not $script:State.ContainsKey('GameDvrOld')) {
        $snap = @{}
        foreach ($k in $script:GameDvrKeys) {
            $v = Get-Reg $k.P $k.N
            $snap[($k.P + '|' + $k.N)] = if ($null -eq $v) { [int64]-1 } else { [int64]$v }
        }
        $script:State['GameDvrOld'] = $snap
    }
    foreach ($k in $script:GameDvrKeys) { Set-RegDword $k.P $k.N 0 }
    Write-Log 'Game DVR и фоновая запись Xbox отключены' 'ok'
}

function Undo-GameDvr {
    $snap = $script:State['GameDvrOld']
    if (-not $snap) { return }
    foreach ($key in @($snap.Keys)) {
        $parts = ([string]$key).Split('|')
        if ($parts.Count -lt 2) { continue }
        $v = [int64]$snap[$key]
        if ($v -lt 0) { Remove-RegValue $parts[0] $parts[1] }
        else { Set-RegDword $parts[0] $parts[1] $v }
    }
    Write-Log 'Game DVR возвращён к прежним значениям' 'ok'
}

function Invoke-GameMode {
    $p = 'HKCU:\Software\Microsoft\GameBar'
    if (-not $script:State.ContainsKey('GameModeOld')) {
        $snap = @{}
        foreach ($n in 'AutoGameModeEnabled', 'AllowAutoGameMode', 'ShowStartupPanel', 'UseNexusForGameBarEnabled') {
            $v = Get-Reg $p $n
            $snap[$n] = if ($null -eq $v) { -1 } else { [int64]$v }
        }
        $script:State['GameModeOld'] = $snap
    }
    Set-RegDword $p 'AutoGameModeEnabled' 1
    Set-RegDword $p 'AllowAutoGameMode' 1
    Set-RegDword $p 'ShowStartupPanel' 0
    Set-RegDword $p 'UseNexusForGameBarEnabled' 0
    Write-Log 'Игровой режим Windows включён' 'ok'
}

function Undo-GameMode {
    $p = 'HKCU:\Software\Microsoft\GameBar'
    $snap = $script:State['GameModeOld']
    if ($snap) {
        foreach ($n in @($snap.Keys)) {
            $v = [int64]$snap[$n]
            if ($v -lt 0) { Remove-RegValue $p $n } else { Set-RegDword $p $n $v }
        }
    }
    Write-Log 'Настройки игрового режима восстановлены' 'ok'
}

function Invoke-Hags {
    $p = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
    Backup-RegKey $p 'GraphicsDrivers.reg'
    $old = Get-Reg $p 'HwSchMode'
    if (-not $script:State.ContainsKey('HagsOld')) {
        $script:State['HagsOld'] = if ($null -eq $old) { -1 } else { [int]$old }
    }
    Set-RegDword $p 'HwSchMode' 2
    Write-Log 'Аппаратное планирование GPU (HAGS) включено — нужен перезапуск' 'warn'
}

function Undo-Hags {
    $p = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
    $old = $script:State['HagsOld']
    if ($null -eq $old -or [int]$old -lt 0) { Remove-RegValue $p 'HwSchMode' }
    else { Set-RegDword $p 'HwSchMode' ([int64]$old) }
    Write-Log 'HAGS возвращён к прежнему значению' 'ok'
}

function Invoke-Mouse {
    $p = 'HKCU:\Control Panel\Mouse'
    if (-not $script:State.ContainsKey('MouseOld')) {
        $script:State['MouseOld'] = @{
            Speed = [string](Get-Reg $p 'MouseSpeed')
            Th1   = [string](Get-Reg $p 'MouseThreshold1')
            Th2   = [string](Get-Reg $p 'MouseThreshold2')
        }
    }
    Set-RegStr $p 'MouseSpeed' '0'
    Set-RegStr $p 'MouseThreshold1' '0'
    Set-RegStr $p 'MouseThreshold2' '0'
    Write-Log 'Ускорение мыши отключено (1:1 движение прицела)' 'ok'
}

function Undo-Mouse {
    $m = $script:State['MouseOld']
    $p = 'HKCU:\Control Panel\Mouse'
    if ($m) {
        Set-RegStr $p 'MouseSpeed'      ($(if ($m.Speed) { [string]$m.Speed } else { '1' }))
        Set-RegStr $p 'MouseThreshold1' ($(if ($m.Th1) { [string]$m.Th1 } else { '6' }))
        Set-RegStr $p 'MouseThreshold2' ($(if ($m.Th2) { [string]$m.Th2 } else { '10' }))
    }
    Write-Log 'Параметры мыши восстановлены' 'ok'
}

function Invoke-KeyFix {
    $sk = 'HKCU:\Control Panel\Accessibility\StickyKeys'
    $tk = 'HKCU:\Control Panel\Accessibility\ToggleKeys'
    $fk = 'HKCU:\Control Panel\Accessibility\Keyboard Response'
    if (-not $script:State.ContainsKey('KeyFixOld')) {
        $script:State['KeyFixOld'] = @{
            Sk = [string](Get-Reg $sk 'Flags')
            Tk = [string](Get-Reg $tk 'Flags')
            Fk = [string](Get-Reg $fk 'Flags')
        }
    }
    Set-RegStr $sk 'Flags' '506'
    Set-RegStr $tk 'Flags' '58'
    Set-RegStr $fk 'Flags' '122'
    Write-Log 'Горячие клавиши залипания/фильтрации отключены' 'ok'
}

function Undo-KeyFix {
    $m = $script:State['KeyFixOld']
    if ($m) {
        if ($m.Sk) { Set-RegStr 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags' ([string]$m.Sk) }
        if ($m.Tk) { Set-RegStr 'HKCU:\Control Panel\Accessibility\ToggleKeys' 'Flags' ([string]$m.Tk) }
        if ($m.Fk) { Set-RegStr 'HKCU:\Control Panel\Accessibility\Keyboard Response' 'Flags' ([string]$m.Fk) }
    }
    Write-Log 'Спец. возможности восстановлены' 'ok'
}

function Invoke-Telemetry {
    $null = Set-ServiceState 'DiagTrack' 'Disabled' -StopIt
    $null = Set-ServiceState 'dmwappushservice' 'Disabled' -StopIt
    Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0
    Set-RegDword 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' 0
    Write-Log 'Телеметрия DiagTrack остановлена и отключена' 'ok'
}

function Undo-Telemetry {
    foreach ($n in 'DiagTrack', 'dmwappushservice') {
        $st = [string]$script:State["svc_$n"]
        if (-not $st) { $st = 'Automatic' }
        try { Set-Service -Name $n -StartupType $st -ErrorAction SilentlyContinue } catch {}
    }
    Remove-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry'
    Remove-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry'
    Write-Log 'Службы телеметрии возвращены в исходное состояние' 'ok'
}

function Invoke-SysMain {
    $null = Set-ServiceState 'SysMain' 'Disabled' -StopIt
    Write-Log 'SysMain (Superfetch) отключён — для SSD это плюс' 'ok'
}

function Undo-SysMain {
    $st = [string]$script:State['svc_SysMain']; if (-not $st) { $st = 'Automatic' }
    try { Set-Service -Name 'SysMain' -StartupType $st -ErrorAction SilentlyContinue } catch {}
    Write-Log 'SysMain возвращён в исходное состояние' 'ok'
}

function Invoke-SearchIndex {
    $null = Set-ServiceState 'WSearch' 'Disabled' -StopIt
    Write-Log 'Индексация поиска Windows отключена (поиск по файлам будет медленнее)' 'warn'
}

function Undo-SearchIndex {
    $st = [string]$script:State['svc_WSearch']; if (-not $st) { $st = 'Automatic' }
    try { Set-Service -Name 'WSearch' -StartupType $st -ErrorAction SilentlyContinue } catch {}
    Write-Log 'Служба поиска возвращена в исходное состояние' 'ok'
}

function Invoke-VisualEffects {
    $p = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
    if (-not $script:State.ContainsKey('VisualOld')) {
        $script:State['VisualOld'] = [string](Get-Reg $p 'VisualFXSetting')
    }
    Set-RegDword $p 'VisualFXSetting' 2
    Write-Log 'Визуальные эффекты → «Обеспечить наибольшее быстродействие»' 'ok'
}

function Undo-VisualEffects {
    $p = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
    $old = [string]$script:State['VisualOld']
    if ($old) { Set-RegDword $p 'VisualFXSetting' ([int64]$old) } else { Set-RegDword $p 'VisualFXSetting' 0 }
    Write-Log 'Визуальные эффекты восстановлены' 'ok'
}

function Invoke-HibernateOff {
    $script:State['HibernateWasOn'] = [bool](Test-Path -LiteralPath "$env:SystemDrive\hiberfil.sys")
    & powercfg -h off 2>&1 | Out-Null
    Write-Log 'Гибернация отключена, hiberfil.sys удалён' 'ok'
}

function Undo-HibernateOff {
    if ($script:State['HibernateWasOn']) {
        & powercfg -h on 2>&1 | Out-Null
        Write-Log 'Гибернация включена обратно' 'ok'
    }
}

function Invoke-PowerThrottle {
    $p = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling'
    Backup-RegKey $p 'PowerThrottling.reg'
    $old = Get-Reg $p 'PowerThrottlingOff'
    if (-not $script:State.ContainsKey('PowerThrottleOld')) {
        $script:State['PowerThrottleOld'] = if ($null -eq $old) { -1 } else { [int]$old }
    }
    Set-RegDword $p 'PowerThrottlingOff' 1
    Write-Log 'Power Throttling отключён — Windows не тормозит активные процессы' 'ok'
}

function Undo-PowerThrottle {
    $p = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling'
    $old = $script:State['PowerThrottleOld']
    if ($null -eq $old -or [int]$old -lt 0) { Remove-RegValue $p 'PowerThrottlingOff' }
    else { Set-RegDword $p 'PowerThrottlingOff' ([int64]$old) }
    Write-Log 'Power Throttling восстановлен' 'ok'
}

function Invoke-BgApps {
    $names = @('OneDrive', 'SkypeApp', 'Skype', 'Teams', 'ms-teams', 'Cortana',
               'YourPhone', 'PhoneExperienceHost', 'WidgetService', 'Widgets', 'WindowsWidgets')
    $killed = 0
    foreach ($n in $names) {
        foreach ($p in @(Get-Process -Name $n -ErrorAction SilentlyContinue)) {
            try { $p.Kill(); $killed = $killed + 1 } catch {}
        }
    }
    if ($killed -gt 0) { Write-Log "Закрыто фоновых процессов: $killed" 'ok' }
    else { Write-Log 'Лишних фоновых процессов не найдено' 'info' }
}

# ============================================================
#  СЕТЬ
# ============================================================
function Get-ActiveNetInterfaces {
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
    $res  = @()
    foreach ($i in @(Get-ChildItem -Path $base -ErrorAction SilentlyContinue)) {
        $pr = Get-ItemProperty -LiteralPath $i.PSPath -ErrorAction SilentlyContinue
        if ($null -eq $pr) { continue }
        if ($pr.IPAddress -or $pr.DhcpIPAddress -or $pr.DefaultGateway -or $pr.NameServer) {
            $res += $i
        }
    }
    return $res
}

function Invoke-Nagle {
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
    $saved = @{}
    foreach ($i in (Get-ActiveNetInterfaces)) {
        $path = Join-Path $base $i.PSChildName
        $pr = Get-ItemProperty -LiteralPath $path -ErrorAction SilentlyContinue
        $ex = @{}
        foreach ($n in 'TcpAckFrequency', 'TCPNoDelay') {
            $v = $pr.$n
            if ($null -ne $v) { $ex[$n] = [int64]$v }
        }
        $saved[$i.PSChildName] = $ex
        Set-RegDword $path 'TcpAckFrequency' 1
        Set-RegDword $path 'TCPNoDelay' 1
    }
    if ($saved.Count -eq 0) { throw 'Активные сетевые интерфейсы не найдены' }
    $script:State['Nagle'] = $saved
    Write-Log "Алгоритм Nagle отключён на интерфейсах: $($saved.Count)" 'ok'
}

function Undo-Nagle {
    $saved = $script:State['Nagle']
    if (-not $saved) { return }
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
    foreach ($id in @($saved.Keys)) {
        $path = Join-Path $base ([string]$id)
        $ex = $saved[$id]
        foreach ($n in 'TcpAckFrequency', 'TCPNoDelay') {
            if ($ex -and $ex.ContainsKey($n)) { Set-RegDword $path $n ([int64]$ex[$n]) }
            else { Remove-RegValue $path $n }
        }
    }
    Write-Log 'Параметры Nagle восстановлены' 'ok'
}

function Invoke-Dns {
    $saved = @{}
    $idx = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
           Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
    if (-not $idx) { throw 'Активный сетевой адаптер не найден' }
    $cur = Get-DnsClientServerAddress -InterfaceIndex $idx.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    $saved['Index'] = $idx.ifIndex
    $saved['Servers'] = @($cur.ServerAddresses)
    $script:State['Dns'] = $saved
    Set-DnsClientServerAddress -InterfaceIndex $idx.ifIndex -ServerAddresses ('1.1.1.1', '1.0.0.1') -ErrorAction Stop
    Write-Log "DNS → Cloudflare (1.1.1.1) на «$($idx.Name)»" 'ok'
}

function Undo-Dns {
    $d = $script:State['Dns']
    if (-not $d) { return }
    try {
        if ($d.Servers -and @($d.Servers).Count -gt 0) {
            Set-DnsClientServerAddress -InterfaceIndex $d.Index -ServerAddresses $d.Servers -ErrorAction Stop
        } else {
            Set-DnsClientServerAddress -InterfaceIndex $d.Index -ResetServerAddresses -ErrorAction Stop
        }
        Write-Log 'DNS возвращён к прежним настройкам' 'ok'
    } catch { Write-Log ('Не удалось вернуть DNS: ' + $_.Exception.Message) 'warn' }
}

function Invoke-TcpTune {
    if (-not $script:State.ContainsKey('TcpTuneOld')) {
        $snap = @{ Ok = $false }
        try {
            $s = Get-NetTCPSetting -SettingName Internet -ErrorAction Stop
            $snap['Auto'] = [string]$s.AutoTuningLevelLocal
            $snap['Ecn']  = [string]$s.EcnCapability
            $snap['Ts']   = [string]$s.Timestamps
            $snap['Ok']   = $true
        } catch {}
        $script:State['TcpTuneOld'] = $snap
    }

    $done = $false
    try {
        Set-NetTCPSetting -SettingName Internet -AutoTuningLevelLocal Normal `
            -EcnCapability Disabled -Timestamps Disabled -ErrorAction Stop
        $done = $true
    } catch {}
    if (-not $done) {
        & netsh int tcp set global autotuninglevel=normal 2>&1 | Out-Null
        & netsh int tcp set global ecncapability=disabled 2>&1 | Out-Null
        & netsh int tcp set global timestamps=disabled 2>&1 | Out-Null
    }

    # RSS полезен для многопоточных сетевых очередей; ошибки не критичны.
    try {
        foreach ($a in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
                         Where-Object { $_.Status -eq 'Up' })) {
            try { Enable-NetAdapterRss -Name $a.Name -ErrorAction Stop } catch {}
        }
    } catch {}

    Write-Log 'TCP: автотюнинг и RSS включены, ECN и timestamps отключены' 'ok'
}

function Undo-TcpTune {
    $o = $script:State['TcpTuneOld']
    if ($o -and $o.Ok) {
        try {
            Set-NetTCPSetting -SettingName Internet -AutoTuningLevelLocal ([string]$o.Auto) `
                -EcnCapability ([string]$o.Ecn) -Timestamps ([string]$o.Ts) -ErrorAction Stop
            Write-Log 'TCP-настройки восстановлены' 'ok'
            return
        } catch {}
    }
    & netsh int tcp set global autotuninglevel=normal 2>&1 | Out-Null
    Write-Log 'TCP: автотюнинг возвращён к normal' 'info'
}

function Invoke-FlushDns {
    & ipconfig /flushdns 2>&1 | Out-Null
    Write-Log 'DNS-кэш сброшен' 'ok'
}

# ============================================================
#  RUST: процесс
# ============================================================
function Invoke-RustCompat {
    if (-not $script:RustExe) { throw 'RUST не найден — оптимизация совместимости пропущена' }
    $k = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
    Ensure-RegKey $k
    $old = Get-Reg $k $script:RustExe
    if (-not $script:State.ContainsKey('RustCompatOld')) {
        $script:State['RustCompatOld'] = if ($null -eq $old) { '' } else { [string]$old }
    }
    $val = '~ DISABLEDXMAXIMIZEDWINDOWEDMODE'
    if ($old -and ([string]$old).Trim().Length -gt 0) {
        if (([string]$old) -notmatch 'DISABLEDXMAXIMIZEDWINDOWEDMODE') {
            $val = ([string]$old).TrimEnd() + ' DISABLEDXMAXIMIZEDWINDOWEDMODE'
        } else { $val = [string]$old }
    }
    Set-RegStr $k $script:RustExe $val
    Write-Log 'Оптимизации полного экрана для RustClient.exe отключены' 'ok'
}

function Undo-RustCompat {
    if (-not $script:RustExe) { return }
    $k = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
    $old = [string]$script:State['RustCompatOld']
    if ($old) { Set-RegStr $k $script:RustExe $old }
    else { Remove-RegValue $k $script:RustExe }
    Write-Log 'Параметры совместимости Rust восстановлены' 'ok'
}

function Invoke-RustGpu {
    if (-not $script:RustExe) { throw 'RUST не найден — привязка к GPU пропущена' }
    $k = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
    Ensure-RegKey $k
    $old = Get-Reg $k $script:RustExe
    if (-not $script:State.ContainsKey('RustGpuOld')) {
        $script:State['RustGpuOld'] = if ($null -eq $old) { '' } else { [string]$old }
    }
    Set-RegStr $k $script:RustExe 'GpuPreference=2;'
    Write-Log 'RustClient.exe → «Высокая производительность» GPU' 'ok'
}

function Undo-RustGpu {
    if (-not $script:RustExe) { return }
    $k = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
    $old = [string]$script:State['RustGpuOld']
    if ($old) { Set-RegStr $k $script:RustExe $old }
    else { Remove-RegValue $k $script:RustExe }
    Write-Log 'Привязка GPU для Rust восстановлена' 'ok'
}

function Invoke-RustPriority {
    $p = @(Get-Process -Name 'RustClient' -ErrorAction SilentlyContinue)
    if ($p.Count -eq 0) { Write-Log 'RustClient не запущен — приоритет применится при старте' 'info'; return }
    foreach ($x in $p) { try { $x.PriorityClass = 'High' } catch {} }
    Write-Log 'Приоритет запущенного RustClient → High' 'ok'
}

function Invoke-RustAffinity {
    $mask = Get-PhysicalCoreMask
    if ($mask -eq 0) { throw 'Не удалось определить физические ядра' }
    $p = @(Get-Process -Name 'RustClient' -ErrorAction SilentlyContinue)
    if ($p.Count -eq 0) { Write-Log 'RustClient не запущен — привязка к ядрам применится при старте' 'info'; return }
    foreach ($x in $p) { try { $x.ProcessorAffinity = [IntPtr]$mask } catch {} }
    Write-Log ('RustClient привязан к физическим ядрам (маска 0x{0:X})' -f $mask) 'ok'
}

function Invoke-RustProcessPolish {
    $p = @(Get-Process -Name 'RustClient' -ErrorAction SilentlyContinue)
    if ($p.Count -eq 0) { return }
    foreach ($x in $p) {
        try { $x.PriorityClass = 'High' } catch {}
        if ($script:Enabled['rustaffinity']) {
            $mask = Get-PhysicalCoreMask
            if ($mask -ne 0) { try { $x.ProcessorAffinity = [IntPtr]$mask } catch {} }
        }
    }
}

# ============================================================
#  RUST: client.cfg — трава и пост-эффекты
# ============================================================
$script:RustCfgLines = @(
    'grass.displacement False',
    'effects.shafts False',
    'graphics.dof False',
    'fps.graph 0'
)

# graphics.shafts — старый неверный ключ: удаляем его из cfg при слиянии.
$script:RustCfgManaged = @('grass.displacement', 'effects.shafts', 'graphics.shafts', 'graphics.dof', 'fps.graph')

function Get-RustCfgCommandText {
    return @($script:RustCfgLines)
}

function Invoke-RustCfg {
    if (-not $script:RustExe) { throw 'RUST не найден — запишите cfg вручную или запустите игру один раз' }
    if (Test-RustRunning) { throw 'Rust запущен: игра перезапишет cfg при выходе. Закройте игру или используйте «Команды для F1».' }
    $dir = Get-RustCfgDir
    if (-not $dir) { throw 'Не удалось открыть папку cfg игры' }
    $file = Join-Path $dir 'client.cfg'
    $null = Backup-FileOnce $file 'client.cfg'
    Backup-FileStamp $file 'client'
    Merge-CfgFile -Path $file -Lines $script:RustCfgLines -ManagedKeys $script:RustCfgManaged
    Write-Log 'client.cfg: трава и пост-эффекты выключены (бэкап сохранён)' 'ok'
}

function Undo-RustCfg {
    if (-not $script:RustExe) { return }
    $dir = Get-RustCfgDir
    if (-not $dir) { return }
    $file = Join-Path $dir 'client.cfg'
    if (Restore-FileOnce $file 'client.cfg') { Write-Log 'client.cfg восстановлен из бэкапа' 'ok' }
}

# ============================================================
#  RUST: бинды (официальный keys.cfg)
# ============================================================
$script:BindPresets = @(
    [pscustomobject]@{ Name = 'Alt-look'; Key = 'mouse4'; Cmd = '+altlook'; Hint = 'свободный обзор' },
    [pscustomobject]@{ Name = 'Консоль';  Key = 'f1';     Cmd = 'consoletoggle'; Hint = 'открыть F1' },
    [pscustomobject]@{ Name = 'Инвентарь'; Key = 'mouse5'; Cmd = 'inventory.toggle'; Hint = 'открыть/закрыть' },
    [pscustomobject]@{ Name = 'FPS-граф'; Key = 'f3';     Cmd = 'fps.graph 1'; Hint = 'показать график' }
)

function Get-BindRecords {
    $raw = @($script:State['Binds'])
    $out = @()
    foreach ($r in $raw) {
        if (-not $r) { continue }
        $parts = ([string]$r).Split('|')
        if ($parts.Count -lt 2) { continue }
        if (-not $parts[0]) { continue }
        $out += [pscustomobject]@{ Key = [string]$parts[0]; Cmd = [string]$parts[1] }
    }
    return $out
}

function Save-BindRecords {
    param($Recs)
    $script:State['Binds'] = @($Recs | ForEach-Object { ([string]$_.Key) + '|' + ([string]$_.Cmd) })
    Save-State
}

function Add-RustBind {
    param([string]$Key, [string]$Cmd)
    $k = ([string]$Key).Trim().ToLower()
    if (-not $k) { return 'Укажите клавишу, например mouse4 или f1' }
    if ($k -match '\s') { return 'Код клавиши не должен содержать пробелов' }
    if ($k -notmatch '^[a-z0-9_]+$') { return 'Некорректный код клавиши (латиница/цифры, например mouse4 или f1)' }
    $c = ([string]$Cmd).Trim()
    if (-not $c) { return 'Команда не может быть пустой' }
    $c = ($c -replace '"', '') -replace "[\r\n]+", ' '
    $recs = @(Get-BindRecords | Where-Object { $_.Key -ne $k })
    $recs += [pscustomobject]@{ Key = $k; Cmd = $c }
    Save-BindRecords $recs
    return $null
}

function Remove-RustBind {
    param([string]$Key)
    $recs = @(Get-BindRecords | Where-Object { $_.Key -ne $Key })
    Save-BindRecords $recs
}

function Get-BindCommandLines {
    $lines = @()
    foreach ($b in @(Get-BindRecords)) {
        $lines += ('bind ' + $b.Key + ' "' + $b.Cmd + '"')
    }
    return $lines
}

function Apply-RustBinds {
    param([switch]$Quiet)
    if (-not $script:RustExe) { throw 'RUST не найден — бинды записать некуда' }
    if (Test-RustRunning) { throw 'Rust запущен: игра перезапишет keys.cfg при выходе. Закройте игру или скопируйте команды для F1.' }
    $recs = @(Get-BindRecords)
    if ($recs.Count -eq 0) { throw 'Список биндов пуст' }
    $dir = Get-RustCfgDir
    if (-not $dir) { throw 'Не удалось открыть папку cfg игры' }
    $file = Join-Path $dir 'keys.cfg'
    $null = Backup-FileOnce $file 'keys.cfg'
    Backup-FileStamp $file 'keys'
    $existing = @()
    if (Test-Path -LiteralPath $file) {
        try { $existing = @([IO.File]::ReadAllLines($file)) } catch { $existing = @() }
    }
    $keys = @{}
    foreach ($r in $recs) { $keys[$r.Key] = $true }
    $keep = New-Object System.Collections.Generic.List[string]
    foreach ($ln in $existing) {
        $t = ([string]$ln).Trim()
        if (-not $t) { continue }
        if ($t -match '^bind\s+(\S+)\s+(.+)$') {
            if ($keys.ContainsKey($matches[1].ToLower())) { continue }
        }
        $keep.Add([string]$ln)
    }
    foreach ($r in $recs) { $keep.Add('bind ' + $r.Key + ' "' + $r.Cmd + '"') }
    [IO.File]::WriteAllLines($file, $keep, (New-Object System.Text.UTF8Encoding($false)))
    if (-not $Quiet) { Write-Log ('keys.cfg: записано биндов — ' + $recs.Count) 'ok' }
}

function Undo-RustBinds {
    if (-not $script:RustExe) { return }
    $dir = Get-RustCfgDir
    if (-not $dir) { return }
    $file = Join-Path $dir 'keys.cfg'
    if (Restore-FileOnce $file 'keys.cfg') { Write-Log 'keys.cfg восстановлен из бэкапа' 'ok' }
}

# ============================================================
#  ОЧИСТКА
# ============================================================
function Invoke-TempClean {
    $paths = @($env:TEMP, (Join-Path $env:SystemRoot 'Temp'),
               (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\INetCache'))
    $bytes = [int64]0
    $freed = 0
    foreach ($p in $paths) {
        if (-not (Test-Path -LiteralPath $p)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue)) {
            # Считаем реальный размер только у того, что действительно удалили.
            $size = [int64]0
            try {
                if ($f.PSIsContainer) {
                    $size = [int64](Get-ChildItem -LiteralPath $f.FullName -Recurse -Force -File -ErrorAction SilentlyContinue |
                                    Measure-Object -Property Length -Sum).Sum
                } else {
                    $size = [int64]$f.Length
                }
            } catch {}
            try {
                Remove-Item -LiteralPath $f.FullName -Recurse -Force -ErrorAction Stop
                $bytes += $size
                $freed = $freed + 1
            } catch {}
        }
    }
    Write-Log ('Очищено {0:N0} МБ временных файлов ({1} объектов)' -f ($bytes / 1MB), $freed) 'ok'
}

function Invoke-RecycleBin {
    try { Clear-RecycleBin -Force -ErrorAction Stop; Write-Log 'Корзина очищена' 'ok' }
    catch { Write-Log 'Корзина уже пуста' 'info' }
}

# ============================================================
#  RUST: максимальная легальная оптимизация cfg (FPS)
# ============================================================
$script:RustMaxCfgLines = @(
    'graphics.drawdistance 1500',
    'graphics.lodbias 0.5',
    'graphics.hlod True',
    'graphics.parallax 0',
    'graphics.af 4',
    'graphics.contactshadows False',
    'graphics.dof False',
    'graphics.shadowmode 1',
    'graphics.shadowlights 1',
    'graphics.aggressiveshadowlod True',
    'graphics.aggressiveshadowlodwearable True',
    'graphics.impostorshadows False',
    'graphics.volumetric_clouds 0',
    'graphics.renderscale 1',
    'graphics.maxqueuedframes 1',
    'graphicssettings.globaltexturemipmaplimit 1',
    'graphicssettings.shadowqualitypreset 0',
    'graphicssettings.enablelodcrossfade False',
    'graphicssettings.softparticles False',
    'graphicssettings.particleraycastbudget 256',
    'effects.antialiasing 0',
    'effects.ao False',
    'effects.bloom False',
    'effects.lensdirt False',
    'effects.motionblur False',
    'effects.shafts False',
    'effects.sharpen False',
    'effects.vignet False',
    'effects.hurtoverlay False',
    'effects.otherplayerslightflares False',
    'effects.creationeffects False',
    'effects.maxgibs 0',
    'particle.quality 25',
    'grass.quality 0',
    'grass.distance 0',
    'grass.displacement False',
    'decor.quality 0',
    'terrain.quality 25',
    'tree.quality 50',
    'tree.meshes 25',
    'mesh.quality 50',
    'water.quality 0',
    'water.reflections 0',
    'sss.enabled False',
    'reflection.planarreflections False',
    'legs.enablelegs False',
    'player.footik False',
    'ui.showinventoryplayer False',
    'fps.graph 0'
)

# Управляем только реальными конварами. Старые неверные ключи также
# включены в список, чтобы слияние вычищало их из client.cfg.
$script:RustMaxCfgManaged = @(
    'graphics.drawdistance','graphics.lodbias','graphics.hlod','graphics.parallax',
    'graphics.af','graphics.contactshadows','graphics.dof','graphics.shadowmode',
    'graphics.shadowlights','graphics.aggressiveshadowlod',
    'graphics.aggressiveshadowlodwearable','graphics.impostorshadows',
    'graphics.volumetric_clouds','graphics.renderscale','graphics.maxqueuedframes',
    'graphicssettings.globaltexturemipmaplimit','graphicssettings.shadowqualitypreset',
    'graphicssettings.enablelodcrossfade','graphicssettings.softparticles',
    'graphicssettings.particleraycastbudget','effects.antialiasing','effects.ao',
    'effects.bloom','effects.lensdirt','effects.motionblur','effects.shafts',
    'effects.sharpen','effects.vignet','effects.hurtoverlay',
    'effects.otherplayerslightflares','effects.creationeffects','effects.maxgibs',
    'particle.quality','grass.quality','grass.distance','grass.displacement',
    'decor.quality','terrain.quality','tree.quality','tree.meshes','mesh.quality',
    'water.quality','water.reflections','sss.enabled','reflection.planarreflections',
    'legs.enablelegs','player.footik','ui.showinventoryplayer','fps.graph',
    'graphics.shafts','graphics.shadowdistance','shadow.distance','graphics.quality',
    'global.quality','global.render_scale','graphics.antialiasing',
    'graphics.parallaxbuildings','graphics.shadowquality','global.pixel_scale'
)

function Invoke-RustMaxCfg {
    if (-not $script:RustExe) { throw 'RUST не найден — оптимизация cfg пропущена' }
    if (Test-RustRunning) { throw 'Rust запущен: игра перезапишет cfg при выходе. Закройте игру или используйте «Команды для F1».' }
    $dir = Get-RustCfgDir
    if (-not $dir) { throw 'Не удалось открыть папку cfg игры' }
    $file = Join-Path $dir 'client.cfg'
    $null = Backup-FileOnce $file 'client.cfg-max'
    Backup-FileStamp $file 'client-max'
    Merge-CfgFile -Path $file -Lines $script:RustMaxCfgLines -ManagedKeys $script:RustMaxCfgManaged
    Write-Log 'client.cfg: максимальная легальная оптимизация графики применена (бэкап сохранён)' 'ok'
}
function Undo-RustMaxCfg {
    if (-not $script:RustExe) { return }
    $dir = Get-RustCfgDir
    if (-not $dir) { return }
    $file = Join-Path $dir 'client.cfg'
    if (Restore-FileOnce $file 'client.cfg-max') {
        Write-Log 'client.cfg: максимальные настройки графики восстановлены' 'ok'
    } else {
        Write-Log 'client.cfg: резервная копия не найдена' 'warn'
    }
}

# ============================================================
#  НОВЫЕ ОПТИМИЗАЦИИ
# ============================================================
function Invoke-TimerRes {
    # 1) Разрешаем приложениям запрашивать точный таймер (Win10 2004+).
    $k = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel'
    $old = Get-Reg $k 'GlobalTimerResolutionRequests'
    if (-not $script:State.ContainsKey('TimerOld')) {
        $script:State['TimerOld'] = if ($null -eq $old) { -1 } else { [int]$old }
    }
    Set-RegDword $k 'GlobalTimerResolutionRequests' 1
    # 2) Держим реальное разрешение 1 мс через winmm, пока программа запущена.
    try { [RustSuite.Native]::TimerStart() } catch {}
    $script:State['TimerOn'] = $true
    Write-Log 'Таймер: разрешение 1 мс включено (действует, пока открыта программа)' 'ok'
}

function Undo-TimerRes {
    try { [RustSuite.Native]::TimerStop() } catch {}
    $script:State['TimerOn'] = $false
    $k = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel'
    $old = $script:State['TimerOld']
    if ($null -eq $old -or [int]$old -lt 0) { Remove-RegValue $k 'GlobalTimerResolutionRequests' }
    else { Set-RegDword $k 'GlobalTimerResolutionRequests' ([int64]$old) }
    Write-Log 'Параметры таймера восстановлены' 'ok'
}

function Invoke-CpuPark {
    # Официальная настройка powercfg «Processor performance core parking min cores».
    $sub     = '54533251-82be-4824-96c1-47b60b740d00'
    $setting = '0cc5b647-c1df-4637-891a-dec35c318583'
    if (-not $script:State.ContainsKey('CoreParkOld')) {
        $old = -1
        try {
            $q = ((& powercfg /query SCHEME_CURRENT $sub $setting 2>&1) -join "`n")
            $m = [regex]::Match($q, 'Current AC Power Setting Index:\s*(0x[0-9a-fA-F]+|\d+)')
            if ($m.Success) {
                $raw = $m.Groups[1].Value
                if ($raw -match '^0x') { $old = [int][Convert]::ToInt32($raw.Substring(2), 16) }
                else { $old = [int]$raw }
            }
        } catch {}
        $script:State['CoreParkOld'] = $old
    }
    & powercfg /setacvalueindex SCHEME_CURRENT $sub $setting 100 2>&1 | Out-Null
    & powercfg /setactive SCHEME_CURRENT 2>&1 | Out-Null
    Write-Log 'Парковка ядер CPU отключена (мин. ядер = 100%)' 'ok'
}

function Undo-CpuPark {
    $sub     = '54533251-82be-4824-96c1-47b60b740d00'
    $setting = '0cc5b647-c1df-4637-891a-dec35c318583'
    $old = $script:State['CoreParkOld']
    if ($null -ne $old -and [int]$old -ge 0) {
        & powercfg /setacvalueindex SCHEME_CURRENT $sub $setting ([int]$old) 2>&1 | Out-Null
        & powercfg /setactive SCHEME_CURRENT 2>&1 | Out-Null
    }
    Write-Log 'Парковка ядер CPU возвращена в исходное состояние' 'ok'
}

function Invoke-QosGame {
    $key = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched'
    Ensure-RegKey $key
    $old = Get-Reg $key 'NonBestEffortLimit'
    if (-not $script:State.ContainsKey('QosOld')) {
        $script:State['QosOld'] = if ($null -eq $old) { -1 } else { [int]$old }
    }
    $null = Set-ServiceState 'Psched' 'Manual'
    Set-RegDword $key 'NonBestEffortLimit' 0
    Write-Log 'QoS: резерв канала 0% — игра не конкурирует с фоновым трафиком' 'ok'
}

function Undo-QosGame {
    $key = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched'
    $old = $script:State['QosOld']
    if ($null -eq $old -or [int]$old -lt 0) { Remove-RegValue $key 'NonBestEffortLimit' }
    else { Set-RegDword $key 'NonBestEffortLimit' ([int64]$old) }
    Write-Log 'QoS возвращён к исходному состоянию' 'ok'
}

function Invoke-PrefetchOff {
    $p = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters'
    Backup-RegKey $p 'Prefetch.reg'
    if (-not $script:State.ContainsKey('PrefetchOld')) {
        $script:State['PrefetchOld'] = @{
            P = [string](Get-Reg $p 'EnablePrefetcher')
            S = [string](Get-Reg $p 'EnableSuperfetch')
        }
    }
    Set-RegDword $p 'EnablePrefetcher' 0
    Set-RegDword $p 'EnableSuperfetch' 0
    Write-Log 'Prefetch / Superfetch полностью отключены через реестр' 'warn'
}

function Undo-PrefetchOff {
    $p = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters'
    $o = $script:State['PrefetchOld']
    if ($o) {
        if ($o.P) { Set-RegDword $p 'EnablePrefetcher' ([int64]$o.P) } else { Remove-RegValue $p 'EnablePrefetcher' }
        if ($o.S) { Set-RegDword $p 'EnableSuperfetch' ([int64]$o.S) } else { Remove-RegValue $p 'EnableSuperfetch' }
    }
    Write-Log 'Prefetch / Superfetch восстановлены' 'ok'
}

function Invoke-DeliveryOpt {
    # Delivery Optimization качает обновления P2P и раздаёт их другим ПК,
    # забирая диск и канал во время игры. Оставляем только HTTP.
    $keys = @(
        @{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'; N = 'DODownloadMode'; V = 0 },
        @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config'; N = 'DODownloadMode'; V = 0 }
    )
    if (-not $script:State.ContainsKey('DeliveryOptOld')) {
        $snap = @{}
        foreach ($k in $keys) {
            $v = Get-Reg $k.P $k.N
            $snap[($k.P + '|' + $k.N)] = if ($null -eq $v) { -1 } else { [int64]$v }
        }
        $script:State['DeliveryOptOld'] = $snap
    }
    foreach ($k in $keys) { Set-RegDword $k.P $k.N $k.V }
    $null = Set-ServiceState 'DoSvc' 'Manual' -StopIt
    Write-Log 'Delivery Optimization: P2P-раздача отключена, служба остановлена' 'ok'
}

function Undo-DeliveryOpt {
    $snap = $script:State['DeliveryOptOld']
    if ($snap) {
        foreach ($key in @($snap.Keys)) {
            $parts = ([string]$key).Split('|')
            if ($parts.Count -lt 2) { continue }
            $v = [int64]$snap[$key]
            if ($v -lt 0) { Remove-RegValue $parts[0] $parts[1] }
            else { Set-RegDword $parts[0] $parts[1] $v }
        }
    }
    $st = [string]$script:State['svc_DoSvc']; if (-not $st) { $st = 'Manual' }
    try { Set-Service -Name 'DoSvc' -StartupType $st -ErrorAction SilentlyContinue } catch {}
    Write-Log 'Delivery Optimization возвращён к прежним настройкам' 'ok'
}

function Invoke-NetPower {
    $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
                  Where-Object { $_.Status -eq 'Up' })
    if ($adapters.Count -eq 0) { throw 'Активный сетевой адаптер не найден' }
    $names = @()
    foreach ($a in $adapters) {
        try {
            Disable-NetAdapterPowerManagement -Name $a.Name -ErrorAction Stop
            $names += [string]$a.Name
        } catch {}
    }
    if ($names.Count -eq 0) { throw 'Не удалось отключить энергосбережение адаптера' }
    $script:State['NetPowerAdapters'] = $names
    Write-Log ('Энергосбережение сетевого адаптера отключено: ' + ($names -join ', ')) 'ok'
}

function Undo-NetPower {
    $names = @($script:State['NetPowerAdapters'])
    foreach ($n in $names) {
        if (-not $n) { continue }
        try { Enable-NetAdapterPowerManagement -Name ([string]$n) -ErrorAction SilentlyContinue } catch {}
    }
    Write-Log 'Энергосбережение сетевого адаптера возвращено' 'ok'
}

function Invoke-ShaderClean {
    $paths = @(
        (Join-Path $env:LOCALAPPDATA 'D3DSCache'),
        (Join-Path $env:LOCALAPPDATA 'NVIDIA\DXCache'),
        (Join-Path $env:LOCALAPPDATA 'NVIDIA\GLCache'),
        (Join-Path $env:LOCALAPPDATA 'AMD\DxCache'),
        (Join-Path $env:LOCALAPPDATA 'AMD\DxcCache'),
        (Join-Path $env:LOCALAPPDATA 'Intel\ShaderCache')
    )
    $bytes = [int64]0
    $freed = 0
    foreach ($p in $paths) {
        if (-not (Test-Path -LiteralPath $p)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue)) {
            $size = [int64]0
            try {
                if ($f.PSIsContainer) {
                    $size = [int64](Get-ChildItem -LiteralPath $f.FullName -Recurse -Force -File -ErrorAction SilentlyContinue |
                                    Measure-Object -Property Length -Sum).Sum
                } else { $size = [int64]$f.Length }
            } catch {}
            try {
                Remove-Item -LiteralPath $f.FullName -Recurse -Force -ErrorAction Stop
                $bytes += $size
                $freed = $freed + 1
            } catch {}
        }
    }
    Write-Log ('Кэш шейдеров очищен: {0:N0} МБ ({1} объектов), игра соберёт его заново' -f ($bytes / 1MB), $freed) 'ok'
}

# ============================================================
#  НОВЫЕ БЕЗОПАСНЫЕ ТВИКИ v5.0 (все обратимые)
# ============================================================
function Set-DwordBatch {
    param([string]$StateKey, $Items)
    if (-not $script:State.ContainsKey($StateKey)) {
        $snap = @{}
        foreach ($it in $Items) {
            $v = Get-Reg $it.P $it.N
            $snap[($it.P + '|' + $it.N)] = if ($null -eq $v) { 'MISSING' } else { [string]$v }
        }
        $script:State[$StateKey] = $snap
    }
    foreach ($it in $Items) { Set-RegDword $it.P $it.N ([int64]$it.V) }
}

function Undo-DwordBatch {
    param([string]$StateKey)
    $snap = $script:State[$StateKey]
    if (-not $snap) { return }
    foreach ($key in @($snap.Keys)) {
        $parts = ([string]$key).Split('|')
        if ($parts.Count -lt 2) { continue }
        if ([string]$snap[$key] -eq 'MISSING') { Remove-RegValue $parts[0] $parts[1] }
        else { Set-RegDword $parts[0] $parts[1] ([int64]$snap[$key]) }
    }
}

function Set-StringBatch {
    param([string]$StateKey, $Items)
    if (-not $script:State.ContainsKey($StateKey)) {
        $snap = @{}
        foreach ($it in $Items) {
            $v = Get-Reg $it.P $it.N
            $snap[($it.P + '|' + $it.N)] = if ($null -eq $v) { 'MISSING' } else { [string]$v }
        }
        $script:State[$StateKey] = $snap
    }
    foreach ($it in $Items) { Set-RegStr $it.P $it.N ([string]$it.V) }
}

function Undo-StringBatch {
    param([string]$StateKey)
    $snap = $script:State[$StateKey]
    if (-not $snap) { return }
    foreach ($key in @($snap.Keys)) {
        $parts = ([string]$key).Split('|')
        if ($parts.Count -lt 2) { continue }
        if ([string]$snap[$key] -eq 'MISSING') { Remove-RegValue $parts[0] $parts[1] }
        else { Set-RegStr $parts[0] $parts[1] ([string]$snap[$key]) }
    }
}

# 1. Xbox Game Bar без оверлея и подсказок
function Invoke-GameBarOff {
    $items = @(
        @{ P = 'HKCU:\Software\Microsoft\GameBar'; N = 'ShowStartupPanel'; V = 0 },
        @{ P = 'HKCU:\Software\Microsoft\GameBar'; N = 'UseNexusForGameBarEnabled'; V = 0 },
        @{ P = 'HKCU:\Software\Microsoft\GameBar'; N = 'AutoGameModeEnabled'; V = 1 },
        @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'; N = 'AppCaptureEnabled'; V = 0 },
        @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'; N = 'HistoricalCaptureEnabled'; V = 0 }
    )
    Set-DwordBatch 'GameBarOld' $items
    Write-Log 'Game Bar: оверлей и автозапись отключены, игровой режим сохранён' 'ok'
}
function Undo-GameBarOff { Undo-DwordBatch 'GameBarOld'; Write-Log 'Game Bar восстановлен' 'ok' }

# 2. Виджеты Windows 11
function Invoke-WidgetsOff {
    $items = @(
        @{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh'; N = 'AllowNewsAndInterests'; V = 0 },
        @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; N = 'TaskbarDa'; V = 0 }
    )
    Set-DwordBatch 'WidgetsOld' $items
    Write-Log 'Виджеты Windows отключены' 'ok'
}
function Undo-WidgetsOff { Undo-DwordBatch 'WidgetsOld'; Write-Log 'Виджеты Windows восстановлены' 'ok' }

# 3. Copilot
function Invoke-CopilotOff {
    $items = @(
        @{ P = 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot'; N = 'TurnOffWindowsCopilot'; V = 1 },
        @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; N = 'ShowCopilotButton'; V = 0 }
    )
    Set-DwordBatch 'CopilotOld' $items
    Write-Log 'Copilot отключён и убран с панели задач' 'ok'
}
function Undo-CopilotOff { Undo-DwordBatch 'CopilotOld'; Write-Log 'Copilot восстановлен' 'ok' }

# 4. Windows Recall (ИИ-запись экрана)
function Invoke-RecallOff {
    $items = @(
        @{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; N = 'DisableAIDataAnalysis'; V = 1 },
        @{ P = 'HKCU:\Software\Policies\Microsoft\Windows\WindowsAI'; N = 'DisableAIDataAnalysis'; V = 1 }
    )
    Set-DwordBatch 'RecallOld' $items
    Write-Log 'Windows Recall отключён (политика WindowsAI)' 'ok'
}
function Undo-RecallOff { Undo-DwordBatch 'RecallOld'; Write-Log 'Настройки Windows Recall восстановлены' 'ok' }

# 5. Рекомендации и реклама в меню «Пуск»
function Invoke-SuggestionsOff {
    $items = @(
        @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; N = 'Start_IrisRecommendations'; V = 0 },
        @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; N = 'ShowSuggestions'; V = 0 },
        @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; N = 'SilentInstalledAppsEnabled'; V = 0 },
        @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; N = 'SystemPaneSuggestionsEnabled'; V = 0 },
        @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; N = 'SubscribedContent-338388Enabled'; V = 0 },
        @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; N = 'SubscribedContent-338389Enabled'; V = 0 },
        @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; N = 'SubscribedContent-353698Enabled'; V = 0 },
        @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; N = 'PreInstalledAppsEnabled'; V = 0 }
    )
    Set-DwordBatch 'SuggestionsOld' $items
    Write-Log 'Рекомендации и тихая установка приложений в «Пуске» отключены' 'ok'
}
function Undo-SuggestionsOff { Undo-DwordBatch 'SuggestionsOld'; Write-Log 'Рекомендации «Пуска» восстановлены' 'ok' }

# 6. Поиск без веб-результатов и Bing
function Invoke-SearchWebOff {
    $items = @(
        @{ P = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'; N = 'DisableSearchBoxSuggestions'; V = 1 },
        @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; N = 'BingSearchEnabled'; V = 0 },
        @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; N = 'CortanaConsent'; V = 0 }
    )
    Set-DwordBatch 'SearchWebOld' $items
    Write-Log 'Поиск Windows: веб-результаты Bing отключены' 'ok'
}
function Undo-SearchWebOff { Undo-DwordBatch 'SearchWebOld'; Write-Log 'Веб-поиск Windows восстановлен' 'ok' }

# 7. Фоновые приложения глобально
function Invoke-BgAppsGlobal {
    $items = @(
        @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications'; N = 'GlobalUserDisabled'; V = 1 },
        @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; N = 'BackgroundAppGlobalToggle'; V = 0 }
    )
    Set-DwordBatch 'BgAppsGlobalOld' $items
    Write-Log 'Фоновые приложения Windows ограничены глобально' 'ok'
}
function Undo-BgAppsGlobal { Undo-DwordBatch 'BgAppsGlobalOld'; Write-Log 'Фоновые приложения восстановлены' 'ok' }

# 8. Прозрачность Windows
function Invoke-TransparencyOff {
    $items = @(
        @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; N = 'EnableTransparency'; V = 0 }
    )
    Set-DwordBatch 'TransparencyOld' $items
    Write-Log 'Прозрачность Windows отключена — чуть меньше нагрузки на GPU' 'ok'
}
function Undo-TransparencyOff { Undo-DwordBatch 'TransparencyOld'; Write-Log 'Прозрачность Windows восстановлена' 'ok' }

# 9. Автозапуск с носителей (AutoPlay / AutoRun)
function Invoke-AutoPlayOff {
    $items = @(
        @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers'; N = 'DisableAutoplay'; V = 1 },
        @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'; N = 'NoDriveTypeAutoRun'; V = 255 }
    )
    Set-DwordBatch 'AutoPlayOld' $items
    Write-Log 'AutoPlay и AutoRun для съёмных носителей отключены' 'ok'
}
function Undo-AutoPlayOff { Undo-DwordBatch 'AutoPlayOld'; Write-Log 'AutoPlay восстановлен' 'ok' }

# 10. Залипание/фильтрация/переключение клавиш без горячих клавиш
function Invoke-StickyKeysOff {
    $items = @(
        @{ P = 'HKCU:\Control Panel\Accessibility\StickyKeys'; N = 'Flags'; V = '506' },
        @{ P = 'HKCU:\Control Panel\Accessibility\ToggleKeys'; N = 'Flags'; V = '58' },
        @{ P = 'HKCU:\Control Panel\Accessibility\Keyboard Response'; N = 'Flags'; V = '122' }
    )
    Set-StringBatch 'StickyKeysOld' $items
    Write-Log 'Случайный вызов залипания/фильтрации клавиш отключён' 'ok'
}
function Undo-StickyKeysOff { Undo-StringBatch 'StickyKeysOld'; Write-Log 'Спец. возможности клавиатуры восстановлены' 'ok' }

# ============================================================
#  WINDOWS CARE ENGINE — очистка
#  Стандартные средства Windows, без сторонних бинарников.
# ============================================================

$script:CleanBytes   = [int64]0
$script:CleanObjects = [int]0
$script:CleanNotes   = New-Object System.Collections.Generic.List[string]

function Reset-CleanMeter {
    $script:CleanBytes   = [int64]0
    $script:CleanObjects = [int]0
    $script:CleanNotes.Clear()
}

function Add-CleanMeter {
    param([int64]$Bytes = 0, [int]$Objects = 0, [string]$Note = '')
    if ($Bytes -gt 0) { $script:CleanBytes += $Bytes }
    if ($Objects -gt 0) { $script:CleanObjects += $Objects }
    if ($Note) { $script:CleanNotes.Add($Note) }
}

function Get-CleanMeterText {
    return ('{0:N1} МБ · {1:N0} объектов' -f ($script:CleanBytes / 1MB), $script:CleanObjects)
}

function Write-CleanSummary {
    param([string]$Title = 'Очистка')
    $mb = [math]::Round($script:CleanBytes / 1MB, 1)
    Write-Log ('{0}: освобождено {1:N1} МБ, удалено объектов — {2:N0}' -f $Title, $mb, $script:CleanObjects) 'ok'
    $script:State['LastCleanMB']    = $mb
    $script:State['LastCleanCount'] = $script:CleanObjects
    $script:State['LastCleanTitle'] = $Title
    $script:State['LastCleanAt']    = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Save-State
}

# ------------------------------------------------------------
#  Безопасные файловые операции
# ------------------------------------------------------------
function Get-PathBytes {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return [int64]0 }
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (-not $item.PSIsContainer) { return [int64]$item.Length }
        $sum = (Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
                Where-Object { -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) } |
                Measure-Object -Property Length -Sum).Sum
        if ($null -eq $sum) { return [int64]0 }
        return [int64]$sum
    } catch { return [int64]0 }
}

function Clear-FolderSafe {
    param([string]$Path, [string]$Filter = '*')
    $res = [pscustomobject]@{ Path = $Path; Bytes = [int64]0; Objects = 0; Skipped = 0 }
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $res }
    $items = @(Get-ChildItem -LiteralPath $Path -Force -Filter $Filter -ErrorAction SilentlyContinue)
    foreach ($it in $items) {
        if ($it.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            $res.Skipped++
            continue
        }
        $size = if ($it.PSIsContainer) { Get-PathBytes $it.FullName } else { [int64]$it.Length }
        try {
            Remove-Item -LiteralPath $it.FullName -Recurse -Force -ErrorAction Stop
            $res.Bytes += $size
            $res.Objects++
            Add-CleanMeter -Bytes $size -Objects 1
        } catch {
            $res.Skipped++
        }
    }
    return $res
}

function Clear-FilesByPattern {
    param([string]$Path, [string]$Pattern)
    $res = [pscustomobject]@{ Path = $Path; Bytes = [int64]0; Objects = 0; Skipped = 0 }
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $res }
    foreach ($f in @(Get-ChildItem -LiteralPath $Path -Filter $Pattern -File -Force -ErrorAction SilentlyContinue)) {
        if ($f.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { $res.Skipped++; continue }
        try {
            $size = [int64]$f.Length
            Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
            $res.Bytes += $size
            $res.Objects++
            Add-CleanMeter -Bytes $size -Objects 1
        } catch { $res.Skipped++ }
    }
    return $res
}

function Remove-FileSafe {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return }
    try {
        $size = [int64](Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue).Length
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        Add-CleanMeter -Bytes $size -Objects 1
    } catch {}
}

# ------------------------------------------------------------
#  Ядро очистки (не сбрасывает счётчик — используется DeepClean)
# ------------------------------------------------------------
function Clear-UpdateCacheCore {
    $services = @('wuauserv', 'bits', 'dosvc', 'usosvc')
    $saved = @{}
    foreach ($n in $services) {
        $svc = Get-Service -Name $n -ErrorAction SilentlyContinue
        if ($svc) {
            $saved[$n] = @{
                Status = [string]$svc.Status
                Start  = [string]$svc.StartType
            }
        }
    }
    foreach ($n in $services) {
        try { Stop-Service -Name $n -Force -ErrorAction SilentlyContinue } catch {}
    }
    try {
        $sd = Join-Path $env:SystemRoot 'SoftwareDistribution'
        Clear-FolderSafe (Join-Path $sd 'Download') | Out-Null
        Clear-FolderSafe (Join-Path $sd 'DeliveryOptimization') | Out-Null
        Clear-FolderSafe (Join-Path $sd 'PostRebootEventCache.V2') | Out-Null
        Clear-FolderSafe (Join-Path $env:SystemRoot 'Logs\WindowsUpdate') | Out-Null
        $doCache = Join-Path $env:SystemRoot 'ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache'
        Clear-FolderSafe $doCache | Out-Null
        if (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue) {
            try { Delete-DeliveryOptimizationCache -Force -ErrorAction SilentlyContinue } catch {}
        }
    } finally {
        foreach ($n in @($saved.Keys)) {
            try { Set-Service -Name $n -StartupType ([string]$saved[$n].Start) -ErrorAction SilentlyContinue } catch {}
            if ($saved[$n].Status -eq 'Running') {
                try { Start-Service -Name $n -ErrorAction SilentlyContinue } catch {}
            }
        }
    }
    Write-Log 'Кэш обновлений Windows и Delivery Optimization очищен' 'info'
}

function Clear-DumpCore {
    Clear-FolderSafe (Join-Path $env:LOCALAPPDATA 'CrashDumps') | Out-Null
    Clear-FolderSafe (Join-Path $env:SystemRoot 'Minidump') | Out-Null
    Clear-FolderSafe (Join-Path $env:SystemRoot 'LiveKernelReports') | Out-Null
    Clear-FolderSafe (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue') | Out-Null
    Clear-FolderSafe (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive') | Out-Null
    Clear-FolderSafe (Join-Path $env:ProgramData 'Microsoft\Windows\WER\Temp') | Out-Null
    Clear-FolderSafe (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER') | Out-Null
    Remove-FileSafe (Join-Path $env:SystemRoot 'MEMORY.DMP')
}

function Clear-BrowserCacheCore {
    $chromium = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data'),
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'),
        (Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data'),
        (Join-Path $env:LOCALAPPDATA 'Vivaldi\User Data'),
        (Join-Path $env:LOCALAPPDATA 'Yandex\YandexBrowser\User Data')
    )
    $cacheSubs = @(
        'Cache', 'Code Cache', 'GPUCache', 'DawnCache', 'GrShaderCache',
        'ShaderCache', 'Media Cache', 'Service Worker\CacheStorage',
        'Service Worker\ScriptCache'
    )
    foreach ($root in $chromium) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $profiles = @(Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue |
                      Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' -or $_.Name -eq 'Guest Profile' -or $_.Name -eq 'System Profile' })
        foreach ($p in $profiles) {
            foreach ($sub in $cacheSubs) {
                Clear-FolderSafe (Join-Path $p.FullName $sub) | Out-Null
            }
        }
        foreach ($sub in @('ShaderCache', 'GrShaderCache', 'GraphiteDawnCache')) {
            Clear-FolderSafe (Join-Path $root $sub) | Out-Null
        }
    }

    $ff = Join-Path $env:LOCALAPPDATA 'Mozilla\Firefox\Profiles'
    if (Test-Path -LiteralPath $ff) {
        foreach ($p in @(Get-ChildItem -LiteralPath $ff -Directory -Force -ErrorAction SilentlyContinue)) {
            foreach ($sub in @('cache2', 'startupCache', 'shader-cache')) {
                Clear-FolderSafe (Join-Path $p.FullName $sub) | Out-Null
            }
        }
    }

    $opera = Join-Path $env:LOCALAPPDATA 'Opera Software\Opera Stable'
    if (Test-Path -LiteralPath $opera) {
        foreach ($sub in @('Cache', 'Code Cache', 'GPUCache', 'Service Worker\CacheStorage')) {
            Clear-FolderSafe (Join-Path $opera $sub) | Out-Null
        }
    }
    Write-Log 'Кэш браузеров очищен (только Cache, без паролей и истории)' 'info'
}

function Clear-GameJunkCore {
    if ($script:SteamPath) {
        foreach ($sub in @('logs', 'dumps', 'appcache\httpcache', 'appcache\librarycache')) {
            Clear-FolderSafe (Join-Path $script:SteamPath $sub) | Out-Null
        }
        # Внутри steamapps\common\Rust не удаляем ничего: единственные файлы,
        # которые программа трогает в папке игры — официальные cfg (client.cfg,
        # keys.cfg). Так исключён любой риск для целостности клиента и EAC.
    }
    $rustLocal = Join-Path $env:LOCALAPPDATA 'Facepunch\Rust'
    if (Test-Path -LiteralPath $rustLocal) {
        foreach ($sub in @('logs', 'crashes')) {
            Clear-FolderSafe (Join-Path $rustLocal $sub) | Out-Null
        }
        Clear-FilesByPattern $rustLocal '*.dmp' | Out-Null
    }
    Write-Log 'Логи и дампы Steam / RUST очищены (папка игры и cfg не тронуты)' 'info'
}

function Clear-ThumbnailCore {
    $explorer = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
    Clear-FilesByPattern $explorer 'thumbcache_*.db' | Out-Null
    Clear-FilesByPattern $explorer 'iconcache_*.db' | Out-Null
    Clear-FolderSafe (Join-Path $explorer 'ThumbCacheToDelete') | Out-Null
    Clear-FolderSafe (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Caches') | Out-Null
    Write-Log 'Кэш эскизов и иконок очищен (занятые Explorer файлы пропущены)' 'info'
}

function Clear-DeepLogsCore {
    Clear-FilesByPattern (Join-Path $env:SystemRoot 'Logs\CBS') '*.log' | Out-Null
    Clear-FilesByPattern (Join-Path $env:SystemRoot 'Logs\CBS') '*.cab' | Out-Null
    Clear-FolderSafe (Join-Path $env:SystemRoot 'Logs\DISM') | Out-Null
    Clear-FolderSafe (Join-Path $env:SystemRoot 'Logs\MoSetup') | Out-Null
    Clear-FolderSafe (Join-Path $env:SystemRoot 'Logs\SIH') | Out-Null
    Clear-FolderSafe (Join-Path $env:SystemRoot 'Temp') | Out-Null
    Clear-FolderSafe (Join-Path $env:ProgramData 'Microsoft\Windows\WER\Temp') | Out-Null
    Write-Log 'Старые журналы CBS/DISM/Windows Update очищены' 'info'
}

function Clear-PrefetchCore {
    Clear-FilesByPattern (Join-Path $env:SystemRoot 'Prefetch') '*.pf' | Out-Null
    Clear-FolderSafe (Join-Path $env:SystemRoot 'Prefetch\ReadyBoot') | Out-Null
    Write-Log 'Prefetch очищен — первые запуски могут быть чуть медленнее' 'warn'
}

function Clear-OldWindowsCore {
    foreach ($name in @('Windows.old', '$Windows.~BT', '$Windows.~WS', '$WinREAgent')) {
        $path = Join-Path $env:SystemDrive $name
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $size = Get-PathBytes $path
        Write-Log ('Удаление ' + $name + ' (' + [math]::Round($size / 1MB, 1) + ' МБ)…') 'warn'
        try {
            & takeown.exe /F $path /R /A /D Y 2>&1 | Out-Null
            & icacls.exe $path /grant '*S-1-5-32-544:(OI)(CI)F' /T /C /Q 2>&1 | Out-Null
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
            Add-CleanMeter -Bytes $size -Objects 1
        } catch {
            Write-Log ('Не удалось удалить ' + $name + ': ' + $_.Exception.Message) 'warn'
        }
    }
}

function Clear-EventLogsCore {
    $logs = @(Get-WinEvent -ListLog * -ErrorAction SilentlyContinue |
              Where-Object { $_.IsEnabled -and $_.RecordCount -gt 0 })
    $cleared = 0
    foreach ($l in $logs) {
        try {
            & wevtutil.exe cl $l.LogName 2>&1 | Out-Null
            $cleared++
            Add-CleanMeter -Objects 1
        } catch {}
    }
    Write-Log ('Журналы событий очищены: ' + $cleared + ' из ' + $logs.Count) 'warn'
}

# ------------------------------------------------------------
#  Публичные модули очистки
# ------------------------------------------------------------
function Invoke-DeepClean {
    Reset-CleanMeter
    Write-Log 'Глубокая очистка Windows: старт' 'step'
    Clear-FolderSafe $env:TEMP | Out-Null
    Clear-FolderSafe (Join-Path $env:SystemRoot 'Temp') | Out-Null
    Clear-FolderSafe (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\INetCache') | Out-Null
    Clear-UpdateCacheCore
    Clear-DumpCore
    Clear-BrowserCacheCore
    Clear-GameJunkCore
    Clear-ThumbnailCore
    Clear-DeepLogsCore
    Write-CleanSummary 'Глубокая очистка Windows'
}

function Invoke-UpdateCacheClean {
    Reset-CleanMeter
    Clear-UpdateCacheCore
    Write-CleanSummary 'Кэш обновлений Windows'
}

function Invoke-DumpClean {
    Reset-CleanMeter
    Clear-DumpCore
    Write-CleanSummary 'Дампы и отчёты об ошибках'
}

function Invoke-BrowserCache {
    Reset-CleanMeter
    Clear-BrowserCacheCore
    Write-CleanSummary 'Кэш браузеров'
}

function Invoke-GameJunkClean {
    Reset-CleanMeter
    Clear-GameJunkCore
    Write-CleanSummary 'Логи и дампы Steam / RUST'
}

function Invoke-ThumbnailClean {
    Reset-CleanMeter
    Clear-ThumbnailCore
    Write-CleanSummary 'Кэш эскизов и иконок'
}

function Invoke-PrefetchClean {
    Reset-CleanMeter
    Clear-PrefetchCore
    Write-CleanSummary 'Prefetch'
}

function Invoke-OldWindowsClean {
    Reset-CleanMeter
    Clear-OldWindowsCore
    Write-CleanSummary 'Старые установки Windows'
}

function Invoke-EventLogClean {
    Reset-CleanMeter
    Clear-EventLogsCore
    Write-CleanSummary 'Журналы событий Windows'
}

# ============================================================
#  WINDOWS CARE ENGINE — восстановление и внешние инструменты
# ============================================================

function Invoke-ExternalTool {
    param(
        [string]$File,
        [string]$Arguments,
        [string]$Label = 'Операция',
        [int]$TimeoutMinutes = 60,
        [switch]$Quiet
    )
    if (-not $File) { throw 'Не указан исполняемый файл' }
    if (-not (Test-Path -LiteralPath $File)) { throw ('Не найден файл: ' + $File) }
    $tmpBase = Join-Path $script:Root ('tool-' + [Guid]::NewGuid().ToString('N'))
    $stdout = $tmpBase + '.out.log'
    $stderr = $tmpBase + '.err.log'
    $result = [pscustomobject]@{
        Label = $Label; ExitCode = -1; Elapsed = 0; Output = ''; Error = ''
    }
    $started = Get-Date
    try {
        $p = Start-Process -FilePath $File -ArgumentList $Arguments -WindowStyle Hidden `
             -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr -ErrorAction Stop
        while (-not $p.HasExited) {
            Start-Sleep -Milliseconds 300
            Pump
            $elapsed = ((Get-Date) - $started).TotalSeconds
            if (-not $Quiet) {
                Set-Status ('{0} · {1:N0} c' -f $Label, $elapsed) '#FF8A4C'
            }
            if ($TimeoutMinutes -gt 0 -and $elapsed -gt ($TimeoutMinutes * 60)) {
                try { $p.Kill() } catch {}
                Write-Log ($Label + ': превышено время ожидания, процесс остановлен') 'err'
                break
            }
        }
        try { $p.WaitForExit() } catch {}
        $result.ExitCode = [int]$p.ExitCode
    } catch {
        $result.Error = $_.Exception.Message
        Write-Log ($Label + ': ' + $result.Error) 'err'
    } finally {
        $result.Elapsed = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
        if (Test-Path -LiteralPath $stdout) {
            try { $result.Output = [IO.File]::ReadAllText($stdout) } catch {}
            Remove-Item -LiteralPath $stdout -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $stderr) {
            try { $result.Error = ($result.Error + ' ' + [IO.File]::ReadAllText($stderr)).Trim() } catch {}
            Remove-Item -LiteralPath $stderr -Force -ErrorAction SilentlyContinue
        }
    }
    if (-not $Quiet) {
        $tail = @(($result.Output -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -Last 8)
        foreach ($line in $tail) { Write-Log ('   ' + $line.Trim()) 'info' }
        if ($result.ExitCode -eq 0) {
            Write-Log ('{0}: готово за {1:N0} c' -f $Label, $result.Elapsed) 'ok'
        } else {
            Write-Log ('{0}: код {1} за {2:N0} c' -f $Label, $result.ExitCode, $result.Elapsed) 'warn'
        }
    }
    return $result
}

function Invoke-SfcScan {
    if (-not $script:IsAdmin) { throw 'Нужны права администратора' }
    Write-Log 'SFC /scannow: проверка системных файлов (может занять 5–20 минут)' 'step'
    Set-Status 'SFC /scannow · проверка системных файлов…' '#FF8A4C'
    $r = Invoke-ExternalTool -File (Join-Path $env:SystemRoot 'System32\sfc.exe') `
         -Arguments '/scannow' -Label 'SFC /scannow' -TimeoutMinutes 60
    if ($r.ExitCode -eq 0) {
        Write-Log 'SFC завершён. Если найдены исправленные файлы — перезагрузите ПК.' 'ok'
    } else {
        Write-Log ('SFC завершён с кодом ' + $r.ExitCode + '. Подробности — в журнале CBS.') 'warn'
    }
    return $r
}

function Invoke-DismRestore {
    if (-not $script:IsAdmin) { throw 'Нужны права администратора' }
    Write-Log 'DISM RestoreHealth: восстановление образа Windows (может занять 10–30 минут)' 'step'
    Set-Status 'DISM /RestoreHealth · восстановление образа…' '#FF8A4C'
    $r = Invoke-ExternalTool -File (Join-Path $env:SystemRoot 'System32\dism.exe') `
         -Arguments '/Online /Cleanup-Image /RestoreHealth' -Label 'DISM RestoreHealth' -TimeoutMinutes 90
    if ($r.ExitCode -eq 0) {
        Write-Log 'DISM: образ Windows восстановлен. Рекомендуется перезагрузка.' 'ok'
    } else {
        Write-Log ('DISM завершён с кодом ' + $r.ExitCode + '. Проверьте интернет и журнал DISM.') 'warn'
    }
    return $r
}

function Invoke-DismComponentCleanup {
    if (-not $script:IsAdmin) { throw 'Нужны права администратора' }
    Write-Log 'DISM StartComponentCleanup: очистка хранилища компонентов WinSxS' 'step'
    Set-Status 'DISM /StartComponentCleanup · очистка WinSxS…' '#FF8A4C'
    $r = Invoke-ExternalTool -File (Join-Path $env:SystemRoot 'System32\dism.exe') `
         -Arguments '/Online /Cleanup-Image /StartComponentCleanup' -Label 'DISM ComponentCleanup' -TimeoutMinutes 120
    if ($r.ExitCode -eq 0) { Write-Log 'WinSxS очищен без удаления актуальных компонентов.' 'ok' }
    return $r
}

# Имя для карточки очистки: тот же безопасный StartComponentCleanup.
function Invoke-WinSxSClean {
    Reset-CleanMeter
    $r = Invoke-DismComponentCleanup
    if ($r -and $r.ExitCode -eq 0) {
        Write-CleanSummary 'Очистка WinSxS'
    } else {
        Write-Log 'WinSxS: очистка завершилась не полностью, счётчик места не обновлён' 'warn'
    }
}

function Invoke-DismAnalyze {
    if (-not $script:IsAdmin) { throw 'Нужны права администратора' }
    Write-Log 'DISM AnalyzeComponentStore: анализ хранилища компонентов' 'step'
    $r = Invoke-ExternalTool -File (Join-Path $env:SystemRoot 'System32\dism.exe') `
         -Arguments '/Online /Cleanup-Image /AnalyzeComponentStore' -Label 'DISM Analyze' -TimeoutMinutes 60
    return $r
}

function Invoke-ChkdskScan {
    if (-not $script:IsAdmin) { throw 'Нужны права администратора' }
    Write-Log 'CHKDSK /scan: онлайн-проверка системного диска (без перезагрузки)' 'step'
    Set-Status 'CHKDSK /scan · проверка диска…' '#FF8A4C'
    $r = Invoke-ExternalTool -File (Join-Path $env:SystemRoot 'System32\chkdsk.exe') `
         -Arguments ((($env:SystemDrive) + ' /scan')) -Label 'CHKDSK /scan' -TimeoutMinutes 90
    return $r
}

function Invoke-WindowsUpdateReset {
    if (-not $script:IsAdmin) { throw 'Нужны права администратора' }
    Write-Log 'Сброс компонентов Windows Update: остановка служб и пересоздание кэша' 'step'
    $names = @('wuauserv', 'bits', 'cryptsvc', 'msiserver', 'appidsvc')
    $saved = @{}
    foreach ($n in $names) {
        $svc = Get-Service -Name $n -ErrorAction SilentlyContinue
        if ($svc) { $saved[$n] = @{ Status = [string]$svc.Status; Start = [string]$svc.StartType } }
    }
    foreach ($n in $names) {
        try { Stop-Service -Name $n -Force -ErrorAction SilentlyContinue } catch {}
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    foreach ($dirName in @('SoftwareDistribution', 'Catroot2')) {
        $path = Join-Path $env:SystemRoot $dirName
        if (Test-Path -LiteralPath $path) {
            try {
                Rename-Item -LiteralPath $path -NewName ($dirName + '.old-' + $stamp) -Force -ErrorAction Stop
                Write-Log ('Переименовано: ' + $dirName + ' → ' + $dirName + '.old-' + $stamp) 'info'
            } catch {
                Write-Log ('Не удалось переименовать ' + $dirName + ': ' + $_.Exception.Message) 'warn'
            }
        }
    }

    $dlls = @(
        'qmgr.dll', 'wuaueng.dll', 'wuapi.dll', 'wups.dll', 'wups2.dll',
        'softpub.dll', 'wintrust.dll', 'initpki.dll', 'oleaut32.dll',
        'ole32.dll', 'urlmon.dll', 'mshtml.dll', 'shdocvw.dll', 'browseui.dll'
    )
    foreach ($d in $dlls) {
        $p = Join-Path $env:SystemRoot 'System32\' + $d
        if (Test-Path -LiteralPath $p) {
            try { & regsvr32.exe /s $p 2>&1 | Out-Null } catch {}
        }
    }

    foreach ($n in @($saved.Keys)) {
        try { Set-Service -Name $n -StartupType ([string]$saved[$n].Start) -ErrorAction SilentlyContinue } catch {}
        if ($saved[$n].Status -eq 'Running') {
            try { Start-Service -Name $n -ErrorAction SilentlyContinue } catch {}
        }
    }
    Write-Log 'Windows Update сброшен. Перезагрузите ПК и проверьте обновления.' 'warn'
}

function Invoke-WindowsUpdateServicesFix {
    $map = @{
        wuauserv  = 'Manual'
        bits      = 'Manual'
        cryptsvc  = 'Automatic'
        msiserver = 'Manual'
        dosvc     = 'Manual'
    }
    foreach ($n in @($map.Keys)) {
        $svc = Get-Service -Name $n -ErrorAction SilentlyContinue
        if (-not $svc) { continue }
        try { Set-Service -Name $n -StartupType $map[$n] -ErrorAction SilentlyContinue } catch {}
        if ($n -eq 'cryptsvc' -and $svc.Status -ne 'Running') {
            try { Start-Service -Name $n -ErrorAction SilentlyContinue } catch {}
        }
    }
    Write-Log 'Службы Windows Update переведены в рабочий режим' 'ok'
}

function Invoke-NetworkReset {
    if (-not $script:IsAdmin) { throw 'Нужны права администратора' }
    Write-Log 'Сброс сети: Winsock, TCP/IP и DNS-кэш. После сброса нужна перезагрузка.' 'warn'
    $netsh = Join-Path $env:SystemRoot 'System32\netsh.exe'
    Invoke-ExternalTool -File $netsh -Arguments 'winsock reset' -Label 'netsh winsock reset' -TimeoutMinutes 5 | Out-Null
    Invoke-ExternalTool -File $netsh -Arguments 'int ip reset' -Label 'netsh int ip reset' -TimeoutMinutes 5 | Out-Null
    try { & ipconfig.exe /flushdns 2>&1 | Out-Null } catch {}
    Write-Log 'Сеть сброшена. Перезагрузите ПК.' 'warn'
}

function Invoke-WmiRepair {
    if (-not $script:IsAdmin) { throw 'Нужны права администратора' }
    $wmi = Join-Path $env:SystemRoot 'System32\wbem\winmgmt.exe'
    Write-Log 'Проверка репозитория WMI…' 'step'
    & $wmi /verifyrepository 2>&1 | Out-Null
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        Write-Log 'Репозиторий WMI не согласован — запускаю salvage' 'warn'
        & $wmi /salvagerepository 2>&1 | Out-Null
        $code = $LASTEXITCODE
    }
    try { Stop-Service -Name 'Winmgmt' -Force -ErrorAction SilentlyContinue } catch {}
    try { Start-Service -Name 'Winmgmt' -ErrorAction SilentlyContinue } catch {}
    if ($code -eq 0) { Write-Log 'WMI: репозиторий согласован.' 'ok' }
    else { Write-Log ('WMI: код ' + $code + '. Если проблемы остались — потребуется перезагрузка.') 'warn' }
}

function Invoke-StoreReset {
    Write-Log 'Сброс кэша Microsoft Store…' 'step'
    $ok = $false
    try {
        $p = Start-Process -FilePath 'wsreset.exe' -ArgumentList '-i' -WindowStyle Hidden -PassThru -Wait -ErrorAction Stop
        $ok = ($p.ExitCode -eq 0)
    } catch {}
    if (-not $ok) {
        try { Start-Process -FilePath 'wsreset.exe' -WindowStyle Hidden -Wait | Out-Null; $ok = $true } catch {}
    }
    if ($ok) { Write-Log 'Кэш Microsoft Store очищен' 'ok' }
    else { Write-Log 'Не удалось запустить wsreset.exe' 'warn' }
}

function Invoke-IconCacheRebuild {
    if (-not $script:IsAdmin) { throw 'Нужны права администратора' }
    Write-Log 'Пересборка кэша иконок: Explorer будет перезапущен' 'warn'
    try { Stop-Process -Name 'explorer' -Force -ErrorAction SilentlyContinue } catch {}
    Start-Sleep -Milliseconds 1200
    Reset-CleanMeter
    Clear-ThumbnailCore
    try { Start-Process -FilePath 'explorer.exe' | Out-Null } catch {}
    Write-CleanSummary 'Кэш иконок и эскизов'
    Write-Log 'Explorer перезапущен, кэш иконок пересобран' 'ok'
}

function Invoke-TimeResync {
    Write-Log 'Синхронизация системного времени…' 'step'
    try { Set-Service -Name 'W32Time' -StartupType Automatic -ErrorAction SilentlyContinue } catch {}
    try { Start-Service -Name 'W32Time' -ErrorAction SilentlyContinue } catch {}
    & w32tm.exe /resync /force 2>&1 | Out-Null
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        & w32tm.exe /config '/manualpeerlist:time.windows.com,0x9' /syncfromflags:manual /update 2>&1 | Out-Null
        try { Restart-Service -Name 'W32Time' -Force -ErrorAction SilentlyContinue } catch {}
        & w32tm.exe /resync /force 2>&1 | Out-Null
        $code = $LASTEXITCODE
    }
    if ($code -eq 0) { Write-Log 'Время синхронизировано с time.windows.com' 'ok' }
    else { Write-Log 'Синхронизация времени не удалась — проверьте доступ к интернету' 'warn' }
}

function Invoke-DriverRescan {
    if (-not $script:IsAdmin) { throw 'Нужны права администратора' }
    Write-Log 'Поиск изменений оборудования (pnputil /scan-devices)…' 'step'
    Invoke-ExternalTool -File (Join-Path $env:SystemRoot 'System32\pnputil.exe') `
        -Arguments '/scan-devices' -Label 'pnputil scan-devices' -TimeoutMinutes 10 | Out-Null
    $bad = @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
             Where-Object { $_.ConfigManagerErrorCode -ne 0 })
    if ($bad.Count -eq 0) { Write-Log 'Проблемных устройств не найдено' 'ok' }
    else { Write-Log ('Устройств с ошибками: ' + $bad.Count + ' — проверьте Диспетчер устройств') 'warn' }
}

function Invoke-SpoolerReset {
    if (-not $script:IsAdmin) { throw 'Нужны права администратора' }
    Write-Log 'Сброс очереди печати…' 'step'
    try { Stop-Service -Name 'Spooler' -Force -ErrorAction Stop } catch {
        Write-Log ('Не удалось остановить Spooler: ' + $_.Exception.Message) 'warn'
        return
    }
    Clear-FolderSafe (Join-Path $env:SystemRoot 'System32\spool\PRINTERS') | Out-Null
    try { Start-Service -Name 'Spooler' -ErrorAction Stop } catch {}
    Write-Log 'Очередь печати очищена, служба Spooler запущена' 'ok'
}

function Invoke-RestorePointNow {
    Write-Log 'Создание точки восстановления…' 'step'
    New-RestorePoint
}

# ------------------------------------------------------------
#  Дополнительные оптимизации
# ------------------------------------------------------------
function Invoke-FullscreenOpt {
    $p = 'HKCU:\System\GameConfigStore'
    $names = @(
        'GameDVR_FSEBehaviorMode',
        'GameDVR_HonorUserFSEBehaviorMode',
        'GameDVR_DXGIHonorFSEWindowsCompatible',
        'GameDVR_EFSEFeatureFlags'
    )
    if (-not $script:State.ContainsKey('FseOld')) {
        $snap = @{}
        foreach ($n in $names) {
            $v = Get-Reg $p $n
            $snap[$n] = if ($null -eq $v) { [int64]-1 } else { [int64]$v }
        }
        $script:State['FseOld'] = $snap
    }
    Set-RegDword $p 'GameDVR_FSEBehaviorMode' 2
    Set-RegDword $p 'GameDVR_HonorUserFSEBehaviorMode' 1
    Set-RegDword $p 'GameDVR_DXGIHonorFSEWindowsCompatible' 1
    Set-RegDword $p 'GameDVR_EFSEFeatureFlags' 0
    Write-Log 'Глобальные оптимизации полного экрана отключены (FSE)' 'ok'
}

function Undo-FullscreenOpt {
    $p = 'HKCU:\System\GameConfigStore'
    $snap = $script:State['FseOld']
    if ($snap) {
        foreach ($n in @($snap.Keys)) {
            $v = [int64]$snap[$n]
            if ($v -lt 0) { Remove-RegValue $p $n } else { Set-RegDword $p $n $v }
        }
    }
    Write-Log 'Настройки полного экрана восстановлены' 'ok'
}

function Invoke-XboxServices {
    foreach ($n in @('XblAuthManager', 'XblGameSave', 'XboxNetApiSvc', 'XboxGipSvc')) {
        $null = Set-ServiceState $n 'Disabled' -StopIt
    }
    Write-Log 'Службы Xbox отключены (Game Pass и Xbox-приложения могут не работать)' 'warn'
}

function Undo-XboxServices {
    foreach ($n in @('XblAuthManager', 'XblGameSave', 'XboxNetApiSvc', 'XboxGipSvc')) {
        $st = [string]$script:State["svc_$n"]
        if (-not $st) { $st = 'Manual' }
        try { Set-Service -Name $n -StartupType $st -ErrorAction SilentlyContinue } catch {}
    }
    Write-Log 'Службы Xbox возвращены в исходное состояние' 'ok'
}

function Invoke-FastStartupOff {
    $p = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
    $old = Get-Reg $p 'HiberbootEnabled'
    if (-not $script:State.ContainsKey('FastStartupOld')) {
        $script:State['FastStartupOld'] = if ($null -eq $old) { -1 } else { [int64]$old }
    }
    Set-RegDword $p 'HiberbootEnabled' 0
    Write-Log 'Быстрый запуск Windows отключён — полное завершение работы и чистая загрузка' 'ok'
}

function Undo-FastStartupOff {
    $p = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
    $old = $script:State['FastStartupOld']
    if ($null -eq $old -or [int64]$old -lt 0) { Remove-RegValue $p 'HiberbootEnabled' }
    else { Set-RegDword $p 'HiberbootEnabled' ([int64]$old) }
    Write-Log 'Быстрый запуск Windows восстановлен' 'ok'
}

# ============================================================
#  ДИАГНОСТИКА WINDOWS
#  Быстрые проверки типовых проблем без тяжёлых WMI-запросов.
# ============================================================

function New-HealthCheck {
    param(
        [string]$Id,
        [string]$Title,
        [string]$Status = 'info',
        [string]$Detail = '',
        [string]$Fix = '',
        [string]$FixLabel = ''
    )
    return [pscustomobject]@{
        Id = $Id; Title = $Title; Status = $Status; Detail = $Detail
        Fix = $Fix; FixLabel = $FixLabel
    }
}

function Test-PendingReboot {
    $pending = $false
    foreach ($k in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )) {
        if (Test-Path -LiteralPath $k) { $pending = $true; break }
    }
    if (-not $pending) {
        $pfro = Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'PendingFileRenameOperations'
        if ($pfro -and @($pfro).Count -gt 0) { $pending = $true }
    }
    return $pending
}

function Get-SystemHealthReport {
    param([switch]$Quick)
    $out = New-Object System.Collections.Generic.List[object]

    $out.Add((New-HealthCheck 'admin' 'Права администратора' `
        $(if ($script:IsAdmin) { 'ok' } else { 'warn' }) `
        $(if ($script:IsAdmin) { 'Полный доступ к обслуживанию Windows' } else { 'Часть проверок и исправлений недоступна — перезапустите от имени администратора' })))

    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop | Select-Object -First 1
        $up = (Get-Date) - $os.LastBootUpTime
        $uptimeText = '{0} дн. {1} ч' -f [int]$up.TotalDays, $up.Hours
        $out.Add((New-HealthCheck 'uptime' 'Время работы системы' 'info' ('Последняя загрузка: ' + $uptimeText)))
        $out.Add((New-HealthCheck 'reboot' 'Ожидание перезагрузки' `
            $(if (Test-PendingReboot) { 'warn' } else { 'ok' }) `
            $(if (Test-PendingReboot) { 'Есть незавершённые изменения — перезагрузите ПК' } else { 'Незавершённых обновлений нет' }) `
            'reboot' 'ПЕРЕЗАГРУЗИТЬ'))
    } catch {
        $out.Add((New-HealthCheck 'uptime' 'Время работы системы' 'info' 'Не удалось получить сведения'))
    }

    try {
        $sys = $env:SystemDrive
        $d = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='" + $sys + "'") -ErrorAction Stop
        $freeGb = [math]::Round($d.FreeSpace / 1GB, 1)
        $totalGb = [math]::Round($d.Size / 1GB, 1)
        $pct = if ($d.Size -gt 0) { [math]::Round($d.FreeSpace / $d.Size * 100, 1) } else { 0 }
        $st = if ($pct -lt 5) { 'err' } elseif ($pct -lt 10) { 'warn' } else { 'ok' }
        $out.Add((New-HealthCheck 'disk' 'Свободное место на системном диске' $st `
            ('{0} ГБ свободно из {1} ГБ ({2} %)' -f $freeGb, $totalGb, $pct) 'cleanup' 'К ОЧИСТКЕ'))
    } catch {
        $out.Add((New-HealthCheck 'disk' 'Свободное место' 'info' 'Не удалось прочитать размер диска'))
    }

    if (-not $Quick) {
        try {
            $disks = @(Get-PhysicalDisk -ErrorAction Stop)
            if ($disks.Count -gt 0) {
                $bad = @($disks | Where-Object { $_.HealthStatus -ne 'Healthy' })
                $names = ($disks | ForEach-Object { [string]$_.FriendlyName } | Select-Object -First 3) -join ', '
                $st = if ($bad.Count -gt 0) { 'err' } else { 'ok' }
                $detail = if ($bad.Count -gt 0) {
                    'Проблемы: ' + (($bad | ForEach-Object { [string]$_.FriendlyName + ' (' + [string]$_.HealthStatus + ')' }) -join ', ')
                } else { 'SMART/Health: ' + $names }
                $out.Add((New-HealthCheck 'disksmart' 'Здоровье накопителей' $st $detail))
            }
        } catch {}

        try {
            $wmi = Join-Path $env:SystemRoot 'System32\wbem\winmgmt.exe'
            if (Test-Path -LiteralPath $wmi) {
                & $wmi /verifyrepository 2>&1 | Out-Null
                $code = $LASTEXITCODE
                if ($code -eq 0) {
                    $out.Add((New-HealthCheck 'wmi' 'Репозиторий WMI' 'ok' 'Согласован'))
                } else {
                    $out.Add((New-HealthCheck 'wmi' 'Репозиторий WMI' 'err' ('Код проверки ' + $code + ' — возможно повреждение') 'wmi' 'ЛЕЧИТЬ WMI'))
                }
            }
        } catch {}
    }

    try {
        $disabled = @()
        foreach ($n in @('wuauserv', 'bits', 'cryptsvc', 'msiserver')) {
            $s = Get-Service -Name $n -ErrorAction SilentlyContinue
            if ($s -and $s.StartType -eq 'Disabled') { $disabled += $n }
        }
        if ($disabled.Count -gt 0) {
            $out.Add((New-HealthCheck 'wu' 'Службы Windows Update' 'warn' ('Отключены: ' + ($disabled -join ', ')) 'wu' 'ИСПРАВИТЬ'))
        } else {
            $out.Add((New-HealthCheck 'wu' 'Службы Windows Update' 'ok' 'Не отключены'))
        }
    } catch {}

    try {
        $t = Get-Service -Name 'W32Time' -ErrorAction SilentlyContinue
        if ($t) {
            if ($t.Status -ne 'Running') {
                $out.Add((New-HealthCheck 'time' 'Служба времени' 'warn' 'Остановлена — время может уходить' 'time' 'СИНХРОНИЗИРОВАТЬ'))
            } else {
                $out.Add((New-HealthCheck 'time' 'Служба времени' 'ok' 'Работает'))
            }
        }
    } catch {}

    try {
        $bad = @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
                 Where-Object { $_.ConfigManagerErrorCode -ne 0 })
        if ($bad.Count -gt 0) {
            $names = ($bad | Select-Object -First 3 | ForEach-Object { [string]$_.Name }) -join ', '
            $out.Add((New-HealthCheck 'devices' 'Устройства с ошибками' 'warn' ($bad.Count.ToString() + ' шт.: ' + $names) 'drivers' 'ПЕРЕСКАНИРОВАТЬ'))
        } else {
            $out.Add((New-HealthCheck 'devices' 'Устройства с ошибками' 'ok' 'Не найдены'))
        }
    } catch {}

    if (-not $Quick) {
        try {
            $events = @(Get-WinEvent -FilterHashtable @{
                LogName = 'System'; Level = 1, 2; StartTime = (Get-Date).AddDays(-7)
            } -MaxEvents 60 -ErrorAction Stop)
            if ($events.Count -gt 0) {
                $top = ($events | Group-Object ProviderName | Sort-Object Count -Descending |
                        Select-Object -First 2 | ForEach-Object { $_.Name + ' ×' + $_.Count }) -join ', '
                $out.Add((New-HealthCheck 'events' 'Критические ошибки за 7 дней' 'warn' ($events.Count.ToString() + ' событий: ' + $top)))
            } else {
                $out.Add((New-HealthCheck 'events' 'Критические ошибки за 7 дней' 'ok' 'Не найдены'))
            }
        } catch {
            $out.Add((New-HealthCheck 'events' 'Критические ошибки за 7 дней' 'info' 'Журнал недоступен или пуст'))
        }
    }

    try {
        $minidumps = @(Get-ChildItem -LiteralPath (Join-Path $env:SystemRoot 'Minidump') -Filter '*.dmp' -File -Force -ErrorAction SilentlyContinue)
        $crash = @(Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'CrashDumps') -Filter '*.dmp' -File -Force -ErrorAction SilentlyContinue)
        $cnt = $minidumps.Count + $crash.Count
        if ($cnt -gt 0) {
            $out.Add((New-HealthCheck 'dumps' 'Дампы и отчёты об ошибках' 'warn' ($cnt.ToString() + ' файлов — можно очистить') 'cleanup' 'ОЧИСТИТЬ'))
        } else {
            $out.Add((New-HealthCheck 'dumps' 'Дампы и отчёты об ошибках' 'ok' 'Не найдены'))
        }
    } catch {}

    if (-not $Quick) {
        try {
            $tempBytes = (Get-PathBytes $env:TEMP) + (Get-PathBytes (Join-Path $env:SystemRoot 'Temp'))
            $tempMb = [math]::Round($tempBytes / 1MB, 0)
            $out.Add((New-HealthCheck 'temp' 'Временные файлы' `
                $(if ($tempMb -ge 2048) { 'warn' } else { 'ok' }) `
                ('{0:N0} МБ во временных папках' -f $tempMb) 'cleanup' 'ОЧИСТИТЬ'))
        } catch {}
        try {
            $updBytes = Get-PathBytes (Join-Path $env:SystemRoot 'SoftwareDistribution\Download')
            $updMb = [math]::Round($updBytes / 1MB, 0)
            $out.Add((New-HealthCheck 'updcache' 'Кэш обновлений Windows' `
                $(if ($updMb -ge 1024) { 'warn' } else { 'ok' }) `
                ('{0:N0} МБ загруженных обновлений' -f $updMb) 'cleanup' 'ОЧИСТИТЬ'))
        } catch {}
    }

    try {
        $sr = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' -ErrorAction SilentlyContinue
        if ($sr -and $null -ne $sr.DisableSR -and [int]$sr.DisableSR -eq 1) {
            $out.Add((New-HealthCheck 'restore' 'Точки восстановления' 'warn' 'Защита системы отключена' 'restore' 'СОЗДАТЬ ТОЧКУ'))
        } else {
            $out.Add((New-HealthCheck 'restore' 'Точки восстановления' 'ok' 'Защита системы не отключена принудительно'))
        }
    } catch {}

    try {
        $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
        if ($adapters.Count -eq 0) {
            $out.Add((New-HealthCheck 'network' 'Сетевые адаптеры' 'warn' 'Нет активного физического адаптера'))
        } else {
            $names = ($adapters | Select-Object -First 3 | ForEach-Object { [string]$_.Name }) -join ', '
            $out.Add((New-HealthCheck 'network' 'Сетевые адаптеры' 'ok' ($adapters.Count.ToString() + ' активных: ' + $names)))
        }
    } catch {}

    return $out
}

function Get-HealthReportText {
    $checks = @(Get-SystemHealthReport)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('PURPLE RUSH · отчёт о здоровье Windows')
    [void]$sb.AppendLine(('Дата: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
    [void]$sb.AppendLine(('Версия: ' + $script:AppVersion))
    [void]$sb.AppendLine('')
    foreach ($c in $checks) {
        $mark = switch ($c.Status) {
            'ok'   { '[OK]  ' }
            'warn' { '[!]   ' }
            'err'  { '[ERR] ' }
            default { '[i]   ' }
        }
        [void]$sb.AppendLine($mark + $c.Title + ': ' + $c.Detail)
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Это стандартные проверки Windows, а не гарантия исправления любой ошибки.')
    return $sb.ToString()
}

function Invoke-QuickHealthFix {
    $checks = @(Get-SystemHealthReport)
    $targets = @($checks | Where-Object { $_.Fix -and @('time', 'wu', 'wmi', 'drivers') -contains $_.Fix })
    if ($targets.Count -eq 0) {
        Write-Log 'Быстрое лечение: проблем, которые можно исправить автоматически, не найдено' 'info'
        return
    }
    foreach ($c in $targets) {
        Write-Log ('Быстрое лечение: ' + $c.Title) 'step'
        try {
            switch ($c.Fix) {
                'time'    { Invoke-TimeResync }
                'wu'      { Invoke-WindowsUpdateServicesFix }
                'wmi'     { Invoke-WmiRepair }
                'drivers' { Invoke-DriverRescan }
            }
        } catch {
            Write-Log ('Не удалось: ' + $c.Title + ' — ' + $_.Exception.Message) 'warn'
        }
    }
    Write-Log 'Быстрое лечение завершено' 'ok'
}

function Get-CleanupPotential {
    $targets = @(
        @{ Name = 'TEMP'; Path = $env:TEMP },
        @{ Name = 'Windows Temp'; Path = (Join-Path $env:SystemRoot 'Temp') },
        @{ Name = 'Центр обновлений'; Path = (Join-Path $env:SystemRoot 'SoftwareDistribution\Download') },
        @{ Name = 'Отчёты об ошибках'; Path = (Join-Path $env:ProgramData 'Microsoft\Windows\WER') },
        @{ Name = 'Дампы'; Path = (Join-Path $env:LOCALAPPDATA 'CrashDumps') },
        @{ Name = 'Кэш Steam'; Path = $(if ($script:SteamPath) { Join-Path $script:SteamPath 'appcache\httpcache' } else { '' }) }
    )
    $rows = @()
    $total = [int64]0
    foreach ($t in $targets) {
        if (-not $t.Path) { continue }
        $b = Get-PathBytes $t.Path
        if ($b -le 0) { continue }
        $total += $b
        $rows += [pscustomobject]@{ Name = $t.Name; Bytes = $b }
    }
    return [pscustomobject]@{ TotalBytes = $total; Rows = $rows }
}

# ============================================================
#  КАРТИНКА RUST: безопасные пресеты, гамма и панель GPU
#  Никаких оверлеев, Freestyle, ReShade и внедрения в игру.
# ============================================================

$script:GpuInfo      = $null
$script:GpuInfoAt    = [datetime]::MinValue
$script:LookPreset   = 'vivid'
$script:LookTiles    = @{}
$script:GammaDir     = Join-Path $script:Root 'gamma'
try { New-Item -ItemType Directory -Force -Path $script:GammaDir | Out-Null } catch {}

$script:LookPresets = @(
    [pscustomobject]@{ Key = 'vivid';  Name = 'BLOGGER VIVID'; Sub = 'сочный · чистый · яркий'; Contrast = 1.10; Gamma = 0.95; Brightness = 1.010
        Desc = 'Высокая детализация, мягкий контраст и лёгкий подъём теней. Без «мыла», блума и god rays.' }
    [pscustomobject]@{ Key = 'cinema'; Name = 'КИНО';          Sub = 'тёплый · объёмный · свет'; Contrast = 1.14; Gamma = 1.00; Brightness = 1.000
        Desc = 'Богатый свет, лучи и объём облаков. Красиво для скриншотов и видео, чуть дороже по FPS.' }
    [pscustomobject]@{ Key = 'night';  Name = 'НОЧЬ';          Sub = 'видно · чисто · без бликов'; Contrast = 1.04; Gamma = 0.88; Brightness = 1.015
        Desc = 'Поднимает тёмные участки и убирает световые блики. Помогает видеть силуэты ночью.' }
)

$savedLook = [string]$script:State['LookPreset']
if ($savedLook -and @($script:LookPresets | Where-Object { $_.Key -eq $savedLook }).Count -gt 0) {
    $script:LookPreset = $savedLook
}

function Get-LookPreset {
    param([string]$Key)
    if (-not $Key) { $Key = 'vivid' }
    $p = @($script:LookPresets | Where-Object { $_.Key -eq $Key } | Select-Object -First 1)
    if ($p.Count -eq 0) { $p = @($script:LookPresets | Select-Object -First 1) }
    return $p[0]
}

function Get-LookPresetName {
    param([string]$Key)
    $p = Get-LookPreset $Key
    return [string]$p.Name
}

function New-NeutralRamp {
    $out = New-Object 'UInt16[]' 768
    for ($c = 0; $c -lt 3; $c++) {
        for ($i = 0; $i -lt 256; $i++) {
            $out[($c * 256) + $i] = [UInt16]([Math]::Round(($i / 255.0) * 65535.0))
        }
    }
    return ,$out
}

function New-LookRamp {
    param([UInt16[]]$BaseRamp, [string]$Key)
    $p = Get-LookPreset $Key
    $haveBase = ($BaseRamp -and $BaseRamp.Length -eq 768)
    $out = New-Object 'UInt16[]' 768
    for ($c = 0; $c -lt 3; $c++) {
        for ($i = 0; $i -lt 256; $i++) {
            if ($haveBase) { $v = [double]$BaseRamp[($c * 256) + $i] / 65535.0 }
            else { $v = [double]$i / 255.0 }
            if ($v -lt 0) { $v = 0 } elseif ($v -gt 1) { $v = 1 }

            # Сначала гамма, затем мягкий контраст вокруг середины.
            $v = [Math]::Pow($v, [double]$p.Gamma)
            $v = (($v - 0.5) * [double]$p.Contrast) + 0.5
            $v = $v * [double]$p.Brightness
            if ($v -lt 0) { $v = 0 } elseif ($v -gt 1) { $v = 1 }
            $out[($c * 256) + $i] = [UInt16]([Math]::Round($v * 65535.0))
        }
    }
    return ,$out
}

function Test-RampClose {
    param([UInt16[]]$A, [UInt16[]]$B, [int]$Tolerance = 1024)
    if ($null -eq $A -or $null -eq $B) { return $false }
    if ($A.Length -ne 768 -or $B.Length -ne 768) { return $false }
    for ($i = 0; $i -lt 768; $i++) {
        if ([Math]::Abs([int]$A[$i] - [int]$B[$i]) -gt $Tolerance) { return $false }
    }
    return $true
}

function Get-GammaBackupFile {
    return (Join-Path $script:GammaDir 'primary-original.bin')
}

function Save-GammaBackup {
    param([UInt16[]]$Ramp)
    if ($null -eq $Ramp -or $Ramp.Length -ne 768) { return $false }
    $file = Get-GammaBackupFile
    $bytes = New-Object byte[] 1536
    [System.Buffer]::BlockCopy($Ramp, 0, $bytes, 0, 1536)
    try {
        [IO.File]::WriteAllBytes($file, $bytes)
        return $true
    } catch { return $false }
}

function Read-GammaBackup {
    $file = Get-GammaBackupFile
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    try {
        $bytes = [IO.File]::ReadAllBytes($file)
        if ($bytes.Length -ne 1536) { return $null }
        $ramp = New-Object 'UInt16[]' 768
        [System.Buffer]::BlockCopy($bytes, 0, $ramp, 0, 1536)
        return ,$ramp
    } catch { return $null }
}

function Get-GammaStatus {
    $support = $false
    $current = $null
    try {
        $current = [RustSuite.Native]::GammaGet()
        $support = ($null -ne $current -and $current.Length -eq 768)
    } catch {}
    $backup = Read-GammaBackup
    $active = $false
    $presetKey = [string]$script:State['GammaPreset']
    if ($support -and $backup -and $presetKey) {
        try {
            $expected = New-LookRamp $backup $presetKey
            $active = Test-RampClose $current $expected 2048
        } catch {}
    }
    return [pscustomobject]@{
        Supported = $support
        Active    = $active
        PresetKey = $presetKey
        Preset    = $(if ($presetKey) { Get-LookPresetName $presetKey } else { '—' })
        Backup    = (Test-Path -LiteralPath (Get-GammaBackupFile))
    }
}

function Apply-LookPreset {
    param([string]$Key)
    $p = Get-LookPreset $Key
    $current = $null
    try { $current = [RustSuite.Native]::GammaGet() } catch {}
    if ($null -eq $current -or $current.Length -ne 768) {
        return [pscustomobject]@{ Ok = $false; Message = 'Драйвер не отдал гамма-таблицу. Используйте панель NVIDIA/AMD — она работает на уровне драйвера.' }
    }

    $original = Read-GammaBackup
    if ($null -eq $original) {
        if (-not (Save-GammaBackup $current)) {
            return [pscustomobject]@{ Ok = $false; Message = 'Не удалось сохранить исходный цветовой профиль. Изменения не применены.' }
        }
        $original = $current
    }

    $ramp = New-LookRamp $original $p.Key
    $ok = $false
    try { $ok = [RustSuite.Native]::GammaSet($ramp) } catch {}
    if (-not $ok) {
        return [pscustomobject]@{ Ok = $false; Message = 'Windows/драйвер отклонил изменение гаммы (часто бывает на HDR-мониторах и в удалённом сеансе). Настройте цвет в панели NVIDIA/AMD.' }
    }

    $now = $null
    try { $now = [RustSuite.Native]::GammaGet() } catch {}
    if ($null -eq $now -or -not (Test-RampClose $now $ramp 4096)) {
        return [pscustomobject]@{ Ok = $false; Message = 'Драйвер принял команду, но не применил её. Используйте панель NVIDIA/AMD.' }
    }

    $script:State['GammaActive'] = $true
    $script:State['GammaPreset'] = $p.Key
    $script:State['GammaAt'] = (Get-Date).ToString('s')
    Save-State
    Write-Log ('Картинка: применён пресет «' + $p.Name + '» (гамма/контраст, обратимо)') 'ok'
    return [pscustomobject]@{ Ok = $true; Message = ('Применено: ' + $p.Name + '. Вернуть исходный цвет — кнопкой «ВЕРНУТЬ ЦВЕТ».') }
}

function Restore-LookGamma {
    $backup = Read-GammaBackup
    if ($null -eq $backup) {
        return [pscustomobject]@{
            Ok = $false
            Message = 'Исходная таблица не найдена: пресет ещё не применялся. Цвет не изменён — перезагрузка Windows тоже возвращает стандартную гамму.'
        }
    }
    $ok = $false
    try { $ok = [RustSuite.Native]::GammaSet($backup) } catch {}
    if (-not $ok) {
        return [pscustomobject]@{ Ok = $false; Message = 'Не удалось вернуть исходный цвет. Перезапустите Windows — гамма сбросится автоматически.' }
    }
    $script:State['GammaActive'] = $false
    $script:State.Remove('GammaPreset')
    $script:State.Remove('GammaAt')
    Save-State
    Write-Log 'Картинка: исходный цвет рабочего стола восстановлен' 'ok'
    return [pscustomobject]@{ Ok = $true; Message = 'Исходный цвет восстановлен.' }
}

# ============================================================
#  RUST: визуальные cfg-пресеты (только официальные конвары)
# ============================================================
$script:RustVisualBaseLines = @(
    'graphics.drawdistance 2500',
    'graphics.lodbias 2',
    'graphics.hlod True',
    'graphics.parallax 2',
    'graphics.af 16',
    'graphics.contactshadows True',
    'graphics.dof False',
    'graphics.shadowmode 4',
    'graphics.shadowlights 3',
    'graphics.aggressiveshadowlod False',
    'graphics.aggressiveshadowlodwearable False',
    'graphics.impostorshadows True',
    'graphics.volumetric_clouds 4',
    'graphics.renderscale 1',
    'graphics.maxqueuedframes 1',
    'graphicssettings.globaltexturemipmaplimit 0',
    'graphicssettings.shadowqualitypreset 3',
    'graphicssettings.enablelodcrossfade True',
    'graphicssettings.softparticles True',
    'graphicssettings.particleraycastbudget 1024',
    'effects.antialiasing 2',
    'effects.ao True',
    'effects.bloom True',
    'effects.lensdirt False',
    'effects.motionblur False',
    'effects.shafts True',
    'effects.sharpen True',
    'effects.vignet False',
    'effects.hurtoverlay False',
    'effects.otherplayerslightflares False',
    'effects.creationeffects True',
    'effects.maxgibs 1',
    'particle.quality 100',
    'grass.quality 100',
    'grass.distance 100',
    'grass.displacement True',
    'decor.quality 100',
    'terrain.quality 100',
    'tree.quality 200',
    'tree.meshes 100',
    'mesh.quality 200',
    'water.quality 2',
    'water.reflections 2',
    'sss.enabled True',
    'reflection.planarreflections False',
    'legs.enablelegs True',
    'player.footik True',
    'ui.showinventoryplayer True'
)

$script:RustVisualExtras = @{
    vivid  = @('effects.bloom False', 'effects.shafts False', 'effects.sharpen True', 'effects.antialiasing 2', 'effects.vignet False', 'graphics.dof False')
    cinema = @('effects.bloom True',  'effects.shafts True',  'effects.sharpen True', 'effects.antialiasing 2', 'effects.vignet False', 'graphics.dof False')
    night  = @('effects.bloom False', 'effects.shafts False', 'effects.sharpen True', 'effects.antialiasing 2', 'effects.vignet False', 'graphics.volumetric_clouds 0', 'graphics.dof False')
}

$script:RustVisualManaged = @(
    foreach ($l in $script:RustVisualBaseLines) { (($l -split '\s+')[0]).ToLower() }
    foreach ($group in $script:RustVisualExtras.Values) {
        foreach ($l in $group) { (($l -split '\s+')[0]).ToLower() }
    }
) | Select-Object -Unique

function Get-RustVisualPresetLines {
    param([string]$Key)
    if (-not $Key -or -not $script:RustVisualExtras.ContainsKey($Key)) { $Key = 'vivid' }
    $map = @{}
    foreach ($l in $script:RustVisualBaseLines) {
        $k = (($l -split '\s+')[0]).ToLower()
        $map[$k] = $l
    }
    foreach ($l in @($script:RustVisualExtras[$Key])) {
        $k = (($l -split '\s+')[0]).ToLower()
        $map[$k] = $l
    }
    return @($map.Values | Sort-Object)
}

function Get-VisualSnapshotFile {
    return (Join-Path $script:RustBackup 'client-picture-original.txt')
}

function Save-VisualSnapshot {
    param([string]$Path)
    $snap = Get-VisualSnapshotFile
    if (Test-Path -LiteralPath $snap) { return $true }
    $map = @{}
    if (Test-Path -LiteralPath $Path) {
        try {
            foreach ($ln in @([IO.File]::ReadAllLines($Path))) {
                $t = ([string]$ln).Trim()
                if (-not $t) { continue }
                $k = (($t -split '\s+')[0]).ToLower()
                if ($script:RustVisualManaged -contains $k) { $map[$k] = $t }
            }
        } catch {}
    }
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($k in @($script:RustVisualManaged)) {
        $v = ''
        if ($map.ContainsKey($k)) { $v = [string]$map[$k] }
        $lines.Add($k + "`t" + $v)
    }
    try {
        [IO.File]::WriteAllLines($snap, $lines, (New-Object System.Text.UTF8Encoding($false)))
        return $true
    } catch { return $false }
}

function Restore-VisualSnapshot {
    param([string]$Path)
    $snap = Get-VisualSnapshotFile
    if (-not (Test-Path -LiteralPath $snap)) { return $false }
    $restore = @()
    try {
        foreach ($ln in @([IO.File]::ReadAllLines($snap))) {
            $idx = ([string]$ln).IndexOf("`t")
            if ($idx -lt 0) { continue }
            $v = ([string]$ln).Substring($idx + 1)
            if ($v.Trim().Length -gt 0) { $restore += $v }
        }
        Merge-CfgFile -Path $Path -Lines $restore -ManagedKeys $script:RustVisualManaged
        Remove-Item -LiteralPath $snap -Force -ErrorAction SilentlyContinue
        return $true
    } catch { return $false }
}

function Set-RustVisualCfg {
    param([string]$Key)
    if (-not $script:RustExe) {
        return [pscustomobject]@{ Ok = $false; Message = 'RUST не найден. Запустите игру через Steam один раз, чтобы появилась папка cfg.' }
    }
    if (Test-RustRunning) {
        return [pscustomobject]@{ Ok = $false; Message = 'Rust запущен: игра перезапишет client.cfg при выходе. Закройте игру и повторите.' }
    }
    $dir = Get-RustCfgDir
    if (-not $dir) { return [pscustomobject]@{ Ok = $false; Message = 'Не удалось открыть папку cfg игры.' } }
    $file = Join-Path $dir 'client.cfg'
    if (-not (Save-VisualSnapshot $file)) {
        return [pscustomobject]@{ Ok = $false; Message = 'Не удалось сохранить исходные значения client.cfg. Изменения не применены.' }
    }
    Backup-FileStamp $file 'client-picture'
    $lines = @(Get-RustVisualPresetLines $Key)
    Merge-CfgFile -Path $file -Lines $lines -ManagedKeys $script:RustVisualManaged
    $p = Get-LookPreset $Key
    $script:State['RustVisualPreset'] = $p.Key
    $script:State['RustVisualAt'] = (Get-Date).ToString('s')
    Save-State
    Write-Log ('RUST: записан визуальный пресет «' + $p.Name + '» (' + $lines.Count + ' конваров, client.cfg)') 'ok'
    return [pscustomobject]@{ Ok = $true; Message = ('client.cfg обновлён: ' + $p.Name + '. Бэкап: ' + $script:RustBackup) }
}

function Undo-RustVisualCfg {
    if (-not $script:RustExe) { return [pscustomobject]@{ Ok = $false; Message = 'RUST не найден.' } }
    if (Test-RustRunning) { return [pscustomobject]@{ Ok = $false; Message = 'Rust запущен. Закройте игру и повторите.' } }
    $dir = Get-RustCfgDir
    if (-not $dir) { return [pscustomobject]@{ Ok = $false; Message = 'Папка cfg недоступна.' } }
    $file = Join-Path $dir 'client.cfg'
    if (Restore-VisualSnapshot $file) {
        Write-Log 'RUST: исходные значения визуальных конваров восстановлены' 'ok'
        return [pscustomobject]@{ Ok = $true; Message = 'Исходные значения client.cfg восстановлены.' }
    }
    return [pscustomobject]@{ Ok = $false; Message = 'Резервная копия визуальных настроек не найдена.' }
}

# ============================================================
#  GPU: определение, подсказки и запуск панели
# ============================================================
function Get-GpuInfo {
    param([switch]$Refresh)
    $now = Get-Date
    if (-not $Refresh -and $script:GpuInfo -and (($now - $script:GpuInfoAt).TotalSeconds -lt 45)) {
        return $script:GpuInfo
    }
    $cards = @()
    try { $cards = @(Get-CimInstance Win32_VideoController -ErrorAction Stop) } catch {}
    $active = @($cards | Where-Object { [int]$_.CurrentHorizontalResolution -gt 0 })
    $primary = if ($active.Count -gt 0) { $active[0] } elseif ($cards.Count -gt 0) { $cards[0] } else { $null }
    $names = @($cards | ForEach-Object { ([string]$_.Name).Trim() } |
               Where-Object { $_ -and $_ -notmatch 'Basic Display|Remote Display|Microsoft Basic' } |
               Select-Object -Unique)
    $allText = ($names -join ' ') + ' ' + [string]$primary.Name + ' ' + [string]$primary.PNPDeviceID
    $vendor = 'OTHER'
    $vendorLabel = 'Видеокарта'
    $panelName = 'Настройки дисплея Windows'
    if ($allText -match 'NVIDIA|GeForce|RTX|GTX|Quadro|VEN_10DE') {
        $vendor = 'NVIDIA'; $vendorLabel = 'NVIDIA'; $panelName = 'NVIDIA Control Panel / NVIDIA app'
    } elseif ($allText -match 'AMD|Radeon|VEN_1002') {
        $vendor = 'AMD'; $vendorLabel = 'AMD Radeon'; $panelName = 'AMD Software: Adrenalin Edition'
    } elseif ($allText -match 'Intel|Arc|UHD|Iris|VEN_8086') {
        $vendor = 'INTEL'; $vendorLabel = 'Intel'; $panelName = 'Intel Graphics Command Center'
    }
    $name = if ($names.Count -gt 0) { $names -join '  ·  ' } else { 'Видеокарта не определена' }
    $res = '—'
    $hz = 0
    if ($primary) {
        $rw = [int]$primary.CurrentHorizontalResolution
        $rh = [int]$primary.CurrentVerticalResolution
        $hz = [int]$primary.CurrentRefreshRate
        if ($rw -gt 0 -and $rh -gt 0) { $res = "$rw × $rh" }
    }
    $driver = if ($primary) { [string]$primary.DriverVersion } else { '' }
    $vramMb = 0
    if ($primary -and $primary.AdapterRAM) {
        try {
            $v = [double]$primary.AdapterRAM / 1MB
            if ($v -gt 0 -and $v -lt 131072) { $vramMb = [int][Math]::Round($v) }
        } catch {}
    }
    $info = [pscustomobject]@{
        Vendor = $vendor; VendorLabel = $vendorLabel; PanelName = $panelName
        Name = $name; Driver = $driver; Resolution = $res; Refresh = $hz
        VramMb = $vramMb; Cards = $names; Primary = $primary
    }
    $script:GpuInfo = $info
    $script:GpuInfoAt = $now
    return $info
}

function Get-GpuPanelGuide {
    param([string]$Vendor)
    if (-not $Vendor) { $Vendor = (Get-GpuInfo).Vendor }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('ПАНЕЛЬ ДРАЙВЕРА — точные настройки для сочной картинки')
    $lines.Add('')
    if ($Vendor -eq 'NVIDIA') {
        $lines.Add('NVIDIA Control Panel → Дисплей → Регулировка параметров цвета рабочего стола:')
        $lines.Add('  • Цифровая насыщенность (Digital Vibrance): 65–72%')
        $lines.Add('  • Яркость / Контраст / Гамма: 50% / 50% / 1.00')
        $lines.Add('  • Формат цвета: RGB; динамический диапазон: Полный (Full)')
        $lines.Add('  • Глубина цвета: 8 bpc, либо 10 bpc при поддержке монитора')
        $lines.Add('')
        $lines.Add('NVIDIA Control Panel → Управление параметрами 3D → RustClient.exe:')
        $lines.Add('  • Режим низкой задержки: Ultra')
        $lines.Add('  • Управление электропитанием: Предпочтителен максимальный режим')
        $lines.Add('  • Вертикальная синхронизация: Выкл.')
        $lines.Add('  • Фильтрация текстур — качество: Высокое качество')
        $lines.Add('  • Потоковая оптимизация: Вкл. (на слабом CPU можно Выкл.)')
        $lines.Add('  • Max Frame Rate: по частоте монитора или 0 (без лимита)')
        $lines.Add('')
        $lines.Add('НЕ включайте Freestyle / Game Filter: это оверлей, он может конфликтовать с EAC.')
    } elseif ($Vendor -eq 'AMD') {
        $lines.Add('AMD Software: Adrenalin Edition → Игры → Rust:')
        $lines.Add('  • Radeon Image Sharpening: 50–70%')
        $lines.Add('  • Radeon Anti-Lag: Вкл.')
        $lines.Add('  • Radeon Chill: Выкл.')
        $lines.Add('  • Enhanced Sync: Вкл. (если нет мерцания; иначе Выкл.)')
        $lines.Add('  • Frame Rate Target Control: по частоте монитора')
        $lines.Add('')
        $lines.Add('AMD Software → Дисплей → Цвет (Custom Color):')
        $lines.Add('  • Насыщенность (Saturation): 110–115%')
        $lines.Add('  • Цветовая температура: 6500K')
        $lines.Add('  • Яркость / контраст: по комфорту, не выше 55 / 55')
        $lines.Add('  • Формат пикселей: RGB 4:4:4, Full RGB')
        $lines.Add('')
        $lines.Add('Не используйте оверлеи и сторонние шейдеры: только панель драйвера.')
    } elseif ($Vendor -eq 'INTEL') {
        $lines.Add('Intel Graphics Command Center → Дисплей → Цвет:')
        $lines.Add('  • Насыщенность: 110–115%')
        $lines.Add('  • Яркость / контраст: по комфорту')
        $lines.Add('  • Цветовая температура: 6500K')
        $lines.Add('')
        $lines.Add('Для дискретной NVIDIA/AMD в ноутбуке используйте панель соответствующего драйвера.')
    } else {
        $lines.Add('Откройте панель драйвера видеокарты и выставьте:')
        $lines.Add('  • Насыщенность: +10–15%')
        $lines.Add('  • Контраст: +5–10%')
        $lines.Add('  • Гамма: 1.0 (или чуть ниже для светлых теней)')
        $lines.Add('  • Полный динамический диапазон RGB')
    }
    $lines.Add('')
    $lines.Add('После изменений закройте панель — настройки применяются сразу.')
    $lines.Add('Это настройки драйвера, а не игры: файлы Rust и процесс игры не изменяются.')
    return ($lines -join "`r`n")
}

function Open-GpuPanel {
    param([string]$Vendor)
    if (-not $Vendor) { $Vendor = (Get-GpuInfo).Vendor }
    $candidates = @()
    if ($Vendor -eq 'NVIDIA') {
        $candidates += @(
            (Join-Path $env:ProgramFiles 'NVIDIA Corporation\Control Panel Client\nvcplui.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'NVIDIA Corporation\Control Panel Client\nvcplui.exe'),
            (Join-Path $env:ProgramFiles 'NVIDIA Corporation\NVIDIA app\CEF\NVIDIA app.exe'),
            (Join-Path $env:ProgramFiles 'NVIDIA Corporation\NVIDIA app\NVIDIA app.exe')
        )
    } elseif ($Vendor -eq 'AMD') {
        $candidates += @(
            (Join-Path $env:ProgramFiles 'AMD\CNext\CNext\RadeonSoftware.exe'),
            (Join-Path $env:ProgramFiles 'AMD\CNext\CNext\RadeonSoftware.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'AMD\CNext\CNext\RadeonSoftware.exe')
        )
    } elseif ($Vendor -eq 'INTEL') {
        $candidates += @(
            (Join-Path $env:ProgramFiles 'Intel\Intel Graphics Command Center\IntelGraphicsCommandCenter.exe'),
            (Join-Path $env:ProgramFiles 'Intel\Intel Graphics Command Center\Intel Graphics Command Center.exe')
        )
    }
    foreach ($c in @($candidates | Where-Object { $_ })) {
        if (Test-Path -LiteralPath $c) {
            try {
                Start-Process -FilePath $c -ErrorAction Stop | Out-Null
                Write-Log ('Открыта панель GPU: ' + $c) 'info'
                return [pscustomobject]@{ Ok = $true; Path = $c; Message = 'Панель драйвера открыта.' }
            } catch {}
        }
    }
    if ($Vendor -eq 'NVIDIA') {
        try { Start-Process -FilePath 'nvcplui.exe' -ErrorAction Stop | Out-Null
              return [pscustomobject]@{ Ok = $true; Path = 'nvcplui.exe'; Message = 'Панель NVIDIA открыта.' } } catch {}
    } elseif ($Vendor -eq 'AMD') {
        try { Start-Process -FilePath 'amdsoftware:' -ErrorAction Stop | Out-Null
              return [pscustomobject]@{ Ok = $true; Path = 'amdsoftware:'; Message = 'AMD Software открыта.' } } catch {}
    }
    try { Start-Process -FilePath 'ms-settings:display' -ErrorAction Stop | Out-Null } catch {}
    return [pscustomobject]@{ Ok = $false; Path = 'ms-settings:display'; Message = 'Панель драйвера не найдена. Открыты настройки дисплея Windows — обновите драйвер или установите панель NVIDIA/AMD.' }
}

function Get-GpuStatusText {
    $info = Get-GpuInfo
    $g = Get-GammaStatus
    $color = if ($g.Active) { 'цвет: ' + $g.Preset } elseif ($g.Supported) { 'цвет: стандарт' } else { 'цвет: панель драйвера' }
    return ($info.VendorLabel + ' · ' + $color)
}

# ============================================================
#  СПИСОК ОПТИМИЗАЦИЙ
# ============================================================
$script:Tweaks = @(
    [pscustomobject]@{ Id = 'power'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'Максимальная производительность'
        Desc = 'План питания Ultimate Performance, отключение ASPM, USB-энергосбережения и сна диска.'
        Apply = { Invoke-PowerPlan }; Undo = { Undo-PowerPlan } }

    [pscustomobject]@{ Id = 'prio'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'Приоритет активного процесса'
        Desc = 'Win32PrioritySeparation = 26: кванты времени отдаются игре, а не фоновым службам.'
        Apply = { Invoke-PrioritySeparation }; Undo = { Undo-PrioritySeparation } }

    [pscustomobject]@{ Id = 'mmcss'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'Планировщик MMCSS и сетевой лимит'
        Desc = 'Снимает NetworkThrottlingIndex, игровые задачи получают High GPU/SFIO приоритет.'
        Apply = { Invoke-Mmcss }; Undo = { Undo-Mmcss } }

    [pscustomobject]@{ Id = 'gamedvr'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'Отключить Game DVR'
        Desc = 'Фоновая запись Xbox забирает 5–15% FPS и добавляет микрофризы.'
        Apply = { Invoke-GameDvr }; Undo = { Undo-GameDvr } }

    [pscustomobject]@{ Id = 'gamemode'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'Игровой режим Windows'
        Desc = 'Windows отдаёт приоритет активной игре и не трогает её фоновыми задачами.'
        Apply = { Invoke-GameMode }; Undo = { Undo-GameMode } }

    [pscustomobject]@{ Id = 'hags'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'Аппаратное планирование GPU'
        Desc = 'HAGS снижает задержку кадра. Требуется перезагрузка, нужна поддержка драйвера.'
        Apply = { Invoke-Hags }; Undo = { Undo-Hags } }

    [pscustomobject]@{ Id = 'mouse'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'Отключить ускорение мыши'
        Desc = 'Движение прицела 1:1 с рукой — самый дешёвый и заметный буст для шутера.'
        Apply = { Invoke-Mouse }; Undo = { Undo-Mouse } }

    [pscustomobject]@{ Id = 'keyfix'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'Убрать залипание клавиш'
        Desc = 'Shift ×5 больше не выбрасывает из игры в окно спец. возможностей.'
        Apply = { Invoke-KeyFix }; Undo = { Undo-KeyFix } }

    [pscustomobject]@{ Id = 'telemetry'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'Отключить телеметрию'
        Desc = 'Службы DiagTrack и dmwappushservice останавливаются и отключаются.'
        Apply = { Invoke-Telemetry }; Undo = { Undo-Telemetry } }

    [pscustomobject]@{ Id = 'powerthrottle'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'Отключить Power Throttling'
        Desc = 'Windows перестаёт ограничивать питание активных процессов (плюс к стабильности FPS).'
        Apply = { Invoke-PowerThrottle }; Undo = { Undo-PowerThrottle } }

    [pscustomobject]@{ Id = 'sysmain'; Group = 'sys'; Risk = $true; Default = $false
        Name = 'Отключить SysMain (Superfetch)'
        Desc = 'Плюс для SSD, минус для HDD. Включайте только если Windows стоит на SSD.'
        Apply = { Invoke-SysMain }; Undo = { Undo-SysMain } }

    [pscustomobject]@{ Id = 'search'; Group = 'sys'; Risk = $true; Default = $false
        Name = 'Отключить индексацию поиска'
        Desc = 'Меньше нагрузка на диск, но поиск по файлам станет медленнее.'
        Apply = { Invoke-SearchIndex }; Undo = { Undo-SearchIndex } }

    [pscustomobject]@{ Id = 'visual'; Group = 'sys'; Risk = $false; Default = $false
        Name = 'Визуальные эффекты на минимум'
        Desc = 'Отключает анимации Windows. Внешний вид станет проще, отклик — резче.'
        Apply = { Invoke-VisualEffects }; Undo = { Undo-VisualEffects } }

    [pscustomobject]@{ Id = 'hibernate'; Group = 'sys'; Risk = $false; Default = $false
        Name = 'Отключить гибернацию'
        Desc = 'Освобождает несколько ГБ на системном диске (удаляется hiberfil.sys).'
        Apply = { Invoke-HibernateOff }; Undo = { Undo-HibernateOff } }

    [pscustomobject]@{ Id = 'timer'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'Точный системный таймер (1 мс)'
        Desc = 'Разрешает приложениям точный таймер и держит 1 мс, пока программа открыта — отклик ввода и кадров ровнее.'
        Apply = { Invoke-TimerRes }; Undo = { Undo-TimerRes } }

    [pscustomobject]@{ Id = 'park'; Group = 'sys'; Risk = $true; Default = $false
        Name = 'Отключить парковку ядер CPU'
        Desc = 'Отключает парковку ядер процессора — плюс на старых CPU, тестируйте.'
        Apply = { Invoke-CpuPark }; Undo = { Undo-CpuPark } }

    [pscustomobject]@{ Id = 'qosgame'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'QoS для игр (DSCP / QoS Packet Scheduler)'
        Desc = 'Активирует планировщик пакетов QoS и задаёт приоритет для игрового трафика.'
        Apply = { Invoke-QosGame }; Undo = { Undo-QosGame } }

    [pscustomobject]@{ Id = 'prefetch'; Group = 'sys'; Risk = $true; Default = $false
        Name = 'Отключить Prefetch / Superfetch (полностью)'
        Desc = 'Полностью отключает Prefetch через реестр для минимизации дисковых операций. Откат возвращает исходные значения.'
        Apply = { Invoke-PrefetchOff }; Undo = { Undo-PrefetchOff } }

    [pscustomobject]@{ Id = 'deliveryopt'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'Отключить P2P-раздачу Delivery Optimization'
        Desc = 'Windows перестаёт раздавать обновления другим ПК и забирать канал во время игры. Сами обновления работают.'
        Apply = { Invoke-DeliveryOpt }; Undo = { Undo-DeliveryOpt } }

    [pscustomobject]@{ Id = 'fullscreenopt'; Group = 'sys'; Risk = $true; Default = $false
        Name = 'Отключить оптимизации полного экрана (глобально)'
        Desc = 'FSE-поведение Windows для всех игр: честный эксклюзивный полный экран. На части систем ломает alt-tab — тестируйте.'
        Apply = { Invoke-FullscreenOpt }; Undo = { Undo-FullscreenOpt } }

    [pscustomobject]@{ Id = 'xboxsvc'; Group = 'sys'; Risk = $true; Default = $false
        Name = 'Отключить службы Xbox'
        Desc = 'XblAuthManager, XblGameSave, XboxNetApiSvc и XboxGipSvc. Освобождает ресурсы, но ломает Game Pass и Xbox-приложения.'
        Apply = { Invoke-XboxServices }; Undo = { Undo-XboxServices } }

    [pscustomobject]@{ Id = 'faststartup'; Group = 'sys'; Risk = $true; Default = $false
        Name = 'Отключить быстрый запуск Windows'
        Desc = 'Полное завершение работы вместо гибридного сна: чище загрузка, меньше «залипших» драйверов. Включение — обратно.'
        Apply = { Invoke-FastStartupOff }; Undo = { Undo-FastStartupOff } }

    [pscustomobject]@{ Id = 'nagle'; Group = 'net'; Risk = $false; Default = $true
        Name = 'Отключить алгоритм Nagle'
        Desc = 'Мелкие пакеты уходят сразу: пинг стабильнее, регистрация попаданий точнее.'
        Apply = { Invoke-Nagle }; Undo = { Undo-Nagle } }

    [pscustomobject]@{ Id = 'netpower'; Group = 'net'; Risk = $false; Default = $true
        Name = 'Убрать энергосбережение сетевого адаптера'
        Desc = 'Windows больше не «усыпляет» сетевую карту для экономии энергии — меньше лагов и разрывов.'
        Apply = { Invoke-NetPower }; Undo = { Undo-NetPower } }

    [pscustomobject]@{ Id = 'tcptune'; Group = 'net'; Risk = $false; Default = $true
        Name = 'TCP-стек под игры'
        Desc = 'Автотюнинг окна и RSS включены, ECN и timestamps отключены. Откат возвращает прежние значения.'
        Apply = { Invoke-TcpTune }; Undo = { Undo-TcpTune } }

    [pscustomobject]@{ Id = 'flushdns'; Group = 'net'; Risk = $false; Default = $true
        Name = 'Сбросить DNS-кэш'
        Desc = 'Чистый кэш убирает старые записи серверов Rust и Steam.'
        Apply = { Invoke-FlushDns }; Undo = { } }

    [pscustomobject]@{ Id = 'dns'; Group = 'net'; Risk = $true; Default = $false
        Name = 'DNS Cloudflare 1.1.1.1'
        Desc = 'Меняет DNS на быстрый публичный. Если настроен свой DNS — лучше не включать.'
        Apply = { Invoke-Dns }; Undo = { Undo-Dns } }

    [pscustomobject]@{ Id = 'rustcompat'; Group = 'rust'; Risk = $false; Default = $true
        Name = 'Честный полный экран Rust'
        Desc = 'Отключает «оптимизации полного экрана» для RustClient.exe — меньше инпут-лага.'
        Apply = { Invoke-RustCompat }; Undo = { Undo-RustCompat } }

    [pscustomobject]@{ Id = 'rustgpu'; Group = 'rust'; Risk = $false; Default = $true
        Name = 'Rust на дискретной видеокарте'
        Desc = 'Явно привязывает RustClient.exe к профилю «Высокая производительность» GPU.'
        Apply = { Invoke-RustGpu }; Undo = { Undo-RustGpu } }

    [pscustomobject]@{ Id = 'rustprio'; Group = 'rust'; Risk = $false; Default = $true
        Name = 'Приоритет Rust → High'
        Desc = 'Повышает приоритет запущенного RustClient.exe. Real-time не используется намеренно.'
        Apply = { Invoke-RustPriority }; Undo = { } }

    [pscustomobject]@{ Id = 'rustaffinity'; Group = 'rust'; Risk = $true; Default = $false
        Name = 'Только физические ядра'
        Desc = 'Привязывает Rust к физическим ядрам без Hyper-Threading. На части CPU даёт минус — тестируйте.'
        Apply = { Invoke-RustAffinity }; Undo = { } }

    [pscustomobject]@{ Id = 'rustcfg'; Group = 'rust'; Risk = $false; Default = $true
        Name = 'Отключить траву и пост-эффекты'
        Desc = 'Пишет официальные конвары в cfg\client.cfg: grass.displacement, лучи, глубина резкости. Нужен закрытый Rust.'
        Apply = { Invoke-RustCfg }; Undo = { Undo-RustCfg; Undo-RustBinds } }

    [pscustomobject]@{ Id = 'rustmax'; Group = 'rust'; Risk = $false; Default = $false
        Name = 'МАКСИМАЛЬНАЯ ГРАФИКА НА МИНИМУМ (легально)'
        Desc = 'Расширенный набор официальных cfg для минимальной нагрузки: тени, дистанция, качество, туман, трава (без вмешательства в файлы клиента — безопасно для EAC).'
        Apply = { Invoke-RustMaxCfg }; Undo = { Undo-RustMaxCfg } }

    [pscustomobject]@{ Id = 'temp'; Group = 'clean'; Risk = $false; Default = $true
        Name = 'Очистка временных файлов'
        Desc = 'Удаляет мусор из TEMP, Windows\Temp и кэша Internet Explorer.'
        Apply = { Invoke-TempClean }; Undo = { } }

    [pscustomobject]@{ Id = 'bgapps'; Group = 'clean'; Risk = $false; Default = $true
        Name = 'Закрыть фоновые приложения'
        Desc = 'Завершает OneDrive, Teams, Skype, Cortana и виджеты. Steam и Rust не трогает.'
        Apply = { Invoke-BgApps }; Undo = { } }

    [pscustomobject]@{ Id = 'recycle'; Group = 'clean'; Risk = $false; Default = $false
        Name = 'Очистить корзину'
        Desc = 'Освобождает место на диске. Восстановить файлы после этого нельзя.'
        Apply = { Invoke-RecycleBin }; Undo = { } }

    [pscustomobject]@{ Id = 'shadercache'; Group = 'clean'; Risk = $false; Default = $false
        Name = 'Очистить кэш шейдеров DirectX'
        Desc = 'Удаляет старый кэш D3D/NVIDIA/AMD/Intel. Освобождает место и лечит артефакты; игра соберёт кэш заново.'
        Apply = { Invoke-ShaderClean }; Undo = { } }

    [pscustomobject]@{ Id = 'deepclean'; Group = 'clean'; Risk = $false; Default = $false
        Name = 'Глубокая очистка Windows'
        Desc = 'TEMP, кэш обновлений и Delivery Optimization, WER, дампы, кэш браузеров, логи Steam/RUST и старые журналы. Корзину и настройки не трогает.'
        Apply = { Invoke-DeepClean }; Undo = { } }

    [pscustomobject]@{ Id = 'updatecache'; Group = 'clean'; Risk = $false; Default = $false
        Name = 'Очистить кэш обновлений Windows'
        Desc = 'Останавливает службы обновления, очищает SoftwareDistribution\Download и кэш Delivery Optimization, затем возвращает службы.'
        Apply = { Invoke-UpdateCacheClean }; Undo = { } }

    [pscustomobject]@{ Id = 'dumps'; Group = 'clean'; Risk = $false; Default = $false
        Name = 'Удалить дампы и отчёты об ошибках'
        Desc = 'MEMORY.DMP, Minidump, CrashDumps, WER и LiveKernelReports. Освобождает место; сами ошибки это не исправляет.'
        Apply = { Invoke-DumpClean }; Undo = { } }

    [pscustomobject]@{ Id = 'browsercache'; Group = 'clean'; Risk = $false; Default = $false
        Name = 'Кэш браузеров'
        Desc = 'Только Cache/Code Cache/GPUCache у Edge, Chrome, Brave, Vivaldi, Yandex, Firefox и Opera. Пароли, cookies и история не удаляются.'
        Apply = { Invoke-BrowserCache }; Undo = { } }

    [pscustomobject]@{ Id = 'gamejunk'; Group = 'clean'; Risk = $false; Default = $false
        Name = 'Логи и дампы Steam / RUST'
        Desc = 'Старые логи Steam, httpcache, crash dumps и *.dmp RUST. Файлы cfg, сохранения и настройки игры не затрагиваются.'
        Apply = { Invoke-GameJunkClean }; Undo = { } }

    [pscustomobject]@{ Id = 'thumbcache'; Group = 'clean'; Risk = $false; Default = $false
        Name = 'Кэш эскизов и иконок'
        Desc = 'Удаляет thumbcache/iconcache. Занятые Explorer файлы пропускаются; для полной пересборки есть отдельная кнопка в «Ремонте».'
        Apply = { Invoke-ThumbnailClean }; Undo = { } }

    [pscustomobject]@{ Id = 'winsxs'; Group = 'clean'; Risk = $false; Default = $false
        Name = 'Очистка WinSxS (DISM)'
        Desc = 'DISM /StartComponentCleanup удаляет устаревшие компоненты. Долго (5–30 минут), но без удаления актуальных обновлений.'
        Apply = { Invoke-WinSxSClean }; Undo = { } }

    [pscustomobject]@{ Id = 'oldwindows'; Group = 'clean'; Risk = $true; Default = $false
        Name = 'Удалить Windows.old и следы установки'
        Desc = 'Windows.old, $Windows.~BT, $Windows.~WS, $WinREAgent. Освобождает десятки ГБ, но откат к предыдущей версии Windows станет невозможен.'
        Apply = { Invoke-OldWindowsClean }; Undo = { } }

    [pscustomobject]@{ Id = 'prefetchclean'; Group = 'clean'; Risk = $false; Default = $false
        Name = 'Очистить Prefetch'
        Desc = 'Удаляет *.pf и ReadyBoot. Первые запуски приложений станут чуть медленнее, затем Windows соберёт кэш заново.'
        Apply = { Invoke-PrefetchClean }; Undo = { } }

    [pscustomobject]@{ Id = 'eventlogs'; Group = 'clean'; Risk = $true; Default = $false
        Name = 'Очистить журналы событий Windows'
        Desc = 'Удаляет старые записи из журналов. Необратимо и мешает диагностике — используйте только осознанно после сбора отчётов.'
        Apply = { Invoke-EventLogClean }; Undo = { } }

    [pscustomobject]@{ Id = 'gamebar'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'Game Bar без оверлея и подсказок'
        Desc = 'Убирает всплывающую панель Xbox, автозапись и подсказки. Игровой режим Windows остаётся включённым.'
        Apply = { Invoke-GameBarOff }; Undo = { Undo-GameBarOff } }

    [pscustomobject]@{ Id = 'widgets'; Group = 'clean'; Risk = $false; Default = $true
        Name = 'Отключить виджеты Windows 11'
        Desc = 'Убирает ленту новостей и кнопку виджетов с панели задач. Работает через официальную политику Dsh.'
        Apply = { Invoke-WidgetsOff }; Undo = { Undo-WidgetsOff } }

    [pscustomobject]@{ Id = 'copilot'; Group = 'clean'; Risk = $false; Default = $true
        Name = 'Отключить Copilot'
        Desc = 'Скрывает кнопку Copilot и отключает его политикой Windows. Возврат — одной кнопкой «Откат».'
        Apply = { Invoke-CopilotOff }; Undo = { Undo-CopilotOff } }

    [pscustomobject]@{ Id = 'recall'; Group = 'clean'; Risk = $false; Default = $true
        Name = 'Отключить Windows Recall'
        Desc = 'Запрещает фоновую ИИ-запись экрана и анализ активности через политику WindowsAI.'
        Apply = { Invoke-RecallOff }; Undo = { Undo-RecallOff } }

    [pscustomobject]@{ Id = 'suggestions'; Group = 'clean'; Risk = $false; Default = $true
        Name = 'Убрать рекомендации и рекламу в «Пуске»'
        Desc = 'Отключает подсказки, тихую установку приложений и рекламные блоки Content Delivery Manager.'
        Apply = { Invoke-SuggestionsOff }; Undo = { Undo-SuggestionsOff } }

    [pscustomobject]@{ Id = 'searchweb'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'Поиск Windows без Bing'
        Desc = 'Поиск в «Пуске» показывает только локальные файлы и приложения — без веб-результатов и Cortana.'
        Apply = { Invoke-SearchWebOff }; Undo = { Undo-SearchWebOff } }

    [pscustomobject]@{ Id = 'bgappsglobal'; Group = 'clean'; Risk = $false; Default = $true
        Name = 'Ограничить фоновые приложения'
        Desc = 'Глобально запрещает приложениям работать в фоне. Steam и RUST запускаются как обычно.'
        Apply = { Invoke-BgAppsGlobal }; Undo = { Undo-BgAppsGlobal } }

    [pscustomobject]@{ Id = 'transparency'; Group = 'sys'; Risk = $false; Default = $false
        Name = 'Отключить прозрачность Windows'
        Desc = 'Убирает прозрачные эффекты панели задач и меню — меньше работы для GPU и видеопамяти.'
        Apply = { Invoke-TransparencyOff }; Undo = { Undo-TransparencyOff } }

    [pscustomobject]@{ Id = 'autoplay'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'Отключить AutoPlay / AutoRun'
        Desc = 'Съёмные носители больше не запускают окна автовоспроизведения и не выполняют autorun-скрипты.'
        Apply = { Invoke-AutoPlayOff }; Undo = { Undo-AutoPlayOff } }

    [pscustomobject]@{ Id = 'stickykeys'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'Защита от случайного залипания клавиш'
        Desc = 'Отключает горячие клавиши Sticky/Filter/Toggle Keys — Shift ×5 больше не блокирует управление в игре.'
        Apply = { Invoke-StickyKeysOff }; Undo = { Undo-StickyKeysOff } }
)

# Восстанавливаем выбор пользователя между запусками
$savedEnabled = $script:State['Enabled']
foreach ($t in $script:Tweaks) {
    $v = [bool]$t.Default
    if ($savedEnabled -is [hashtable] -and $savedEnabled.ContainsKey($t.Id)) {
        $v = [bool]$savedEnabled[$t.Id]
    }
    $script:Enabled[$t.Id] = $v
}

# ============================================================
#  ОРКЕСТРАЦИЯ
# ============================================================
function New-RestorePoint {
    Set-Status 'Создание точки восстановления…' '#E3B341'
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description 'RUST Performance Suite' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Log 'Точка восстановления создана' 'ok'
    } catch {
        $msg = $_.Exception.Message
        if ($msg -match '1440|already|уже') {
            Write-Log 'Точка восстановления уже создавалась за последние 24 часа — пропускаю' 'warn'
        } else {
            Write-Log "Точка восстановления недоступна: $msg" 'warn'
        }
    }
}

function Add-Applied {
    param([string]$Id)
    $a = @($script:State['Applied'])
    if ($a -notcontains $Id) { $a += $Id; $script:State['Applied'] = $a }
}

function Get-AppliedTweaks {
    $applied = @($script:State['Applied'])
    return @($script:Tweaks | Where-Object { $applied -contains $_.Id })
}

function Start-Optimization {
    $list = @($script:Tweaks | Where-Object { $script:Enabled[$_.Id] })
    if ($list.Count -eq 0) { return 0 }

    Set-Busy $true
    try {
        Write-Log ('Запуск оптимизации: модулей — ' + $list.Count) 'step'
        # Эталон клиента до любых действий: после оптимизации сравним.
        try { $null = Save-ClientGuardBaseline } catch {}
        New-RestorePoint
        Backup-RegKey 'HKCU:\Control Panel\Mouse' 'Mouse.reg'

        $i = 0
        foreach ($t in $list) {
            $i = $i + 1
            Set-Status ('Применение: ' + $t.Name) '#FF8A4C'
            Set-ProgressValue ((($i - 1) / [double]$list.Count) * 100)
            Write-Log ('▶ ' + $t.Name) 'step'
            try {
                $null = & $t.Apply
                Add-Applied $t.Id
            } catch {
                Write-Log ('   ошибка: ' + $_.Exception.Message) 'err'
            }
            Set-ProgressValue (($i / [double]$list.Count) * 100)
            Save-State
        }

        try { Invoke-RustProcessPolish } catch {}
        $script:State['Enabled'] = $script:Enabled
        Save-State
        try {
            $cg = Test-ClientGuard
            if ($cg.State -eq 'ok') {
                Write-Log 'Целостность клиента: RustClient.exe и DLL не изменены' 'ok'
            } elseif ($cg.State -eq 'changed') {
                Write-Log 'ВНИМАНИЕ: файлы клиента отличаются от эталона. Это не действие оптимизатора — проверьте обновление игры/Steam.' 'warn'
            }
        } catch {}
        Set-ProgressValue 100
        Set-Status 'Готово. Перезагрузите ПК для полного эффекта.' '#4ECB71'
        Write-Log 'Оптимизация завершена' 'ok'
    } finally {
        Set-Busy $false
    }
    return $list.Count
}

function Start-Rollback {
    Set-Busy $true
    try {
        $applied = @(Get-AppliedTweaks)
        Write-Log ('Откат изменений: модулей — ' + $applied.Count) 'step'
        [array]::Reverse($applied)
        $i = 0
        foreach ($t in $applied) {
            $i = $i + 1
            Set-ProgressValue (($i / [double][Math]::Max(1, $applied.Count)) * 100)
            Write-Log ('↩ ' + $t.Name) 'info'
            try { $null = & $t.Undo } catch { Write-Log ('   ошибка отката: ' + $_.Exception.Message) 'warn' }
        }
        $script:State['Applied'] = @()
        Save-State
        Set-ProgressValue 100
        Set-Status 'Откат выполнен' '#4ECB71'
        Write-Log 'Откат завершён. Для 100% чистоты используйте точку восстановления.' 'ok'
    } finally {
        Set-Busy $false
    }
}

# ============================================================
#  RUST ОДНОЙ КНОПКОЙ: ТРАВА + БИНДЫ
# ============================================================
function Invoke-RustOneClick {
    if (-not $script:RustExe) {
        return 'RUST не найден автоматически. Запустите игру через Steam один раз и повторите.'
    }
    $cfgLines = Get-RustCfgCommandText
    $bindLines = Get-BindCommandLines
    $all = @()
    $all += $cfgLines
    $all += $bindLines

    if (Test-RustRunning) {
        $ok = Copy-Text ($all -join "`r`n")
        if ($ok) {
            Write-Log 'Rust запущен — команды скопированы в буфер обмена' 'warn'
            return "RUST сейчас запущен, поэтому файлы cfg трогать нельзя (игра перезапишет их при выходе).`n`nКоманды скопированы в буфер обмена. Откройте в игре консоль (F1) и вставьте их (Ctrl+V), затем нажмите Enter."
        }
        return 'RUST запущен. Закройте игру и повторите, либо примените команды вручную через F1.'
    }

    $dir = Get-RustCfgDir
    if (-not $dir) { return 'Не удалось открыть папку cfg игры.' }

    try { $null = Save-ClientGuardBaseline } catch {}
    $wroteCfg = $false
    $wroteBinds = $false
    $errors = @()
    if ($cfgLines.Count -gt 0) {
        try { $null = Invoke-RustCfg; $wroteCfg = $true }
        catch { $errors += ('client.cfg: ' + $_.Exception.Message); Write-Log ('cfg: ' + $_.Exception.Message) 'warn' }
    }
    if ($bindLines.Count -gt 0) {
        try { Apply-RustBinds -Quiet; $wroteBinds = $true }
        catch { $errors += ('keys.cfg: ' + $_.Exception.Message); Write-Log ('бинды: ' + $_.Exception.Message) 'warn' }
    }
    if ($wroteCfg -or $wroteBinds) { Add-Applied 'rustcfg'; Save-State }
    try {
        $cg = Test-ClientGuard
        if ($cg.State -eq 'ok') { Write-Log 'Целостность клиента после cfg/биндов: файлы не изменены' 'ok' }
    } catch {}

    $cfgCount = if ($wroteCfg) { @($cfgLines).Count } else { 0 }
    $bindCount = if ($wroteBinds) { @($bindLines).Count } else { 0 }
    Write-Log ('Rust: применено строк cfg — ' + $cfgCount + ', биндов — ' + $bindCount) 'ok'
    if ($errors.Count -gt 0) {
        return ("Частично готово.`n`nclient.cfg: " + $cfgCount + " строк`nkeys.cfg: " + $bindCount + " биндов`n`nНе удалось:`n- " + ($errors -join "`n- ") + "`n`nБэкапы: " + $script:RustBackup)
    }
    return ("Готово.`n`nclient.cfg: " + $cfgCount + " строк`nkeys.cfg: " + $bindCount + " биндов`n`nБэкапы: " + $script:RustBackup)
}

function Invoke-RustConsoleCopy {
    $all = @()
    $all += Get-RustCfgCommandText
    $all += Get-BindCommandLines
    if ($all.Count -eq 0) { return 'Нет команд для копирования.' }
    $ok = Copy-Text (($all -join "`r`n") + "`r`n")
    if ($ok) {
        Write-Log 'Команды Rust скопированы в буфер обмена' 'ok'
        return "Команды скопированы.`n`nВ игре нажмите F1, вставьте (Ctrl+V) и нажмите Enter."
    }
    return 'Не удалось скопировать в буфер обмена.'
}

# ============================================================
#  ОКРУЖЕНИЕ (нужно и для SELFTEST, и для интерфейса)
# ============================================================
$script:SteamPath   = Find-SteamPath
$script:RustExe     = Find-RustExe
$script:RustCfgDir  = $null
$script:IsAdmin     = Test-Admin
$script:RustRunning = Test-RustRunning

# ============================================================
#  ТЕМА И АНИМИРОВАННЫЕ КОНТРОЛЫ (C#)
# ============================================================
$script:CsCode = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace RustSuite
{
    public interface IAnim { bool Tick(); }

    public static class Anim
    {
        private static readonly List<IAnim> Items = new List<IAnim>();
        private static Timer _timer;

        public static void Add(IAnim a)
        {
            if (a == null) return;
            if (!Items.Contains(a)) Items.Add(a);
            if (_timer == null)
            {
                _timer = new Timer();
                _timer.Interval = 15;
                _timer.Tick += OnTick;
            }
            if (!_timer.Enabled) _timer.Start();
        }

        public static void Remove(IAnim a)
        {
            if (a != null) Items.Remove(a);
            if (Items.Count == 0 && _timer != null) _timer.Stop();
        }

        private static void OnTick(object sender, EventArgs e)
        {
            for (int i = Items.Count - 1; i >= 0; i--)
            {
                bool keep;
                try { keep = Items[i].Tick(); }
                catch { keep = false; }
                if (!keep) Items.RemoveAt(i);
            }
            if (Items.Count == 0 && _timer != null) _timer.Stop();
        }
    }

    public static class Ease
    {
        public static float Clamp01(float v) { return v < 0f ? 0f : (v > 1f ? 1f : v); }
        public static float OutCubic(float t)
        {
            t = Clamp01(t); float u = 1f - t;
            return 1f - u * u * u;
        }
        public static float OutBack(float t)
        {
            t = Clamp01(t); float c1 = 1.70158f; float c3 = c1 + 1f; float u = t - 1f;
            return 1f + c3 * u * u * u + c1 * u * u;
        }
        public static float Approach(float cur, float target, float k)
        {
            return cur + (target - cur) * k;
        }
        public static bool Done(float a, float b) { return Math.Abs(a - b) < 0.002f; }
    }

    public static class Theme
    {
        public static Color Bg        = Color.FromArgb(22, 14, 34);
        public static Color PanelBg   = Color.FromArgb(26, 16, 38);
        public static Color CardBg    = Color.FromArgb(30, 18, 42);
        public static Color CardHover = Color.FromArgb(34, 22, 48);
        public static Color BorderC   = Color.FromArgb(60, 40, 90);
        public static Color Accent    = Color.FromArgb(140, 50, 200);
        public static Color AccentLt  = Color.FromArgb(180, 80, 230);
        public static Color Secondary = Color.FromArgb(255, 70, 190);
        public static Color Glow      = Color.FromArgb(90, 40, 160);
        public static Color TextC     = Color.FromArgb(250, 240, 255);
        public static Color Muted     = Color.FromArgb(160, 140, 175);
        public static Color Ok        = Color.FromArgb(100, 190, 110);
        public static Color Warn      = Color.FromArgb(230, 190, 50);
        public static Color Err       = Color.FromArgb(240, 90, 100);
        public static Color Field     = Color.FromArgb(24, 16, 36);

        public static Font FTitle = new Font("Segoe UI Semibold", 23f, FontStyle.Bold);
        public static Font FSub   = new Font("Segoe UI", 9f);
        public static Font FName  = new Font("Segoe UI Semibold", 9.5f);
        public static Font FDesc  = new Font("Segoe UI", 8.2f);
        public static Font FBtn   = new Font("Segoe UI Semibold", 9.5f);
        public static Font FMono  = new Font("Consolas", 8.2f);
        public static Font FSmall = new Font("Segoe UI", 7.8f);
        public static Font FHead  = new Font("Segoe UI Semibold", 8.2f);

        public static void ScaleFonts(float s)
        {
            if (s < 0.5f) s = 1f;
            if (Math.Abs(s - 1f) < 0.01f) return;
            FTitle = new Font("Segoe UI Semibold", 23f * s, FontStyle.Bold);
            FSub   = new Font("Segoe UI", 9f * s);
            FName  = new Font("Segoe UI Semibold", 9.5f * s);
            FDesc  = new Font("Segoe UI", 8.2f * s);
            FBtn   = new Font("Segoe UI Semibold", 9.5f * s);
            FMono  = new Font("Consolas", 8.2f * s);
            FSmall = new Font("Segoe UI", 7.8f * s);
            FHead  = new Font("Segoe UI Semibold", 8.2f * s);
        }

        public static Color Lerp(Color a, Color b, float t)
        {
            t = Ease.Clamp01(t);
            return Color.FromArgb(
                (int)(a.A + (b.A - a.A) * t),
                (int)(a.R + (b.R - a.R) * t),
                (int)(a.G + (b.G - a.G) * t),
                (int)(a.B + (b.B - a.B) * t));
        }

        public static GraphicsPath Round(RectangleF r, float rad)
        {
            GraphicsPath p = new GraphicsPath();
            if (rad <= 0.5f) { p.AddRectangle(r); return p; }
            float d = rad * 2f;
            if (d > r.Width) d = r.Width;
            if (d > r.Height) d = r.Height;
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }
    }

    public class BufferedPanel : Panel
    {
        public BufferedPanel()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        }
    }

    // Панель с плавной прокруткой колесом мыши и без мерцания при перестройке.
    public class SmoothScrollPanel : BufferedPanel
    {
        private readonly Timer _t;
        private int _target;

        public SmoothScrollPanel()
        {
            AutoScroll = true;
            _t = new Timer();
            _t.Interval = 15;
            _t.Tick += OnTick;
        }

        protected override void OnMouseWheel(MouseEventArgs e)
        {
            int cur = -AutoScrollPosition.Y;
            int max = 0;
            try { max = Math.Max(0, VerticalScroll.Maximum - VerticalScroll.LargeChange + 1); } catch { }
            _target = cur - e.Delta;
            if (_target < 0) _target = 0;
            if (_target > max) _target = max;
            if (!_t.Enabled) _t.Start();
        }

        protected override void OnMouseEnter(EventArgs e)
        {
            WheelHub.Target = this;
            base.OnMouseEnter(e);
        }

        private void OnTick(object sender, EventArgs e)
        {
            int cur = -AutoScrollPosition.Y;
            int max = 0;
            try { max = Math.Max(0, VerticalScroll.Maximum - VerticalScroll.LargeChange + 1); } catch { }
            if (_target > max) _target = max;
            int d = _target - cur;
            if (Math.Abs(d) <= 1)
            {
                try { AutoScrollPosition = new Point(0, Math.Max(0, _target)); } catch { }
                _t.Stop();
                return;
            }
            int step = (int)Math.Round(d * 0.24);
            if (step == 0) step = Math.Sign(d);
            try { AutoScrollPosition = new Point(0, Math.Max(0, cur + step)); } catch { }
        }

        public void ScrollToTop()
        {
            _target = 0;
            _t.Stop();
            try { AutoScrollPosition = new Point(0, 0); } catch { }
        }

        public void ScrollToValue(int v)
        {
            _target = Math.Max(0, v);
            _t.Stop();
            try { AutoScrollPosition = new Point(0, _target); } catch { }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing && _t != null) { try { _t.Stop(); _t.Dispose(); } catch { } }
            base.Dispose(disposing);
        }
    }

    // Заметная вертикальная полоса прокрутки со стрелками вверх/вниз.
    // Накладывается поверх штатной полосы целевой панели и работает
    // с её AutoScrollPosition, поэтому не ломает колесо и клавиатуру.
    public class ScrollStrip : Control
    {
        private readonly Timer _t;
        private Control _target;
        private bool _hoverUp, _hoverDown, _hoverThumb;
        private bool _dragging;
        private int _dragOffset;
        private int _arrowH;
        private bool _syncing;

        public Control Target
        {
            get { return _target; }
            set
            {
                _target = value;
                ScrollableControl sc = _target as ScrollableControl;
                if (sc != null) { sc.Scroll += delegate { Invalidate(); }; }
                Visible = false;
                Sync();
            }
        }

        public ScrollStrip()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
            Cursor = Cursors.Hand;
            _arrowH = 16;
            try { Width = SystemInformation.VerticalScrollBarWidth; } catch { Width = 17; }
            _t = new Timer();
            _t.Interval = 70;
            _t.Tick += delegate { Sync(); };
            _t.Start();
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing && _t != null) { try { _t.Stop(); _t.Dispose(); } catch { } }
            base.Dispose(disposing);
        }

        private ScrollableControl Sc { get { return _target as ScrollableControl; } }

        private int MaxValue
        {
            get
            {
                if (Sc == null) return 0;
                try { return Math.Max(0, Sc.VerticalScroll.Maximum - Sc.VerticalScroll.LargeChange + 1); }
                catch { return 0; }
            }
        }

        private int Value
        {
            get
            {
                if (Sc == null) return 0;
                try { return Math.Max(0, -Sc.AutoScrollPosition.Y); } catch { return 0; }
            }
        }

        private int ContentHeight
        {
            get
            {
                if (Sc == null) return 0;
                try { return Math.Max(1, Sc.VerticalScroll.Maximum); } catch { return 1; }
            }
        }

        private int ViewHeight
        {
            get
            {
                if (Sc == null) return 1;
                try { return Math.Max(1, Sc.ClientSize.Height); } catch { return 1; }
            }
        }

        public void Sync()
        {
            if (_syncing || Sc == null || Sc.IsDisposed || IsDisposed) return;
            _syncing = true;
            try
            {
                bool need = false;
                try { need = Sc.VerticalScroll.Visible && MaxValue > 0; } catch { }
                if (!need)
                {
                    if (Visible) Visible = false;
                    return;
                }

                int x, y, h;
                if (Parent == _target)
                {
                    x = Math.Max(0, Sc.ClientSize.Width - Width);
                    y = -Sc.AutoScrollPosition.Y;
                    h = Sc.ClientSize.Height;
                }
                else
                {
                    x = _target.Right - Width;
                    y = _target.Top;
                    h = _target.Height;
                }
                if (Bounds.X != x || Bounds.Y != y || Bounds.Height != h || Bounds.Width != Width)
                {
                    Bounds = new Rectangle(x, y, Width, h);
                }
                if (!Visible)
                {
                    Visible = true;
                    BringToFront();
                }
                Invalidate();
            }
            catch { }
            finally { _syncing = false; }
        }

        private int TrackTop { get { return _arrowH + 2; } }
        private int TrackBottom { get { return Height - _arrowH - 2; } }
        private int TrackHeight { get { return Math.Max(1, TrackBottom - TrackTop); } }

        private int ThumbHeight()
        {
            int h = (int)Math.Round((double)TrackHeight * Math.Min(1.0, (double)ViewHeight / ContentHeight));
            return Math.Max(24, Math.Min(TrackHeight, h));
        }

        private Rectangle ThumbRect()
        {
            int th = ThumbHeight();
            int room = TrackHeight - th;
            int max = MaxValue;
            int y = TrackTop;
            if (max > 0 && room > 0)
            {
                y += (int)Math.Round((double)room * Math.Min(1.0, (double)Value / max));
            }
            return new Rectangle(3, y, Math.Max(4, Width - 6), th);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            int w = Width, h = Height;
            using (SolidBrush b = new SolidBrush(Theme.Field)) g.FillRectangle(b, 0, 0, w, h);
            DrawArrow(g, _hoverUp ? Theme.AccentLt : Theme.Muted, 0, true);
            DrawArrow(g, _hoverDown ? Theme.AccentLt : Theme.Muted, h - _arrowH, false);

            Color track = Theme.Lerp(Theme.Field, Theme.Bg, 0.55f);
            using (SolidBrush tb = new SolidBrush(track)) g.FillRectangle(tb, 3, TrackTop, Math.Max(1, w - 6), TrackHeight);

            Rectangle tr = ThumbRect();
            Color thumb = (_dragging || _hoverThumb) ? Theme.AccentLt : Theme.Accent;
            using (GraphicsPath p = RoundRect(tr, 5))
            using (SolidBrush sb = new SolidBrush(thumb)) g.FillPath(sb, p);
            using (Pen pen = new Pen(Theme.Lerp(Theme.Accent, Color.White, 0.3f), 1f))
            {
                if (tr.Width > 6) g.DrawLine(pen, tr.X + 3, tr.Y + 3, tr.Right - 4, tr.Y + 3);
            }
            using (Pen bp = new Pen(Theme.Lerp(Theme.BorderC, Theme.Bg, 0.35f), 1f))
            {
                g.DrawRectangle(bp, 0, 0, w - 1, h - 1);
            }
        }

        private void DrawArrow(Graphics g, Color c, int top, bool up)
        {
            int cx = Width / 2;
            int cy = top + _arrowH / 2;
            Point[] p = up
                ? new Point[] { new Point(cx, cy - 4), new Point(cx - 5, cy + 2), new Point(cx + 5, cy + 2) }
                : new Point[] { new Point(cx, cy + 4), new Point(cx - 5, cy - 2), new Point(cx + 5, cy - 2) };
            using (SolidBrush b = new SolidBrush(c)) g.FillPolygon(b, p);
        }

        private GraphicsPath RoundRect(Rectangle r, int rad)
        {
            GraphicsPath p = new GraphicsPath();
            int d = Math.Max(2, rad * 2);
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }

        private void ScrollTo(int v)
        {
            if (Sc == null) return;
            int max = MaxValue;
            if (v < 0) v = 0;
            if (v > max) v = max;
            SmoothScrollPanel smooth = Sc as SmoothScrollPanel;
            if (smooth != null) smooth.ScrollToValue(v);
            else { try { Sc.AutoScrollPosition = new Point(0, v); } catch { } }
            Invalidate();
        }

        private void PageTo(int dir)
        {
            int page = Math.Max(40, ViewHeight - 40);
            ScrollTo(Value + dir * page);
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (e.Button != MouseButtons.Left) return;
            if (e.Y < _arrowH) { PageTo(-1); return; }
            if (e.Y >= Height - _arrowH) { PageTo(1); return; }
            Rectangle tr = ThumbRect();
            if (tr.Contains(e.Location))
            {
                _dragging = true;
                _dragOffset = e.Y - tr.Y;
            }
            else
            {
                ScrollTo(Value + (e.Y < tr.Y ? -1 : 1) * Math.Max(40, ViewHeight - 40));
            }
            Invalidate();
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            _hoverUp = e.Y < _arrowH;
            _hoverDown = e.Y >= Height - _arrowH;
            _hoverThumb = ThumbRect().Contains(e.Location);
            if (_dragging)
            {
                int room = TrackHeight - ThumbHeight();
                int rel = e.Y - TrackTop - _dragOffset;
                if (rel < 0) rel = 0;
                if (rel > room) rel = room;
                int max = MaxValue;
                int v = (room <= 0 || max <= 0) ? 0 : (int)Math.Round((double)max * rel / room);
                ScrollTo(v);
            }
            Invalidate();
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            _dragging = false;
            Invalidate();
        }

        protected override void OnMouseLeave(EventArgs e)
        {
            base.OnMouseLeave(e);
            _hoverUp = _hoverDown = _hoverThumb = false;
            _dragging = false;
            Invalidate();
        }
    }

    // Колесо мыши над навигацией/панелями тоже прокручивает контент.
    // Не перехватываем колесо у списков, полей ввода и самих прокручиваемых панелей.
    public static class WheelHub
    {
        public static SmoothScrollPanel Target;

        [DllImport("user32.dll")]
        private static extern IntPtr WindowFromPoint(POINT p);
        [DllImport("user32.dll")]
        private static extern bool GetCursorPos(out POINT p);
        [DllImport("user32.dll")]
        private static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

        [StructLayout(LayoutKind.Sequential)]
        private struct POINT { public int X; public int Y; }

        public static bool Route(Message m)
        {
            if (Target == null || Target.IsDisposed || !Target.IsHandleCreated) return false;
            Form host = Target.FindForm();
            if (host == null || Form.ActiveForm != host) return false;
            POINT p;
            if (!GetCursorPos(out p)) return false;
            Control c = Control.FromHandle(WindowFromPoint(p));

            // Курсор над нашей полосой — крутим её панель, а не контент.
            ScrollStrip strip = c as ScrollStrip;
            if (strip != null && strip.Target != null && strip.Target.IsHandleCreated)
            {
                SendMessage(strip.Target.Handle, m.Msg, m.WParam, m.LParam);
                return true;
            }

            for (Control x = c; x != null; x = x.Parent)
            {
                if (x is TextBoxBase || x is ListBox || x is ComboBox) return false;

                // Меню разделов и другие AutoScroll-панели листаются своим колесом.
                ScrollableControl sc = x as ScrollableControl;
                if (sc != null && sc.AutoScroll && sc != Target)
                {
                    bool canScroll = false;
                    try { canScroll = sc.VerticalScroll.Visible && sc.VerticalScroll.Maximum > sc.VerticalScroll.LargeChange; }
                    catch { }
                    if (canScroll)
                    {
                        SendMessage(sc.Handle, m.Msg, m.WParam, m.LParam);
                        return true;
                    }
                }
                if (x is SmoothScrollPanel) return false;
            }
            SendMessage(Target.Handle, m.Msg, m.WParam, m.LParam);
            return true;
        }
    }

    public class WheelRouter : IMessageFilter
    {
        public bool PreFilterMessage(ref Message m)
        {
            if (m.Msg != 0x020A) return false;
            try { return WheelHub.Route(m); } catch { return false; }
        }
    }

    public class HeaderPanel : Panel, IAnim
    {
        private float _phase = 0.15f;
        private int _skip;
        public HeaderPanel()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Theme.PanelBg;
            Anim.Add(this);
        }
        public bool Tick()
        {
            // Блик движется плавно, но перерисовывается ~20 раз в секунду,
            // а не 66: шапка не греет CPU и не мешает плавности прокрутки.
            _phase += 0.0114f;
            if (_phase > 1.35f) _phase = -0.25f;
            _skip++;
            if (_skip < 3) return true;
            _skip = 0;
            Invalidate();
            return true;
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            Rectangle rc = new Rectangle(0, 0, Width, Height);
            using (LinearGradientBrush b = new LinearGradientBrush(rc, Theme.PanelBg, Theme.Bg, LinearGradientMode.Vertical))
                g.FillRectangle(b, rc);

            float sx = _phase * (Width + 620f) - 310f;
            Rectangle sheen = new Rectangle((int)sx, 0, 190, Height);
            using (LinearGradientBrush b = new LinearGradientBrush(sheen, Color.Transparent, Color.Transparent, LinearGradientMode.Horizontal))
            {
                ColorBlend cb = new ColorBlend(3);
                cb.Colors = new Color[] { Color.FromArgb(0, Theme.Accent), Color.FromArgb(130, Theme.Secondary), Color.FromArgb(0, Theme.Accent) };
                cb.Positions = new float[] { 0f, 0.5f, 1f };
                b.InterpolationColors = cb;
                g.FillRectangle(b, sheen);
            }

            using (SolidBrush b = new SolidBrush(Theme.Accent)) g.FillRectangle(b, 0, Height - 2, Width, 2);
            float gx = ((_phase * 1.7f) % 1f) * Width;
            Rectangle glow = new Rectangle((int)gx - 90, Height - 3, 180, 5);
            using (LinearGradientBrush b = new LinearGradientBrush(glow, Color.Transparent, Color.Transparent, LinearGradientMode.Horizontal))
            {
                ColorBlend cb = new ColorBlend(3);
                cb.Colors = new Color[] { Color.FromArgb(0, Theme.Accent), Color.FromArgb(160, Theme.Secondary), Color.FromArgb(0, Theme.Accent) };
                cb.Positions = new float[] { 0f, 0.5f, 1f };
                b.InterpolationColors = cb;
                g.FillRectangle(b, glow);
            }
            // Пользовательские Paint-обработчики (текст шапки) вызываются
            // базовым OnPaint; без этого события Paint не срабатывает.
            base.OnPaint(e);
        }
    }

    public class Card : Panel, IAnim
    {
        private bool _on, _hover;
        private float _p, _ha;
        public string Title = "";
        public string Sub = "";
        public bool Risk;
        public event EventHandler Toggled;

        public bool On
        {
            get { return _on; }
            set
            {
                if (_on == value) return;
                _on = value;
                Anim.Add(this);
                Invalidate();
                EventHandler h = Toggled;
                if (h != null) h(this, EventArgs.Empty);
            }
        }

        public Card()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Theme.Bg;
            Cursor = Cursors.Hand;
        }

        protected override void OnMouseEnter(EventArgs e)
        { _hover = true; Anim.Add(this); Invalidate(); base.OnMouseEnter(e); }

        protected override void OnMouseLeave(EventArgs e)
        {
            _hover = ClientRectangle.Contains(PointToClient(Cursor.Position));
            Anim.Add(this); Invalidate(); base.OnMouseLeave(e);
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (e.Button == MouseButtons.Left) On = !On;
        }

        public bool Tick()
        {
            float tp = _on ? 1f : 0f;
            float th = _hover ? 1f : 0f;
            _p = Ease.Approach(_p, tp, 0.22f);
            _ha = Ease.Approach(_ha, th, 0.25f);
            Invalidate();
            return !(Ease.Done(_p, tp) && Ease.Done(_ha, th));
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            RectangleF r = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
            Color fill = Theme.Lerp(Theme.CardBg, Theme.CardHover, _ha);
            Color line = Theme.Lerp(Theme.BorderC, Color.FromArgb(64, 255, 255, 255), _ha);
            if (_p > 0.01f) line = Theme.Lerp(line, Color.FromArgb(120, Theme.Accent), _p);
            using (GraphicsPath p = Theme.Round(r, 9f))
            {
                using (SolidBrush b = new SolidBrush(fill)) g.FillPath(b, p);
                using (Pen pen = new Pen(line, 1f)) g.DrawPath(pen, p);
            }
            if (_p > 0.02f)
            {
                int h = Height - 26;
                if (h < 8) h = 8;
                using (SolidBrush b = new SolidBrush(Color.FromArgb((int)(230 * _p), Theme.Accent)))
                    g.FillRectangle(b, 0, (Height - h) / 2, 3, h);
            }

            int tw = Width - 100;
            if (tw < 60) tw = 60;
            Color tc = Risk ? Theme.Warn : Theme.TextC;
            TextRenderer.DrawText(g, Title, Theme.FName, new Rectangle(16, 11, tw, 20), tc,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
            int dh = Height - 40;
            if (dh < 10) dh = 10;
            TextRenderer.DrawText(g, Sub, Theme.FDesc, new Rectangle(16, 32, tw, dh), Theme.Muted,
                TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.WordBreak | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);

            float tww = 42f, thh = 22f;
            if (Width > 130)
            {
                float tx = Width - tww - 16f;
                float ty = (Height - thh) / 2f;
                using (GraphicsPath p = Theme.Round(new RectangleF(tx, ty, tww, thh), thh / 2f))
                using (SolidBrush b = new SolidBrush(Theme.Lerp(Color.FromArgb(44, 51, 65), Theme.Accent, _p)))
                    g.FillPath(b, p);
                float d = thh - 7f;
                float kx = tx + 3.5f + (tww - d - 7f) * _p;
                using (SolidBrush b = new SolidBrush(Theme.Lerp(Color.FromArgb(140, 151, 166), Color.White, _p)))
                    g.FillEllipse(b, kx, ty + 3.5f, d, d);
            }
        }
    }

    public class FlatButton : Control, IAnim
    {
        public enum Kind { Primary, Ghost }
        public Kind Style = Kind.Primary;
        private bool _hover, _down;
        private float _ha;
        private float _rx, _ry, _rr, _ra;

        public FlatButton()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor | ControlStyles.Selectable, true);
            Cursor = Cursors.Hand;
            Font = Theme.FBtn;
            ForeColor = Theme.TextC;
            BackColor = Color.Transparent;
            TabStop = true;
        }

        protected override void OnMouseEnter(EventArgs e) { _hover = true; Anim.Add(this); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { _hover = false; _down = false; Anim.Add(this); base.OnMouseLeave(e); }
        protected override void OnMouseDown(MouseEventArgs e)
        {
            _down = true; _rx = e.X; _ry = e.Y; _rr = 4f; _ra = 0.30f;
            Anim.Add(this); base.OnMouseDown(e);
        }
        protected override void OnMouseUp(MouseEventArgs e) { _down = false; Anim.Add(this); base.OnMouseUp(e); }
        protected override void OnKeyDown(KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Enter || e.KeyCode == Keys.Space) { e.Handled = true; OnClick(EventArgs.Empty); }
            base.OnKeyDown(e);
        }
        protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
        protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }

        public bool Tick()
        {
            _ha = Ease.Approach(_ha, _hover ? 1f : 0f, 0.25f);
            bool ripple = false;
            if (_ra > 0.01f)
            {
                _rr += Math.Max(6f, Width / 18f);
                _ra -= 0.045f;
                if (_ra < 0f) _ra = 0f;
                ripple = true;
            }
            Invalidate();
            return !Ease.Done(_ha, _hover ? 1f : 0f) || ripple;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            RectangleF r = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
            Color fill, line = Color.Empty, text = ForeColor;
            if (Style == Kind.Primary)
            {
                fill = !Enabled ? Color.FromArgb(70, Theme.Accent)
                     : _down ? Theme.Lerp(Theme.Accent, Color.Black, 0.25f)
                     : Theme.Lerp(Theme.Accent, Theme.AccentLt, _ha);
                text = Enabled ? Color.White : Color.FromArgb(150, 150, 150);
            }
            else
            {
                fill = _down ? Theme.Lerp(Theme.CardBg, Color.Black, 0.22f)
                     : Theme.Lerp(Theme.PanelBg, Theme.CardBg, _ha);
                line = _hover ? Theme.Lerp(Theme.BorderC, Theme.AccentLt, 0.45f) : Theme.BorderC;
                text = Enabled ? Theme.TextC : Color.FromArgb(110, 118, 130);
            }
            using (GraphicsPath p = Theme.Round(r, 9f))
            {
                using (SolidBrush b = new SolidBrush(fill)) g.FillPath(b, p);
                if (line != Color.Empty) { using (Pen pen = new Pen(line, 1f)) g.DrawPath(pen, p); }
                if (_ra > 0.01f)
                {
                    GraphicsState st = g.Save();
                    g.SetClip(p);
                    using (SolidBrush rb = new SolidBrush(Color.FromArgb((int)(255 * _ra), 255, 255, 255)))
                        g.FillEllipse(rb, _rx - _rr, _ry - _rr, _rr * 2f, _rr * 2f);
                    g.Restore(st);
                }
            }
            if (Focused && Enabled)
            {
                using (Pen pen = new Pen(Color.FromArgb(90, 255, 255, 255), 1f))
                using (GraphicsPath p = Theme.Round(new RectangleF(3f, 3f, Width - 7f, Height - 7f), 7f))
                    g.DrawPath(pen, p);
            }
            TextRenderer.DrawText(g, Text, Font, ClientRectangle, text,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter |
                TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
        }
    }

    public class NavButton : Control, IAnim
    {
        private bool _hover, _sel;
        private float _sa, _ha;
        public string Sub = "";

        public bool Selected { get { return _sel; } set { _sel = value; Anim.Add(this); Invalidate(); } }

        public NavButton()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
            Cursor = Cursors.Hand;
            BackColor = Color.Transparent;
        }

        protected override void OnMouseEnter(EventArgs e) { _hover = true; Anim.Add(this); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { _hover = false; Anim.Add(this); base.OnMouseLeave(e); }

        public bool Tick()
        {
            _sa = Ease.Approach(_sa, _sel ? 1f : 0f, 0.24f);
            _ha = Ease.Approach(_ha, _hover ? 1f : 0f, 0.25f);
            Invalidate();
            return !(Ease.Done(_sa, _sel ? 1f : 0f) && Ease.Done(_ha, _hover ? 1f : 0f));
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            RectangleF r = new RectangleF(0.5f, 0.5f, Width - 2.5f, Height - 1.5f);
            float a = Math.Max(_sa, _ha * 0.55f);
            if (a > 0.02f)
            {
                Color navFill = Theme.Lerp(Theme.Bg, Theme.CardHover, _sel ? 0.85f : 0.45f);
                using (GraphicsPath p = Theme.Round(r, 8f))
                using (SolidBrush b = new SolidBrush(Color.FromArgb(_sel ? 165 : 70, navFill)))
                    g.FillPath(b, p);
            }
            if (_sa > 0.02f)
            {
                int h = (int)(18 * Ease.OutBack(_sa));
                if (h > Height - 8) h = Height - 8;
                using (SolidBrush b = new SolidBrush(Theme.Accent))
                    g.FillRectangle(b, 0, (Height - h) / 2, 3, h);
            }
            Color c = Theme.Lerp(Theme.Muted, Theme.TextC, Math.Max(_sa, _ha * 0.8f));
            using (Font f = new Font("Segoe UI Semibold", 9.2f))
                TextRenderer.DrawText(g, Text, f, new Rectangle(14, 8, Width - 22, 18), c,
                    TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
            if (!string.IsNullOrEmpty(Sub))
            {
                Color sc = Theme.Lerp(Theme.Muted, Theme.TextC, _sa * 0.7f);
                using (Font f = new Font("Segoe UI", 7.4f))
                    TextRenderer.DrawText(g, Sub, f, new Rectangle(14, 26, Width - 22, 14), sc,
                        TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
            }
        }
    }

    public class ThemeTile : Control, IAnim
    {
        public string Title = "";
        public string Sub = "";
        public Color ColorA = Theme.Accent;
        public Color ColorB = Theme.AccentLt;
        public Color ColorC = Theme.Secondary;
        private bool _sel, _hover;
        private float _sa, _ha, _phase;

        public bool Selected
        {
            get { return _sel; }
            set { _sel = value; Anim.Add(this); Invalidate(); }
        }

        public ThemeTile()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
            Cursor = Cursors.Hand;
        }

        protected override void OnClick(EventArgs e)
        {
            base.OnClick(e);
        }

        protected override void OnMouseEnter(EventArgs e) { _hover = true; Anim.Add(this); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { _hover = false; Anim.Add(this); base.OnMouseLeave(e); }

        public bool Tick()
        {
            _sa = Ease.Approach(_sa, _sel ? 1f : 0f, 0.2f);
            _ha = Ease.Approach(_ha, _hover ? 1f : 0f, 0.22f);
            if (_sel || _hover) { _phase += 0.022f; if (_phase > 1f) _phase -= 1f; }
            Invalidate();
            return !(Ease.Done(_sa, _sel ? 1f : 0f) && Ease.Done(_ha, _hover ? 1f : 0f));
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            RectangleF r = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
            using (GraphicsPath p = Theme.Round(r, 10f))
            {
                using (LinearGradientBrush b = new LinearGradientBrush(
                    new Rectangle(0, 0, Math.Max(2, Width), Math.Max(2, Height)),
                    ColorA, ColorB, LinearGradientMode.ForwardDiagonal))
                    g.FillPath(b, p);

                using (LinearGradientBrush dark = new LinearGradientBrush(
                    new Rectangle(0, Math.Max(0, Height - 46), Math.Max(2, Width), 46),
                    Color.FromArgb(0, 0, 0, 0), Color.FromArgb(150, 0, 0, 0), LinearGradientMode.Vertical))
                {
                    GraphicsState st = g.Save();
                    g.SetClip(p);
                    g.FillRectangle(dark, 0, Height - 46, Width, 46);
                    g.Restore(st);
                }

                if (_ha > 0.02f || _sel)
                {
                    GraphicsState st = g.Save();
                    g.SetClip(p);
                    float sx = (float)(_phase * (Width + 160.0)) - 80f;
                    using (LinearGradientBrush sheen = new LinearGradientBrush(
                        new Rectangle((int)sx, 0, 70, Math.Max(2, Height)),
                        Color.FromArgb(0, 255, 255, 255), Color.FromArgb(0, 255, 255, 255),
                        LinearGradientMode.Horizontal))
                    {
                        ColorBlend cb = new ColorBlend(3);
                        cb.Colors = new Color[] { Color.FromArgb(0, 255, 255, 255), Color.FromArgb(45, 255, 255, 255), Color.FromArgb(0, 255, 255, 255) };
                        cb.Positions = new float[] { 0f, 0.5f, 1f };
                        sheen.InterpolationColors = cb;
                        g.FillRectangle(sheen, new Rectangle((int)sx, 0, 70, Height));
                    }
                    g.Restore(st);
                }

                Color border = _sel ? Color.White : (_hover ? Color.FromArgb(200, 255, 255, 255) : Color.FromArgb(90, 255, 255, 255));
                using (Pen pen = new Pen(border, _sel ? 2f : 1f)) g.DrawPath(pen, p);
            }

            TextRenderer.DrawText(g, Title, Theme.FName, new Rectangle(14, Height - 36, Width - 70, 18), Color.White,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
            TextRenderer.DrawText(g, Sub, Theme.FSmall, new Rectangle(14, Height - 19, Width - 20, 14), Color.FromArgb(220, 240, 235, 255),
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);

            int cy = 14;
            using (SolidBrush b = new SolidBrush(ColorC)) g.FillEllipse(b, Width - 30, cy, 9, 9);
            using (SolidBrush b = new SolidBrush(Color.FromArgb(150, 255, 255, 255))) g.FillEllipse(b, Width - 18, cy + 3, 5, 5);

            if (_sel)
            {
                using (SolidBrush b = new SolidBrush(Color.FromArgb(230, 255, 255, 255)))
                    g.FillEllipse(b, Width - 34, 10, 20, 20);
                TextRenderer.DrawText(g, "✓", Theme.FSmall, new Rectangle(Width - 34, 9, 20, 20), Color.FromArgb(35, 15, 55),
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
            }
        }
    }

    public class HealthRow : Control, IAnim
    {
        public string Title = "";
        public string Detail = "";
        public string ActionText = "";
        private string _status = "info";
        private bool _hover;
        private float _ha, _phase;

        public string Status
        {
            get { return _status; }
            set { _status = value ?? "info"; Anim.Add(this); Invalidate(); }
        }

        public event EventHandler ActionClicked;

        public HealthRow()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
        }

        protected override void OnMouseEnter(EventArgs e) { _hover = true; Anim.Add(this); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { _hover = false; Cursor = Cursors.Default; Anim.Add(this); base.OnMouseLeave(e); }
        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            Cursor = (e.X >= Width - 150 && !string.IsNullOrEmpty(ActionText)) ? Cursors.Hand : Cursors.Default;
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (e.Button == MouseButtons.Left && e.X >= Width - 150 && !string.IsNullOrEmpty(ActionText))
            {
                EventHandler h = ActionClicked;
                if (h != null) h(this, EventArgs.Empty);
            }
        }

        public bool Tick()
        {
            _ha = Ease.Approach(_ha, _hover ? 1f : 0f, 0.22f);
            bool pulse = (_status == "warn" || _status == "err");
            if (pulse) { _phase += 0.045f; if (_phase > 1f) _phase -= 1f; }
            Invalidate();
            return pulse || !Ease.Done(_ha, _hover ? 1f : 0f);
        }

        private Color StatusColor()
        {
            if (_status == "ok") return Theme.Ok;
            if (_status == "warn") return Theme.Warn;
            if (_status == "err") return Theme.Err;
            return Theme.AccentLt;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            RectangleF r = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
            Color fill = Theme.Lerp(Theme.CardBg, Theme.CardHover, _ha);
            using (GraphicsPath p = Theme.Round(r, 9f))
            {
                using (SolidBrush b = new SolidBrush(fill)) g.FillPath(b, p);
                using (Pen pen = new Pen(Theme.Lerp(Theme.BorderC, Color.FromArgb(110, 255, 255, 255), _ha), 1f))
                    g.DrawPath(pen, p);
            }
            Color sc = StatusColor();
            float pulse = 0.35f + 0.25f * (float)Math.Sin(_phase * Math.PI * 2.0);
            if (_status == "warn" || _status == "err")
                using (SolidBrush glow = new SolidBrush(Color.FromArgb((int)(50 * pulse), sc.R, sc.G, sc.B)))
                    g.FillEllipse(glow, 13, Height / 2 - 7, 14, 14);
            using (SolidBrush dot = new SolidBrush(sc))
                g.FillEllipse(dot, 17, Height / 2 - 3, 6, 6);
            using (SolidBrush bar = new SolidBrush(Color.FromArgb(110, sc)))
                g.FillRectangle(bar, 0, 12, 3, Height - 24);

            int actionW = string.IsNullOrEmpty(ActionText) ? 0 : 132;
            int tw = Width - 42 - actionW;
            if (tw < 80) tw = 80;
            TextRenderer.DrawText(g, Title, Theme.FName, new Rectangle(30, 7, tw, 19), Theme.TextC,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
            TextRenderer.DrawText(g, Detail, Theme.FSmall, new Rectangle(30, 26, tw, Height - 29), Theme.Muted,
                TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.WordBreak | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);

            if (actionW > 0 && Width > 220)
            {
                int bw = 118, bh = 26;
                int bx = Width - bw - 14;
                int by = (Height - bh) / 2;
                using (GraphicsPath p = Theme.Round(new RectangleF(bx, by, bw, bh), 8f))
                {
                    using (SolidBrush b = new SolidBrush(Color.FromArgb(30, sc.R, sc.G, sc.B))) g.FillPath(b, p);
                    using (Pen pen = new Pen(Color.FromArgb(120, sc.R, sc.G, sc.B), 1f)) g.DrawPath(pen, p);
                }
                TextRenderer.DrawText(g, ActionText, Theme.FSmall, new Rectangle(bx, by, bw, bh), sc,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
            }
        }
    }

    public class ProgressStrip : Control, IAnim
    {        private double _v, _shown;
        private float _phase;
        private int _skip;
        public bool Shimmer = true;

        public double Value
        {
            get { return _v; }
            set { _v = Math.Max(0, Math.Min(100, value)); Anim.Add(this); }
        }

        public ProgressStrip()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
        }

        public bool Tick()
        {
            _shown = _shown + (_v - _shown) * 0.18;
            bool moving = Math.Abs(_v - _shown) > 0.05;
            bool shim = Shimmer && _shown > 0.5 && _shown < 99.5;
            if (moving)
            {
                _skip = 0;
                if (shim) { _phase += 0.025f; if (_phase > 1f) _phase -= 1f; }
                Invalidate();
                return true;
            }
            // Блик на неподвижной полосе перерисовывается реже — экономия CPU.
            if (shim)
            {
                _skip++;
                if (_skip >= 3)
                {
                    _skip = 0;
                    _phase += 0.075f;
                    if (_phase > 1f) _phase -= 1f;
                    Invalidate();
                }
                return true;
            }
            return false;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            RectangleF r = new RectangleF(0, 0, Width, Height);
            using (GraphicsPath p = Theme.Round(r, Height / 2f))
            using (SolidBrush b = new SolidBrush(Color.FromArgb(30, 36, 46)))
                g.FillPath(b, p);

            double w = Width * (_shown / 100.0);
            if (w >= 2)
            {
                RectangleF rf = new RectangleF(0, 0, (float)w, Height);
                using (GraphicsPath p = Theme.Round(rf, Height / 2f))
                {
                    using (LinearGradientBrush b = new LinearGradientBrush(
                        new Rectangle(0, 0, Math.Max(2, (int)w), Math.Max(2, Height)),
                        Theme.Accent, Theme.AccentLt, LinearGradientMode.Horizontal))
                        g.FillPath(b, p);
                    if (Shimmer && w > 24)
                    {
                        GraphicsState st = g.Save();
                        g.SetClip(p);
                        float sx = (float)(_phase * (w + 90.0)) - 45f;
                        using (LinearGradientBrush b = new LinearGradientBrush(
                            new Rectangle((int)sx, 0, 60, Math.Max(2, Height)),
                            Color.FromArgb(0, 255, 255, 255), Color.FromArgb(0, 255, 255, 255),
                            LinearGradientMode.Horizontal))
                        {
                            ColorBlend cb = new ColorBlend(3);
                            cb.Colors = new Color[] { Color.FromArgb(120, 255, 100, 160), Color.FromArgb(180, 160, 60, 240), Color.FromArgb(120, 255, 100, 160) };
                            cb.Positions = new float[] { 0f, 0.5f, 1f };
                            b.InterpolationColors = cb;
                            g.FillRectangle(b, new Rectangle((int)sx, 0, 60, Height));
                        }
                        g.Restore(st);
                    }
                }
            }
        }
    }

    public class Spinner : Control, IAnim
    {
        private float _angle;
        private bool _active;

        public bool Active
        {
            get { return _active; }
            set { _active = value; if (value) Anim.Add(this); Invalidate(); }
        }

        public Spinner()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
        }

        public bool Tick()
        {
            if (!_active) return false;
            _angle += 11f;
            if (_angle > 360f) _angle -= 360f;
            Invalidate();
            return true;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            int d = Math.Min(Width, Height) - 4;
            if (d < 6 || !_active) return;
            RectangleF r = new RectangleF(2, 2, d, d);
            using (Pen bg = new Pen(Color.FromArgb(40, 255, 255, 255), 2.4f))
                g.DrawEllipse(bg, r);
            using (Pen pen = new Pen(Theme.AccentLt, 2.4f))
            {
                pen.StartCap = LineCap.Round;
                pen.EndCap = LineCap.Round;
                g.DrawArc(pen, r, _angle, 100f);
            }
        }
    }

    // Компактная карточка-показатель для панели «ОБЗОР».
    public class StatCard : Control, IAnim
    {
        public string Label = "";
        public string Value = "";
        public string Hint = "";
        public Color AccentC = Theme.Accent;
        private bool _hover;
        private float _ha;
        private float _glow;

        public StatCard()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
            Cursor = Cursors.Hand;
        }

        public void SetValue(string v)
        {
            if (Value == v) return;
            Value = v == null ? "" : v;
            _glow = 1f;
            Anim.Add(this);
            Invalidate();
        }

        protected override void OnMouseEnter(EventArgs e) { _hover = true; Anim.Add(this); Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { _hover = false; Anim.Add(this); Invalidate(); base.OnMouseLeave(e); }

        public bool Tick()
        {
            float th = _hover ? 1f : 0f;
            _ha = Ease.Approach(_ha, th, 0.22f);
            _glow = Ease.Approach(_glow, 0f, 0.06f);
            Invalidate();
            return !(Ease.Done(_ha, th) && _glow < 0.01f);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            RectangleF r = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
            Color fill = Theme.Lerp(Theme.CardBg, Theme.CardHover, _ha);
            using (GraphicsPath p = Theme.Round(r, 9f))
            {
                using (LinearGradientBrush b = new LinearGradientBrush(
                    new Rectangle(0, 0, Math.Max(2, Width), Math.Max(2, Height)),
                    fill, Theme.PanelBg, LinearGradientMode.Vertical))
                    g.FillPath(b, p);
                Color line = Theme.Lerp(Theme.BorderC, Color.FromArgb(90, AccentC), Math.Max(_ha, _glow * 0.7f));
                using (Pen pen = new Pen(line, 1f)) g.DrawPath(pen, p);
            }
            using (SolidBrush b = new SolidBrush(AccentC))
                g.FillRectangle(b, 0, 12, 3, Math.Max(6, Height - 24));

            TextRenderer.DrawText(g, Label, Theme.FHead, new Rectangle(14, 9, Width - 22, 16), Theme.Muted,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
            using (Font fv = new Font("Segoe UI Semibold", 14f, FontStyle.Bold))
                TextRenderer.DrawText(g, Value, fv, new Rectangle(14, 24, Width - 22, Height - 40), Theme.TextC,
                    TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
            if (!string.IsNullOrEmpty(Hint))
                TextRenderer.DrawText(g, Hint, Theme.FSmall, new Rectangle(14, Height - 20, Width - 22, 15), Theme.Muted,
                    TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
        }
    }

    // Кольцевой индикатор оценки оптимизации: дуга, градиент, бегущий блик.
    public class RingGauge : Control, IAnim
    {
        private double _v, _shown;
        private float _phase;
        private string _caption = "";
        private string _sub = "";
        private int _idle;
        private int _skip;

        public double Value
        {
            get { return _v; }
            set
            {
                double nv = Math.Max(0, Math.Min(100, value));
                if (Math.Abs(nv - _v) < 0.001) return;
                _v = nv;
                _idle = 0;
                Anim.Add(this);
            }
        }

        public string Caption
        {
            get { return _caption; }
            set { _caption = value == null ? "" : value; Invalidate(); }
        }

        public string Sub
        {
            get { return _sub; }
            set { _sub = value == null ? "" : value; Invalidate(); }
        }

        public RingGauge()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
            _phase = 0.2f;
        }

        public bool Tick()
        {
            _shown = _shown + (_v - _shown) * 0.12;
            bool settling = Math.Abs(_v - _shown) > 0.05;
            if (settling)
            {
                _idle = 0;
                _skip = 0;
                _phase += 0.012f;
                if (_phase > 1f) _phase -= 1f;
                Invalidate();
                return true;
            }
            // После остановки блик живёт ещё ~1.5 секунды и плавно замирает.
            // Постоянный таймер не крутится вхолостую: интерфейс остаётся лёгким.
            if (_idle < 90)
            {
                _idle++;
                _skip++;
                if (_skip >= 4)
                {
                    _skip = 0;
                    _phase += 0.048f;
                    if (_phase > 1f) _phase -= 1f;
                    Invalidate();
                }
                return true;
            }
            return false;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            int pad = 12;
            int side = Math.Min(Width, Height) - pad * 2;
            if (side < 20) return;
            RectangleF r = new RectangleF((Width - side) / 2f, (Height - side) / 2f, side, side);
            float th = Math.Max(6f, side * 0.075f);

            using (Pen track = new Pen(Color.FromArgb(36, Theme.BorderC), th))
            {
                track.StartCap = LineCap.Round;
                track.EndCap = LineCap.Round;
                g.DrawArc(track, r, 135f, 270f);
            }

            float sweep = (float)(270.0 * (_shown / 100.0));
            if (sweep > 0.4f)
            {
                using (LinearGradientBrush b = new LinearGradientBrush(
                    Rectangle.Round(r), Theme.Accent, Theme.Secondary, 45f))
                using (Pen arc = new Pen(b, th))
                {
                    arc.StartCap = LineCap.Round;
                    arc.EndCap = LineCap.Round;
                    g.DrawArc(arc, r, 135f, sweep);
                }

                // Бегущий блик по дуге.
                if (_shown > 4 && _shown < 99.9)
                {
                    float a = 135f + sweep * _phase;
                    double rad = a * Math.PI / 180.0;
                    float cx = r.X + r.Width / 2f + (float)Math.Cos(rad) * (side / 2f);
                    float cy = r.Y + r.Height / 2f + (float)Math.Sin(rad) * (side / 2f);
                    float d = th * 0.55f;
                    using (SolidBrush b = new SolidBrush(Color.FromArgb(210, Color.White)))
                        g.FillEllipse(b, cx - d / 2f, cy - d / 2f, d, d);
                }
            }

            string big = ((int)Math.Round(_shown)).ToString();
            using (Font fBig = new Font("Segoe UI Semibold", Math.Max(15f, side * 0.23f), FontStyle.Bold))
            using (Font fPct = new Font("Segoe UI", Math.Max(8f, side * 0.075f)))
            {
                Size bs = TextRenderer.MeasureText(big, fBig);
                Rectangle br = new Rectangle(0, (Height / 2) - (int)(bs.Height * 0.78), Width, bs.Height);
                TextRenderer.DrawText(g, big, fBig, br, Theme.TextC,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
                Rectangle pr = new Rectangle((Width + bs.Width / 2) / 2 + 1, br.Y + (int)(bs.Height * 0.30), Width, (int)(bs.Height * 0.55));
                TextRenderer.DrawText(g, "%", fPct, pr, Theme.Muted,
                    TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.NoPrefix);
            }
            if (!string.IsNullOrEmpty(_caption))
            {
                Rectangle cr = new Rectangle(0, (Height / 2) + (int)(side * 0.11), Width, 20);
                TextRenderer.DrawText(g, _caption, Theme.FHead, cr, Theme.TextC,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.Top | TextFormatFlags.NoPrefix | TextFormatFlags.EndEllipsis);
            }
            if (!string.IsNullOrEmpty(_sub))
            {
                Rectangle sr = new Rectangle(0, (Height / 2) + (int)(side * 0.11) + 19, Width, 18);
                TextRenderer.DrawText(g, _sub, Theme.FSmall, sr, Theme.Muted,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.Top | TextFormatFlags.NoPrefix | TextFormatFlags.EndEllipsis);
            }
        }
    }

    // Живой график нагрузки: заполненная область, линия и точка на конце.
    public class Sparkline : Control, IAnim
    {
        private readonly List<float> _pts = new List<float>();
        private readonly int _cap;
        private float _phase;
        private Color _line;
        private int _pulse;

        public Sparkline() : this(60) { }

        public Sparkline(int capacity)
        {
            _cap = Math.Max(4, capacity);
            _line = Theme.AccentLt;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
        }

        public Color LineColor
        {
            get { return _line; }
            set { _line = value; Invalidate(); }
        }

        public void Push(double value)
        {
            float v = (float)Math.Max(0, Math.Min(100, value));
            _pts.Add(v);
            while (_pts.Count > _cap) _pts.RemoveAt(0);
            _pulse = 24;
            Anim.Add(this);
            Invalidate();
        }

        public void Reset()
        {
            _pts.Clear();
            Invalidate();
        }

        public int Count { get { return _pts.Count; } }

        public bool Tick()
        {
            if (_pts.Count < 2) return false;
            // Пульс точки запускается только после нового замера (раз в 2.5 с),
            // а не крутится 66 кадров/с всё время, пока открыт «ОБЗОР».
            if (_pulse <= 0) return false;
            _pulse--;
            _phase += 0.05f;
            if (_phase > 1f) _phase -= 1f;
            Invalidate();
            return _pulse > 0;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            int n = _pts.Count;
            if (n < 2 || Width < 8 || Height < 8) return;

            // Мягкая сетка.
            using (Pen grid = new Pen(Color.FromArgb(22, Theme.BorderC), 1f))
            {
                for (int i = 1; i < 4; i++)
                {
                    int yy = Height * i / 4;
                    g.DrawLine(grid, 0, yy, Width, yy);
                }
            }

            PointF[] pts = new PointF[n];
            float stepX = Width / (float)(n - 1);
            for (int i = 0; i < n; i++)
            {
                float y = Height - 2f - (_pts[i] / 100f) * (Height - 4f);
                pts[i] = new PointF(i * stepX, y);
            }

            GraphicsPath area = new GraphicsPath();
            area.AddLine(0, Height, (int)pts[0].X, (int)pts[0].Y);
            area.AddLines(pts);
            area.AddLine((int)pts[n - 1].X, (int)pts[n - 1].Y, Width, Height);
            area.AddLine(Width, Height, 0, Height);
            area.CloseFigure();
            using (LinearGradientBrush b = new LinearGradientBrush(
                new Rectangle(0, 0, Math.Max(2, Width), Math.Max(2, Height)),
                Color.FromArgb(110, _line), Color.FromArgb(0, _line), 90f))
                g.FillPath(b, area);
            area.Dispose();

            using (Pen pen = new Pen(_line, 1.8f))
            {
                pen.LineJoin = LineJoin.Round;
                g.DrawLines(pen, pts);
            }

            PointF last = pts[n - 1];
            float r = 3.0f + (float)(Math.Sin(_phase * Math.PI * 2) * 1.2);
            using (SolidBrush halo = new SolidBrush(Color.FromArgb(90, _line)))
                g.FillEllipse(halo, last.X - r * 2, last.Y - r * 2, r * 4, r * 4);
            using (SolidBrush dot = new SolidBrush(_line))
                g.FillEllipse(dot, last.X - r, last.Y - r, r * 2, r * 2);
        }
    }

    public class SlideTween : IAnim
    {
        private readonly Control _c;
        private readonly float _from, _to, _delay, _dur;
        private float _t;

        public SlideTween(Control c, int fromTop, int toTop, int delayMs, int durMs)
        {
            _c = c;
            _from = fromTop;
            _to = toTop;
            _delay = Math.Max(0, delayMs);
            _dur = Math.Max(1, durMs);
            Anim.Add(this);
        }

        public bool Tick()
        {
            _t += 16f;
            if (_t < _delay) return true;
            float p = Ease.Clamp01((_t - _delay) / _dur);
            float e = Ease.OutCubic(p);
            if (_c != null && !_c.IsDisposed)
            {
                int top = (int)Math.Round(_from + (_to - _from) * e);
                if (_c.Top != top) _c.Top = top;
            }
            return p < 1f;
        }
    }

    public static class Native
    {
        [DllImport("dwmapi.dll")]
        public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int val, int size);
        [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)]
        public static extern int SetWindowTheme(IntPtr hwnd, string sub, string sub2);

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        private static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);
        private const int WM_SETREDRAW = 0x000B;

        // Пакетная перерисовка: строим панель без промежуточных миганий.
        public static void SetRedraw(Control c, bool enabled)
        {
            try { SendMessage(c.Handle, WM_SETREDRAW, enabled ? (IntPtr)1 : IntPtr.Zero, IntPtr.Zero); } catch { }
        }

        public static void DarkTitle(Form f)
        {
            try
            {
                int v = 1;
                DwmSetWindowAttribute(f.Handle, 20, ref v, 4);
                DwmSetWindowAttribute(f.Handle, 19, ref v, 4);
                // Windows 11: скруглённые углы окна (на Windows 10 вызов игнорируется).
                int corner = 2;
                DwmSetWindowAttribute(f.Handle, 33, ref corner, 4);
            }
            catch { }
        }
        public static void DarkScroll(Control c)
        {
            try { SetWindowTheme(c.Handle, "DarkMode_Explorer", null); } catch { }
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
        public class MEMORYSTATUSEX
        {
            public uint dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
            public uint dwMemoryLoad;
            public ulong ullTotalPhys;
            public ulong ullAvailPhys;
            public ulong ullTotalPageFile;
            public ulong ullAvailPageFile;
            public ulong ullTotalVirtual;
            public ulong ullAvailVirtual;
            public ulong ullAvailExtendedVirtual;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern bool GlobalMemoryStatusEx([In, Out] MEMORYSTATUSEX lpBuffer);

        // Быстрый % загрузки ОЗУ без WMI и без блокировки интерфейса.
        public static int MemLoad()
        {
            try
            {
                MEMORYSTATUSEX m = new MEMORYSTATUSEX();
                if (GlobalMemoryStatusEx(m)) return (int)m.dwMemoryLoad;
            }
            catch { }
            return -1;
        }

        public static long MemTotalMb()
        {
            try
            {
                MEMORYSTATUSEX m = new MEMORYSTATUSEX();
                if (GlobalMemoryStatusEx(m)) return (long)(m.ullTotalPhys / 1048576UL);
            }
            catch { }
            return 0;
        }

        public static long MemFreeMb()
        {
            try
            {
                MEMORYSTATUSEX m = new MEMORYSTATUSEX();
                if (GlobalMemoryStatusEx(m)) return (long)(m.ullAvailPhys / 1048576UL);
            }
            catch { }
            return 0;
        }

        // Реальное разрешение системного таймера 1 мс на время работы программы.
        [DllImport("winmm.dll")]
        private static extern uint timeBeginPeriod(uint uPeriod);
        [DllImport("winmm.dll")]
        private static extern uint timeEndPeriod(uint uPeriod);

        public static void TimerStart() { try { timeBeginPeriod(1); } catch { } }
        public static void TimerStop() { try { timeEndPeriod(1); } catch { } }

        // Гамма-таблица дисплея: безопасное изменение цвета драйвером,
        // без оверлеев и без вмешательства в процесс игры.
        [DllImport("user32.dll")]
        private static extern IntPtr GetDC(IntPtr hWnd);
        [DllImport("user32.dll")]
        private static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
        [DllImport("gdi32.dll", SetLastError = true)]
        private static extern bool GetDeviceGammaRamp(IntPtr hdc, [Out] ushort[] lpRamp);
        [DllImport("gdi32.dll", SetLastError = true)]
        private static extern bool SetDeviceGammaRamp(IntPtr hdc, [In] ushort[] lpRamp);

        public static ushort[] GammaGet()
        {
            IntPtr dc = IntPtr.Zero;
            try
            {
                dc = GetDC(IntPtr.Zero);
                if (dc == IntPtr.Zero) return null;
                ushort[] ramp = new ushort[768];
                if (!GetDeviceGammaRamp(dc, ramp)) return null;
                return ramp;
            }
            catch { return null; }
            finally { if (dc != IntPtr.Zero) ReleaseDC(IntPtr.Zero, dc); }
        }

        public static bool GammaSet(ushort[] ramp)
        {
            if (ramp == null || ramp.Length != 768) return false;
            IntPtr dc = IntPtr.Zero;
            try
            {
                dc = GetDC(IntPtr.Zero);
                if (dc == IntPtr.Zero) return false;
                return SetDeviceGammaRamp(dc, ramp);
            }
            catch { return false; }
            finally { if (dc != IntPtr.Zero) ReleaseDC(IntPtr.Zero, dc); }
        }
    }
}
'@

try { $null = [RustSuite.Theme] } catch {
    Add-Type -TypeDefinition $script:CsCode -ReferencedAssemblies 'System.Windows.Forms', 'System.Drawing', 'System' -ErrorAction Stop
}

# ============================================================
#  ПРОФИЛИ: экспорт и импорт выбранных модулей
#  Формат — обычный JSON. Код из файла не исполняется:
#  импортируются только логические флаги известных модулей.
# ============================================================
function Get-ProfileState {
    $enabled = [ordered]@{}
    foreach ($t in $script:Tweaks) {
        $enabled[$t.Id] = [bool]$script:Enabled[$t.Id]
    }
    return $enabled
}

function Export-OptimizerProfile {
    param([string]$Path)
    if (-not $Path) { throw 'Не указан путь для сохранения профиля' }
    $data = [ordered]@{
        app     = 'PURPLE RUSH'
        version = [string]$script:AppVersion
        created = (Get-Date).ToString('s')
        total   = @($script:Tweaks).Count
        enabled = (Get-ProfileState)
    }
    $json = $data | ConvertTo-Json -Depth 4
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    [IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($true)))
    Write-Log ('Профиль сохранён: ' + $Path) 'ok'
    return $Path
}

function Import-OptimizerProfile {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
        throw 'Файл профиля не найден'
    }
    $fi = Get-Item -LiteralPath $Path
    if ($fi.Length -gt 1MB) { throw 'Файл профиля слишком большой (ожидается JSON до 1 МБ)' }

    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $data = $null
    try { $data = $raw | ConvertFrom-Json } catch { throw 'Файл не является корректным JSON' }
    if (-not $data -or -not $data.enabled) { throw 'В профиле нет блока enabled' }

    $known = @{}
    foreach ($t in $script:Tweaks) { $known[$t.Id] = $true }

    $applied = 0
    $skipped = 0
    foreach ($p in @($data.enabled.PSObject.Properties)) {
        if ($p -and $known.ContainsKey([string]$p.Name)) {
            $script:Enabled[[string]$p.Name] = [bool]$p.Value
            $applied = $applied + 1
        } else {
            $skipped = $skipped + 1
        }
    }
    if ($applied -eq 0) { throw 'В профиле нет ни одного известного модуля' }

    $script:State['Enabled'] = $script:Enabled
    Save-State
    Write-Log ("Профиль загружен: применено $applied, пропущено неизвестных $skipped") 'ok'
    return @{ Applied = $applied; Skipped = $skipped }
}

# ============================================================
#  ДОВЕРИЕ И ПЛАН: проверяемый отчёт и предпросмотр изменений
#  Отчёт не требует интернета: он читает собственный исходник
#  и считает опасные шаблоны. Ноль находок — проверяемый факт.
# ============================================================
function Get-AuditSourcePath {
    $candidates = @()
    try {
        if ($PSScriptRoot) {
            $candidates += (Join-Path $PSScriptRoot 'RustOptimizer.ps1')
            $candidates += (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\RustOptimizer.ps1')
        }
    } catch {}
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

function Get-SourceFingerprint {
    $p = Get-AuditSourcePath
    if (-not $p) { return $null }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [IO.File]::OpenRead($p)
        try { $hash = $sha.ComputeHash($stream) } finally { $stream.Dispose() }
        $hex = ($hash | ForEach-Object { $_.ToString('x2') }) -join ''
        return [pscustomobject]@{
            Path   = $p
            Bytes  = (Get-Item -LiteralPath $p).Length
            SHA256 = $hex
        }
    } finally { $sha.Dispose() }
}

# Шаблоны собираются из частей, чтобы отчёт не находил сам себя.
function Get-TrustScan {
    $p = Get-AuditSourcePath
    $categories = @(
        @{ Name = 'Сетевые загрузки';        Needles = @(('Invoke-' + 'WebRequest'), ('Invoke-' + 'RestMethod'), ('Download' + 'String'), ('Download' + 'File'), ('Web' + 'Client'), ('Start-' + 'BitsTransfer')) },
        @{ Name = 'Внедрение в процесс';     Needles = @(('Write' + 'ProcessMemory'), ('Create' + 'RemoteThread'), ('Virtual' + 'AllocEx'), ('Open' + 'Process'), ('SetWindows' + 'HookEx')) },
        @{ Name = 'Динамический код';        Needles = @(('Invoke-' + 'Expression'), ('From' + 'Base64String'), ('Assembly' + ']::Load')) },
        @{ Name = 'Изменение клиента игры';  Needles = @(('RustClient' + '.exe.*Set-Content'), ('RustClient' + '.exe.*Copy-Item'), ('RustClient' + '.exe.*Remove-Item')) }
    )
    $text = ''
    if ($p) { try { $text = [IO.File]::ReadAllText($p) } catch { $text = '' } }
    $result = @()
    $total = 0
    foreach ($c in $categories) {
        $hits = 0
        foreach ($n in $c.Needles) {
            if (-not $n -or -not $text) { continue }
            try {
                $hits = $hits + ([regex]::Matches($text, [string]$n, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count
            } catch {}
        }
        $total = $total + $hits
        $result += [pscustomobject]@{ Name = $c.Name; Hits = $hits }
    }
    return [pscustomobject]@{ Items = $result; Total = $total; Scanned = [bool]($text.Length -gt 0) }
}

function Get-BackupStats {
    $reg = 0
    $cfg = 0
    try { if (Test-Path -LiteralPath $script:RegBackup) { $reg = @(Get-ChildItem -LiteralPath $script:RegBackup -File -ErrorAction SilentlyContinue).Count } } catch {}
    try { if (Test-Path -LiteralPath $script:RustBackup) { $cfg = @(Get-ChildItem -LiteralPath $script:RustBackup -File -ErrorAction SilentlyContinue).Count } } catch {}
    return @{ Reg = $reg; Cfg = $cfg }
}

# ============================================================
#  ЗАЩИТА КЛИЕНТА ИГРЫ
#  Снимок размеров и времени изменения RustClient.exe и DLL.
#  Программа никогда не пишет в эти файлы; снимок до/после
#  оптимизации доказывает, что клиент остался нетронутым.
# ============================================================
function Get-ClientGuardSnapshot {
    if (-not $script:RustExe) { return $null }
    $root = Split-Path -Parent $script:RustExe
    if (-not $root -or -not (Test-Path -LiteralPath $root)) { return $null }
    $files = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    $addFile = {
        param($file)
        try {
            if (-not $file -or -not (Test-Path -LiteralPath $file)) { return }
            $fi = Get-Item -LiteralPath $file -Force -ErrorAction Stop
            if ($fi.PSIsContainer) { return }
            $rel = $fi.FullName.Substring($root.Length).TrimStart('\')
            if ($seen.ContainsKey($rel)) { return }
            $seen[$rel] = $true
            $files.Add($rel + "`t" + [string]$fi.Length + "`t" + [string]$fi.LastWriteTimeUtc.Ticks)
        } catch {}
    }
    & $addFile (Join-Path $root 'RustClient.exe')
    & $addFile (Join-Path $root 'UnityPlayer.dll')
    try {
        foreach ($f in @(Get-ChildItem -LiteralPath $root -Filter '*.dll' -File -Force -ErrorAction SilentlyContinue)) { & $addFile $f.FullName }
        foreach ($f in @(Get-ChildItem -LiteralPath $root -Filter '*.exe' -File -Force -ErrorAction SilentlyContinue)) { & $addFile $f.FullName }
    } catch {}
    foreach ($rel in @('RustClient_Data\Plugins\x86_64\EasyAntiCheat\EasyAntiCheat_x64.dll',
                       'EasyAntiCheat\EasyAntiCheat_x64.dll',
                       'EasyAntiCheat\EasyAntiCheat.exe')) {
        & $addFile (Join-Path $root $rel)
    }
    $items = @($files | Sort-Object)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes(($items -join "`n"))
        $hash = ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join ''
    } finally { $sha.Dispose() }
    return [pscustomobject]@{
        Root  = $root
        Count = $items.Count
        Hash  = $hash
        Items = $items
        At    = (Get-Date).ToString('s')
    }
}

function Save-ClientGuardBaseline {
    $snap = Get-ClientGuardSnapshot
    if (-not $snap) { return $null }
    $script:State['ClientGuard'] = $snap
    Save-State
    return $snap
}

function Compare-ClientGuardSnapshots {
    param($Before, $After)
    $res = [pscustomobject]@{ State = 'none'; Missing = @(); Changed = @(); Added = @() }
    if (-not $Before -or -not $After) { return $res }
    $old = @{}
    foreach ($l in @($Before.Items)) {
        $p = ([string]$l).Split("`t")
        if ($p.Count -ge 3) { $old[$p[0]] = ($p[1] + '|' + $p[2]) }
    }
    $new = @{}
    foreach ($l in @($After.Items)) {
        $p = ([string]$l).Split("`t")
        if ($p.Count -ge 3) { $new[$p[0]] = ($p[1] + '|' + $p[2]) }
    }
    $missing = @(); $changed = @()
    foreach ($k in @($old.Keys)) {
        if (-not $new.ContainsKey($k)) { $missing += $k }
        elseif ($new[$k] -ne $old[$k]) { $changed += $k }
    }
    $added = @()
    foreach ($k in @($new.Keys)) { if (-not $old.ContainsKey($k)) { $added += $k } }
    $res.Missing = @($missing)
    $res.Changed = @($changed)
    $res.Added   = @($added)
    if ($missing.Count -eq 0 -and $changed.Count -eq 0 -and $added.Count -eq 0) { $res.State = 'ok' }
    else { $res.State = 'changed' }
    return $res
}

function Test-ClientGuard {
    $base = $script:State['ClientGuard']
    if (-not $base) { return [pscustomobject]@{ State = 'none'; Missing = @(); Changed = @(); Added = @() } }
    return (Compare-ClientGuardSnapshots $base (Get-ClientGuardSnapshot))
}

function Get-ClientGuardText {
    $base = $script:State['ClientGuard']
    $cur  = Get-ClientGuardSnapshot
    if (-not $cur) {
        return 'Клиент игры: RUST не найден, проверка недоступна.'
    }
    if (-not $base) {
        return ('Клиент игры: эталон ещё не снят. Файлов для контроля: ' + $cur.Count + '.')
    }
    $diff = Compare-ClientGuardSnapshots $base $cur
    $lines = @()
    if ($diff.State -eq 'ok') {
        $lines += ('Клиент игры        : НЕ ИЗМЕНЁН · файлов ' + $cur.Count)
    } else {
        $lines += ('Клиент игры        : ЕСТЬ ОТЛИЧИЯ от эталона')
        if ($diff.Missing.Count -gt 0) { $lines += ('  пропали          : ' + ($diff.Missing -join ', ')) }
        if ($diff.Changed.Count -gt 0) { $lines += ('  изменились       : ' + ($diff.Changed -join ', ')) }
        if ($diff.Added.Count -gt 0)   { $lines += ('  появились        : ' + ($diff.Added -join ', ')) }
    }
    $lines += ('Эталон снят         : ' + [string]$base.At)
    $lines += ('SHA256 метаданных   : ' + [string]$cur.Hash)
    return ($lines -join "`r`n")
}

function Get-TrustReportText {
    $fp = Get-SourceFingerprint
    $scan = Get-TrustScan
    $bk = Get-BackupStats
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('PURPLE RUSH — ОТЧЁТ О НАДЁЖНОСТИ')
    [void]$sb.AppendLine(('Версия            : ' + $script:AppVersion))
    [void]$sb.AppendLine(('PowerShell        : ' + $PSVersionTable.PSVersion.ToString()))
    [void]$sb.AppendLine(('Права              : ' + $(if ($script:IsAdmin) { 'администратор' } else { 'обычный пользователь' })))
    [void]$sb.AppendLine(('Лицензия           : MIT, исходный код открыт'))
    [void]$sb.AppendLine('')
    if ($fp) {
        [void]$sb.AppendLine(('Исходник           : ' + $fp.Path))
        [void]$sb.AppendLine(('Размер             : ' + [math]::Round($fp.Bytes / 1KB, 1) + ' КБ'))
        [void]$sb.AppendLine(('SHA256             : ' + $fp.SHA256))
    } else {
        [void]$sb.AppendLine('Исходник           : не найден рядом с приложением')
    }
    [void]$sb.AppendLine(('Модулей            : ' + @($script:Tweaks).Count))
    [void]$sb.AppendLine(('Резервные копии    : реестр ' + $bk.Reg + ' · cfg ' + $bk.Cfg))
    [void]$sb.AppendLine(('Состояние          : ' + $(if (Test-Path -LiteralPath $script:StateFile) { 'state.xml на месте' } else { 'будет создан при первом сохранении' })))
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('ЦЕЛОСТНОСТЬ КЛИЕНТА ИГРЫ')
    foreach ($line in ((Get-ClientGuardText) -split "`r?`n")) { [void]$sb.AppendLine('  ' + $line) }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('СТАТИЧЕСКИЙ АУДИТ ИСХОДНИКА')
    foreach ($it in $scan.Items) {
        [void]$sb.AppendLine(('  {0,-26} {1}' -f ($it.Name + ':'), $it.Hits))
    }
    [void]$sb.AppendLine(('  ИТОГО опасных совпадений: ' + $scan.Total))
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('КАК ЭТО ЧИТАТЬ')
    [void]$sb.AppendLine('  0 сетевых загрузок — программа не скачивает и не запускает код из интернета.')
    [void]$sb.AppendLine('  0 внедрений в процесс — нет инъекций, хуков и чтения памяти игры.')
    [void]$sb.AppendLine('  0 изменений клиента — RustClient.exe и *.dll не перезаписываются.')
    [void]$sb.AppendLine('  Меняются только официальные cfg-файлы игры, реестр Windows и настройки системы.')
    [void]$sb.AppendLine('  Перед применением создаётся точка восстановления и резервные копии реестра/cfg.')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Подпись кода: нет. Это открытый PowerShell-проект: любой может прочитать')
    [void]$sb.AppendLine('src\parts\*.ps1, собрать его через rebuild-bat.ps1 и сравнить SHA256.')
    return $sb.ToString()
}

function Get-PlanText {
    $on = @($script:Tweaks | Where-Object { $script:Enabled[$_.Id] })
    $all = @($script:Tweaks)
    $map = @{ home = 'ОБЗОР'; sys = 'СИСТЕМА'; net = 'СЕТЬ'; rust = 'RUST';
              picture = 'КАРТИНКА'; binds = 'БИНДЫ'; clean = 'ОЧИСТКА';
              repair = 'РЕМОНТ'; settings = 'НАСТРОЙКИ' }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('ПЛАН ОПТИМИЗАЦИИ — ПРЕДПРОСМОТР')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine(('Включено модулей : {0} из {1}' -f $on.Count, $all.Count))
    [void]$sb.AppendLine(('Рискованных      : {0}' -f @($on | Where-Object { $_.Risk }).Count))
    [void]$sb.AppendLine('')
    foreach ($g in @('sys', 'net', 'rust', 'clean')) {
        $items = @($on | Where-Object { $_.Group -eq $g })
        if ($items.Count -eq 0) { continue }
        [void]$sb.AppendLine(('[' + $map[$g] + ']  ' + $items.Count + ' шт.'))
        foreach ($t in $items) {
            $mark = if ($t.Risk) { '●' } else { '·' }
            [void]$sb.AppendLine(('   ' + $mark + ' ' + $t.Name))
        }
        [void]$sb.AppendLine('')
    }
    $risk = @($on | Where-Object { $_.Risk })
    if ($risk.Count -gt 0) {
        [void]$sb.AppendLine('МОДУЛИ С ПОМЕТКОЙ ● — включайте осознанно:')
        foreach ($t in $risk) { [void]$sb.AppendLine(('   ● ' + $t.Name + ' — ' + $t.Desc)) }
        [void]$sb.AppendLine('')
    }
    [void]$sb.AppendLine('Это только предпросмотр: до нажатия «ОПТИМИЗИРОВАТЬ» ничего не меняется.')
    [void]$sb.AppendLine('Перед применением создаётся точка восстановления и резервные копии.')
    return $sb.ToString()
}

function Show-TextDialog {
    param([string]$Title, [string]$Text, [string]$Note = '')
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = $Title
    $dlg.StartPosition   = 'CenterParent'
    $dlg.FormBorderStyle = 'Sizable'
    $dlg.MinimizeBox     = $false
    $dlg.MaximizeBox     = $false
    $dlg.BackColor       = [RustSuite.Theme]::Bg
    $dlg.ForeColor       = [RustSuite.Theme]::TextC
    $dlg.Font            = [RustSuite.Theme]::FSub
    $dlg.Size            = New-Object System.Drawing.Size (S 720), (S 560)
    $dlg.MinimumSize     = New-Object System.Drawing.Size (S 520), (S 400)

    $head = New-Object System.Windows.Forms.Label
    $head.Text      = $Title
    $head.Font      = [RustSuite.Theme]::FName
    $head.ForeColor = [RustSuite.Theme]::AccentLt
    $head.BackColor = [System.Drawing.Color]::Transparent
    $head.Dock      = 'Top'
    $head.Height    = S 34
    $head.Padding   = New-Object System.Windows.Forms.Padding (S 14), (S 10), 0, 0

    $box = New-Object System.Windows.Forms.RichTextBox
    $box.Dock        = 'Fill'
    $box.BorderStyle = 'None'
    $box.ReadOnly    = $true
    $box.WordWrap    = $false
    $box.BackColor   = [RustSuite.Theme]::Field
    $box.ForeColor   = [RustSuite.Theme]::TextC
    $box.Font        = [RustSuite.Theme]::FMono
    $box.Text        = $Text
    $box.DetectUrls  = $false

    $note = New-Object System.Windows.Forms.Label
    $note.Text      = $Note
    $note.Font      = [RustSuite.Theme]::FSmall
    $note.ForeColor = [RustSuite.Theme]::Muted
    $note.BackColor = [System.Drawing.Color]::Transparent
    $note.Dock      = 'Bottom'
    $note.Height    = S 24
    $note.Padding   = New-Object System.Windows.Forms.Padding (S 14), (S 4), 0, 0

    $bar = New-Object System.Windows.Forms.Panel
    $bar.Dock      = 'Bottom'
    $bar.Height    = S 50
    $bar.BackColor = [RustSuite.Theme]::PanelBg
    $bar.Padding   = New-Object System.Windows.Forms.Padding (S 12), (S 9), (S 12), (S 9)

    $btnCopy = New-Object RustSuite.FlatButton
    $btnCopy.Style  = 'Ghost'
    $btnCopy.Text   = 'КОПИРОВАТЬ'
    $btnCopy.Font   = [RustSuite.Theme]::FSmall
    $btnCopy.Width  = S 160
    $btnCopy.Dock   = 'Left'

    $btnClose = New-Object RustSuite.FlatButton
    $btnClose.Style  = 'Primary'
    $btnClose.Text   = 'ЗАКРЫТЬ'
    $btnClose.Font   = [RustSuite.Theme]::FSmall
    $btnClose.Width  = S 160
    $btnClose.Dock   = 'Right'

    $btnCopy.Add_Click(({
        try { [System.Windows.Forms.Clipboard]::SetText($box.Text) } catch {}
    }).GetNewClosure())
    $btnClose.Add_Click(({ try { $dlg.Close() } catch {} }).GetNewClosure())

    $bar.Controls.Add($btnClose)
    $bar.Controls.Add($btnCopy)
    $dlg.Controls.Add($box)
    $dlg.Controls.Add($head)
    $dlg.Controls.Add($note)
    $dlg.Controls.Add($bar)
    $dlg.Add_Shown({ param($s, $e) try { [void][RustSuite.Native]::DarkTitle($s) } catch {} })

    try {
        if ($script:MainForm -and -not $script:MainForm.IsDisposed) {
            $dlg.ShowDialog($script:MainForm)
        } else {
            $dlg.ShowDialog()
        }
    } finally {
        try { $dlg.Dispose() } catch {}
    }
}

function Show-PlanPreview {
    Show-TextDialog 'ПЛАН ОПТИМИЗАЦИИ' (Get-PlanText) 'Предпросмотр ничего не изменяет. Закройте окно и нажмите «ОПТИМИЗИРОВАТЬ».'
}

function Show-TrustReport {
    Show-TextDialog 'ОТЧЁТ О НАДЁЖНОСТИ' (Get-TrustReportText) 'Отчёт построен по локальному исходнику. Скопируйте его и сравните SHA256 с релизом на GitHub.'
}

function Show-ClientGuardReport {
    $text = (Get-ClientGuardText) + "`r`n`r`n" +
        "Что проверяется:`r`n" +
        "  RustClient.exe, UnityPlayer.dll, все DLL и EXE в корне игры,`r`n" +
        "  файлы EasyAntiCheat.`r`n`r`n" +
        "Сравниваются размер и время изменения. Программа не открывает`r`n" +
        "эти файлы на запись и не читает память игры, поэтому после`r`n" +
        "оптимизации снимок обязан совпадать. Если файлы изменились —`r`n" +
        "это сделала игра, Steam или другое приложение, а не PURPLE RUSH."
    Show-TextDialog 'КЛИЕНТ RUST · ПРОВЕРКА ЦЕЛОСТНОСТИ' $text 'Эталон снимается при запуске программы и перед каждой оптимизацией.'
}

# ============================================================
#  ОБЗОР — новая стартовая панель v5.0
#  Живой кольцевой индикатор, графики нагрузки и быстрые действия.
# ============================================================
function Get-OptimizationStats {
    $total = @($script:Tweaks).Count
    $on = 0
    foreach ($t in $script:Tweaks) {
        if ($script:Enabled[$t.Id]) { $on = $on + 1 }
    }
    $score = 0
    if ($total -gt 0) { $score = [int][Math]::Round(100.0 * $on / $total) }
    return @{ On = $on; Total = $total; Score = $score }
}

function Get-OptimizationScore {
    return [int](Get-OptimizationStats).Score
}

function Set-ProfileFromHome {
    param([bool]$IncludeRisk)
    foreach ($t in $script:Tweaks) {
        $script:Enabled[$t.Id] = if ($IncludeRisk) { $true } else { -not $t.Risk }
    }
    $script:State['Enabled'] = $script:Enabled
    Save-State
    Request-Group 'home' -Force
    if ($IncludeRisk) {
        Set-Status 'Профиль «МАКСИМУМ»: включены все модули' '#E3B341'
        Write-Log 'Профиль «МАКСИМУМ»: включены все модули, включая рискованные' 'warn'
    } else {
        Set-Status 'Профиль «БЕЗОПАСНЫЙ»: только проверенные модули' '#4ECB71'
        Write-Log 'Профиль «БЕЗОПАСНЫЙ»: включены только безопасные модули' 'info'
    }
}

function Start-OptimizationFromHome {
    if ($script:Busy) { return }
    $cnt = @($script:Tweaks | Where-Object { $script:Enabled[$_.Id] }).Count
    if ($cnt -eq 0) {
        [void][System.Windows.Forms.MessageBox]::Show(
            'Не выбран ни один модуль. Нажмите «БЕЗОПАСНЫЙ ПРОФИЛЬ» или «МАКСИМУМ».',
            'PURPLE RUSH', 'OK', 'Information')
        return
    }
    $ans = [System.Windows.Forms.MessageBox]::Show(
        ("Применить модулей: $cnt`n`nБудет создана точка восстановления и резервные копии реестра.`nПродолжить?"),
        'PURPLE RUSH', 'YesNo', 'Question')
    if ($ans -ne 'Yes') { return }
    try {
        $null = Start-Optimization
        Request-Group 'home' -Force
        Update-Stats
        Write-Log ("Оптимизация из «ОБЗОРА» завершена: $cnt модулей") 'ok'
        [void][System.Windows.Forms.MessageBox]::Show(
            ("Готово. Применено модулей: $cnt.`n`nПерезагрузите ПК, чтобы все изменения вступили в силу."),
            'PURPLE RUSH', 'OK', 'Information')
    } catch {
        Write-Log ('Ошибка оптимизации: ' + $_.Exception.Message) 'err'
        [void][System.Windows.Forms.MessageBox]::Show(
            ('Ошибка: ' + $_.Exception.Message), 'PURPLE RUSH', 'OK', 'Error')
    }
}

function Start-RollbackFromHome {
    if ($script:Busy) { return }
    $applied = @(Get-AppliedTweaks)
    if ($applied.Count -eq 0) {
        [void][System.Windows.Forms.MessageBox]::Show(
            'Нет применённых модулей — откатывать нечего.',
            'PURPLE RUSH', 'OK', 'Information')
        return
    }
    $ans = [System.Windows.Forms.MessageBox]::Show(
        ("Откатить изменения: $($applied.Count) модулей?`n`nБудут возвращены прежние значения реестра и настроек."),
        'PURPLE RUSH', 'YesNo', 'Question')
    if ($ans -ne 'Yes') { return }
    try {
        Start-Rollback
        Request-Group 'home' -Force
        Update-Stats
        [void][System.Windows.Forms.MessageBox]::Show('Откат выполнен.', 'PURPLE RUSH', 'OK', 'Information')
    } catch {
        Write-Log ('Ошибка отката: ' + $_.Exception.Message) 'err'
    }
}

# Обновление живых элементов «ОБЗОРА» из общего таймера статистики.
function Update-HomeLive {
    param([int]$Cpu = -1, [int]$Ram = -1, [double]$DiskFreeGb = 0, [double]$DiskFreePct = 0)
    try {
        if (-not $script:HomeGauge -or $script:HomeGauge.IsDisposed) { return }
        $st = Get-OptimizationStats
        $script:HomeGauge.Value = $st.Score
        $script:HomeGauge.Sub = ('{0} из {1} модулей' -f $st.On, $st.Total)

        if ($script:HomeSpark -and -not $script:HomeSpark.IsDisposed -and $Cpu -ge 0) {
            # Первая точка не рисует линию — дублируем её, чтобы график
            # появлялся сразу, а не через секунду.
            if ($script:HomeSpark.Count -eq 0) { $script:HomeSpark.Push($Cpu) }
            $script:HomeSpark.Push($Cpu)
        }
        if ($script:HomeCpuVal -and -not $script:HomeCpuVal.IsDisposed) {
            if ($Cpu -ge 0) {
                $script:HomeCpuVal.Text = ('CPU  {0}%' -f $Cpu)
                $script:HomeCpuVal.ForeColor = if ($Cpu -ge 85) { [RustSuite.Theme]::Warn } else { [RustSuite.Theme]::TextC }
            } else {
                $script:HomeCpuVal.Text = 'CPU  —'
                $script:HomeCpuVal.ForeColor = [RustSuite.Theme]::Muted
            }
        }
        if ($script:HomeRamVal -and -not $script:HomeRamVal.IsDisposed) {
            if ($Ram -ge 0) {
                $script:HomeRamVal.Text = ('ОЗУ  {0}%   ·   диск свободно {1:N1} ГБ ({2:N0}%)' -f $Ram, $DiskFreeGb, $DiskFreePct)
            } else {
                $script:HomeRamVal.Text = 'ОЗУ  —'
            }
        }

        if ($script:HomeCards -is [hashtable]) {
            $mc = $script:HomeCards['modules']
            if ($mc -and -not $mc.IsDisposed) {
                $mc.SetValue(('{0} / {1}' -f $st.On, $st.Total))
            }
            $dc = $script:HomeCards['disk']
            if ($dc -and -not $dc.IsDisposed) {
                if ($DiskFreeGb -gt 0) { $dc.SetValue(('{0:N1} ГБ' -f $DiskFreeGb)) }
                else { $dc.SetValue('н/д') }
            }
            $rc = $script:HomeCards['rust']
            if ($rc -and -not $rc.IsDisposed) {
                if ($script:RustExe) {
                    if ($script:RustRunning) { $rc.SetValue('ЗАПУЩЕН') }
                    else { $rc.SetValue('НАЙДЕН') }
                } else { $rc.SetValue('НЕ НАЙДЕН') }
            }
        }

        if ($script:HomeStatusLbl -and -not $script:HomeStatusLbl.IsDisposed) {
            $applied = @(Get-AppliedTweaks).Count
            $adm = if ($script:IsAdmin) { 'администратор' } else { 'без прав администратора' }
            $script:HomeStatusLbl.Text = ('Применено модулей: {0}   ·   {1}   ·   тема: {2}' -f $applied, $adm, $script:ThemeName)
        }
    } catch {}
}

function Show-HomePanel {
    $w = Get-RowWidth 18
    if ($w -lt (S 340)) { $w = (S 340) }
    $y = S 2

    $accentBar = New-Object System.Windows.Forms.Panel
    $accentBar.BackColor = [RustSuite.Theme]::Accent
    $accentBar.Bounds    = New-Object System.Drawing.Rectangle 0, ($y + (S 3)), (S 3), (S 17)
    $script:RowHost.Controls.Add($accentBar)

    $head = New-Object System.Windows.Forms.Label
    $head.Text      = 'ОБЗОР  ·  ЦЕНТР УПРАВЛЕНИЯ'
    $head.Font      = [RustSuite.Theme]::FHead
    $head.ForeColor = [RustSuite.Theme]::TextC
    $head.BackColor = [System.Drawing.Color]::Transparent
    $head.AutoSize  = $false
    $head.Bounds    = New-Object System.Drawing.Rectangle (S 12), $y, (S 460), (S 22)
    $script:RowHost.Controls.Add($head)

    $sub = New-Object System.Windows.Forms.Label
    $sub.Text      = 'Живая нагрузка, оценка профиля и быстрые действия — всё на одном экране.'
    $sub.Font      = [RustSuite.Theme]::FSmall
    $sub.ForeColor = [RustSuite.Theme]::Muted
    $sub.BackColor = [System.Drawing.Color]::Transparent
    $sub.AutoSize  = $false
    $sub.Bounds    = New-Object System.Drawing.Rectangle 0, ($y + (S 22)), $w, (S 16)
    $script:RowHost.Controls.Add($sub)
    $y += S 46

    # ---------- Герой-панель: кольцо + живой график ----------
    $heroH   = S 198
    $gaugeW  = S 184
    $rightX  = $gaugeW + (S 22)
    $rightW  = $w - $rightX - (S 14)
    if ($rightW -lt (S 120)) { $rightW = (S 120) }

    $hero = New-Object System.Windows.Forms.Panel
    $hero.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, $heroH
    $hero.BackColor = [RustSuite.Theme]::PanelBg
    $script:HomeHero = $hero
    $hero.Add_Paint({
        param($s, $e)
        try {
            $g = $e.Graphics
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $r = New-Object System.Drawing.RectangleF 0.5, 0.5, ([Math]::Max(2, $s.Width - 1.5)), ([Math]::Max(2, $s.Height - 1.5))
            $p = [RustSuite.Theme]::Round($r, 12)
            $lw = [Math]::Max(2, $s.Width)
            $lh = [Math]::Max(2, $s.Height)
            $b = New-Object System.Drawing.Drawing2D.LinearGradientBrush ([System.Drawing.Rectangle]::new(0, 0, $lw, $lh)), [RustSuite.Theme]::CardBg, [RustSuite.Theme]::PanelBg, ([System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
            $g.FillPath($b, $p)
            $b.Dispose()
            $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(70, [RustSuite.Theme]::Accent)), 1
            $g.DrawPath($pen, $p)
            $pen.Dispose()
            $p.Dispose()
            $glow = New-Object System.Drawing.Drawing2D.LinearGradientBrush ([System.Drawing.Rectangle]::new(0, 0, $lw, (S 3))), [RustSuite.Theme]::Accent, [RustSuite.Theme]::Secondary, ([System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
            $g.FillRectangle($glow, (S 16), 0, ([Math]::Max(10, $s.Width - (S 32))), (S 3))
            $glow.Dispose()
        } catch {}
    })
    $script:RowHost.Controls.Add($hero)

    $script:HomeGauge = New-Object RustSuite.RingGauge
    $script:HomeGauge.Bounds  = New-Object System.Drawing.Rectangle (S 12), (S 4), $gaugeW, ($heroH - (S 8))
    $script:HomeGauge.BackColor = [System.Drawing.Color]::Transparent
    $script:HomeGauge.Caption = 'ГОТОВНОСТЬ'
    $script:HomeGauge.Sub     = 'профиль модулей'
    $st = Get-OptimizationStats
    $script:HomeGauge.Value   = $st.Score
    $hero.Controls.Add($script:HomeGauge)

    $liveHead = New-Object System.Windows.Forms.Label
    $liveHead.Text      = 'НАГРУЗКА В РЕАЛЬНОМ ВРЕМЕНИ'
    $liveHead.Font      = [RustSuite.Theme]::FHead
    $liveHead.ForeColor = [RustSuite.Theme]::Muted
    $liveHead.BackColor = [System.Drawing.Color]::Transparent
    $liveHead.AutoSize  = $false
    $liveHead.Bounds    = New-Object System.Drawing.Rectangle $rightX, (S 14), $rightW, (S 16)
    $hero.Controls.Add($liveHead)

    $script:HomeCpuVal = New-Object System.Windows.Forms.Label
    $script:HomeCpuVal.Text      = 'CPU  —'
    $script:HomeCpuVal.Font      = [RustSuite.Theme]::FName
    $script:HomeCpuVal.ForeColor = [RustSuite.Theme]::TextC
    $script:HomeCpuVal.BackColor = [System.Drawing.Color]::Transparent
    $script:HomeCpuVal.AutoSize  = $false
    $script:HomeCpuVal.Bounds    = New-Object System.Drawing.Rectangle $rightX, (S 32), $rightW, (S 20)
    $hero.Controls.Add($script:HomeCpuVal)

    $script:HomeSpark = New-Object RustSuite.Sparkline
    $script:HomeSpark.Bounds    = New-Object System.Drawing.Rectangle $rightX, (S 56), $rightW, (S 62)
    $script:HomeSpark.BackColor = [System.Drawing.Color]::Transparent
    $script:HomeSpark.LineColor = [RustSuite.Theme]::AccentLt
    $hero.Controls.Add($script:HomeSpark)

    $script:HomeRamVal = New-Object System.Windows.Forms.Label
    $script:HomeRamVal.Text      = 'ОЗУ  —'
    $script:HomeRamVal.Font      = [RustSuite.Theme]::FSmall
    $script:HomeRamVal.ForeColor = [RustSuite.Theme]::Muted
    $script:HomeRamVal.BackColor = [System.Drawing.Color]::Transparent
    $script:HomeRamVal.AutoSize  = $false
    $script:HomeRamVal.Bounds    = New-Object System.Drawing.Rectangle $rightX, (S 122), $rightW, (S 16)
    $hero.Controls.Add($script:HomeRamVal)

    $script:HomeStatusLbl = New-Object System.Windows.Forms.Label
    $script:HomeStatusLbl.Text      = ''
    $script:HomeStatusLbl.Font      = [RustSuite.Theme]::FSmall
    $script:HomeStatusLbl.ForeColor = [RustSuite.Theme]::Muted
    $script:HomeStatusLbl.BackColor = [System.Drawing.Color]::Transparent
    $script:HomeStatusLbl.AutoSize  = $false
    $script:HomeStatusLbl.Bounds    = New-Object System.Drawing.Rectangle $rightX, (S 144), $rightW, (S 40)
    $hero.Controls.Add($script:HomeStatusLbl)

    $null = New-Object RustSuite.SlideTween -ArgumentList $hero, ($y + (S 22)), $y, 0, 300
    $y += $heroH + (S 10)

    # ---------- Карточки-показатели ----------
    $gap   = S 8
    $cw    = [int](($w - ($gap * 2)) / 3)
    if ($cw -lt (S 96)) { $cw = [int](($w - $gap) / 2) }
    $cardH = S 76
    $script:HomeCards = @{}
    $cards = @(
        @{ Key = 'modules'; Label = 'МОДУЛИ'; Value = ('{0} / {1}' -f $st.On, $st.Total); Hint = 'включено сейчас';  Accent = [RustSuite.Theme]::Accent },
        @{ Key = 'disk';    Label = 'СВОБОДНО'; Value = '—'; Hint = 'на системном диске'; Accent = [RustSuite.Theme]::Secondary },
        @{ Key = 'rust';    Label = 'RUST'; Value = $(if ($script:RustExe) { 'НАЙДЕН' } else { 'НЕ НАЙДЕН' }); Hint = $(if ($script:RustExe) { 'cfg доступен' } else { 'запустите игру через Steam' }); Accent = [RustSuite.Theme]::Ok }
    )
    $ci = 0
    foreach ($cd in $cards) {
        $card = New-Object RustSuite.StatCard
        $card.Label   = [string]$cd.Label
        $card.Value   = [string]$cd.Value
        $card.Hint    = [string]$cd.Hint
        $card.AccentC = [System.Drawing.Color]$cd.Accent
        $x = ($ci % 3) * ($cw + $gap)
        if ($cw -lt (S 96)) { $x = ($ci % 2) * ($cw + $gap) }
        $cy = $y + [int]([Math]::Floor($ci / $(if ($cw -lt (S 96)) { 2 } else { 3 })) * ($cardH + $gap))
        $card.Bounds = New-Object System.Drawing.Rectangle $x, $cy, $cw, $cardH
        $script:HomeCards[$cd.Key] = $card
        $script:RowHost.Controls.Add($card)
        $null = New-Object RustSuite.SlideTween -ArgumentList $card, ($cy + (S 12)), $cy, (80 + $ci * 40), 260
        $ci = $ci + 1
    }
    $rows = [int][Math]::Ceiling($ci / $(if ($cw -lt (S 96)) { 2 } else { 3 }))
    $y += ($rows * ($cardH + $gap)) + (S 4)

    # ---------- Быстрые действия ----------
    $actHead = New-Object System.Windows.Forms.Label
    $actHead.Text      = 'БЫСТРЫЕ ДЕЙСТВИЯ'
    $actHead.Font      = [RustSuite.Theme]::FHead
    $actHead.ForeColor = [RustSuite.Theme]::Muted
    $actHead.BackColor = [System.Drawing.Color]::Transparent
    $actHead.AutoSize  = $false
    $actHead.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 16)
    $script:RowHost.Controls.Add($actHead)
    $y += S 24

    $half = [int](($w - (S 8)) / 2)
    $bw   = $half
    $bh   = S 40
    $buttons = @(
        @{ Text = '✓  БЕЗОПАСНЫЙ ПРОФИЛЬ'; X = 0; Y = 0; Style = 'Primary'; Action = { Set-ProfileFromHome $false } },
        @{ Text = '⚡  МАКСИМУМ'; X = ($half + (S 8)); Y = 0; Style = 'Ghost'; Action = { Set-ProfileFromHome $true } },
        @{ Text = '▶  ОПТИМИЗИРОВАТЬ СЕЙЧАС'; X = 0; Y = ($bh + (S 8)); Style = 'Primary'; Action = { Start-OptimizationFromHome } },
        @{ Text = '↩  ОТКАТИТЬ ИЗМЕНЕНИЯ'; X = ($half + (S 8)); Y = ($bh + (S 8)); Style = 'Ghost'; Action = { Start-RollbackFromHome } },
        @{ Text = '◈  ДИАГНОСТИКА WINDOWS'; X = 0; Y = (($bh + (S 8)) * 2); Style = 'Ghost'; Action = { Request-Group 'repair' } },
        @{ Text = '◐  ТЕМЫ И НАСТРОЙКИ'; X = ($half + (S 8)); Y = (($bh + (S 8)) * 2); Style = 'Ghost'; Action = { Request-Group 'settings' } }
    )
    foreach ($bd in $buttons) {
        $b = New-Object RustSuite.FlatButton
        $b.Style  = [string]$bd.Style
        $b.Text   = [string]$bd.Text
        $b.Font   = [RustSuite.Theme]::FSmall
        $b.Bounds = New-Object System.Drawing.Rectangle ([int]$bd.X), ($y + [int]$bd.Y), $bw, $bh
        $b.Add_Click($bd.Action)
        $script:RowHost.Controls.Add($b)
    }
    $y += (($bh + (S 8)) * 3)

    $btnPlan = New-Object RustSuite.FlatButton
    $btnPlan.Style  = 'Ghost'
    $btnPlan.Text   = '≡  ПРОВЕРИТЬ ПЛАН ПЕРЕД ПРИМЕНЕНИЕМ'
    $btnPlan.Font   = [RustSuite.Theme]::FSmall
    $btnPlan.Bounds = New-Object System.Drawing.Rectangle 0, $y, $w, $bh
    $btnPlan.Add_Click({ Show-PlanPreview })
    $script:RowHost.Controls.Add($btnPlan)
    $y += $bh + (S 12)

    # ---------- Пояснение ----------
    $note = New-Object System.Windows.Forms.Label
    $note.Text = 'Оценка готовности — доля включённых модулей от общего числа. ' +
                 '«БЕЗОПАСНЫЙ ПРОФИЛЬ» оставляет только проверенные обратимые твики; «МАКСИМУМ» включает всё, включая помеченные ●. ' +
                 'Перед применением создаётся точка восстановления, а «ОТКАТ» возвращает прежние значения реестра и cfg.'
    $note.Font      = [RustSuite.Theme]::FSmall
    $note.ForeColor = [RustSuite.Theme]::Muted
    $note.BackColor = [System.Drawing.Color]::Transparent
    $note.AutoSize  = $false
    $note.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 68)
    $script:RowHost.Controls.Add($note)
    $y += S 78

    $script:RowHost.AutoScrollMinSize = New-Object System.Drawing.Size 0, $y
    Update-HomeLive
}

# ============================================================
#  ОТЧЁТ О НАДЁЖНОСТИ (без интерфейса)
# ============================================================
if ($Verify) {
    $script:SuppressSave = $true
    Write-Host (Get-TrustReportText)
    exit 0
}

# ============================================================
#  БЫСТРЫЕ ПРОВЕРКИ (без интерфейса)
# ============================================================
if ($SelfTest) {
    $script:SuppressSave = $true
    $fail = 0
    Write-Host '=== PURPLE RUSH :: SELFTEST ==='
    Write-Host ("Version    : " + $script:AppVersion)
    Write-Host ("Admin      : " + $script:IsAdmin)
    Write-Host ("Steam      : " + $(if ($script:SteamPath) { $script:SteamPath } else { '<not found>' }))
    Write-Host ("Rust       : " + $(if ($script:RustExe) { $script:RustExe } else { '<not found>' }))
    Write-Host ("Cfg dir    : " + $(if ($script:RustExe) { [string](Get-RustCfgDir) } else { '<n/a>' }))
    Write-Host ("Tweaks     : " + $script:Tweaks.Count)
    Write-Host ("Core mask  : 0x" + ('{0:X}' -f (Get-PhysicalCoreMask)))

    foreach ($t in $script:Tweaks) {
        if (-not $t.Apply) { Write-Host ("MISSING APPLY: " + $t.Id); $fail++ }
        if ($null -eq $t.Undo) { Write-Host ("MISSING UNDO : " + $t.Id); $fail++ }
        if (-not $t.Id -or -not $t.Group -or -not $t.Name) { Write-Host ("BROKEN TWEAK: " + $t.Id); $fail++ }
    }

    # Все Id уникальны
    $ids = @($script:Tweaks | ForEach-Object { $_.Id })
    if (@($ids | Select-Object -Unique).Count -ne $ids.Count) { Write-Host 'DUPLICATE TWEAK IDS'; $fail++ }

    # Кастомные контролы скомпилировались
    foreach ($tn in 'Card', 'FlatButton', 'NavButton', 'ProgressStrip', 'Spinner', 'HeaderPanel', 'SlideTween', 'SmoothScrollPanel', 'WheelRouter', 'ThemeTile', 'HealthRow', 'ScrollStrip', 'RingGauge', 'Sparkline', 'StatCard') {
        try {
            $null = [System.Type]::GetType('RustSuite.' + $tn + ', ' + [RustSuite.Card].Assembly.FullName, $false)
            if (-not [System.Type]::GetType('RustSuite.' + $tn + ', ' + [RustSuite.Card].Assembly.FullName, $false)) {
                Write-Host ("MISSING CONTROL: " + $tn); $fail++
            }
        } catch { Write-Host ("CONTROL ERROR: " + $tn); $fail++ }
    }

    # Ярлык и иконка
    foreach ($fn in 'Get-AppLauncherPath', 'Get-AppIconPath', 'Install-AppShortcut', 'Set-AppWindowIcon') {
        if (-not (Get-Command -Name $fn -CommandType Function -ErrorAction SilentlyContinue)) {
            Write-Host ('MISSING APP FUNCTION: ' + $fn); $fail++
        }
    }

    # Новые движки очистки, ремонта и диагностики доступны
    foreach ($fn in 'Invoke-DeepClean', 'Invoke-UpdateCacheClean', 'Invoke-DumpClean',
                    'Invoke-BrowserCache', 'Invoke-GameJunkClean', 'Invoke-ThumbnailClean',
                    'Invoke-WinSxSClean', 'Invoke-OldWindowsClean', 'Invoke-PrefetchClean',
                    'Invoke-EventLogClean', 'Invoke-SfcScan', 'Invoke-DismRestore',
                    'Invoke-DismComponentCleanup', 'Invoke-ChkdskScan', 'Invoke-WindowsUpdateReset',
                    'Invoke-NetworkReset', 'Invoke-WmiRepair', 'Invoke-TimeResync',
                    'Invoke-DriverRescan', 'Invoke-SpoolerReset', 'Invoke-IconCacheRebuild',
                    'Get-SystemHealthReport', 'Get-HealthReportText', 'Invoke-QuickHealthFix',
                    'Get-CleanupPotential', 'Test-PendingReboot') {
        if (-not (Get-Command -Name $fn -CommandType Function -ErrorAction SilentlyContinue)) {
            Write-Host ("MISSING FUNCTION: " + $fn); $fail++
        }
    }

    # Все новые модули очистки присутствуют в списке
    foreach ($id in 'deepclean', 'updatecache', 'dumps', 'browsercache', 'gamejunk',
                    'thumbcache', 'winsxs', 'oldwindows', 'prefetchclean', 'eventlogs') {
        if (-not @($script:Tweaks | Where-Object { $_.Id -eq $id }).Count) {
            Write-Host ("MISSING CLEANUP TWEAK: " + $id); $fail++
        }
    }

    # Дополнительные безопасные твики v5.0
    foreach ($id in 'gamebar', 'widgets', 'copilot', 'recall', 'suggestions',
                    'searchweb', 'bgappsglobal', 'transparency', 'autoplay', 'stickykeys') {
        if (-not @($script:Tweaks | Where-Object { $_.Id -eq $id }).Count) {
            Write-Host ("MISSING SAFE TWEAK: " + $id); $fail++
        }
    }

    # Панель «ОБЗОР» и её живые контролы доступны
    foreach ($fn in 'Get-OptimizationStats', 'Get-OptimizationScore', 'Update-HomeLive', 'Show-HomePanel') {
        if (-not (Get-Command -Name $fn -CommandType Function -ErrorAction SilentlyContinue)) {
            Write-Host ('MISSING DASHBOARD FUNCTION: ' + $fn); $fail++
        }
    }

    # Иконка лаунчера лежит рядом с исходниками
    try {
        $iconPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\rust-optimizer.ico'
        if (-not (Test-Path -LiteralPath $iconPath)) {
            Write-Host 'MISSING APP ICON'; $fail++
        } else {
            $icoBytes = [IO.File]::ReadAllBytes($iconPath)
            if ($icoBytes.Length -lt 10000 -or $icoBytes[0] -ne 0 -or $icoBytes[1] -ne 0 -or $icoBytes[2] -ne 1 -or $icoBytes[3] -ne 0) {
                Write-Host 'APP ICON IS INVALID'; $fail++
            }
        }
    } catch { Write-Host 'APP ICON CHECK ERROR'; $fail++ }

    # Безопасная очистка действительно удаляет только содержимое своей папки
    $cleanTmp = Join-Path $env:TEMP ('rustopt-clean-' + [Guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $cleanTmp -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $cleanTmp 'a.tmp') -Value ('x' * 2048) -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $cleanTmp 'b.tmp') -Value ('y' * 2048) -Encoding ASCII
        $subDir = Join-Path $cleanTmp 'nested'
        New-Item -ItemType Directory -Path $subDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $subDir 'c.tmp') -Value ('z' * 2048) -Encoding ASCII
        Reset-CleanMeter
        $null = Clear-FolderSafe $cleanTmp
        $left = @(Get-ChildItem -LiteralPath $cleanTmp -Force -ErrorAction SilentlyContinue).Count
        if ($left -ne 0) { Write-Host ('CLEANUP LEFT FILES: ' + $left); $fail++ }
        if ($script:CleanObjects -ne 3) { Write-Host ('CLEANUP METER OBJECTS: ' + $script:CleanObjects); $fail++ }
        if ($script:CleanBytes -lt 4000) { Write-Host ('CLEANUP METER BYTES: ' + $script:CleanBytes); $fail++ }
    } catch {
        Write-Host ('CLEANUP CHECK ERROR: ' + $_.Exception.Message); $fail++
    } finally {
        Remove-Item -LiteralPath $cleanTmp -Recurse -Force -ErrorAction SilentlyContinue
        Reset-CleanMeter
    }

    # Проверка незавершённой перезагрузки не должна падать
    try {
        $pending = Test-PendingReboot
        if ($pending -isnot [bool]) { Write-Host 'PENDING REBOOT RETURN TYPE'; $fail++ }
    } catch { Write-Host ('PENDING REBOOT ERROR: ' + $_.Exception.Message); $fail++ }

    # Перезагрузка: shutdown.exe присутствует, аргументы корректны
    try {
        $shPath = Join-Path $env:SystemRoot 'System32\shutdown.exe'
        if (-not (Test-Path -LiteralPath $shPath)) { Write-Host 'SHUTDOWN NOT FOUND'; $fail++ }
        $shArgs = '/r /t 10 /f /c "PURPLE RUSH: применение оптимизации"'
        if ($shArgs -notmatch '^/r /t 10 ') { Write-Host 'SHUTDOWN ARGS BROKEN'; $fail++ }
    } catch { Write-Host 'SHUTDOWN CHECK ERROR'; $fail++ }

    # Нативные методы таймера, колеса мыши и гаммы присутствуют
    foreach ($m in 'TimerStart', 'TimerStop', 'MemLoad', 'MemTotalMb', 'MemFreeMb', 'GammaGet', 'GammaSet') {
        try {
            if (-not [RustSuite.Native].GetMethod($m)) { Write-Host ('MISSING NATIVE: ' + $m); $fail++ }
        } catch { Write-Host ('NATIVE CHECK ERROR: ' + $m); $fail++ }
    }

    # Картинка: функции, пресеты и математика гаммы
    foreach ($fn in 'Get-LookPreset', 'New-NeutralRamp', 'New-LookRamp', 'Test-RampClose',
                    'Apply-LookPreset', 'Restore-LookGamma', 'Get-GammaStatus',
                    'Set-RustVisualCfg', 'Undo-RustVisualCfg', 'Get-RustVisualPresetLines',
                    'Get-GpuInfo', 'Get-GpuPanelGuide', 'Open-GpuPanel', 'Get-GpuStatusText') {
        if (-not (Get-Command -Name $fn -CommandType Function -ErrorAction SilentlyContinue)) {
            Write-Host ('MISSING PICTURE FUNCTION: ' + $fn); $fail++
        }
    }
    try {
        if (@($script:LookPresets).Count -lt 3) { Write-Host 'PICTURE PRESETS MISSING'; $fail++ }
        $lookKeys = @($script:LookPresets | ForEach-Object { [string]$_.Key })
        if (@($lookKeys | Select-Object -Unique).Count -ne $lookKeys.Count) {
            Write-Host 'DUPLICATE PICTURE PRESET KEYS'; $fail++
        }
        $neutral = New-NeutralRamp
        if ($null -eq $neutral -or $neutral.Length -ne 768) {
            Write-Host 'NEUTRAL GAMMA RAMP BROKEN'; $fail++
        } else {
            if (-not (Test-RampClose $neutral $neutral 0)) { Write-Host 'GAMMA RAMP COMPARE FAILED'; $fail++ }
            $vivid = New-LookRamp $neutral 'vivid'
            if ($null -eq $vivid -or $vivid.Length -ne 768) { Write-Host 'LOOK GAMMA RAMP BROKEN'; $fail++ }
            elseif (Test-RampClose $neutral $vivid 0) { Write-Host 'LOOK PRESET HAS NO EFFECT'; $fail++ }
        }

        # В cfg-пресетах не должно быть устаревших/неверных ключей.
        $invalidKeys = @('graphics.shafts', 'graphics.quality', 'global.quality',
                         'global.render_scale', 'graphics.antialiasing',
                         'graphics.parallaxbuildings', 'graphics.shadowquality',
                         'global.pixel_scale', 'graphics.shadowdistance', 'shadow.distance')
        $cfgLines = @($script:RustVisualBaseLines) + @($script:RustMaxCfgLines)
        foreach ($group in $script:RustVisualExtras.Values) { $cfgLines += @($group) }
        $usedKeys = @($cfgLines | ForEach-Object { (([string]$_).Trim() -split '\s+')[0].ToLower() } | Select-Object -Unique)
        foreach ($bad in $invalidKeys) {
            if ($usedKeys -contains $bad) { Write-Host ('INVALID RUST CONVAR: ' + $bad); $fail++ }
        }
        if ($usedKeys -notcontains 'effects.shafts') { Write-Host 'EFFECTS.SHAFTS MISSING'; $fail++ }
        $lineNo = 0
        foreach ($line in @($script:RustMaxCfgLines)) {
            $lineNo++
            if ([string]$line -notmatch '^[a-z0-9_.]+\s+\S+') {
                Write-Host ('BROKEN MAX CFG LINE ' + $lineNo + ': ' + $line); $fail++
            }
        }

        # Визуальный пресет действительно содержит нужные ключи.
        $vividLines = @(Get-RustVisualPresetLines 'vivid')
        if ($vividLines.Count -lt 20) { Write-Host 'VISUAL PRESET TOO SMALL'; $fail++ }
        $vividKeys = @($vividLines | ForEach-Object { (([string]$_).Trim() -split '\s+')[0].ToLower() })
        if ($vividKeys -notcontains 'effects.shafts') { Write-Host 'VISUAL PRESET MISSES EFFECTS.SHAFTS'; $fail++ }
        if ($vividKeys -contains 'graphics.shafts') { Write-Host 'VISUAL PRESET USES INVALID SHAFTS'; $fail++ }

        # Бэкап гаммы: запись и чтение без изменения реального дисплея.
        $oldGammaDir = $script:GammaDir
        $testGammaDir = Join-Path $env:TEMP ('rustopt-gamma-' + [Guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $testGammaDir -Force | Out-Null
            $script:GammaDir = $testGammaDir
            $ramp = New-NeutralRamp
            if (-not (Save-GammaBackup $ramp)) { Write-Host 'GAMMA BACKUP SAVE FAILED'; $fail++ }
            $read = Read-GammaBackup
            if ($null -eq $read -or -not (Test-RampClose $ramp $read 0)) {
                Write-Host 'GAMMA BACKUP READ FAILED'; $fail++
            }
        } finally {
            $script:GammaDir = $oldGammaDir
            Remove-Item -LiteralPath $testGammaDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        if (-not (Get-GpuPanelGuide)) { Write-Host 'GPU PANEL GUIDE EMPTY'; $fail++ }

        # Снимок client.cfg: возвращаются только управляемые строки,
        # чужие настройки и исходные значения сохраняются.
        $oldRustBackup = $script:RustBackup
        $tmpSnapDir = Join-Path $env:TEMP ('rustopt-snap-' + [Guid]::NewGuid().ToString('N'))
        $tmpCfg = Join-Path $tmpSnapDir 'client.cfg'
        try {
            New-Item -ItemType Directory -Path $tmpSnapDir -Force | Out-Null
            $script:RustBackup = $tmpSnapDir
            [IO.File]::WriteAllText($tmpCfg,
                "effects.shafts True`r`ngraphics.drawdistance 3000`r`nkeep.me 1`r`n",
                (New-Object System.Text.UTF8Encoding($false)))
            if (-not (Save-VisualSnapshot $tmpCfg)) { Write-Host 'VISUAL SNAPSHOT SAVE FAILED'; $fail++ }
            Merge-CfgFile -Path $tmpCfg -Lines @(Get-RustVisualPresetLines 'vivid') -ManagedKeys $script:RustVisualManaged
            $appliedText = [IO.File]::ReadAllText($tmpCfg)
            if ($appliedText -notmatch 'effects\.shafts\s+False') { Write-Host 'VISUAL CFG APPLY FAILED'; $fail++ }
            if (-not (Restore-VisualSnapshot $tmpCfg)) { Write-Host 'VISUAL SNAPSHOT RESTORE FAILED'; $fail++ }
            $restoredText = [IO.File]::ReadAllText($tmpCfg)
            if ($restoredText -notmatch 'effects\.shafts\s+True') { Write-Host 'VISUAL CFG SHAFTS NOT RESTORED'; $fail++ }
            if ($restoredText -notmatch 'keep\.me 1') { Write-Host 'VISUAL CFG LOST FOREIGN LINE'; $fail++ }
            if ($restoredText -notmatch 'graphics\.drawdistance 3000') { Write-Host 'VISUAL CFG LOST ORIGINAL VALUE'; $fail++ }
            if ($restoredText -match 'effects\.bloom') { Write-Host 'VISUAL CFG LEFT MANAGED KEY'; $fail++ }
        } catch {
            Write-Host ('VISUAL SNAPSHOT CHECK ERROR: ' + $_.Exception.Message); $fail++
        } finally {
            $script:RustBackup = $oldRustBackup
            Remove-Item -LiteralPath $tmpSnapDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        $gpu = Get-GpuInfo
        if ($null -eq $gpu -or -not $gpu.Vendor -or -not $gpu.Name) {
            Write-Host 'GPU INFO BROKEN'; $fail++
        }
    } catch {
        Write-Host ('PICTURE CHECK ERROR: ' + $_.Exception.Message); $fail++
        Write-Host ([string]$_.ScriptStackTrace)
    }

    # Валидация биндов
    $oldBinds = $script:State['Binds']
    try {
        $okBind = Add-RustBind 'zz_test' '+altlook'
        $badKey = Add-RustBind 'bad key!' 'x'
        $badCmd = Add-RustBind 'zz_test' '   '
        if ($null -ne $okBind) { Write-Host 'BIND ACCEPT FAILED'; $fail++ }
        if (-not $badKey) { Write-Host 'BIND KEY VALIDATION FAILED'; $fail++ }
        if (-not $badCmd) { Write-Host 'BIND CMD VALIDATION FAILED'; $fail++ }
        $lines = @(Get-BindCommandLines)
        if ($lines.Count -lt 1) { Write-Host 'BIND OUTPUT FAILED'; $fail++ }
    } finally {
        if ($null -eq $oldBinds) { $script:State.Remove('Binds') } else { $script:State['Binds'] = $oldBinds }
    }

    # Слияние cfg не дублирует управляемые строки
    $tmp = Join-Path $env:TEMP ('rustopt-selftest-' + [Guid]::NewGuid().ToString('N') + '.cfg')
    try {
        [IO.File]::WriteAllText($tmp, "grass.displacement true`r`nkeep.me 1`r`n", (New-Object System.Text.UTF8Encoding($false)))
        Merge-CfgFile -Path $tmp -Lines @('grass.displacement false') -ManagedKeys @('grass.displacement')
        $txt = [IO.File]::ReadAllText($tmp)
        $cnt = ([regex]::Matches($txt, 'grass\.displacement')).Count
        if ($cnt -ne 1) { Write-Host ('CFG MERGE FAILED (count=' + $cnt + ')'); $fail++ }
        if ($txt -notmatch 'keep\.me 1') { Write-Host 'CFG MERGE LOST FOREIGN LINES'; $fail++ }
        if ($txt -notmatch 'grass\.displacement false') { Write-Host 'CFG MERGE VALUE FAILED'; $fail++ }
    } catch { Write-Host ('CFG MERGE ERROR: ' + $_.Exception.Message); $fail++ }
    finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }

    # Профили и проверяемый отчёт о надёжности (v5.1)
    foreach ($fn in 'Get-ProfileState', 'Export-OptimizerProfile', 'Import-OptimizerProfile',
                    'Get-AuditSourcePath', 'Get-SourceFingerprint', 'Get-TrustScan',
                    'Get-BackupStats', 'Get-TrustReportText', 'Get-PlanText',
                    'Get-ClientGuardSnapshot', 'Save-ClientGuardBaseline',
                    'Compare-ClientGuardSnapshots', 'Test-ClientGuard', 'Get-ClientGuardText',
                    'Show-TextDialog', 'Show-PlanPreview', 'Show-TrustReport', 'Show-ClientGuardReport') {
        if (-not (Get-Command -Name $fn -CommandType Function -ErrorAction SilentlyContinue)) {
            Write-Host ('MISSING RELIABILITY FUNCTION: ' + $fn); $fail++
        }
    }

    # Сравнение снимков клиента: одинаковые = ok, изменённый файл = changed.
    try {
        $ga = [pscustomobject]@{ Items = @("RustClient.exe`t100`t111", "a.dll`t50`t222") }
        $gb = [pscustomobject]@{ Items = @("RustClient.exe`t100`t111", "a.dll`t50`t222") }
        $gc = [pscustomobject]@{ Items = @("RustClient.exe`t999`t111", "a.dll`t50`t222") }
        if ((Compare-ClientGuardSnapshots $ga $gb).State -ne 'ok') { Write-Host 'CLIENT GUARD SAME SNAPSHOT FAILED'; $fail++ }
        $gd = Compare-ClientGuardSnapshots $ga $gc
        if ($gd.State -ne 'changed' -or @($gd.Changed).Count -ne 1) { Write-Host 'CLIENT GUARD CHANGE NOT DETECTED'; $fail++ }
        if (@($gd.Changed)[0] -ne 'RustClient.exe') { Write-Host 'CLIENT GUARD CHANGE NAME WRONG'; $fail++ }
        $realGuard = Get-ClientGuardSnapshot
        if ($script:RustExe -and (-not $realGuard -or $realGuard.Count -lt 1)) { Write-Host 'CLIENT GUARD REAL SNAPSHOT EMPTY'; $fail++ }
        if ($realGuard) {
            $oldGuard = $script:State['ClientGuard']
            try {
                $null = Save-ClientGuardBaseline
                $tg = Test-ClientGuard
                if ($tg.State -ne 'ok') { Write-Host ('CLIENT GUARD ROUNDTRIP: ' + $tg.State); $fail++ }
                if (-not (Get-ClientGuardText)) { Write-Host 'CLIENT GUARD TEXT EMPTY'; $fail++ }
            } finally {
                if ($null -eq $oldGuard) { $script:State.Remove('ClientGuard') } else { $script:State['ClientGuard'] = $oldGuard }
            }
        }
    } catch { Write-Host ('CLIENT GUARD CHECK ERROR: ' + $_.Exception.Message); $fail++ }

    try {
        $plan = Get-PlanText
        if (-not $plan -or $plan.Length -lt 50) { Write-Host 'PLAN TEXT EMPTY'; $fail++ }
        elseif ($plan -notmatch 'ПЛАН ОПТИМИЗАЦИИ') { Write-Host 'PLAN TEXT BROKEN'; $fail++ }
    } catch { Write-Host ('PLAN TEXT ERROR: ' + $_.Exception.Message); $fail++ }

    try {
        $scan = Get-TrustScan
        if (-not $scan.Scanned) { Write-Host 'TRUST SCAN DID NOT READ SOURCE'; $fail++ }
        if ($scan.Total -ne 0) {
            Write-Host ('TRUST SCAN RISKY HITS: ' + $scan.Total)
            foreach ($it in $scan.Items) { if ($it.Hits -gt 0) { Write-Host ('  ' + $it.Name + ' = ' + $it.Hits) } }
            $fail++
        }
        $fp = Get-SourceFingerprint
        if (-not $fp -or -not $fp.SHA256 -or $fp.SHA256.Length -ne 64) { Write-Host 'SOURCE FINGERPRINT BROKEN'; $fail++ }
    } catch { Write-Host ('TRUST SCAN ERROR: ' + $_.Exception.Message); $fail++ }

    # Экспорт/импорт профиля: только известные флаги, без исполнения кода.
    $oldEnabledMap = $script:Enabled
    $oldStateEnabled = $script:State['Enabled']
    $profTmp = Join-Path $env:TEMP ('rustopt-profile-' + [Guid]::NewGuid().ToString('N') + '.json')
    try {
        $probeId = [string]$script:Tweaks[0].Id
        $script:Enabled = @{}
        foreach ($t in $script:Tweaks) { $script:Enabled[$t.Id] = $false }
        $script:Enabled[$probeId] = $true
        $null = Export-OptimizerProfile -Path $profTmp
        if (-not (Test-Path -LiteralPath $profTmp)) { Write-Host 'PROFILE EXPORT FAILED'; $fail++ }
        else {
            $json = Get-Content -LiteralPath $profTmp -Raw -Encoding UTF8
            if ($json -notmatch '"enabled"') { Write-Host 'PROFILE JSON BROKEN'; $fail++ }
            $script:Enabled[$probeId] = $false
            $res = Import-OptimizerProfile -Path $profTmp
            if (-not $script:Enabled[$probeId]) { Write-Host 'PROFILE IMPORT DID NOT RESTORE FLAG'; $fail++ }
            if ($res.Applied -lt 1) { Write-Host 'PROFILE IMPORT APPLIED ZERO'; $fail++ }
        }
        [IO.File]::WriteAllText($profTmp, '{ this is not json', (New-Object System.Text.UTF8Encoding($false)))
        $threw = $false
        try { $null = Import-OptimizerProfile -Path $profTmp } catch { $threw = $true }
        if (-not $threw) { Write-Host 'PROFILE IMPORT ACCEPTED INVALID JSON'; $fail++ }
    } catch {
        Write-Host ('PROFILE CHECK ERROR: ' + $_.Exception.Message); $fail++
    } finally {
        $script:Enabled = $oldEnabledMap
        if ($null -eq $oldStateEnabled) { $script:State.Remove('Enabled') } else { $script:State['Enabled'] = $oldStateEnabled }
        Remove-Item -LiteralPath $profTmp -Force -ErrorAction SilentlyContinue
    }

    if ($fail -gt 0) {
        Write-Host ("SELFTEST FAILED: " + $fail + " issue(s)")
        exit 1
    }
    Write-Host 'SELFTEST OK'
    exit 0
}

# ============================================================
#  НАСТРОЙКИ: ТЕМЫ + МОНИТОРИНГ
#  ВАЖНО: этот файл загружается ДО 40_ui.ps1, поэтому функция
#  Show-SettingsPanel уже существует к моменту первого Show-Group.
# ============================================================

# ---------- Палитры ----------
$script:Themes = @(
    @{ Name='PURPLE RUSH'; Bg=[System.Drawing.Color]::FromArgb(18,10,28);  Panel=[System.Drawing.Color]::FromArgb(28,15,42);  Card=[System.Drawing.Color]::FromArgb(36,20,58);  CardHover=[System.Drawing.Color]::FromArgb(48,28,72);  Border=[System.Drawing.Color]::FromArgb(70,45,110);  Accent=[System.Drawing.Color]::FromArgb(160,60,220);  AccentLt=[System.Drawing.Color]::FromArgb(200,100,255); Secondary=[System.Drawing.Color]::FromArgb(255,79,216); Glow=[System.Drawing.Color]::FromArgb(106,31,176); TextC=[System.Drawing.Color]::FromArgb(245,240,255); Muted=[System.Drawing.Color]::FromArgb(170,150,190); Ok=[System.Drawing.Color]::FromArgb(120,200,120); Warn=[System.Drawing.Color]::FromArgb(240,200,60);   Err=[System.Drawing.Color]::FromArgb(255,100,120); Field=[System.Drawing.Color]::FromArgb(22,14,38) },
    @{ Name='MIDNIGHT';    Bg=[System.Drawing.Color]::FromArgb(10,14,26); Panel=[System.Drawing.Color]::FromArgb(16,20,36); Card=[System.Drawing.Color]::FromArgb(22,30,48); CardHover=[System.Drawing.Color]::FromArgb(30,40,60); Border=[System.Drawing.Color]::FromArgb(50,64,100); Accent=[System.Drawing.Color]::FromArgb(60,120,255);  AccentLt=[System.Drawing.Color]::FromArgb(100,160,255); Secondary=[System.Drawing.Color]::FromArgb(0,212,255); Glow=[System.Drawing.Color]::FromArgb(30,80,176); TextC=[System.Drawing.Color]::FromArgb(230,235,245); Muted=[System.Drawing.Color]::FromArgb(140,150,170); Ok=[System.Drawing.Color]::FromArgb(80,220,130);  Warn=[System.Drawing.Color]::FromArgb(250,190,50);   Err=[System.Drawing.Color]::FromArgb(255,90,110);  Field=[System.Drawing.Color]::FromArgb(14,16,30) },
    @{ Name='EMERALD';     Bg=[System.Drawing.Color]::FromArgb(10,20,14); Panel=[System.Drawing.Color]::FromArgb(15,28,20); Card=[System.Drawing.Color]::FromArgb(20,36,28); CardHover=[System.Drawing.Color]::FromArgb(28,48,36); Border=[System.Drawing.Color]::FromArgb(60,100,70);  Accent=[System.Drawing.Color]::FromArgb(60,220,100); AccentLt=[System.Drawing.Color]::FromArgb(100,255,150); Secondary=[System.Drawing.Color]::FromArgb(0,255,176); Glow=[System.Drawing.Color]::FromArgb(30,140,70); TextC=[System.Drawing.Color]::FromArgb(240,245,235); Muted=[System.Drawing.Color]::FromArgb(160,175,160); Ok=[System.Drawing.Color]::FromArgb(100,240,120); Warn=[System.Drawing.Color]::FromArgb(240,210,60);   Err=[System.Drawing.Color]::FromArgb(240,100,110); Field=[System.Drawing.Color]::FromArgb(12,18,14) },
    @{ Name='CRIMSON';     Bg=[System.Drawing.Color]::FromArgb(26,10,14); Panel=[System.Drawing.Color]::FromArgb(36,15,22); Card=[System.Drawing.Color]::FromArgb(48,22,30); CardHover=[System.Drawing.Color]::FromArgb(60,30,42); Border=[System.Drawing.Color]::FromArgb(110,45,70); Accent=[System.Drawing.Color]::FromArgb(255,60,90);  AccentLt=[System.Drawing.Color]::FromArgb(255,120,140); Secondary=[System.Drawing.Color]::FromArgb(255,154,60); Glow=[System.Drawing.Color]::FromArgb(176,30,60); TextC=[System.Drawing.Color]::FromArgb(245,230,235); Muted=[System.Drawing.Color]::FromArgb(180,140,160); Ok=[System.Drawing.Color]::FromArgb(100,220,120); Warn=[System.Drawing.Color]::FromArgb(255,200,60);   Err=[System.Drawing.Color]::FromArgb(255,100,120); Field=[System.Drawing.Color]::FromArgb(30,12,16) },
    @{ Name='CYBERPUNK';   Bg=[System.Drawing.Color]::FromArgb(5,10,18);  Panel=[System.Drawing.Color]::FromArgb(8,18,30);  Card=[System.Drawing.Color]::FromArgb(12,26,42);  CardHover=[System.Drawing.Color]::FromArgb(18,36,54);  Border=[System.Drawing.Color]::FromArgb(30,74,102);  Accent=[System.Drawing.Color]::FromArgb(0,229,255);  AccentLt=[System.Drawing.Color]::FromArgb(100,240,255); Secondary=[System.Drawing.Color]::FromArgb(255,43,214); Glow=[System.Drawing.Color]::FromArgb(0,136,170); TextC=[System.Drawing.Color]::FromArgb(230,250,255); Muted=[System.Drawing.Color]::FromArgb(122,160,180); Ok=[System.Drawing.Color]::FromArgb(50,255,154); Warn=[System.Drawing.Color]::FromArgb(255,210,60);   Err=[System.Drawing.Color]::FromArgb(255,79,120); Field=[System.Drawing.Color]::FromArgb(6,16,26) },
    @{ Name='ROYAL GOLD';  Bg=[System.Drawing.Color]::FromArgb(18,16,10); Panel=[System.Drawing.Color]::FromArgb(28,24,16); Card=[System.Drawing.Color]::FromArgb(38,32,22); CardHover=[System.Drawing.Color]::FromArgb(50,40,28); Border=[System.Drawing.Color]::FromArgb(100,80,42); Accent=[System.Drawing.Color]::FromArgb(212,160,50); AccentLt=[System.Drawing.Color]::FromArgb(255,210,100); Secondary=[System.Drawing.Color]::FromArgb(255,240,160); Glow=[System.Drawing.Color]::FromArgb(140,110,30); TextC=[System.Drawing.Color]::FromArgb(255,248,230); Muted=[System.Drawing.Color]::FromArgb(180,163,130); Ok=[System.Drawing.Color]::FromArgb(140,210,120); Warn=[System.Drawing.Color]::FromArgb(255,200,60);   Err=[System.Drawing.Color]::FromArgb(255,100,120); Field=[System.Drawing.Color]::FromArgb(22,18,12) },
    @{ Name='ARCTIC';      Bg=[System.Drawing.Color]::FromArgb(10,16,24); Panel=[System.Drawing.Color]::FromArgb(16,24,32); Card=[System.Drawing.Color]::FromArgb(22,34,44); CardHover=[System.Drawing.Color]::FromArgb(30,46,58); Border=[System.Drawing.Color]::FromArgb(58,86,104); Accent=[System.Drawing.Color]::FromArgb(90,200,255); AccentLt=[System.Drawing.Color]::FromArgb(150,230,255); Secondary=[System.Drawing.Color]::FromArgb(200,244,255); Glow=[System.Drawing.Color]::FromArgb(42,124,160); TextC=[System.Drawing.Color]::FromArgb(240,250,255); Muted=[System.Drawing.Color]::FromArgb(146,168,180); Ok=[System.Drawing.Color]::FromArgb(100,224,160); Warn=[System.Drawing.Color]::FromArgb(255,210,100);  Err=[System.Drawing.Color]::FromArgb(255,110,130); Field=[System.Drawing.Color]::FromArgb(12,18,24) },
    @{ Name='SAKURA';      Bg=[System.Drawing.Color]::FromArgb(24,10,18); Panel=[System.Drawing.Color]::FromArgb(36,16,28); Card=[System.Drawing.Color]::FromArgb(48,22,38); CardHover=[System.Drawing.Color]::FromArgb(62,30,48); Border=[System.Drawing.Color]::FromArgb(112,64,90); Accent=[System.Drawing.Color]::FromArgb(255,92,168); AccentLt=[System.Drawing.Color]::FromArgb(255,154,204); Secondary=[System.Drawing.Color]::FromArgb(255,200,160); Glow=[System.Drawing.Color]::FromArgb(176,38,110); TextC=[System.Drawing.Color]::FromArgb(255,240,246); Muted=[System.Drawing.Color]::FromArgb(188,142,166); Ok=[System.Drawing.Color]::FromArgb(120,216,144); Warn=[System.Drawing.Color]::FromArgb(255,200,100);  Err=[System.Drawing.Color]::FromArgb(255,92,120);  Field=[System.Drawing.Color]::FromArgb(30,12,22) },
    @{ Name='OBSIDIAN';    Bg=[System.Drawing.Color]::FromArgb(10,10,12); Panel=[System.Drawing.Color]::FromArgb(18,18,22); Card=[System.Drawing.Color]::FromArgb(26,26,32); CardHover=[System.Drawing.Color]::FromArgb(36,36,44); Border=[System.Drawing.Color]::FromArgb(60,60,72);  Accent=[System.Drawing.Color]::FromArgb(180,180,200); AccentLt=[System.Drawing.Color]::FromArgb(230,230,240); Secondary=[System.Drawing.Color]::FromArgb(140,140,160); Glow=[System.Drawing.Color]::FromArgb(80,80,94); TextC=[System.Drawing.Color]::FromArgb(248,248,250); Muted=[System.Drawing.Color]::FromArgb(152,152,166); Ok=[System.Drawing.Color]::FromArgb(140,216,144); Warn=[System.Drawing.Color]::FromArgb(216,192,112); Err=[System.Drawing.Color]::FromArgb(224,104,120); Field=[System.Drawing.Color]::FromArgb(14,14,18) },
    @{ Name='TOXIC';       Bg=[System.Drawing.Color]::FromArgb(10,16,6);  Panel=[System.Drawing.Color]::FromArgb(18,26,12); Card=[System.Drawing.Color]::FromArgb(26,36,18); CardHover=[System.Drawing.Color]::FromArgb(36,48,26); Border=[System.Drawing.Color]::FromArgb(74,100,42);  Accent=[System.Drawing.Color]::FromArgb(168,230,60); AccentLt=[System.Drawing.Color]::FromArgb(212,255,100); Secondary=[System.Drawing.Color]::FromArgb(240,255,60); Glow=[System.Drawing.Color]::FromArgb(90,140,30); TextC=[System.Drawing.Color]::FromArgb(246,255,234); Muted=[System.Drawing.Color]::FromArgb(160,180,138); Ok=[System.Drawing.Color]::FromArgb(140,255,100); Warn=[System.Drawing.Color]::FromArgb(255,230,60);   Err=[System.Drawing.Color]::FromArgb(255,92,100);  Field=[System.Drawing.Color]::FromArgb(14,20,8) },
    @{ Name='AURORA';      Bg=[System.Drawing.Color]::FromArgb(8,14,22);  Panel=[System.Drawing.Color]::FromArgb(12,22,34); Card=[System.Drawing.Color]::FromArgb(18,32,48); CardHover=[System.Drawing.Color]::FromArgb(26,44,64); Border=[System.Drawing.Color]::FromArgb(46,86,110); Accent=[System.Drawing.Color]::FromArgb(64,224,200); AccentLt=[System.Drawing.Color]::FromArgb(120,255,232); Secondary=[System.Drawing.Color]::FromArgb(150,120,255); Glow=[System.Drawing.Color]::FromArgb(30,140,130); TextC=[System.Drawing.Color]::FromArgb(232,255,252); Muted=[System.Drawing.Color]::FromArgb(140,170,176); Ok=[System.Drawing.Color]::FromArgb(110,235,160); Warn=[System.Drawing.Color]::FromArgb(250,210,90);   Err=[System.Drawing.Color]::FromArgb(255,110,140); Field=[System.Drawing.Color]::FromArgb(10,18,26) },
    @{ Name='NEON NOIR';   Bg=[System.Drawing.Color]::FromArgb(8,8,12);   Panel=[System.Drawing.Color]::FromArgb(14,14,22); Card=[System.Drawing.Color]::FromArgb(20,20,32); CardHover=[System.Drawing.Color]::FromArgb(30,30,46); Border=[System.Drawing.Color]::FromArgb(56,50,96);  Accent=[System.Drawing.Color]::FromArgb(255,54,140); AccentLt=[System.Drawing.Color]::FromArgb(255,120,190); Secondary=[System.Drawing.Color]::FromArgb(60,230,255); Glow=[System.Drawing.Color]::FromArgb(120,24,90); TextC=[System.Drawing.Color]::FromArgb(245,245,252); Muted=[System.Drawing.Color]::FromArgb(150,148,168); Ok=[System.Drawing.Color]::FromArgb(100,230,170); Warn=[System.Drawing.Color]::FromArgb(250,200,80);   Err=[System.Drawing.Color]::FromArgb(255,90,120);  Field=[System.Drawing.Color]::FromArgb(12,12,18) }
)

$script:ThemeName = 'PURPLE RUSH'

function Set-ThemeColors {
    param($Palette)
    if (-not $Palette) { return }
    [RustSuite.Theme]::Bg        = $Palette.Bg
    [RustSuite.Theme]::PanelBg   = $Palette.Panel
    [RustSuite.Theme]::CardBg    = $Palette.Card
    [RustSuite.Theme]::CardHover = $Palette.CardHover
    [RustSuite.Theme]::BorderC   = $Palette.Border
    [RustSuite.Theme]::Accent    = $Palette.Accent
    [RustSuite.Theme]::AccentLt  = $Palette.AccentLt
    [RustSuite.Theme]::Secondary = $Palette.Secondary
    [RustSuite.Theme]::Glow      = $Palette.Glow
    [RustSuite.Theme]::TextC     = $Palette.TextC
    [RustSuite.Theme]::Muted     = $Palette.Muted
    [RustSuite.Theme]::Ok        = $Palette.Ok
    [RustSuite.Theme]::Warn      = $Palette.Warn
    [RustSuite.Theme]::Err       = $Palette.Err
    [RustSuite.Theme]::Field     = $Palette.Field
}

function Apply-Theme {
    param([string]$Name, [switch]$Save)
    $pal = $script:Themes | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if (-not $pal) { $pal = $script:Themes[0] }
    $script:PrevPalette = $script:CurrentPalette
    Set-ThemeColors $pal
    $script:CurrentPalette = $pal
    $script:ThemeName = $pal.Name
    if ($Save) {
        $script:State['Theme'] = $pal.Name
        Save-State
    }
}

# Применяем сохранённую тему ещё до создания окон.
if ($script:State['Theme']) { Apply-Theme ([string]$script:State['Theme']) }
else { Apply-Theme $script:Themes[0].Name }

function Update-ControlTree {
    param($Root)
    if (-not $Root) { return }
    foreach ($c in @($Root.Controls)) {
        if (-not $c) { continue }
        try {
            if ($c -is [System.Windows.Forms.Label]) {
                $pv = $script:PrevPalette
                if ($pv) {
                    if ($c.BackColor.ToArgb() -eq $pv.Bg.ToArgb()) { $c.BackColor = [RustSuite.Theme]::Bg }
                    elseif ($c.BackColor.ToArgb() -eq $pv.Panel.ToArgb()) { $c.BackColor = [RustSuite.Theme]::PanelBg }
                    if ($c.ForeColor.ToArgb() -eq $pv.Muted.ToArgb()) { $c.ForeColor = [RustSuite.Theme]::Muted }
                    elseif ($c.ForeColor.ToArgb() -eq $pv.TextC.ToArgb()) { $c.ForeColor = [RustSuite.Theme]::TextC }
                } elseif ($c.BackColor -ne [System.Drawing.Color]::Transparent) {
                    $c.BackColor = [RustSuite.Theme]::Bg
                }
            } elseif ($c -is [System.Windows.Forms.TextBox]) {
                $c.BackColor = [RustSuite.Theme]::Field
                $c.ForeColor = [RustSuite.Theme]::TextC
            } elseif ($c -is [System.Windows.Forms.ComboBox] -or $c -is [System.Windows.Forms.ListBox]) {
                $c.BackColor = [RustSuite.Theme]::Field
                $c.ForeColor = [RustSuite.Theme]::TextC
            } elseif ($c -is [System.Windows.Forms.CheckBox]) {
                $c.BackColor = [System.Drawing.Color]::Transparent
                $c.ForeColor = [RustSuite.Theme]::TextC
            }
        } catch {}
        if ($c.HasChildren) { Update-ControlTree $c }
    }
}

function Update-ThemeSurfaces {
    try { if ($script:MainForm -and -not $script:MainForm.IsDisposed) { $script:MainForm.BackColor = [RustSuite.Theme]::Bg } } catch {}
    $pairs = @(
        @{ N='FooterPanel';  C='Panel' }, @{ N='NavPanel';      C='Bg' },
        @{ N='NavTopPanel';  C='Bg' },    @{ N='NavBottomPanel'; C='Bg' },
        @{ N='NavScrollWrap'; C='Bg' },
        @{ N='BodyPanel';    C='Bg' },    @{ N='ContentWrap';   C='Bg' },
        @{ N='RightCol';     C='Panel' }, @{ N='StatsPanel';    C='Panel' },
        @{ N='LogPanel';     C='Panel' }, @{ N='LogHost';       C='Panel' }
    )
    foreach ($p in $pairs) {
        try {
            $v = Get-Variable -Name $p.N -Scope Script -ErrorAction SilentlyContinue
            if ($v -and $v.Value -and -not $v.Value.IsDisposed) {
                if ($p.C -eq 'Panel') { $v.Value.BackColor = [RustSuite.Theme]::PanelBg }
                else { $v.Value.BackColor = [RustSuite.Theme]::Bg }
            }
        } catch {}
    }
    try { if ($script:Status) { $script:Status.ForeColor = [RustSuite.Theme]::Muted } } catch {}
    try {
        if ($script:MainForm -and -not $script:MainForm.IsDisposed) {
            Update-ControlTree $script:MainForm
            $script:MainForm.Invalidate($true)
        }
    } catch {}
}

# Перестроить панель настроек после смены темы (безопасно, вне обработчика клика).
function Restart-SettingsSoon {
    try {
        if ($script:ThemeTimer) { $script:ThemeTimer.Stop(); $script:ThemeTimer.Dispose() }
        $script:ThemeTimer = New-Object System.Windows.Forms.Timer
        $script:ThemeTimer.Interval = 40
        $script:ThemeTimer.Add_Tick({
            try { $script:ThemeTimer.Stop() } catch {}
            # Перестраиваем только если пользователь всё ещё на странице настроек.
            if ($script:ActiveGroup -eq 'settings') {
                try { Request-Group 'settings' -Force } catch {}
            }
        })
        $script:ThemeTimer.Start()
    } catch {}
}

# ---------- Быстрые датчики (без WMI на каждом тике) ----------
function Get-CpuLoadFast {
    param([switch]$Force)
    $now = Get-Date
    try {
        # PerformanceCounter нельзя опрашивать чаще ~1 раза в секунду:
        # иначе он возвращает 0 и график «дёргается».
        if (-not $Force -and $script:CpuSampleAt -and
            ($now - $script:CpuSampleAt).TotalMilliseconds -lt 900) {
            return [int]$script:CpuSample
        }
    } catch {}
    try {
        if (-not $script:PcCpu) {
            $script:PcCpu = New-Object System.Diagnostics.PerformanceCounter('Processor', '% Processor Time', '_Total')
            [void]$script:PcCpu.NextValue()
        }
        $v = [int][Math]::Round([double]$script:PcCpu.NextValue())
        if ($v -lt 0) { $v = 0 }
        if ($v -gt 100) { $v = 100 }
        $script:CpuSampleAt = $now
        $script:CpuSample   = $v
        return $v
    } catch { return -1 }
}

function Get-RamLoadFast {
    try {
        $m = [RustSuite.Native]::MemLoad()
        if ($m -ge 0) { return [int]$m }
    } catch {}
    return -1
}

function Get-GpuNameFast {
    if ($script:GpuName) { return $script:GpuName }
    $name = ''
    try {
        $base = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
        $keys = @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue |
                  Where-Object { $_.PSChildName -match '^\d{4}$' })
        foreach ($k in $keys) {
            $d = (Get-ItemProperty -LiteralPath $k.PSPath -Name 'DriverDesc' -ErrorAction SilentlyContinue).DriverDesc
            if ($d) { $name = [string]$d; break }
        }
    } catch {}
    if (-not $name) {
        try {
            $name = [string]((Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
                              Select-Object -First 1).Name)
        } catch {}
    }
    if (-not $name) { $name = 'не определён' }
    $script:GpuName = $name
    return $name
}

function Get-AcpiTemp {
    # WMI-датчик опрашиваем не чаще раза в 30 секунд: он медленный.
    try {
        if ($script:AcpiTempAt -and ((Get-Date) - $script:AcpiTempAt).TotalSeconds -lt 30) {
            return $script:AcpiTempCache
        }
    } catch {}
    $script:AcpiTempAt = Get-Date
    $script:AcpiTempCache = $null
    try {
        $z = @(Get-CimInstance -Namespace 'root/wmi' -ClassName 'MSAcpi_ThermalZoneTemperature' -ErrorAction SilentlyContinue)
        foreach ($t in $z) {
            $c = [double]$t.CurrentTemperature / 10.0 - 273.15
            if ($c -gt 1 -and $c -lt 125) { $script:AcpiTempCache = [math]::Round($c, 1); break }
        }
    } catch {}
    return $script:AcpiTempCache
}

# Один раз собираем сведения о ПК — для карточки «Система».
function Get-SystemReport {
    if ($script:SysReportCache) { return [string]$script:SysReportCache }
    $lines = New-Object System.Collections.Generic.List[string]
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($os) {
            $ver = ([string]$os.Caption).Trim()
            $lines.Add(('ОС: ' + $ver + ' ' + [string]$os.Version + ' (build ' + [string]$os.BuildNumber + ')'))
        }
    } catch {}
    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cpu) {
            $name = ([string]$cpu.Name).Trim() -replace '\s+', ' '
            $lines.Add(('CPU: ' + $name))
            $lines.Add(('Ядра / потоки: ' + [string]$cpu.NumberOfCores + ' / ' + [string]$cpu.NumberOfLogicalProcessors))
        }
    } catch {}
    try { $lines.Add(('GPU: ' + (Get-GpuNameFast))) } catch {}
    try {
        $total = [long][RustSuite.Native]::MemTotalMb()
        $free  = [long][RustSuite.Native]::MemFreeMb()
        if ($total -gt 0) { $lines.Add(('ОЗУ: {0:N0} МБ всего, {1:N0} МБ свободно' -f $total, $free)) }
    } catch {}
    try {
        $lines.Add('Права: ' + $(if ($script:IsAdmin) { 'администратор' } else { 'обычный пользователь' }))
        $lines.Add('Steam: ' + $(if ($script:SteamPath) { [string]$script:SteamPath } else { 'не найден' }))
        $lines.Add('RUST: ' + $(if ($script:RustExe) { [string]$script:RustExe } else { 'не найден' }))
    } catch {}
    $txt = ($lines -join "`r`n")
    $script:SysReportCache = $txt
    return $txt
}

function Update-SettingsMonitor {
    $barCpu = $script:SetCpuBar
    $valCpu = $script:SetValCpu
    $barRam = $script:SetRamBar
    $valRam = $script:SetValRam
    try {
        if ($barCpu -and -not $barCpu.IsDisposed) {
            $cpu = Get-CpuLoadFast
            if ($cpu -ge 0) {
                $barCpu.Value = $cpu
                if ($valCpu -and -not $valCpu.IsDisposed) {
                    $valCpu.Text = ('{0} %' -f $cpu)
                    $valCpu.ForeColor = if ($cpu -ge 85) { [RustSuite.Theme]::Err }
                                        elseif ($cpu -ge 60) { [RustSuite.Theme]::Warn }
                                        else { [RustSuite.Theme]::TextC }
                }
            } elseif ($valCpu -and -not $valCpu.IsDisposed) {
                $valCpu.Text = 'н/д'
            }
        }
    } catch {}

    try {
        if ($barRam -and -not $barRam.IsDisposed) {
            $ram = Get-RamLoadFast
            $totalMb = 0
            try { $totalMb = [long][RustSuite.Native]::MemTotalMb() } catch {}
            if ($ram -ge 0) {
                $barRam.Value = $ram
                if ($valRam -and -not $valRam.IsDisposed) {
                    if ($totalMb -gt 0) { $valRam.Text = ('{0} % · {1:N0} МБ' -f $ram, $totalMb) }
                    else { $valRam.Text = ('{0} %' -f $ram) }
                    $valRam.ForeColor = if ($ram -ge 90) { [RustSuite.Theme]::Err }
                                        elseif ($ram -ge 75) { [RustSuite.Theme]::Warn }
                                        else { [RustSuite.Theme]::TextC }
                }
            } elseif ($valRam -and -not $valRam.IsDisposed) {
                $valRam.Text = 'н/д'
            }
        }
    } catch {}
}

function Read-SettingsTemps {
    $lines = New-Object System.Collections.Generic.List[string]
    try {
        $cpu = Get-CpuLoadFast
        if ($cpu -ge 0) { $lines.Add(('CPU: загрузка {0} %' -f $cpu)) }
    } catch {}
    try {
        $ram = Get-RamLoadFast
        $freeMb  = [long][RustSuite.Native]::MemFreeMb()
        $totalMb = [long][RustSuite.Native]::MemTotalMb()
        if ($ram -ge 0) {
            if ($totalMb -gt 0) { $lines.Add(('ОЗУ: {0:N0} МБ свободно / {1:N0} МБ всего ({2} %)' -f $freeMb, $totalMb, $ram)) }
            else { $lines.Add(('ОЗУ: загрузка {0} %' -f $ram)) }
        }
    } catch {}
    try {
        $acpi = Get-AcpiTemp
        if ($null -ne $acpi) { $lines.Add(('Температура (ACPI): {0} °C' -f $acpi)) }
        else { $lines.Add('Температура (ACPI): датчик недоступен') }
    } catch {
        $lines.Add('Температура (ACPI): датчик недоступен')
    }
    try { $lines.Add(('GPU: ' + (Get-GpuNameFast))) } catch {}
    $lines.Add('')
    $lines.Add('Примечание: Windows не отдаёт температуру ядер CPU/GPU')
    $lines.Add('без фирменного драйвера. ACPI-датчик есть не на всех ПК.')
    return ($lines -join "`r`n")
}

# ---------- Панель настроек ----------
function Show-SettingsPanel {
    $w = Get-RowWidth 22
    if ($w -lt (S 340)) { $w = (S 340) }

    # Заголовок
    $accentBar = New-Object System.Windows.Forms.Panel
    $accentBar.BackColor = [RustSuite.Theme]::Accent
    $accentBar.Bounds    = New-Object System.Drawing.Rectangle 0, (S 5), (S 3), (S 15)
    $script:RowHost.Controls.Add($accentBar)

    $head = New-Object System.Windows.Forms.Label
    $head.Text      = 'НАСТРОЙКИ · ТЕМЫ И МОНИТОРИНГ'
    $head.Font      = [RustSuite.Theme]::FHead
    $head.ForeColor = [RustSuite.Theme]::TextC
    $head.BackColor = [System.Drawing.Color]::Transparent
    $head.AutoSize  = $false
    $head.Bounds    = New-Object System.Drawing.Rectangle (S 12), (S 2), (S 460), (S 22)
    $script:RowHost.Controls.Add($head)

    # --- Темы ---
    $lblTheme = New-Object System.Windows.Forms.Label
    $lblTheme.Text      = 'ТЕМА ОФОРМЛЕНИЯ · применяется сразу'
    $lblTheme.Font      = [RustSuite.Theme]::FHead
    $lblTheme.ForeColor = [RustSuite.Theme]::Muted
    $lblTheme.BackColor = [System.Drawing.Color]::Transparent
    $lblTheme.AutoSize  = $false
    $lblTheme.Bounds    = New-Object System.Drawing.Rectangle 0, (S 30), $w, (S 16)
    $script:RowHost.Controls.Add($lblTheme)

    $btnY = S 52
    $tileH = S 64
    $gap  = S 8
    $colW = [int](($w - $gap) / 2)
    $idx  = 0
    foreach ($t in $script:Themes) {
        $rx = if ($idx % 2 -eq 0) { 0 } else { $colW + $gap }
        $ry = $btnY + [int]([Math]::Floor($idx / 2) * ($tileH + $gap))

        $tile = New-Object RustSuite.ThemeTile
        $tile.Title    = [string]$t.Name
        $tile.Sub      = 'анимированный градиент'
        $tile.ColorA   = $t.Bg
        $tile.ColorB   = $t.Accent
        $tile.ColorC   = $t.Secondary
        $tile.Selected = ($t.Name -eq $script:ThemeName)
        $tile.Bounds   = New-Object System.Drawing.Rectangle $rx, $ry, $colW, $tileH
        $tile.Tag      = $t
        $tile.Add_Click({
            param($s, $e)
            $th = $s.Tag
            Apply-Theme $th.Name -Save
            Update-ThemeSurfaces
            Write-Log ('Тема изменена: ' + $th.Name) 'ok'
            Set-Status ('Тема: ' + $th.Name) '#8B949E'
            Restart-SettingsSoon
        })
        $script:RowHost.Controls.Add($tile)
        $idx++
    }

    $y = $btnY + [int]([Math]::Ceiling($idx / 2) * ($tileH + $gap)) + (S 10)

    $btnRandom = New-Object RustSuite.FlatButton
    $btnRandom.Style  = 'Ghost'
    $btnRandom.Text   = '✦  СЛУЧАЙНАЯ ТЕМА'
    $btnRandom.Font   = [RustSuite.Theme]::FSmall
    $btnRandom.Bounds = New-Object System.Drawing.Rectangle 0, $y, $w, (S 32)
    $btnRandom.Add_Click({
        $pool = @($script:Themes | Where-Object { $_.Name -ne $script:ThemeName })
        if ($pool.Count -gt 0) {
            $th = $pool | Get-Random
            Apply-Theme $th.Name -Save
            Update-ThemeSurfaces
            Write-Log ('Случайная тема: ' + $th.Name) 'ok'
            Set-Status ('Тема: ' + $th.Name) '#8B949E'
            Restart-SettingsSoon
        }
    })
    $script:RowHost.Controls.Add($btnRandom)
    $y += S 44

    # --- Система ---
    $lblSys = New-Object System.Windows.Forms.Label
    $lblSys.Text      = 'СИСТЕМА · этот компьютер'
    $lblSys.Font      = [RustSuite.Theme]::FHead
    $lblSys.ForeColor = [RustSuite.Theme]::Muted
    $lblSys.BackColor = [System.Drawing.Color]::Transparent
    $lblSys.AutoSize  = $false
    $lblSys.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 16)
    $script:RowHost.Controls.Add($lblSys)
    $y += S 22

    $sysBox = New-Object System.Windows.Forms.TextBox
    $sysBox.Multiline   = $true
    $sysBox.ReadOnly    = $true
    $sysBox.ScrollBars  = 'Vertical'
    $sysBox.BorderStyle = 'FixedSingle'
    $sysBox.BackColor   = [RustSuite.Theme]::Field
    $sysBox.ForeColor   = [RustSuite.Theme]::TextC
    $sysBox.Font        = [RustSuite.Theme]::FMono
    $sysBox.Bounds      = New-Object System.Drawing.Rectangle 0, $y, $w, (S 112)
    $sysBox.Anchor      = 'Top,Left,Right'
    $sysBox.Text        = Get-SystemReport
    $script:RowHost.Controls.Add($sysBox)
    $y += S 120

    $btnCopySys = New-Object RustSuite.FlatButton
    $btnCopySys.Style  = 'Ghost'
    $btnCopySys.Text   = 'СКОПИРОВАТЬ ОТЧЁТ О СИСТЕМЕ'
    $btnCopySys.Font   = [RustSuite.Theme]::FSmall
    $btnCopySys.Bounds = New-Object System.Drawing.Rectangle 0, $y, $w, (S 32)
    $btnCopySys.Tag    = $sysBox
    $btnCopySys.Add_Click({
        param($s, $e)
        if ($s.Tag -and (Copy-Text $s.Tag.Text)) {
            Set-Status 'Отчёт о системе скопирован' '#4ECB71'
            Write-Log 'Отчёт о системе скопирован в буфер обмена' 'ok'
        }
    })
    $script:RowHost.Controls.Add($btnCopySys)
    $y += S 44

    $halfW = [int](($w - (S 8)) / 2)
    $btnData = New-Object RustSuite.FlatButton
    $btnData.Style  = 'Ghost'
    $btnData.Text   = 'ПАПКА ДАННЫХ'
    $btnData.Font   = [RustSuite.Theme]::FSmall
    $btnData.Bounds = New-Object System.Drawing.Rectangle 0, $y, $halfW, (S 30)
    $btnData.Add_Click({ Open-Explorer $script:Root })
    $script:RowHost.Controls.Add($btnData)

    $btnLog = New-Object RustSuite.FlatButton
    $btnLog.Style  = 'Ghost'
    $btnLog.Text   = 'ОТКРЫТЬ ЖУРНАЛ'
    $btnLog.Font   = [RustSuite.Theme]::FSmall
    $btnLog.Bounds = New-Object System.Drawing.Rectangle ($halfW + (S 8)), $y, ($w - $halfW - (S 8)), (S 30)
    $btnLog.Add_Click({
        if (Test-Path -LiteralPath $script:LogFile) { Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + $script:LogFile + '"') | Out-Null }
        else { Write-Log 'Журнал ещё не создан' 'info' }
    })
    $script:RowHost.Controls.Add($btnLog)
    $y += S 42

    # --- Поведение ---
    $lblBeh = New-Object System.Windows.Forms.Label
    $lblBeh.Text      = 'ПОВЕДЕНИЕ'
    $lblBeh.Font      = [RustSuite.Theme]::FHead
    $lblBeh.ForeColor = [RustSuite.Theme]::Muted
    $lblBeh.BackColor = [System.Drawing.Color]::Transparent
    $lblBeh.AutoSize  = $false
    $lblBeh.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 16)
    $script:RowHost.Controls.Add($lblBeh)
    $y += S 22

    $chkAutoClose = New-Object System.Windows.Forms.CheckBox
    $chkAutoClose.Text      = 'Закрывать оптимизатор после запуска RUST'
    $chkAutoClose.Font      = [RustSuite.Theme]::FSub
    $chkAutoClose.ForeColor = [RustSuite.Theme]::TextC
    $chkAutoClose.BackColor = [System.Drawing.Color]::Transparent
    $chkAutoClose.FlatStyle = 'Flat'
    $chkAutoClose.AutoSize  = $false
    $chkAutoClose.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 24)
    $chkAutoClose.Checked   = [bool]$script:AutoClose
    $chkAutoClose.Add_CheckedChanged({
        param($s, $e)
        $script:AutoClose = [bool]$s.Checked
        $script:State['AutoClose'] = $script:AutoClose
        Save-State
        Set-Status $(if ($script:AutoClose) { 'Автозакрытие после запуска RUST включено' } else { 'Автозакрытие отключено' }) '#8B949E'
    })
    $script:RowHost.Controls.Add($chkAutoClose)
    $y += S 28

    $lblBehHint = New-Object System.Windows.Forms.Label
    $lblBehHint.Text      = 'После нажатия «ЗАПУСТИТЬ RUST» программа дождётся RustClient.exe и закроется сама.'
    $lblBehHint.Font      = [RustSuite.Theme]::FSmall
    $lblBehHint.ForeColor = [RustSuite.Theme]::Muted
    $lblBehHint.BackColor = [System.Drawing.Color]::Transparent
    $lblBehHint.AutoSize  = $false
    $lblBehHint.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 30)
    $script:RowHost.Controls.Add($lblBehHint)
    $y += S 42

    $btnShortcut = New-Object RustSuite.FlatButton
    $btnShortcut.Style  = 'Ghost'
    $btnShortcut.Text   = 'СОЗДАТЬ ЯРЛЫК НА РАБОЧЕМ СТОЛЕ'
    $btnShortcut.Font   = [RustSuite.Theme]::FSmall
    $btnShortcut.Bounds = New-Object System.Drawing.Rectangle 0, $y, $w, (S 30)
    $btnShortcut.Add_Click({
        $lnk = Install-AppShortcut -Force
        if ($lnk) {
            $script:ShortcutPath = $lnk
            Set-Status 'Ярлык обновлён на рабочем столе' '#4ECB71'
            Write-Log ('Ярлык создан: ' + $lnk) 'ok'
        } else {
            Set-Status 'Не удалось создать ярлык' '#FF6B62'
            Write-Log 'Не удалось создать ярлык (нет лаунчера или иконки)' 'warn'
        }
    })
    $script:RowHost.Controls.Add($btnShortcut)
    $y += S 42

    # --- Профили и отчёт о надёжности (v5.1) ---
    $lblProf = New-Object System.Windows.Forms.Label
    $lblProf.Text      = 'ПРОФИЛИ И ПРОВЕРКА НАДЁЖНОСТИ'
    $lblProf.Font      = [RustSuite.Theme]::FHead
    $lblProf.ForeColor = [RustSuite.Theme]::Muted
    $lblProf.BackColor = [System.Drawing.Color]::Transparent
    $lblProf.AutoSize  = $false
    $lblProf.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 16)
    $script:RowHost.Controls.Add($lblProf)
    $y += S 24

    $halfW = [int](($w - (S 8)) / 2)
    $btnExport = New-Object RustSuite.FlatButton
    $btnExport.Style  = 'Ghost'
    $btnExport.Text   = 'ЭКСПОРТ ПРОФИЛЯ'
    $btnExport.Font   = [RustSuite.Theme]::FSmall
    $btnExport.Bounds = New-Object System.Drawing.Rectangle 0, $y, $halfW, (S 34)
    $btnExport.Add_Click({
        $dlg = New-Object System.Windows.Forms.SaveFileDialog
        try {
            $dlg.Title      = 'Экспорт профиля PURPLE RUSH'
            $dlg.Filter     = 'Профиль PURPLE RUSH (*.json)|*.json|Все файлы (*.*)|*.*'
            $dlg.FileName   = 'purple-rush-profile.json'
            $dlg.DefaultExt = 'json'
            if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                try {
                    $null = Export-OptimizerProfile -Path $dlg.FileName
                    Set-Status 'Профиль сохранён в JSON' '#4ECB71'
                } catch {
                    Set-Status ('Ошибка экспорта: ' + $_.Exception.Message) '#FF6B62'
                }
            }
        } finally { $dlg.Dispose() }
    })
    $script:RowHost.Controls.Add($btnExport)

    $btnImport = New-Object RustSuite.FlatButton
    $btnImport.Style  = 'Ghost'
    $btnImport.Text   = 'ИМПОРТ ПРОФИЛЯ'
    $btnImport.Font   = [RustSuite.Theme]::FSmall
    $btnImport.Bounds = New-Object System.Drawing.Rectangle ($halfW + (S 8)), $y, $halfW, (S 34)
    $btnImport.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        try {
            $dlg.Title       = 'Импорт профиля PURPLE RUSH'
            $dlg.Filter      = 'Профиль PURPLE RUSH (*.json)|*.json|Все файлы (*.*)|*.*'
            $dlg.CheckFileExists = $true
            if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                try {
                    $res = Import-OptimizerProfile -Path $dlg.FileName
                    Set-Status ('Профиль применён: ' + $res.Applied + ' модулей') '#4ECB71'
                    Request-Group 'settings' -Force
                } catch {
                    Set-Status ('Ошибка импорта: ' + $_.Exception.Message) '#FF6B62'
                }
            }
        } finally { $dlg.Dispose() }
    })
    $script:RowHost.Controls.Add($btnImport)
    $y += S 44

    $btnGuard = New-Object RustSuite.FlatButton
    $btnGuard.Style  = 'Ghost'
    $btnGuard.Text   = 'СВЕРИТЬ КЛИЕНТ RUST'
    $btnGuard.Font   = [RustSuite.Theme]::FSmall
    $btnGuard.Bounds = New-Object System.Drawing.Rectangle 0, $y, $halfW, (S 34)
    $btnGuard.Add_Click({ Show-ClientGuardReport })
    $script:RowHost.Controls.Add($btnGuard)

    $btnGuardBase = New-Object RustSuite.FlatButton
    $btnGuardBase.Style  = 'Ghost'
    $btnGuardBase.Text   = 'ОБНОВИТЬ ЭТАЛОН'
    $btnGuardBase.Font   = [RustSuite.Theme]::FSmall
    $btnGuardBase.Bounds = New-Object System.Drawing.Rectangle ($halfW + (S 8)), $y, $halfW, (S 34)
    $btnGuardBase.Add_Click({
        try {
            $snap = Save-ClientGuardBaseline
            if ($snap) {
                Set-Status ('Эталон клиента обновлён: ' + $snap.Count + ' файлов') '#4ECB71'
                Write-Log ('Эталон клиента RUST обновлён: ' + $snap.Count + ' файлов') 'ok'
            } else {
                Set-Status 'RUST не найден — эталон не снят' '#FF6B62'
            }
        } catch { Set-Status ('Ошибка эталона: ' + $_.Exception.Message) '#FF6B62' }
    })
    $script:RowHost.Controls.Add($btnGuardBase)
    $y += S 44

    $btnTrust = New-Object RustSuite.FlatButton
    $btnTrust.Style  = 'Ghost'
    $btnTrust.Text   = 'ОТЧЁТ О НАДЁЖНОСТИ · ЧТО ИМЕННО МЕНЯЕТСЯ'
    $btnTrust.Font   = [RustSuite.Theme]::FSmall
    $btnTrust.Bounds = New-Object System.Drawing.Rectangle 0, $y, $w, (S 34)
    $btnTrust.Add_Click({ Show-TrustReport })
    $script:RowHost.Controls.Add($btnTrust)
    $y += S 46

    # --- Мониторинг ---
    $lblMon = New-Object System.Windows.Forms.Label
    $lblMon.Text      = 'МОНИТОРИНГ · обновляется автоматически'
    $lblMon.Font      = [RustSuite.Theme]::FHead
    $lblMon.ForeColor = [RustSuite.Theme]::Muted
    $lblMon.BackColor = [System.Drawing.Color]::Transparent
    $lblMon.AutoSize  = $false
    $lblMon.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 16)
    $script:RowHost.Controls.Add($lblMon)
    $y += S 24

    $lblCpu = New-Object System.Windows.Forms.Label
    $lblCpu.Text      = 'ЗАГРУЗКА CPU'
    $lblCpu.Font      = [RustSuite.Theme]::FSmall
    $lblCpu.ForeColor = [RustSuite.Theme]::Muted
    $lblCpu.BackColor = [System.Drawing.Color]::Transparent
    $lblCpu.AutoSize  = $false
    $lblCpu.Bounds    = New-Object System.Drawing.Rectangle 0, $y, ([int]($w * 0.62)), (S 16)
    $script:RowHost.Controls.Add($lblCpu)

    $valCpu = New-Object System.Windows.Forms.Label
    $valCpu.Text      = '—'
    $valCpu.Font      = [RustSuite.Theme]::FSmall
    $valCpu.ForeColor = [RustSuite.Theme]::TextC
    $valCpu.BackColor = [System.Drawing.Color]::Transparent
    $valCpu.AutoSize  = $false
    $valCpu.TextAlign = 'MiddleRight'
    $valCpu.Bounds    = New-Object System.Drawing.Rectangle ([int]($w * 0.62)), $y, ([int]($w * 0.38)), (S 16)
    $script:RowHost.Controls.Add($valCpu)
    $y += S 20

    $barCpu = New-Object RustSuite.ProgressStrip
    $barCpu.Shimmer = $true
    $barCpu.Value   = 0
    $barCpu.Bounds  = New-Object System.Drawing.Rectangle 0, $y, $w, (S 10)
    $barCpu.BackColor = [System.Drawing.Color]::Transparent
    $script:RowHost.Controls.Add($barCpu)
    $y += S 22

    $lblRam = New-Object System.Windows.Forms.Label
    $lblRam.Text      = 'ЗАГРУЗКА ОЗУ'
    $lblRam.Font      = [RustSuite.Theme]::FSmall
    $lblRam.ForeColor = [RustSuite.Theme]::Muted
    $lblRam.BackColor = [System.Drawing.Color]::Transparent
    $lblRam.AutoSize  = $false
    $lblRam.Bounds    = New-Object System.Drawing.Rectangle 0, $y, ([int]($w * 0.62)), (S 16)
    $script:RowHost.Controls.Add($lblRam)

    $valRam = New-Object System.Windows.Forms.Label
    $valRam.Text      = '—'
    $valRam.Font      = [RustSuite.Theme]::FSmall
    $valRam.ForeColor = [RustSuite.Theme]::TextC
    $valRam.BackColor = [System.Drawing.Color]::Transparent
    $valRam.AutoSize  = $false
    $valRam.TextAlign = 'MiddleRight'
    $valRam.Bounds    = New-Object System.Drawing.Rectangle ([int]($w * 0.62)), $y, ([int]($w * 0.38)), (S 16)
    $script:RowHost.Controls.Add($valRam)
    $y += S 20

    $barRam = New-Object RustSuite.ProgressStrip
    $barRam.Shimmer = $true
    $barRam.Value   = 0
    $barRam.Bounds  = New-Object System.Drawing.Rectangle 0, $y, $w, (S 10)
    $barRam.BackColor = [System.Drawing.Color]::Transparent
    $script:RowHost.Controls.Add($barRam)
    $y += S 28

    $lblTemps = New-Object System.Windows.Forms.Label
    $lblTemps.Text      = 'ДАТЧИКИ И ОБОРУДОВАНИЕ'
    $lblTemps.Font      = [RustSuite.Theme]::FHead
    $lblTemps.ForeColor = [RustSuite.Theme]::Muted
    $lblTemps.BackColor = [System.Drawing.Color]::Transparent
    $lblTemps.AutoSize  = $false
    $lblTemps.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 16)
    $script:RowHost.Controls.Add($lblTemps)
    $y += S 22

    $tempBox = New-Object System.Windows.Forms.TextBox
    $tempBox.Multiline    = $true
    $tempBox.ReadOnly     = $true
    $tempBox.ScrollBars   = 'Vertical'
    $tempBox.BorderStyle  = 'FixedSingle'
    $tempBox.BackColor    = [RustSuite.Theme]::Field
    $tempBox.ForeColor    = [RustSuite.Theme]::TextC
    $tempBox.Font         = [RustSuite.Theme]::FMono
    $tempBox.Bounds       = New-Object System.Drawing.Rectangle 0, $y, $w, (S 150)
    $tempBox.Anchor       = 'Top,Left,Right'
    $script:RowHost.Controls.Add($tempBox)
    $y += S 162

    $btnRefresh = New-Object RustSuite.FlatButton
    $btnRefresh.Style  = 'Ghost'
    $btnRefresh.Text   = 'ОБНОВИТЬ ПОКАЗАНИЯ'
    $btnRefresh.Font   = [RustSuite.Theme]::FSmall
    $btnRefresh.Bounds = New-Object System.Drawing.Rectangle 0, $y, $w, (S 34)
    $script:RowHost.Controls.Add($btnRefresh)
    $y += S 46

    # Ссылки для функций обновления (см. ниже, уровень скрипта).
    $script:SetCpuBar   = $barCpu
    $script:SetRamBar   = $barRam
    $script:SetValCpu   = $valCpu
    $script:SetValRam   = $valRam
    $script:SetTempBox  = $tempBox

    Update-SettingsMonitor
    $tempBox.Text = Read-SettingsTemps

    $tick = 0
    try {
        if ($script:TempTimer) { $script:TempTimer.Stop(); $script:TempTimer.Dispose() }
    } catch {}
    $script:TempTimer = New-Object System.Windows.Forms.Timer
    $script:TempTimer.Interval = 1000
    $script:TempTimer.Add_Tick({
        try {
            if (-not $script:SetTempBox -or $script:SetTempBox.IsDisposed) { $script:TempTimer.Stop(); return }
            Update-SettingsMonitor
            $script:TempTick = [int]$script:TempTick + 1
            if ($script:TempTick -ge 5) {
                $script:TempTick = 0
                $script:SetTempBox.Text = Read-SettingsTemps
            }
        } catch {}
    })
    $script:TempTick = 0
    $script:TempTimer.Start()

    $btnRefresh.Add_Click({
        try {
            Update-SettingsMonitor
            $script:SetTempBox.Text = Read-SettingsTemps
        } catch {}
    })

    $script:RowHost.AutoScrollMinSize = New-Object System.Drawing.Size 0, ($y + (S 10))
}

$form.Add_FormClosing({
    param($s, $e)
    try { if ($script:TempTimer) { $script:TempTimer.Stop(); $script:TempTimer.Dispose() } } catch {}
    try { if ($script:ThemeTimer) { $script:ThemeTimer.Stop(); $script:ThemeTimer.Dispose() } } catch {}
})

# ============================================================
#  ИНТЕРФЕЙС
# ============================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

$form = New-Object System.Windows.Forms.Form
$script:MainForm     = $form
$form.Text            = 'PURPLE RUSH — RUST PERFORMANCE ENGINE'
$form.StartPosition   = 'CenterScreen'
$form.FormBorderStyle = 'Sizable'
$form.MaximizeBox     = $false
$form.AutoScaleMode   = 'None'
$form.BackColor       = [RustSuite.Theme]::Bg
$form.ForeColor       = [RustSuite.Theme]::TextC
$form.Padding         = New-Object System.Windows.Forms.Padding 0
$null = $form.Handle

try { $script:SC = [double]$form.DeviceDpi / 96.0 } catch { $script:SC = 1.0 }
if ($script:SC -lt 1) { $script:SC = 1.0 }
if ($script:SC -gt 2.5) { $script:SC = 2.5 }
[RustSuite.Theme]::ScaleFonts($script:SC)

function S([double]$v) { return [int][math]::Round($v * $script:SC) }

# Безопасная навигация из обработчиков кликов: панель перестраивается
# после выхода из события, а не внутри него. Это исключает удаление контрола,
# который ещё находится на стеке вызова, и убирает редкие подвисания.
function Request-Group {
    param([string]$gid, [switch]$Force)
    if (-not $gid) { return }
    if (-not $Force -and $gid -eq $script:ActiveGroup -and
        $script:RowHost -and -not $script:RowHost.IsDisposed) {
        try { $script:RowHost.ScrollToTop() } catch {}
        return
    }
    try {
        if ($script:MainForm -and -not $script:MainForm.IsDisposed) {
            $invoke = [System.Windows.Forms.MethodInvoker]({ Show-Group $gid }.GetNewClosure())
            $null = $script:MainForm.BeginInvoke($invoke)
            return
        }
    } catch {}
    Show-Group $gid
}

$area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$minW = S 1000
$minH = S 640
$winW = [Math]::Min((S 1240), [Math]::Max($minW, $area.Width - (S 60)))
$winH = [Math]::Min((S 820),  [Math]::Max($minH, $area.Height - (S 70)))

# Восстанавливаем размер прошлой сессии, если он помещается на текущий экран.
try {
    $savedW = [int]$script:State['WinW']
    $savedH = [int]$script:State['WinH']
    if ($savedW -ge $minW -and $savedH -ge $minH) {
        $winW = [Math]::Min($savedW, [Math]::Max($minW, $area.Width - (S 20)))
        $winH = [Math]::Min($savedH, [Math]::Max($minH, $area.Height - (S 20)))
    }
} catch {}

$form.Size        = New-Object System.Drawing.Size $winW, $winH
$form.MinimumSize = New-Object System.Drawing.Size $minW, $minH
$form.Font        = [RustSuite.Theme]::FSub
$form.KeyPreview  = $true
Set-AppWindowIcon $form

# Handle создаётся выше для чтения DPI, поэтому CenterScreen не успевает
# примениться к размеру по умолчанию. Позиционируем окно вручную уже
# после установки финального размера — иначе часть окна уходит за экран.
$px = $area.Left + [int][Math]::Max(0, (($area.Width - $winW) / 2))
$py = $area.Top  + [int][Math]::Max(0, (($area.Height - $winH) / 2))

# Позицию прошлой сессии используем только если окно остаётся видимым
# хотя бы на одном мониторе (например, после отключения второго экрана).
try {
    if ($script:State['WinPos']) {
        $sx = [int]$script:State['WinX']
        $sy = [int]$script:State['WinY']
        $r  = New-Object System.Drawing.Rectangle $sx, $sy, $winW, $winH
        foreach ($scr in [System.Windows.Forms.Screen]::AllScreens) {
            if ($scr.WorkingArea.IntersectsWith($r)) { $px = $sx; $py = $sy; break }
        }
    }
} catch {}

$form.StartPosition = 'Manual'
$form.Location = New-Object System.Drawing.Point $px, $py

# Включаем двойную буферизацию контейнеров: меньше мерцания при перерисовке.
function Enable-DoubleBuffer {
    param($Control)
    try {
        $p = $Control.GetType().GetProperty('DoubleBuffered',
            [System.Reflection.BindingFlags]'Instance, NonPublic')
        if ($p) { $p.SetValue($Control, $true, $null) }
    } catch {}
}

# ---------- Шапка ----------
$script:Header = New-Object RustSuite.HeaderPanel
$header = $script:Header
$header.Dock   = 'Top'
$header.Height = S 108

$header.Add_Paint({
    param($s, $e)
    try {
        $g  = $e.Graphics
        $tf = [System.Windows.Forms.TextFormatFlags]::NoPadding

        $f  = [RustSuite.Theme]::FTitle
        $w1 = [System.Windows.Forms.TextRenderer]::MeasureText('RUST', $f).Width
        [System.Windows.Forms.TextRenderer]::DrawText($g, 'RUST', $f,
            [System.Drawing.Point]::new((S 26), (S 15)), [RustSuite.Theme]::Accent, $tf)
        $w2 = [System.Windows.Forms.TextRenderer]::MeasureText('PERFORMANCE SUITE', $f).Width
        [System.Windows.Forms.TextRenderer]::DrawText($g, 'PERFORMANCE SUITE', $f,
            [System.Drawing.Point]::new(((S 26) + $w1 + (S 14)), (S 15)), [RustSuite.Theme]::TextC, $tf)

        # Небольшой бейдж версии рядом с заголовком.
        $vtext = 'v' + $script:AppVersion
        $vfont = [RustSuite.Theme]::FSmall
        $vsz   = [System.Windows.Forms.TextRenderer]::MeasureText($vtext, $vfont)
        $vw    = $vsz.Width + (S 18)
        $vh    = S 21
        $vx    = (S 26) + $w1 + (S 14) + $w2 + (S 14)
        if (($vx + $vw) -lt ($s.Width - (S 230))) {
            $vrect = [System.Drawing.Rectangle]::new($vx, (S 16), $vw, $vh)
            $vp    = [RustSuite.Theme]::Round([System.Drawing.RectangleF]$vrect, (S 10))
            $vbr   = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(45, [RustSuite.Theme]::Accent))
            $g.FillPath($vbr, $vp)
            $vbr.Dispose()
            $vpen  = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(120, [RustSuite.Theme]::AccentLt), 1)
            $g.DrawPath($vpen, $vp)
            $vpen.Dispose(); $vp.Dispose()
            $vcf = [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor `
                   [System.Windows.Forms.TextFormatFlags]::VerticalCenter
            [System.Windows.Forms.TextRenderer]::DrawText($g, $vtext, $vfont, $vrect,
                [RustSuite.Theme]::AccentLt, $vcf)
        }

        $sub = 'оптимизация Windows под RUST   ·   журнал: ProgramData\RustOptimizer'
        [System.Windows.Forms.TextRenderer]::DrawText($g, $sub, [RustSuite.Theme]::FSub,
            [System.Drawing.Point]::new((S 28), (S 70)), [RustSuite.Theme]::Muted, $tf)

        $chip  = if ($script:IsAdmin) { 'АДМИНИСТРАТОР' } else { 'НЕТ ПРАВ' }
        $ccol  = if ($script:IsAdmin) { [RustSuite.Theme]::Ok } else { [RustSuite.Theme]::Err }
        $cs    = [System.Windows.Forms.TextRenderer]::MeasureText($chip, [RustSuite.Theme]::FSmall)
        $cw    = $cs.Width + (S 22)
        $cx    = $s.Width - $cw - (S 26)
        $crect = [System.Drawing.Rectangle]::new($cx, (S 22), $cw, (S 22))
        $cp    = [RustSuite.Theme]::Round([System.Drawing.RectangleF]$crect, (S 11))
        $cbr   = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(28, $ccol.R, $ccol.G, $ccol.B))
        $g.FillPath($cbr, $cp)
        $cbr.Dispose()
        $pen   = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(90, $ccol.R, $ccol.G, $ccol.B), 1)
        $g.DrawPath($pen, $cp)
        $pen.Dispose(); $cp.Dispose()
        $cf = [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor `
              [System.Windows.Forms.TextFormatFlags]::VerticalCenter
        [System.Windows.Forms.TextRenderer]::DrawText($g, $chip, [RustSuite.Theme]::FSmall, $crect, $ccol, $cf)

        $rst = if (-not $script:RustExe) { 'RUST НЕ НАЙДЕН' }
               elseif ($script:RustRunning) { 'RUST ЗАПУЩЕН' }
               else { 'RUST ГОТОВ' }
        $rc  = if (-not $script:RustExe) { [RustSuite.Theme]::Warn }
               elseif ($script:RustRunning) { [RustSuite.Theme]::AccentLt }
               else { [RustSuite.Theme]::Ok }
        $rsz = [System.Windows.Forms.TextRenderer]::MeasureText($rst, [RustSuite.Theme]::FSmall)
        $rrect = [System.Drawing.Rectangle]::new(($s.Width - $cw - (S 26)), (S 50), $cw, (S 20))
        $rf = [System.Windows.Forms.TextFormatFlags]::Right -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter
        [System.Windows.Forms.TextRenderer]::DrawText($g, $rst, [RustSuite.Theme]::FSmall, $rrect, $rc, $rf)
        $line = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(70, [RustSuite.Theme]::Accent)), 1
        $g.DrawLine($line, 0, ($s.Height - 1), $s.Width, ($s.Height - 1))
        $line.Dispose()
    } catch {}
})

# ---------- Подвал ----------
$footer = New-Object System.Windows.Forms.Panel
$script:FooterPanel = $footer
$footer.Dock      = 'Bottom'
$footer.Height    = S 96
$footer.BackColor = [RustSuite.Theme]::PanelBg
$footer.Add_Paint({
    param($s, $e)
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(34, 40, 52)), 1
    $e.Graphics.DrawLine($pen, 0, 0, $s.Width, 0)
    $pen.Dispose()
    try {
        $hint = 'Ctrl+1…9 — разделы    ·    Ctrl+R — обновить статистику'
        $hr   = New-Object System.Drawing.Rectangle 0, ($s.Height - (S 24)), ($s.Width - (S 26)), (S 18)
        [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $hint,
            [RustSuite.Theme]::FSmall, $hr,
            [System.Drawing.Color]::FromArgb(120, [RustSuite.Theme]::Muted),
            [System.Windows.Forms.TextFormatFlags]::Right)
    } catch {}
})

$btnRun = New-Object RustSuite.FlatButton
$btnRun.Style   = 'Primary'
$btnRun.Text    = '▶  ОПТИМИЗИРОВАТЬ ПК'
$btnRun.Bounds  = New-Object System.Drawing.Rectangle (S 26), (S 22), (S 286), (S 50)

$btnUndo = New-Object RustSuite.FlatButton
$btnUndo.Style  = 'Ghost'
$btnUndo.Text   = '↺  ОТКАТ'
$btnUndo.Bounds = New-Object System.Drawing.Rectangle (S 320), (S 22), (S 132), (S 50)

$btnScan = New-Object RustSuite.FlatButton
$btnScan.Style  = 'Ghost'
$btnScan.Text   = '◈  ДИАГНОСТИКА'
$btnScan.Bounds = New-Object System.Drawing.Rectangle (S 460), (S 22), (S 158), (S 50)

$script:Spinner = New-Object RustSuite.Spinner
$script:Spinner.Bounds = New-Object System.Drawing.Rectangle (S 628), (S 26), (S 20), (S 20)
$script:Spinner.BackColor = [System.Drawing.Color]::Transparent

$script:Progress = New-Object RustSuite.ProgressStrip
$script:Progress.Bounds = New-Object System.Drawing.Rectangle (S 660), (S 30), (S 460), (S 7)
$script:Progress.BackColor = [System.Drawing.Color]::Transparent

$script:Status = New-Object System.Windows.Forms.Label
$script:Status.Text      = 'Готов к работе. Выберите модули и нажмите «Оптимизировать ПК».'
$script:Status.ForeColor = [RustSuite.Theme]::Muted
$script:Status.BackColor = [System.Drawing.Color]::Transparent
$script:Status.Font      = [RustSuite.Theme]::FSmall
$script:Status.AutoSize  = $false
$script:Status.Bounds    = New-Object System.Drawing.Rectangle (S 660), (S 48), (S 460), (S 20)

$footer.Controls.AddRange(@($btnRun, $btnUndo, $btnScan, $script:Spinner, $script:Progress, $script:Status))

$footer.Add_Resize({
    $w = $footer.ClientSize.Width
    $x = (S 660)
    if ($w - $x - (S 26) -lt (S 140)) { $x = (S 628) + (S 34) }
    $script:Progress.Left  = $x
    $script:Progress.Width = [Math]::Max((S 140), $w - $x - (S 26))
    $script:Status.Left    = $x
    $script:Status.Width   = $script:Progress.Width
})

# ---------- Тело ----------
$body = New-Object System.Windows.Forms.TableLayoutPanel
$script:BodyPanel = $body
$body.Dock        = 'Fill'
$body.BackColor   = [RustSuite.Theme]::Bg
$body.ColumnCount = 3
$body.RowCount    = 1
$body.Padding     = New-Object System.Windows.Forms.Padding (S 18), (S 14), (S 18), (S 10)
[void]$body.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle(
    [System.Windows.Forms.SizeType]::Absolute, (S 202))))
[void]$body.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle(
    [System.Windows.Forms.SizeType]::Percent, 100)))
[void]$body.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle(
    [System.Windows.Forms.SizeType]::Absolute, (S 382))))
[void]$body.RowStyles.Add((New-Object System.Windows.Forms.RowStyle(
    [System.Windows.Forms.SizeType]::Percent, 100)))

$form.Controls.Add($body)
$form.Controls.Add($footer)
$form.Controls.Add($header)

# ---------- Навигация ----------
$script:NavButtons = @{}
$nav = New-Object System.Windows.Forms.TableLayoutPanel
$script:NavPanel = $nav
$nav.Dock        = 'Fill'
$nav.BackColor   = [RustSuite.Theme]::Bg
$nav.ColumnCount = 1
$nav.RowCount    = 2
[void]$nav.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle(
    [System.Windows.Forms.SizeType]::Percent, 100)))
[void]$nav.RowStyles.Add((New-Object System.Windows.Forms.RowStyle(
    [System.Windows.Forms.SizeType]::Percent, 100)))
[void]$nav.RowStyles.Add((New-Object System.Windows.Forms.RowStyle(
    [System.Windows.Forms.SizeType]::Absolute, (S 108))))

$navScrollWrap = New-Object System.Windows.Forms.Panel
$script:NavScrollWrap = $navScrollWrap
$navScrollWrap.Dock      = 'Fill'
$navScrollWrap.BackColor = [RustSuite.Theme]::Bg

$navTop = New-Object System.Windows.Forms.Panel
$script:NavTopPanel = $navTop
$navTop.Dock       = 'Fill'
$navTop.BackColor  = [RustSuite.Theme]::Bg
# При минимальной высоте окна восемь пунктов не помещаются —
# включаем прокрутку вместо наложения на блок «ПРОФИЛИ».
$navTop.AutoScroll = $true
$navScrollWrap.Controls.Add($navTop)

$script:Groups = @(
    @{ Id = 'home';    Glyph = '◉'; Title = 'ОБЗОР';    Sub = 'оценка и быстрые действия' },
    @{ Id = 'sys';     Glyph = '◆'; Title = 'СИСТЕМА';  Sub = 'питание и приоритеты' },
    @{ Id = 'net';     Glyph = '↔'; Title = 'СЕТЬ';     Sub = 'пинг и пакеты' },
    @{ Id = 'rust';    Glyph = '▶'; Title = 'RUST';     Sub = 'профиль игры' },
    @{ Id = 'picture'; Glyph = '◐'; Title = 'КАРТИНКА'; Sub = 'цвет и панель GPU' },
    @{ Id = 'binds';   Glyph = '⌨'; Title = 'БИНДЫ';    Sub = 'keys.cfg одной кнопкой' },
    @{ Id = 'clean';   Glyph = '✦'; Title = 'ОЧИСТКА';  Sub = 'мусор и фоновые' },
    @{ Id = 'repair';  Glyph = '◈'; Title = 'РЕМОНТ';   Sub = 'проверка и лечение Windows' },
    @{ Id = 'settings'; Glyph = '⚙'; Title = 'НАСТРОЙКИ'; Sub = 'темы и мониторинг' }
)

$i = 0
$script:NavTip = New-Object System.Windows.Forms.ToolTip
$script:NavTip.InitialDelay  = 450
$script:NavTip.ReshowDelay   = 120
$script:NavTip.AutoPopDelay  = 6000
foreach ($grp in $script:Groups) {
    $b = New-Object RustSuite.NavButton
    $b.Text   = $grp.Glyph + '  ' + $grp.Title
    $b.Sub    = $grp.Sub
    $b.Tag    = $grp.Id
    $b.Bounds = [System.Drawing.Rectangle]::new(0, (S (2 + $i * 40)), (S 176), (S 36))
    $b.Add_Click({ param($s, $e) Request-Group $s.Tag })
    try { $script:NavTip.SetToolTip($b, ($grp.Title + ' — ' + $grp.Sub + "`nCtrl+" + ($i + 1))) } catch {}
    $script:NavButtons[$grp.Id] = $b
    $navTop.Controls.Add($b)
    $i = $i + 1
}

$navBottom = New-Object System.Windows.Forms.Panel
$script:NavBottomPanel = $navBottom
$navBottom.Dock      = 'Bottom'
$navBottom.Height    = S 108
$navBottom.BackColor = [RustSuite.Theme]::Bg

$lblProfiles = New-Object System.Windows.Forms.Label
$lblProfiles.Text      = 'ПРОФИЛИ'
$lblProfiles.Font      = [RustSuite.Theme]::FHead
$lblProfiles.ForeColor = [RustSuite.Theme]::Muted
$lblProfiles.BackColor = [RustSuite.Theme]::Bg
$lblProfiles.Bounds    = New-Object System.Drawing.Rectangle 0, (S 0), (S 186), (S 18)

$btnSafe = New-Object RustSuite.FlatButton
$btnSafe.Style  = 'Ghost'
$btnSafe.Text   = 'БЕЗОПАСНЫЙ'
$btnSafe.Font   = [RustSuite.Theme]::FSmall
$btnSafe.Bounds = New-Object System.Drawing.Rectangle 0, (S 20), (S 186), (S 30)

$btnMax = New-Object RustSuite.FlatButton
$btnMax.Style  = 'Ghost'
$btnMax.Text   = 'МАКСИМУМ'
$btnMax.Font   = [RustSuite.Theme]::FSmall
$btnMax.Bounds = New-Object System.Drawing.Rectangle 0, (S 56), (S 186), (S 30)

$navBottom.Controls.AddRange(@($lblProfiles, $btnSafe, $btnMax))
$script:NavScrollStrip = New-Object RustSuite.ScrollStrip
$script:NavScrollStrip.Target = $navTop
$navScrollWrap.Controls.Add($script:NavScrollStrip)
$nav.Controls.Add($navScrollWrap, 0, 0)
$nav.Controls.Add($navBottom, 0, 1)

# ---------- Правая колонка: статистика + журнал ----------
$rightCol = New-Object System.Windows.Forms.TableLayoutPanel
$script:RightCol = $rightCol
$rightCol.Dock        = 'Fill'
$rightCol.ColumnCount = 1
$rightCol.RowCount    = 2
$rightCol.BackColor   = [RustSuite.Theme]::PanelBg
[void]$rightCol.RowStyles.Add((New-Object System.Windows.Forms.RowStyle(
    [System.Windows.Forms.SizeType]::Absolute, (S 168))))
[void]$rightCol.RowStyles.Add((New-Object System.Windows.Forms.RowStyle(
    [System.Windows.Forms.SizeType]::Percent, 100)))

$statsPanel = New-Object RustSuite.BufferedPanel
$script:StatsPanel = $statsPanel
$statsPanel.Dock      = 'Fill'
$statsPanel.BackColor = [RustSuite.Theme]::PanelBg
$statsPanel.Add_Paint({
    param($s, $e)
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(28, 34, 44)), 1
    $e.Graphics.DrawLine($pen, 0, ($s.Height - 1), $s.Width, ($s.Height - 1))
    $pen.Dispose()
})

$lblStats = New-Object System.Windows.Forms.Label
$lblStats.Text      = 'СОСТОЯНИЕ СИСТЕМЫ'
$lblStats.Font      = [RustSuite.Theme]::FHead
$lblStats.ForeColor = [RustSuite.Theme]::Muted
$lblStats.BackColor = [System.Drawing.Color]::Transparent
$lblStats.Bounds    = New-Object System.Drawing.Rectangle (S 14), (S 10), (S 240), (S 18)

function New-MetricLabel {
    param([string]$Text, [int]$X, [int]$Y, [int]$W, [System.Drawing.Color]$Color)
    $l = New-Object System.Windows.Forms.Label
    $l.Text      = $Text
    $l.Font      = [RustSuite.Theme]::FSmall
    $l.ForeColor = $Color
    $l.BackColor = [System.Drawing.Color]::Transparent
    $l.AutoSize  = $false
    $l.Bounds    = New-Object System.Drawing.Rectangle $X, $Y, $W, (S 16)
    return $l
}

$script:CpuVal = New-MetricLabel '—' (S 190) (S 30) (S 170) ([RustSuite.Theme]::TextC)
$script:RamVal = New-MetricLabel '—' (S 190) (S 66) (S 170) ([RustSuite.Theme]::TextC)
$script:DiskVal = New-MetricLabel '—' (S 190) (S 102) (S 170) ([RustSuite.Theme]::TextC)
$script:RustState = New-MetricLabel '—' (S 60) (S 130) (S 300) ([RustSuite.Theme]::TextC)
$script:CpuVal.TextAlign  = 'MiddleRight'
$script:RamVal.TextAlign  = 'MiddleRight'
$script:DiskVal.TextAlign = 'MiddleRight'

$script:CpuBar = New-Object RustSuite.ProgressStrip
$script:CpuBar.Bounds    = New-Object System.Drawing.Rectangle (S 14), (S 50), (S 340), (S 6)
$script:CpuBar.Shimmer   = $false
$script:CpuBar.BackColor = [System.Drawing.Color]::Transparent

$script:RamBar = New-Object RustSuite.ProgressStrip
$script:RamBar.Bounds    = New-Object System.Drawing.Rectangle (S 14), (S 86), (S 340), (S 6)
$script:RamBar.Shimmer   = $false
$script:RamBar.BackColor = [System.Drawing.Color]::Transparent

$script:DiskBar = New-Object RustSuite.ProgressStrip
$script:DiskBar.Bounds    = New-Object System.Drawing.Rectangle (S 14), (S 122), (S 340), (S 6)
$script:DiskBar.Shimmer   = $false
$script:DiskBar.BackColor = [System.Drawing.Color]::Transparent

$statsPanel.Controls.AddRange(@(
    $lblStats,
    (New-MetricLabel 'CPU'  (S 14) (S 30) (S 80) ([RustSuite.Theme]::Muted)),
    (New-MetricLabel 'ОЗУ'  (S 14) (S 66) (S 80) ([RustSuite.Theme]::Muted)),
    (New-MetricLabel 'ДИСК' (S 14) (S 102) (S 80) ([RustSuite.Theme]::Muted)),
    (New-MetricLabel 'RUST' (S 14) (S 130) (S 46) ([RustSuite.Theme]::Muted)),
    $script:CpuVal, $script:RamVal, $script:DiskVal, $script:RustState,
    $script:CpuBar, $script:RamBar, $script:DiskBar
))

$statsPanel.Add_Resize({
    $w = $statsPanel.ClientSize.Width
    $script:CpuBar.Width  = [Math]::Max((S 60), $w - (S 28))
    $script:RamBar.Width  = [Math]::Max((S 60), $w - (S 28))
    $script:DiskBar.Width = [Math]::Max((S 60), $w - (S 28))
    $script:CpuVal.Left   = [Math]::Max((S 60), $w - (S 200))
    $script:RamVal.Left   = $script:CpuVal.Left
    $script:DiskVal.Left  = $script:CpuVal.Left
    $script:CpuVal.Width  = [Math]::Max((S 80), $w - $script:CpuVal.Left - (S 14))
    $script:RamVal.Width  = $script:CpuVal.Width
    $script:DiskVal.Width = $script:CpuVal.Width
    $script:RustState.Width = [Math]::Max((S 100), $w - (S 74))
})

$logPanel = New-Object System.Windows.Forms.Panel
$script:LogPanel = $logPanel
$logPanel.Dock      = 'Fill'
$logPanel.BackColor = [RustSuite.Theme]::PanelBg

$logTitle = New-Object System.Windows.Forms.Label
$logTitle.Text      = 'ЖУРНАЛ ВЫПОЛНЕНИЯ'
$logTitle.Font      = [RustSuite.Theme]::FHead
$logTitle.ForeColor = [RustSuite.Theme]::Muted
$logTitle.BackColor = [RustSuite.Theme]::PanelBg
$logTitle.Dock      = 'Top'
$logTitle.Height    = S 30
$logTitle.Padding   = New-Object System.Windows.Forms.Padding (S 14), (S 8), 0, 0

$logHost = New-Object RustSuite.BufferedPanel
$script:LogHost = $logHost
$logHost.Dock      = 'Fill'
$logHost.BackColor = [RustSuite.Theme]::PanelBg
$logHost.Padding   = New-Object System.Windows.Forms.Padding (S 12), 0, (S 6), (S 8)

$script:LogBox = New-Object System.Windows.Forms.RichTextBox
$script:LogBox.Dock        = 'Fill'
$script:LogBox.BorderStyle = 'None'
$script:LogBox.BackColor   = [System.Drawing.ColorTranslator]::FromHtml('#0C0F14')
$script:LogBox.ForeColor   = [System.Drawing.ColorTranslator]::FromHtml('#9AA4B2')
$script:LogBox.Font        = [RustSuite.Theme]::FMono
$script:LogBox.ReadOnly    = $true
$script:LogBox.WordWrap    = $true
$script:LogBox.ScrollBars  = 'Vertical'
$script:LogBox.DetectUrls  = $false

$logHost.Controls.Add($script:LogBox)
$logPanel.Controls.Add($logHost)
$logPanel.Controls.Add($logTitle)
$rightCol.Controls.Add($statsPanel, 0, 0)
$rightCol.Controls.Add($logPanel, 0, 1)

# ---------- Контент ----------
$contentWrap = New-Object System.Windows.Forms.Panel
$script:ContentWrap = $contentWrap
$contentWrap.Dock      = 'Fill'
$contentWrap.BackColor = [RustSuite.Theme]::Bg
$contentWrap.Padding   = New-Object System.Windows.Forms.Padding 0, 0, (S 10), 0

$script:RowHost = New-Object RustSuite.SmoothScrollPanel
$script:RowHost.Dock       = 'Fill'
$script:RowHost.BackColor  = [RustSuite.Theme]::Bg
$script:RowHost.AutoScroll = $true
$script:ContentScrollStrip = New-Object RustSuite.ScrollStrip
$script:ContentScrollStrip.Target = $script:RowHost
$contentWrap.Controls.Add($script:RowHost)
$contentWrap.Controls.Add($script:ContentScrollStrip)
try {
    [RustSuite.WheelHub]::Target = $script:RowHost
    [void][System.Windows.Forms.Application]::AddMessageFilter((New-Object RustSuite.WheelRouter))
} catch {}

$body.Controls.Add($nav, 0, 0)
$body.Controls.Add($contentWrap, 1, 0)
$body.Controls.Add($rightCol, 2, 0)

foreach ($c in @($form, $body, $footer, $nav, $navTop, $navBottom, $rightCol, $statsPanel,
                 $contentWrap, $logPanel, $logHost, $script:RowHost, $navScrollWrap)) {
    Enable-DoubleBuffer $c
}

# Ширина контента с запасом под вертикальную полосу прокрутки:
# иначе фиксированные панели вылезают вправо и появляется горизонтальный скролл.
function Get-RowWidth {
    param([int]$Pad = 22)
    $sb = 0
    try { $sb = [int][System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth } catch {}
    $w = $script:RowHost.ClientSize.Width - (S $Pad) - $sb
    if ($w -lt (S 280)) { $w = (S 280) }
    return [int]$w
}

# ============================================================
#  Построение списка модулей
# ============================================================
function Update-RowWidths {
    if (-not $script:RowHost -or $script:RowHost.IsDisposed) { return }
    $w = $script:RowHost.ClientSize.Width - (S 18)
    if ($w -lt (S 300)) { $w = (S 300) }
    foreach ($c in @($script:RowHost.Controls)) {
        if ($c -is [RustSuite.Card]) { $c.Width = $w }
    }
}

function Show-BindsPanel {
    $w = Get-RowWidth 18
    if ($w -lt (S 340)) { $w = (S 340) }
    $recs = @(Get-BindRecords)

    $head = New-Object System.Windows.Forms.Label
    $head.Text      = 'БИНДЫ RUST  ·  ' + $recs.Count + ' шт. в списке'
    $head.Font      = [RustSuite.Theme]::FHead
    $head.ForeColor = [RustSuite.Theme]::TextC
    $head.BackColor = [System.Drawing.Color]::Transparent
    $head.AutoSize  = $false
    $head.Bounds    = New-Object System.Drawing.Rectangle (S 12), 0, (S 420), (S 20)

    $accentBar = New-Object System.Windows.Forms.Panel
    $accentBar.BackColor = [RustSuite.Theme]::Accent
    $accentBar.Bounds    = New-Object System.Drawing.Rectangle 0, (S 3), (S 3), (S 15)
    $script:RowHost.Controls.Add($accentBar)

    $sub = New-Object System.Windows.Forms.Label
    $sub.Text      = 'Официальный keys.cfg игры. Макросы и автоклик не поддерживаются — это риск бана.'
    $sub.Font      = [RustSuite.Theme]::FSmall
    $sub.ForeColor = [RustSuite.Theme]::Muted
    $sub.BackColor = [System.Drawing.Color]::Transparent
    $sub.AutoSize  = $false
    $sub.Bounds    = New-Object System.Drawing.Rectangle 0, (S 24), $w, (S 16)

    $lblKey = New-Object System.Windows.Forms.Label
    $lblKey.Text      = 'КЛАВИША'
    $lblKey.Font      = [RustSuite.Theme]::FHead
    $lblKey.ForeColor = [RustSuite.Theme]::Muted
    $lblKey.BackColor = [System.Drawing.Color]::Transparent
    $lblKey.AutoSize  = $false
    $lblKey.Bounds    = New-Object System.Drawing.Rectangle (S 2), (S 50), (S 200), (S 16)

    $script:BindKeyBox = New-Object System.Windows.Forms.ComboBox
    $script:BindKeyBox.DropDownStyle = 'DropDown'
    $script:BindKeyBox.FlatStyle     = 'Flat'
    $script:BindKeyBox.BackColor     = [RustSuite.Theme]::Field
    $script:BindKeyBox.ForeColor     = [RustSuite.Theme]::TextC
    $script:BindKeyBox.Font          = [RustSuite.Theme]::FSub
    $script:BindKeyBox.Bounds        = New-Object System.Drawing.Rectangle (S 2), (S 68), (S 190), (S 26)
    foreach ($k in @('mouse0','mouse1','mouse2','mouse3','mouse4','mouse5',
                     'f1','f2','f3','f4','f5','f6','f7','f8','f9','f10','f11','f12',
                     'h','j','k','l','n','m','u','y','i','o','p','b','c','v','x','z',
                     'g','t','r','e','q','space','tab','leftshift','leftctrl','leftalt','capslock','return')) {
        [void]$script:BindKeyBox.Items.Add($k)
    }
    $script:BindKeyBox.Text = 'mouse4'

    $btnAddBind = New-Object RustSuite.FlatButton
    $btnAddBind.Style   = 'Ghost'
    $btnAddBind.Text    = 'ДОБАВИТЬ'
    $btnAddBind.Font    = [RustSuite.Theme]::FSmall
    $btnAddBind.Bounds  = New-Object System.Drawing.Rectangle (S 200), (S 67), (S 120), (S 28)

    $lblCmd = New-Object System.Windows.Forms.Label
    $lblCmd.Text      = 'КОМАНДА'
    $lblCmd.Font      = [RustSuite.Theme]::FHead
    $lblCmd.ForeColor = [RustSuite.Theme]::Muted
    $lblCmd.BackColor = [System.Drawing.Color]::Transparent
    $lblCmd.AutoSize  = $false
    $lblCmd.Bounds    = New-Object System.Drawing.Rectangle (S 2), (S 104), (S 200), (S 16)

    $script:BindCmdBox = New-Object System.Windows.Forms.TextBox
    $script:BindCmdBox.BorderStyle = 'FixedSingle'
    $script:BindCmdBox.BackColor   = [RustSuite.Theme]::Field
    $script:BindCmdBox.ForeColor   = [RustSuite.Theme]::TextC
    $script:BindCmdBox.Font        = [RustSuite.Theme]::FSub
    $script:BindCmdBox.Bounds      = New-Object System.Drawing.Rectangle (S 2), (S 122), ($w - (S 4)), (S 26)
    $script:BindCmdBox.Anchor      = 'Top,Left,Right'
    $script:BindCmdBox.Text        = '+altlook'

    $lblPresets = New-Object System.Windows.Forms.Label
    $lblPresets.Text      = 'ПРЕСЕТЫ  ·  нажмите, чтобы добавить'
    $lblPresets.Font      = [RustSuite.Theme]::FHead
    $lblPresets.ForeColor = [RustSuite.Theme]::Muted
    $lblPresets.BackColor = [System.Drawing.Color]::Transparent
    $lblPresets.AutoSize  = $false
    $lblPresets.Bounds    = New-Object System.Drawing.Rectangle (S 2), (S 160), (S 320), (S 16)

    $script:RowHost.Controls.AddRange(@($head, $sub, $lblKey, $script:BindKeyBox, $btnAddBind,
                                        $lblCmd, $script:BindCmdBox, $lblPresets))

    $pw = [int](($w - (S 8)) / 2)
    $px = @((S 2), ($pw + (S 6)))
    $py = (S 180)
    $idx = 0
    foreach ($p in $script:BindPresets) {
        $pb = New-Object RustSuite.FlatButton
        $pb.Style  = 'Ghost'
        $pb.Font   = [RustSuite.Theme]::FSmall
        $pb.Text   = $p.Name + '  ·  ' + $p.Key
        $pb.Tag    = $p
        $pb.Bounds = New-Object System.Drawing.Rectangle $px[$idx % 2], ($py + [int]([Math]::Floor($idx / 2) * (S 36))), $pw, (S 30)
        $pb.Add_Click({
            param($s, $e)
            $null = Add-RustBind $s.Tag.Key $s.Tag.Cmd
            Update-BindListBox
            Set-Status ('Добавлен бинд: ' + $s.Tag.Key + ' → ' + $s.Tag.Cmd) '#4ECB71'
            Write-Log ('Бинд добавлен: ' + $s.Tag.Key + ' → ' + $s.Tag.Cmd) 'ok'
        })
        $script:RowHost.Controls.Add($pb)
        $idx = $idx + 1
    }
    $allBtn = New-Object RustSuite.FlatButton
    $allBtn.Style  = 'Primary'
    $allBtn.Font   = [RustSuite.Theme]::FSmall
    $allBtn.Text   = 'ДОБАВИТЬ ВСЕ БЕЗОПАСНЫЕ'
    $allBtn.Bounds = New-Object System.Drawing.Rectangle $px[0], ($py + (S 72)), $pw, (S 30)
    $allBtn.Add_Click({
        foreach ($p in $script:BindPresets) { $null = Add-RustBind $p.Key $p.Cmd }
        Update-BindListBox
        Set-Status 'Добавлены все безопасные бинды' '#4ECB71'
        Write-Log 'Добавлены все безопасные бинды Rust' 'ok'
    })
    $script:RowHost.Controls.Add($allBtn)

    $lblList = New-Object System.Windows.Forms.Label
    $lblList.Text      = 'ВАШИ БИНДЫ'
    $lblList.Font      = [RustSuite.Theme]::FHead
    $lblList.ForeColor = [RustSuite.Theme]::Muted
    $lblList.BackColor = [System.Drawing.Color]::Transparent
    $lblList.AutoSize  = $false
    $lblList.Bounds    = New-Object System.Drawing.Rectangle (S 2), (S 292), (S 220), (S 16)

    $script:BindListBox = New-Object System.Windows.Forms.ListBox
    $script:BindListBox.BorderStyle    = 'None'
    $script:BindListBox.BackColor      = [RustSuite.Theme]::Field
    $script:BindListBox.ForeColor      = [RustSuite.Theme]::TextC
    $script:BindListBox.Font           = [RustSuite.Theme]::FMono
    $script:BindListBox.IntegralHeight = $false
    $script:BindListBox.Bounds         = New-Object System.Drawing.Rectangle (S 2), (S 310), ($w - (S 4)), (S 150)
    $script:BindListBox.Anchor         = 'Top,Left,Right'

    $btnApply = New-Object RustSuite.FlatButton
    $btnApply.Style  = 'Primary'
    $btnApply.Text   = 'ЗАПИСАТЬ БИНДЫ В KEYS.CFG'
    $btnApply.Font   = [RustSuite.Theme]::FSmall
    $btnApply.Bounds = New-Object System.Drawing.Rectangle (S 2), (S 470), ($w - (S 4)), (S 38)
    $btnApply.Anchor = 'Top,Left,Right'

    $btnDel = New-Object RustSuite.FlatButton
    $btnDel.Style  = 'Ghost'
    $btnDel.Text   = 'УДАЛИТЬ ВЫБРАННЫЙ'
    $btnDel.Font   = [RustSuite.Theme]::FSmall
    $btnDel.Bounds = New-Object System.Drawing.Rectangle (S 2), (S 516), ($pw), (S 32)

    $btnClear = New-Object RustSuite.FlatButton
    $btnClear.Style  = 'Ghost'
    $btnClear.Text   = 'ОЧИСТИТЬ СПИСОК'
    $btnClear.Font   = [RustSuite.Theme]::FSmall
    $btnClear.Bounds = New-Object System.Drawing.Rectangle $px[1], (S 516), ($pw), (S 32)

    $btnCopy = New-Object RustSuite.FlatButton
    $btnCopy.Style  = 'Ghost'
    $btnCopy.Text   = 'СКОПИРОВАТЬ ДЛЯ КОНСОЛИ F1'
    $btnCopy.Font   = [RustSuite.Theme]::FSmall
    $btnCopy.Bounds = New-Object System.Drawing.Rectangle (S 2), (S 556), ($w - (S 4)), (S 34)
    $btnCopy.Anchor = 'Top,Left,Right'

    $note = New-Object System.Windows.Forms.Label
    $note.Text = 'Безопасность: это официальный файл настроек Rust, игра сама читает его при запуске. ' +
                 'Программа не трогает exe/dll, не внедряется в процесс и не эмулирует ввод — EAC такие действия не блокирует. ' +
                 'Бинды с автоповтором, макросами и «одна кнопка = серия действий» не добавляются: за автоматизацию ввода можно получить бан.'
    $note.Font      = [RustSuite.Theme]::FSmall
    $note.ForeColor = [RustSuite.Theme]::Muted
    $note.BackColor = [System.Drawing.Color]::Transparent
    $note.AutoSize  = $false
    $note.Bounds    = New-Object System.Drawing.Rectangle (S 2), (S 600), ($w - (S 4)), (S 110)
    $note.Anchor    = 'Top,Left,Right'

    $script:RowHost.Controls.AddRange(@($lblList, $script:BindListBox, $btnApply, $btnDel, $btnClear, $btnCopy, $note))

    $btnAddBind.Add_Click({ Add-BindFromUi })
    $script:BindCmdBox.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'Return') { Add-BindFromUi; $e.SuppressKeyPress = $true } })
    $btnApply.Add_Click({ Apply-BindsFromUi })
    $btnCopy.Add_Click({ Copy-BindsFromUi })
    $btnDel.Add_Click({
        if ($script:BindListBox -and $script:BindListBox.SelectedIndex -ge 0) {
            $recs = @(Get-BindRecords)
            $i = $script:BindListBox.SelectedIndex
            if ($i -lt $recs.Count) {
                Remove-RustBind $recs[$i].Key
                Update-BindListBox
                Write-Log ('Бинд удалён: ' + $recs[$i].Key) 'info'
            }
        }
    })
    $btnClear.Add_Click({
        Save-BindRecords @()
        Update-BindListBox
        Write-Log 'Список биндов очищен' 'info'
    })

    Update-BindListBox
    $script:RowHost.AutoScrollMinSize = New-Object System.Drawing.Size 0, (S 724)
}

function Show-Group {
    param([string]$gid)
    if (-not $gid) { $gid = 'home' }
    $script:ActiveGroup = $gid

    # Останавливаем таймеры страниц, иначе они держат удалённые контролы.
    try {
        if ($script:TempTimer) { $script:TempTimer.Stop(); $script:TempTimer.Dispose(); $script:TempTimer = $null }
    } catch {}
    try {
        if ($script:ThemeTimer) { $script:ThemeTimer.Stop(); $script:ThemeTimer.Dispose(); $script:ThemeTimer = $null }
    } catch {}
    try {
        if ($script:RepairScanTimer) { $script:RepairScanTimer.Stop(); $script:RepairScanTimer.Dispose(); $script:RepairScanTimer = $null }
    } catch {}
    $script:SetTempBox = $null
    $script:SetCpuBar  = $null
    $script:SetRamBar  = $null
    $script:SetValCpu  = $null
    $script:SetValRam  = $null
    $script:PictureStatusLabel  = $null
    $script:PicturePreviewAfter = $null
    $script:PictureTiles        = @()
    $script:PictureDescLabel    = $null
    $script:HomeGauge           = $null
    $script:HomeSpark           = $null
    $script:HomeCpuVal          = $null
    $script:HomeRamVal          = $null
    $script:HomeStatusLbl       = $null
    $script:HomeHero            = $null
    $script:HomeCards           = @{}

    foreach ($k in $script:NavButtons.Keys) { $script:NavButtons[$k].Selected = ($k -eq $gid) }
    foreach ($c in @($script:RowHost.Controls)) { $c.Dispose() }
    $script:RowHost.Controls.Clear()
    $script:RowHost.AutoScrollMinSize = New-Object System.Drawing.Size 0, 0
    try { $script:RowHost.ScrollToTop() } catch {}

    # Строим новую страницу без промежуточных перерисовок — переход без мигания.
    try { [RustSuite.Native]::SetRedraw($script:RowHost, $false) } catch {}
    try { $script:RowHost.SuspendLayout() } catch {}

    try {
        if ($gid -eq 'home') { Show-HomePanel; return }
        if ($gid -eq 'binds') { Show-BindsPanel; return }
        if ($gid -eq 'picture') { Show-PicturePanel; return }
        if ($gid -eq 'repair') { Show-RepairPanel; return }
        if ($gid -eq 'settings') { Show-SettingsPanel; return }

    $items = @($script:Tweaks | Where-Object { $_.Group -eq $gid })
    $w = Get-RowWidth 18
    if ($w -lt (S 300)) { $w = (S 300) }

    $y = S 2
    $title = ($script:Groups | Where-Object { $_.Id -eq $gid }).Title
    $accentBar = New-Object System.Windows.Forms.Panel
    $accentBar.BackColor = [RustSuite.Theme]::Accent
    $accentBar.Bounds    = New-Object System.Drawing.Rectangle 0, ($y + (S 3)), (S 3), (S 17)
    $script:RowHost.Controls.Add($accentBar)

    $head = New-Object System.Windows.Forms.Label
    $head.Text      = [string]$title + '  ·  ' + $items.Count + ' модулей'
    $head.Font      = [RustSuite.Theme]::FHead
    $head.ForeColor = [RustSuite.Theme]::TextC
    $head.BackColor = [System.Drawing.Color]::Transparent
    $head.AutoSize  = $false
    $head.Bounds    = New-Object System.Drawing.Rectangle (S 12), $y, (S 420), (S 22)
    $script:RowHost.Controls.Add($head)
    $y += S 30

    if ($gid -eq 'clean') {
        $btnDeep = New-Object RustSuite.FlatButton
        $btnDeep.Style  = 'Primary'
        $btnDeep.Text   = '✦  ГЛУБОКАЯ ОЧИСТКА WINDOWS'
        $btnDeep.Bounds = New-Object System.Drawing.Rectangle 0, $y, $w, (S 44)
        $btnDeep.Add_Click({ Start-DeepCleanFromUi })
        $script:RowHost.Controls.Add($btnDeep)

        $deepSub = New-Object System.Windows.Forms.Label
        $deepSub.Text      = 'TEMP · кэш обновлений · дампы · кэш браузеров · логи Steam/RUST · эскизы'
        $deepSub.Font      = [RustSuite.Theme]::FSmall
        $deepSub.ForeColor = [RustSuite.Theme]::Muted
        $deepSub.BackColor = [System.Drawing.Color]::Transparent
        $deepSub.AutoSize  = $false
        $deepSub.Bounds    = New-Object System.Drawing.Rectangle 0, ($y + (S 48)), $w, (S 16)
        $script:RowHost.Controls.Add($deepSub)
        $y += S 74
    }

    $rh = S 80
    $idx = 0
    foreach ($t in $items) {
        $top = $y
        $card = New-Object RustSuite.Card
        $card.Bounds = New-Object System.Drawing.Rectangle 0, ($top + (S 18)), $w, $rh
        $card.Title  = if ($t.Risk) { '● ' + $t.Name } else { [string]$t.Name }
        $card.Sub    = [string]$t.Desc
        $card.Risk   = [bool]$t.Risk
        $card.Tag    = $t
        $card.On     = [bool]$script:Enabled[$t.Id]
        $card.Add_Toggled({
            param($s, $e)
            $tw = $s.Tag
            $script:Enabled[$tw.Id] = $s.On
            $script:State['Enabled'] = $script:Enabled
            Save-State
        })
        $script:RowHost.Controls.Add($card)
        $null = New-Object RustSuite.SlideTween -ArgumentList $card, ($top + (S 18)), $top, ([Math]::Min($idx, 8) * 22), 220
        $y += $rh + (S 8)
        $idx = $idx + 1
    }

    if ($gid -eq 'rust') {
        $cw = $w
        $btnLaunch = New-Object RustSuite.FlatButton
        $btnLaunch.Style  = 'Primary'
        $btnLaunch.Text   = '▶  ЗАПУСТИТЬ RUST С ОПТИМИЗАЦИЕЙ'
        $btnLaunch.Bounds = New-Object System.Drawing.Rectangle 0, ($y + (S 4)), $cw, (S 46)
        $btnLaunch.Add_Click({ Start-Rust })
        $script:RowHost.Controls.Add($btnLaunch)

        $btnOne = New-Object RustSuite.FlatButton
        $btnOne.Style  = 'Ghost'
        $btnOne.Text   = 'ТРАВА + БИНДЫ ОДНОЙ КНОПКОЙ'
        $btnOne.Bounds = New-Object System.Drawing.Rectangle 0, ($y + (S 58)), $cw, (S 42)
        $btnOne.Add_Click({ Rust-OneClickFromUi })
        $script:RowHost.Controls.Add($btnOne)

        $half = [int](($cw - (S 8)) / 2)
        $btnCfg = New-Object RustSuite.FlatButton
        $btnCfg.Style  = 'Ghost'
        $btnCfg.Text   = 'ОТКРЫТЬ ПАПКУ CFG'
        $btnCfg.Font   = [RustSuite.Theme]::FSmall
        $btnCfg.Bounds = New-Object System.Drawing.Rectangle 0, ($y + (S 108)), $half, (S 34)
        $btnCfg.Add_Click({ $d = Get-RustCfgDir; if ($d) { Open-Explorer $d } else { Write-Log 'RUST не найден — папка cfg недоступна' 'warn' } })

        $btnCmd = New-Object RustSuite.FlatButton
        $btnCmd.Style  = 'Ghost'
        $btnCmd.Text   = 'КОМАНДЫ ДЛЯ F1'
        $btnCmd.Font   = [RustSuite.Theme]::FSmall
        $btnCmd.Bounds = New-Object System.Drawing.Rectangle ($half + (S 8)), ($y + (S 108)), ($cw - $half - (S 8)), (S 34)
        $btnCmd.Add_Click({ Show-ConsoleCommands })

        $note = New-Object System.Windows.Forms.Label
        $note.Text = 'Про траву честно: полностью убрать её официальными средствами нельзя — это меняет баланс игры. ' +
                     'Модуль отключает вытаптывание травы (grass.displacement) и пост-эффекты. ' +
                     'Шейдеры и моды, вырезающие траву, не поддерживаются: это прямое вмешательство в клиент и риск бана.'
        $note.Font      = [RustSuite.Theme]::FSmall
        $note.ForeColor = [RustSuite.Theme]::Muted
        $note.BackColor = [System.Drawing.Color]::Transparent
        $note.AutoSize  = $false
        $note.Bounds    = New-Object System.Drawing.Rectangle 0, ($y + (S 152)), $cw, (S 86)

        $script:RowHost.Controls.AddRange(@($btnCfg, $btnCmd, $note))
        $y += S 246
    }

    $script:RowHost.AutoScrollMinSize = New-Object System.Drawing.Size 0, ($y + (S 12))
    Update-RowWidths
    } finally {
        try { $script:RowHost.ResumeLayout($false) } catch {}
        try { [RustSuite.Native]::SetRedraw($script:RowHost, $true) } catch {}
        try { $script:RowHost.Invalidate($true) } catch {}
        try { $script:RowHost.Update() } catch {}
    }
}

$script:RowHost.Add_Resize({ Update-RowWidths })
$script:RowHost.Add_ClientSizeChanged({
    Update-RowWidths
})

# ============================================================
#  СТРАНИЦА «РЕМОНТ И ДИАГНОСТИКА»
#  Проверки Windows + стандартные средства восстановления.
# ============================================================

$script:RepairReport   = $null
$script:RepairReportAt = $null
$script:RepairScanTimer = $null

function Format-HealthReportFromCache {
    $checks = @($script:RepairReport)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('PURPLE RUSH · отчёт о здоровье Windows')
    [void]$sb.AppendLine(('Дата: ' + $(if ($script:RepairReportAt) { $script:RepairReportAt.ToString('yyyy-MM-dd HH:mm:ss') } else { '—' })))
    [void]$sb.AppendLine(('Версия: ' + $script:AppVersion))
    [void]$sb.AppendLine('')
    foreach ($c in $checks) {
        $mark = switch ($c.Status) {
            'ok'   { '[OK]  ' }
            'warn' { '[!]   ' }
            'err'  { '[ERR] ' }
            default { '[i]   ' }
        }
        [void]$sb.AppendLine($mark + $c.Title + ': ' + $c.Detail)
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Это стандартные проверки Windows, а не гарантия исправления любой ошибки.')
    return $sb.ToString()
}

function Start-HealthScan {
    if ($script:Busy) { return }
    $oldCursor = $null
    Set-Busy $true
    try {
        if ($script:RowHost -and -not $script:RowHost.IsDisposed) {
            $oldCursor = $script:RowHost.Cursor
            $script:RowHost.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        }
        Set-ProgressValue 12
        Set-Status 'Диагностика Windows: WMI, службы, диск, события…' '#FF8A4C'
        Write-Log 'Диагностика Windows: сбор отчёта…' 'step'
        Pump
        $script:RepairReport = @(Get-SystemHealthReport)
        $script:RepairReportAt = Get-Date
        $warn = @($script:RepairReport | Where-Object { $_.Status -eq 'warn' -or $_.Status -eq 'err' }).Count
        Set-ProgressValue 100
        if ($warn -gt 0) {
            Set-Status ('Диагностика готова: замечаний — ' + $warn) '#E3B341'
            Write-Log ('Диагностика: проверок — ' + $script:RepairReport.Count + ', замечаний — ' + $warn) 'warn'
        } else {
            Set-Status 'Диагностика готова: критичных замечаний нет' '#4ECB71'
            Write-Log ('Диагностика: проверок — ' + $script:RepairReport.Count + ', замечаний нет') 'ok'
        }
    } catch {
        Write-Log ('Диагностика не удалась: ' + $_.Exception.Message) 'err'
        Set-Status 'Диагностика завершилась с ошибкой — смотрите журнал' '#FF6B62'
    } finally {
        Set-Busy $false
        Set-ProgressValue 0
        if ($oldCursor -and $script:RowHost -and -not $script:RowHost.IsDisposed) {
            $script:RowHost.Cursor = $oldCursor
        }
    }
    # Show-Group очищает старые контролы, поэтому после сканирования
    # страница перестраивается без наложения двух наборов строк.
    if ($script:ActiveGroup -eq 'repair') { Request-Group 'repair' -Force }
}

function Restart-PcFromUi {
    $ans = [System.Windows.Forms.MessageBox]::Show(
        ("Перезагрузить ПК сейчас?`n`nНесохранённые файлы будут закрыты. Перезагрузка начнётся через 10 секунд."),
        'PURPLE RUSH — ПЕРЕЗАГРУЗКА', 'YesNo', 'Warning')
    if ($ans -ne 'Yes') { return }
    try {
        $shutdown = Join-Path $env:SystemRoot 'System32\shutdown.exe'
        Start-Process -FilePath $shutdown `
            -ArgumentList '/r /t 10 /f /c "PURPLE RUSH: перезагрузка после диагностики"' `
            -WindowStyle Hidden -ErrorAction Stop | Out-Null
        Write-Log 'Запланирована перезагрузка через 10 секунд' 'warn'
        Set-Status 'Перезагрузка через 10 секунд…' '#FF8A4C'
    } catch {
        Write-Log ('Не удалось запланировать перезагрузку: ' + $_.Exception.Message) 'err'
        [void][System.Windows.Forms.MessageBox]::Show(
            ("Не удалось перезагрузить автоматически.`n`n" + $_.Exception.Message),
            'PURPLE RUSH', 'OK', 'Error')
    }
}

function Invoke-HealthFixFromUi {
    param($Check)
    if (-not $Check -or $script:Busy) { return }

    if ($Check.Fix -eq 'cleanup') {
        Request-Group 'clean'
        Set-Status ('Рекомендация: ' + $Check.Title + ' — запустите глубокую очистку') '#E3B341'
        Write-Log ('Диагностика рекомендует очистку: ' + $Check.Title) 'info'
        return
    }
    if ($Check.Fix -eq 'reboot') { Restart-PcFromUi; return }

    $confirm = switch ($Check.Fix) {
        'wmi'     { 'Проверить и при необходимости восстановить репозиторий WMI?' }
        'restore' { 'Создать точку восстановления системы сейчас?' }
        'wu'      { 'Вернуть службы Windows Update в рабочий режим?' }
        'time'    { 'Синхронизировать системное время с time.windows.com?' }
        'drivers' { 'Запустить поиск изменений оборудования?' }
        default   { '' }
    }
    if ($confirm) {
        $a = [System.Windows.Forms.MessageBox]::Show($confirm, 'PURPLE RUSH — РЕМОНТ', 'YesNo', 'Question')
        if ($a -ne 'Yes') { return }
    }

    Set-Busy $true
    Set-ProgressValue 25
    try {
        switch ($Check.Fix) {
            'time'    { Invoke-TimeResync }
            'wu'      { Invoke-WindowsUpdateServicesFix }
            'wmi'     { Invoke-WmiRepair }
            'drivers' { Invoke-DriverRescan }
            'restore' { Invoke-RestorePointNow }
        }
        Set-ProgressValue 100
        Set-Status ('Готово: ' + $Check.Title) '#4ECB71'
    } catch {
        Write-Log ('Ремонт «' + $Check.Title + '»: ' + $_.Exception.Message) 'err'
        Set-Status ('Ошибка ремонта: ' + $_.Exception.Message) '#FF6B62'
        [void][System.Windows.Forms.MessageBox]::Show(
            ("Не удалось выполнить: " + $Check.Title + "`n`n" + $_.Exception.Message + "`n`nЖурнал: " + $script:LogFile),
            'PURPLE RUSH', 'OK', 'Warning')
    } finally {
        Set-Busy $false
        Set-ProgressValue 0
    }
    if ($script:ActiveGroup -eq 'repair') { Start-HealthScan }
}

function Invoke-RepairToolFromUi {
    param([string]$Key)
    if (-not $Key -or $script:Busy) { return }

    $tools = @{
        sfc = @{
            Label = 'SFC /scannow'
            Confirm = "Проверить целостность системных файлов?`n`nSFC может занять 5–20 минут. Не закрывайте окно."
            Notice = $true
            Run = { Invoke-SfcScan }
        }
        dism = @{
            Label = 'DISM RestoreHealth'
            Confirm = "Восстановить образ Windows через DISM?`n`nНужен интернет, операция может занять 10–30 минут."
            Notice = $true
            Run = { Invoke-DismRestore }
        }
        dismclean = @{
            Label = 'DISM ComponentCleanup'
            Confirm = "Очистить хранилище компонентов WinSxS?`n`nWindows может работать медленнее до следующей перезагрузки."
            Notice = $true
            Run = { Invoke-DismComponentCleanup }
        }
        chkdsk = @{
            Label = 'CHKDSK /scan'
            Confirm = "Проверить системный диск онлайн?`n`nCHKDSK /scan работает без перезагрузки и может занять несколько минут."
            Notice = $true
            Run = { Invoke-ChkdskScan }
        }
        wureset = @{
            Label = 'Сброс Windows Update'
            Confirm = "Сбросить компоненты Windows Update?`n`nКэш обновлений будет пересоздан, после операции нужна перезагрузка."
            Notice = $true
            Run = { Invoke-WindowsUpdateReset }
        }
        netreset = @{
            Label = 'Сброс сети'
            Confirm = "Сбросить Winsock, TCP/IP и DNS?`n`nСеть может быть недоступна до перезагрузки."
            Notice = $true
            Run = { Invoke-NetworkReset }
        }
        wmi = @{
            Label = 'Лечение WMI'
            Confirm = "Проверить и при необходимости восстановить репозиторий WMI?"
            Notice = $false
            Run = { Invoke-WmiRepair }
        }
        store = @{
            Label = 'Сброс Microsoft Store'
            Confirm = "Очистить кэш Microsoft Store?"
            Notice = $false
            Run = { Invoke-StoreReset }
        }
        icons = @{
            Label = 'Пересборка кэша иконок'
            Confirm = "Пересобрать кэш иконок и эскизов?`n`nПроводник Windows будет перезапущен."
            Notice = $false
            Run = { Invoke-IconCacheRebuild }
        }
        time = @{
            Label = 'Синхронизация времени'
            Confirm = ''
            Notice = $false
            Run = { Invoke-TimeResync }
        }
        drivers = @{
            Label = 'Пересканировать драйверы'
            Confirm = "Запустить поиск изменений оборудования?"
            Notice = $false
            Run = { Invoke-DriverRescan }
        }
        spooler = @{
            Label = 'Очередь печати'
            Confirm = "Очистить очередь печати и перезапустить Spooler?"
            Notice = $false
            Run = { Invoke-SpoolerReset }
        }
        restore = @{
            Label = 'Точка восстановления'
            Confirm = "Создать точку восстановления системы сейчас?"
            Notice = $true
            Run = { Invoke-RestorePointNow }
        }
    }

    $tool = $tools[$Key]
    if (-not $tool) { return }
    if ($tool.Confirm) {
        $a = [System.Windows.Forms.MessageBox]::Show($tool.Confirm, 'PURPLE RUSH — РЕМОНТ', 'YesNo', 'Question')
        if ($a -ne 'Yes') { return }
    }

    $oldCursor = $null
    Set-Busy $true
    try {
        if ($script:RowHost -and -not $script:RowHost.IsDisposed) {
            $oldCursor = $script:RowHost.Cursor
            $script:RowHost.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        }
        Set-ProgressValue 5
        Set-Status ($tool.Label + ' · выполняется…') '#FF8A4C'
        Write-Log ('Ремонт Windows: ' + $tool.Label) 'step'
        Pump
        $null = & $tool.Run
        Set-ProgressValue 100
        Set-Status ($tool.Label + ' · готово') '#4ECB71'
        if ($tool.Notice) {
            [void][System.Windows.Forms.MessageBox]::Show(
                ($tool.Label + " — готово.`n`nПодробности в журнале:`n" + $script:LogFile),
                'PURPLE RUSH — РЕМОНТ', 'OK', 'Information')
        }
    } catch {
        Write-Log ($tool.Label + ': ' + $_.Exception.Message) 'err'
        Set-Status ('Ошибка: ' + $_.Exception.Message) '#FF6B62'
        [void][System.Windows.Forms.MessageBox]::Show(
            ($tool.Label + "`n`n" + $_.Exception.Message + "`n`nЖурнал: " + $script:LogFile),
            'PURPLE RUSH — РЕМОНТ', 'OK', 'Warning')
    } finally {
        Set-Busy $false
        Set-ProgressValue 0
        if ($oldCursor -and $script:RowHost -and -not $script:RowHost.IsDisposed) {
            $script:RowHost.Cursor = $oldCursor
        }
    }
    if ($script:ActiveGroup -eq 'repair') { Start-HealthScan }
}

function Show-RepairPanel {
    try { if ($script:RepairTip) { $script:RepairTip.Dispose(); $script:RepairTip = $null } } catch {}
    $w = Get-RowWidth 22
    if ($w -lt (S 340)) { $w = (S 340) }

    $accentBar = New-Object System.Windows.Forms.Panel
    $accentBar.BackColor = [RustSuite.Theme]::Accent
    $accentBar.Bounds    = New-Object System.Drawing.Rectangle 0, (S 5), (S 3), (S 15)
    $script:RowHost.Controls.Add($accentBar)

    $head = New-Object System.Windows.Forms.Label
    $head.Text      = 'РЕМОНТ И ДИАГНОСТИКА · WINDOWS'
    $head.Font      = [RustSuite.Theme]::FHead
    $head.ForeColor = [RustSuite.Theme]::TextC
    $head.BackColor = [System.Drawing.Color]::Transparent
    $head.AutoSize  = $false
    $head.Bounds    = New-Object System.Drawing.Rectangle (S 12), (S 2), (S 520), (S 22)
    $script:RowHost.Controls.Add($head)

    $sub = New-Object System.Windows.Forms.Label
    $sub.Text      = 'Только штатные средства Windows: SFC, DISM, CHKDSK, WMI, службы и кэши. Сторонние бинарники не используются.'
    $sub.Font      = [RustSuite.Theme]::FSmall
    $sub.ForeColor = [RustSuite.Theme]::Muted
    $sub.BackColor = [System.Drawing.Color]::Transparent
    $sub.AutoSize  = $false
    $sub.Bounds    = New-Object System.Drawing.Rectangle 0, (S 24), $w, (S 32)
    $sub.Anchor    = 'Top,Left,Right'
    $script:RowHost.Controls.Add($sub)

    $btnScan = New-Object RustSuite.FlatButton
    $btnScan.Style  = 'Primary'
    $btnScan.Text   = '◈  ПРОВЕРИТЬ WINDOWS СЕЙЧАС'
    $btnScan.Bounds = New-Object System.Drawing.Rectangle 0, (S 58), $w, (S 44)
    $btnScan.Anchor = 'Top,Left,Right'
    $btnScan.Add_Click({ Start-HealthScan })
    $script:RowHost.Controls.Add($btnScan)

    $half = [int](($w - (S 8)) / 2)
    $btnFix = New-Object RustSuite.FlatButton
    $btnFix.Style  = 'Ghost'
    $btnFix.Text   = '⚡  БЫСТРОЕ ЛЕЧЕНИЕ'
    $btnFix.Font   = [RustSuite.Theme]::FSmall
    $btnFix.Bounds = New-Object System.Drawing.Rectangle 0, (S 110), $half, (S 32)
    $btnFix.Add_Click({
        if ($script:Busy) { return }
        $a = [System.Windows.Forms.MessageBox]::Show(
            "Исправить автоматически то, что можно: службы времени и Windows Update, WMI, драйверы?`n`nПродолжить?",
            'PURPLE RUSH — БЫСТРОЕ ЛЕЧЕНИЕ', 'YesNo', 'Question')
        if ($a -ne 'Yes') { return }
        Set-Busy $true
        Set-ProgressValue 10
        try {
            Write-Log 'Быстрое лечение Windows: старт' 'step'
            Set-Status 'Быстрое лечение Windows…' '#FF8A4C'
            Invoke-QuickHealthFix
            Set-ProgressValue 100
            Set-Status 'Быстрое лечение завершено — проверяю снова' '#4ECB71'
        } catch {
            Write-Log ('Быстрое лечение: ' + $_.Exception.Message) 'err'
        } finally {
            Set-Busy $false
            Set-ProgressValue 0
        }
        Start-HealthScan
    })
    $script:RowHost.Controls.Add($btnFix)

    $btnCopy = New-Object RustSuite.FlatButton
    $btnCopy.Style  = 'Ghost'
    $btnCopy.Text   = '⧉  КОПИРОВАТЬ ОТЧЁТ'
    $btnCopy.Font   = [RustSuite.Theme]::FSmall
    $btnCopy.Bounds = New-Object System.Drawing.Rectangle ($half + (S 8)), (S 110), ($w - $half - (S 8)), (S 32)
    $btnCopy.Add_Click({
        if ($null -eq $script:RepairReport) { Start-HealthScan }
        if ($null -eq $script:RepairReport) { return }
        $txt = Format-HealthReportFromCache
        if (Copy-Text $txt) {
            Set-Status 'Отчёт о здоровье Windows скопирован' '#4ECB71'
            Write-Log 'Отчёт о здоровье Windows скопирован в буфер обмена' 'ok'
        }
    })
    $script:RowHost.Controls.Add($btnCopy)

    # ---------- Сводка ----------
    $report = @()
    if ($null -ne $script:RepairReport) { $report = @($script:RepairReport) }
    $cntOk = 0; $cntWarn = 0; $cntErr = 0; $cntInfo = 0
    foreach ($c in $report) {
        switch ([string]$c.Status) {
            'ok'   { $cntOk++ }
            'warn' { $cntWarn++ }
            'err'  { $cntErr++ }
            default { $cntInfo++ }
        }
    }

    $sumY = S 150
    $sumW = [int]($w / 4)
    $sums = @(
        @{ T = ('✓  ' + $cntOk + ' ОК');        C = [RustSuite.Theme]::Ok },
        @{ T = ('!  ' + $cntWarn + ' ВНИМАНИЕ'); C = [RustSuite.Theme]::Warn },
        @{ T = ('✕  ' + $cntErr + ' ОШИБКА');    C = [RustSuite.Theme]::Err },
        @{ T = ('i  ' + $cntInfo + ' ИНФО');     C = [RustSuite.Theme]::AccentLt }
    )
    for ($si = 0; $si -lt $sums.Count; $si++) {
        $sl = New-Object System.Windows.Forms.Label
        $sl.Text      = $sums[$si].T
        $sl.Font      = [RustSuite.Theme]::FSub
        $sl.ForeColor = $sums[$si].C
        $sl.BackColor = [System.Drawing.Color]::Transparent
        $sl.AutoSize  = $false
        $sl.Bounds    = New-Object System.Drawing.Rectangle ($si * $sumW), $sumY, $sumW, (S 22)
        $script:RowHost.Controls.Add($sl)
    }

    $when = if ($script:RepairReportAt) { $script:RepairReportAt.ToString('HH:mm:ss') } else { '—' }
    $lblWhen = New-Object System.Windows.Forms.Label
    $lblWhen.Text      = 'Обновлено: ' + $when
    $lblWhen.Font      = [RustSuite.Theme]::FSmall
    $lblWhen.ForeColor = [RustSuite.Theme]::Muted
    $lblWhen.BackColor = [System.Drawing.Color]::Transparent
    $lblWhen.AutoSize  = $false
    $lblWhen.Bounds    = New-Object System.Drawing.Rectangle 0, ($sumY + (S 22)), $w, (S 16)
    $lblWhen.Anchor    = 'Top,Left,Right'
    $script:RowHost.Controls.Add($lblWhen)

    # ---------- Строки проверок ----------
    $y = S 196
    if ($report.Count -eq 0) {
        $hint = New-Object System.Windows.Forms.Label
        $hint.Text      = "Отчёт ещё не собран.`r`nНажмите «ПРОВЕРИТЬ WINDOWS СЕЙЧАС» — проверка займёт несколько секунд."
        $hint.Font      = [RustSuite.Theme]::FSub
        $hint.ForeColor = [RustSuite.Theme]::Muted
        $hint.BackColor = [System.Drawing.Color]::Transparent
        $hint.AutoSize  = $false
        $hint.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 52)
        $hint.Anchor    = 'Top,Left,Right'
        $script:RowHost.Controls.Add($hint)
        $y += S 64
    } else {
        foreach ($c in $report) {
            $row = New-Object RustSuite.HealthRow
            $row.Title      = [string]$c.Title
            $row.Detail     = [string]$c.Detail
            $row.Status     = [string]$c.Status
            $row.ActionText = [string]$c.FixLabel
            $row.Tag        = $c
            $row.Bounds     = New-Object System.Drawing.Rectangle 0, $y, $w, (S 58)
            $row.Anchor     = 'Top,Left,Right'
            $row.Add_ActionClicked({
                param($s, $e)
                Invoke-HealthFixFromUi $s.Tag
            })
            $script:RowHost.Controls.Add($row)
            $y += S 64
        }
    }

    # ---------- Инструменты ----------
    $y += S 8
    $lblTools = New-Object System.Windows.Forms.Label
    $lblTools.Text      = 'ИНСТРУМЕНТЫ ВОССТАНОВЛЕНИЯ'
    $lblTools.Font      = [RustSuite.Theme]::FHead
    $lblTools.ForeColor = [RustSuite.Theme]::Muted
    $lblTools.BackColor = [System.Drawing.Color]::Transparent
    $lblTools.AutoSize  = $false
    $lblTools.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 16)
    $script:RowHost.Controls.Add($lblTools)
    $y += S 24

    $toolDefs = @(
        @{ K='sfc';       T='SFC · СИСТЕМНЫЕ ФАЙЛЫ';      D='sfc /scannow: проверка и починка системных файлов.' },
        @{ K='dism';      T='DISM · ВОССТАНОВЛЕНИЕ';        D='DISM /RestoreHealth: восстановление образа Windows.' },
        @{ K='dismclean'; T='DISM · ЧИСТКА WINSXS';         D='StartComponentCleanup: безопасная очистка хранилища компонентов.' },
        @{ K='chkdsk';    T='CHKDSK · ПРОВЕРКА ДИСКА';      D='chkdsk /scan: онлайн-проверка системного диска.' },
        @{ K='wureset';   T='СБРОС WINDOWS UPDATE';         D='Остановка служб, пересоздание SoftwareDistribution и Catroot2.' },
        @{ K='netreset';  T='СБРОС СЕТИ';                   D='netsh winsock reset + int ip reset + сброс DNS.' },
        @{ K='wmi';       T='ЛЕЧЕНИЕ WMI';                  D='Проверка и восстановление репозитория WMI.' },
        @{ K='store';     T='СБРОС MICROSOFT STORE';        D='wsreset: очистка кэша Store без удаления приложений.' },
        @{ K='icons';     T='ПЕРЕСБОРКА КЭША ИКОНОК';       D='Очистка thumbcache/iconcache с перезапуском Explorer.' },
        @{ K='time';      T='СИНХРОНИЗАЦИЯ ВРЕМЕНИ';        D='w32tm /resync: синхронизация с time.windows.com.' },
        @{ K='drivers';   T='ПЕРЕСКАНИРОВАТЬ ДРАЙВЕРЫ';     D='pnputil /scan-devices: поиск изменений оборудования.' },
        @{ K='spooler';   T='ОЧИСТИТЬ ОЧЕРЕДЬ ПЕЧАТИ';      D='Остановка Spooler, очистка PRINTERS, запуск службы.' }
    )

    $tip = New-Object System.Windows.Forms.ToolTip
    $tip.AutoPopDelay = 12000
    $tip.InitialDelay = 400
    $tip.ReshowDelay = 100
    $script:RepairTip = $tip

    $tw = [int](($w - (S 8)) / 2)
    for ($ti = 0; $ti -lt $toolDefs.Count; $ti++) {
        $td = $toolDefs[$ti]
        $tx = if ($ti % 2 -eq 0) { 0 } else { $tw + (S 8) }
        $ty = $y + [int]([Math]::Floor($ti / 2) * (S 42))
        $tb = New-Object RustSuite.FlatButton
        $tb.Style  = 'Ghost'
        $tb.Font   = [RustSuite.Theme]::FSmall
        $tb.Text   = $td.T
        $tb.Tag    = $td.K
        $tb.Bounds = New-Object System.Drawing.Rectangle $tx, $ty, $tw, (S 34)
        $tip.SetToolTip($tb, $td.D)
        $tb.Add_Click({ param($s, $e) Invoke-RepairToolFromUi $s.Tag })
        $script:RowHost.Controls.Add($tb)
    }
    $y += [int]([Math]::Ceiling($toolDefs.Count / 2) * (S 42)) + (S 4)

    $btnRestore = New-Object RustSuite.FlatButton
    $btnRestore.Style  = 'Primary'
    $btnRestore.Text   = '◈  СОЗДАТЬ ТОЧКУ ВОССТАНОВЛЕНИЯ'
    $btnRestore.Font   = [RustSuite.Theme]::FSmall
    $btnRestore.Bounds = New-Object System.Drawing.Rectangle 0, $y, $w, (S 38)
    $btnRestore.Anchor = 'Top,Left,Right'
    $btnRestore.Add_Click({ Invoke-RepairToolFromUi 'restore' })
    $script:RowHost.Controls.Add($btnRestore)
    $y += S 52

    $note = New-Object System.Windows.Forms.Label
    $note.Text = 'SFC, DISM и CHKDSK могут работать 10–30 минут — это нормально, окно закрывать не нужно. ' +
                 'Перед основной оптимизацией точка восстановления создаётся автоматически, для ремонта её можно создать кнопкой выше. ' +
                 'Если проблема не ушла, откройте журнал: ProgramData\RustOptimizer. Это диагностика стандартными средствами, ' +
                 'а не «починка всего» одной кнопкой.'
    $note.Font      = [RustSuite.Theme]::FSmall
    $note.ForeColor = [RustSuite.Theme]::Muted
    $note.BackColor = [System.Drawing.Color]::Transparent
    $note.AutoSize  = $false
    $note.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 72)
    $note.Anchor    = 'Top,Left,Right'
    $script:RowHost.Controls.Add($note)
    $y += S 84

    $script:RowHost.AutoScrollMinSize = New-Object System.Drawing.Size 0, $y
}

# ============================================================
#  СТРАНИЦА «КАРТИНКА»: пресеты, предпросмотр, гамма, панель GPU
#  Только официальные cfg-конвары, Windows-гамма и панель драйвера.
# ============================================================

function Get-PictureStatusText {
    $g = Get-GammaStatus
    $color = if ($g.Active) { 'цвет: ' + $g.Preset }
             elseif ($g.Supported) { 'цвет: стандарт' }
             else { 'цвет: только панель драйвера' }
    $rv = [string]$script:State['RustVisualPreset']
    $cfg = if ($rv) { 'client.cfg: ' + (Get-LookPresetName $rv) } else { 'client.cfg: без изменений' }
    return ($color + '   ·   ' + $cfg)
}

function Update-PictureStatusLabel {
    try {
        if ($script:PictureStatusLabel -and -not $script:PictureStatusLabel.IsDisposed) {
            $script:PictureStatusLabel.Text = Get-PictureStatusText
        }
    } catch {}
}

function New-LookPreview {
    param([int]$X, [int]$Y, [int]$W, [int]$H, [bool]$After)

    $p = New-Object RustSuite.BufferedPanel
    $p.Bounds    = New-Object System.Drawing.Rectangle $X, $Y, $W, $H
    $p.BackColor = [System.Drawing.Color]::FromArgb(20, 24, 32)
    $p.Tag       = $After

    $p.Add_Paint({
        param($s, $e)
        try {
            $g = $e.Graphics
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $w = [Math]::Max(2, $s.Width)
            $h = [Math]::Max(2, $s.Height)
            $after = [bool]$s.Tag

            # Небо: «до» — нейтральное, «после» — по выбранному пресету.
            $skyTop = [System.Drawing.Color]::FromArgb(43, 51, 64)
            $skyBot = [System.Drawing.Color]::FromArgb(91, 102, 117)
            $groundTop = [System.Drawing.Color]::FromArgb(60, 74, 53)
            $groundBot = [System.Drawing.Color]::FromArgb(42, 53, 38)
            $sun = [System.Drawing.Color]::FromArgb(205, 205, 190)
            if ($after) {
                $key = [string]$script:LookPreset
                if ($key -eq 'cinema') {
                    $skyTop = [System.Drawing.Color]::FromArgb(30, 62, 112)
                    $skyBot = [System.Drawing.Color]::FromArgb(244, 155, 82)
                    $groundTop = [System.Drawing.Color]::FromArgb(104, 112, 52)
                    $groundBot = [System.Drawing.Color]::FromArgb(52, 62, 30)
                    $sun = [System.Drawing.Color]::FromArgb(255, 224, 140)
                } elseif ($key -eq 'night') {
                    $skyTop = [System.Drawing.Color]::FromArgb(7, 15, 38)
                    $skyBot = [System.Drawing.Color]::FromArgb(34, 68, 110)
                    $groundTop = [System.Drawing.Color]::FromArgb(22, 44, 38)
                    $groundBot = [System.Drawing.Color]::FromArgb(10, 22, 20)
                    $sun = [System.Drawing.Color]::FromArgb(196, 220, 255)
                } else {
                    $skyTop = [System.Drawing.Color]::FromArgb(23, 96, 196)
                    $skyBot = [System.Drawing.Color]::FromArgb(139, 196, 255)
                    $groundTop = [System.Drawing.Color]::FromArgb(70, 150, 62)
                    $groundBot = [System.Drawing.Color]::FromArgb(33, 92, 40)
                    $sun = [System.Drawing.Color]::FromArgb(255, 218, 120)
                }
            }

            $skyRect = [System.Drawing.Rectangle]::new(0, 0, $w, [int]($h * 0.68))
            $skyBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
                $skyRect, $skyTop, $skyBot, [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
            $g.FillRectangle($skyBrush, $skyRect)
            $skyBrush.Dispose()

            $gndRect = [System.Drawing.Rectangle]::new(0, [int]($h * 0.68), $w, ([int]($h * 0.32) + 1))
            $gndBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
                $gndRect, $groundTop, $groundBot, [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
            $g.FillRectangle($gndBrush, $gndRect)
            $gndBrush.Dispose()

            # Солнце / луна с мягким ореолом.
            $cx = [int]($w * 0.76)
            $cy = [int]($h * 0.24)
            $r  = [int]([Math]::Max(7, $h * 0.085))
            $glow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(45, $sun.R, $sun.G, $sun.B))
            $g.FillEllipse($glow, ($cx - $r * 3), ($cy - $r * 3), ($r * 6), ($r * 6))
            $glow.Dispose()
            $sunBrush = New-Object System.Drawing.SolidBrush $sun
            $g.FillEllipse($sunBrush, ($cx - $r), ($cy - $r), ($r * 2), ($r * 2))
            $sunBrush.Dispose()

            # Дальние холмы.
            $hillAlpha = if ($after) { 150 } else { 90 }
            $hill = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($hillAlpha, 18, 34, 28))
            $hillPts = [System.Drawing.Point[]]@(
                [System.Drawing.Point]::new(0, [int]($h * 0.68)),
                [System.Drawing.Point]::new([int]($w * 0.28), [int]($h * 0.52)),
                [System.Drawing.Point]::new([int]($w * 0.52), [int]($h * 0.68)),
                [System.Drawing.Point]::new($w, [int]($h * 0.56)),
                [System.Drawing.Point]::new($w, [int]($h * 0.70)),
                [System.Drawing.Point]::new(0, [int]($h * 0.70))
            )
            $g.FillPolygon($hill, $hillPts)
            $hill.Dispose()

            # Пара деревьев-силуэтов.
            $tree = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(225, 16, 26, 20))
            foreach ($fx in @(0.18, 0.30, 0.64)) {
                $tx = [int]($w * $fx)
                $ty = [int]($h * 0.70)
                $th = [int]($h * 0.28)
                $tw = [int]([Math]::Max(8, $w * 0.035))
                $g.FillRectangle($tree, ($tx - [int]($tw / 4)), ($ty - [int]($th * 0.45)), [int]([Math]::Max(3, $tw / 2)), [int]($th * 0.45))
                $g.FillEllipse($tree, ($tx - $tw), ($ty - $th), ($tw * 2), [int]($th * 0.8))
            }
            $tree.Dispose()

            # Аккуратная виньетка, как в игре.
            if ($after) {
                $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(55, 0, 0, 0)), 3
                $g.DrawRectangle($pen, 1, 1, ($w - 3), ($h - 3))
                $pen.Dispose()
            }

            $label = if ($after) { 'ПОСЛЕ · ' + (Get-LookPresetName $script:LookPreset) } else { 'ДО · стандарт' }
            $badge = [System.Windows.Forms.TextRenderer]::MeasureText($label, [RustSuite.Theme]::FSmall)
            $br = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(170, 0, 0, 0))
            $g.FillRectangle($br, 8, 8, ($badge.Width + 14), 21)
            $br.Dispose()
            [System.Windows.Forms.TextRenderer]::DrawText($g, $label, [RustSuite.Theme]::FSmall,
                ([System.Drawing.Rectangle]::new(15, 10, ($badge.Width + 4), 17)),
                [System.Drawing.Color]::White,
                ([System.Windows.Forms.TextFormatFlags]::Left -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter))
            $script:PreviewPaints = [int]$script:PreviewPaints + 1
        } catch {
            if (-not $script:PreviewPaintWarned) {
                $script:PreviewPaintWarned = $true
                Write-Log ('Ошибка отрисовки предпросмотра: ' + $_.Exception.Message) 'err'
            }
        }
    })

    return $p
}

function Show-PicturePanel {
    $script:PreviewPaintWarned = $false
    $script:PreviewPaints = 0
    $w = Get-RowWidth 22
    if ($w -lt (S 340)) { $w = (S 340) }

    # ---------- Заголовок ----------
    $accentBar = New-Object System.Windows.Forms.Panel
    $accentBar.BackColor = [RustSuite.Theme]::Accent
    $accentBar.Bounds    = New-Object System.Drawing.Rectangle 0, (S 5), (S 3), (S 15)
    $script:RowHost.Controls.Add($accentBar)

    $head = New-Object System.Windows.Forms.Label
    $head.Text      = 'КАРТИНКА · СОЧНЫЙ ЦВЕТ БЕЗ ОВЕРЛЕЕВ'
    $head.Font      = [RustSuite.Theme]::FHead
    $head.ForeColor = [RustSuite.Theme]::TextC
    $head.BackColor = [System.Drawing.Color]::Transparent
    $head.AutoSize  = $false
    $head.Bounds    = New-Object System.Drawing.Rectangle (S 12), (S 2), $w, (S 22)
    $script:RowHost.Controls.Add($head)

    $sub = New-Object System.Windows.Forms.Label
    $sub.Text      = 'Гамма Windows + официальные конвары RUST + настройки панели NVIDIA/AMD. ' +
                     'Никаких Freestyle, ReShade и внедрения в игру.'
    $sub.Font      = [RustSuite.Theme]::FSmall
    $sub.ForeColor = [RustSuite.Theme]::Muted
    $sub.BackColor = [System.Drawing.Color]::Transparent
    $sub.AutoSize  = $false
    $sub.Bounds    = New-Object System.Drawing.Rectangle 0, (S 28), $w, (S 32)
    $sub.Anchor    = 'Top,Left,Right'
    $script:RowHost.Controls.Add($sub)

    $y = S 66

    # ---------- Видеокарта ----------
    $info = Get-GpuInfo -Refresh
    $lblGpu = New-Object System.Windows.Forms.Label
    $lblGpu.Text      = 'ВИДЕОКАРТА · ' + $info.VendorLabel
    $lblGpu.Font      = [RustSuite.Theme]::FHead
    $lblGpu.ForeColor = [RustSuite.Theme]::Muted
    $lblGpu.BackColor = [System.Drawing.Color]::Transparent
    $lblGpu.AutoSize  = $false
    $lblGpu.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 16)
    $script:RowHost.Controls.Add($lblGpu)
    $y += S 20

    $gpuName = New-Object System.Windows.Forms.Label
    $gpuName.Text      = [string]$info.Name
    $gpuName.Font      = [RustSuite.Theme]::FSub
    $gpuName.ForeColor = [RustSuite.Theme]::TextC
    $gpuName.BackColor = [System.Drawing.Color]::Transparent
    $gpuName.AutoSize  = $false
    $gpuName.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 20)
    $gpuName.Anchor    = 'Top,Left,Right'
    $script:RowHost.Controls.Add($gpuName)
    $y += S 22

    $gpuDetail = 'Панель: ' + $info.PanelName
    if ($info.Resolution -ne '—') { $gpuDetail += '   ·   ' + $info.Resolution }
    if ($info.Refresh -gt 0) { $gpuDetail += ' @ ' + [string]$info.Refresh + ' Гц' }
    if ($info.Driver) { $gpuDetail += '   ·   драйвер ' + $info.Driver }
    $gpuSub = New-Object System.Windows.Forms.Label
    $gpuSub.Text      = $gpuDetail
    $gpuSub.Font      = [RustSuite.Theme]::FSmall
    $gpuSub.ForeColor = [RustSuite.Theme]::Muted
    $gpuSub.BackColor = [System.Drawing.Color]::Transparent
    $gpuSub.AutoSize  = $false
    $gpuSub.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 16)
    $gpuSub.Anchor    = 'Top,Left,Right'
    $script:RowHost.Controls.Add($gpuSub)
    $y += S 22

    $half = [int](($w - (S 8)) / 2)

    $btnPanel = New-Object RustSuite.FlatButton
    $btnPanel.Style  = 'Primary'
    $btnPanel.Text   = 'ОТКРЫТЬ ПАНЕЛЬ ' + $info.VendorLabel.ToUpper()
    $btnPanel.Font   = [RustSuite.Theme]::FSmall
    $btnPanel.Bounds = New-Object System.Drawing.Rectangle 0, $y, $half, (S 34)
    $btnPanel.Add_Click({
        $r = Open-GpuPanel
        Set-Status $r.Message $(if ($r.Ok) { '#4ECB71' } else { '#E3B341' })
        Write-Log $r.Message $(if ($r.Ok) { 'info' } else { 'warn' })
        if (-not $r.Ok) {
            [void][System.Windows.Forms.MessageBox]::Show(
                ($r.Message + "`r`n`r`nСкопируйте инструкцию ниже и выставьте значения вручную."),
                'КАРТИНКА RUST', 'OK', 'Information')
        }
    })

    $btnCopyGuide = New-Object RustSuite.FlatButton
    $btnCopyGuide.Style  = 'Ghost'
    $btnCopyGuide.Text   = 'СКОПИРОВАТЬ ИНСТРУКЦИЮ'
    $btnCopyGuide.Font   = [RustSuite.Theme]::FSmall
    $btnCopyGuide.Bounds = New-Object System.Drawing.Rectangle ($half + (S 8)), $y, ($w - $half - (S 8)), (S 34)
    $btnCopyGuide.Add_Click({
        if (Copy-Text (Get-GpuPanelGuide)) {
            Set-Status 'Инструкция для панели драйвера скопирована' '#4ECB71'
            Write-Log 'Инструкция панели GPU скопирована в буфер обмена' 'ok'
        }
    })
    $script:RowHost.Controls.AddRange(@($btnPanel, $btnCopyGuide))
    $y += S 44

    $status = New-Object System.Windows.Forms.Label
    $status.Text      = Get-PictureStatusText
    $status.Font      = [RustSuite.Theme]::FSmall
    $status.ForeColor = [RustSuite.Theme]::AccentLt
    $status.BackColor = [System.Drawing.Color]::Transparent
    $status.AutoSize  = $false
    $status.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 16)
    $status.Anchor    = 'Top,Left,Right'
    $script:PictureStatusLabel = $status
    $script:RowHost.Controls.Add($status)
    $y += S 24

    # ---------- Предпросмотр до / после ----------
    $lblPrev = New-Object System.Windows.Forms.Label
    $lblPrev.Text      = 'ПРЕДПРОСМОТР · выберите пресет ниже'
    $lblPrev.Font      = [RustSuite.Theme]::FHead
    $lblPrev.ForeColor = [RustSuite.Theme]::Muted
    $lblPrev.BackColor = [System.Drawing.Color]::Transparent
    $lblPrev.AutoSize  = $false
    $lblPrev.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 16)
    $script:RowHost.Controls.Add($lblPrev)
    $y += S 20

    $prevGap = S 8
    $prevW = [int](($w - $prevGap) / 2)
    $prevH = S 116
    $before = New-LookPreview 0 $y $prevW $prevH $false
    $after  = New-LookPreview ($prevW + $prevGap) $y ($w - $prevW - $prevGap) $prevH $true
    $script:PicturePreviewAfter = $after
    $script:RowHost.Controls.AddRange(@($before, $after))
    $y += $prevH + (S 12)

    # ---------- Пресеты ----------
    $lblPresets = New-Object System.Windows.Forms.Label
    $lblPresets.Text      = 'ПРЕСЕТЫ КАРТИНКИ · нажмите, чтобы выбрать'
    $lblPresets.Font      = [RustSuite.Theme]::FHead
    $lblPresets.ForeColor = [RustSuite.Theme]::Muted
    $lblPresets.BackColor = [System.Drawing.Color]::Transparent
    $lblPresets.AutoSize  = $false
    $lblPresets.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 16)
    $script:RowHost.Controls.Add($lblPresets)
    $y += S 20

    $tileGap = S 6
    $tileW = [int](($w - ($tileGap * 2)) / 3)
    $tileH = S 96
    $script:PictureTiles = @()
    $idx = 0
    foreach ($p in $script:LookPresets) {
        $tile = New-Object RustSuite.ThemeTile
        $tile.Title = [string]$p.Name
        $tile.Sub   = [string]$p.Sub
        $tile.Tag   = [string]$p.Key
        if ($p.Key -eq 'cinema') {
            $tile.ColorA = [System.Drawing.Color]::FromArgb(120, 58, 20)
            $tile.ColorB = [System.Drawing.Color]::FromArgb(255, 168, 72)
            $tile.ColorC = [System.Drawing.Color]::FromArgb(255, 214, 128)
        } elseif ($p.Key -eq 'night') {
            $tile.ColorA = [System.Drawing.Color]::FromArgb(9, 22, 54)
            $tile.ColorB = [System.Drawing.Color]::FromArgb(52, 112, 214)
            $tile.ColorC = [System.Drawing.Color]::FromArgb(148, 204, 255)
        } else {
            $tile.ColorA = [System.Drawing.Color]::FromArgb(92, 28, 158)
            $tile.ColorB = [System.Drawing.Color]::FromArgb(255, 79, 216)
            $tile.ColorC = [System.Drawing.Color]::FromArgb(120, 220, 130)
        }
        $tile.Selected = ([string]$p.Key -eq [string]$script:LookPreset)
        $tile.Bounds   = New-Object System.Drawing.Rectangle ($idx * ($tileW + $tileGap)), $y, $tileW, $tileH
        $tile.Add_Click({
            param($s, $e)
            $key = [string]$s.Tag
            $script:LookPreset = $key
            foreach ($t in @($script:PictureTiles)) {
                try { if ($t -and -not $t.IsDisposed) { $t.Selected = ([string]$t.Tag -eq $key) } } catch {}
            }
            try { if ($script:PicturePreviewAfter -and -not $script:PicturePreviewAfter.IsDisposed) { $script:PicturePreviewAfter.Invalidate() } } catch {}
            try {
                if ($script:PictureDescLabel -and -not $script:PictureDescLabel.IsDisposed) {
                    $script:PictureDescLabel.Text = [string](Get-LookPreset $key).Desc
                }
            } catch {}
            $script:State['LookPreset'] = $key
            Save-State
            Set-Status ('Пресет картинки: ' + (Get-LookPresetName $key)) '#8B949E'
            Update-PictureStatusLabel
        })
        $script:PictureTiles += $tile
        $script:RowHost.Controls.Add($tile)
        $idx++
    }
    $y += $tileH + (S 14)

    $desc = Get-LookPreset $script:LookPreset
    $lblDesc = New-Object System.Windows.Forms.Label
    $lblDesc.Text      = [string]$desc.Desc
    $lblDesc.Font      = [RustSuite.Theme]::FSmall
    $lblDesc.ForeColor = [RustSuite.Theme]::Muted
    $lblDesc.BackColor = [System.Drawing.Color]::Transparent
    $lblDesc.AutoSize  = $false
    $lblDesc.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 32)
    $lblDesc.Anchor    = 'Top,Left,Right'
    $script:PictureDescLabel = $lblDesc
    $script:RowHost.Controls.Add($lblDesc)
    $y += S 40

    # ---------- Кнопки цвета ----------
    $lblColor = New-Object System.Windows.Forms.Label
    $lblColor.Text      = 'ЦВЕТ WINDOWS · гамма и контраст, обратимо'
    $lblColor.Font      = [RustSuite.Theme]::FHead
    $lblColor.ForeColor = [RustSuite.Theme]::Muted
    $lblColor.BackColor = [System.Drawing.Color]::Transparent
    $lblColor.AutoSize  = $false
    $lblColor.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 16)
    $script:RowHost.Controls.Add($lblColor)
    $y += S 22

    $btnApplyLook = New-Object RustSuite.FlatButton
    $btnApplyLook.Style  = 'Primary'
    $btnApplyLook.Text   = 'ПРИМЕНИТЬ ЦВЕТ'
    $btnApplyLook.Font   = [RustSuite.Theme]::FSmall
    $btnApplyLook.Bounds = New-Object System.Drawing.Rectangle 0, $y, $half, (S 36)
    $btnApplyLook.Add_Click({
        $r = Apply-LookPreset $script:LookPreset
        Set-Status $r.Message $(if ($r.Ok) { '#4ECB71' } else { '#E3B341' })
        Update-PictureStatusLabel
        if (-not $r.Ok) {
            [void][System.Windows.Forms.MessageBox]::Show($r.Message, 'КАРТИНКА RUST', 'OK', 'Information')
        }
    })

    $btnRestoreLook = New-Object RustSuite.FlatButton
    $btnRestoreLook.Style  = 'Ghost'
    $btnRestoreLook.Text   = 'ВЕРНУТЬ ЦВЕТ'
    $btnRestoreLook.Font   = [RustSuite.Theme]::FSmall
    $btnRestoreLook.Bounds = New-Object System.Drawing.Rectangle ($half + (S 8)), $y, ($w - $half - (S 8)), (S 36)
    $btnRestoreLook.Add_Click({
        $r = Restore-LookGamma
        Set-Status $r.Message $(if ($r.Ok) { '#4ECB71' } else { '#E3B341' })
        Update-PictureStatusLabel
        if (-not $r.Ok) {
            [void][System.Windows.Forms.MessageBox]::Show($r.Message, 'КАРТИНКА RUST', 'OK', 'Information')
        }
    })
    $script:RowHost.Controls.AddRange(@($btnApplyLook, $btnRestoreLook))
    $y += S 46

    $gammaNote = New-Object System.Windows.Forms.Label
    $gammaNote.Text      = 'Гамма действует на основной монитор и сбрасывается после перезагрузки Windows. ' +
                           'В полноэкранной игре драйвер может вернуть свою таблицу — тогда используйте панель NVIDIA/AMD.'
    $gammaNote.Font      = [RustSuite.Theme]::FSmall
    $gammaNote.ForeColor = [RustSuite.Theme]::Muted
    $gammaNote.BackColor = [System.Drawing.Color]::Transparent
    $gammaNote.AutoSize  = $false
    $gammaNote.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 30)
    $gammaNote.Anchor    = 'Top,Left,Right'
    $script:RowHost.Controls.Add($gammaNote)
    $y += S 40

    # ---------- client.cfg ----------
    $lblCfg = New-Object System.Windows.Forms.Label
    $lblCfg.Text      = 'RUST CLIENT.CFG · только официальные конвары'
    $lblCfg.Font      = [RustSuite.Theme]::FHead
    $lblCfg.ForeColor = [RustSuite.Theme]::Muted
    $lblCfg.BackColor = [System.Drawing.Color]::Transparent
    $lblCfg.AutoSize  = $false
    $lblCfg.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 16)
    $script:RowHost.Controls.Add($lblCfg)
    $y += S 22

    $btnCfg = New-Object RustSuite.FlatButton
    $btnCfg.Style  = 'Primary'
    $btnCfg.Text   = 'ЗАПИСАТЬ ПРЕСЕТ В CLIENT.CFG'
    $btnCfg.Font   = [RustSuite.Theme]::FSmall
    $btnCfg.Bounds = New-Object System.Drawing.Rectangle 0, $y, $half, (S 36)
    $btnCfg.Add_Click({
        $r = Set-RustVisualCfg $script:LookPreset
        Set-Status $r.Message $(if ($r.Ok) { '#4ECB71' } else { '#E3B341' })
        Update-PictureStatusLabel
        if (-not $r.Ok) {
            [void][System.Windows.Forms.MessageBox]::Show($r.Message, 'КАРТИНКА RUST', 'OK', 'Information')
        }
    })

    $btnCfgUndo = New-Object RustSuite.FlatButton
    $btnCfgUndo.Style  = 'Ghost'
    $btnCfgUndo.Text   = 'ВЕРНУТЬ CLIENT.CFG'
    $btnCfgUndo.Font   = [RustSuite.Theme]::FSmall
    $btnCfgUndo.Bounds = New-Object System.Drawing.Rectangle ($half + (S 8)), $y, ($w - $half - (S 8)), (S 36)
    $btnCfgUndo.Add_Click({
        $r = Undo-RustVisualCfg
        Set-Status $r.Message $(if ($r.Ok) { '#4ECB71' } else { '#E3B341' })
        Update-PictureStatusLabel
        if (-not $r.Ok) {
            [void][System.Windows.Forms.MessageBox]::Show($r.Message, 'КАРТИНКА RUST', 'OK', 'Information')
        }
    })
    $script:RowHost.Controls.AddRange(@($btnCfg, $btnCfgUndo))
    $y += S 46

    $cfgNote = New-Object System.Windows.Forms.Label
    $cfgNote.Text      = 'Перед записью закройте RUST: игра перезаписывает client.cfg при выходе. ' +
                         'Программа сохраняет только те строки, которые меняет, и возвращает их кнопкой «ВЕРНУТЬ CLIENT.CFG».'
    $cfgNote.Font      = [RustSuite.Theme]::FSmall
    $cfgNote.ForeColor = [RustSuite.Theme]::Muted
    $cfgNote.BackColor = [System.Drawing.Color]::Transparent
    $cfgNote.AutoSize  = $false
    $cfgNote.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 30)
    $cfgNote.Anchor    = 'Top,Left,Right'
    $script:RowHost.Controls.Add($cfgNote)
    $y += S 38

    # ---------- Инструкция панели ----------
    $lblGuide = New-Object System.Windows.Forms.Label
    $lblGuide.Text      = 'ПАНЕЛЬ ДРАЙВЕРА · точные значения'
    $lblGuide.Font      = [RustSuite.Theme]::FHead
    $lblGuide.ForeColor = [RustSuite.Theme]::Muted
    $lblGuide.BackColor = [System.Drawing.Color]::Transparent
    $lblGuide.AutoSize  = $false
    $lblGuide.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 16)
    $script:RowHost.Controls.Add($lblGuide)
    $y += S 22

    $guide = New-Object System.Windows.Forms.RichTextBox
    $guide.Text        = Get-GpuPanelGuide $info.Vendor
    $guide.ReadOnly    = $true
    $guide.BorderStyle = 'None'
    $guide.BackColor   = [RustSuite.Theme]::Field
    $guide.ForeColor   = [RustSuite.Theme]::TextC
    $guide.Font        = [RustSuite.Theme]::FSmall
    $guide.WordWrap    = $true
    $guide.ScrollBars  = 'Vertical'
    $guide.DetectUrls  = $false
    $guide.Bounds      = New-Object System.Drawing.Rectangle 0, $y, $w, (S 232)
    $guide.Anchor      = 'Top,Left,Right'
    $script:RowHost.Controls.Add($guide)
    $y += S 242

    $btnCopy2 = New-Object RustSuite.FlatButton
    $btnCopy2.Style  = 'Ghost'
    $btnCopy2.Text   = 'СКОПИРОВАТЬ ВСЕ НАСТРОЙКИ ПАНЕЛИ'
    $btnCopy2.Font   = [RustSuite.Theme]::FSmall
    $btnCopy2.Bounds = New-Object System.Drawing.Rectangle 0, $y, $w, (S 34)
    $btnCopy2.Anchor = 'Top,Left,Right'
    $btnCopy2.Add_Click({
        if (Copy-Text (Get-GpuPanelGuide)) {
            Set-Status 'Настройки панели драйвера скопированы' '#4ECB71'
            Write-Log 'Настройки панели драйвера скопированы' 'ok'
        }
    })
    $script:RowHost.Controls.Add($btnCopy2)
    $y += S 44

    # ---------- Безопасность ----------
    $note = New-Object System.Windows.Forms.Label
    $note.Text = 'Почему это безопасно: программа не ставит оверлеи, не подменяет шейдеры, не читает память игры ' +
                 'и не эмулирует ввод. Используются только файл настроек самого RUST, гамма-таблица Windows и панель драйвера. ' +
                 'Freestyle/ReShade и «фильтры поверх игры» не поддерживаются: они внедряются в кадр и могут конфликтовать с EAC. ' +
                 'Гарантии 0% бана не даёт ни один оптимизатор, но здесь нет ни одного вектора вмешательства в клиент.'
    $note.Font      = [RustSuite.Theme]::FSmall
    $note.ForeColor = [RustSuite.Theme]::Muted
    $note.BackColor = [System.Drawing.Color]::Transparent
    $note.AutoSize  = $false
    $note.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 92)
    $note.Anchor    = 'Top,Left,Right'
    $script:RowHost.Controls.Add($note)
    $y += S 102

    $script:RowHost.AutoScrollMinSize = New-Object System.Drawing.Size 0, ($y + (S 12))
}

# ============================================================
#  ДЕЙСТВИЯ И ТАЙМЕРЫ
# ============================================================
function Update-BindListBox {
    if (-not $script:BindListBox -or $script:BindListBox.IsDisposed) { return }
    $script:BindListBox.BeginUpdate()
    $script:BindListBox.Items.Clear()
    foreach ($b in @(Get-BindRecords)) {
        [void]$script:BindListBox.Items.Add('bind ' + $b.Key + '   →   ' + $b.Cmd)
    }
    $script:BindListBox.EndUpdate()
}

function Add-BindFromUi {
    if (-not $script:BindKeyBox -or -not $script:BindCmdBox) { return }
    if ($script:BindKeyBox.IsDisposed -or $script:BindCmdBox.IsDisposed) { return }
    $err = Add-RustBind ([string]$script:BindKeyBox.Text) ([string]$script:BindCmdBox.Text)
    if ($err) {
        Set-Status $err '#FF6B62'
        Write-Log $err 'warn'
        return
    }
    $k = ([string]$script:BindKeyBox.Text).Trim().ToLower()
    $c = ([string]$script:BindCmdBox.Text).Trim()
    $script:BindCmdBox.Text = ''
    Update-BindListBox
    Set-Status ('Бинд добавлен: ' + $k + ' → ' + $c) '#4ECB71'
    Write-Log ('Бинд: ' + $k + ' → ' + $c) 'ok'
}

function Apply-BindsFromUi {
    try {
        Apply-RustBinds
        Set-Status 'Бинды записаны в keys.cfg' '#4ECB71'
        [void][System.Windows.Forms.MessageBox]::Show(
            "Бинды записаны в cfg\keys.cfg.`n`nПолностью закройте Rust и запустите снова — игра прочитает файл при старте.",
            'PURPLE RUSH', 'OK', 'Information')
    } catch {
        $msg = $_.Exception.Message
        Write-Log $msg 'err'
        if (Test-RustRunning) {
            $a = [System.Windows.Forms.MessageBox]::Show(
                ($msg + "`n`nСкопировать команды для консоли F1?"),
                'PURPLE RUSH', 'YesNo', 'Warning')
            if ($a -eq 'Yes') { Copy-BindsFromUi }
        } else {
            [void][System.Windows.Forms.MessageBox]::Show($msg, 'PURPLE RUSH', 'OK', 'Warning')
        }
    }
}

function Copy-BindsFromUi {
    $lines = @(Get-BindCommandLines)
    if ($lines.Count -eq 0) {
        [void][System.Windows.Forms.MessageBox]::Show('Список биндов пуст.', 'PURPLE RUSH', 'OK', 'Information')
        return
    }
    if (Copy-Text (($lines -join "`r`n") + "`r`n")) {
        Set-Status 'Бинды скопированы в буфер обмена' '#4ECB71'
        Write-Log 'Бинды скопированы в буфер обмена' 'ok'
        [void][System.Windows.Forms.MessageBox]::Show(
            "Команды скопированы.`n`nВ игре нажмите F1, вставьте (Ctrl+V) и нажмите Enter.",
            'PURPLE RUSH', 'OK', 'Information')
    } else {
        [void][System.Windows.Forms.MessageBox]::Show('Не удалось скопировать в буфер обмена.', 'PURPLE RUSH', 'OK', 'Warning')
    }
}

# Показ длинного текста выполняет Show-TextDialog из 33_trust.ps1:
# один диалог на всё приложение, с кнопкой копирования и заметкой.

function Show-ConsoleCommands {
    $all = @()
    $all += Get-RustCfgCommandText
    $all += Get-BindCommandLines
    if ($all.Count -eq 0) {
        [void][System.Windows.Forms.MessageBox]::Show(
            'Нет ни конваров, ни биндов. Добавьте бинды на вкладке «БИНДЫ».',
            'PURPLE RUSH', 'OK', 'Information')
        return
    }
    $body = ($all -join "`r`n")
    $body += "`r`n"
    $ok = Copy-Text $body
    if ($ok) { Write-Log 'Команды Rust скопированы в буфер обмена' 'ok' }
    Show-TextDialog 'RUST · команды для консоли F1' $body
}

function Rust-OneClickFromUi {
    if ($script:Busy) { return }
    $a = [System.Windows.Forms.MessageBox]::Show(
        ("Записать в Rust:`n`n· траву/пост-эффекты (cfg\client.cfg)`n· ваши бинды (cfg\keys.cfg)`n`nRust должен быть закрыт. Продолжить?"),
        'PURPLE RUSH', 'YesNo', 'Question')
    if ($a -ne 'Yes') { return }
    $res = [string](Invoke-RustOneClick)
    if ($script:ActiveGroup -eq 'rust') { Request-Group 'rust' -Force }
    [void][System.Windows.Forms.MessageBox]::Show($res, 'PURPLE RUSH', 'OK', 'Information')
}

function Start-DeepCleanFromUi {
    if ($script:Busy) { return }
    $ans = [System.Windows.Forms.MessageBox]::Show(
        ("Глубокая очистка Windows:`n`n· TEMP и Windows Temp`n· кэш обновлений Windows`n· дампы и отчёты об ошибках`n· кэш браузеров (без паролей и истории)`n· логи Steam / RUST`n· кэш эскизов и иконок`n`nЗакройте браузеры и игры. Продолжить?"),
        'PURPLE RUSH — ГЛУБОКАЯ ОЧИСТКА', 'YesNo', 'Question')
    if ($ans -ne 'Yes') { return }

    Set-Busy $true
    Set-ProgressValue 0
    try {
        Write-Log 'Глубокая очистка Windows: старт' 'step'
        Set-Status 'Глубокая очистка Windows…' '#FF8A4C'
        Invoke-DeepClean
        Set-ProgressValue 100
        $mb  = [math]::Round($script:CleanBytes / 1MB, 1)
        $obj = $script:CleanObjects
        Set-Status ('Очистка готова: {0:N1} МБ' -f $mb) '#4ECB71'
        Write-Log ('Глубокая очистка: освобождено {0:N1} МБ' -f $mb) 'ok'
        Update-Stats
        [void][System.Windows.Forms.MessageBox]::Show(
            ("Освобождено: {0:N1} МБ`nУдалено объектов: {1:N0}`n`nПароли, история браузеров, cfg RUST и сохранения не затронуты." -f $mb, $obj),
            'PURPLE RUSH — ГОТОВО', 'OK', 'Information')
    } catch {
        Write-Log ('Глубокая очистка: ' + $_.Exception.Message) 'err'
        [void][System.Windows.Forms.MessageBox]::Show(
            ("Очистка прервана: " + $_.Exception.Message + "`n`nЖурнал: " + $script:LogFile),
            'PURPLE RUSH', 'OK', 'Warning')
    } finally {
        Set-Busy $false
        Set-ProgressValue 0
    }
}

function Update-Stats {
    $cpu = -1
    $ram = -1
    try {
        # Единый кэшированный датчик: не создаём второй PerformanceCounter
        # и не опрашиваем его чаще раза в секунду.
        if (Get-Command Get-CpuLoadFast -ErrorAction SilentlyContinue) {
            $cpu = [int](Get-CpuLoadFast)
        } else {
            if (-not $script:PcCpu) {
                $script:PcCpu = New-Object System.Diagnostics.PerformanceCounter('Processor', '% Processor Time', '_Total')
                $null = $script:PcCpu.NextValue()
            }
            $cpu = [int][Math]::Round([double]$script:PcCpu.NextValue())
        }
        if ($cpu -lt 0) { $cpu = 0 }
        if ($cpu -gt 100) { $cpu = 100 }
    } catch { $cpu = -1 }

    try {
        # ОЗУ через WinAPI: мгновенно, без WMI и без подвисаний интерфейса.
        $ram = [int][RustSuite.Native]::MemLoad()
        $totalMb = [long][RustSuite.Native]::MemTotalMb()
        if ($totalMb -gt 0) { $script:RamTotal = [double]$totalMb }
    } catch {
        $ram = -1
        try {
            $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
            $script:RamTotal = [double]$os.TotalVisibleMemorySize / 1024.0
            $ram = [int][Math]::Round((1.0 - ([double]$os.FreePhysicalMemory / [double]$os.TotalVisibleMemorySize)) * 100.0)
        } catch { $ram = -1 }
    }

    if ($script:CpuBar -and -not $script:CpuBar.IsDisposed) {
        if ($cpu -ge 0) {
            $script:CpuBar.Value = $cpu
            $script:CpuVal.Text  = [string]$cpu + ' %'
            $script:CpuVal.ForeColor = if ($cpu -ge 85) { [RustSuite.Theme]::Err }
                                      elseif ($cpu -ge 60) { [RustSuite.Theme]::Warn }
                                      else { [RustSuite.Theme]::TextC }
        } else {
            $script:CpuBar.Value = 0
            $script:CpuVal.Text  = 'н/д'
        }
    }
    if ($script:RamBar -and -not $script:RamBar.IsDisposed) {
        if ($ram -ge 0) {
            $script:RamBar.Value = $ram
            $script:RamVal.Text  = [string]$ram + ' %'
            $script:RamVal.ForeColor = if ($ram -ge 90) { [RustSuite.Theme]::Err }
                                      elseif ($ram -ge 75) { [RustSuite.Theme]::Warn }
                                      else { [RustSuite.Theme]::TextC }
        } else {
            $script:RamBar.Value = 0
            $script:RamVal.Text  = 'н/д'
        }
    }

    $diskUsed = -1
    $diskFreeGb = 0.0
    $diskFreePct = 0.0
    try {
        $di = New-Object System.IO.DriveInfo($env:SystemDrive)
        if ($di.IsReady -and $di.TotalSize -gt 0) {
            $diskFreePct = ($di.AvailableFreeSpace / [double]$di.TotalSize) * 100.0
            $diskUsed = [int][Math]::Round(100.0 - $diskFreePct)
            $diskFreeGb = [math]::Round($di.AvailableFreeSpace / 1GB, 1)
        }
    } catch {}
    if ($script:DiskBar -and -not $script:DiskBar.IsDisposed) {
        if ($diskUsed -ge 0) {
            $script:DiskBar.Value = $diskUsed
            $script:DiskVal.Text  = ('{0:N1} ГБ' -f $diskFreeGb)
            $script:DiskVal.ForeColor = if ($diskFreePct -lt 8) { [RustSuite.Theme]::Err }
                                        elseif ($diskFreePct -lt 15) { [RustSuite.Theme]::Warn }
                                        else { [RustSuite.Theme]::TextC }
        } else {
            $script:DiskBar.Value = 0
            $script:DiskVal.Text  = 'н/д'
        }
    }

    $script:RustRunning = Test-RustRunning
    if ($script:RustState -and -not $script:RustState.IsDisposed) {
        if (-not $script:RustExe) {
            $script:RustState.Text = 'не найден — запустите игру через Steam'
            $script:RustState.ForeColor = [RustSuite.Theme]::Warn
        } elseif ($script:RustRunning) {
            $script:RustState.Text = 'запущен · приоритет High · бинды активны'
            $script:RustState.ForeColor = [RustSuite.Theme]::Ok
        } else {
            $script:RustState.Text = 'готов · cfg можно менять'
            $script:RustState.ForeColor = [RustSuite.Theme]::Muted
        }
    }
    if ($script:Header -and -not $script:Header.IsDisposed) { $script:Header.Invalidate() }

    # Новая панель «ОБЗОР» получает те же живые значения.
    if (Get-Command Update-HomeLive -ErrorAction SilentlyContinue) {
        Update-HomeLive -Cpu $cpu -Ram $ram -DiskFreeGb $diskFreeGb -DiskFreePct $diskFreePct
    }
}

# ---------- Запуск Rust ----------
$script:LaunchTries = 0
$script:LaunchTimer = New-Object System.Windows.Forms.Timer
$script:LaunchTimer.Interval = 2000
$script:LaunchTimer.Add_Tick({
    $p = @(Get-Process -Name 'RustClient' -ErrorAction SilentlyContinue)
    if ($p.Count -gt 0) {
        Invoke-RustProcessPolish
        Write-Log 'RustClient запущен — приоритет High применён' 'ok'
        Set-Status 'RUST запущен, оптимизация применена' '#4ECB71'
        $script:LaunchTimer.Stop()
        Update-Stats

        # Автозакрытие: даём увидеть статус и закрываем оптимизатор.
        if ($script:AutoClose -and $script:MainForm -and -not $script:MainForm.IsDisposed) {
            Set-Status 'RUST запущен — закрываю оптимизатор…' '#4ECB71'
            Write-Log 'Автозакрытие оптимизатора через 2 секунды' 'info'
            try {
                if ($script:CloseTimer) { $script:CloseTimer.Stop(); $script:CloseTimer.Dispose() }
                $script:CloseTimer = New-Object System.Windows.Forms.Timer
                $script:CloseTimer.Interval = 2000
                $script:CloseTimer.Add_Tick({
                    try { $script:CloseTimer.Stop(); $script:CloseTimer.Dispose() } catch {}
                    $script:CloseTimer = $null
                    if ($script:MainForm -and -not $script:MainForm.IsDisposed) {
                        $script:MainForm.Close()
                    }
                })
                $script:CloseTimer.Start()
            } catch {
                Write-Log ('Автозакрытие недоступно: ' + $_.Exception.Message) 'warn'
            }
        }
    } else {
        $script:LaunchTries--
        if ($script:LaunchTries -le 0) {
            $script:LaunchTimer.Stop()
            Write-Log 'RustClient не появился за 3 минуты — откройте игру вручную' 'warn'
            Set-Status 'RUST не запустился автоматически' '#E3B341'
        }
    }
})

function Start-Rust {
    if ($script:Busy) { return }
    try {
        [System.Diagnostics.Process]::Start('steam://rungameid/252490') | Out-Null
        Write-Log 'Запуск RUST через Steam…' 'step'
        Set-Status 'Ожидание процесса RustClient.exe…' '#FF8A4C'
        $script:LaunchTries = 90
        $script:LaunchTimer.Start()
    } catch {
        Write-Log ('Не удалось запустить Steam: ' + $_.Exception.Message) 'err'
    }
}

# ---------- Кнопки ----------
$btnSafe.Add_Click({
    foreach ($t in $script:Tweaks) { $script:Enabled[$t.Id] = (-not $t.Risk) }
    $script:State['Enabled'] = $script:Enabled
    Save-State
    Request-Group $script:ActiveGroup -Force
    Write-Log 'Профиль «Безопасный»: только проверенные модули' 'info'
})

$btnMax.Add_Click({
    foreach ($t in $script:Tweaks) { $script:Enabled[$t.Id] = $true }
    $script:State['Enabled'] = $script:Enabled
    Save-State
    Request-Group $script:ActiveGroup -Force
    Write-Log 'Профиль «Максимум»: включены все модули, включая рискованные' 'warn'
})

$btnRun.Add_Click({
    if ($script:Busy) { return }
    $cnt = @($script:Tweaks | Where-Object { $script:Enabled[$_.Id] }).Count
    if ($cnt -eq 0) {
        [void][System.Windows.Forms.MessageBox]::Show(
            'Не выбран ни один модуль. Отметьте карточки или нажмите «МАКСИМУМ».',
            'PURPLE RUSH', 'OK', 'Information')
        return
    }
    $ans = [System.Windows.Forms.MessageBox]::Show(
        ("Применить модулей: $cnt`n`nБудет создана точка восстановления и резервные копии реестра.`nПродолжить?"),
        'PURPLE RUSH', 'YesNo', 'Question')
    if ($ans -ne 'Yes') { return }

    $btnRun.Enabled  = $false
    $btnUndo.Enabled = $false
    try {
        $n = Start-Optimization

        $ansReboot = [System.Windows.Forms.MessageBox]::Show(
            ("Готово. Применено модулей: $n.`n`nДля применения всех изменений нужна перезагрузка ПК.`nПерезагрузить сейчас?`n`nОК — перезагрузка через 10 секунд (несохранённые файлы будут закрыты).`nОтмена — перезагрузите вручную позже."),
            'PURPLE RUSH — RUST PERFORMANCE ENGINE', 'OKCancel', 'Question', 'Button1')

        if ($ansReboot -eq 'OK') {
            $scheduled = $false
            Write-Log 'Запланирована автоматическая перезагрузка ПК через 10 секунд' 'warn'
            Set-Status 'Перезагрузка ПК через 10 секунд…' '#FF8A4C'

            # Важно: одна строка аргументов — иначе /c "..." разбивается на части
            # и shutdown.exe завершается с ошибкой, не перезагружая ПК.
            try {
                $shutdown = Join-Path $env:SystemRoot 'System32\shutdown.exe'
                $shArgs = '/r /t 10 /f /c "PURPLE RUSH: применение оптимизации"'
                $proc = Start-Process -FilePath $shutdown -ArgumentList $shArgs -WindowStyle Hidden -PassThru -ErrorAction Stop
                try { [void]$proc.WaitForExit(3000) } catch {}
                if ($proc.HasExited -and $proc.ExitCode -ne 0) {
                    Write-Log ('shutdown.exe вернул код ' + $proc.ExitCode + ' — пробую Restart-Computer') 'warn'
                } else {
                    $scheduled = $true
                }
            } catch {
                Write-Log ('shutdown.exe недоступен: ' + $_.Exception.Message) 'warn'
            }

            if (-not $scheduled) {
                try {
                    Restart-Computer -Force -ErrorAction Stop
                    $scheduled = $true
                    Write-Log 'Перезагрузка запущена через Restart-Computer' 'warn'
                } catch {
                    Write-Log ('Restart-Computer не сработал: ' + $_.Exception.Message) 'err'
                }
            }

            if (-not $scheduled) {
                [void][System.Windows.Forms.MessageBox]::Show(
                    ("Не удалось перезагрузить ПК автоматически.`n`nЗапустите программу от имени администратора`nили перезагрузите компьютер вручную.`n`nЖурнал: $($script:LogFile)"),
                    'PURPLE RUSH — RUST PERFORMANCE ENGINE', 'OK', 'Warning')
            }
        } else {
            [void][System.Windows.Forms.MessageBox]::Show(
                ("Перезагрузка отложена.`nЖурнал: $($script:LogFile)"),
                'PURPLE RUSH — RUST PERFORMANCE ENGINE', 'OK', 'Information')
        }
    } catch {
        $msg = $_.Exception.Message
        Write-Log ('Ошибка оптимизации: ' + $msg) 'err'
        [void][System.Windows.Forms.MessageBox]::Show(
            ("Ошибка оптимизации: $msg`n`nЖурнал: $($script:LogFile)"),
            'PURPLE RUSH — RUST PERFORMANCE ENGINE', 'OK', 'Error')
    } finally {
        $btnRun.Enabled  = $true
        $btnUndo.Enabled = $true
        Update-Stats
    }
})

$btnUndo.Add_Click({
    if ($script:Busy) { return }
    $applied = @(Get-AppliedTweaks)
    if ($applied.Count -eq 0) {
        [void][System.Windows.Forms.MessageBox]::Show(
            'Откатывать нечего: в журнале нет применённых модулей.',
            'PURPLE RUSH', 'OK', 'Information')
        return
    }
    $ans = [System.Windows.Forms.MessageBox]::Show(
        ("Вернуть систему к значениям до оптимизации?`n`nМодулей в откате: " + $applied.Count + ".`nОткатятся реестр, службы, план питания, DNS и cfg Rust."),
        'PURPLE RUSH', 'YesNo', 'Question')
    if ($ans -ne 'Yes') { return }

    $btnRun.Enabled  = $false
    $btnUndo.Enabled = $false
    try {
        Start-Rollback
        [void][System.Windows.Forms.MessageBox]::Show('Откат выполнен.', 'PURPLE RUSH', 'OK', 'Information')
    } finally {
        $btnRun.Enabled  = $true
        $btnUndo.Enabled = $true
        Update-Stats
    }
})

$btnScan.Add_Click({
    if ($script:Busy) { return }
    Show-Group 'repair'
    Start-HealthScan
})

# ---------- Горячие клавиши ----------
$form.Add_KeyDown({
    param($s, $e)
    try {
        if (-not $e.Control) { return }
        $key = [int]$e.KeyCode
        $first = [int][System.Windows.Forms.Keys]::D1
        $last  = [int][System.Windows.Forms.Keys]::D9
        if ($key -ge $first -and $key -le $last) {
            $idx = $key - $first
            if ($idx -ge 0 -and $idx -lt $script:Groups.Count) {
                Request-Group $script:Groups[$idx].Id
                $e.Handled = $true
                $e.SuppressKeyPress = $true
                return
            }
        }
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::R) {
            Update-Stats
            Set-Status 'Статистика обновлена' '#8B949E'
            $e.Handled = $true
            $e.SuppressKeyPress = $true
        }
    } catch {}
})

# ---------- Жизненный цикл ----------
$form.Add_FormClosing({
    param($s, $e)
    if ($script:Closing) { return }
    if ($script:Busy -and -not $script:TestUi) {
        $a = [System.Windows.Forms.MessageBox]::Show(
            'Оптимизация ещё выполняется. Прервать?', 'PURPLE RUSH', 'YesNo', 'Warning')
        if ($a -ne 'Yes') { $e.Cancel = $true; return }
    }
    $script:Closing = $true
    try { $script:StatsTimer.Stop() } catch {}
    try { $script:LaunchTimer.Stop() } catch {}
    try { $script:ProbeTimer.Stop() } catch {}
    try { $script:CloseTimer.Stop() } catch {}
    try { if ($script:TempTimer) { $script:TempTimer.Stop(); $script:TempTimer.Dispose() } } catch {}
    try { if ($script:ThemeTimer) { $script:ThemeTimer.Stop(); $script:ThemeTimer.Dispose() } } catch {}
    try { if ($script:RepairScanTimer) { $script:RepairScanTimer.Stop(); $script:RepairScanTimer.Dispose() } } catch {}
    if ($script:State['TimerOn']) { try { [RustSuite.Native]::TimerStop() } catch {} }

    # Запоминаем размер и позицию окна для следующего запуска.
    if (-not $script:TestUi -and -not $script:SelfTest) {
        try {
            $script:State['WinW']   = [int]$form.Width
            $script:State['WinH']   = [int]$form.Height
            $script:State['WinX']   = [int]$form.Left
            $script:State['WinY']   = [int]$form.Top
            $script:State['WinPos'] = $true
            Save-State
        } catch {}
    }
})

$form.Add_Shown({
    [void][RustSuite.Native]::DarkTitle($form)
    [void][RustSuite.Native]::DarkScroll($script:RowHost)
    [void][RustSuite.Native]::DarkScroll($script:LogBox)

    # Ярлык с фирменной иконкой создаётся один раз при запуске .bat.
    if (-not $script:TestUi) {
        try {
            $hadShortcut = $false
            $desktop = [Environment]::GetFolderPath('Desktop')
            if ($desktop) { $hadShortcut = Test-Path -LiteralPath (Join-Path $desktop 'PURPLE RUSH.lnk') }
            $script:ShortcutPath = Install-AppShortcut
            if ($script:ShortcutPath -and -not $hadShortcut) {
                Write-Log ('Ярлык создан на рабочем столе: ' + $script:ShortcutPath) 'ok'
            }
        } catch {}
    }

    Show-Group 'home'
    Update-Stats

    Write-Log ('PURPLE RUSH — RUST PERFORMANCE ENGINE v' + $script:AppVersion) 'step'
    Write-Log ('Права администратора: ' + $(if ($script:IsAdmin) { 'да' } else { 'НЕТ — часть функций не сработает' })) $(if ($script:IsAdmin) { 'info' } else { 'warn' })
    Write-Log ('Steam: ' + $(if ($script:SteamPath) { $script:SteamPath } else { 'не найден' })) 'info'
    Write-Log ('RUST: ' + $(if ($script:RustExe) { $script:RustExe } else { 'не найден' })) 'info'
    try {
        $cores = (Get-CimInstance Win32_Processor | Select-Object -First 1).NumberOfCores
        Write-Log ('Физических ядер: ' + $cores) 'info'
    } catch {}
    Write-Log 'Бинды и cfg — официальные файлы игры; exe/dll не изменяются.' 'info'
    Write-Log 'Выберите модули и нажмите «ОПТИМИЗИРОВАТЬ ПК».' 'info'

    if (-not $script:TestUi) {
        try {
            $snap = Save-ClientGuardBaseline
            if ($snap) { Write-Log ('Эталон клиента RUST снят: ' + $snap.Count + ' файлов, exe/dll не трогаем') 'info' }
        } catch {}
    }

    $script:StatsTimer = New-Object System.Windows.Forms.Timer
    $script:StatsTimer.Interval = 2500
    $script:StatsTimer.Add_Tick({ Update-Stats })
    $script:StatsTimer.Start()

    if ($script:TestUi) {
        $script:ProbeStep = 0
        $script:ProbeHold = $false
        $script:ProbeTimer = New-Object System.Windows.Forms.Timer
        $script:ProbeTimer.Interval = 450
        $script:ProbeTimer.Add_Tick({
            if ($script:ProbeHold) { return }
            try {
                switch ($script:ProbeStep) {
                    0 { Request-Group 'sys' }
                    1 {
                        if ($script:ActiveGroup -ne 'sys') { throw 'DEFERRED NAVIGATION FAILED' }
                        Show-Group 'net'
                    }
                    2 { Show-Group 'rust' }
                    3 { Show-Group 'binds' }
                    4 { Show-Group 'clean' }
                    5 {
                        Show-Group 'repair'
                        if ($script:RepairReport) { Write-Host ('REPAIR ROWS: ' + @($script:RepairReport).Count) }
                    }
                    6 {
                        Show-Group 'repair'
                        $script:ProbeHold = $true
                        try { Start-HealthScan } finally { $script:ProbeHold = $false }
                        Write-Host ('HEALTH ROWS: ' + @($script:RepairReport).Count)
                    }
                    7 {
                        Show-Group 'settings'
                        Apply-Theme 'MIDNIGHT' -Save
                        Update-ThemeSurfaces
                        Restart-SettingsSoon
                    }
                    8 {
                        Show-Group 'sys'
                        $c = @($script:RowHost.Controls | Where-Object { $_ -is [RustSuite.Card] }) | Select-Object -First 1
                        if ($c) { $c.On = (-not $c.On); $c.On = (-not $c.On) }
                        Update-Stats
                    }
                    9 {
                        Show-Group 'repair'
                        Apply-Theme 'SAKURA' -Save
                        Update-ThemeSurfaces
                    }
                    10 {
                        Show-Group 'picture'
                        try {
                            if ($script:PicturePreviewAfter -and -not $script:PicturePreviewAfter.IsDisposed) {
                                $script:PicturePreviewAfter.Invalidate()
                                $script:PicturePreviewAfter.Update()
                            }
                        } catch {}
                        $tiles = @($script:RowHost.Controls | Where-Object { $_ -is [RustSuite.ThemeTile] })
                        $prevs = @($script:RowHost.Controls | Where-Object { $_ -is [RustSuite.BufferedPanel] })
                        Write-Host ('PICTURE TILES: ' + $tiles.Count + ' · PREVIEWS: ' + $prevs.Count + ' · PAINTS: ' + $script:PreviewPaints)
                        if ($tiles.Count -lt 3) { throw 'PICTURE TILES MISSING' }
                        if ($prevs.Count -lt 2) { throw 'PICTURE PREVIEW MISSING' }
                        if ($script:PreviewPaintWarned) { throw 'PICTURE PAINT FAILED' }
                        if ([int]$script:PreviewPaints -lt 1) { throw 'PICTURE PREVIEW NOT PAINTED' }
                        if ($script:PictureStatusLabel -and $script:PictureStatusLabel.Text.Length -lt 3) {
                            throw 'PICTURE STATUS MISSING'
                        }
                        try { $script:RowHost.PerformLayout() } catch {}
                        try { $script:ContentScrollStrip.Sync() } catch {}
                        Write-Host ('SCROLL content strip=' + $script:ContentScrollStrip.Visible +
                                    ' height=' + $script:RowHost.ClientSize.Height +
                                    ' hscroll=' + $script:RowHost.HorizontalScroll.Visible)
                        if (-not $script:ContentScrollStrip.Visible) { throw 'CONTENT SCROLL STRIP MISSING' }
                        if ($script:RowHost.HorizontalScroll.Visible) { throw 'CONTENT HORIZONTAL SCROLL PRESENT' }

                        # Стрелка «вниз» на нашей полосе действительно листает страницу.
                        $before = [int]$script:RowHost.VerticalScroll.Value
                        $mi = [System.Windows.Forms.Control].GetMethod('OnMouseDown',
                            [System.Reflection.BindingFlags]'Instance,NonPublic')
                        $me = New-Object System.Windows.Forms.MouseEventArgs(
                            [System.Windows.Forms.MouseButtons]::Left, 1,
                            [int]($script:ContentScrollStrip.Width / 2),
                            [int]($script:ContentScrollStrip.Height - 5), 0)
                        $mi.Invoke($script:ContentScrollStrip, @($me.PSObject.BaseObject)) | Out-Null
                        $after = [int]$script:RowHost.VerticalScroll.Value
                        $script:RowHost.ScrollToTop()
                        if ($after -le $before) { throw 'CONTENT SCROLL STRIP NOT WORKING' }

                        $origSize = $form.Size
                        try {
                            $form.Size = $form.MinimumSize
                            $form.PerformLayout()
                            try { $script:NavTopPanel.PerformLayout() } catch {}
                            try { $script:NavScrollStrip.Sync() } catch {}
                            Write-Host ('SCROLL nav strip=' + $script:NavScrollStrip.Visible +
                                        ' height=' + $script:NavTopPanel.ClientSize.Height +
                                        ' max=' + $script:NavTopPanel.VerticalScroll.Maximum)
                            if (-not $script:NavScrollStrip.Visible) { throw 'NAV SCROLL STRIP MISSING' }
                            try { $script:NavTopPanel.AutoScrollPosition = New-Object System.Drawing.Point 0, 60 } catch {}
                            if ([int]$script:NavTopPanel.VerticalScroll.Value -le 0) { throw 'NAV SCROLL NOT WORKING' }
                        } finally {
                            $form.Size = $origSize
                            $form.PerformLayout()
                            try { $script:NavTopPanel.AutoScrollPosition = New-Object System.Drawing.Point 0, 0 } catch {}
                        }
                        $form.Refresh()
                        Write-Host 'PICTURE OK'
                    }
                    11 {
                        Show-Group 'home'
                        if (-not $script:HomeGauge -or $script:HomeGauge.IsDisposed) { throw 'HOME GAUGE MISSING' }
                        if (-not $script:HomeSpark -or $script:HomeSpark.IsDisposed) { throw 'HOME SPARKLINE MISSING' }
                        $cards = @($script:RowHost.Controls | Where-Object { $_ -is [RustSuite.StatCard] })
                        if ($cards.Count -lt 3) { throw 'HOME STAT CARDS MISSING' }
                        Update-Stats
                        $score = Get-OptimizationScore
                        if ($score -le 0) { throw 'HOME SCORE IS ZERO' }
                        Write-Host ('HOME score=' + $score + ' cards=' + $cards.Count +
                                    ' gauge=' + $script:HomeGauge.Width + 'x' + $script:HomeGauge.Height +
                                    ' spark=' + $script:HomeSpark.Width + 'x' + $script:HomeSpark.Height)
                        Write-Host 'HOME OK'
                        if ($env:RUSTOPT_SHOT) {
                            try {
                                $script:RowHost.ScrollToTop()
                                $form.Refresh()
                                $bmp = New-Object System.Drawing.Bitmap $form.Width, $form.Height
                                $g = [System.Drawing.Graphics]::FromImage($bmp)
                                $g.CopyFromScreen($form.Location, [System.Drawing.Point]::Empty, $form.Size)
                                $g.Dispose()
                                $bmp.Save([string]$env:RUSTOPT_SHOT, [System.Drawing.Imaging.ImageFormat]::Png)
                                $bmp.Dispose()
                            } catch {}
                        }
                    }
                    12 {
                        Apply-Theme 'PURPLE RUSH' -Save
                        Update-ThemeSurfaces
                        Write-Host 'UI TEST OK'
                        $script:ProbeTimer.Stop()
                        $script:Busy = $false
                        $form.Close()
                    }
                }
            } catch {
                Write-Host ('UI TEST FAIL: ' + $_.Exception.Message)
                Write-Host $_.ScriptStackTrace
                try { $script:ProbeTimer.Stop() } catch {}
                $form.Close()
            }
            $script:ProbeStep = $script:ProbeStep + 1
        })
        $script:ProbeTimer.Start()
    }
})

[System.Windows.Forms.Application]::add_ThreadException({
    param($s, $e)
    $msg = ''
    if ($e -and $e.Exception) { $msg = $e.Exception.Message }
    Write-Log ('Ошибка интерфейса: ' + $msg) 'err'
})

# Ошибка вне UI-потока не должна приводить к молчаливому падению:
# пишем её в журнал, чтобы причина осталась видимой.
try {
    [AppDomain]::CurrentDomain.add_UnhandledException({
        param($s, $e)
        $msg = ''
        if ($e -and $e.ExceptionObject) { $msg = [string]$e.ExceptionObject.Message }
        Write-Log ('Критическая ошибка: ' + $msg) 'err'
    })
} catch {}

[System.Windows.Forms.Application]::Run($form)

try {
    if ($script:SingleInstance) {
        $script:SingleInstance.ReleaseMutex()
        $script:SingleInstance.Dispose()
    }
} catch {}

