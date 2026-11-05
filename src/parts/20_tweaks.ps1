# ============================================================
#  СПИСОК ОПТИМИЗАЦИЙ
# ============================================================
$script:Tweaks = @(
    [pscustomobject]@{ Id = 'power'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'Максимальная производительность'
        Desc = 'План питания Ultimate Performance, отключение ASPM, USB-энергосбережения и сна диска.'
        Apply = { Invoke-PowerPlan }; Undo = { Undo-PowerPlan } }

    [pscustomobject]@{ Id = 'prio'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'Приоритет активного процесса'
        Desc = 'Win32PrioritySeparation = 26: кванты времени отдаются игре, а не фоновым службам.'
        Apply = { Invoke-PrioritySeparation }; Undo = { Undo-PrioritySeparation } }

    [pscustomobject]@{ Id = 'mmcss'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'Планировщик MMCSS и сетевой лимит'
        Desc = 'Снимает NetworkThrottlingIndex, игровые задачи получают High GPU/SFIO приоритет.'
        Apply = { Invoke-Mmcss }; Undo = { Undo-Mmcss } }

    [pscustomobject]@{ Id = 'gamedvr'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'Отключить Game DVR'
        Desc = 'Фоновая запись Xbox забирает 5–15% FPS и добавляет микрофризы.'
        Apply = { Invoke-GameDvr }; Undo = { Undo-GameDvr } }

    [pscustomobject]@{ Id = 'gamemode'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'Игровой режим Windows'
        Desc = 'Windows отдаёт приоритет активной игре и не трогает её фоновыми задачами.'
        Apply = { Invoke-GameMode }; Undo = { Undo-GameMode } }

    [pscustomobject]@{ Id = 'hags'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'Аппаратное планирование GPU'
        Desc = 'HAGS снижает задержку кадра. Требуется перезагрузка, нужна поддержка драйвера.'
        Apply = { Invoke-Hags }; Undo = { Undo-Hags } }

    [pscustomobject]@{ Id = 'mouse'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'Отключить ускорение мыши'
        Desc = 'Движение прицела 1:1 с рукой — самый дешёвый и заметный буст для шутера.'
        Apply = { Invoke-Mouse }; Undo = { Undo-Mouse } }

    [pscustomobject]@{ Id = 'keyfix'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'Убрать залипание клавиш'
        Desc = 'Shift ×5 больше не выбрасывает из игры в окно спец. возможностей.'
        Apply = { Invoke-KeyFix }; Undo = { Undo-KeyFix } }

    [pscustomobject]@{ Id = 'telemetry'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'Отключить телеметрию'
        Desc = 'Службы DiagTrack и dmwappushservice останавливаются и отключаются.'
        Apply = { Invoke-Telemetry }; Undo = { Undo-Telemetry } }

    [pscustomobject]@{ Id = 'powerthrottle'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'Отключить Power Throttling'
        Desc = 'Windows перестаёт ограничивать питание активных процессов (плюс к стабильности FPS).'
        Apply = { Invoke-PowerThrottle }; Undo = { Undo-PowerThrottle } }

    [pscustomobject]@{ Id = 'sysmain'; Group = 'sys'; Risk = $true; Default = $false
        Name = 'Отключить SysMain (Superfetch)'
        Desc = 'Плюс для SSD, минус для HDD. Включайте только если Windows стоит на SSD.'
        Apply = { Invoke-SysMain }; Undo = { Undo-SysMain } }

    [pscustomobject]@{ Id = 'search'; Group = 'sys'; Risk = $true; Default = $false
        Name = 'Отключить индексацию поиска'
        Desc = 'Меньше нагрузка на диск, но поиск по файлам станет медленнее.'
        Apply = { Invoke-SearchIndex }; Undo = { Undo-SearchIndex } }

    [pscustomobject]@{ Id = 'visual'; Group = 'sys'; Risk = $false; Default = $false
        Name = 'Визуальные эффекты на минимум'
        Desc = 'Отключает анимации Windows. Внешний вид станет проще, отклик — резче.'
        Apply = { Invoke-VisualEffects }; Undo = { Undo-VisualEffects } }

    [pscustomobject]@{ Id = 'hibernate'; Group = 'sys'; Risk = $false; Default = $false
        Name = 'Отключить гибернацию'
        Desc = 'Освобождает несколько ГБ на системном диске (удаляется hiberfil.sys).'
        Apply = { Invoke-HibernateOff }; Undo = { Undo-HibernateOff } }

    [pscustomobject]@{ Id = 'timer'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'Точный системный таймер (1 мс)'
        Desc = 'Разрешает приложениям точный таймер и держит 1 мс, пока программа открыта — отклик ввода и кадров ровнее.'
        Apply = { Invoke-TimerRes }; Undo = { Undo-TimerRes } }

    [pscustomobject]@{ Id = 'park'; Group = 'sys'; Risk = $true; Default = $false
        Name = 'Отключить парковку ядер CPU'
        Desc = 'Отключает парковку ядер процессора — плюс на старых CPU, тестируйте.'
        Apply = { Invoke-CpuPark }; Undo = { Undo-CpuPark } }

    [pscustomobject]@{ Id = 'qosgame'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'QoS для игр (DSCP / QoS Packet Scheduler)'
        Desc = 'Активирует планировщик пакетов QoS и задаёт приоритет для игрового трафика.'
        Apply = { Invoke-QosGame }; Undo = { Undo-QosGame } }

    [pscustomobject]@{ Id = 'prefetch'; Group = 'sys'; Risk = $true; Default = $false
        Name = 'Отключить Prefetch / Superfetch (полностью)'
        Desc = 'Полностью отключает Prefetch через реестр для минимизации дисковых операций. Откат возвращает исходные значения.'
        Apply = { Invoke-PrefetchOff }; Undo = { Undo-PrefetchOff } }

    [pscustomobject]@{ Id = 'deliveryopt'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'Отключить P2P-раздачу Delivery Optimization'
        Desc = 'Windows перестаёт раздавать обновления другим ПК и забирать канал во время игры. Сами обновления работают.'
        Apply = { Invoke-DeliveryOpt }; Undo = { Undo-DeliveryOpt } }

    [pscustomobject]@{ Id = 'fullscreenopt'; Group = 'sys'; Risk = $true; Default = $false
        Name = 'Отключить оптимизации полного экрана (глобально)'
        Desc = 'FSE-поведение Windows для всех игр: честный эксклюзивный полный экран. На части систем ломает alt-tab — тестируйте.'
        Apply = { Invoke-FullscreenOpt }; Undo = { Undo-FullscreenOpt } }

    [pscustomobject]@{ Id = 'xboxsvc'; Group = 'sys'; Risk = $true; Default = $false
        Name = 'Отключить службы Xbox'
        Desc = 'XblAuthManager, XblGameSave, XboxNetApiSvc и XboxGipSvc. Освобождает ресурсы, но ломает Game Pass и Xbox-приложения.'
        Apply = { Invoke-XboxServices }; Undo = { Undo-XboxServices } }

    [pscustomobject]@{ Id = 'faststartup'; Group = 'sys'; Risk = $true; Default = $false
        Name = 'Отключить быстрый запуск Windows'
        Desc = 'Полное завершение работы вместо гибридного сна: чище загрузка, меньше «залипших» драйверов. Включение — обратно.'
        Apply = { Invoke-FastStartupOff }; Undo = { Undo-FastStartupOff } }

    [pscustomobject]@{ Id = 'nagle'; Group = 'net'; Risk = $false; Default = $true
        Name = 'Отключить алгоритм Nagle'
        Desc = 'Мелкие пакеты уходят сразу: пинг стабильнее, регистрация попаданий точнее.'
        Apply = { Invoke-Nagle }; Undo = { Undo-Nagle } }

    [pscustomobject]@{ Id = 'netpower'; Group = 'net'; Risk = $false; Default = $true
        Name = 'Убрать энергосбережение сетевого адаптера'
        Desc = 'Windows больше не «усыпляет» сетевую карту для экономии энергии — меньше лагов и разрывов.'
        Apply = { Invoke-NetPower }; Undo = { Undo-NetPower } }

    [pscustomobject]@{ Id = 'tcptune'; Group = 'net'; Risk = $false; Default = $true
        Name = 'TCP-стек под игры'
        Desc = 'Автотюнинг окна и RSS включены, ECN и timestamps отключены. Откат возвращает прежние значения.'
        Apply = { Invoke-TcpTune }; Undo = { Undo-TcpTune } }

    [pscustomobject]@{ Id = 'flushdns'; Group = 'net'; Risk = $false; Default = $true
        Name = 'Сбросить DNS-кэш'
        Desc = 'Чистый кэш убирает старые записи серверов Rust и Steam.'
        Apply = { Invoke-FlushDns }; Undo = { } }

    [pscustomobject]@{ Id = 'dns'; Group = 'net'; Risk = $true; Default = $false
        Name = 'DNS Cloudflare 1.1.1.1'
        Desc = 'Меняет DNS на быстрый публичный. Если настроен свой DNS — лучше не включать.'
        Apply = { Invoke-Dns }; Undo = { Undo-Dns } }

    [pscustomobject]@{ Id = 'rustcompat'; Group = 'rust'; Risk = $false; Default = $true
        Name = 'Честный полный экран Rust'
        Desc = 'Отключает «оптимизации полного экрана» для RustClient.exe — меньше инпут-лага.'
        Apply = { Invoke-RustCompat }; Undo = { Undo-RustCompat } }

    [pscustomobject]@{ Id = 'rustgpu'; Group = 'rust'; Risk = $false; Default = $true
        Name = 'Rust на дискретной видеокарте'
        Desc = 'Явно привязывает RustClient.exe к профилю «Высокая производительность» GPU.'
        Apply = { Invoke-RustGpu }; Undo = { Undo-RustGpu } }

    [pscustomobject]@{ Id = 'rustprio'; Group = 'rust'; Risk = $false; Default = $true
        Name = 'Приоритет Rust → High'
        Desc = 'Повышает приоритет запущенного RustClient.exe. Real-time не используется намеренно.'
        Apply = { Invoke-RustPriority }; Undo = { } }

    [pscustomobject]@{ Id = 'rustaffinity'; Group = 'rust'; Risk = $true; Default = $false
        Name = 'Только физические ядра'
        Desc = 'Привязывает Rust к физическим ядрам без Hyper-Threading. На части CPU даёт минус — тестируйте.'
        Apply = { Invoke-RustAffinity }; Undo = { } }

    [pscustomobject]@{ Id = 'rustcfg'; Group = 'rust'; Risk = $false; Default = $true
        Name = 'Отключить траву и пост-эффекты'
        Desc = 'Пишет официальные конвары в cfg\client.cfg: grass.displacement, лучи, глубина резкости. Нужен закрытый Rust.'
        Apply = { Invoke-RustCfg }; Undo = { Undo-RustCfg; Undo-RustBinds } }

    [pscustomobject]@{ Id = 'rustmax'; Group = 'rust'; Risk = $false; Default = $false
        Name = 'МАКСИМАЛЬНАЯ ГРАФИКА НА МИНИМУМ (легально)'
        Desc = 'Расширенный набор официальных cfg для минимальной нагрузки: тени, дистанция, качество, туман, трава (без вмешательства в файлы клиента — безопасно для EAC).'
        Apply = { Invoke-RustMaxCfg }; Undo = { Undo-RustMaxCfg } }

    [pscustomobject]@{ Id = 'temp'; Group = 'clean'; Risk = $false; Default = $true
        Name = 'Очистка временных файлов'
        Desc = 'Удаляет мусор из TEMP, Windows\Temp и кэша Internet Explorer.'
        Apply = { Invoke-TempClean }; Undo = { } }

    [pscustomobject]@{ Id = 'bgapps'; Group = 'clean'; Risk = $false; Default = $true
        Name = 'Закрыть фоновые приложения'
        Desc = 'Завершает OneDrive, Teams, Skype, Cortana и виджеты. Steam и Rust не трогает.'
        Apply = { Invoke-BgApps }; Undo = { } }

    [pscustomobject]@{ Id = 'recycle'; Group = 'clean'; Risk = $false; Default = $false
        Name = 'Очистить корзину'
        Desc = 'Освобождает место на диске. Восстановить файлы после этого нельзя.'
        Apply = { Invoke-RecycleBin }; Undo = { } }

    [pscustomobject]@{ Id = 'shadercache'; Group = 'clean'; Risk = $false; Default = $false
        Name = 'Очистить кэш шейдеров DirectX'
        Desc = 'Удаляет старый кэш D3D/NVIDIA/AMD/Intel. Освобождает место и лечит артефакты; игра соберёт кэш заново.'
        Apply = { Invoke-ShaderClean }; Undo = { } }

    [pscustomobject]@{ Id = 'deepclean'; Group = 'clean'; Risk = $false; Default = $false
        Name = 'Глубокая очистка Windows'
        Desc = 'TEMP, кэш обновлений и Delivery Optimization, WER, дампы, кэш браузеров, логи Steam/RUST и старые журналы. Корзину и настройки не трогает.'
        Apply = { Invoke-DeepClean }; Undo = { } }

    [pscustomobject]@{ Id = 'updatecache'; Group = 'clean'; Risk = $false; Default = $false
        Name = 'Очистить кэш обновлений Windows'
        Desc = 'Останавливает службы обновления, очищает SoftwareDistribution\Download и кэш Delivery Optimization, затем возвращает службы.'
        Apply = { Invoke-UpdateCacheClean }; Undo = { } }

    [pscustomobject]@{ Id = 'dumps'; Group = 'clean'; Risk = $false; Default = $false
        Name = 'Удалить дампы и отчёты об ошибках'
        Desc = 'MEMORY.DMP, Minidump, CrashDumps, WER и LiveKernelReports. Освобождает место; сами ошибки это не исправляет.'
        Apply = { Invoke-DumpClean }; Undo = { } }

    [pscustomobject]@{ Id = 'browsercache'; Group = 'clean'; Risk = $false; Default = $false
        Name = 'Кэш браузеров'
        Desc = 'Только Cache/Code Cache/GPUCache у Edge, Chrome, Brave, Vivaldi, Yandex, Firefox и Opera. Пароли, cookies и история не удаляются.'
        Apply = { Invoke-BrowserCache }; Undo = { } }

    [pscustomobject]@{ Id = 'gamejunk'; Group = 'clean'; Risk = $false; Default = $false
        Name = 'Логи и дампы Steam / RUST'
        Desc = 'Старые логи Steam, httpcache, crash dumps и *.dmp RUST. Файлы cfg, сохранения и настройки игры не затрагиваются.'
        Apply = { Invoke-GameJunkClean }; Undo = { } }

    [pscustomobject]@{ Id = 'thumbcache'; Group = 'clean'; Risk = $false; Default = $false
        Name = 'Кэш эскизов и иконок'
        Desc = 'Удаляет thumbcache/iconcache. Занятые Explorer файлы пропускаются; для полной пересборки есть отдельная кнопка в «Ремонте».'
        Apply = { Invoke-ThumbnailClean }; Undo = { } }

    [pscustomobject]@{ Id = 'winsxs'; Group = 'clean'; Risk = $false; Default = $false
        Name = 'Очистка WinSxS (DISM)'
        Desc = 'DISM /StartComponentCleanup удаляет устаревшие компоненты. Долго (5–30 минут), но без удаления актуальных обновлений.'
        Apply = { Invoke-WinSxSClean }; Undo = { } }

    [pscustomobject]@{ Id = 'oldwindows'; Group = 'clean'; Risk = $true; Default = $false
        Name = 'Удалить Windows.old и следы установки'
        Desc = 'Windows.old, $Windows.~BT, $Windows.~WS, $WinREAgent. Освобождает десятки ГБ, но откат к предыдущей версии Windows станет невозможен.'
        Apply = { Invoke-OldWindowsClean }; Undo = { } }

    [pscustomobject]@{ Id = 'prefetchclean'; Group = 'clean'; Risk = $false; Default = $false
        Name = 'Очистить Prefetch'
        Desc = 'Удаляет *.pf и ReadyBoot. Первые запуски приложений станут чуть медленнее, затем Windows соберёт кэш заново.'
        Apply = { Invoke-PrefetchClean }; Undo = { } }

    [pscustomobject]@{ Id = 'eventlogs'; Group = 'clean'; Risk = $true; Default = $false
        Name = 'Очистить журналы событий Windows'
        Desc = 'Удаляет старые записи из журналов. Необратимо и мешает диагностике — используйте только осознанно после сбора отчётов.'
        Apply = { Invoke-EventLogClean }; Undo = { } }

    [pscustomobject]@{ Id = 'gamebar'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'Game Bar без оверлея и подсказок'
        Desc = 'Убирает всплывающую панель Xbox, автозапись и подсказки. Игровой режим Windows остаётся включённым.'
        Apply = { Invoke-GameBarOff }; Undo = { Undo-GameBarOff } }

    [pscustomobject]@{ Id = 'widgets'; Group = 'clean'; Risk = $false; Default = $true
        Name = 'Отключить виджеты Windows 11'
        Desc = 'Убирает ленту новостей и кнопку виджетов с панели задач. Работает через официальную политику Dsh.'
        Apply = { Invoke-WidgetsOff }; Undo = { Undo-WidgetsOff } }

    [pscustomobject]@{ Id = 'copilot'; Group = 'clean'; Risk = $false; Default = $true
        Name = 'Отключить Copilot'
        Desc = 'Скрывает кнопку Copilot и отключает его политикой Windows. Возврат — одной кнопкой «Откат».'
        Apply = { Invoke-CopilotOff }; Undo = { Undo-CopilotOff } }

    [pscustomobject]@{ Id = 'recall'; Group = 'clean'; Risk = $false; Default = $true
        Name = 'Отключить Windows Recall'
        Desc = 'Запрещает фоновую ИИ-запись экрана и анализ активности через политику WindowsAI.'
        Apply = { Invoke-RecallOff }; Undo = { Undo-RecallOff } }

    [pscustomobject]@{ Id = 'suggestions'; Group = 'clean'; Risk = $false; Default = $true
        Name = 'Убрать рекомендации и рекламу в «Пуске»'
        Desc = 'Отключает подсказки, тихую установку приложений и рекламные блоки Content Delivery Manager.'
        Apply = { Invoke-SuggestionsOff }; Undo = { Undo-SuggestionsOff } }

    [pscustomobject]@{ Id = 'searchweb'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'Поиск Windows без Bing'
        Desc = 'Поиск в «Пуске» показывает только локальные файлы и приложения — без веб-результатов и Cortana.'
        Apply = { Invoke-SearchWebOff }; Undo = { Undo-SearchWebOff } }

    [pscustomobject]@{ Id = 'bgappsglobal'; Group = 'clean'; Risk = $false; Default = $true
        Name = 'Ограничить фоновые приложения'
        Desc = 'Глобально запрещает приложениям работать в фоне. Steam и RUST запускаются как обычно.'
        Apply = { Invoke-BgAppsGlobal }; Undo = { Undo-BgAppsGlobal } }

    [pscustomobject]@{ Id = 'transparency'; Group = 'sys'; Risk = $false; Default = $false
        Name = 'Отключить прозрачность Windows'
        Desc = 'Убирает прозрачные эффекты панели задач и меню — меньше работы для GPU и видеопамяти.'
        Apply = { Invoke-TransparencyOff }; Undo = { Undo-TransparencyOff } }

    [pscustomobject]@{ Id = 'autoplay'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'Отключить AutoPlay / AutoRun'
        Desc = 'Съёмные носители больше не запускают окна автовоспроизведения и не выполняют autorun-скрипты.'
        Apply = { Invoke-AutoPlayOff }; Undo = { Undo-AutoPlayOff } }

    [pscustomobject]@{ Id = 'stickykeys'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'Защита от случайного залипания клавиш'
        Desc = 'Отключает горячие клавиши Sticky/Filter/Toggle Keys — Shift ×5 больше не блокирует управление в игре.'
        Apply = { Invoke-StickyKeysOff }; Undo = { Undo-StickyKeysOff } }

    [pscustomobject]@{ Id = 'windowedopt'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'Оптимизации оконных игр Windows 11'
        Desc = 'SwapEffectUpgrade для DirectX: меньше задержка и разрывы в оконном/безрамочном режиме. Обратимо.'
        Apply = { Invoke-WindowedOpt }; Undo = { Undo-WindowedOpt } }

    [pscustomobject]@{ Id = 'storagesense'; Group = 'sys'; Risk = $false; Default = $true
        Name = 'Пауза Storage Sense'
        Desc = 'Windows не запускает фоновую автоочистку диска во время игры — меньше микрофризов на SSD/HDD.'
        Apply = { Invoke-StorageSenseOff }; Undo = { Undo-StorageSenseOff } }
)

# Восстанавливаем выбор пользователя между запусками
$savedEnabled = $script:State['Enabled']
foreach ($t in $script:Tweaks) {
    $v = [bool]$t.Default
    if ($savedEnabled -is [hashtable] -and $savedEnabled.ContainsKey($t.Id)) {
        $v = [bool]$savedEnabled[$t.Id]
    }
    $script:Enabled[$t.Id] = $v
}

# ============================================================
#  ОРКЕСТРАЦИЯ
# ============================================================
function New-RestorePoint {
    Set-Status 'Создание точки восстановления…' '#E3B341'
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description 'RUST Performance Suite' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Log 'Точка восстановления создана' 'ok'
    } catch {
        $msg = $_.Exception.Message
        if ($msg -match '1440|already|уже') {
            Write-Log 'Точка восстановления уже создавалась за последние 24 часа — пропускаю' 'warn'
        } else {
            Write-Log "Точка восстановления недоступна: $msg" 'warn'
        }
    }
}

function Add-Applied {
    param([string]$Id)
    $a = @($script:State['Applied'])
    if ($a -notcontains $Id) { $a += $Id; $script:State['Applied'] = $a }
}

function Get-AppliedTweaks {
    $applied = @($script:State['Applied'])
    return @($script:Tweaks | Where-Object { $applied -contains $_.Id })
}

function Start-Optimization {
    $list = @($script:Tweaks | Where-Object { $script:Enabled[$_.Id] })
    if ($list.Count -eq 0) { return 0 }

    Set-Busy $true
    try {
        Write-Log ('Запуск оптимизации: модулей — ' + $list.Count) 'step'
        # Эталон клиента до любых действий: после оптимизации сравним.
        try { $null = Save-ClientGuardBaseline } catch {}
        New-RestorePoint
        Backup-RegKey 'HKCU:\Control Panel\Mouse' 'Mouse.reg'

        $i = 0
        foreach ($t in $list) {
            $i = $i + 1
            Set-Status ('Применение: ' + $t.Name) '#FF8A4C'
            Set-ProgressValue ((($i - 1) / [double]$list.Count) * 100)
            Write-Log ('▶ ' + $t.Name) 'step'
            try {
                $null = & $t.Apply
                Add-Applied $t.Id
            } catch {
                Write-Log ('   ошибка: ' + $_.Exception.Message) 'err'
            }
            Set-ProgressValue (($i / [double]$list.Count) * 100)
            Save-State
        }

        try { Invoke-RustProcessPolish } catch {}
        $script:State['Enabled'] = $script:Enabled
        Save-State
        try {
            $cg = Test-ClientGuard
            if ($cg.State -eq 'ok') {
                Write-Log 'Целостность клиента: RustClient.exe и DLL не изменены' 'ok'
            } elseif ($cg.State -eq 'changed') {
                Write-Log 'ВНИМАНИЕ: файлы клиента отличаются от эталона. Это не действие оптимизатора — проверьте обновление игры/Steam.' 'warn'
            }
        } catch {}
        Set-ProgressValue 100
        Set-Status 'Готово. Перезагрузите ПК для полного эффекта.' '#4ECB71'
        Write-Log 'Оптимизация завершена' 'ok'
    } finally {
        Set-Busy $false
    }
    return $list.Count
}

function Start-Rollback {
    Set-Busy $true
    try {
        $applied = @(Get-AppliedTweaks)
        Write-Log ('Откат изменений: модулей — ' + $applied.Count) 'step'
        [array]::Reverse($applied)
        $i = 0
        foreach ($t in $applied) {
            $i = $i + 1
            Set-ProgressValue (($i / [double][Math]::Max(1, $applied.Count)) * 100)
            Write-Log ('↩ ' + $t.Name) 'info'
            try { $null = & $t.Undo } catch { Write-Log ('   ошибка отката: ' + $_.Exception.Message) 'warn' }
        }
        $script:State['Applied'] = @()
        Save-State
        Set-ProgressValue 100
        Set-Status 'Откат выполнен' '#4ECB71'
        Write-Log 'Откат завершён. Для 100% чистоты используйте точку восстановления.' 'ok'
    } finally {
        Set-Busy $false
    }
}

# ============================================================
#  RUST ОДНОЙ КНОПКОЙ: ТРАВА + БИНДЫ
# ============================================================
function Invoke-RustOneClick {
    if (-not $script:RustExe) {
        return 'RUST не найден автоматически. Запустите игру через Steam один раз и повторите.'
    }
    $cfgLines = Get-RustCfgCommandText
    $bindLines = Get-BindCommandLines
    $all = @()
    $all += $cfgLines
    $all += $bindLines

    if (Test-RustRunning) {
        $ok = Copy-Text ($all -join "`r`n")
        if ($ok) {
            Write-Log 'Rust запущен — команды скопированы в буфер обмена' 'warn'
            return "RUST сейчас запущен, поэтому файлы cfg трогать нельзя (игра перезапишет их при выходе).`n`nКоманды скопированы в буфер обмена. Откройте в игре консоль (F1) и вставьте их (Ctrl+V), затем нажмите Enter."
        }
        return 'RUST запущен. Закройте игру и повторите, либо примените команды вручную через F1.'
    }

    $dir = Get-RustCfgDir
    if (-not $dir) { return 'Не удалось открыть папку cfg игры.' }

    try { $null = Save-ClientGuardBaseline } catch {}
    $wroteCfg = $false
    $wroteBinds = $false
    $errors = @()
    if ($cfgLines.Count -gt 0) {
        try { $null = Invoke-RustCfg; $wroteCfg = $true }
        catch { $errors += ('client.cfg: ' + $_.Exception.Message); Write-Log ('cfg: ' + $_.Exception.Message) 'warn' }
    }
    if ($bindLines.Count -gt 0) {
        try { Apply-RustBinds -Quiet; $wroteBinds = $true }
        catch { $errors += ('keys.cfg: ' + $_.Exception.Message); Write-Log ('бинды: ' + $_.Exception.Message) 'warn' }
    }
    if ($wroteCfg -or $wroteBinds) { Add-Applied 'rustcfg'; Save-State }
    try {
        $cg = Test-ClientGuard
        if ($cg.State -eq 'ok') { Write-Log 'Целостность клиента после cfg/биндов: файлы не изменены' 'ok' }
    } catch {}

    $cfgCount = if ($wroteCfg) { @($cfgLines).Count } else { 0 }
    $bindCount = if ($wroteBinds) { @($bindLines).Count } else { 0 }
    Write-Log ('Rust: применено строк cfg — ' + $cfgCount + ', биндов — ' + $bindCount) 'ok'
    if ($errors.Count -gt 0) {
        return ("Частично готово.`n`nclient.cfg: " + $cfgCount + " строк`nkeys.cfg: " + $bindCount + " биндов`n`nНе удалось:`n- " + ($errors -join "`n- ") + "`n`nБэкапы: " + $script:RustBackup)
    }
    return ("Готово.`n`nclient.cfg: " + $cfgCount + " строк`nkeys.cfg: " + $bindCount + " биндов`n`nБэкапы: " + $script:RustBackup)
}

function Invoke-RustConsoleCopy {
    $all = @()
    $all += Get-RustCfgCommandText
    $all += Get-BindCommandLines
    if ($all.Count -eq 0) { return 'Нет команд для копирования.' }
    $ok = Copy-Text (($all -join "`r`n") + "`r`n")
    if ($ok) {
        Write-Log 'Команды Rust скопированы в буфер обмена' 'ok'
        return "Команды скопированы.`n`nВ игре нажмите F1, вставьте (Ctrl+V) и нажмите Enter."
    }
    return 'Не удалось скопировать в буфер обмена.'
}

# ============================================================
#  ОКРУЖЕНИЕ (нужно и для SELFTEST, и для интерфейса)
# ============================================================
$script:SteamPath   = Find-SteamPath
$script:RustExe     = Find-RustExe
$script:RustCfgDir  = $null
$script:IsAdmin     = Test-Admin
$script:RustRunning = Test-RustRunning
$script:RustInfo    = Get-RustClientInfo
