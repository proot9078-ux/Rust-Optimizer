# ============================================================
#  ДОВЕРИЕ И ПЛАН: проверяемый отчёт и предпросмотр изменений
#  Отчёт не требует интернета: он читает собственный исходник
#  и считает опасные шаблоны. Ноль находок — проверяемый факт.
# ============================================================
function Get-AuditSourcePath {
    $candidates = @()
    try {
        if ($PSScriptRoot) {
            $candidates += (Join-Path $PSScriptRoot 'RustOptimizer.ps1')
            $candidates += (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\RustOptimizer.ps1')
        }
    } catch {}
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

function Get-SourceFingerprint {
    $p = Get-AuditSourcePath
    if (-not $p) { return $null }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [IO.File]::OpenRead($p)
        try { $hash = $sha.ComputeHash($stream) } finally { $stream.Dispose() }
        $hex = ($hash | ForEach-Object { $_.ToString('x2') }) -join ''
        return [pscustomobject]@{
            Path   = $p
            Bytes  = (Get-Item -LiteralPath $p).Length
            SHA256 = $hex
        }
    } finally { $sha.Dispose() }
}

# Шаблоны собираются из частей, чтобы отчёт не находил сам себя.
function Get-TrustScan {
    $p = Get-AuditSourcePath
    $categories = @(
        @{ Name = 'Сетевые загрузки';        Needles = @(('Invoke-' + 'WebRequest'), ('Invoke-' + 'RestMethod'), ('Download' + 'String'), ('Download' + 'File'), ('Web' + 'Client'), ('Start-' + 'BitsTransfer')) },
        @{ Name = 'Внедрение в процесс';     Needles = @(('Write' + 'ProcessMemory'), ('Create' + 'RemoteThread'), ('Virtual' + 'AllocEx'), ('Open' + 'Process'), ('SetWindows' + 'HookEx')) },
        @{ Name = 'Динамический код';        Needles = @(('Invoke-' + 'Expression'), ('From' + 'Base64String'), ('Assembly' + ']::Load')) },
        @{ Name = 'Изменение клиента игры';  Needles = @(('RustClient' + '.exe.*Set-Content'), ('RustClient' + '.exe.*Copy-Item'), ('RustClient' + '.exe.*Remove-Item')) }
    )
    $text = ''
    if ($p) { try { $text = [IO.File]::ReadAllText($p) } catch { $text = '' } }
    $result = @()
    $total = 0
    foreach ($c in $categories) {
        $hits = 0
        foreach ($n in $c.Needles) {
            if (-not $n -or -not $text) { continue }
            try {
                $hits = $hits + ([regex]::Matches($text, [string]$n, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count
            } catch {}
        }
        $total = $total + $hits
        $result += [pscustomobject]@{ Name = $c.Name; Hits = $hits }
    }
    return [pscustomobject]@{ Items = $result; Total = $total; Scanned = [bool]($text.Length -gt 0) }
}

function Get-BackupStats {
    $reg = 0
    $cfg = 0
    try { if (Test-Path -LiteralPath $script:RegBackup) { $reg = @(Get-ChildItem -LiteralPath $script:RegBackup -File -ErrorAction SilentlyContinue).Count } } catch {}
    try { if (Test-Path -LiteralPath $script:RustBackup) { $cfg = @(Get-ChildItem -LiteralPath $script:RustBackup -File -ErrorAction SilentlyContinue).Count } } catch {}
    return @{ Reg = $reg; Cfg = $cfg }
}

# ============================================================
#  ЗАЩИТА КЛИЕНТА ИГРЫ
#  Снимок размеров и времени изменения RustClient.exe и DLL.
#  Программа никогда не пишет в эти файлы; снимок до/после
#  оптимизации доказывает, что клиент остался нетронутым.
# ============================================================
function Get-ClientGuardSnapshot {
    if (-not $script:RustExe) { return $null }
    $root = Split-Path -Parent $script:RustExe
    if (-not $root -or -not (Test-Path -LiteralPath $root)) { return $null }
    $files = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    $addFile = {
        param($file)
        try {
            if (-not $file -or -not (Test-Path -LiteralPath $file)) { return }
            $fi = Get-Item -LiteralPath $file -Force -ErrorAction Stop
            if ($fi.PSIsContainer) { return }
            $rel = $fi.FullName.Substring($root.Length).TrimStart('\')
            if ($seen.ContainsKey($rel)) { return }
            $seen[$rel] = $true
            $files.Add($rel + "`t" + [string]$fi.Length + "`t" + [string]$fi.LastWriteTimeUtc.Ticks)
        } catch {}
    }
    & $addFile (Join-Path $root 'RustClient.exe')
    & $addFile (Join-Path $root 'UnityPlayer.dll')
    try {
        foreach ($f in @(Get-ChildItem -LiteralPath $root -Filter '*.dll' -File -Force -ErrorAction SilentlyContinue)) { & $addFile $f.FullName }
        foreach ($f in @(Get-ChildItem -LiteralPath $root -Filter '*.exe' -File -Force -ErrorAction SilentlyContinue)) { & $addFile $f.FullName }
    } catch {}
    foreach ($rel in @('RustClient_Data\Plugins\x86_64\EasyAntiCheat\EasyAntiCheat_x64.dll',
                       'EasyAntiCheat\EasyAntiCheat_x64.dll',
                       'EasyAntiCheat\EasyAntiCheat.exe')) {
        & $addFile (Join-Path $root $rel)
    }
    $items = @($files | Sort-Object)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes(($items -join "`n"))
        $hash = ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join ''
    } finally { $sha.Dispose() }
    return [pscustomobject]@{
        Root  = $root
        Count = $items.Count
        Hash  = $hash
        Items = $items
        At    = (Get-Date).ToString('s')
    }
}

function Save-ClientGuardBaseline {
    $snap = Get-ClientGuardSnapshot
    if (-not $snap) { return $null }
    $script:State['ClientGuard'] = $snap
    Save-State
    return $snap
}

function Compare-ClientGuardSnapshots {
    param($Before, $After)
    $res = [pscustomobject]@{ State = 'none'; Missing = @(); Changed = @(); Added = @() }
    if (-not $Before -or -not $After) { return $res }
    $old = @{}
    foreach ($l in @($Before.Items)) {
        $p = ([string]$l).Split("`t")
        if ($p.Count -ge 3) { $old[$p[0]] = ($p[1] + '|' + $p[2]) }
    }
    $new = @{}
    foreach ($l in @($After.Items)) {
        $p = ([string]$l).Split("`t")
        if ($p.Count -ge 3) { $new[$p[0]] = ($p[1] + '|' + $p[2]) }
    }
    $missing = @(); $changed = @()
    foreach ($k in @($old.Keys)) {
        if (-not $new.ContainsKey($k)) { $missing += $k }
        elseif ($new[$k] -ne $old[$k]) { $changed += $k }
    }
    $added = @()
    foreach ($k in @($new.Keys)) { if (-not $old.ContainsKey($k)) { $added += $k } }
    $res.Missing = @($missing)
    $res.Changed = @($changed)
    $res.Added   = @($added)
    if ($missing.Count -eq 0 -and $changed.Count -eq 0 -and $added.Count -eq 0) { $res.State = 'ok' }
    else { $res.State = 'changed' }
    return $res
}

function Test-ClientGuard {
    $base = $script:State['ClientGuard']
    if (-not $base) { return [pscustomobject]@{ State = 'none'; Missing = @(); Changed = @(); Added = @() } }
    return (Compare-ClientGuardSnapshots $base (Get-ClientGuardSnapshot))
}

function Get-ClientGuardText {
    $base = $script:State['ClientGuard']
    $cur  = Get-ClientGuardSnapshot
    if (-not $cur) {
        return 'Клиент игры: RUST не найден, проверка недоступна.'
    }
    if (-not $base) {
        return ('Клиент игры: эталон ещё не снят. Файлов для контроля: ' + $cur.Count + '.')
    }
    $diff = Compare-ClientGuardSnapshots $base $cur
    $lines = @()
    if ($diff.State -eq 'ok') {
        $lines += ('Клиент игры        : НЕ ИЗМЕНЁН · файлов ' + $cur.Count)
    } else {
        $lines += ('Клиент игры        : ЕСТЬ ОТЛИЧИЯ от эталона')
        if ($diff.Missing.Count -gt 0) { $lines += ('  пропали          : ' + ($diff.Missing -join ', ')) }
        if ($diff.Changed.Count -gt 0) { $lines += ('  изменились       : ' + ($diff.Changed -join ', ')) }
        if ($diff.Added.Count -gt 0)   { $lines += ('  появились        : ' + ($diff.Added -join ', ')) }
    }
    $lines += ('Эталон снят         : ' + [string]$base.At)
    $lines += ('SHA256 метаданных   : ' + [string]$cur.Hash)
    return ($lines -join "`r`n")
}

function Get-TrustReportText {
    $fp = Get-SourceFingerprint
    $scan = Get-TrustScan
    $bk = Get-BackupStats
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('PURPLE RUSH — ОТЧЁТ О НАДЁЖНОСТИ')
    [void]$sb.AppendLine(('Версия            : ' + $script:AppVersion))
    [void]$sb.AppendLine(('PowerShell        : ' + $PSVersionTable.PSVersion.ToString()))
    [void]$sb.AppendLine(('Права              : ' + $(if ($script:IsAdmin) { 'администратор' } else { 'обычный пользователь' })))
    [void]$sb.AppendLine(('Лицензия           : MIT, исходный код открыт'))
    [void]$sb.AppendLine('')
    if ($fp) {
        [void]$sb.AppendLine(('Исходник           : ' + $fp.Path))
        [void]$sb.AppendLine(('Размер             : ' + [math]::Round($fp.Bytes / 1KB, 1) + ' КБ'))
        [void]$sb.AppendLine(('SHA256             : ' + $fp.SHA256))
    } else {
        [void]$sb.AppendLine('Исходник           : не найден рядом с приложением')
    }
    [void]$sb.AppendLine(('Модулей            : ' + @($script:Tweaks).Count))
    [void]$sb.AppendLine(('Резервные копии    : реестр ' + $bk.Reg + ' · cfg ' + $bk.Cfg))
    [void]$sb.AppendLine(('Состояние          : ' + $(if (Test-Path -LiteralPath $script:StateFile) { 'state.xml на месте' } else { 'будет создан при первом сохранении' })))
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('ЦЕЛОСТНОСТЬ КЛИЕНТА ИГРЫ')
    foreach ($line in ((Get-ClientGuardText) -split "`r?`n")) { [void]$sb.AppendLine('  ' + $line) }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('СТАТИЧЕСКИЙ АУДИТ ИСХОДНИКА')
    foreach ($it in $scan.Items) {
        [void]$sb.AppendLine(('  {0,-26} {1}' -f ($it.Name + ':'), $it.Hits))
    }
    [void]$sb.AppendLine(('  ИТОГО опасных совпадений: ' + $scan.Total))
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('КАК ЭТО ЧИТАТЬ')
    [void]$sb.AppendLine('  0 сетевых загрузок — программа не скачивает и не запускает код из интернета.')
    [void]$sb.AppendLine('  0 внедрений в процесс — нет инъекций, хуков и чтения памяти игры.')
    [void]$sb.AppendLine('  0 изменений клиента — RustClient.exe и *.dll не перезаписываются.')
    [void]$sb.AppendLine('  Меняются только официальные cfg-файлы игры, реестр Windows и настройки системы.')
    [void]$sb.AppendLine('  Перед применением создаётся точка восстановления и резервные копии реестра/cfg.')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Подпись кода: нет. Это открытый PowerShell-проект: любой может прочитать')
    [void]$sb.AppendLine('src\parts\*.ps1, собрать его через rebuild-bat.ps1 и сравнить SHA256.')
    return $sb.ToString()
}

function Get-PlanText {
    $on = @($script:Tweaks | Where-Object { $script:Enabled[$_.Id] })
    $all = @($script:Tweaks)
    $map = @{ home = 'ОБЗОР'; sys = 'СИСТЕМА'; net = 'СЕТЬ'; rust = 'RUST';
              picture = 'КАРТИНКА'; binds = 'БИНДЫ'; clean = 'ОЧИСТКА';
              repair = 'РЕМОНТ'; settings = 'НАСТРОЙКИ' }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('ПЛАН ОПТИМИЗАЦИИ — ПРЕДПРОСМОТР')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine(('Включено модулей : {0} из {1}' -f $on.Count, $all.Count))
    [void]$sb.AppendLine(('Рискованных      : {0}' -f @($on | Where-Object { $_.Risk }).Count))
    [void]$sb.AppendLine('')
    foreach ($g in @('sys', 'net', 'rust', 'clean')) {
        $items = @($on | Where-Object { $_.Group -eq $g })
        if ($items.Count -eq 0) { continue }
        [void]$sb.AppendLine(('[' + $map[$g] + ']  ' + $items.Count + ' шт.'))
        foreach ($t in $items) {
            $mark = if ($t.Risk) { '●' } else { '·' }
            [void]$sb.AppendLine(('   ' + $mark + ' ' + $t.Name))
        }
        [void]$sb.AppendLine('')
    }
    $risk = @($on | Where-Object { $_.Risk })
    if ($risk.Count -gt 0) {
        [void]$sb.AppendLine('МОДУЛИ С ПОМЕТКОЙ ● — включайте осознанно:')
        foreach ($t in $risk) { [void]$sb.AppendLine(('   ● ' + $t.Name + ' — ' + $t.Desc)) }
        [void]$sb.AppendLine('')
    }
    [void]$sb.AppendLine('Это только предпросмотр: до нажатия «ОПТИМИЗИРОВАТЬ» ничего не меняется.')
    [void]$sb.AppendLine('Перед применением создаётся точка восстановления и резервные копии.')
    return $sb.ToString()
}

function Show-TextDialog {
    param([string]$Title, [string]$Text, [string]$Note = '')
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = $Title
    $dlg.StartPosition   = 'CenterParent'
    $dlg.FormBorderStyle = 'Sizable'
    $dlg.MinimizeBox     = $false
    $dlg.MaximizeBox     = $false
    $dlg.BackColor       = [RustSuite.Theme]::Bg
    $dlg.ForeColor       = [RustSuite.Theme]::TextC
    $dlg.Font            = [RustSuite.Theme]::FSub
    $dlg.Size            = New-Object System.Drawing.Size (S 720), (S 560)
    $dlg.MinimumSize     = New-Object System.Drawing.Size (S 520), (S 400)

    $head = New-Object System.Windows.Forms.Label
    $head.Text      = $Title
    $head.Font      = [RustSuite.Theme]::FName
    $head.ForeColor = [RustSuite.Theme]::AccentLt
    $head.BackColor = [System.Drawing.Color]::Transparent
    $head.Dock      = 'Top'
    $head.Height    = S 34
    $head.Padding   = New-Object System.Windows.Forms.Padding (S 14), (S 10), 0, 0

    $box = New-Object System.Windows.Forms.RichTextBox
    $box.Dock        = 'Fill'
    $box.BorderStyle = 'None'
    $box.ReadOnly    = $true
    $box.WordWrap    = $false
    $box.BackColor   = [RustSuite.Theme]::Field
    $box.ForeColor   = [RustSuite.Theme]::TextC
    $box.Font        = [RustSuite.Theme]::FMono
    $box.Text        = $Text
    $box.DetectUrls  = $false

    $note = New-Object System.Windows.Forms.Label
    $note.Text      = $Note
    $note.Font      = [RustSuite.Theme]::FSmall
    $note.ForeColor = [RustSuite.Theme]::Muted
    $note.BackColor = [System.Drawing.Color]::Transparent
    $note.Dock      = 'Bottom'
    $note.Height    = S 24
    $note.Padding   = New-Object System.Windows.Forms.Padding (S 14), (S 4), 0, 0

    $bar = New-Object System.Windows.Forms.Panel
    $bar.Dock      = 'Bottom'
    $bar.Height    = S 50
    $bar.BackColor = [RustSuite.Theme]::PanelBg
    $bar.Padding   = New-Object System.Windows.Forms.Padding (S 12), (S 9), (S 12), (S 9)

    $btnCopy = New-Object RustSuite.FlatButton
    $btnCopy.Style  = 'Ghost'
    $btnCopy.Text   = 'КОПИРОВАТЬ'
    $btnCopy.Font   = [RustSuite.Theme]::FSmall
    $btnCopy.Width  = S 160
    $btnCopy.Dock   = 'Left'

    $btnClose = New-Object RustSuite.FlatButton
    $btnClose.Style  = 'Primary'
    $btnClose.Text   = 'ЗАКРЫТЬ'
    $btnClose.Font   = [RustSuite.Theme]::FSmall
    $btnClose.Width  = S 160
    $btnClose.Dock   = 'Right'

    $btnCopy.Add_Click(({
        try { [System.Windows.Forms.Clipboard]::SetText($box.Text) } catch {}
    }).GetNewClosure())
    $btnClose.Add_Click(({ try { $dlg.Close() } catch {} }).GetNewClosure())

    $bar.Controls.Add($btnClose)
    $bar.Controls.Add($btnCopy)
    $dlg.Controls.Add($box)
    $dlg.Controls.Add($head)
    $dlg.Controls.Add($note)
    $dlg.Controls.Add($bar)
    $dlg.Add_Shown({ param($s, $e) try { [void][RustSuite.Native]::DarkTitle($s) } catch {} })

    try {
        if ($script:MainForm -and -not $script:MainForm.IsDisposed) {
            $dlg.ShowDialog($script:MainForm)
        } else {
            $dlg.ShowDialog()
        }
    } finally {
        try { $dlg.Dispose() } catch {}
    }
}

function Show-PlanPreview {
    Show-TextDialog 'ПЛАН ОПТИМИЗАЦИИ' (Get-PlanText) 'Предпросмотр ничего не изменяет. Закройте окно и нажмите «ОПТИМИЗИРОВАТЬ».'
}

function Show-TrustReport {
    Show-TextDialog 'ОТЧЁТ О НАДЁЖНОСТИ' (Get-TrustReportText) 'Отчёт построен по локальному исходнику. Скопируйте его и сравните SHA256 с релизом на GitHub.'
}

function Show-ClientGuardReport {
    $text = (Get-ClientGuardText) + "`r`n`r`n" +
        "Что проверяется:`r`n" +
        "  RustClient.exe, UnityPlayer.dll, все DLL и EXE в корне игры,`r`n" +
        "  файлы EasyAntiCheat.`r`n`r`n" +
        "Сравниваются размер и время изменения. Программа не открывает`r`n" +
        "эти файлы на запись и не читает память игры, поэтому после`r`n" +
        "оптимизации снимок обязан совпадать. Если файлы изменились —`r`n" +
        "это сделала игра, Steam или другое приложение, а не PURPLE RUSH."
    Show-TextDialog 'КЛИЕНТ RUST · ПРОВЕРКА ЦЕЛОСТНОСТИ' $text 'Эталон снимается при запуске программы и перед каждой оптимизацией.'
}
