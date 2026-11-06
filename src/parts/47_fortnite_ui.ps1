# ============================================================
#  СТРАНИЦА «FORTNITE»: официальные пресеты и запуск игры
#  Никаких модификаций клиента, EAC и оверлеев.
# ============================================================

function Update-FortniteStatusLabel {
    try {
        if ($script:FortniteStatusLabel -and -not $script:FortniteStatusLabel.IsDisposed) {
            $script:FortniteStatusLabel.Text = 'Сейчас: ' + (Get-FortniteCfgStatusText)
        }
    } catch {}
}

function Add-FortnitePageExtras {
    param([int]$W, [int]$Y)

    $cw = $W
    $y  = $Y
    $ri = if ($script:FortniteInfo) { $script:FortniteInfo } else { Get-FortniteClientInfo }

    # ---------- Информация о клиенте ----------
    $info = New-Object System.Windows.Forms.Label
    if ($ri.Found) {
        $cfgTxt = if ($ri.CfgReady) { [string]$ri.CfgKeys + ' ключей' } else { 'создастся после первого запуска' }
        $eacTxt = if ($ri.Eac) { 'EAC найден, не изменяется' } else { 'EAC не найден' }
        $info.Text = ('Клиент ' + $ri.Version + '  ·  ' + $ri.Engine + '  ·  cfg: ' + $cfgTxt + "`r`n" +
                      'Обновлён ' + $ri.Updated + '  ·  ' + $eacTxt)
    } else {
        $info.Text = 'FORTNITE не найден. Установите игру через Epic Games Launcher и запустите её один раз — появится GameUserSettings.ini.'
    }
    $info.Font      = [RustSuite.Theme]::FSmall
    $info.ForeColor = [RustSuite.Theme]::Muted
    $info.BackColor = [System.Drawing.Color]::Transparent
    $info.AutoSize  = $false
    $info.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $cw, (S 38)
    $script:RowHost.Controls.Add($info)
    $y += S 44

    $head = New-Object System.Windows.Forms.Label
    $head.Text      = 'ОФИЦИАЛЬНЫЕ ПРЕСЕТЫ FORTNITE · GameUserSettings.ini'
    $head.Font      = [RustSuite.Theme]::FHead
    $head.ForeColor = [RustSuite.Theme]::Muted
    $head.BackColor = [System.Drawing.Color]::Transparent
    $head.AutoSize  = $false
    $head.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $cw, (S 16)
    $script:RowHost.Controls.Add($head)
    $y += S 22

    # ---------- Пресет максимального FPS ----------
    $btnPerf = New-Object RustSuite.FlatButton
    $btnPerf.Style  = 'Primary'
    $btnPerf.Text   = '⚡  МАКСИМАЛЬНЫЙ FPS · ПРИМЕНИТЬ СЕЙЧАС'
    $btnPerf.Bounds = New-Object System.Drawing.Rectangle 0, $y, $cw, (S 46)
    $btnPerf.Add_Click({
        $r = Set-FortniteCfgPreset 'performance'
        Set-Status $r.Message $(if ($r.Ok) { '#4ECB71' } else { '#E3B341' })
        Update-FortniteStatusLabel
    })
    $script:RowHost.Controls.Add($btnPerf)
    $y += S 54

    $half = [int](($cw - (S 8)) / 2)
    $btnBal = New-Object RustSuite.FlatButton
    $btnBal.Style  = 'Ghost'
    $btnBal.Text   = 'БАЛАНС'
    $btnBal.Font   = [RustSuite.Theme]::FSmall
    $btnBal.Bounds = New-Object System.Drawing.Rectangle 0, $y, $half, (S 38)
    $btnBal.Add_Click({
        $r = Set-FortniteCfgPreset 'balanced'
        Set-Status $r.Message $(if ($r.Ok) { '#4ECB71' } else { '#E3B341' })
        Update-FortniteStatusLabel
    })
    $btnQual = New-Object RustSuite.FlatButton
    $btnQual.Style  = 'Ghost'
    $btnQual.Text   = 'КАЧЕСТВО'
    $btnQual.Font   = [RustSuite.Theme]::FSmall
    $btnQual.Bounds = New-Object System.Drawing.Rectangle ($half + (S 8)), $y, ($cw - $half - (S 8)), (S 38)
    $btnQual.Add_Click({
        $r = Set-FortniteCfgPreset 'quality'
        Set-Status $r.Message $(if ($r.Ok) { '#4ECB71' } else { '#E3B341' })
        Update-FortniteStatusLabel
    })
    $script:RowHost.Controls.AddRange(@($btnBal, $btnQual))
    $y += S 46

    $script:FortniteStatusLabel = New-Object System.Windows.Forms.Label
    $script:FortniteStatusLabel.Text      = 'Сейчас: ' + (Get-FortniteCfgStatusText)
    $script:FortniteStatusLabel.Font      = [RustSuite.Theme]::FSmall
    $script:FortniteStatusLabel.ForeColor = [RustSuite.Theme]::Muted
    $script:FortniteStatusLabel.BackColor = [System.Drawing.Color]::Transparent
    $script:FortniteStatusLabel.AutoSize  = $false
    $script:FortniteStatusLabel.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $cw, (S 18)
    $script:RowHost.Controls.Add($script:FortniteStatusLabel)
    $y += S 24

    $btnUndo = New-Object RustSuite.FlatButton
    $btnUndo.Style  = 'Ghost'
    $btnUndo.Text   = '↩  ВЕРНУТЬ ИСХОДНЫЙ GAMEUSERSETTINGS.INI'
    $btnUndo.Font   = [RustSuite.Theme]::FSmall
    $btnUndo.Bounds = New-Object System.Drawing.Rectangle 0, $y, $cw, (S 36)
    $btnUndo.Add_Click({
        $r = Undo-FortniteCfg
        Set-Status $r.Message $(if ($r.Ok) { '#4ECB71' } else { '#E3B341' })
        Update-FortniteStatusLabel
    })
    $script:RowHost.Controls.Add($btnUndo)
    $y += S 48

    # ---------- Запуск и папка ----------
    $btnLaunch = New-Object RustSuite.FlatButton
    $btnLaunch.Style  = 'Primary'
    $btnLaunch.Text   = '▶  ЗАПУСТИТЬ FORTNITE С ОПТИМИЗАЦИЕЙ'
    $btnLaunch.Bounds = New-Object System.Drawing.Rectangle 0, $y, $cw, (S 46)
    $btnLaunch.Add_Click({ Start-Fortnite })
    $script:RowHost.Controls.Add($btnLaunch)
    $y += S 54

    $btnFolder = New-Object RustSuite.FlatButton
    $btnFolder.Style  = 'Ghost'
    $btnFolder.Text   = 'ОТКРЫТЬ ПАПКУ КОНФИГА'
    $btnFolder.Font   = [RustSuite.Theme]::FSmall
    $btnFolder.Bounds = New-Object System.Drawing.Rectangle 0, $y, $half, (S 34)
    $btnFolder.Add_Click({
        $d = Get-FortniteCfgDir
        if ($d) { Open-Explorer $d } else { Write-Log 'Fortnite не найден — папка конфига недоступна' 'warn' }
    })

    $btnCheck = New-Object RustSuite.FlatButton
    $btnCheck.Style  = 'Ghost'
    $btnCheck.Text   = '◈  ПРОВЕРИТЬ КЛИЕНТ И CFG'
    $btnCheck.Font   = [RustSuite.Theme]::FSmall
    $btnCheck.Bounds = New-Object System.Drawing.Rectangle ($half + (S 8)), $y, ($cw - $half - (S 8)), (S 34)
    $btnCheck.Add_Click({ Show-TextDialog 'FORTNITE' (Get-FortniteCompatText) })
    $script:RowHost.Controls.AddRange(@($btnFolder, $btnCheck))
    $y += S 44

    $note = New-Object System.Windows.Forms.Label
    $note.Text = 'Fortnite использует EasyAntiCheat. Меняются только официальные настройки меню игры, реестр Windows и профиль GPU: ' +
                 'exe/dll клиента и файлы EAC не затрагиваются. Если игра запущена, пресет запишется автоматически после её закрытия. ' +
                 'Откат возвращает исходный GameUserSettings.ini из резервной копии.'
    $note.Font      = [RustSuite.Theme]::FSmall
    $note.ForeColor = [RustSuite.Theme]::Muted
    $note.BackColor = [System.Drawing.Color]::Transparent
    $note.AutoSize  = $false
    $note.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $cw, (S 74)
    $script:RowHost.Controls.Add($note)
    $y += S 84

    return $y
}
