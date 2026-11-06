# ============================================================
#  FORTNITE: определение клиента, официальные настройки и модули
#  Меняются только параметры меню игры (GameUserSettings.ini),
#  реестр Windows и настройки GPU. Файлы клиента и EAC не трогаем.
# ============================================================

$script:FortniteExe        = $null
$script:FortniteInstallDir = $null
$script:FortniteCfgDir     = $null
$script:FortniteInfo       = $null
$script:FortniteRunning    = $false
$script:FortniteBackup     = Join-Path $script:Root 'fortnitecfg'
try { New-Item -ItemType Directory -Force -Path $script:FortniteBackup | Out-Null } catch {}

# ---------- Поиск установленной игры ----------
function Find-FortniteExe {
    $candidates = New-Object System.Collections.Generic.List[string]
    $exeRel = 'FortniteGame\Binaries\Win64\FortniteClient-Win64-Shipping.exe'

    # 1. Манифесты Epic Games Launcher: самый надёжный источник пути.
    foreach ($m in @(
        (Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests'),
        (Join-Path ${env:ProgramData} 'Epic\UnrealEngineLauncher\Data\Manifests'))) {
        try {
            foreach ($f in @(Get-ChildItem -LiteralPath $m -Filter '*.item' -File -ErrorAction SilentlyContinue)) {
                try {
                    $j = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop | ConvertFrom-Json
                    $name = [string]$j.DisplayName
                    $app = [string]$j.AppName
                    if ($name -match 'Fortnite' -or $app -match 'Fortnite') {
                        $loc = [string]$j.InstallLocation
                        if ($loc) { $candidates.Add((Join-Path $loc $exeRel)) }
                    }
                } catch {}
            }
        } catch {}
    }

    # 2. LauncherInstalled.dat — резервный список установок Epic.
    try {
        $li = Join-Path $env:ProgramData 'Epic\UnrealEngineLauncher\LauncherInstalled.dat'
        if (Test-Path -LiteralPath $li) {
            $j = Get-Content -LiteralPath $li -Raw -ErrorAction Stop | ConvertFrom-Json
            foreach ($it in @($j.InstallationList)) {
                if ([string]$it.AppName -match 'Fortnite' -and $it.InstallLocation) {
                    $candidates.Add((Join-Path ([string]$it.InstallLocation) $exeRel))
                }
            }
        }
    } catch {}

    # 3. Стандартные папки и другие диски.
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, 'C:\Epic Games',
                        'D:\Epic Games', 'E:\Epic Games', 'C:\Games', 'D:\Games', 'E:\Games')) {
        if (-not $root) { continue }
        $candidates.Add((Join-Path $root ('Fortnite\' + $exeRel)))
    }
    try {
        foreach ($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
            if (-not $d.Root) { continue }
            $candidates.Add((Join-Path $d.Root ('Epic Games\Fortnite\' + $exeRel)))
            $candidates.Add((Join-Path $d.Root ('Games\Fortnite\' + $exeRel)))
        }
    } catch {}

    foreach ($p in $candidates) {
        try { if ($p -and (Test-Path -LiteralPath $p)) { return [string]$p } } catch {}
    }
    return $null
}

function Get-FortniteCfgDir {
    if ($script:FortniteCfgDir -and (Test-Path -LiteralPath $script:FortniteCfgDir)) {
        return $script:FortniteCfgDir
    }
    $base = Join-Path $env:LOCALAPPDATA 'FortniteGame\Saved\Config'
    foreach ($name in @('WindowsClient', 'Windows')) {
        $p = Join-Path $base $name
        if (Test-Path -LiteralPath $p) { $script:FortniteCfgDir = $p; return $p }
    }
    $script:FortniteCfgDir = Join-Path $base 'WindowsClient'
    return $script:FortniteCfgDir
}

function Get-FortniteCfgFile {
    $dir = Get-FortniteCfgDir
    if (-not $dir) { return $null }
    return (Join-Path $dir 'GameUserSettings.ini')
}

function Test-FortniteRunning {
    try {
        $p = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $_.ProcessName -like 'FortniteClient-Win64-Shipping*'
        })
        return ($p.Count -gt 0)
    } catch { return $false }
}

# ---------- Сведения о клиенте ----------
function Get-FortniteClientInfo {
    $info = [pscustomobject]@{
        Found       = $false
        Exe         = ''
        InstallDir  = ''
        Version     = '—'
        Build       = '—'
        Updated     = '—'
        Engine      = 'Unreal Engine 5'
        Store       = 'Epic Games'
        CfgReady    = $false
        CfgPath     = ''
        CfgKeys     = 0
        Eac         = $false
        EacPath     = ''
    }
    if (-not $script:FortniteExe -or -not (Test-Path -LiteralPath $script:FortniteExe)) { return $info }

    $info.Found      = $true
    $info.Exe        = [string]$script:FortniteExe
    $info.InstallDir = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $script:FortniteExe)))
    try {
        $fi = Get-Item -LiteralPath $script:FortniteExe -Force
        $vi = $fi.VersionInfo
        $ver = [string]$vi.FileVersion
        if (-not $ver) { $ver = [string]$vi.ProductVersion }
        if ($ver) { $info.Version = $ver.Split('+')[0].Trim() }
        $info.Build   = [string]$vi.ProductName
        if (-not $info.Build) { $info.Build = 'Fortnite' }
        $info.Updated = $fi.LastWriteTime.ToString('yyyy-MM-dd')
    } catch {}

    # Версия Epic-сборки лежит в манифесте лаунчера, а не в FileVersion.
    if ($info.Version -eq '—') {
        try {
            foreach ($m in @(
                (Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests'),
                (Join-Path ${env:ProgramData} 'Epic\UnrealEngineLauncher\Data\Manifests'))) {
                foreach ($f in @(Get-ChildItem -LiteralPath $m -Filter '*.item' -File -ErrorAction SilentlyContinue)) {
                    $j = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop | ConvertFrom-Json
                    if (([string]$j.InstallLocation).TrimEnd('\') -ne ([string]$info.InstallDir).TrimEnd('\')) { continue }
                    $v = [string]$j.CompleteVersion
                    if (-not $v) { $v = [string]$j.AppVersionString }
                    if ($v -match 'Release-([0-9.]+)') { $info.Version = $matches[1] }
                    elseif ($v) { $info.Version = $v }
                    if (-not $info.Build -or $info.Build -eq 'Fortnite') {
                        if ($v) { $info.Build = $v }
                    }
                    break
                }
            }
        } catch {}
    }

    $cfg = Get-FortniteCfgFile
    if ($cfg) {
        $info.CfgPath = $cfg
        if (Test-Path -LiteralPath $cfg) {
            $info.CfgReady = $true
            try {
                $keys = @{}
                foreach ($ln in @([IO.File]::ReadAllLines($cfg))) {
                    $t = ([string]$ln).Trim()
                    if (-not $t -or $t.StartsWith(';') -or $t.StartsWith('[')) { continue }
                    $eq = $t.IndexOf('=')
                    if ($eq -gt 0) { $keys[$t.Substring(0, $eq).Trim().ToLower()] = $true }
                }
                $info.CfgKeys = $keys.Count
            } catch {}
        }
    }

    $root = Split-Path -Parent $script:FortniteExe
    foreach ($rel in @(
        'EasyAntiCheat\EasyAntiCheat_EOS_Setup.exe',
        'EasyAntiCheat\EasyAntiCheat_x64.dll',
        'FortniteGame\Binaries\Win64\EasyAntiCheat\EasyAntiCheat_EOS_Setup.exe',
        'FortniteGame\Binaries\Win64\EasyAntiCheat\EasyAntiCheat_x64.dll')) {
        $p = Join-Path (Split-Path -Parent (Split-Path -Parent $root)) $rel
        if (-not (Test-Path -LiteralPath $p)) { $p = Join-Path $root $rel }
        if (Test-Path -LiteralPath $p) { $info.Eac = $true; $info.EacPath = $p; break }
    }
    if (-not $info.Eac) {
        try {
            $eac = Get-ChildItem -LiteralPath (Split-Path -Parent $root) -Filter 'EasyAntiCheat*' -Directory -ErrorAction SilentlyContinue |
                   Select-Object -First 1
            if ($eac) { $info.Eac = $true; $info.EacPath = $eac.FullName }
        } catch {}
    }
    return $info
}

# ---------- Пресеты официальных настроек ----------
$script:FortnitePresets = @(
    [pscustomobject]@{
        Key  = 'performance'
        Name = 'МАКСИМАЛЬНЫЙ FPS'
        Sub  = 'низкие эффекты · без VSync · полный экран'
        Desc = 'Максимальная частота кадров и минимальная задержка: тени, эффекты и постобработка на минимуме, VSync выключен, полный экран. Все параметры есть в меню Fortnite.'
        Blocks = @(
            [pscustomobject]@{ Section = '[/Script/FortniteGame.FortGameUserSettings]'; Lines = @(
                'FullscreenMode=0',
                'LastConfirmedFullscreenMode=0',
                'PreferredFullscreenMode=0',
                'bUseVSync=False',
                'bUseDynamicResolution=False',
                'bMotionBlur=False',
                'bShowFPS=True',
                'bShowGrass=False',
                'bUseNanite=False',
                'bUseGPUCrashDebugging=False',
                'FrameRateLimit=0.000000',
                'FrontendFrameRateLimit=120.000000'
            ) }
            [pscustomobject]@{ Section = '[ScalabilityGroups]'; Lines = @(
                'sg.ResolutionQuality=100',
                'sg.ViewDistanceQuality=2',
                'sg.AntiAliasingQuality=0',
                'sg.ShadowQuality=0',
                'sg.GlobalIlluminationQuality=0',
                'sg.ReflectionQuality=0',
                'sg.PostProcessQuality=0',
                'sg.TextureQuality=2',
                'sg.EffectsQuality=0',
                'sg.FoliageQuality=0',
                'sg.ShadingQuality=0',
                'sg.LandscapeQuality=0'
            ) }
            [pscustomobject]@{ Section = '[PerformanceMode]'; Lines = @('MeshQuality=0') }
        )
    }
    [pscustomobject]@{
        Key  = 'balanced'
        Name = 'БАЛАНС'
        Sub  = 'чисто · стабильно · без мыла'
        Desc = 'Компромисс между картинкой и FPS: средние тени и эффекты, дальность прорисовки выше, VSync выключен, без сглаживания. Подходит для 144 Гц.'
        Blocks = @(
            [pscustomobject]@{ Section = '[/Script/FortniteGame.FortGameUserSettings]'; Lines = @(
                'bUseVSync=False',
                'bUseDynamicResolution=False',
                'bMotionBlur=False',
                'bShowFPS=True',
                'bShowGrass=True',
                'bUseNanite=False',
                'FrameRateLimit=165.000000',
                'FrontendFrameRateLimit=120.000000'
            ) }
            [pscustomobject]@{ Section = '[ScalabilityGroups]'; Lines = @(
                'sg.ResolutionQuality=100',
                'sg.ViewDistanceQuality=2',
                'sg.AntiAliasingQuality=1',
                'sg.ShadowQuality=1',
                'sg.GlobalIlluminationQuality=1',
                'sg.ReflectionQuality=1',
                'sg.PostProcessQuality=1',
                'sg.TextureQuality=2',
                'sg.EffectsQuality=1',
                'sg.FoliageQuality=1',
                'sg.ShadingQuality=1',
                'sg.LandscapeQuality=1'
            ) }
            [pscustomobject]@{ Section = '[PerformanceMode]'; Lines = @('MeshQuality=1') }
        )
    }
    [pscustomobject]@{
        Key  = 'quality'
        Name = 'КАЧЕСТВО'
        Sub  = 'максимум деталей · 165 FPS'
        Desc = 'Максимальные тени, сглаживание, отражения и растительность при FrameRateLimit 165. VSync и размытие движения выключены для отклика.'
        Blocks = @(
            [pscustomobject]@{ Section = '[/Script/FortniteGame.FortGameUserSettings]'; Lines = @(
                'bUseVSync=False',
                'bUseDynamicResolution=False',
                'bMotionBlur=False',
                'bShowFPS=True',
                'bShowGrass=True',
                'bUseNanite=False',
                'FrameRateLimit=165.000000',
                'FrontendFrameRateLimit=120.000000'
            ) }
            [pscustomobject]@{ Section = '[ScalabilityGroups]'; Lines = @(
                'sg.ResolutionQuality=100',
                'sg.ViewDistanceQuality=3',
                'sg.AntiAliasingQuality=3',
                'sg.ShadowQuality=3',
                'sg.GlobalIlluminationQuality=3',
                'sg.ReflectionQuality=3',
                'sg.PostProcessQuality=3',
                'sg.TextureQuality=3',
                'sg.EffectsQuality=3',
                'sg.FoliageQuality=3',
                'sg.ShadingQuality=3',
                'sg.LandscapeQuality=3'
            ) }
            [pscustomobject]@{ Section = '[PerformanceMode]'; Lines = @('MeshQuality=1') }
        )
    }
)

function Get-FortnitePreset {
    param([string]$Key)
    $p = @($script:FortnitePresets | Where-Object { $_.Key -eq $Key } | Select-Object -First 1)
    if ($p.Count -eq 0) { $p = @($script:FortnitePresets | Select-Object -First 1) }
    return $p[0]
}

function Get-FortnitePresetName {
    param([string]$Key)
    if (-not $Key) { return '—' }
    return [string](Get-FortnitePreset $Key).Name
}

function Get-FortniteCfgStatusText {
    $key = [string]$script:State['FortnitePreset']
    $pending = [string]$script:State['FortnitePending']
    if ($pending) { return ('пресет ' + (Get-FortnitePresetName $pending) + ' · запишется после закрытия игры') }
    if ($key) { return ('пресет ' + (Get-FortnitePresetName $key)) }
    return 'настройки не изменялись'
}

# ---------- Слияние INI без потери чужих параметров ----------
function Merge-IniFile {
    param([string]$Path, [string]$Section, [string[]]$Lines)

    $target = [string]$Section
    if (-not $target.StartsWith('[')) { $target = '[' + $target.Trim('[', ']') + ']' }
    $existing = @()
    if (Test-Path -LiteralPath $Path) {
        try { $existing = @([IO.File]::ReadAllLines($Path)) } catch { $existing = @() }
    }

    $values  = @{}
    $managed = New-Object System.Collections.Generic.List[string]
    foreach ($l in @($Lines)) {
        $t = ([string]$l).Trim()
        if (-not $t) { continue }
        $eq = $t.IndexOf('=')
        if ($eq -lt 1) { continue }
        $k = $t.Substring(0, $eq).Trim()
        $values[$k.ToLower()] = $t
        $managed.Add($k.ToLower())
    }

    $start = -1
    $end   = $existing.Count
    for ($i = 0; $i -lt $existing.Count; $i++) {
        $t = ([string]$existing[$i]).Trim()
        if ($t.StartsWith('[') -and $t.EndsWith(']')) {
            if ($start -ge 0) { $end = $i; break }
            if ($t -ieq $target) { $start = $i }
        }
    }

    $out = New-Object System.Collections.Generic.List[string]
    if ($start -lt 0) {
        foreach ($l in $existing) { $out.Add([string]$l) }
        if ($out.Count -gt 0 -and $out[$out.Count - 1].Trim().Length -gt 0) { $out.Add('') }
        $out.Add($target)
        foreach ($k in $managed) { $out.Add([string]$values[$k]) }
    } else {
        for ($i = 0; $i -le $start; $i++) { $out.Add([string]$existing[$i]) }
        $seen = @{}
        for ($i = $start + 1; $i -lt $end; $i++) {
            $line = [string]$existing[$i]
            $t = $line.Trim()
            $eq = $t.IndexOf('=')
            if ($eq -gt 0) {
                $key = $t.Substring(0, $eq).Trim().ToLower()
                if ($values.ContainsKey($key)) {
                    if (-not $seen.ContainsKey($key)) {
                        $out.Add([string]$values[$key])
                        $seen[$key] = $true
                    }
                    continue
                }
            }
            $out.Add($line)
        }
        foreach ($k in $managed) {
            if (-not $seen.ContainsKey($k)) { $out.Add([string]$values[$k]) }
        }
        for ($i = $end; $i -lt $existing.Count; $i++) { $out.Add([string]$existing[$i]) }
    }

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllLines($Path, $out, (New-Object System.Text.UTF8Encoding($false)))
}

# ---------- Применение, откат и отложенная запись ----------
function Set-FortniteCfgPreset {
    param([string]$Key)
    $p = Get-FortnitePreset $Key
    if (Test-FortniteRunning) {
        $script:State['FortnitePending'] = $p.Key
        Save-State
        return [pscustomobject]@{ Ok = $false; Pending = $true
            Message = ('Fortnite запущен: настройки «' + $p.Name + '» запишутся автоматически после закрытия игры.') }
    }
    $file = Get-FortniteCfgFile
    if (-not $file) {
        return [pscustomobject]@{ Ok = $false; Pending = $false; Message = 'Не удалось найти папку настроек Fortnite.' }
    }
    if (Test-Path -LiteralPath $file) {
        $null = Backup-FileOnce $file 'fortnite-gus' $script:FortniteBackup
        Backup-FileStamp $file 'fortnite-gus' $script:FortniteBackup
    } else {
        $dir = Split-Path -Parent $file
        try { New-Item -ItemType Directory -Force -Path $dir | Out-Null } catch {}
        $null = Backup-FileOnce $file 'fortnite-gus' $script:FortniteBackup
    }
    try {
        foreach ($block in @($p.Blocks)) {
            Merge-IniFile -Path $file -Section ([string]$block.Section) -Lines @($block.Lines)
        }
    } catch {
        return [pscustomobject]@{ Ok = $false; Pending = $false; Message = ('Не удалось записать GameUserSettings.ini: ' + $_.Exception.Message) }
    }
    $script:State['FortnitePreset'] = $p.Key
    $script:State['FortniteAt'] = (Get-Date).ToString('s')
    $script:State.Remove('FortnitePending')
    Save-State
    Write-Log ('FORTNITE: применён пресет «' + $p.Name + '» (официальные настройки, бэкап сохранён)') 'ok'
    return [pscustomobject]@{ Ok = $true; Pending = $false
        Message = ('Fortnite: применён пресет «' + $p.Name + '». Бэкап: ' + $script:FortniteBackup) }
}

function Update-PendingFortniteCfg {
    try {
        $key = [string]$script:State['FortnitePending']
        if (-not $key) { return $false }
        if (Test-FortniteRunning) { return $false }
        $r = Set-FortniteCfgPreset $key
        if ($r.Ok) {
            Write-Log ('FORTNITE: отложенный пресет «' + (Get-FortnitePresetName $key) + '» записан после закрытия игры') 'ok'
            return $true
        }
    } catch {}
    return $false
}

function Undo-FortniteCfg {
    if (Test-FortniteRunning) {
        return [pscustomobject]@{ Ok = $false; Message = 'Fortnite запущен. Закройте игру и повторите откат.' }
    }
    $file = Get-FortniteCfgFile
    if (-not $file) {
        return [pscustomobject]@{ Ok = $false; Message = 'Настройки Fortnite не найдены.' }
    }
    if (Restore-FileOnce $file 'fortnite-gus' $script:FortniteBackup) {
        $script:State.Remove('FortnitePreset')
        $script:State.Remove('FortniteAt')
        $script:State.Remove('FortnitePending')
        Save-State
        Write-Log 'FORTNITE: исходный GameUserSettings.ini восстановлен' 'ok'
        return [pscustomobject]@{ Ok = $true; Message = 'Исходные настройки Fortnite восстановлены.' }
    }
    return [pscustomobject]@{ Ok = $false; Message = 'Резервная копия настроек Fortnite не найдена.' }
}

function Invoke-FortniteCfg {
    $r = Set-FortniteCfgPreset 'performance'
    if (-not $r.Ok -and -not $r.Pending) { throw $r.Message }
    if ($r.Pending) { Write-Log $r.Message 'info' }
}

# ---------- Windows / GPU / процесс ----------
function Invoke-FortniteCompat {
    if (-not $script:FortniteExe) { throw 'FORTNITE не найден — оптимизация совместимости пропущена' }
    $k = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
    Ensure-RegKey $k
    $old = Get-Reg $k $script:FortniteExe
    if (-not $script:State.ContainsKey('FortniteCompatOld')) {
        $script:State['FortniteCompatOld'] = if ($null -eq $old) { '' } else { [string]$old }
    }
    $val = '~ DISABLEDXMAXIMIZEDWINDOWEDMODE'
    if ($old -and ([string]$old).Trim().Length -gt 0) {
        if (([string]$old) -notmatch 'DISABLEDXMAXIMIZEDWINDOWEDMODE') {
            $val = ([string]$old).TrimEnd() + ' DISABLEDXMAXIMIZEDWINDOWEDMODE'
        } else { $val = [string]$old }
    }
    Set-RegStr $k $script:FortniteExe $val
    Write-Log 'Оптимизации полного экрана для Fortnite отключены' 'ok'
}

function Undo-FortniteCompat {
    if (-not $script:FortniteExe) { return }
    $k = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
    $old = [string]$script:State['FortniteCompatOld']
    if ($old) { Set-RegStr $k $script:FortniteExe $old }
    else { Remove-RegValue $k $script:FortniteExe }
    Write-Log 'Параметры совместимости Fortnite восстановлены' 'ok'
}

function Invoke-FortniteGpu {
    if (-not $script:FortniteExe) { throw 'FORTNITE не найден — привязка к GPU пропущена' }
    $k = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
    Ensure-RegKey $k
    $old = Get-Reg $k $script:FortniteExe
    if (-not $script:State.ContainsKey('FortniteGpuOld')) {
        $script:State['FortniteGpuOld'] = if ($null -eq $old) { '' } else { [string]$old }
    }
    $parts = @()
    if ($old) {
        foreach ($p in ([string]$old).Split(';')) {
            $t = $p.Trim()
            if (-not $t) { continue }
            if ($t -match '^GpuPreference\s*=') { continue }
            $parts += $t
        }
    }
    $parts += 'GpuPreference=2'
    Set-RegStr $k $script:FortniteExe (($parts -join ';') + ';')
    Write-Log 'Fortnite → «Высокая производительность» GPU (прочие флаги сохранены)' 'ok'
}

function Undo-FortniteGpu {
    if (-not $script:FortniteExe) { return }
    $k = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
    $old = [string]$script:State['FortniteGpuOld']
    if ($old) { Set-RegStr $k $script:FortniteExe $old }
    else { Remove-RegValue $k $script:FortniteExe }
    Write-Log 'Привязка GPU для Fortnite восстановлена' 'ok'
}

function Get-FortniteProcesses {
    try {
        return @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $_.ProcessName -like 'FortniteClient-Win64-Shipping*'
        })
    } catch { return @() }
}

function Invoke-FortnitePriority {
    $p = @(Get-FortniteProcesses)
    if ($p.Count -eq 0) { Write-Log 'Fortnite не запущен — приоритет применится при старте' 'info'; return }
    foreach ($x in $p) { try { $x.PriorityClass = 'High' } catch {} }
    Write-Log 'Приоритет запущенного Fortnite → High' 'ok'
}

function Invoke-FortniteAffinity {
    $mask = Get-PhysicalCoreMask
    if ($mask -eq 0) { throw 'Не удалось определить физические ядра' }
    $p = @(Get-FortniteProcesses)
    if ($p.Count -eq 0) { Write-Log 'Fortnite не запущен — привязка к ядрам применится при старте' 'info'; return }
    foreach ($x in $p) { try { $x.ProcessorAffinity = [IntPtr]$mask } catch {} }
    Write-Log ('Fortnite привязан к физическим ядрам (маска 0x{0:X})' -f $mask) 'ok'
}

function Invoke-FortniteProcessPolish {
    $p = @(Get-FortniteProcesses)
    if ($p.Count -eq 0) { return }
    foreach ($x in $p) {
        try { $x.PriorityClass = 'High' } catch {}
        if ($script:Enabled['fortniteaffinity']) {
            $mask = Get-PhysicalCoreMask
            if ($mask -ne 0) { try { $x.ProcessorAffinity = [IntPtr]$mask } catch {} }
        }
    }
}

# ---------- Текст отчёта для страницы ----------
function Get-FortniteCompatText {
    $ri = Get-FortniteClientInfo
    $lines = New-Object System.Collections.Generic.List[string]
    if (-not $ri.Found) {
        $lines.Add('FORTNITE не найден.')
        $lines.Add('')
        $lines.Add('Установите игру через Epic Games Launcher и запустите её один раз —')
        $lines.Add('появится GameUserSettings.ini, после чего станут доступны пресеты.')
        return ($lines -join "`r`n")
    }
    $lines.Add('FORTNITE · ' + $ri.Version)
    $lines.Add('Клиент: ' + $ri.Exe)
    $lines.Add('Обновлён: ' + $ri.Updated + '   ·   движок: ' + $ri.Engine)
    $lines.Add('Конфиг: ' + $(if ($ri.CfgReady) { [string]$ri.CfgKeys + ' ключей' } else { 'появится после первого запуска' }))
    $lines.Add('EasyAntiCheat: ' + $(if ($ri.Eac) { 'найден, не изменяется' } else { 'не найден' }))
    $lines.Add('')
    $lines.Add('Доступные пресеты (только параметры меню игры):')
    foreach ($p in @($script:FortnitePresets)) {
        $lines.Add('  · ' + $p.Name + ' — ' + $p.Desc)
    }
    $lines.Add('')
    $lines.Add('Сейчас: ' + (Get-FortniteCfgStatusText) + '.')
    $lines.Add('Бэкап: ' + $script:FortniteBackup)
    $lines.Add('')
    $lines.Add('Безопасность: exe/dll клиента и файлы EAC не изменяются.')
    $lines.Add('Меняются только официальные настройки игры, реестр Windows и профиль GPU.')
    return ($lines -join "`r`n")
}

# ============================================================
#  ОКРУЖЕНИЕ FORTNITE
# ============================================================
$script:FortniteExe        = Find-FortniteExe
$script:FortniteInstallDir = $(if ($script:FortniteExe) {
    Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $script:FortniteExe)))
} else { $null })
$script:FortniteRunning    = Test-FortniteRunning
$script:FortniteInfo       = Get-FortniteClientInfo
