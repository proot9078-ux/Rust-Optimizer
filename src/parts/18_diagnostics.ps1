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
