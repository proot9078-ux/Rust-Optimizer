# ============================================================
#  КАРТИНКА RUST: безопасные пресеты, гамма и панель GPU
#  Никаких оверлеев, Freestyle, ReShade и внедрения в игру.
# ============================================================

$script:GpuInfo      = $null
$script:GpuInfoAt    = [datetime]::MinValue
$script:LookPreset   = 'vivid'
$script:LookTiles    = @{}
$script:GammaDir     = Join-Path $script:Root 'gamma'
try { New-Item -ItemType Directory -Force -Path $script:GammaDir | Out-Null } catch {}

$script:LookPresets = @(
    [pscustomobject]@{ Key = 'vivid';  Name = 'BLOGGER VIVID'; Sub = 'сочный · чистый · яркий'; Contrast = 1.10; Gamma = 0.95; Brightness = 1.010
        Desc = 'Высокая детализация, мягкий контраст и лёгкий подъём теней. Без «мыла», блума и god rays.' }
    [pscustomobject]@{ Key = 'cinema'; Name = 'КИНО';          Sub = 'тёплый · объёмный · свет'; Contrast = 1.14; Gamma = 1.00; Brightness = 1.000
        Desc = 'Богатый свет, лучи и объём облаков. Красиво для скриншотов и видео, чуть дороже по FPS.' }
    [pscustomobject]@{ Key = 'night';  Name = 'НОЧЬ';          Sub = 'видно · чисто · без бликов'; Contrast = 1.04; Gamma = 0.88; Brightness = 1.015
        Desc = 'Поднимает тёмные участки и убирает световые блики. Помогает видеть силуэты ночью.' }
)

$savedLook = [string]$script:State['LookPreset']
if ($savedLook -and @($script:LookPresets | Where-Object { $_.Key -eq $savedLook }).Count -gt 0) {
    $script:LookPreset = $savedLook
}

function Get-LookPreset {
    param([string]$Key)
    if (-not $Key) { $Key = 'vivid' }
    $p = @($script:LookPresets | Where-Object { $_.Key -eq $Key } | Select-Object -First 1)
    if ($p.Count -eq 0) { $p = @($script:LookPresets | Select-Object -First 1) }
    return $p[0]
}

function Get-LookPresetName {
    param([string]$Key)
    $p = Get-LookPreset $Key
    return [string]$p.Name
}

function New-NeutralRamp {
    $out = New-Object 'UInt16[]' 768
    for ($c = 0; $c -lt 3; $c++) {
        for ($i = 0; $i -lt 256; $i++) {
            $out[($c * 256) + $i] = [UInt16]([Math]::Round(($i / 255.0) * 65535.0))
        }
    }
    return ,$out
}

function New-LookRamp {
    param([UInt16[]]$BaseRamp, [string]$Key)
    $p = Get-LookPreset $Key
    $haveBase = ($BaseRamp -and $BaseRamp.Length -eq 768)
    $out = New-Object 'UInt16[]' 768
    for ($c = 0; $c -lt 3; $c++) {
        for ($i = 0; $i -lt 256; $i++) {
            if ($haveBase) { $v = [double]$BaseRamp[($c * 256) + $i] / 65535.0 }
            else { $v = [double]$i / 255.0 }
            if ($v -lt 0) { $v = 0 } elseif ($v -gt 1) { $v = 1 }

            # Сначала гамма, затем мягкий контраст вокруг середины.
            $v = [Math]::Pow($v, [double]$p.Gamma)
            $v = (($v - 0.5) * [double]$p.Contrast) + 0.5
            $v = $v * [double]$p.Brightness
            if ($v -lt 0) { $v = 0 } elseif ($v -gt 1) { $v = 1 }
            $out[($c * 256) + $i] = [UInt16]([Math]::Round($v * 65535.0))
        }
    }
    return ,$out
}

function Test-RampClose {
    param([UInt16[]]$A, [UInt16[]]$B, [int]$Tolerance = 1024)
    if ($null -eq $A -or $null -eq $B) { return $false }
    if ($A.Length -ne 768 -or $B.Length -ne 768) { return $false }
    for ($i = 0; $i -lt 768; $i++) {
        if ([Math]::Abs([int]$A[$i] - [int]$B[$i]) -gt $Tolerance) { return $false }
    }
    return $true
}

function Get-GammaBackupFile {
    return (Join-Path $script:GammaDir 'primary-original.bin')
}

function Save-GammaBackup {
    param([UInt16[]]$Ramp)
    if ($null -eq $Ramp -or $Ramp.Length -ne 768) { return $false }
    $file = Get-GammaBackupFile
    $bytes = New-Object byte[] 1536
    [System.Buffer]::BlockCopy($Ramp, 0, $bytes, 0, 1536)
    try {
        [IO.File]::WriteAllBytes($file, $bytes)
        return $true
    } catch { return $false }
}

function Read-GammaBackup {
    $file = Get-GammaBackupFile
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    try {
        $bytes = [IO.File]::ReadAllBytes($file)
        if ($bytes.Length -ne 1536) { return $null }
        $ramp = New-Object 'UInt16[]' 768
        [System.Buffer]::BlockCopy($bytes, 0, $ramp, 0, 1536)
        return ,$ramp
    } catch { return $null }
}

function Get-GammaStatus {
    $support = $false
    $current = $null
    try {
        $current = [RustSuite.Native]::GammaGet()
        $support = ($null -ne $current -and $current.Length -eq 768)
    } catch {}
    $backup = Read-GammaBackup
    $active = $false
    $presetKey = [string]$script:State['GammaPreset']
    if ($support -and $backup -and $presetKey) {
        try {
            $expected = New-LookRamp $backup $presetKey
            $active = Test-RampClose $current $expected 2048
        } catch {}
    }
    return [pscustomobject]@{
        Supported = $support
        Active    = $active
        PresetKey = $presetKey
        Preset    = $(if ($presetKey) { Get-LookPresetName $presetKey } else { '—' })
        Backup    = (Test-Path -LiteralPath (Get-GammaBackupFile))
    }
}

function Apply-LookPreset {
    param([string]$Key)
    $p = Get-LookPreset $Key
    $current = $null
    try { $current = [RustSuite.Native]::GammaGet() } catch {}
    if ($null -eq $current -or $current.Length -ne 768) {
        return [pscustomobject]@{ Ok = $false; Message = 'Драйвер не отдал гамма-таблицу. Используйте панель NVIDIA/AMD — она работает на уровне драйвера.' }
    }

    $original = Read-GammaBackup
    if ($null -eq $original) {
        if (-not (Save-GammaBackup $current)) {
            return [pscustomobject]@{ Ok = $false; Message = 'Не удалось сохранить исходный цветовой профиль. Изменения не применены.' }
        }
        $original = $current
    }

    $ramp = New-LookRamp $original $p.Key
    $ok = $false
    try { $ok = [RustSuite.Native]::GammaSet($ramp) } catch {}
    if (-not $ok) {
        return [pscustomobject]@{ Ok = $false; Message = 'Windows/драйвер отклонил изменение гаммы (часто бывает на HDR-мониторах и в удалённом сеансе). Настройте цвет в панели NVIDIA/AMD.' }
    }

    $now = $null
    try { $now = [RustSuite.Native]::GammaGet() } catch {}
    if ($null -eq $now -or -not (Test-RampClose $now $ramp 4096)) {
        return [pscustomobject]@{ Ok = $false; Message = 'Драйвер принял команду, но не применил её. Используйте панель NVIDIA/AMD.' }
    }

    $script:State['GammaActive'] = $true
    $script:State['GammaPreset'] = $p.Key
    $script:State['GammaAt'] = (Get-Date).ToString('s')
    Save-State
    Write-Log ('Картинка: применён пресет «' + $p.Name + '» (гамма/контраст, обратимо)') 'ok'
    return [pscustomobject]@{ Ok = $true; Message = ('Применено: ' + $p.Name + '. Вернуть исходный цвет — кнопкой «ВЕРНУТЬ ЦВЕТ».') }
}

function Restore-LookGamma {
    $backup = Read-GammaBackup
    if ($null -eq $backup) {
        return [pscustomobject]@{
            Ok = $false
            Message = 'Исходная таблица не найдена: пресет ещё не применялся. Цвет не изменён — перезагрузка Windows тоже возвращает стандартную гамму.'
        }
    }
    $ok = $false
    try { $ok = [RustSuite.Native]::GammaSet($backup) } catch {}
    if (-not $ok) {
        return [pscustomobject]@{ Ok = $false; Message = 'Не удалось вернуть исходный цвет. Перезапустите Windows — гамма сбросится автоматически.' }
    }
    $script:State['GammaActive'] = $false
    $script:State.Remove('GammaPreset')
    $script:State.Remove('GammaAt')
    Save-State
    Write-Log 'Картинка: исходный цвет рабочего стола восстановлен' 'ok'
    return [pscustomobject]@{ Ok = $true; Message = 'Исходный цвет восстановлен.' }
}

# ============================================================
#  RUST: визуальные cfg-пресеты (только официальные конвары)
# ============================================================
$script:RustVisualBaseLines = @(
    'graphics.drawdistance 2500',
    'graphics.lodbias 2',
    'graphics.hlod True',
    'graphics.parallax 2',
    'graphics.af 16',
    'graphics.contactshadows True',
    'graphics.dof False',
    'graphics.shadowmode 4',
    'graphics.shadowlights 3',
    'graphics.aggressiveshadowlod False',
    'graphics.aggressiveshadowlodwearable False',
    'graphics.impostorshadows True',
    'graphics.volumetric_clouds 4',
    'graphics.renderscale 1',
    'graphics.maxqueuedframes 1',
    'graphicssettings.globaltexturemipmaplimit 0',
    'graphicssettings.shadowqualitypreset 3',
    'graphicssettings.enablelodcrossfade True',
    'graphicssettings.softparticles True',
    'graphicssettings.particleraycastbudget 1024',
    'effects.antialiasing 2',
    'effects.ao True',
    'effects.bloom True',
    'effects.lensdirt False',
    'effects.motionblur False',
    'effects.shafts True',
    'effects.sharpen True',
    'effects.vignet False',
    'effects.hurtoverlay False',
    'effects.otherplayerslightflares False',
    'effects.creationeffects True',
    'effects.maxgibs 1',
    'particle.quality 100',
    'grass.quality 100',
    'grass.distance 100',
    'grass.displacement True',
    'decor.quality 100',
    'terrain.quality 100',
    'tree.quality 200',
    'tree.meshes 100',
    'mesh.quality 200',
    'water.quality 2',
    'water.reflections 2',
    'sss.enabled True',
    'reflection.planarreflections False',
    'legs.enablelegs True',
    'player.footik True',
    'ui.showinventoryplayer True'
)

$script:RustVisualExtras = @{
    vivid  = @('effects.bloom False', 'effects.shafts False', 'effects.sharpen True', 'effects.antialiasing 2', 'effects.vignet False', 'graphics.dof False')
    cinema = @('effects.bloom True',  'effects.shafts True',  'effects.sharpen True', 'effects.antialiasing 2', 'effects.vignet False', 'graphics.dof False')
    night  = @('effects.bloom False', 'effects.shafts False', 'effects.sharpen True', 'effects.antialiasing 2', 'effects.vignet False', 'graphics.volumetric_clouds 0', 'graphics.dof False')
}

$script:RustVisualManaged = @(
    foreach ($l in $script:RustVisualBaseLines) { (($l -split '\s+')[0]).ToLower() }
    foreach ($group in $script:RustVisualExtras.Values) {
        foreach ($l in $group) { (($l -split '\s+')[0]).ToLower() }
    }
) | Select-Object -Unique

function Get-RustVisualPresetLines {
    param([string]$Key)
    if (-not $Key -or -not $script:RustVisualExtras.ContainsKey($Key)) { $Key = 'vivid' }
    $map = @{}
    foreach ($l in $script:RustVisualBaseLines) {
        $k = (($l -split '\s+')[0]).ToLower()
        $map[$k] = $l
    }
    foreach ($l in @($script:RustVisualExtras[$Key])) {
        $k = (($l -split '\s+')[0]).ToLower()
        $map[$k] = $l
    }
    return @($map.Values | Sort-Object)
}

function Get-VisualSnapshotFile {
    return (Join-Path $script:RustBackup 'client-picture-original.txt')
}

function Save-VisualSnapshot {
    param([string]$Path)
    $snap = Get-VisualSnapshotFile
    if (Test-Path -LiteralPath $snap) { return $true }
    $map = @{}
    if (Test-Path -LiteralPath $Path) {
        try {
            foreach ($ln in @([IO.File]::ReadAllLines($Path))) {
                $t = ([string]$ln).Trim()
                if (-not $t) { continue }
                $k = (($t -split '\s+')[0]).ToLower()
                if ($script:RustVisualManaged -contains $k) { $map[$k] = $t }
            }
        } catch {}
    }
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($k in @($script:RustVisualManaged)) {
        $v = ''
        if ($map.ContainsKey($k)) { $v = [string]$map[$k] }
        $lines.Add($k + "`t" + $v)
    }
    try {
        [IO.File]::WriteAllLines($snap, $lines, (New-Object System.Text.UTF8Encoding($false)))
        return $true
    } catch { return $false }
}

function Restore-VisualSnapshot {
    param([string]$Path)
    $snap = Get-VisualSnapshotFile
    if (-not (Test-Path -LiteralPath $snap)) { return $false }
    $restore = @()
    try {
        foreach ($ln in @([IO.File]::ReadAllLines($snap))) {
            $idx = ([string]$ln).IndexOf("`t")
            if ($idx -lt 0) { continue }
            $v = ([string]$ln).Substring($idx + 1)
            if ($v.Trim().Length -gt 0) { $restore += $v }
        }
        Merge-CfgFile -Path $Path -Lines $restore -ManagedKeys $script:RustVisualManaged
        Remove-Item -LiteralPath $snap -Force -ErrorAction SilentlyContinue
        return $true
    } catch { return $false }
}

function Set-RustVisualCfg {
    param([string]$Key)
    if (-not $script:RustExe) {
        return [pscustomobject]@{ Ok = $false; Message = 'RUST не найден. Запустите игру через Steam один раз, чтобы появилась папка cfg.' }
    }
    if (Test-RustRunning) {
        return [pscustomobject]@{ Ok = $false; Message = 'Rust запущен: игра перезапишет client.cfg при выходе. Закройте игру и повторите.' }
    }
    $dir = Get-RustCfgDir
    if (-not $dir) { return [pscustomobject]@{ Ok = $false; Message = 'Не удалось открыть папку cfg игры.' } }
    $file = Join-Path $dir 'client.cfg'
    if (-not (Save-VisualSnapshot $file)) {
        return [pscustomobject]@{ Ok = $false; Message = 'Не удалось сохранить исходные значения client.cfg. Изменения не применены.' }
    }
    Backup-FileStamp $file 'client-picture'
    $lines = @(Get-RustVisualPresetLines $Key)
    Merge-CfgFile -Path $file -Lines $lines -ManagedKeys $script:RustVisualManaged
    $p = Get-LookPreset $Key
    $script:State['RustVisualPreset'] = $p.Key
    $script:State['RustVisualAt'] = (Get-Date).ToString('s')
    Save-State
    Write-Log ('RUST: записан визуальный пресет «' + $p.Name + '» (' + $lines.Count + ' конваров, client.cfg)') 'ok'
    return [pscustomobject]@{ Ok = $true; Message = ('client.cfg обновлён: ' + $p.Name + '. Бэкап: ' + $script:RustBackup) }
}

function Undo-RustVisualCfg {
    if (-not $script:RustExe) { return [pscustomobject]@{ Ok = $false; Message = 'RUST не найден.' } }
    if (Test-RustRunning) { return [pscustomobject]@{ Ok = $false; Message = 'Rust запущен. Закройте игру и повторите.' } }
    $dir = Get-RustCfgDir
    if (-not $dir) { return [pscustomobject]@{ Ok = $false; Message = 'Папка cfg недоступна.' } }
    $file = Join-Path $dir 'client.cfg'
    if (Restore-VisualSnapshot $file) {
        Write-Log 'RUST: исходные значения визуальных конваров восстановлены' 'ok'
        return [pscustomobject]@{ Ok = $true; Message = 'Исходные значения client.cfg восстановлены.' }
    }
    return [pscustomobject]@{ Ok = $false; Message = 'Резервная копия визуальных настроек не найдена.' }
}

# ============================================================
#  GPU: определение, подсказки и запуск панели
# ============================================================
function Get-GpuInfo {
    param([switch]$Refresh)
    $now = Get-Date
    if (-not $Refresh -and $script:GpuInfo -and (($now - $script:GpuInfoAt).TotalSeconds -lt 45)) {
        return $script:GpuInfo
    }
    $cards = @()
    try { $cards = @(Get-CimInstance Win32_VideoController -ErrorAction Stop) } catch {}
    $active = @($cards | Where-Object { [int]$_.CurrentHorizontalResolution -gt 0 })
    $primary = if ($active.Count -gt 0) { $active[0] } elseif ($cards.Count -gt 0) { $cards[0] } else { $null }
    $names = @($cards | ForEach-Object { ([string]$_.Name).Trim() } |
               Where-Object { $_ -and $_ -notmatch 'Basic Display|Remote Display|Microsoft Basic' } |
               Select-Object -Unique)
    $allText = ($names -join ' ') + ' ' + [string]$primary.Name + ' ' + [string]$primary.PNPDeviceID
    $vendor = 'OTHER'
    $vendorLabel = 'Видеокарта'
    $panelName = 'Настройки дисплея Windows'
    if ($allText -match 'NVIDIA|GeForce|RTX|GTX|Quadro|VEN_10DE') {
        $vendor = 'NVIDIA'; $vendorLabel = 'NVIDIA'; $panelName = 'NVIDIA Control Panel / NVIDIA app'
    } elseif ($allText -match 'AMD|Radeon|VEN_1002') {
        $vendor = 'AMD'; $vendorLabel = 'AMD Radeon'; $panelName = 'AMD Software: Adrenalin Edition'
    } elseif ($allText -match 'Intel|Arc|UHD|Iris|VEN_8086') {
        $vendor = 'INTEL'; $vendorLabel = 'Intel'; $panelName = 'Intel Graphics Command Center'
    }
    $name = if ($names.Count -gt 0) { $names -join '  ·  ' } else { 'Видеокарта не определена' }
    $res = '—'
    $hz = 0
    if ($primary) {
        $rw = [int]$primary.CurrentHorizontalResolution
        $rh = [int]$primary.CurrentVerticalResolution
        $hz = [int]$primary.CurrentRefreshRate
        if ($rw -gt 0 -and $rh -gt 0) { $res = "$rw × $rh" }
    }
    $driver = if ($primary) { [string]$primary.DriverVersion } else { '' }
    $vramMb = 0
    if ($primary -and $primary.AdapterRAM) {
        try {
            $v = [double]$primary.AdapterRAM / 1MB
            if ($v -gt 0 -and $v -lt 131072) { $vramMb = [int][Math]::Round($v) }
        } catch {}
    }
    $info = [pscustomobject]@{
        Vendor = $vendor; VendorLabel = $vendorLabel; PanelName = $panelName
        Name = $name; Driver = $driver; Resolution = $res; Refresh = $hz
        VramMb = $vramMb; Cards = $names; Primary = $primary
    }
    $script:GpuInfo = $info
    $script:GpuInfoAt = $now
    return $info
}

function Get-GpuPanelGuide {
    param([string]$Vendor)
    if (-not $Vendor) { $Vendor = (Get-GpuInfo).Vendor }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('ПАНЕЛЬ ДРАЙВЕРА — точные настройки для сочной картинки')
    $lines.Add('')
    if ($Vendor -eq 'NVIDIA') {
        $lines.Add('NVIDIA Control Panel → Дисплей → Регулировка параметров цвета рабочего стола:')
        $lines.Add('  • Цифровая насыщенность (Digital Vibrance): 65–72%')
        $lines.Add('  • Яркость / Контраст / Гамма: 50% / 50% / 1.00')
        $lines.Add('  • Формат цвета: RGB; динамический диапазон: Полный (Full)')
        $lines.Add('  • Глубина цвета: 8 bpc, либо 10 bpc при поддержке монитора')
        $lines.Add('')
        $lines.Add('NVIDIA Control Panel → Управление параметрами 3D → RustClient.exe:')
        $lines.Add('  • Режим низкой задержки: Ultra')
        $lines.Add('  • Управление электропитанием: Предпочтителен максимальный режим')
        $lines.Add('  • Вертикальная синхронизация: Выкл.')
        $lines.Add('  • Фильтрация текстур — качество: Высокое качество')
        $lines.Add('  • Потоковая оптимизация: Вкл. (на слабом CPU можно Выкл.)')
        $lines.Add('  • Max Frame Rate: по частоте монитора или 0 (без лимита)')
        $lines.Add('')
        $lines.Add('НЕ включайте Freestyle / Game Filter: это оверлей, он может конфликтовать с EAC.')
    } elseif ($Vendor -eq 'AMD') {
        $lines.Add('AMD Software: Adrenalin Edition → Игры → Rust:')
        $lines.Add('  • Radeon Image Sharpening: 50–70%')
        $lines.Add('  • Radeon Anti-Lag: Вкл.')
        $lines.Add('  • Radeon Chill: Выкл.')
        $lines.Add('  • Enhanced Sync: Вкл. (если нет мерцания; иначе Выкл.)')
        $lines.Add('  • Frame Rate Target Control: по частоте монитора')
        $lines.Add('')
        $lines.Add('AMD Software → Дисплей → Цвет (Custom Color):')
        $lines.Add('  • Насыщенность (Saturation): 110–115%')
        $lines.Add('  • Цветовая температура: 6500K')
        $lines.Add('  • Яркость / контраст: по комфорту, не выше 55 / 55')
        $lines.Add('  • Формат пикселей: RGB 4:4:4, Full RGB')
        $lines.Add('')
        $lines.Add('Не используйте оверлеи и сторонние шейдеры: только панель драйвера.')
    } elseif ($Vendor -eq 'INTEL') {
        $lines.Add('Intel Graphics Command Center → Дисплей → Цвет:')
        $lines.Add('  • Насыщенность: 110–115%')
        $lines.Add('  • Яркость / контраст: по комфорту')
        $lines.Add('  • Цветовая температура: 6500K')
        $lines.Add('')
        $lines.Add('Для дискретной NVIDIA/AMD в ноутбуке используйте панель соответствующего драйвера.')
    } else {
        $lines.Add('Откройте панель драйвера видеокарты и выставьте:')
        $lines.Add('  • Насыщенность: +10–15%')
        $lines.Add('  • Контраст: +5–10%')
        $lines.Add('  • Гамма: 1.0 (или чуть ниже для светлых теней)')
        $lines.Add('  • Полный динамический диапазон RGB')
    }
    $lines.Add('')
    $lines.Add('После изменений закройте панель — настройки применяются сразу.')
    $lines.Add('Это настройки драйвера, а не игры: файлы Rust и процесс игры не изменяются.')
    return ($lines -join "`r`n")
}

function Open-GpuPanel {
    param([string]$Vendor)
    if (-not $Vendor) { $Vendor = (Get-GpuInfo).Vendor }
    $candidates = @()
    if ($Vendor -eq 'NVIDIA') {
        $candidates += @(
            (Join-Path $env:ProgramFiles 'NVIDIA Corporation\Control Panel Client\nvcplui.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'NVIDIA Corporation\Control Panel Client\nvcplui.exe'),
            (Join-Path $env:ProgramFiles 'NVIDIA Corporation\NVIDIA app\CEF\NVIDIA app.exe'),
            (Join-Path $env:ProgramFiles 'NVIDIA Corporation\NVIDIA app\NVIDIA app.exe')
        )
    } elseif ($Vendor -eq 'AMD') {
        $candidates += @(
            (Join-Path $env:ProgramFiles 'AMD\CNext\CNext\RadeonSoftware.exe'),
            (Join-Path $env:ProgramFiles 'AMD\CNext\CNext\RadeonSoftware.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'AMD\CNext\CNext\RadeonSoftware.exe')
        )
    } elseif ($Vendor -eq 'INTEL') {
        $candidates += @(
            (Join-Path $env:ProgramFiles 'Intel\Intel Graphics Command Center\IntelGraphicsCommandCenter.exe'),
            (Join-Path $env:ProgramFiles 'Intel\Intel Graphics Command Center\Intel Graphics Command Center.exe')
        )
    }
    foreach ($c in @($candidates | Where-Object { $_ })) {
        if (Test-Path -LiteralPath $c) {
            try {
                Start-Process -FilePath $c -ErrorAction Stop | Out-Null
                Write-Log ('Открыта панель GPU: ' + $c) 'info'
                return [pscustomobject]@{ Ok = $true; Path = $c; Message = 'Панель драйвера открыта.' }
            } catch {}
        }
    }
    if ($Vendor -eq 'NVIDIA') {
        try { Start-Process -FilePath 'nvcplui.exe' -ErrorAction Stop | Out-Null
              return [pscustomobject]@{ Ok = $true; Path = 'nvcplui.exe'; Message = 'Панель NVIDIA открыта.' } } catch {}
    } elseif ($Vendor -eq 'AMD') {
        try { Start-Process -FilePath 'amdsoftware:' -ErrorAction Stop | Out-Null
              return [pscustomobject]@{ Ok = $true; Path = 'amdsoftware:'; Message = 'AMD Software открыта.' } } catch {}
    }
    try { Start-Process -FilePath 'ms-settings:display' -ErrorAction Stop | Out-Null } catch {}
    return [pscustomobject]@{ Ok = $false; Path = 'ms-settings:display'; Message = 'Панель драйвера не найдена. Открыты настройки дисплея Windows — обновите драйвер или установите панель NVIDIA/AMD.' }
}

function Get-GpuStatusText {
    $info = Get-GpuInfo
    $g = Get-GammaStatus
    $color = if ($g.Active) { 'цвет: ' + $g.Preset } elseif ($g.Supported) { 'цвет: стандарт' } else { 'цвет: панель драйвера' }
    return ($info.VendorLabel + ' · ' + $color)
}
