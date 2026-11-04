# ============================================================
#  ПРОФИЛИ: экспорт и импорт выбранных модулей
#  Формат — обычный JSON. Код из файла не исполняется:
#  импортируются только логические флаги известных модулей.
# ============================================================
function Get-ProfileState {
    $enabled = [ordered]@{}
    foreach ($t in $script:Tweaks) {
        $enabled[$t.Id] = [bool]$script:Enabled[$t.Id]
    }
    return $enabled
}

function Export-OptimizerProfile {
    param([string]$Path)
    if (-not $Path) { throw 'Не указан путь для сохранения профиля' }
    $data = [ordered]@{
        app     = 'PURPLE RUSH'
        version = [string]$script:AppVersion
        created = (Get-Date).ToString('s')
        total   = @($script:Tweaks).Count
        enabled = (Get-ProfileState)
    }
    $json = $data | ConvertTo-Json -Depth 4
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    [IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($true)))
    Write-Log ('Профиль сохранён: ' + $Path) 'ok'
    return $Path
}

function Import-OptimizerProfile {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
        throw 'Файл профиля не найден'
    }
    $fi = Get-Item -LiteralPath $Path
    if ($fi.Length -gt 1MB) { throw 'Файл профиля слишком большой (ожидается JSON до 1 МБ)' }

    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $data = $null
    try { $data = $raw | ConvertFrom-Json } catch { throw 'Файл не является корректным JSON' }
    if (-not $data -or -not $data.enabled) { throw 'В профиле нет блока enabled' }

    $known = @{}
    foreach ($t in $script:Tweaks) { $known[$t.Id] = $true }

    $applied = 0
    $skipped = 0
    foreach ($p in @($data.enabled.PSObject.Properties)) {
        if ($p -and $known.ContainsKey([string]$p.Name)) {
            $script:Enabled[[string]$p.Name] = [bool]$p.Value
            $applied = $applied + 1
        } else {
            $skipped = $skipped + 1
        }
    }
    if ($applied -eq 0) { throw 'В профиле нет ни одного известного модуля' }

    $script:State['Enabled'] = $script:Enabled
    Save-State
    Write-Log ("Профиль загружен: применено $applied, пропущено неизвестных $skipped") 'ok'
    return @{ Applied = $applied; Skipped = $skipped }
}
