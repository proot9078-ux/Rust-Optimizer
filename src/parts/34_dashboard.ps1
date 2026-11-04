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
    Show-Group 'home'
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
        Show-Group 'home'
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
        Show-Group 'home'
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
        @{ Text = '◈  ДИАГНОСТИКА WINDOWS'; X = 0; Y = (($bh + (S 8)) * 2); Style = 'Ghost'; Action = { Show-Group 'repair' } },
        @{ Text = '◐  ТЕМЫ И НАСТРОЙКИ'; X = ($half + (S 8)); Y = (($bh + (S 8)) * 2); Style = 'Ghost'; Action = { Show-Group 'settings' } }
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
