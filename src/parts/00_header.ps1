# ============================================================
#  PURPLE RUSH - RUST + FORTNITE PERFORMANCE ENGINE  v7.0
#  Оптимизация Windows под RUST и FORTNITE + официальные cfg/бинды +
#  глубокая очистка, диагностика и восстановление Windows.
#  Запуск: RustOptimizer.bat (права администратора)
# ============================================================
param([switch]$SelfTest, [switch]$TestUi, [switch]$InstallShortcut, [switch]$Verify)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

$script:AppVersion   = '7.0'
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
$script:RustInfo     = $null
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

# ============================================================
#  RUST: версия клиента и совместимость cfg
#  Rust 2026 работает на Unity 6.x; набор конваров меняется,
#  поэтому cfg применяется только к ключам, которые игра
#  реально использует в своём client.cfg.
# ============================================================
function Get-RustClientInfo {
    $info = [pscustomobject]@{
        Found    = $false
        Exe      = ''
        Version  = ''
        Unity    = ''
        Build    = ''
        Updated  = ''
        SizeMb   = 0
        Eac      = $false
        CfgPath  = ''
        CfgKeys  = 0
        CfgReady = $false
    }
    if (-not $script:RustExe -or -not (Test-Path -LiteralPath $script:RustExe)) { return $info }
    $info.Found = $true
    $info.Exe   = [string]$script:RustExe
    try {
        $fi = Get-Item -LiteralPath $script:RustExe -Force
        $info.SizeMb  = [math]::Round($fi.Length / 1MB, 1)
        $info.Updated = $fi.LastWriteTime.ToString('yyyy-MM-dd')
        $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($fi.FullName)
        $info.Version = [string]$vi.FileVersion
        $parts = $info.Version.Split('.')
        if ($parts.Count -ge 3) { $info.Unity = ($parts[0..2] -join '.') }
        if ($parts.Count -ge 4) { $info.Build = [string]$parts[3] }
    } catch {}
    $root = Split-Path -Parent $info.Exe
    foreach ($rel in @('EasyAntiCheat\EasyAntiCheat_x64.dll',
                       'EasyAntiCheat\EasyAntiCheat_EOS_Setup.exe',
                       'RustClient_Data\Plugins\x86_64\EasyAntiCheat\EasyAntiCheat_x64.dll')) {
        try { if (Test-Path -LiteralPath (Join-Path $root $rel)) { $info.Eac = $true; break } } catch {}
    }
    try {
        $cfgDir = Join-Path $root 'cfg'
        $info.CfgPath = Join-Path $cfgDir 'client.cfg'
        if (Test-Path -LiteralPath $info.CfgPath) {
            $info.CfgKeys  = (Get-RustCfgKnownKeys $info.CfgPath).Count
            $info.CfgReady = ($info.CfgKeys -ge 50)
        }
    } catch {}
    return $info
}

function Get-RustCfgKnownKeys {
    param([string]$Path)
    $keys = @{}
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $keys }
    try {
        foreach ($ln in [IO.File]::ReadAllLines($Path)) {
            if ($ln -match '^\s*([A-Za-z0-9_.]+)\s') { $keys[$matches[1].ToLower()] = $true }
        }
    } catch {}
    return $keys
}

# Оставляет только те строки, которые эта версия Rust уже использует.
# Если cfg ещё не создан игрой — применяется полный проверенный список.
function Select-RustCfgLines {
    param([string[]]$Lines, [string]$Path)
    $res = [pscustomobject]@{ Lines = @($Lines); Skipped = @() }
    $known = Get-RustCfgKnownKeys $Path
    if ($known.Count -lt 50) { return $res }
    $keep = @()
    $skip = @()
    foreach ($l in @($Lines)) {
        if (-not $l) { continue }
        if ($l -match '^\s*([A-Za-z0-9_.]+)') {
            $k = $matches[1].ToLower()
            if ($k -eq 'fps.graph' -or $known.ContainsKey($k)) { $keep += [string]$l }
            else { $skip += $k }
        } else { $keep += [string]$l }
    }
    $res.Lines   = @($keep)
    $res.Skipped = @($skip | Select-Object -Unique)
    return $res
}

function Get-RustCfgAudit {
    param([string[]]$Keys)
    $dir  = Get-RustCfgDir
    $path = if ($dir) { Join-Path $dir 'client.cfg' } else { '' }
    $known = Get-RustCfgKnownKeys $path
    $ok = @(); $missing = @()
    foreach ($k in @($Keys)) {
        if (-not $k) { continue }
        if ($known.ContainsKey(([string]$k).ToLower())) { $ok += [string]$k } else { $missing += [string]$k }
    }
    return [pscustomobject]@{
        Ready   = ($known.Count -ge 50)
        Total   = $known.Count
        Ok      = @($ok)
        Missing = @($missing)
        Path    = $path
    }
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
    param([string]$Path, [string]$Tag, [string]$Dir = $script:RustBackup)
    $dest = Join-Path $Dir ($Tag + '.orig')
    if (Test-Path -LiteralPath $dest) { return $dest }
    if (Test-Path -LiteralPath $Path) {
        try { Copy-Item -LiteralPath $Path -Destination $dest -Force } catch {}
    } else {
        try { [IO.File]::WriteAllText($dest, '', (New-Object System.Text.UTF8Encoding($false))) } catch {}
    }
    return $dest
}

function Backup-FileStamp {
    param([string]$Path, [string]$Tag, [string]$Dir = $script:RustBackup)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        $name = $Tag + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.bak'
        Copy-Item -LiteralPath $Path -Destination (Join-Path $Dir $name) -Force
        $old = @(Get-ChildItem -LiteralPath $Dir -Filter ($Tag + '-*.bak') -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending | Select-Object -Skip 10)
        foreach ($f in $old) { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue }
    } catch {}
}

function Restore-FileOnce {
    param([string]$Path, [string]$Tag, [string]$Dir = $script:RustBackup)
    $src = Join-Path $Dir ($Tag + '.orig')
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
