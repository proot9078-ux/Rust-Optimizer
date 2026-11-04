# ============================================================
#  НАСТРОЙКИ: ТЕМЫ + МОНИТОРИНГ
#  ВАЖНО: этот файл загружается ДО 40_ui.ps1, поэтому функция
#  Show-SettingsPanel уже существует к моменту первого Show-Group.
# ============================================================
function S([double]$v) { return [int][math]::Round($v * $script:SC) }

# ---------- Палитры ----------
$script:Themes = @(
    @{ Name='PURPLE RUSH'; Bg=[System.Drawing.Color]::FromArgb(18,10,28);  Panel=[System.Drawing.Color]::FromArgb(28,15,42);  Card=[System.Drawing.Color]::FromArgb(36,20,58);  CardHover=[System.Drawing.Color]::FromArgb(48,28,72);  Border=[System.Drawing.Color]::FromArgb(70,45,110);  Accent=[System.Drawing.Color]::FromArgb(160,60,220);  AccentLt=[System.Drawing.Color]::FromArgb(200,100,255); Secondary=[System.Drawing.Color]::FromArgb(255,79,216); Glow=[System.Drawing.Color]::FromArgb(106,31,176); TextC=[System.Drawing.Color]::FromArgb(245,240,255); Muted=[System.Drawing.Color]::FromArgb(170,150,190); Ok=[System.Drawing.Color]::FromArgb(120,200,120); Warn=[System.Drawing.Color]::FromArgb(240,200,60);   Err=[System.Drawing.Color]::FromArgb(255,100,120); Field=[System.Drawing.Color]::FromArgb(22,14,38) },
    @{ Name='MIDNIGHT';    Bg=[System.Drawing.Color]::FromArgb(10,14,26); Panel=[System.Drawing.Color]::FromArgb(16,20,36); Card=[System.Drawing.Color]::FromArgb(22,30,48); CardHover=[System.Drawing.Color]::FromArgb(30,40,60); Border=[System.Drawing.Color]::FromArgb(50,64,100); Accent=[System.Drawing.Color]::FromArgb(60,120,255);  AccentLt=[System.Drawing.Color]::FromArgb(100,160,255); Secondary=[System.Drawing.Color]::FromArgb(0,212,255); Glow=[System.Drawing.Color]::FromArgb(30,80,176); TextC=[System.Drawing.Color]::FromArgb(230,235,245); Muted=[System.Drawing.Color]::FromArgb(140,150,170); Ok=[System.Drawing.Color]::FromArgb(80,220,130);  Warn=[System.Drawing.Color]::FromArgb(250,190,50);   Err=[System.Drawing.Color]::FromArgb(255,90,110);  Field=[System.Drawing.Color]::FromArgb(14,16,30) },
    @{ Name='EMERALD';     Bg=[System.Drawing.Color]::FromArgb(10,20,14); Panel=[System.Drawing.Color]::FromArgb(15,28,20); Card=[System.Drawing.Color]::FromArgb(20,36,28); CardHover=[System.Drawing.Color]::FromArgb(28,48,36); Border=[System.Drawing.Color]::FromArgb(60,100,70);  Accent=[System.Drawing.Color]::FromArgb(60,220,100); AccentLt=[System.Drawing.Color]::FromArgb(100,255,150); Secondary=[System.Drawing.Color]::FromArgb(0,255,176); Glow=[System.Drawing.Color]::FromArgb(30,140,70); TextC=[System.Drawing.Color]::FromArgb(240,245,235); Muted=[System.Drawing.Color]::FromArgb(160,175,160); Ok=[System.Drawing.Color]::FromArgb(100,240,120); Warn=[System.Drawing.Color]::FromArgb(240,210,60);   Err=[System.Drawing.Color]::FromArgb(240,100,110); Field=[System.Drawing.Color]::FromArgb(12,18,14) },
    @{ Name='CRIMSON';     Bg=[System.Drawing.Color]::FromArgb(26,10,14); Panel=[System.Drawing.Color]::FromArgb(36,15,22); Card=[System.Drawing.Color]::FromArgb(48,22,30); CardHover=[System.Drawing.Color]::FromArgb(60,30,42); Border=[System.Drawing.Color]::FromArgb(110,45,70); Accent=[System.Drawing.Color]::FromArgb(255,60,90);  AccentLt=[System.Drawing.Color]::FromArgb(255,120,140); Secondary=[System.Drawing.Color]::FromArgb(255,154,60); Glow=[System.Drawing.Color]::FromArgb(176,30,60); TextC=[System.Drawing.Color]::FromArgb(245,230,235); Muted=[System.Drawing.Color]::FromArgb(180,140,160); Ok=[System.Drawing.Color]::FromArgb(100,220,120); Warn=[System.Drawing.Color]::FromArgb(255,200,60);   Err=[System.Drawing.Color]::FromArgb(255,100,120); Field=[System.Drawing.Color]::FromArgb(30,12,16) },
    @{ Name='CYBERPUNK';   Bg=[System.Drawing.Color]::FromArgb(5,10,18);  Panel=[System.Drawing.Color]::FromArgb(8,18,30);  Card=[System.Drawing.Color]::FromArgb(12,26,42);  CardHover=[System.Drawing.Color]::FromArgb(18,36,54);  Border=[System.Drawing.Color]::FromArgb(30,74,102);  Accent=[System.Drawing.Color]::FromArgb(0,229,255);  AccentLt=[System.Drawing.Color]::FromArgb(100,240,255); Secondary=[System.Drawing.Color]::FromArgb(255,43,214); Glow=[System.Drawing.Color]::FromArgb(0,136,170); TextC=[System.Drawing.Color]::FromArgb(230,250,255); Muted=[System.Drawing.Color]::FromArgb(122,160,180); Ok=[System.Drawing.Color]::FromArgb(50,255,154); Warn=[System.Drawing.Color]::FromArgb(255,210,60);   Err=[System.Drawing.Color]::FromArgb(255,79,120); Field=[System.Drawing.Color]::FromArgb(6,16,26) },
    @{ Name='ROYAL GOLD';  Bg=[System.Drawing.Color]::FromArgb(18,16,10); Panel=[System.Drawing.Color]::FromArgb(28,24,16); Card=[System.Drawing.Color]::FromArgb(38,32,22); CardHover=[System.Drawing.Color]::FromArgb(50,40,28); Border=[System.Drawing.Color]::FromArgb(100,80,42); Accent=[System.Drawing.Color]::FromArgb(212,160,50); AccentLt=[System.Drawing.Color]::FromArgb(255,210,100); Secondary=[System.Drawing.Color]::FromArgb(255,240,160); Glow=[System.Drawing.Color]::FromArgb(140,110,30); TextC=[System.Drawing.Color]::FromArgb(255,248,230); Muted=[System.Drawing.Color]::FromArgb(180,163,130); Ok=[System.Drawing.Color]::FromArgb(140,210,120); Warn=[System.Drawing.Color]::FromArgb(255,200,60);   Err=[System.Drawing.Color]::FromArgb(255,100,120); Field=[System.Drawing.Color]::FromArgb(22,18,12) },
    @{ Name='ARCTIC';      Bg=[System.Drawing.Color]::FromArgb(10,16,24); Panel=[System.Drawing.Color]::FromArgb(16,24,32); Card=[System.Drawing.Color]::FromArgb(22,34,44); CardHover=[System.Drawing.Color]::FromArgb(30,46,58); Border=[System.Drawing.Color]::FromArgb(58,86,104); Accent=[System.Drawing.Color]::FromArgb(90,200,255); AccentLt=[System.Drawing.Color]::FromArgb(150,230,255); Secondary=[System.Drawing.Color]::FromArgb(200,244,255); Glow=[System.Drawing.Color]::FromArgb(42,124,160); TextC=[System.Drawing.Color]::FromArgb(240,250,255); Muted=[System.Drawing.Color]::FromArgb(146,168,180); Ok=[System.Drawing.Color]::FromArgb(100,224,160); Warn=[System.Drawing.Color]::FromArgb(255,210,100);  Err=[System.Drawing.Color]::FromArgb(255,110,130); Field=[System.Drawing.Color]::FromArgb(12,18,24) },
    @{ Name='SAKURA';      Bg=[System.Drawing.Color]::FromArgb(24,10,18); Panel=[System.Drawing.Color]::FromArgb(36,16,28); Card=[System.Drawing.Color]::FromArgb(48,22,38); CardHover=[System.Drawing.Color]::FromArgb(62,30,48); Border=[System.Drawing.Color]::FromArgb(112,64,90); Accent=[System.Drawing.Color]::FromArgb(255,92,168); AccentLt=[System.Drawing.Color]::FromArgb(255,154,204); Secondary=[System.Drawing.Color]::FromArgb(255,200,160); Glow=[System.Drawing.Color]::FromArgb(176,38,110); TextC=[System.Drawing.Color]::FromArgb(255,240,246); Muted=[System.Drawing.Color]::FromArgb(188,142,166); Ok=[System.Drawing.Color]::FromArgb(120,216,144); Warn=[System.Drawing.Color]::FromArgb(255,200,100);  Err=[System.Drawing.Color]::FromArgb(255,92,120);  Field=[System.Drawing.Color]::FromArgb(30,12,22) },
    @{ Name='OBSIDIAN';    Bg=[System.Drawing.Color]::FromArgb(10,10,12); Panel=[System.Drawing.Color]::FromArgb(18,18,22); Card=[System.Drawing.Color]::FromArgb(26,26,32); CardHover=[System.Drawing.Color]::FromArgb(36,36,44); Border=[System.Drawing.Color]::FromArgb(60,60,72);  Accent=[System.Drawing.Color]::FromArgb(180,180,200); AccentLt=[System.Drawing.Color]::FromArgb(230,230,240); Secondary=[System.Drawing.Color]::FromArgb(140,140,160); Glow=[System.Drawing.Color]::FromArgb(80,80,94); TextC=[System.Drawing.Color]::FromArgb(248,248,250); Muted=[System.Drawing.Color]::FromArgb(152,152,166); Ok=[System.Drawing.Color]::FromArgb(140,216,144); Warn=[System.Drawing.Color]::FromArgb(216,192,112); Err=[System.Drawing.Color]::FromArgb(224,104,120); Field=[System.Drawing.Color]::FromArgb(14,14,18) },
    @{ Name='TOXIC';       Bg=[System.Drawing.Color]::FromArgb(10,16,6);  Panel=[System.Drawing.Color]::FromArgb(18,26,12); Card=[System.Drawing.Color]::FromArgb(26,36,18); CardHover=[System.Drawing.Color]::FromArgb(36,48,26); Border=[System.Drawing.Color]::FromArgb(74,100,42);  Accent=[System.Drawing.Color]::FromArgb(168,230,60); AccentLt=[System.Drawing.Color]::FromArgb(212,255,100); Secondary=[System.Drawing.Color]::FromArgb(240,255,60); Glow=[System.Drawing.Color]::FromArgb(90,140,30); TextC=[System.Drawing.Color]::FromArgb(246,255,234); Muted=[System.Drawing.Color]::FromArgb(160,180,138); Ok=[System.Drawing.Color]::FromArgb(140,255,100); Warn=[System.Drawing.Color]::FromArgb(255,230,60);   Err=[System.Drawing.Color]::FromArgb(255,92,100);  Field=[System.Drawing.Color]::FromArgb(14,20,8) },
    @{ Name='AURORA';      Bg=[System.Drawing.Color]::FromArgb(8,14,22);  Panel=[System.Drawing.Color]::FromArgb(12,22,34); Card=[System.Drawing.Color]::FromArgb(18,32,48); CardHover=[System.Drawing.Color]::FromArgb(26,44,64); Border=[System.Drawing.Color]::FromArgb(46,86,110); Accent=[System.Drawing.Color]::FromArgb(64,224,200); AccentLt=[System.Drawing.Color]::FromArgb(120,255,232); Secondary=[System.Drawing.Color]::FromArgb(150,120,255); Glow=[System.Drawing.Color]::FromArgb(30,140,130); TextC=[System.Drawing.Color]::FromArgb(232,255,252); Muted=[System.Drawing.Color]::FromArgb(140,170,176); Ok=[System.Drawing.Color]::FromArgb(110,235,160); Warn=[System.Drawing.Color]::FromArgb(250,210,90);   Err=[System.Drawing.Color]::FromArgb(255,110,140); Field=[System.Drawing.Color]::FromArgb(10,18,26) },
    @{ Name='NEON NOIR';   Bg=[System.Drawing.Color]::FromArgb(8,8,12);   Panel=[System.Drawing.Color]::FromArgb(14,14,22); Card=[System.Drawing.Color]::FromArgb(20,20,32); CardHover=[System.Drawing.Color]::FromArgb(30,30,46); Border=[System.Drawing.Color]::FromArgb(56,50,96);  Accent=[System.Drawing.Color]::FromArgb(255,54,140); AccentLt=[System.Drawing.Color]::FromArgb(255,120,190); Secondary=[System.Drawing.Color]::FromArgb(60,230,255); Glow=[System.Drawing.Color]::FromArgb(120,24,90); TextC=[System.Drawing.Color]::FromArgb(245,245,252); Muted=[System.Drawing.Color]::FromArgb(150,148,168); Ok=[System.Drawing.Color]::FromArgb(100,230,170); Warn=[System.Drawing.Color]::FromArgb(250,200,80);   Err=[System.Drawing.Color]::FromArgb(255,90,120);  Field=[System.Drawing.Color]::FromArgb(12,12,18) }
)

$script:ThemeName = 'PURPLE RUSH'

function Set-ThemeColors {
    param($Palette)
    if (-not $Palette) { return }
    [RustSuite.Theme]::Bg        = $Palette.Bg
    [RustSuite.Theme]::PanelBg   = $Palette.Panel
    [RustSuite.Theme]::CardBg    = $Palette.Card
    [RustSuite.Theme]::CardHover = $Palette.CardHover
    [RustSuite.Theme]::BorderC   = $Palette.Border
    [RustSuite.Theme]::Accent    = $Palette.Accent
    [RustSuite.Theme]::AccentLt  = $Palette.AccentLt
    [RustSuite.Theme]::Secondary = $Palette.Secondary
    [RustSuite.Theme]::Glow      = $Palette.Glow
    [RustSuite.Theme]::TextC     = $Palette.TextC
    [RustSuite.Theme]::Muted     = $Palette.Muted
    [RustSuite.Theme]::Ok        = $Palette.Ok
    [RustSuite.Theme]::Warn      = $Palette.Warn
    [RustSuite.Theme]::Err       = $Palette.Err
    [RustSuite.Theme]::Field     = $Palette.Field
}

function Apply-Theme {
    param([string]$Name, [switch]$Save)
    $pal = $script:Themes | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if (-not $pal) { $pal = $script:Themes[0] }
    $script:PrevPalette = $script:CurrentPalette
    Set-ThemeColors $pal
    $script:CurrentPalette = $pal
    $script:ThemeName = $pal.Name
    if ($Save) {
        $script:State['Theme'] = $pal.Name
        Save-State
    }
}

# Применяем сохранённую тему ещё до создания окон.
if ($script:State['Theme']) { Apply-Theme ([string]$script:State['Theme']) }
else { Apply-Theme $script:Themes[0].Name }

function Update-ControlTree {
    param($Root)
    if (-not $Root) { return }
    foreach ($c in @($Root.Controls)) {
        if (-not $c) { continue }
        try {
            if ($c -is [System.Windows.Forms.Label]) {
                $pv = $script:PrevPalette
                if ($pv) {
                    if ($c.BackColor.ToArgb() -eq $pv.Bg.ToArgb()) { $c.BackColor = [RustSuite.Theme]::Bg }
                    elseif ($c.BackColor.ToArgb() -eq $pv.Panel.ToArgb()) { $c.BackColor = [RustSuite.Theme]::PanelBg }
                    if ($c.ForeColor.ToArgb() -eq $pv.Muted.ToArgb()) { $c.ForeColor = [RustSuite.Theme]::Muted }
                    elseif ($c.ForeColor.ToArgb() -eq $pv.TextC.ToArgb()) { $c.ForeColor = [RustSuite.Theme]::TextC }
                } elseif ($c.BackColor -ne [System.Drawing.Color]::Transparent) {
                    $c.BackColor = [RustSuite.Theme]::Bg
                }
            } elseif ($c -is [System.Windows.Forms.TextBox]) {
                $c.BackColor = [RustSuite.Theme]::Field
                $c.ForeColor = [RustSuite.Theme]::TextC
            } elseif ($c -is [System.Windows.Forms.ComboBox] -or $c -is [System.Windows.Forms.ListBox]) {
                $c.BackColor = [RustSuite.Theme]::Field
                $c.ForeColor = [RustSuite.Theme]::TextC
            } elseif ($c -is [System.Windows.Forms.CheckBox]) {
                $c.BackColor = [System.Drawing.Color]::Transparent
                $c.ForeColor = [RustSuite.Theme]::TextC
            }
        } catch {}
        if ($c.HasChildren) { Update-ControlTree $c }
    }
}

function Update-ThemeSurfaces {
    try { if ($script:MainForm -and -not $script:MainForm.IsDisposed) { $script:MainForm.BackColor = [RustSuite.Theme]::Bg } } catch {}
    $pairs = @(
        @{ N='FooterPanel';  C='Panel' }, @{ N='NavPanel';      C='Bg' },
        @{ N='NavTopPanel';  C='Bg' },    @{ N='NavBottomPanel'; C='Bg' },
        @{ N='NavScrollWrap'; C='Bg' },
        @{ N='BodyPanel';    C='Bg' },    @{ N='ContentWrap';   C='Bg' },
        @{ N='RightCol';     C='Panel' }, @{ N='StatsPanel';    C='Panel' },
        @{ N='LogPanel';     C='Panel' }, @{ N='LogHost';       C='Panel' }
    )
    foreach ($p in $pairs) {
        try {
            $v = Get-Variable -Name $p.N -Scope Script -ErrorAction SilentlyContinue
            if ($v -and $v.Value -and -not $v.Value.IsDisposed) {
                if ($p.C -eq 'Panel') { $v.Value.BackColor = [RustSuite.Theme]::PanelBg }
                else { $v.Value.BackColor = [RustSuite.Theme]::Bg }
            }
        } catch {}
    }
    try { if ($script:Status) { $script:Status.ForeColor = [RustSuite.Theme]::Muted } } catch {}
    try {
        if ($script:MainForm -and -not $script:MainForm.IsDisposed) {
            Update-ControlTree $script:MainForm
            $script:MainForm.Invalidate($true)
        }
    } catch {}
}

# Перестроить панель настроек после смены темы (безопасно, вне обработчика клика).
function Restart-SettingsSoon {
    try {
        if ($script:ThemeTimer) { $script:ThemeTimer.Stop(); $script:ThemeTimer.Dispose() }
        $script:ThemeTimer = New-Object System.Windows.Forms.Timer
        $script:ThemeTimer.Interval = 40
        $script:ThemeTimer.Add_Tick({
            try { $script:ThemeTimer.Stop() } catch {}
            # Перестраиваем только если пользователь всё ещё на странице настроек.
            if ($script:ActiveGroup -eq 'settings') {
                try { Show-Group 'settings' } catch {}
            }
        })
        $script:ThemeTimer.Start()
    } catch {}
}

# ---------- Быстрые датчики (без WMI на каждом тике) ----------
function Get-CpuLoadFast {
    param([switch]$Force)
    $now = Get-Date
    try {
        # PerformanceCounter нельзя опрашивать чаще ~1 раза в секунду:
        # иначе он возвращает 0 и график «дёргается».
        if (-not $Force -and $script:CpuSampleAt -and
            ($now - $script:CpuSampleAt).TotalMilliseconds -lt 900) {
            return [int]$script:CpuSample
        }
    } catch {}
    try {
        if (-not $script:PcCpu) {
            $script:PcCpu = New-Object System.Diagnostics.PerformanceCounter('Processor', '% Processor Time', '_Total')
            [void]$script:PcCpu.NextValue()
        }
        $v = [int][Math]::Round([double]$script:PcCpu.NextValue())
        if ($v -lt 0) { $v = 0 }
        if ($v -gt 100) { $v = 100 }
        $script:CpuSampleAt = $now
        $script:CpuSample   = $v
        return $v
    } catch { return -1 }
}

function Get-RamLoadFast {
    try {
        $m = [RustSuite.Native]::MemLoad()
        if ($m -ge 0) { return [int]$m }
    } catch {}
    return -1
}

function Get-GpuNameFast {
    if ($script:GpuName) { return $script:GpuName }
    $name = ''
    try {
        $base = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
        $keys = @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue |
                  Where-Object { $_.PSChildName -match '^\d{4}$' })
        foreach ($k in $keys) {
            $d = (Get-ItemProperty -LiteralPath $k.PSPath -Name 'DriverDesc' -ErrorAction SilentlyContinue).DriverDesc
            if ($d) { $name = [string]$d; break }
        }
    } catch {}
    if (-not $name) {
        try {
            $name = [string]((Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
                              Select-Object -First 1).Name)
        } catch {}
    }
    if (-not $name) { $name = 'не определён' }
    $script:GpuName = $name
    return $name
}

function Get-AcpiTemp {
    # WMI-датчик опрашиваем не чаще раза в 30 секунд: он медленный.
    try {
        if ($script:AcpiTempAt -and ((Get-Date) - $script:AcpiTempAt).TotalSeconds -lt 30) {
            return $script:AcpiTempCache
        }
    } catch {}
    $script:AcpiTempAt = Get-Date
    $script:AcpiTempCache = $null
    try {
        $z = @(Get-CimInstance -Namespace 'root/wmi' -ClassName 'MSAcpi_ThermalZoneTemperature' -ErrorAction SilentlyContinue)
        foreach ($t in $z) {
            $c = [double]$t.CurrentTemperature / 10.0 - 273.15
            if ($c -gt 1 -and $c -lt 125) { $script:AcpiTempCache = [math]::Round($c, 1); break }
        }
    } catch {}
    return $script:AcpiTempCache
}

# Один раз собираем сведения о ПК — для карточки «Система».
function Get-SystemReport {
    if ($script:SysReportCache) { return [string]$script:SysReportCache }
    $lines = New-Object System.Collections.Generic.List[string]
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($os) {
            $ver = ([string]$os.Caption).Trim()
            $lines.Add(('ОС: ' + $ver + ' ' + [string]$os.Version + ' (build ' + [string]$os.BuildNumber + ')'))
        }
    } catch {}
    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cpu) {
            $name = ([string]$cpu.Name).Trim() -replace '\s+', ' '
            $lines.Add(('CPU: ' + $name))
            $lines.Add(('Ядра / потоки: ' + [string]$cpu.NumberOfCores + ' / ' + [string]$cpu.NumberOfLogicalProcessors))
        }
    } catch {}
    try { $lines.Add(('GPU: ' + (Get-GpuNameFast))) } catch {}
    try {
        $total = [long][RustSuite.Native]::MemTotalMb()
        $free  = [long][RustSuite.Native]::MemFreeMb()
        if ($total -gt 0) { $lines.Add(('ОЗУ: {0:N0} МБ всего, {1:N0} МБ свободно' -f $total, $free)) }
    } catch {}
    try {
        $lines.Add('Права: ' + $(if ($script:IsAdmin) { 'администратор' } else { 'обычный пользователь' }))
        $lines.Add('Steam: ' + $(if ($script:SteamPath) { [string]$script:SteamPath } else { 'не найден' }))
        $lines.Add('RUST: ' + $(if ($script:RustExe) { [string]$script:RustExe } else { 'не найден' }))
    } catch {}
    $txt = ($lines -join "`r`n")
    $script:SysReportCache = $txt
    return $txt
}

function Update-SettingsMonitor {
    $barCpu = $script:SetCpuBar
    $valCpu = $script:SetValCpu
    $barRam = $script:SetRamBar
    $valRam = $script:SetValRam
    try {
        if ($barCpu -and -not $barCpu.IsDisposed) {
            $cpu = Get-CpuLoadFast
            if ($cpu -ge 0) {
                $barCpu.Value = $cpu
                if ($valCpu -and -not $valCpu.IsDisposed) {
                    $valCpu.Text = ('{0} %' -f $cpu)
                    $valCpu.ForeColor = if ($cpu -ge 85) { [RustSuite.Theme]::Err }
                                        elseif ($cpu -ge 60) { [RustSuite.Theme]::Warn }
                                        else { [RustSuite.Theme]::TextC }
                }
            } elseif ($valCpu -and -not $valCpu.IsDisposed) {
                $valCpu.Text = 'н/д'
            }
        }
    } catch {}

    try {
        if ($barRam -and -not $barRam.IsDisposed) {
            $ram = Get-RamLoadFast
            $totalMb = 0
            try { $totalMb = [long][RustSuite.Native]::MemTotalMb() } catch {}
            if ($ram -ge 0) {
                $barRam.Value = $ram
                if ($valRam -and -not $valRam.IsDisposed) {
                    if ($totalMb -gt 0) { $valRam.Text = ('{0} % · {1:N0} МБ' -f $ram, $totalMb) }
                    else { $valRam.Text = ('{0} %' -f $ram) }
                    $valRam.ForeColor = if ($ram -ge 90) { [RustSuite.Theme]::Err }
                                        elseif ($ram -ge 75) { [RustSuite.Theme]::Warn }
                                        else { [RustSuite.Theme]::TextC }
                }
            } elseif ($valRam -and -not $valRam.IsDisposed) {
                $valRam.Text = 'н/д'
            }
        }
    } catch {}
}

function Read-SettingsTemps {
    $lines = New-Object System.Collections.Generic.List[string]
    try {
        $cpu = Get-CpuLoadFast
        if ($cpu -ge 0) { $lines.Add(('CPU: загрузка {0} %' -f $cpu)) }
    } catch {}
    try {
        $ram = Get-RamLoadFast
        $freeMb  = [long][RustSuite.Native]::MemFreeMb()
        $totalMb = [long][RustSuite.Native]::MemTotalMb()
        if ($ram -ge 0) {
            if ($totalMb -gt 0) { $lines.Add(('ОЗУ: {0:N0} МБ свободно / {1:N0} МБ всего ({2} %)' -f $freeMb, $totalMb, $ram)) }
            else { $lines.Add(('ОЗУ: загрузка {0} %' -f $ram)) }
        }
    } catch {}
    try {
        $acpi = Get-AcpiTemp
        if ($null -ne $acpi) { $lines.Add(('Температура (ACPI): {0} °C' -f $acpi)) }
        else { $lines.Add('Температура (ACPI): датчик недоступен') }
    } catch {
        $lines.Add('Температура (ACPI): датчик недоступен')
    }
    try { $lines.Add(('GPU: ' + (Get-GpuNameFast))) } catch {}
    $lines.Add('')
    $lines.Add('Примечание: Windows не отдаёт температуру ядер CPU/GPU')
    $lines.Add('без фирменного драйвера. ACPI-датчик есть не на всех ПК.')
    return ($lines -join "`r`n")
}

# ---------- Панель настроек ----------
function Show-SettingsPanel {
    $w = Get-RowWidth 22
    if ($w -lt (S 340)) { $w = (S 340) }

    # Заголовок
    $accentBar = New-Object System.Windows.Forms.Panel
    $accentBar.BackColor = [RustSuite.Theme]::Accent
    $accentBar.Bounds    = New-Object System.Drawing.Rectangle 0, (S 5), (S 3), (S 15)
    $script:RowHost.Controls.Add($accentBar)

    $head = New-Object System.Windows.Forms.Label
    $head.Text      = 'НАСТРОЙКИ · ТЕМЫ И МОНИТОРИНГ'
    $head.Font      = [RustSuite.Theme]::FHead
    $head.ForeColor = [RustSuite.Theme]::TextC
    $head.BackColor = [System.Drawing.Color]::Transparent
    $head.AutoSize  = $false
    $head.Bounds    = New-Object System.Drawing.Rectangle (S 12), (S 2), (S 460), (S 22)
    $script:RowHost.Controls.Add($head)

    # --- Темы ---
    $lblTheme = New-Object System.Windows.Forms.Label
    $lblTheme.Text      = 'ТЕМА ОФОРМЛЕНИЯ · применяется сразу'
    $lblTheme.Font      = [RustSuite.Theme]::FHead
    $lblTheme.ForeColor = [RustSuite.Theme]::Muted
    $lblTheme.BackColor = [System.Drawing.Color]::Transparent
    $lblTheme.AutoSize  = $false
    $lblTheme.Bounds    = New-Object System.Drawing.Rectangle 0, (S 30), $w, (S 16)
    $script:RowHost.Controls.Add($lblTheme)

    $btnY = S 52
    $tileH = S 64
    $gap  = S 8
    $colW = [int](($w - $gap) / 2)
    $idx  = 0
    foreach ($t in $script:Themes) {
        $rx = if ($idx % 2 -eq 0) { 0 } else { $colW + $gap }
        $ry = $btnY + [int]([Math]::Floor($idx / 2) * ($tileH + $gap))

        $tile = New-Object RustSuite.ThemeTile
        $tile.Title    = [string]$t.Name
        $tile.Sub      = 'анимированный градиент'
        $tile.ColorA   = $t.Bg
        $tile.ColorB   = $t.Accent
        $tile.ColorC   = $t.Secondary
        $tile.Selected = ($t.Name -eq $script:ThemeName)
        $tile.Bounds   = New-Object System.Drawing.Rectangle $rx, $ry, $colW, $tileH
        $tile.Tag      = $t
        $tile.Add_Click({
            param($s, $e)
            $th = $s.Tag
            Apply-Theme $th.Name -Save
            Update-ThemeSurfaces
            Write-Log ('Тема изменена: ' + $th.Name) 'ok'
            Set-Status ('Тема: ' + $th.Name) '#8B949E'
            Restart-SettingsSoon
        })
        $script:RowHost.Controls.Add($tile)
        $idx++
    }

    $y = $btnY + [int]([Math]::Ceiling($idx / 2) * ($tileH + $gap)) + (S 10)

    $btnRandom = New-Object RustSuite.FlatButton
    $btnRandom.Style  = 'Ghost'
    $btnRandom.Text   = '✦  СЛУЧАЙНАЯ ТЕМА'
    $btnRandom.Font   = [RustSuite.Theme]::FSmall
    $btnRandom.Bounds = New-Object System.Drawing.Rectangle 0, $y, $w, (S 32)
    $btnRandom.Add_Click({
        $pool = @($script:Themes | Where-Object { $_.Name -ne $script:ThemeName })
        if ($pool.Count -gt 0) {
            $th = $pool | Get-Random
            Apply-Theme $th.Name -Save
            Update-ThemeSurfaces
            Write-Log ('Случайная тема: ' + $th.Name) 'ok'
            Set-Status ('Тема: ' + $th.Name) '#8B949E'
            Restart-SettingsSoon
        }
    })
    $script:RowHost.Controls.Add($btnRandom)
    $y += S 44

    # --- Система ---
    $lblSys = New-Object System.Windows.Forms.Label
    $lblSys.Text      = 'СИСТЕМА · этот компьютер'
    $lblSys.Font      = [RustSuite.Theme]::FHead
    $lblSys.ForeColor = [RustSuite.Theme]::Muted
    $lblSys.BackColor = [System.Drawing.Color]::Transparent
    $lblSys.AutoSize  = $false
    $lblSys.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 16)
    $script:RowHost.Controls.Add($lblSys)
    $y += S 22

    $sysBox = New-Object System.Windows.Forms.TextBox
    $sysBox.Multiline   = $true
    $sysBox.ReadOnly    = $true
    $sysBox.ScrollBars  = 'Vertical'
    $sysBox.BorderStyle = 'FixedSingle'
    $sysBox.BackColor   = [RustSuite.Theme]::Field
    $sysBox.ForeColor   = [RustSuite.Theme]::TextC
    $sysBox.Font        = [RustSuite.Theme]::FMono
    $sysBox.Bounds      = New-Object System.Drawing.Rectangle 0, $y, $w, (S 112)
    $sysBox.Anchor      = 'Top,Left,Right'
    $sysBox.Text        = Get-SystemReport
    $script:RowHost.Controls.Add($sysBox)
    $y += S 120

    $btnCopySys = New-Object RustSuite.FlatButton
    $btnCopySys.Style  = 'Ghost'
    $btnCopySys.Text   = 'СКОПИРОВАТЬ ОТЧЁТ О СИСТЕМЕ'
    $btnCopySys.Font   = [RustSuite.Theme]::FSmall
    $btnCopySys.Bounds = New-Object System.Drawing.Rectangle 0, $y, $w, (S 32)
    $btnCopySys.Tag    = $sysBox
    $btnCopySys.Add_Click({
        param($s, $e)
        if ($s.Tag -and (Copy-Text $s.Tag.Text)) {
            Set-Status 'Отчёт о системе скопирован' '#4ECB71'
            Write-Log 'Отчёт о системе скопирован в буфер обмена' 'ok'
        }
    })
    $script:RowHost.Controls.Add($btnCopySys)
    $y += S 44

    $halfW = [int](($w - (S 8)) / 2)
    $btnData = New-Object RustSuite.FlatButton
    $btnData.Style  = 'Ghost'
    $btnData.Text   = 'ПАПКА ДАННЫХ'
    $btnData.Font   = [RustSuite.Theme]::FSmall
    $btnData.Bounds = New-Object System.Drawing.Rectangle 0, $y, $halfW, (S 30)
    $btnData.Add_Click({ Open-Explorer $script:Root })
    $script:RowHost.Controls.Add($btnData)

    $btnLog = New-Object RustSuite.FlatButton
    $btnLog.Style  = 'Ghost'
    $btnLog.Text   = 'ОТКРЫТЬ ЖУРНАЛ'
    $btnLog.Font   = [RustSuite.Theme]::FSmall
    $btnLog.Bounds = New-Object System.Drawing.Rectangle ($halfW + (S 8)), $y, ($w - $halfW - (S 8)), (S 30)
    $btnLog.Add_Click({
        if (Test-Path -LiteralPath $script:LogFile) { Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + $script:LogFile + '"') | Out-Null }
        else { Write-Log 'Журнал ещё не создан' 'info' }
    })
    $script:RowHost.Controls.Add($btnLog)
    $y += S 42

    # --- Поведение ---
    $lblBeh = New-Object System.Windows.Forms.Label
    $lblBeh.Text      = 'ПОВЕДЕНИЕ'
    $lblBeh.Font      = [RustSuite.Theme]::FHead
    $lblBeh.ForeColor = [RustSuite.Theme]::Muted
    $lblBeh.BackColor = [System.Drawing.Color]::Transparent
    $lblBeh.AutoSize  = $false
    $lblBeh.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 16)
    $script:RowHost.Controls.Add($lblBeh)
    $y += S 22

    $chkAutoClose = New-Object System.Windows.Forms.CheckBox
    $chkAutoClose.Text      = 'Закрывать оптимизатор после запуска RUST'
    $chkAutoClose.Font      = [RustSuite.Theme]::FSub
    $chkAutoClose.ForeColor = [RustSuite.Theme]::TextC
    $chkAutoClose.BackColor = [System.Drawing.Color]::Transparent
    $chkAutoClose.FlatStyle = 'Flat'
    $chkAutoClose.AutoSize  = $false
    $chkAutoClose.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 24)
    $chkAutoClose.Checked   = [bool]$script:AutoClose
    $chkAutoClose.Add_CheckedChanged({
        param($s, $e)
        $script:AutoClose = [bool]$s.Checked
        $script:State['AutoClose'] = $script:AutoClose
        Save-State
        Set-Status $(if ($script:AutoClose) { 'Автозакрытие после запуска RUST включено' } else { 'Автозакрытие отключено' }) '#8B949E'
    })
    $script:RowHost.Controls.Add($chkAutoClose)
    $y += S 28

    $lblBehHint = New-Object System.Windows.Forms.Label
    $lblBehHint.Text      = 'После нажатия «ЗАПУСТИТЬ RUST» программа дождётся RustClient.exe и закроется сама.'
    $lblBehHint.Font      = [RustSuite.Theme]::FSmall
    $lblBehHint.ForeColor = [RustSuite.Theme]::Muted
    $lblBehHint.BackColor = [System.Drawing.Color]::Transparent
    $lblBehHint.AutoSize  = $false
    $lblBehHint.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 30)
    $script:RowHost.Controls.Add($lblBehHint)
    $y += S 42

    $btnShortcut = New-Object RustSuite.FlatButton
    $btnShortcut.Style  = 'Ghost'
    $btnShortcut.Text   = 'СОЗДАТЬ ЯРЛЫК НА РАБОЧЕМ СТОЛЕ'
    $btnShortcut.Font   = [RustSuite.Theme]::FSmall
    $btnShortcut.Bounds = New-Object System.Drawing.Rectangle 0, $y, $w, (S 30)
    $btnShortcut.Add_Click({
        $lnk = Install-AppShortcut -Force
        if ($lnk) {
            $script:ShortcutPath = $lnk
            Set-Status 'Ярлык обновлён на рабочем столе' '#4ECB71'
            Write-Log ('Ярлык создан: ' + $lnk) 'ok'
        } else {
            Set-Status 'Не удалось создать ярлык' '#FF6B62'
            Write-Log 'Не удалось создать ярлык (нет лаунчера или иконки)' 'warn'
        }
    })
    $script:RowHost.Controls.Add($btnShortcut)
    $y += S 42

    # --- Мониторинг ---
    $lblMon = New-Object System.Windows.Forms.Label
    $lblMon.Text      = 'МОНИТОРИНГ · обновляется автоматически'
    $lblMon.Font      = [RustSuite.Theme]::FHead
    $lblMon.ForeColor = [RustSuite.Theme]::Muted
    $lblMon.BackColor = [System.Drawing.Color]::Transparent
    $lblMon.AutoSize  = $false
    $lblMon.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 16)
    $script:RowHost.Controls.Add($lblMon)
    $y += S 24

    $lblCpu = New-Object System.Windows.Forms.Label
    $lblCpu.Text      = 'ЗАГРУЗКА CPU'
    $lblCpu.Font      = [RustSuite.Theme]::FSmall
    $lblCpu.ForeColor = [RustSuite.Theme]::Muted
    $lblCpu.BackColor = [System.Drawing.Color]::Transparent
    $lblCpu.AutoSize  = $false
    $lblCpu.Bounds    = New-Object System.Drawing.Rectangle 0, $y, ([int]($w * 0.62)), (S 16)
    $script:RowHost.Controls.Add($lblCpu)

    $valCpu = New-Object System.Windows.Forms.Label
    $valCpu.Text      = '—'
    $valCpu.Font      = [RustSuite.Theme]::FSmall
    $valCpu.ForeColor = [RustSuite.Theme]::TextC
    $valCpu.BackColor = [System.Drawing.Color]::Transparent
    $valCpu.AutoSize  = $false
    $valCpu.TextAlign = 'MiddleRight'
    $valCpu.Bounds    = New-Object System.Drawing.Rectangle ([int]($w * 0.62)), $y, ([int]($w * 0.38)), (S 16)
    $script:RowHost.Controls.Add($valCpu)
    $y += S 20

    $barCpu = New-Object RustSuite.ProgressStrip
    $barCpu.Shimmer = $true
    $barCpu.Value   = 0
    $barCpu.Bounds  = New-Object System.Drawing.Rectangle 0, $y, $w, (S 10)
    $barCpu.BackColor = [System.Drawing.Color]::Transparent
    $script:RowHost.Controls.Add($barCpu)
    $y += S 22

    $lblRam = New-Object System.Windows.Forms.Label
    $lblRam.Text      = 'ЗАГРУЗКА ОЗУ'
    $lblRam.Font      = [RustSuite.Theme]::FSmall
    $lblRam.ForeColor = [RustSuite.Theme]::Muted
    $lblRam.BackColor = [System.Drawing.Color]::Transparent
    $lblRam.AutoSize  = $false
    $lblRam.Bounds    = New-Object System.Drawing.Rectangle 0, $y, ([int]($w * 0.62)), (S 16)
    $script:RowHost.Controls.Add($lblRam)

    $valRam = New-Object System.Windows.Forms.Label
    $valRam.Text      = '—'
    $valRam.Font      = [RustSuite.Theme]::FSmall
    $valRam.ForeColor = [RustSuite.Theme]::TextC
    $valRam.BackColor = [System.Drawing.Color]::Transparent
    $valRam.AutoSize  = $false
    $valRam.TextAlign = 'MiddleRight'
    $valRam.Bounds    = New-Object System.Drawing.Rectangle ([int]($w * 0.62)), $y, ([int]($w * 0.38)), (S 16)
    $script:RowHost.Controls.Add($valRam)
    $y += S 20

    $barRam = New-Object RustSuite.ProgressStrip
    $barRam.Shimmer = $true
    $barRam.Value   = 0
    $barRam.Bounds  = New-Object System.Drawing.Rectangle 0, $y, $w, (S 10)
    $barRam.BackColor = [System.Drawing.Color]::Transparent
    $script:RowHost.Controls.Add($barRam)
    $y += S 28

    $lblTemps = New-Object System.Windows.Forms.Label
    $lblTemps.Text      = 'ДАТЧИКИ И ОБОРУДОВАНИЕ'
    $lblTemps.Font      = [RustSuite.Theme]::FHead
    $lblTemps.ForeColor = [RustSuite.Theme]::Muted
    $lblTemps.BackColor = [System.Drawing.Color]::Transparent
    $lblTemps.AutoSize  = $false
    $lblTemps.Bounds    = New-Object System.Drawing.Rectangle 0, $y, $w, (S 16)
    $script:RowHost.Controls.Add($lblTemps)
    $y += S 22

    $tempBox = New-Object System.Windows.Forms.TextBox
    $tempBox.Multiline    = $true
    $tempBox.ReadOnly     = $true
    $tempBox.ScrollBars   = 'Vertical'
    $tempBox.BorderStyle  = 'FixedSingle'
    $tempBox.BackColor    = [RustSuite.Theme]::Field
    $tempBox.ForeColor    = [RustSuite.Theme]::TextC
    $tempBox.Font         = [RustSuite.Theme]::FMono
    $tempBox.Bounds       = New-Object System.Drawing.Rectangle 0, $y, $w, (S 150)
    $tempBox.Anchor       = 'Top,Left,Right'
    $script:RowHost.Controls.Add($tempBox)
    $y += S 162

    $btnRefresh = New-Object RustSuite.FlatButton
    $btnRefresh.Style  = 'Ghost'
    $btnRefresh.Text   = 'ОБНОВИТЬ ПОКАЗАНИЯ'
    $btnRefresh.Font   = [RustSuite.Theme]::FSmall
    $btnRefresh.Bounds = New-Object System.Drawing.Rectangle 0, $y, $w, (S 34)
    $script:RowHost.Controls.Add($btnRefresh)
    $y += S 46

    # Ссылки для функций обновления (см. ниже, уровень скрипта).
    $script:SetCpuBar   = $barCpu
    $script:SetRamBar   = $barRam
    $script:SetValCpu   = $valCpu
    $script:SetValRam   = $valRam
    $script:SetTempBox  = $tempBox

    Update-SettingsMonitor
    $tempBox.Text = Read-SettingsTemps

    $tick = 0
    try {
        if ($script:TempTimer) { $script:TempTimer.Stop(); $script:TempTimer.Dispose() }
    } catch {}
    $script:TempTimer = New-Object System.Windows.Forms.Timer
    $script:TempTimer.Interval = 1000
    $script:TempTimer.Add_Tick({
        try {
            if (-not $script:SetTempBox -or $script:SetTempBox.IsDisposed) { $script:TempTimer.Stop(); return }
            Update-SettingsMonitor
            $script:TempTick = [int]$script:TempTick + 1
            if ($script:TempTick -ge 5) {
                $script:TempTick = 0
                $script:SetTempBox.Text = Read-SettingsTemps
            }
        } catch {}
    })
    $script:TempTick = 0
    $script:TempTimer.Start()

    $btnRefresh.Add_Click({
        try {
            Update-SettingsMonitor
            $script:SetTempBox.Text = Read-SettingsTemps
        } catch {}
    })

    $script:RowHost.AutoScrollMinSize = New-Object System.Drawing.Size 0, ($y + (S 10))
}

$form.Add_FormClosing({
    param($s, $e)
    try { if ($script:TempTimer) { $script:TempTimer.Stop(); $script:TempTimer.Dispose() } } catch {}
    try { if ($script:ThemeTimer) { $script:ThemeTimer.Stop(); $script:ThemeTimer.Dispose() } } catch {}
})
