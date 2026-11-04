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
