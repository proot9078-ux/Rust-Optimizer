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
            $rver = if ($script:RustInfo -and $script:RustInfo.Unity) { ' · Unity ' + $script:RustInfo.Unity } else { '' }
            $script:RustState.Text = 'запущен · High' + $rver + ' · бинды активны'
            $script:RustState.ForeColor = [RustSuite.Theme]::Ok
        } else {
            $rver = ''
            if ($script:RustInfo -and $script:RustInfo.Unity) {
                $rver = ' · Unity ' + $script:RustInfo.Unity
                if ($script:RustInfo.CfgReady) { $rver += ' · cfg ' + $script:RustInfo.CfgKeys }
            }
            $script:RustState.Text = 'готов' + $rver
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
                        if (@($script:Themes).Count -lt 14) { throw 'THEME COUNT TOO LOW' }
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
                        if ($script:RustExe -and (-not $script:RustInfo -or -not $script:RustInfo.Found -or -not $script:RustInfo.Version)) { throw 'RUST INFO MISSING' }
                        Write-Host ('RUST info=' + $(if ($script:RustInfo) { $script:RustInfo.Version + ' Unity ' + $script:RustInfo.Unity + ' cfg=' + $script:RustInfo.CfgKeys } else { 'n/a' }))
                        Write-Host ('HOME score=' + $score + ' cards=' + $cards.Count +
                                    ' gauge=' + $script:HomeGauge.Width + 'x' + $script:HomeGauge.Height +
                                    ' spark=' + $script:HomeSpark.Width + 'x' + $script:HomeSpark.Height)
                        Write-Host 'HOME OK'
                    }
                    12 {
                        try { $script:ProbeTimer.Stop() } catch {}
                        Apply-Theme 'PURPLE RUSH' -Save
                        Update-ThemeSurfaces
                        if ($env:RUSTOPT_SHOT) {
                            try {
                                if ($script:FadeVeil) { $script:FadeVeil.Cancel() }
                                $script:RowHost.ScrollToTop()
                                $form.Refresh()
                                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                                while ($sw.ElapsedMilliseconds -lt 700) {
                                    [System.Windows.Forms.Application]::DoEvents()
                                    Start-Sleep -Milliseconds 15
                                }
                                $sw.Stop()
                                $form.Refresh()
                                $bmp = New-Object System.Drawing.Bitmap $form.Width, $form.Height
                                $g = [System.Drawing.Graphics]::FromImage($bmp)
                                $g.CopyFromScreen($form.Location, [System.Drawing.Point]::Empty, $form.Size)
                                $g.Dispose()
                                $bmp.Save([string]$env:RUSTOPT_SHOT, [System.Drawing.Imaging.ImageFormat]::Png)
                                $bmp.Dispose()
                            } catch {}
                        }
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
