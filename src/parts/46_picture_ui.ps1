# ============================================================
#  СТРАНИЦА «КАРТИНКА»: пресеты, предпросмотр, гамма, панель GPU
#  Только официальные cfg-конвары, Windows-гамма и панель драйвера.
# ============================================================

function Get-PictureStatusText {
    $g = Get-GammaStatus
    $color = if ($g.Active) { 'цвет: ' + $g.Preset }
             elseif ($g.Supported) { 'цвет: стандарт' }
             else { 'цвет: только панель драйвера' }
    $rv = [string]$script:State['RustVisualPreset']
    $cfg = if ($rv) { 'client.cfg: ' + (Get-LookPresetName $rv) } else { 'client.cfg: без изменений' }
    return ($color + '   ·   ' + $cfg)
}

function Update-PictureStatusLabel {
    try {
        if ($script:PictureStatusLabel -and -not $script:PictureStatusLabel.IsDisposed) {
            $script:PictureStatusLabel.Text = Get-PictureStatusText
        }
    } catch {}
}

function New-LookPreview {
    param([int]$X, [int]$Y, [int]$W, [int]$H, [bool]$After)

    $p = New-Object RustSuite.BufferedPanel
    $p.Bounds    = New-Object System.Drawing.Rectangle $X, $Y, $W, $H
    $p.BackColor = [System.Drawing.Color]::FromArgb(20, 24, 32)
    $p.Tag       = $After

    $p.Add_Paint({
        param($s, $e)
        try {
            $g = $e.Graphics
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $w = [Math]::Max(2, $s.Width)
            $h = [Math]::Max(2, $s.Height)
            $after = [bool]$s.Tag

            # Небо: «до» — нейтральное, «после» — по выбранному пресету.
            $skyTop = [System.Drawing.Color]::FromArgb(43, 51, 64)
            $skyBot = [System.Drawing.Color]::FromArgb(91, 102, 117)
            $groundTop = [System.Drawing.Color]::FromArgb(60, 74, 53)
            $groundBot = [System.Drawing.Color]::FromArgb(42, 53, 38)
            $sun = [System.Drawing.Color]::FromArgb(205, 205, 190)
            if ($after) {
                $key = [string]$script:LookPreset
                if ($key -eq 'cinema') {
                    $skyTop = [System.Drawing.Color]::FromArgb(30, 62, 112)
                    $skyBot = [System.Drawing.Color]::FromArgb(244, 155, 82)
                    $groundTop = [System.Drawing.Color]::FromArgb(104, 112, 52)
                    $groundBot = [System.Drawing.Color]::FromArgb(52, 62, 30)
                    $sun = [System.Drawing.Color]::FromArgb(255, 224, 140)
                } elseif ($key -eq 'night') {
                    $skyTop = [System.Drawing.Color]::FromArgb(7, 15, 38)
                    $skyBot = [System.Drawing.Color]::FromArgb(34, 68, 110)
                    $groundTop = [System.Drawing.Color]::FromArgb(22, 44, 38)
                    $groundBot = [System.Drawing.Color]::FromArgb(10, 22, 20)
                    $sun = [System.Drawing.Color]::FromArgb(196, 220, 255)
                } else {
                    $skyTop = [System.Drawing.Color]::FromArgb(23, 96, 196)
                    $skyBot = [System.Drawing.Color]::FromArgb(139, 196, 255)
                    $groundTop = [System.Drawing.Color]::FromArgb(70, 150, 62)
                    $groundBot = [System.Drawing.Color]::FromArgb(33, 92, 40)
                    $sun = [System.Drawing.Color]::FromArgb(255, 218, 120)
                }
            }

            $skyRect = [System.Drawing.Rectangle]::new(0, 0, $w, [int]($h * 0.68))
            $skyBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
                $skyRect, $skyTop, $skyBot, [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
            $g.FillRectangle($skyBrush, $skyRect)
            $skyBrush.Dispose()

            $gndRect = [System.Drawing.Rectangle]::new(0, [int]($h * 0.68), $w, ([int]($h * 0.32) + 1))
            $gndBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
                $gndRect, $groundTop, $groundBot, [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
            $g.FillRectangle($gndBrush, $gndRect)
            $gndBrush.Dispose()

            # Солнце / луна с мягким ореолом.
            $cx = [int]($w * 0.76)
            $cy = [int]($h * 0.24)
            $r  = [int]([Math]::Max(7, $h * 0.085))
            $glow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(45, $sun.R, $sun.G, $sun.B))
            $g.FillEllipse($glow, ($cx - $r * 3), ($cy - $r * 3), ($r * 6), ($r * 6))
            $glow.Dispose()
            $sunBrush = New-Object System.Drawing.SolidBrush $sun
            $g.FillEllipse($sunBrush, ($cx - $r), ($cy - $r), ($r * 2), ($r * 2))
            $sunBrush.Dispose()

            # Дальние холмы.
            $hillAlpha = if ($after) { 150 } else { 90 }
            $hill = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($hillAlpha, 18, 34, 28))
            $hillPts = [System.Drawing.Point[]]@(
                [System.Drawing.Point]::new(0, [int]($h * 0.68)),
                [System.Drawing.Point]::new([int]($w * 0.28), [int]($h * 0.52)),
                [System.Drawing.Point]::new([int]($w * 0.52), [int]($h * 0.68)),
                [System.Drawing.Point]::new($w, [int]($h * 0.56)),
                [System.Drawing.Point]::new($w, [int]($h * 0.70)),
                [System.Drawing.Point]::new(0, [int]($h * 0.70))
            )
            $g.FillPolygon($hill, $hillPts)
            $hill.Dispose()

            # Пара деревьев-силуэтов.
            $tree = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(225, 16, 26, 20))
            foreach ($fx in @(0.18, 0.30, 0.64)) {
                $tx = [int]($w * $fx)
                $ty = [int]($h * 0.70)
                $th = [int]($h * 0.28)
                $tw = [int]([Math]::Max(8, $w * 0.035))
                $g.FillRectangle($tree, ($tx - [int]($tw / 4)), ($ty - [int]($th * 0.45)), [int]([Math]::Max(3, $tw / 2)), [int]($th * 0.45))
                $g.FillEllipse($tree, ($tx - $tw), ($ty - $th), ($tw * 2), [int]($th * 0.8))
            }
            $tree.Dispose()

            # Аккуратная виньетка, как в игре.
            if ($after) {
                $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(55, 0, 0, 0)), 3
                $g.DrawRectangle($pen, 1, 1, ($w - 3), ($h - 3))
                $pen.Dispose()
            }

            $label = if ($after) { 'ПОСЛЕ · ' + (Get-LookPresetName $script:LookPreset) } else { 'ДО · стандарт' }
            $badge = [System.Windows.Forms.TextRenderer]::MeasureText($label, [RustSuite.Theme]::FSmall)
            $br = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(170, 0, 0, 0))
            $g.FillRectangle($br, 8, 8, ($badge.Width + 14), 21)
            $br.Dispose()
            [System.Windows.Forms.TextRenderer]::DrawText($g, $label, [RustSuite.Theme]::FSmall,
                ([System.Drawing.Rectangle]::new(15, 10, ($badge.Width + 4), 17)),
                [System.Drawing.Color]::White,
                ([System.Windows.Forms.TextFormatFlags]::Left -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter))
            $script:PreviewPaints = [int]$script:PreviewPaints + 1
        } catch {
            if (-not $script:PreviewPaintWarned) {
                $script:PreviewPaintWarned = $true
                Write-Log ('Ошибка отрисовки предпросмотра: ' + $_.Exception.Message) 'err'
            }
        }
    })

    return $p
}

function Show-PicturePanel {
    $script:PreviewPaintWarned = $false
    $script:PreviewPaints = 0
    $w = $script:RowHost.ClientSize.Width - (S 22)
    if ($w -lt (S 340)) { $w = (S 340) }

    # ---------- Заголовок ----------
    $accentBar = New-Object System.Windows.Forms.Panel
    $accentBar.BackColor = [RustSuite.Theme]::Accent
    $accentBar.Bounds    = New-Object System.Drawing.Rectangle 0, (S 5), (S 3), (S 15)
    $script:RowHost.Controls.Add($accentBar)

    $head = New-Object System.Windows.Forms.Label
    $head.Text      = 'КАРТИНКА · СОЧНЫЙ ЦВЕТ БЕЗ ОВЕРЛЕЕВ'
    $head.Font      = [RustSuite.Theme]::FHead
    $head.ForeColor = [RustSuite.Theme]::TextC
    $head.BackColor = [System.Drawing.Color]::Transparent
    $head.AutoSize  = $false
    $head.Bounds    = New-Object System.Drawing.Rectangle (S 12), (S 2), $w, (S 22)
    $script:RowHost.Controls.Add($head)

    $sub = New-Object System.Windows.Forms.Label
    $sub.Text      = 'Гамма Windows + официальные конвары RUST + настройки панели NVIDIA/AMD. ' +
                     'Никаких Freestyle, ReShade и внедрения в игру.'
    $sub.Font      = [RustSuite.Theme]::FSmall
    $sub.ForeColor = [RustSuite.Theme]::Muted
    $sub.BackColor = [System.Drawing.Color]::Transparent
    $sub.AutoSize  = $false
    $sub.Bounds    = New-Object System.Drawing.Rectangle 0, (S 28), $w, (S 32)
    $sub.Anchor    = 'Top,Left,Right'
    $script:RowHost.Controls.Add($sub)

    $y = S 66

    # ---------- Видеокарта ----------
    $info = Get-GpuInfo -Refresh
    $lblGpu = New-Object System.Windows.Forms.Label
    $lblGpu.Text      = 'ВИДЕОКАРТА · ' + $info.VendorLabel
    $lblGpu.Font      = [RustSuite.Theme]::FHead
    $lblGpu.ForeColor = [RustSuite.Theme]::Muted
    $lblGpu.BackColor = [System.Drawing.Color]::Transparent
    $lblGpu.AutoSize  = $false
    $lblGpu.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 16)
    $script:RowHost.Controls.Add($lblGpu)
    $y += S 20

    $gpuName = New-Object System.Windows.Forms.Label
    $gpuName.Text      = [string]$info.Name
    $gpuName.Font      = [RustSuite.Theme]::FSub
    $gpuName.ForeColor = [RustSuite.Theme]::TextC
    $gpuName.BackColor = [System.Drawing.Color]::Transparent
    $gpuName.AutoSize  = $false
    $gpuName.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 20)
    $gpuName.Anchor    = 'Top,Left,Right'
    $script:RowHost.Controls.Add($gpuName)
    $y += S 22

    $gpuDetail = 'Панель: ' + $info.PanelName
    if ($info.Resolution -ne '—') { $gpuDetail += '   ·   ' + $info.Resolution }
    if ($info.Refresh -gt 0) { $gpuDetail += ' @ ' + [string]$info.Refresh + ' Гц' }
    if ($info.Driver) { $gpuDetail += '   ·   драйвер ' + $info.Driver }
    $gpuSub = New-Object System.Windows.Forms.Label
    $gpuSub.Text      = $gpuDetail
    $gpuSub.Font      = [RustSuite.Theme]::FSmall
    $gpuSub.ForeColor = [RustSuite.Theme]::Muted
    $gpuSub.BackColor = [System.Drawing.Color]::Transparent
    $gpuSub.AutoSize  = $false
    $gpuSub.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 16)
    $gpuSub.Anchor    = 'Top,Left,Right'
    $script:RowHost.Controls.Add($gpuSub)
    $y += S 22

    $half = [int](($w - (S 8)) / 2)

    $btnPanel = New-Object RustSuite.FlatButton
    $btnPanel.Style  = 'Primary'
    $btnPanel.Text   = 'ОТКРЫТЬ ПАНЕЛЬ ' + $info.VendorLabel.ToUpper()
    $btnPanel.Font   = [RustSuite.Theme]::FSmall
    $btnPanel.Bounds = New-Object System.Drawing.Rectangle 0, $y, $half, (S 34)
    $btnPanel.Add_Click({
        $r = Open-GpuPanel
        Set-Status $r.Message $(if ($r.Ok) { '#4ECB71' } else { '#E3B341' })
        Write-Log $r.Message $(if ($r.Ok) { 'info' } else { 'warn' })
        if (-not $r.Ok) {
            [void][System.Windows.Forms.MessageBox]::Show(
                ($r.Message + "`r`n`r`nСкопируйте инструкцию ниже и выставьте значения вручную."),
                'КАРТИНКА RUST', 'OK', 'Information')
        }
    })

    $btnCopyGuide = New-Object RustSuite.FlatButton
    $btnCopyGuide.Style  = 'Ghost'
    $btnCopyGuide.Text   = 'СКОПИРОВАТЬ ИНСТРУКЦИЮ'
    $btnCopyGuide.Font   = [RustSuite.Theme]::FSmall
    $btnCopyGuide.Bounds = New-Object System.Drawing.Rectangle ($half + (S 8)), $y, ($w - $half - (S 8)), (S 34)
    $btnCopyGuide.Add_Click({
        if (Copy-Text (Get-GpuPanelGuide)) {
            Set-Status 'Инструкция для панели драйвера скопирована' '#4ECB71'
            Write-Log 'Инструкция панели GPU скопирована в буфер обмена' 'ok'
        }
    })
    $script:RowHost.Controls.AddRange(@($btnPanel, $btnCopyGuide))
    $y += S 44

    $status = New-Object System.Windows.Forms.Label
    $status.Text      = Get-PictureStatusText
    $status.Font      = [RustSuite.Theme]::FSmall
    $status.ForeColor = [RustSuite.Theme]::AccentLt
    $status.BackColor = [System.Drawing.Color]::Transparent
    $status.AutoSize  = $false
    $status.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 16)
    $status.Anchor    = 'Top,Left,Right'
    $script:PictureStatusLabel = $status
    $script:RowHost.Controls.Add($status)
    $y += S 24

    # ---------- Предпросмотр до / после ----------
    $lblPrev = New-Object System.Windows.Forms.Label
    $lblPrev.Text      = 'ПРЕДПРОСМОТР · выберите пресет ниже'
    $lblPrev.Font      = [RustSuite.Theme]::FHead
    $lblPrev.ForeColor = [RustSuite.Theme]::Muted
    $lblPrev.BackColor = [System.Drawing.Color]::Transparent
    $lblPrev.AutoSize  = $false
    $lblPrev.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 16)
    $script:RowHost.Controls.Add($lblPrev)
    $y += S 20

    $prevGap = S 8
    $prevW = [int](($w - $prevGap) / 2)
    $prevH = S 116
    $before = New-LookPreview 0 $y $prevW $prevH $false
    $after  = New-LookPreview ($prevW + $prevGap) $y ($w - $prevW - $prevGap) $prevH $true
    $script:PicturePreviewAfter = $after
    $script:RowHost.Controls.AddRange(@($before, $after))
    $y += $prevH + (S 12)

    # ---------- Пресеты ----------
    $lblPresets = New-Object System.Windows.Forms.Label
    $lblPresets.Text      = 'ПРЕСЕТЫ КАРТИНКИ · нажмите, чтобы выбрать'
    $lblPresets.Font      = [RustSuite.Theme]::FHead
    $lblPresets.ForeColor = [RustSuite.Theme]::Muted
    $lblPresets.BackColor = [System.Drawing.Color]::Transparent
    $lblPresets.AutoSize  = $false
    $lblPresets.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 16)
    $script:RowHost.Controls.Add($lblPresets)
    $y += S 20

    $tileGap = S 6
    $tileW = [int](($w - ($tileGap * 2)) / 3)
    $tileH = S 96
    $script:PictureTiles = @()
    $idx = 0
    foreach ($p in $script:LookPresets) {
        $tile = New-Object RustSuite.ThemeTile
        $tile.Title = [string]$p.Name
        $tile.Sub   = [string]$p.Sub
        $tile.Tag   = [string]$p.Key
        if ($p.Key -eq 'cinema') {
            $tile.ColorA = [System.Drawing.Color]::FromArgb(120, 58, 20)
            $tile.ColorB = [System.Drawing.Color]::FromArgb(255, 168, 72)
            $tile.ColorC = [System.Drawing.Color]::FromArgb(255, 214, 128)
        } elseif ($p.Key -eq 'night') {
            $tile.ColorA = [System.Drawing.Color]::FromArgb(9, 22, 54)
            $tile.ColorB = [System.Drawing.Color]::FromArgb(52, 112, 214)
            $tile.ColorC = [System.Drawing.Color]::FromArgb(148, 204, 255)
        } else {
            $tile.ColorA = [System.Drawing.Color]::FromArgb(92, 28, 158)
            $tile.ColorB = [System.Drawing.Color]::FromArgb(255, 79, 216)
            $tile.ColorC = [System.Drawing.Color]::FromArgb(120, 220, 130)
        }
        $tile.Selected = ([string]$p.Key -eq [string]$script:LookPreset)
        $tile.Bounds   = New-Object System.Drawing.Rectangle ($idx * ($tileW + $tileGap)), $y, $tileW, $tileH
        $tile.Add_Click({
            param($s, $e)
            $key = [string]$s.Tag
            $script:LookPreset = $key
            foreach ($t in @($script:PictureTiles)) {
                try { if ($t -and -not $t.IsDisposed) { $t.Selected = ([string]$t.Tag -eq $key) } } catch {}
            }
            try { if ($script:PicturePreviewAfter -and -not $script:PicturePreviewAfter.IsDisposed) { $script:PicturePreviewAfter.Invalidate() } } catch {}
            try {
                if ($script:PictureDescLabel -and -not $script:PictureDescLabel.IsDisposed) {
                    $script:PictureDescLabel.Text = [string](Get-LookPreset $key).Desc
                }
            } catch {}
            $script:State['LookPreset'] = $key
            Save-State
            Set-Status ('Пресет картинки: ' + (Get-LookPresetName $key)) '#8B949E'
            Update-PictureStatusLabel
        })
        $script:PictureTiles += $tile
        $script:RowHost.Controls.Add($tile)
        $idx++
    }
    $y += $tileH + (S 14)

    $desc = Get-LookPreset $script:LookPreset
    $lblDesc = New-Object System.Windows.Forms.Label
    $lblDesc.Text      = [string]$desc.Desc
    $lblDesc.Font      = [RustSuite.Theme]::FSmall
    $lblDesc.ForeColor = [RustSuite.Theme]::Muted
    $lblDesc.BackColor = [System.Drawing.Color]::Transparent
    $lblDesc.AutoSize  = $false
    $lblDesc.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 32)
    $lblDesc.Anchor    = 'Top,Left,Right'
    $script:PictureDescLabel = $lblDesc
    $script:RowHost.Controls.Add($lblDesc)
    $y += S 40

    # ---------- Кнопки цвета ----------
    $lblColor = New-Object System.Windows.Forms.Label
    $lblColor.Text      = 'ЦВЕТ WINDOWS · гамма и контраст, обратимо'
    $lblColor.Font      = [RustSuite.Theme]::FHead
    $lblColor.ForeColor = [RustSuite.Theme]::Muted
    $lblColor.BackColor = [System.Drawing.Color]::Transparent
    $lblColor.AutoSize  = $false
    $lblColor.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 16)
    $script:RowHost.Controls.Add($lblColor)
    $y += S 22

    $btnApplyLook = New-Object RustSuite.FlatButton
    $btnApplyLook.Style  = 'Primary'
    $btnApplyLook.Text   = 'ПРИМЕНИТЬ ЦВЕТ'
    $btnApplyLook.Font   = [RustSuite.Theme]::FSmall
    $btnApplyLook.Bounds = New-Object System.Drawing.Rectangle 0, $y, $half, (S 36)
    $btnApplyLook.Add_Click({
        $r = Apply-LookPreset $script:LookPreset
        Set-Status $r.Message $(if ($r.Ok) { '#4ECB71' } else { '#E3B341' })
        Update-PictureStatusLabel
        if (-not $r.Ok) {
            [void][System.Windows.Forms.MessageBox]::Show($r.Message, 'КАРТИНКА RUST', 'OK', 'Information')
        }
    })

    $btnRestoreLook = New-Object RustSuite.FlatButton
    $btnRestoreLook.Style  = 'Ghost'
    $btnRestoreLook.Text   = 'ВЕРНУТЬ ЦВЕТ'
    $btnRestoreLook.Font   = [RustSuite.Theme]::FSmall
    $btnRestoreLook.Bounds = New-Object System.Drawing.Rectangle ($half + (S 8)), $y, ($w - $half - (S 8)), (S 36)
    $btnRestoreLook.Add_Click({
        $r = Restore-LookGamma
        Set-Status $r.Message $(if ($r.Ok) { '#4ECB71' } else { '#E3B341' })
        Update-PictureStatusLabel
        if (-not $r.Ok) {
            [void][System.Windows.Forms.MessageBox]::Show($r.Message, 'КАРТИНКА RUST', 'OK', 'Information')
        }
    })
    $script:RowHost.Controls.AddRange(@($btnApplyLook, $btnRestoreLook))
    $y += S 46

    $gammaNote = New-Object System.Windows.Forms.Label
    $gammaNote.Text      = 'Гамма действует на основной монитор и сбрасывается после перезагрузки Windows. ' +
                           'В полноэкранной игре драйвер может вернуть свою таблицу — тогда используйте панель NVIDIA/AMD.'
    $gammaNote.Font      = [RustSuite.Theme]::FSmall
    $gammaNote.ForeColor = [RustSuite.Theme]::Muted
    $gammaNote.BackColor = [System.Drawing.Color]::Transparent
    $gammaNote.AutoSize  = $false
    $gammaNote.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 30)
    $gammaNote.Anchor    = 'Top,Left,Right'
    $script:RowHost.Controls.Add($gammaNote)
    $y += S 40

    # ---------- client.cfg ----------
    $lblCfg = New-Object System.Windows.Forms.Label
    $lblCfg.Text      = 'RUST CLIENT.CFG · только официальные конвары'
    $lblCfg.Font      = [RustSuite.Theme]::FHead
    $lblCfg.ForeColor = [RustSuite.Theme]::Muted
    $lblCfg.BackColor = [System.Drawing.Color]::Transparent
    $lblCfg.AutoSize  = $false
    $lblCfg.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 16)
    $script:RowHost.Controls.Add($lblCfg)
    $y += S 22

    $btnCfg = New-Object RustSuite.FlatButton
    $btnCfg.Style  = 'Primary'
    $btnCfg.Text   = 'ЗАПИСАТЬ ПРЕСЕТ В CLIENT.CFG'
    $btnCfg.Font   = [RustSuite.Theme]::FSmall
    $btnCfg.Bounds = New-Object System.Drawing.Rectangle 0, $y, $half, (S 36)
    $btnCfg.Add_Click({
        $r = Set-RustVisualCfg $script:LookPreset
        Set-Status $r.Message $(if ($r.Ok) { '#4ECB71' } else { '#E3B341' })
        Update-PictureStatusLabel
        if (-not $r.Ok) {
            [void][System.Windows.Forms.MessageBox]::Show($r.Message, 'КАРТИНКА RUST', 'OK', 'Information')
        }
    })

    $btnCfgUndo = New-Object RustSuite.FlatButton
    $btnCfgUndo.Style  = 'Ghost'
    $btnCfgUndo.Text   = 'ВЕРНУТЬ CLIENT.CFG'
    $btnCfgUndo.Font   = [RustSuite.Theme]::FSmall
    $btnCfgUndo.Bounds = New-Object System.Drawing.Rectangle ($half + (S 8)), $y, ($w - $half - (S 8)), (S 36)
    $btnCfgUndo.Add_Click({
        $r = Undo-RustVisualCfg
        Set-Status $r.Message $(if ($r.Ok) { '#4ECB71' } else { '#E3B341' })
        Update-PictureStatusLabel
        if (-not $r.Ok) {
            [void][System.Windows.Forms.MessageBox]::Show($r.Message, 'КАРТИНКА RUST', 'OK', 'Information')
        }
    })
    $script:RowHost.Controls.AddRange(@($btnCfg, $btnCfgUndo))
    $y += S 46

    $cfgNote = New-Object System.Windows.Forms.Label
    $cfgNote.Text      = 'Перед записью закройте RUST: игра перезаписывает client.cfg при выходе. ' +
                         'Программа сохраняет только те строки, которые меняет, и возвращает их кнопкой «ВЕРНУТЬ CLIENT.CFG».'
    $cfgNote.Font      = [RustSuite.Theme]::FSmall
    $cfgNote.ForeColor = [RustSuite.Theme]::Muted
    $cfgNote.BackColor = [System.Drawing.Color]::Transparent
    $cfgNote.AutoSize  = $false
    $cfgNote.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 30)
    $cfgNote.Anchor    = 'Top,Left,Right'
    $script:RowHost.Controls.Add($cfgNote)
    $y += S 38

    # ---------- Инструкция панели ----------
    $lblGuide = New-Object System.Windows.Forms.Label
    $lblGuide.Text      = 'ПАНЕЛЬ ДРАЙВЕРА · точные значения'
    $lblGuide.Font      = [RustSuite.Theme]::FHead
    $lblGuide.ForeColor = [RustSuite.Theme]::Muted
    $lblGuide.BackColor = [System.Drawing.Color]::Transparent
    $lblGuide.AutoSize  = $false
    $lblGuide.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 16)
    $script:RowHost.Controls.Add($lblGuide)
    $y += S 22

    $guide = New-Object System.Windows.Forms.RichTextBox
    $guide.Text        = Get-GpuPanelGuide $info.Vendor
    $guide.ReadOnly    = $true
    $guide.BorderStyle = 'None'
    $guide.BackColor   = [RustSuite.Theme]::Field
    $guide.ForeColor   = [RustSuite.Theme]::TextC
    $guide.Font        = [RustSuite.Theme]::FSmall
    $guide.WordWrap    = $true
    $guide.ScrollBars  = 'Vertical'
    $guide.DetectUrls  = $false
    $guide.Bounds      = New-Object System.Drawing.Rectangle 0, $y, $w, (S 232)
    $guide.Anchor      = 'Top,Left,Right'
    $script:RowHost.Controls.Add($guide)
    $y += S 242

    $btnCopy2 = New-Object RustSuite.FlatButton
    $btnCopy2.Style  = 'Ghost'
    $btnCopy2.Text   = 'СКОПИРОВАТЬ ВСЕ НАСТРОЙКИ ПАНЕЛИ'
    $btnCopy2.Font   = [RustSuite.Theme]::FSmall
    $btnCopy2.Bounds = New-Object System.Drawing.Rectangle 0, $y, $w, (S 34)
    $btnCopy2.Anchor = 'Top,Left,Right'
    $btnCopy2.Add_Click({
        if (Copy-Text (Get-GpuPanelGuide)) {
            Set-Status 'Настройки панели драйвера скопированы' '#4ECB71'
            Write-Log 'Настройки панели драйвера скопированы' 'ok'
        }
    })
    $script:RowHost.Controls.Add($btnCopy2)
    $y += S 44

    # ---------- Безопасность ----------
    $note = New-Object System.Windows.Forms.Label
    $note.Text = 'Почему это безопасно: программа не ставит оверлеи, не подменяет шейдеры, не читает память игры ' +
                 'и не эмулирует ввод. Используются только файл настроек самого RUST, гамма-таблица Windows и панель драйвера. ' +
                 'Freestyle/ReShade и «фильтры поверх игры» не поддерживаются: они внедряются в кадр и могут конфликтовать с EAC. ' +
                 'Гарантии 0% бана не даёт ни один оптимизатор, но здесь нет ни одного вектора вмешательства в клиент.'
    $note.Font      = [RustSuite.Theme]::FSmall
    $note.ForeColor = [RustSuite.Theme]::Muted
    $note.BackColor = [System.Drawing.Color]::Transparent
    $note.AutoSize  = $false
    $note.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 92)
    $note.Anchor    = 'Top,Left,Right'
    $script:RowHost.Controls.Add($note)
    $y += S 102

    $script:RowHost.AutoScrollMinSize = New-Object System.Drawing.Size 0, ($y + (S 12))
}
