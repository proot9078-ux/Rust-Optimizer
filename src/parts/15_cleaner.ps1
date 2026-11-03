# ============================================================
#  WINDOWS CARE ENGINE — очистка
#  Стандартные средства Windows, без сторонних бинарников.
# ============================================================

$script:CleanBytes   = [int64]0
$script:CleanObjects = [int]0
$script:CleanNotes   = New-Object System.Collections.Generic.List[string]

function Reset-CleanMeter {
    $script:CleanBytes   = [int64]0
    $script:CleanObjects = [int]0
    $script:CleanNotes.Clear()
}

function Add-CleanMeter {
    param([int64]$Bytes = 0, [int]$Objects = 0, [string]$Note = '')
    if ($Bytes -gt 0) { $script:CleanBytes += $Bytes }
    if ($Objects -gt 0) { $script:CleanObjects += $Objects }
    if ($Note) { $script:CleanNotes.Add($Note) }
}

function Get-CleanMeterText {
    return ('{0:N1} МБ · {1:N0} объектов' -f ($script:CleanBytes / 1MB), $script:CleanObjects)
}

function Write-CleanSummary {
    param([string]$Title = 'Очистка')
    $mb = [math]::Round($script:CleanBytes / 1MB, 1)
    Write-Log ('{0}: освобождено {1:N1} МБ, удалено объектов — {2:N0}' -f $Title, $mb, $script:CleanObjects) 'ok'
    $script:State['LastCleanMB']    = $mb
    $script:State['LastCleanCount'] = $script:CleanObjects
    $script:State['LastCleanTitle'] = $Title
    $script:State['LastCleanAt']    = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Save-State
}

# ------------------------------------------------------------
#  Безопасные файловые операции
# ------------------------------------------------------------
function Get-PathBytes {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return [int64]0 }
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (-not $item.PSIsContainer) { return [int64]$item.Length }
        $sum = (Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
                Where-Object { -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) } |
                Measure-Object -Property Length -Sum).Sum
        if ($null -eq $sum) { return [int64]0 }
        return [int64]$sum
    } catch { return [int64]0 }
}

function Clear-FolderSafe {
    param([string]$Path, [string]$Filter = '*')
    $res = [pscustomobject]@{ Path = $Path; Bytes = [int64]0; Objects = 0; Skipped = 0 }
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $res }
    $items = @(Get-ChildItem -LiteralPath $Path -Force -Filter $Filter -ErrorAction SilentlyContinue)
    foreach ($it in $items) {
        if ($it.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            $res.Skipped++
            continue
        }
        $size = if ($it.PSIsContainer) { Get-PathBytes $it.FullName } else { [int64]$it.Length }
        try {
            Remove-Item -LiteralPath $it.FullName -Recurse -Force -ErrorAction Stop
            $res.Bytes += $size
            $res.Objects++
            Add-CleanMeter -Bytes $size -Objects 1
        } catch {
            $res.Skipped++
        }
    }
    return $res
}

function Clear-FilesByPattern {
    param([string]$Path, [string]$Pattern)
    $res = [pscustomobject]@{ Path = $Path; Bytes = [int64]0; Objects = 0; Skipped = 0 }
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $res }
    foreach ($f in @(Get-ChildItem -LiteralPath $Path -Filter $Pattern -File -Force -ErrorAction SilentlyContinue)) {
        if ($f.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { $res.Skipped++; continue }
        try {
            $size = [int64]$f.Length
            Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
            $res.Bytes += $size
            $res.Objects++
            Add-CleanMeter -Bytes $size -Objects 1
        } catch { $res.Skipped++ }
    }
    return $res
}

function Remove-FileSafe {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return }
    try {
        $size = [int64](Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue).Length
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        Add-CleanMeter -Bytes $size -Objects 1
    } catch {}
}

# ------------------------------------------------------------
#  Ядро очистки (не сбрасывает счётчик — используется DeepClean)
# ------------------------------------------------------------
function Clear-UpdateCacheCore {
    $services = @('wuauserv', 'bits', 'dosvc', 'usosvc')
    $saved = @{}
    foreach ($n in $services) {
        $svc = Get-Service -Name $n -ErrorAction SilentlyContinue
        if ($svc) {
            $saved[$n] = @{
                Status = [string]$svc.Status
                Start  = [string]$svc.StartType
            }
        }
    }
    foreach ($n in $services) {
        try { Stop-Service -Name $n -Force -ErrorAction SilentlyContinue } catch {}
    }
    try {
        $sd = Join-Path $env:SystemRoot 'SoftwareDistribution'
        Clear-FolderSafe (Join-Path $sd 'Download') | Out-Null
        Clear-FolderSafe (Join-Path $sd 'DeliveryOptimization') | Out-Null
        Clear-FolderSafe (Join-Path $sd 'PostRebootEventCache.V2') | Out-Null
        Clear-FolderSafe (Join-Path $env:SystemRoot 'Logs\WindowsUpdate') | Out-Null
        $doCache = Join-Path $env:SystemRoot 'ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache'
        Clear-FolderSafe $doCache | Out-Null
        if (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue) {
            try { Delete-DeliveryOptimizationCache -Force -ErrorAction SilentlyContinue } catch {}
        }
    } finally {
        foreach ($n in @($saved.Keys)) {
            try { Set-Service -Name $n -StartupType ([string]$saved[$n].Start) -ErrorAction SilentlyContinue } catch {}
            if ($saved[$n].Status -eq 'Running') {
                try { Start-Service -Name $n -ErrorAction SilentlyContinue } catch {}
            }
        }
    }
    Write-Log 'Кэш обновлений Windows и Delivery Optimization очищен' 'info'
}

function Clear-DumpCore {
    Clear-FolderSafe (Join-Path $env:LOCALAPPDATA 'CrashDumps') | Out-Null
    Clear-FolderSafe (Join-Path $env:SystemRoot 'Minidump') | Out-Null
    Clear-FolderSafe (Join-Path $env:SystemRoot 'LiveKernelReports') | Out-Null
    Clear-FolderSafe (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue') | Out-Null
    Clear-FolderSafe (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive') | Out-Null
    Clear-FolderSafe (Join-Path $env:ProgramData 'Microsoft\Windows\WER\Temp') | Out-Null
    Clear-FolderSafe (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER') | Out-Null
    Remove-FileSafe (Join-Path $env:SystemRoot 'MEMORY.DMP')
}

function Clear-BrowserCacheCore {
    $chromium = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data'),
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'),
        (Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data'),
        (Join-Path $env:LOCALAPPDATA 'Vivaldi\User Data'),
        (Join-Path $env:LOCALAPPDATA 'Yandex\YandexBrowser\User Data')
    )
    $cacheSubs = @(
        'Cache', 'Code Cache', 'GPUCache', 'DawnCache', 'GrShaderCache',
        'ShaderCache', 'Media Cache', 'Service Worker\CacheStorage',
        'Service Worker\ScriptCache'
    )
    foreach ($root in $chromium) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $profiles = @(Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue |
                      Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' -or $_.Name -eq 'Guest Profile' -or $_.Name -eq 'System Profile' })
        foreach ($p in $profiles) {
            foreach ($sub in $cacheSubs) {
                Clear-FolderSafe (Join-Path $p.FullName $sub) | Out-Null
            }
        }
        foreach ($sub in @('ShaderCache', 'GrShaderCache', 'GraphiteDawnCache')) {
            Clear-FolderSafe (Join-Path $root $sub) | Out-Null
        }
    }

    $ff = Join-Path $env:LOCALAPPDATA 'Mozilla\Firefox\Profiles'
    if (Test-Path -LiteralPath $ff) {
        foreach ($p in @(Get-ChildItem -LiteralPath $ff -Directory -Force -ErrorAction SilentlyContinue)) {
            foreach ($sub in @('cache2', 'startupCache', 'shader-cache')) {
                Clear-FolderSafe (Join-Path $p.FullName $sub) | Out-Null
            }
        }
    }

    $opera = Join-Path $env:LOCALAPPDATA 'Opera Software\Opera Stable'
    if (Test-Path -LiteralPath $opera) {
        foreach ($sub in @('Cache', 'Code Cache', 'GPUCache', 'Service Worker\CacheStorage')) {
            Clear-FolderSafe (Join-Path $opera $sub) | Out-Null
        }
    }
    Write-Log 'Кэш браузеров очищен (только Cache, без паролей и истории)' 'info'
}

function Clear-GameJunkCore {
    if ($script:SteamPath) {
        foreach ($sub in @('logs', 'dumps', 'appcache\httpcache', 'appcache\librarycache')) {
            Clear-FolderSafe (Join-Path $script:SteamPath $sub) | Out-Null
        }
        $rust = Join-Path $script:SteamPath 'steamapps\common\Rust'
        foreach ($sub in @('logs', 'crash dumps')) {
            Clear-FolderSafe (Join-Path $rust $sub) | Out-Null
        }
        Clear-FilesByPattern $rust '*.dmp' | Out-Null
    }
    $rustLocal = Join-Path $env:LOCALAPPDATA 'Facepunch\Rust'
    if (Test-Path -LiteralPath $rustLocal) {
        foreach ($sub in @('logs', 'crashes')) {
            Clear-FolderSafe (Join-Path $rustLocal $sub) | Out-Null
        }
        Clear-FilesByPattern $rustLocal '*.dmp' | Out-Null
    }
    Write-Log 'Логи и дампы Steam / RUST очищены (cfg и настройки не тронуты)' 'info'
}

function Clear-ThumbnailCore {
    $explorer = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
    Clear-FilesByPattern $explorer 'thumbcache_*.db' | Out-Null
    Clear-FilesByPattern $explorer 'iconcache_*.db' | Out-Null
    Clear-FolderSafe (Join-Path $explorer 'ThumbCacheToDelete') | Out-Null
    Clear-FolderSafe (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Caches') | Out-Null
    Write-Log 'Кэш эскизов и иконок очищен (занятые Explorer файлы пропущены)' 'info'
}

function Clear-DeepLogsCore {
    Clear-FilesByPattern (Join-Path $env:SystemRoot 'Logs\CBS') '*.log' | Out-Null
    Clear-FilesByPattern (Join-Path $env:SystemRoot 'Logs\CBS') '*.cab' | Out-Null
    Clear-FolderSafe (Join-Path $env:SystemRoot 'Logs\DISM') | Out-Null
    Clear-FolderSafe (Join-Path $env:SystemRoot 'Logs\MoSetup') | Out-Null
    Clear-FolderSafe (Join-Path $env:SystemRoot 'Logs\SIH') | Out-Null
    Clear-FolderSafe (Join-Path $env:SystemRoot 'Temp') | Out-Null
    Clear-FolderSafe (Join-Path $env:ProgramData 'Microsoft\Windows\WER\Temp') | Out-Null
    Write-Log 'Старые журналы CBS/DISM/Windows Update очищены' 'info'
}

function Clear-PrefetchCore {
    Clear-FilesByPattern (Join-Path $env:SystemRoot 'Prefetch') '*.pf' | Out-Null
    Clear-FolderSafe (Join-Path $env:SystemRoot 'Prefetch\ReadyBoot') | Out-Null
    Write-Log 'Prefetch очищен — первые запуски могут быть чуть медленнее' 'warn'
}

function Clear-OldWindowsCore {
    foreach ($name in @('Windows.old', '$Windows.~BT', '$Windows.~WS', '$WinREAgent')) {
        $path = Join-Path $env:SystemDrive $name
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $size = Get-PathBytes $path
        Write-Log ('Удаление ' + $name + ' (' + [math]::Round($size / 1MB, 1) + ' МБ)…') 'warn'
        try {
            & takeown.exe /F $path /R /A /D Y 2>&1 | Out-Null
            & icacls.exe $path /grant '*S-1-5-32-544:(OI)(CI)F' /T /C /Q 2>&1 | Out-Null
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
            Add-CleanMeter -Bytes $size -Objects 1
        } catch {
            Write-Log ('Не удалось удалить ' + $name + ': ' + $_.Exception.Message) 'warn'
        }
    }
}

function Clear-EventLogsCore {
    $logs = @(Get-WinEvent -ListLog * -ErrorAction SilentlyContinue |
              Where-Object { $_.IsEnabled -and $_.RecordCount -gt 0 })
    $cleared = 0
    foreach ($l in $logs) {
        try {
            & wevtutil.exe cl $l.LogName 2>&1 | Out-Null
            $cleared++
            Add-CleanMeter -Objects 1
        } catch {}
    }
    Write-Log ('Журналы событий очищены: ' + $cleared + ' из ' + $logs.Count) 'warn'
}

# ------------------------------------------------------------
#  Публичные модули очистки
# ------------------------------------------------------------
function Invoke-DeepClean {
    Reset-CleanMeter
    Write-Log 'Глубокая очистка Windows: старт' 'step'
    Clear-FolderSafe $env:TEMP | Out-Null
    Clear-FolderSafe (Join-Path $env:SystemRoot 'Temp') | Out-Null
    Clear-FolderSafe (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\INetCache') | Out-Null
    Clear-UpdateCacheCore
    Clear-DumpCore
    Clear-BrowserCacheCore
    Clear-GameJunkCore
    Clear-ThumbnailCore
    Clear-DeepLogsCore
    Write-CleanSummary 'Глубокая очистка Windows'
}

function Invoke-UpdateCacheClean {
    Reset-CleanMeter
    Clear-UpdateCacheCore
    Write-CleanSummary 'Кэш обновлений Windows'
}

function Invoke-DumpClean {
    Reset-CleanMeter
    Clear-DumpCore
    Write-CleanSummary 'Дампы и отчёты об ошибках'
}

function Invoke-BrowserCache {
    Reset-CleanMeter
    Clear-BrowserCacheCore
    Write-CleanSummary 'Кэш браузеров'
}

function Invoke-GameJunkClean {
    Reset-CleanMeter
    Clear-GameJunkCore
    Write-CleanSummary 'Логи и дампы Steam / RUST'
}

function Invoke-ThumbnailClean {
    Reset-CleanMeter
    Clear-ThumbnailCore
    Write-CleanSummary 'Кэш эскизов и иконок'
}

function Invoke-PrefetchClean {
    Reset-CleanMeter
    Clear-PrefetchCore
    Write-CleanSummary 'Prefetch'
}

function Invoke-OldWindowsClean {
    Reset-CleanMeter
    Clear-OldWindowsCore
    Write-CleanSummary 'Старые установки Windows'
}

function Invoke-EventLogClean {
    Reset-CleanMeter
    Clear-EventLogsCore
    Write-CleanSummary 'Журналы событий Windows'
}
