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
$minW = S 1000
$minH = S 640
$winW = [Math]::Min((S 1240), [Math]::Max($minW, $area.Width - (S 60)))
$winH = [Math]::Min((S 820),  [Math]::Max($minH, $area.Height - (S 70)))

# Восстанавливаем размер прошлой сессии, если он помещается на текущий экран.
try {
    $savedW = [int]$script:State['WinW']
    $savedH = [int]$script:State['WinH']
    if ($savedW -ge $minW -and $savedH -ge $minH) {
        $winW = [Math]::Min($savedW, [Math]::Max($minW, $area.Width - (S 20)))
        $winH = [Math]::Min($savedH, [Math]::Max($minH, $area.Height - (S 20)))
    }
} catch {}

$form.Size        = New-Object System.Drawing.Size $winW, $winH
$form.MinimumSize = New-Object System.Drawing.Size $minW, $minH
$form.Font        = [RustSuite.Theme]::FSub
$form.KeyPreview  = $true
Set-AppWindowIcon $form

# Handle создаётся выше для чтения DPI, поэтому CenterScreen не успевает
# примениться к размеру по умолчанию. Позиционируем окно вручную уже
# после установки финального размера — иначе часть окна уходит за экран.
$px = $area.Left + [int][Math]::Max(0, (($area.Width - $winW) / 2))
$py = $area.Top  + [int][Math]::Max(0, (($area.Height - $winH) / 2))

# Позицию прошлой сессии используем только если окно остаётся видимым
# хотя бы на одном мониторе (например, после отключения второго экрана).
try {
    if ($script:State['WinPos']) {
        $sx = [int]$script:State['WinX']
        $sy = [int]$script:State['WinY']
        $r  = New-Object System.Drawing.Rectangle $sx, $sy, $winW, $winH
        foreach ($scr in [System.Windows.Forms.Screen]::AllScreens) {
            if ($scr.WorkingArea.IntersectsWith($r)) { $px = $sx; $py = $sy; break }
        }
    }
} catch {}

$form.StartPosition = 'Manual'
$form.Location = New-Object System.Drawing.Point $px, $py

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
        $w2 = [System.Windows.Forms.TextRenderer]::MeasureText('PERFORMANCE SUITE', $f).Width
        [System.Windows.Forms.TextRenderer]::DrawText($g, 'PERFORMANCE SUITE', $f,
            [System.Drawing.Point]::new(((S 26) + $w1 + (S 14)), (S 15)), [RustSuite.Theme]::TextC, $tf)

        # Небольшой бейдж версии рядом с заголовком.
        $vtext = 'v' + $script:AppVersion
        $vfont = [RustSuite.Theme]::FSmall
        $vsz   = [System.Windows.Forms.TextRenderer]::MeasureText($vtext, $vfont)
        $vw    = $vsz.Width + (S 18)
        $vh    = S 21
        $vx    = (S 26) + $w1 + (S 14) + $w2 + (S 14)
        if (($vx + $vw) -lt ($s.Width - (S 230))) {
            $vrect = [System.Drawing.Rectangle]::new($vx, (S 16), $vw, $vh)
            $vp    = [RustSuite.Theme]::Round([System.Drawing.RectangleF]$vrect, (S 10))
            $vbr   = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(45, [RustSuite.Theme]::Accent))
            $g.FillPath($vbr, $vp)
            $vbr.Dispose()
            $vpen  = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(120, [RustSuite.Theme]::AccentLt), 1)
            $g.DrawPath($vpen, $vp)
            $vpen.Dispose(); $vp.Dispose()
            $vcf = [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor `
                   [System.Windows.Forms.TextFormatFlags]::VerticalCenter
            [System.Windows.Forms.TextRenderer]::DrawText($g, $vtext, $vfont, $vrect,
                [RustSuite.Theme]::AccentLt, $vcf)
        }

        $sub = 'оптимизация Windows под RUST   ·   журнал: ProgramData\RustOptimizer'
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
        $line = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(70, [RustSuite.Theme]::Accent)), 1
        $g.DrawLine($line, 0, ($s.Height - 1), $s.Width, ($s.Height - 1))
        $line.Dispose()
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
    try {
        $hint = 'Ctrl+1…9 — разделы    ·    Ctrl+R — обновить статистику'
        $hr   = New-Object System.Drawing.Rectangle 0, ($s.Height - (S 24)), ($s.Width - (S 26)), (S 18)
        [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $hint,
            [RustSuite.Theme]::FSmall, $hr,
            [System.Drawing.Color]::FromArgb(120, [RustSuite.Theme]::Muted),
            [System.Windows.Forms.TextFormatFlags]::Right)
    } catch {}
})

$btnRun = New-Object RustSuite.FlatButton
$btnRun.Style   = 'Primary'
$btnRun.Text    = '▶  ОПТИМИЗИРОВАТЬ ПК'
$btnRun.Bounds  = New-Object System.Drawing.Rectangle (S 26), (S 22), (S 286), (S 50)

$btnUndo = New-Object RustSuite.FlatButton
$btnUndo.Style  = 'Ghost'
$btnUndo.Text   = '↺  ОТКАТ'
$btnUndo.Bounds = New-Object System.Drawing.Rectangle (S 320), (S 22), (S 132), (S 50)

$btnScan = New-Object RustSuite.FlatButton
$btnScan.Style  = 'Ghost'
$btnScan.Text   = '◈  ДИАГНОСТИКА'
$btnScan.Bounds = New-Object System.Drawing.Rectangle (S 460), (S 22), (S 158), (S 50)

$script:Spinner = New-Object RustSuite.Spinner
$script:Spinner.Bounds = New-Object System.Drawing.Rectangle (S 628), (S 26), (S 20), (S 20)
$script:Spinner.BackColor = [System.Drawing.Color]::Transparent

$script:Progress = New-Object RustSuite.ProgressStrip
$script:Progress.Bounds = New-Object System.Drawing.Rectangle (S 660), (S 30), (S 460), (S 7)
$script:Progress.BackColor = [System.Drawing.Color]::Transparent

$script:Status = New-Object System.Windows.Forms.Label
$script:Status.Text      = 'Готов к работе. Выберите модули и нажмите «Оптимизировать ПК».'
$script:Status.ForeColor = [RustSuite.Theme]::Muted
$script:Status.BackColor = [System.Drawing.Color]::Transparent
$script:Status.Font      = [RustSuite.Theme]::FSmall
$script:Status.AutoSize  = $false
$script:Status.Bounds    = New-Object System.Drawing.Rectangle (S 660), (S 48), (S 460), (S 20)

$footer.Controls.AddRange(@($btnRun, $btnUndo, $btnScan, $script:Spinner, $script:Progress, $script:Status))

$footer.Add_Resize({
    $w = $footer.ClientSize.Width
    $x = (S 660)
    if ($w - $x - (S 26) -lt (S 140)) { $x = (S 628) + (S 34) }
    $script:Progress.Left  = $x
    $script:Progress.Width = [Math]::Max((S 140), $w - $x - (S 26))
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
$nav = New-Object System.Windows.Forms.TableLayoutPanel
$script:NavPanel = $nav
$nav.Dock        = 'Fill'
$nav.BackColor   = [RustSuite.Theme]::Bg
$nav.ColumnCount = 1
$nav.RowCount    = 2
[void]$nav.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle(
    [System.Windows.Forms.SizeType]::Percent, 100)))
[void]$nav.RowStyles.Add((New-Object System.Windows.Forms.RowStyle(
    [System.Windows.Forms.SizeType]::Percent, 100)))
[void]$nav.RowStyles.Add((New-Object System.Windows.Forms.RowStyle(
    [System.Windows.Forms.SizeType]::Absolute, (S 108))))

$navScrollWrap = New-Object System.Windows.Forms.Panel
$script:NavScrollWrap = $navScrollWrap
$navScrollWrap.Dock      = 'Fill'
$navScrollWrap.BackColor = [RustSuite.Theme]::Bg

$navTop = New-Object System.Windows.Forms.Panel
$script:NavTopPanel = $navTop
$navTop.Dock       = 'Fill'
$navTop.BackColor  = [RustSuite.Theme]::Bg
# При минимальной высоте окна восемь пунктов не помещаются —
# включаем прокрутку вместо наложения на блок «ПРОФИЛИ».
$navTop.AutoScroll = $true
$navScrollWrap.Controls.Add($navTop)

$script:Groups = @(
    @{ Id = 'home';    Glyph = '◉'; Title = 'ОБЗОР';    Sub = 'оценка и быстрые действия' },
    @{ Id = 'sys';     Glyph = '◆'; Title = 'СИСТЕМА';  Sub = 'питание и приоритеты' },
    @{ Id = 'net';     Glyph = '↔'; Title = 'СЕТЬ';     Sub = 'пинг и пакеты' },
    @{ Id = 'rust';    Glyph = '▶'; Title = 'RUST';     Sub = 'профиль игры' },
    @{ Id = 'picture'; Glyph = '◐'; Title = 'КАРТИНКА'; Sub = 'цвет и панель GPU' },
    @{ Id = 'binds';   Glyph = '⌨'; Title = 'БИНДЫ';    Sub = 'keys.cfg одной кнопкой' },
    @{ Id = 'clean';   Glyph = '✦'; Title = 'ОЧИСТКА';  Sub = 'мусор и фоновые' },
    @{ Id = 'repair';  Glyph = '◈'; Title = 'РЕМОНТ';   Sub = 'проверка и лечение Windows' },
    @{ Id = 'settings'; Glyph = '⚙'; Title = 'НАСТРОЙКИ'; Sub = 'темы и мониторинг' }
)

$i = 0
$script:NavTip = New-Object System.Windows.Forms.ToolTip
$script:NavTip.InitialDelay  = 450
$script:NavTip.ReshowDelay   = 120
$script:NavTip.AutoPopDelay  = 6000
foreach ($grp in $script:Groups) {
    $b = New-Object RustSuite.NavButton
    $b.Text   = $grp.Glyph + '  ' + $grp.Title
    $b.Sub    = $grp.Sub
    $b.Tag    = $grp.Id
    $b.Bounds = [System.Drawing.Rectangle]::new(0, (S (2 + $i * 40)), (S 176), (S 36))
    $b.Add_Click({ param($s, $e) Show-Group $s.Tag })
    try { $script:NavTip.SetToolTip($b, ($grp.Title + ' — ' + $grp.Sub + "`nCtrl+" + ($i + 1))) } catch {}
    $script:NavButtons[$grp.Id] = $b
    $navTop.Controls.Add($b)
    $i = $i + 1
}

$navBottom = New-Object System.Windows.Forms.Panel
$script:NavBottomPanel = $navBottom
$navBottom.Dock      = 'Bottom'
$navBottom.Height    = S 108
$navBottom.BackColor = [RustSuite.Theme]::Bg

$lblProfiles = New-Object System.Windows.Forms.Label
$lblProfiles.Text      = 'ПРОФИЛИ'
$lblProfiles.Font      = [RustSuite.Theme]::FHead
$lblProfiles.ForeColor = [RustSuite.Theme]::Muted
$lblProfiles.BackColor = [RustSuite.Theme]::Bg
$lblProfiles.Bounds    = New-Object System.Drawing.Rectangle 0, (S 0), (S 186), (S 18)

$btnSafe = New-Object RustSuite.FlatButton
$btnSafe.Style  = 'Ghost'
$btnSafe.Text   = 'БЕЗОПАСНЫЙ'
$btnSafe.Font   = [RustSuite.Theme]::FSmall
$btnSafe.Bounds = New-Object System.Drawing.Rectangle 0, (S 20), (S 186), (S 30)

$btnMax = New-Object RustSuite.FlatButton
$btnMax.Style  = 'Ghost'
$btnMax.Text   = 'МАКСИМУМ'
$btnMax.Font   = [RustSuite.Theme]::FSmall
$btnMax.Bounds = New-Object System.Drawing.Rectangle 0, (S 56), (S 186), (S 30)

$navBottom.Controls.AddRange(@($lblProfiles, $btnSafe, $btnMax))
$script:NavScrollStrip = New-Object RustSuite.ScrollStrip
$script:NavScrollStrip.Target = $navTop
$navScrollWrap.Controls.Add($script:NavScrollStrip)
$nav.Controls.Add($navScrollWrap, 0, 0)
$nav.Controls.Add($navBottom, 0, 1)

# ---------- Правая колонка: статистика + журнал ----------
$rightCol = New-Object System.Windows.Forms.TableLayoutPanel
$script:RightCol = $rightCol
$rightCol.Dock        = 'Fill'
$rightCol.ColumnCount = 1
$rightCol.RowCount    = 2
$rightCol.BackColor   = [RustSuite.Theme]::PanelBg
[void]$rightCol.RowStyles.Add((New-Object System.Windows.Forms.RowStyle(
    [System.Windows.Forms.SizeType]::Absolute, (S 168))))
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

$script:CpuVal = New-MetricLabel '—' (S 190) (S 30) (S 170) ([RustSuite.Theme]::TextC)
$script:RamVal = New-MetricLabel '—' (S 190) (S 66) (S 170) ([RustSuite.Theme]::TextC)
$script:DiskVal = New-MetricLabel '—' (S 190) (S 102) (S 170) ([RustSuite.Theme]::TextC)
$script:RustState = New-MetricLabel '—' (S 60) (S 130) (S 300) ([RustSuite.Theme]::TextC)
$script:CpuVal.TextAlign  = 'MiddleRight'
$script:RamVal.TextAlign  = 'MiddleRight'
$script:DiskVal.TextAlign = 'MiddleRight'

$script:CpuBar = New-Object RustSuite.ProgressStrip
$script:CpuBar.Bounds    = New-Object System.Drawing.Rectangle (S 14), (S 50), (S 340), (S 6)
$script:CpuBar.Shimmer   = $false
$script:CpuBar.BackColor = [System.Drawing.Color]::Transparent

$script:RamBar = New-Object RustSuite.ProgressStrip
$script:RamBar.Bounds    = New-Object System.Drawing.Rectangle (S 14), (S 86), (S 340), (S 6)
$script:RamBar.Shimmer   = $false
$script:RamBar.BackColor = [System.Drawing.Color]::Transparent

$script:DiskBar = New-Object RustSuite.ProgressStrip
$script:DiskBar.Bounds    = New-Object System.Drawing.Rectangle (S 14), (S 122), (S 340), (S 6)
$script:DiskBar.Shimmer   = $false
$script:DiskBar.BackColor = [System.Drawing.Color]::Transparent

$statsPanel.Controls.AddRange(@(
    $lblStats,
    (New-MetricLabel 'CPU'  (S 14) (S 30) (S 80) ([RustSuite.Theme]::Muted)),
    (New-MetricLabel 'ОЗУ'  (S 14) (S 66) (S 80) ([RustSuite.Theme]::Muted)),
    (New-MetricLabel 'ДИСК' (S 14) (S 102) (S 80) ([RustSuite.Theme]::Muted)),
    (New-MetricLabel 'RUST' (S 14) (S 130) (S 46) ([RustSuite.Theme]::Muted)),
    $script:CpuVal, $script:RamVal, $script:DiskVal, $script:RustState,
    $script:CpuBar, $script:RamBar, $script:DiskBar
))

$statsPanel.Add_Resize({
    $w = $statsPanel.ClientSize.Width
    $script:CpuBar.Width  = [Math]::Max((S 60), $w - (S 28))
    $script:RamBar.Width  = [Math]::Max((S 60), $w - (S 28))
    $script:DiskBar.Width = [Math]::Max((S 60), $w - (S 28))
    $script:CpuVal.Left   = [Math]::Max((S 60), $w - (S 200))
    $script:RamVal.Left   = $script:CpuVal.Left
    $script:DiskVal.Left  = $script:CpuVal.Left
    $script:CpuVal.Width  = [Math]::Max((S 80), $w - $script:CpuVal.Left - (S 14))
    $script:RamVal.Width  = $script:CpuVal.Width
    $script:DiskVal.Width = $script:CpuVal.Width
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
$script:ContentScrollStrip = New-Object RustSuite.ScrollStrip
$script:ContentScrollStrip.Target = $script:RowHost
$contentWrap.Controls.Add($script:RowHost)
$contentWrap.Controls.Add($script:ContentScrollStrip)
try {
    [RustSuite.WheelHub]::Target = $script:RowHost
    [void][System.Windows.Forms.Application]::AddMessageFilter((New-Object RustSuite.WheelRouter))
} catch {}

$body.Controls.Add($nav, 0, 0)
$body.Controls.Add($contentWrap, 1, 0)
$body.Controls.Add($rightCol, 2, 0)

foreach ($c in @($form, $body, $footer, $nav, $navTop, $navBottom, $rightCol, $statsPanel,
                 $contentWrap, $logPanel, $logHost, $script:RowHost, $navScrollWrap)) {
    Enable-DoubleBuffer $c
}

# Ширина контента с запасом под вертикальную полосу прокрутки:
# иначе фиксированные панели вылезают вправо и появляется горизонтальный скролл.
function Get-RowWidth {
    param([int]$Pad = 22)
    $sb = 0
    try { $sb = [int][System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth } catch {}
    $w = $script:RowHost.ClientSize.Width - (S $Pad) - $sb
    if ($w -lt (S 280)) { $w = (S 280) }
    return [int]$w
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
    $w = Get-RowWidth 18
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
    if (-not $gid) { $gid = 'home' }
    $script:ActiveGroup = $gid

    # Останавливаем таймеры страниц, иначе они держат удалённые контролы.
    try {
        if ($script:TempTimer) { $script:TempTimer.Stop(); $script:TempTimer.Dispose(); $script:TempTimer = $null }
    } catch {}
    try {
        if ($script:ThemeTimer) { $script:ThemeTimer.Stop(); $script:ThemeTimer.Dispose(); $script:ThemeTimer = $null }
    } catch {}
    try {
        if ($script:RepairScanTimer) { $script:RepairScanTimer.Stop(); $script:RepairScanTimer.Dispose(); $script:RepairScanTimer = $null }
    } catch {}
    $script:SetTempBox = $null
    $script:SetCpuBar  = $null
    $script:SetRamBar  = $null
    $script:SetValCpu  = $null
    $script:SetValRam  = $null
    $script:PictureStatusLabel  = $null
    $script:PicturePreviewAfter = $null
    $script:PictureTiles        = @()
    $script:PictureDescLabel    = $null
    $script:HomeGauge           = $null
    $script:HomeSpark           = $null
    $script:HomeCpuVal          = $null
    $script:HomeRamVal          = $null
    $script:HomeStatusLbl       = $null
    $script:HomeHero            = $null
    $script:HomeCards           = @{}

    foreach ($k in $script:NavButtons.Keys) { $script:NavButtons[$k].Selected = ($k -eq $gid) }
    foreach ($c in @($script:RowHost.Controls)) { $c.Dispose() }
    $script:RowHost.Controls.Clear()
    $script:RowHost.AutoScrollMinSize = New-Object System.Drawing.Size 0, 0
    try { $script:RowHost.ScrollToTop() } catch {}

    # Строим новую страницу без промежуточных перерисовок — переход без мигания.
    try { [RustSuite.Native]::SetRedraw($script:RowHost, $false) } catch {}
    try { $script:RowHost.SuspendLayout() } catch {}

    try {
        if ($gid -eq 'home') { Show-HomePanel; return }
        if ($gid -eq 'binds') { Show-BindsPanel; return }
        if ($gid -eq 'picture') { Show-PicturePanel; return }
        if ($gid -eq 'repair') { Show-RepairPanel; return }
        if ($gid -eq 'settings') { Show-SettingsPanel; return }

    $items = @($script:Tweaks | Where-Object { $_.Group -eq $gid })
    $w = Get-RowWidth 18
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

    if ($gid -eq 'clean') {
        $btnDeep = New-Object RustSuite.FlatButton
        $btnDeep.Style  = 'Primary'
        $btnDeep.Text   = '✦  ГЛУБОКАЯ ОЧИСТКА WINDOWS'
        $btnDeep.Bounds = New-Object System.Drawing.Rectangle 0, $y, $w, (S 44)
        $btnDeep.Add_Click({ Start-DeepCleanFromUi })
        $script:RowHost.Controls.Add($btnDeep)

        $deepSub = New-Object System.Windows.Forms.Label
        $deepSub.Text      = 'TEMP · кэш обновлений · дампы · кэш браузеров · логи Steam/RUST · эскизы'
        $deepSub.Font      = [RustSuite.Theme]::FSmall
        $deepSub.ForeColor = [RustSuite.Theme]::Muted
        $deepSub.BackColor = [System.Drawing.Color]::Transparent
        $deepSub.AutoSize  = $false
        $deepSub.Bounds    = New-Object System.Drawing.Rectangle 0, ($y + (S 48)), $w, (S 16)
        $script:RowHost.Controls.Add($deepSub)
        $y += S 74
    }

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
