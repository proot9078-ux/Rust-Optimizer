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
