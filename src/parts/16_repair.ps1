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
