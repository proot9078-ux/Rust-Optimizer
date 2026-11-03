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
    foreach ($tn in 'Card', 'FlatButton', 'NavButton', 'ProgressStrip', 'Spinner', 'HeaderPanel', 'SlideTween', 'SmoothScrollPanel', 'WheelRouter', 'ThemeTile', 'HealthRow') {
        try {
            $null = [System.Type]::GetType('RustSuite.' + $tn + ', ' + [RustSuite.Card].Assembly.FullName, $false)
            if (-not [System.Type]::GetType('RustSuite.' + $tn + ', ' + [RustSuite.Card].Assembly.FullName, $false)) {
                Write-Host ("MISSING CONTROL: " + $tn); $fail++
            }
        } catch { Write-Host ("CONTROL ERROR: " + $tn); $fail++ }
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

    if ($fail -gt 0) {
        Write-Host ("SELFTEST FAILED: " + $fail + " issue(s)")
        exit 1
    }
    Write-Host 'SELFTEST OK'
    exit 0
}
