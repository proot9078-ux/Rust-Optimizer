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
    $parts = @()
    if ($old) {
        foreach ($p in ([string]$old).Split(';')) {
            $t = $p.Trim()
            if (-not $t) { continue }
            if ($t -match '^GpuPreference\s*=') { continue }
            $parts += $t
        }
    }
    $parts += 'GpuPreference=2'
    Set-RegStr $k $script:RustExe (($parts -join ';') + ';')
    Write-Log 'RustClient.exe → «Высокая производительность» GPU (прочие флаги сохранены)' 'ok'
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
    $sel = Select-RustCfgLines $script:RustCfgLines $file
    Merge-CfgFile -Path $file -Lines $sel.Lines -ManagedKeys $script:RustCfgManaged
    if ($sel.Skipped.Count -gt 0) {
        Write-Log ('client.cfg: ключи, которых нет в этой версии Rust, пропущены — ' + (@($sel.Skipped) -join ', ')) 'info'
    }
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
    'effects.maxgibdist 0',
    'particle.quality 25',
    'graphicssettings.pixellightcount 0',
    'graphics.collapserenderers True',
    'graphics.vsync 0',
    'mesh.reducebonecountonlowlod True',
    'sss.halfres True',
    'sss.quality 0',
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
    'effects.maxgibdist','particle.quality','graphicssettings.pixellightcount',
    'graphics.collapserenderers','graphics.vsync','mesh.reducebonecountonlowlod',
    'sss.halfres','sss.quality',
    'grass.quality','grass.distance','grass.displacement',
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
    $sel = Select-RustCfgLines $script:RustMaxCfgLines $file
    Merge-CfgFile -Path $file -Lines $sel.Lines -ManagedKeys $script:RustMaxCfgManaged
    if ($sel.Skipped.Count -gt 0) {
        Write-Log ('client.cfg: не поддерживаются этой версией Rust и пропущены — ' + (@($sel.Skipped) -join ', ')) 'info'
    }
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
#  RUST 2026: отчёт о совместимости клиента и cfg
# ============================================================
function Get-RustCompatText {
    $info = Get-RustClientInfo
    if (-not $info.Found) {
        return "RUST не найден.`r`n`r`nУстановите игру в Steam и запустите её один раз — после этого появится cfg и станет доступна проверка совместимости."
    }
    $keys = @()
    foreach ($l in @($script:RustMaxCfgLines)) {
        if ($l -match '^\s*([A-Za-z0-9_.]+)') { $keys += $matches[1] }
    }
    $audit = Get-RustCfgAudit $keys
    $lines = @()
    $lines += 'RUST · СОВМЕСТИМОСТЬ С ТЕКУЩЕЙ ВЕРСИЕЙ'
    $lines += ''
    $lines += ('Клиент          : ' + $info.Version + '  (Unity ' + $info.Unity + ')')
    $lines += ('Сборка          : ' + $info.Build + ' · обновлён ' + $info.Updated)
    $lines += ('Размер          : ' + $info.SizeMb + ' МБ')
    $lines += ('EasyAntiCheat   : ' + $(if ($info.Eac) { 'найден, не изменяется' } else { 'не найден в папке игры' }))
    $lines += ('cfg             : ' + $info.CfgPath)
    $lines += ('Ключей в cfg    : ' + $audit.Total)
    $lines += ''
    if (-not $audit.Ready) {
        $lines += 'cfg ещё не создан игрой: запустите RUST один раз, выйдите и повторите проверку.'
        $lines += 'До этого применяется только проверенный базовый набор конваров.'
    } else {
        $lines += ('Проверено ключей: ' + $audit.Ok.Count + ' из ' + $keys.Count)
        if ($audit.Missing.Count -eq 0) {
            $lines += 'Все конвары профиля поддерживаются этим клиентом.'
        } else {
            $lines += ('Не поддерживаются и будут пропущены: ' + ($audit.Missing -join ', '))
        }
        $lines += ''
        $lines += 'Профиль применяется только к ключам, которые игра сама'
        $lines += 'использует в client.cfg. Новые обновления Rust не ломают'
        $lines += 'настройки: неизвестные ключи автоматически пропускаются.'
    }
    $lines += ''
    $lines += 'Клиент не модифицируется: меняются только cfg-файлы,'
    $lines += 'а exe/dll сверяются по снимку до и после.'
    return ($lines -join "`r`n")
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

# 11. Windows 11: оптимизации для оконных игр (SwapEffectUpgrade)
function Invoke-WindowedOpt {
    $k = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
    Ensure-RegKey $k
    $old = Get-Reg $k 'DirectXUserGlobalSettings'
    if (-not $script:State.ContainsKey('WindowedOptOld')) {
        $script:State['WindowedOptOld'] = if ($null -eq $old) { '~none~' } else { [string]$old }
    }
    $parts = @()
    if ($old) {
        foreach ($p in ([string]$old).Split(';')) {
            $t = $p.Trim()
            if (-not $t) { continue }
            if ($t -match '^SwapEffectUpgradeEnable\s*=') { continue }
            $parts += $t
        }
    }
    $parts += 'SwapEffectUpgradeEnable=1'
    Set-RegStr $k 'DirectXUserGlobalSettings' (($parts -join ';') + ';')
    Write-Log 'Оптимизации оконных игр Windows 11 включены (SwapEffectUpgrade)' 'ok'
}
function Undo-WindowedOpt {
    $k = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
    $old = [string]$script:State['WindowedOptOld']
    if ($old -eq '~none~') { Remove-RegValue $k 'DirectXUserGlobalSettings' }
    elseif ($old) { Set-RegStr $k 'DirectXUserGlobalSettings' $old }
    Write-Log 'Настройка оконных игр восстановлена' 'ok'
}

# 12. Storage Sense: без фоновой автоочистки во время игры
function Invoke-StorageSenseOff {
    $items = @(
        @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'; N = '01'; V = 0 }
    )
    Set-DwordBatch 'StorageSenseOld' $items
    Write-Log 'Автоматическая очистка Storage Sense приостановлена' 'ok'
}
function Undo-StorageSenseOff { Undo-DwordBatch 'StorageSenseOld'; Write-Log 'Storage Sense восстановлен' 'ok' }
