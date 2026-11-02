# ============================================================
#  PURPLE RUSH — RUST PERFORMANCE ENGINE  v3.0
#  Оптимизация Windows под игру RUST + официальные cfg/бинды + мониторинг + темы
#  Запуск: RustOptimizer.bat (права администратора)
# ============================================================
param([switch]$SelfTest, [switch]$TestUi)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

$script:AppVersion   = '3.1'
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
$script:ActiveGroup  = 'sys'
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
$script:CpuVal       = $null
$script:RamVal       = $null
$script:RustState    = $null
$script:Header       = $null

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
if (-not ($script:State -is [hashtable])) { $script:State = @{} }

function Save-State {
    if ($script:SuppressSave) { return }
    try { $script:State | Export-Clixml -LiteralPath $script:StateFile -Depth 6 -Force } catch {}
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
    'grass.displacement false',
    'graphics.shafts false',
    'graphics.dof false',
    'fps.graph 0'
)

$script:RustCfgManaged = @('grass.displacement', 'graphics.shafts', 'graphics.dof', 'fps.graph')

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
    'grass.displacement false',
    'grass.shadow.onlyself false',
    'grass.distance 0',
    'graphics.shafts false',
    'graphics.dof false',
    'graphics.shadowdistance 0',
    'shadow.distance 0',
    'graphics.quality 0',
    'global.quality 0',
    'global.render_scale 0.8',
    'graphics.drawdistance 400',
    'terrain.quality 0',
    'graphics.antialiasing false',
    'graphics.parallaxbuildings false',
    'graphics.shadowquality 0',
    'graphics.lodbias 0',
    'fps.graph 0',
    'global.pixel_scale 0.9'
)
$script:RustMaxCfgManaged = @('grass.displacement','grass.shadow.onlyself','grass.distance','graphics.shafts','graphics.dof','graphics.shadowdistance','shadow.distance','graphics.quality','global.quality','global.render_scale','graphics.drawdistance','terrain.quality','graphics.antialiasing','graphics.parallaxbuildings','graphics.shadowquality','graphics.lodbias','fps.graph','global.pixel_scale')

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
            for (Control x = c; x != null; x = x.Parent)
            {
                if (x is SmoothScrollPanel) return false;
                if (x is TextBoxBase || x is ListBox || x is ComboBox) return false;
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
        public HeaderPanel()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Theme.PanelBg;
            Anim.Add(this);
        }
        public bool Tick()
        {
            _phase += 0.0038f;
            if (_phase > 1.35f) _phase = -0.25f;
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
                cb.Colors = new Color[] { Color.FromArgb(55, Theme.Accent), Color.FromArgb(150, Theme.AccentLt), Color.FromArgb(55, Theme.Accent) };
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
                cb.Colors = new Color[] { Color.FromArgb(0, Theme.Accent), Color.FromArgb(160, Theme.AccentLt), Color.FromArgb(0, Theme.Accent) };
                cb.Positions = new float[] { 0f, 0.5f, 1f };
                b.InterpolationColors = cb;
                g.FillRectangle(b, glow);
            }
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

    public class ProgressStrip : Control, IAnim
    {
        private double _v, _shown;
        private float _phase;
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
            if (shim) { _phase += 0.025f; if (_phase > 1f) _phase -= 1f; }
            Invalidate();
            return moving || shim;
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
            try { int v = 1; DwmSetWindowAttribute(f.Handle, 20, ref v, 4); DwmSetWindowAttribute(f.Handle, 19, ref v, 4); } catch { }
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
    }
}
'@

try { $null = [RustSuite.Theme] } catch {
    Add-Type -TypeDefinition $script:CsCode -ReferencedAssemblies 'System.Windows.Forms', 'System.Drawing', 'System' -ErrorAction Stop
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
    foreach ($tn in 'Card', 'FlatButton', 'NavButton', 'ProgressStrip', 'Spinner', 'HeaderPanel', 'SlideTween', 'SmoothScrollPanel', 'WheelRouter') {
        try {
            $null = [System.Type]::GetType('RustSuite.' + $tn + ', ' + [RustSuite.Card].Assembly.FullName, $false)
            if (-not [System.Type]::GetType('RustSuite.' + $tn + ', ' + [RustSuite.Card].Assembly.FullName, $false)) {
                Write-Host ("MISSING CONTROL: " + $tn); $fail++
            }
        } catch { Write-Host ("CONTROL ERROR: " + $tn); $fail++ }
    }

    # Перезагрузка: shutdown.exe присутствует, аргументы корректны
    try {
        $shPath = Join-Path $env:SystemRoot 'System32\shutdown.exe'
        if (-not (Test-Path -LiteralPath $shPath)) { Write-Host 'SHUTDOWN NOT FOUND'; $fail++ }
        $shArgs = '/r /t 10 /f /c "PURPLE RUSH: применение оптимизации"'
        if ($shArgs -notmatch '^/r /t 10 ') { Write-Host 'SHUTDOWN ARGS BROKEN'; $fail++ }
    } catch { Write-Host 'SHUTDOWN CHECK ERROR'; $fail++ }

    # Нативные методы таймера и колеса мыши присутствуют
    foreach ($m in 'TimerStart', 'TimerStop', 'MemLoad', 'MemTotalMb', 'MemFreeMb') {
        try {
            if (-not [RustSuite.Native].GetMethod($m)) { Write-Host ('MISSING NATIVE: ' + $m); $fail++ }
        } catch { Write-Host ('NATIVE CHECK ERROR: ' + $m); $fail++ }
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
function S([double]$v) { return [int][math]::Round($v * $script:SC) }

# ---------- Палитры ----------
$script:Themes = @(
    @{ Name='ПУРПУРНАЯ';  Bg=[System.Drawing.Color]::FromArgb(18,10,28);  Panel=[System.Drawing.Color]::FromArgb(28,15,42);  Card=[System.Drawing.Color]::FromArgb(36,20,58);  CardHover=[System.Drawing.Color]::FromArgb(48,28,72);  Border=[System.Drawing.Color]::FromArgb(70,45,110);  Accent=[System.Drawing.Color]::FromArgb(160,60,220);  AccentLt=[System.Drawing.Color]::FromArgb(200,100,255); TextC=[System.Drawing.Color]::FromArgb(245,240,255); Muted=[System.Drawing.Color]::FromArgb(170,150,190); Ok=[System.Drawing.Color]::FromArgb(120,200,120); Warn=[System.Drawing.Color]::FromArgb(240,200,60);   Err=[System.Drawing.Color]::FromArgb(255,100,120); Field=[System.Drawing.Color]::FromArgb(22,14,38) },
    @{ Name='ТЁМНО-СИНЯЯ'; Bg=[System.Drawing.Color]::FromArgb(10,14,26); Panel=[System.Drawing.Color]::FromArgb(16,20,36); Card=[System.Drawing.Color]::FromArgb(22,26,48); CardHover=[System.Drawing.Color]::FromArgb(30,36,60); Border=[System.Drawing.Color]::FromArgb(50,60,100); Accent=[System.Drawing.Color]::FromArgb(60,120,255);  AccentLt=[System.Drawing.Color]::FromArgb(100,160,255); TextC=[System.Drawing.Color]::FromArgb(230,235,245); Muted=[System.Drawing.Color]::FromArgb(140,150,170); Ok=[System.Drawing.Color]::FromArgb(80,220,130);  Warn=[System.Drawing.Color]::FromArgb(250,190,50);   Err=[System.Drawing.Color]::FromArgb(255,90,110);  Field=[System.Drawing.Color]::FromArgb(14,16,30) },
    @{ Name='ИЗУМРУДНАЯ';  Bg=[System.Drawing.Color]::FromArgb(10,20,14); Panel=[System.Drawing.Color]::FromArgb(15,28,20); Card=[System.Drawing.Color]::FromArgb(20,36,28); CardHover=[System.Drawing.Color]::FromArgb(28,48,36); Border=[System.Drawing.Color]::FromArgb(60,100,70);  Accent=[System.Drawing.Color]::FromArgb(60,220,100); AccentLt=[System.Drawing.Color]::FromArgb(100,255,150); TextC=[System.Drawing.Color]::FromArgb(240,245,235); Muted=[System.Drawing.Color]::FromArgb(160,175,160); Ok=[System.Drawing.Color]::FromArgb(100,240,120); Warn=[System.Drawing.Color]::FromArgb(240,210,60);   Err=[System.Drawing.Color]::FromArgb(240,100,110); Field=[System.Drawing.Color]::FromArgb(12,18,14) },
    @{ Name='КРИМСОН';     Bg=[System.Drawing.Color]::FromArgb(26,10,14); Panel=[System.Drawing.Color]::FromArgb(36,15,22); Card=[System.Drawing.Color]::FromArgb(48,22,30); CardHover=[System.Drawing.Color]::FromArgb(60,30,42); Border=[System.Drawing.Color]::FromArgb(110,45,70); Accent=[System.Drawing.Color]::FromArgb(255,60,90);  AccentLt=[System.Drawing.Color]::FromArgb(255,120,140); TextC=[System.Drawing.Color]::FromArgb(245,230,235); Muted=[System.Drawing.Color]::FromArgb(180,140,160); Ok=[System.Drawing.Color]::FromArgb(100,220,120); Warn=[System.Drawing.Color]::FromArgb(255,200,60);   Err=[System.Drawing.Color]::FromArgb(255,100,120); Field=[System.Drawing.Color]::FromArgb(30,12,16) }
)

$script:ThemeName = 'ПУРПУРНАЯ'

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
                try { Show-Group 'settings' } catch {}
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
    $w = $script:RowHost.ClientSize.Width - (S 22)
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
    $btnH = S 34
    $gap  = S 8
    $sw   = S 8
    $colW = [int](($w - $gap) / 2)
    $idx  = 0
    foreach ($t in $script:Themes) {
        $rx = if ($idx % 2 -eq 0) { 0 } else { $colW + $gap }
        $ry = $btnY + [int]([Math]::Floor($idx / 2) * ($btnH + $gap))

        $swatch = New-Object System.Windows.Forms.Panel
        $swatch.BackColor = $t.Accent
        $swatch.Bounds    = New-Object System.Drawing.Rectangle $rx, $ry, $sw, $btnH
        $script:RowHost.Controls.Add($swatch)

        $btn = New-Object RustSuite.FlatButton
        $btn.Text   = $(if ($t.Name -eq $script:ThemeName) { '✓ ' + $t.Name } else { $t.Name })
        $btn.Font   = [RustSuite.Theme]::FBtn
        $btn.Style  = $(if ($t.Name -eq $script:ThemeName) { 'Primary' } else { 'Ghost' })
        $btn.Bounds = New-Object System.Drawing.Rectangle ($rx + $sw), $ry, ($colW - $sw), $btnH
        $btn.Tag    = $t
        $btn.Add_Click({
            param($s, $e)
            $th = $s.Tag
            Apply-Theme $th.Name -Save
            Update-ThemeSurfaces
            Write-Log ('Тема изменена: ' + $th.Name) 'ok'
            Set-Status ('Тема: ' + $th.Name) '#8B949E'
            Restart-SettingsSoon
        })
        $script:RowHost.Controls.Add($btn)
        $idx++
    }

    $y = $btnY + [int]([Math]::Ceiling($idx / 2) * ($btnH + $gap)) + (S 12)

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

$area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$winW = [Math]::Min((S 1240), [Math]::Max((S 1020), $area.Width - (S 60)))
$winH = [Math]::Min((S 820),  [Math]::Max((S 660), $area.Height - (S 70)))
$form.Size        = New-Object System.Drawing.Size $winW, $winH
$form.MinimumSize = New-Object System.Drawing.Size (S 1000), (S 640)
$form.Font        = [RustSuite.Theme]::FSub

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
        [System.Windows.Forms.TextRenderer]::DrawText($g, 'PERFORMANCE SUITE', $f,
            [System.Drawing.Point]::new(((S 26) + $w1 + (S 14)), (S 15)), [RustSuite.Theme]::TextC, $tf)

        $sub = 'оптимизация Windows под RUST   ·   v' + $script:AppVersion + '   ·   журнал: ProgramData\RustOptimizer'
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
})

$btnRun = New-Object RustSuite.FlatButton
$btnRun.Style   = 'Primary'
$btnRun.Text    = 'ОПТИМИЗИРОВАТЬ ПК'
$btnRun.Bounds  = New-Object System.Drawing.Rectangle (S 26), (S 22), (S 300), (S 50)

$btnUndo = New-Object RustSuite.FlatButton
$btnUndo.Style  = 'Ghost'
$btnUndo.Text   = 'ОТКАТ'
$btnUndo.Bounds = New-Object System.Drawing.Rectangle (S 338), (S 22), (S 150), (S 50)

$script:Spinner = New-Object RustSuite.Spinner
$script:Spinner.Bounds = New-Object System.Drawing.Rectangle (S 506), (S 26), (S 20), (S 20)
$script:Spinner.BackColor = [System.Drawing.Color]::Transparent

$script:Progress = New-Object RustSuite.ProgressStrip
$script:Progress.Bounds = New-Object System.Drawing.Rectangle (S 538), (S 30), (S 500), (S 7)
$script:Progress.BackColor = [System.Drawing.Color]::Transparent

$script:Status = New-Object System.Windows.Forms.Label
$script:Status.Text      = 'Готов к работе. Выберите модули и нажмите «Оптимизировать ПК».'
$script:Status.ForeColor = [RustSuite.Theme]::Muted
$script:Status.BackColor = [System.Drawing.Color]::Transparent
$script:Status.Font      = [RustSuite.Theme]::FSmall
$script:Status.AutoSize  = $false
$script:Status.Bounds    = New-Object System.Drawing.Rectangle (S 538), (S 48), (S 500), (S 20)

$footer.Controls.AddRange(@($btnRun, $btnUndo, $script:Spinner, $script:Progress, $script:Status))

$footer.Add_Resize({
    $w = $footer.ClientSize.Width
    $x = (S 538)
    if ($w - $x - (S 26) -lt (S 120)) { $x = (S 506) + (S 34) }
    $script:Progress.Left  = $x
    $script:Progress.Width = [Math]::Max((S 120), $w - $x - (S 26))
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
$nav = New-Object System.Windows.Forms.Panel
$script:NavPanel = $nav
$nav.Dock      = 'Fill'
$nav.BackColor = [RustSuite.Theme]::Bg

$navTop = New-Object System.Windows.Forms.Panel
$script:NavTopPanel = $navTop
$navTop.Dock      = 'Top'
$navTop.Height    = S 278
$navTop.BackColor = [RustSuite.Theme]::Bg

$script:Groups = @(
    @{ Id = 'sys';   Glyph = '◆'; Title = 'СИСТЕМА'; Sub = 'питание и приоритеты' },
    @{ Id = 'net';   Glyph = '↔'; Title = 'СЕТЬ';    Sub = 'пинг и пакеты' },
    @{ Id = 'rust';  Glyph = '▶'; Title = 'RUST';    Sub = 'профиль игры' },
    @{ Id = 'binds'; Glyph = '⌨'; Title = 'БИНДЫ';   Sub = 'keys.cfg одной кнопкой' },
    @{ Id = 'clean'; Glyph = '✦'; Title = 'ОЧИСТКА'; Sub = 'мусор и фоновые' },
    @{ Id = 'settings'; Glyph = '⚙'; Title = 'НАСТРОЙКИ'; Sub = 'темы и мониторинг' }
)

$i = 0
foreach ($grp in $script:Groups) {
    $b = New-Object RustSuite.NavButton
    $b.Text   = $grp.Glyph + '  ' + $grp.Title
    $b.Sub    = $grp.Sub
    $b.Tag    = $grp.Id
    $b.Bounds = [System.Drawing.Rectangle]::new(0, (S (2 + $i * 42)), (S 186), (S 38))
    $b.Add_Click({ param($s, $e) Show-Group $s.Tag })
    $script:NavButtons[$grp.Id] = $b
    $navTop.Controls.Add($b)
    $i = $i + 1
}

$navBottom = New-Object System.Windows.Forms.Panel
$script:NavBottomPanel = $navBottom
$navBottom.Dock      = 'Bottom'
$navBottom.Height    = S 120
$navBottom.BackColor = [RustSuite.Theme]::Bg

$lblProfiles = New-Object System.Windows.Forms.Label
$lblProfiles.Text      = 'ПРОФИЛИ'
$lblProfiles.Font      = [RustSuite.Theme]::FHead
$lblProfiles.ForeColor = [RustSuite.Theme]::Muted
$lblProfiles.BackColor = [RustSuite.Theme]::Bg
$lblProfiles.Bounds    = New-Object System.Drawing.Rectangle 0, (S 2), (S 186), (S 18)

$btnSafe = New-Object RustSuite.FlatButton
$btnSafe.Style  = 'Ghost'
$btnSafe.Text   = 'БЕЗОПАСНЫЙ'
$btnSafe.Font   = [RustSuite.Theme]::FSmall
$btnSafe.Bounds = New-Object System.Drawing.Rectangle 0, (S 24), (S 186), (S 32)

$btnMax = New-Object RustSuite.FlatButton
$btnMax.Style  = 'Ghost'
$btnMax.Text   = 'МАКСИМУМ'
$btnMax.Font   = [RustSuite.Theme]::FSmall
$btnMax.Bounds = New-Object System.Drawing.Rectangle 0, (S 62), (S 186), (S 32)

$navBottom.Controls.AddRange(@($lblProfiles, $btnSafe, $btnMax))
$nav.Controls.Add($navTop)
$nav.Controls.Add($navBottom)

# ---------- Правая колонка: статистика + журнал ----------
$rightCol = New-Object System.Windows.Forms.TableLayoutPanel
$script:RightCol = $rightCol
$rightCol.Dock        = 'Fill'
$rightCol.ColumnCount = 1
$rightCol.RowCount    = 2
$rightCol.BackColor   = [RustSuite.Theme]::PanelBg
[void]$rightCol.RowStyles.Add((New-Object System.Windows.Forms.RowStyle(
    [System.Windows.Forms.SizeType]::Absolute, (S 146))))
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

$script:CpuVal = New-MetricLabel '—' (S 190) (S 34) (S 170) ([RustSuite.Theme]::TextC)
$script:RamVal = New-MetricLabel '—' (S 190) (S 70) (S 170) ([RustSuite.Theme]::TextC)
$script:RustState = New-MetricLabel '—' (S 60) (S 106) (S 300) ([RustSuite.Theme]::TextC)
$script:CpuVal.TextAlign = 'MiddleRight'
$script:RamVal.TextAlign = 'MiddleRight'

$script:CpuBar = New-Object RustSuite.ProgressStrip
$script:CpuBar.Bounds    = New-Object System.Drawing.Rectangle (S 14), (S 54), (S 340), (S 6)
$script:CpuBar.Shimmer   = $false
$script:CpuBar.BackColor = [System.Drawing.Color]::Transparent

$script:RamBar = New-Object RustSuite.ProgressStrip
$script:RamBar.Bounds    = New-Object System.Drawing.Rectangle (S 14), (S 90), (S 340), (S 6)
$script:RamBar.Shimmer   = $false
$script:RamBar.BackColor = [System.Drawing.Color]::Transparent

$statsPanel.Controls.AddRange(@(
    $lblStats,
    (New-MetricLabel 'CPU'  (S 14) (S 34) (S 80) ([RustSuite.Theme]::Muted)),
    (New-MetricLabel 'ОЗУ'  (S 14) (S 70) (S 80) ([RustSuite.Theme]::Muted)),
    (New-MetricLabel 'RUST' (S 14) (S 106) (S 46) ([RustSuite.Theme]::Muted)),
    $script:CpuVal, $script:RamVal, $script:RustState,
    $script:CpuBar, $script:RamBar
))

$statsPanel.Add_Resize({
    $w = $statsPanel.ClientSize.Width
    $script:CpuBar.Width = [Math]::Max((S 60), $w - (S 28))
    $script:RamBar.Width = [Math]::Max((S 60), $w - (S 28))
    $script:CpuVal.Left  = [Math]::Max((S 60), $w - (S 200))
    $script:RamVal.Left  = $script:CpuVal.Left
    $script:CpuVal.Width = [Math]::Max((S 80), $w - $script:CpuVal.Left - (S 14))
    $script:RamVal.Width = $script:CpuVal.Width
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
$contentWrap.Controls.Add($script:RowHost)
try {
    [RustSuite.WheelHub]::Target = $script:RowHost
    [void][System.Windows.Forms.Application]::AddMessageFilter((New-Object RustSuite.WheelRouter))
} catch {}

$body.Controls.Add($nav, 0, 0)
$body.Controls.Add($contentWrap, 1, 0)
$body.Controls.Add($rightCol, 2, 0)

foreach ($c in @($form, $body, $footer, $nav, $navTop, $navBottom, $rightCol, $statsPanel,
                 $contentWrap, $logPanel, $logHost, $script:RowHost)) {
    Enable-DoubleBuffer $c
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
    $w = $script:RowHost.ClientSize.Width - (S 18)
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
    if (-not $gid) { $gid = 'sys' }
    $script:ActiveGroup = $gid

    # Останавливаем таймер настроек, иначе он держит удалённые контролы.
    try {
        if ($script:TempTimer) { $script:TempTimer.Stop(); $script:TempTimer.Dispose(); $script:TempTimer = $null }
    } catch {}
    $script:SetTempBox = $null
    $script:SetCpuBar  = $null
    $script:SetRamBar  = $null
    $script:SetValCpu  = $null
    $script:SetValRam  = $null

    foreach ($k in $script:NavButtons.Keys) { $script:NavButtons[$k].Selected = ($k -eq $gid) }
    foreach ($c in @($script:RowHost.Controls)) { $c.Dispose() }
    $script:RowHost.Controls.Clear()
    $script:RowHost.AutoScrollMinSize = New-Object System.Drawing.Size 0, 0
    try { $script:RowHost.ScrollToTop() } catch {}

    # Строим новую страницу без промежуточных перерисовок — переход без мигания.
    try { [RustSuite.Native]::SetRedraw($script:RowHost, $false) } catch {}
    try { $script:RowHost.SuspendLayout() } catch {}

    try {
        if ($gid -eq 'binds') { Show-BindsPanel; return }
        if ($gid -eq 'settings') { Show-SettingsPanel; return }

    $items = @($script:Tweaks | Where-Object { $_.Group -eq $gid })
    $w = $script:RowHost.ClientSize.Width - (S 18)
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
        $null = New-Object RustSuite.SlideTween -ArgumentList $card, ($top + (S 18)), $top, ($idx * 26), 260
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

function Show-TextDialog {
    param([string]$Title, [string]$Body)
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = $Title
    $dlg.StartPosition   = 'CenterParent'
    $dlg.FormBorderStyle = 'Sizable'
    $dlg.MinimizeBox     = $false
    $dlg.BackColor       = [RustSuite.Theme]::Bg
    $dlg.ForeColor       = [RustSuite.Theme]::TextC
    $dlg.Font            = [RustSuite.Theme]::FSub
    $dlg.Size            = New-Object System.Drawing.Size (S 640), (S 460)
    $dlg.MinimumSize     = New-Object System.Drawing.Size (S 480), (S 340)

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Multiline   = $true
    $tb.ReadOnly    = $true
    $tb.ScrollBars  = 'Both'
    $tb.WordWrap    = $false
    $tb.BorderStyle = 'None'
    $tb.BackColor   = [RustSuite.Theme]::Field
    $tb.ForeColor   = [RustSuite.Theme]::TextC
    $tb.Font        = [RustSuite.Theme]::FMono
    $tb.Dock        = 'Fill'
    $tb.Text        = $Body

    $bar = New-Object System.Windows.Forms.Panel
    $bar.Dock      = 'Bottom'
    $bar.Height    = S 58
    $bar.BackColor = [RustSuite.Theme]::PanelBg

    $btnCopy = New-Object RustSuite.FlatButton
    $btnCopy.Style  = 'Primary'
    $btnCopy.Text   = 'КОПИРОВАТЬ'
    $btnCopy.Bounds = New-Object System.Drawing.Rectangle (S 16), (S 12), (S 170), (S 36)
    $btnCopy.Tag    = $tb
    $btnCopy.Add_Click({
        param($s, $e)
        if ($s.Tag -and (Copy-Text $s.Tag.Text)) { Write-Log 'Текст скопирован в буфер обмена' 'ok' }
    })

    $btnClose = New-Object RustSuite.FlatButton
    $btnClose.Style  = 'Ghost'
    $btnClose.Text   = 'ЗАКРЫТЬ'
    $btnClose.Bounds = New-Object System.Drawing.Rectangle (S 196), (S 12), (S 130), (S 36)
    $btnClose.Add_Click({ param($s, $e) $f = $s.FindForm(); if ($f) { $f.Close() } })

    $bar.Controls.AddRange(@($btnCopy, $btnClose))
    $dlg.Controls.Add($tb)
    $dlg.Controls.Add($bar)
    [void]$dlg.ShowDialog($form)
}

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
    if ($script:ActiveGroup -eq 'rust') { Show-Group 'rust' }
    [void][System.Windows.Forms.MessageBox]::Show($res, 'PURPLE RUSH', 'OK', 'Information')
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
    Show-Group $script:ActiveGroup
    Write-Log 'Профиль «Безопасный»: только проверенные модули' 'info'
})

$btnMax.Add_Click({
    foreach ($t in $script:Tweaks) { $script:Enabled[$t.Id] = $true }
    $script:State['Enabled'] = $script:Enabled
    Save-State
    Show-Group $script:ActiveGroup
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

# ---------- Жизненный цикл ----------
$form.Add_FormClosing({
    param($s, $e)
    if ($script:Busy) {
        $a = [System.Windows.Forms.MessageBox]::Show(
            'Оптимизация ещё выполняется. Прервать?', 'PURPLE RUSH', 'YesNo', 'Warning')
        if ($a -ne 'Yes') { $e.Cancel = $true; return }
    }
    try { $script:StatsTimer.Stop() } catch {}
    try { $script:LaunchTimer.Stop() } catch {}
    if ($script:State['TimerOn']) { try { [RustSuite.Native]::TimerStop() } catch {} }
})

$form.Add_Shown({
    [void][RustSuite.Native]::DarkTitle($form)
    [void][RustSuite.Native]::DarkScroll($script:RowHost)
    [void][RustSuite.Native]::DarkScroll($script:LogBox)

    Show-Group 'sys'
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

    $script:StatsTimer = New-Object System.Windows.Forms.Timer
    $script:StatsTimer.Interval = 2500
    $script:StatsTimer.Add_Tick({ Update-Stats })
    $script:StatsTimer.Start()

    if ($script:TestUi) {
        $script:ProbeStep = 0
        $script:ProbeTimer = New-Object System.Windows.Forms.Timer
        $script:ProbeTimer.Interval = 450
        $script:ProbeTimer.Add_Tick({
            try {
                switch ($script:ProbeStep) {
                    0 { Show-Group 'sys' }
                    1 { Show-Group 'net' }
                    2 { Show-Group 'rust' }
                    3 { Show-Group 'binds' }
                    4 { Show-Group 'clean' }
                    5 {
                        Show-Group 'settings'
                    }
                    6 {
                        Apply-Theme 'ТЁМНО-СИНЯЯ' -Save
                        Update-ThemeSurfaces
                        Restart-SettingsSoon
                    }
                    7 {
                        Show-Group 'sys'
                        $c = @($script:RowHost.Controls | Where-Object { $_ -is [RustSuite.Card] }) | Select-Object -First 1
                        if ($c) { $c.On = (-not $c.On); $c.On = (-not $c.On) }
                        Update-Stats
                    }
                    8 {
                        Apply-Theme 'ПУРПУРНАЯ' -Save
                        Update-ThemeSurfaces
                        Write-Host 'UI TEST OK'
                        $script:ProbeTimer.Stop()
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

[System.Windows.Forms.Application]::Run($form)

