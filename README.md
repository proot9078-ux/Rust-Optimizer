# PURPLE RUSH — RUST PERFORMANCE ENGINE

[![CI](https://github.com/proot9078-ux/Rust-Optimizer/actions/workflows/ci.yml/badge.svg)](https://github.com/proot9078-ux/Rust-Optimizer/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)
[![PowerShell 5.1](https://img.shields.io/badge/PowerShell-5.1-blue.svg)](https://learn.microsoft.com/powershell/)

<p align="center">
  <img src="assets/app-icon.png" width="144" alt="PURPLE RUSH icon">
</p>

Открытый оптимизатор Windows под игру **RUST** с глубокой очисткой, диагностикой и восстановлением системы. Полностью читаемый исходный код, без обфускации, скрытых бинарников и «магических» твиков.

> **Версия 4.0** · 47 модулей · 10 анимированных тем · отдельная страница ремонта Windows.

---

## Что нового в 4.0

- **Windows Care Engine** — 10 новых модулей очистки: кэш обновлений, дампы и WER, кэш браузеров, логи Steam/RUST, эскизы, WinSxS, `Windows.old`, Prefetch, журналы событий и глубокая очистка одной кнопкой.
- **Страница «РЕМОНТ»** — проверка здоровья Windows и запуск штатных инструментов: SFC, DISM RestoreHealth / ComponentCleanup / Analyze, CHKDSK `/scan`, сброс Windows Update и сети, лечение WMI, сброс Store, пересборка кэша иконок, синхронизация времени, пересканирование драйверов, очередь печати, точка восстановления.
- **Диагностика в один клик** — 15 проверок: права, uptime, ожидание перезагрузки, место на диске, SMART, WMI, службы обновления и времени, устройства с ошибками, события за 7 дней, дампы, TEMP, кэш обновлений, защита системы, сетевые адаптеры. Отчёт копируется в буфер обмена.
- **10 тем** с живыми градиентами и анимацией: PURPLE RUSH, MIDNIGHT, EMERALD, CRIMSON, CYBERPUNK, ROYAL GOLD, ARCTIC, SAKURA, OBSIDIAN, TOXIC.
- **Новый интерфейс** — 7 разделов навигации, диск в панели состояния, кнопка «ДИАГНОСТИКА» в подвале, глубокая очистка на странице «ОЧИСТКА», анимированные плитки тем и строки здоровья.
- **Иконка и ярлык** — фирменная иконка `assets\rust-optimizer.ico` (16–256 px) и установщик ярлыка на рабочий стол и в меню «Пуск».
- **Больше самопроверок** — `-SelfTest` проверяет новые контролы, движки очистки, функции ремонта, иконку и безопасное удаление файлов.

## Возможности

### Система

- План питания и точный таймер 1 мс на время работы программы.
- Приоритеты процессов, MMCSS, Game Mode, Game DVR / Xbox Game Bar.
- HAGS, Power Throttling, парковка ядер, QoS для игрового процесса.
- Отключение телеметрии, P2P-раздачи Delivery Optimization и лишних фоновых служб.
- Дополнительно: глобальные оптимизации полного экрана (FSE), службы Xbox, быстрый запуск Windows.

### Сеть

- Отключение алгоритма Nagle, TCP-стек под игры, QoS.
- Энергосбережение сетевого адаптера, сброс DNS-кэша.
- Смена DNS-серверов с честным откатом.

### RUST

- Официальные переменные `cfg\client.cfg`: трава, тени, качество, дистанция, сглаживание.
- Профиль игры, приоритет процесса, affinity, GPU-параметры.
- Редактор официального `cfg\keys.cfg` с готовыми пресетами.
- Запуск RUST через Steam с ожиданием `RustClient.exe`.
- Безопасность: exe/dll игры не изменяются, в процесс ничего не внедряется.

### Очистка Windows

| Модуль | Что делает |
|---|---|
| `deepclean` | Глубокая очистка: TEMP, Windows Temp, кэш обновлений, дампы, браузеры, Steam/RUST, эскизы, старые логи |
| `updatecache` | Кэш Windows Update и Delivery Optimization |
| `dumps` | Дампы, WER, `MEMORY.DMP`, `LiveKernelReports` |
| `browsercache` | Только Cache/Code Cache/GPUCache и Service Worker cache; пароли и история не трогаются |
| `gamejunk` | Логи и `*.dmp` Steam/RUST; `cfg` и сохранения остаются на месте |
| `thumbcache` | `thumbcache_*.db` и `iconcache_*.db`; занятые файлы пропускаются |
| `winsxs` | Безопасный `DISM /StartComponentCleanup` |
| `oldwindows` | `Windows.old`, `$Windows.~BT`, `$Windows.~WS`, `$WinREAgent` |
| `prefetchclean` | Prefetch и ReadyBoot |
| `eventlogs` | Очистка журналов событий Windows |

Все новые модули очистки **по умолчанию выключены**. Опасные действия (`oldwindows`, `eventlogs`, отключение служб) требуют явного включения и подтверждения.

### Ремонт и диагностика

- `SFC /scannow`, `DISM /RestoreHealth`, `DISM /StartComponentCleanup`, `DISM /AnalyzeComponentStore`.
- `CHKDSK /scan` без перезагрузки.
- Сброс Windows Update (службы + `SoftwareDistribution` + `Catroot2`).
- Сброс Winsock/TCP-IP/DNS, лечение WMI, сброс Microsoft Store.
- Пересборка кэша иконок, синхронизация времени, `pnputil /scan-devices`, сброс очереди печати.
- Точка восстановления по кнопке; перед основной оптимизацией создаётся автоматически.

### Интерфейс

- 10 палитр, плитки тем с живым градиентом и бликом.
- Двойная буферизация, пакетная перерисовка страниц, плавная прокрутка колесом.
- Анимированные карточки модулей, строки диагностики, прогресс и спиннер.
- Панель состояния: CPU, ОЗУ, свободное место на системном диске, статус RUST.
- Отчёт о системе и отчёт о здоровье Windows — в буфер обмена.
- Автозакрытие после запуска RUST (можно отключить).

## Темы

`PURPLE RUSH` · `MIDNIGHT` · `EMERALD` · `CRIMSON` · `CYBERPUNK` · `ROYAL GOLD` · `ARCTIC` · `SAKURA` · `OBSIDIAN` · `TOXIC`

Тема применяется сразу и сохраняется в `%ProgramData%\RustOptimizer\state.xml`. Кнопка «СЛУЧАЙНАЯ ТЕМА» выбирает любую палитру, кроме текущей.

## Иконка и ярлык

Windows не позволяет встроить иконку в `.bat`, поэтому используется `.lnk`-ярлык:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\install-shortcut.ps1
```

Скрипт создаёт:

- `PURPLE RUSH.lnk` на рабочем столе;
- `PURPLE RUSH.lnk` в меню «Пуск» (отключить: `-DesktopOnly`);
- ярлык запускает `RustOptimizer.bat`, рабочая папка и иконка задаются автоматически.

Иконку можно пересобрать:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\make-icon.ps1
```

## Требования

- Windows 10/11.
- Встроенный Windows PowerShell 5.1.
- Права администратора для полной проверки и ремонта. Без прав интерфейс работает, но часть операций будет недоступна.
- Для SFC/DISM/CHKDSK/WMI и сброса сети нужен администратор.

## Запуск

```bat
:: ПКМ -> Запуск от имени администратора (рекомендуется)
RustOptimizer.bat
```

Или напрямую:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\RustOptimizer.ps1
```

Самопроверка без интерфейса:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\RustOptimizer.ps1 -SelfTest
```

UI-смоук-тест (окно само пройдёт по разделам и закроется):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\RustOptimizer.ps1 -TestUi
```

## Сборка

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\rebuild-bat.ps1
```

Скрипт:

1. склеивает `src\parts\*.ps1` в `src\RustOptimizer.ps1`;
2. пишет читаемый `RustOptimizer.bat`;
3. собирает одиночный `dist\RustOptimizer-standalone.bat` (base64 payload) для пользователей без папки с исходниками.

Не редактируйте `src\RustOptimizer.ps1` вручную — правьте файлы в `src\parts\`.

## Структура проекта

```text
src/
  parts/
    00_header.ps1       константы, логирование, реестр, поиск Steam/RUST
    10_modules.ps1      реализации модулей оптимизации
    15_cleaner.ps1      движок безопасной очистки Windows
    16_repair.ps1       SFC/DISM/CHKDSK/WMI и восстановление
    18_diagnostics.ps1  проверки здоровья Windows и быстрые исправления
    20_tweaks.ps1       список 47 модулей, Start-Optimization / Start-Rollback
    30_controls.ps1     темы и анимированные контролы (C#)
    35_selftest.ps1     самопроверка
    39_settings.ps1     10 тем, отчёт о системе, мониторинг
    40_ui.ps1           окно, навигация, карточки, бинды
    45_repair_ui.ps1    страница «РЕМОНТ И ДИАГНОСТИКА»
    50_actions.ps1      кнопки, таймеры, перезагрузка
  RustOptimizer.ps1     собранный исходник (генерируется)
RustOptimizer.bat       читаемый лаунчер для GitHub
rebuild-bat.ps1         сборка src + лаунчер + standalone
assets/                 app-icon.png и multiresolution .ico
tools/                  make-icon.ps1, install-shortcut.ps1
docs/SAFETY.md          что чистится, риски ремонта и откат
dist/                   одиночный .bat (создаётся при сборке, в git не входит)
.github/workflows/ci.yml сборка, синтаксис и SelfTest в CI
```

## Группы модулей

| Группа | Модулей | Назначение |
|---|---:|---|
| Система | 22 | питание, приоритеты, службы, телеметрия, FSE, Xbox, быстрый запуск |
| Сеть | 5 | Nagle, TCP, QoS, DNS, энергосбережение адаптера |
| RUST | 6 | cfg, приоритет, affinity, GPU, запуск |
| Очистка | 14 | TEMP, кэши, дампы, Steam/RUST, WinSxS, журналы |
| **Всего** | **47** | + официальные бинды `keys.cfg` |

## Безопасность и EAC

Программа **не** изменяет `RustClient.exe` / `*.dll`, не внедряется в процесс, не эмулирует ввод, не использует оверлеи. Работает только с официальными файлами `cfg\` и стандартными средствами Windows.

> Полностью убрать траву официальными настройками нельзя — это меняет баланс игры. Модуль использует только документированные конвары клиента. Шейдеры и моды, вырезающие траву, не поддерживаются: это вмешательство в клиент и риск бана.

Перед оптимизацией создаётся точка восстановления и резервные копии реестра. Откат восстанавливает применённые модули, но лучший «откат всего» — точка восстановления Windows.

Подробно о путях очистки, рисках ремонта и откате: [docs/SAFETY.md](docs/SAFETY.md).

## Ограничения

- Диагностика и ремонт — это стандартные проверки Windows, а не гарантия исправления любой ошибки.
- SFC, DISM и CHKDSK могут занимать 10–30 минут; окно закрывать не нужно.
- ACPI-температура доступна не на всех ПК; Windows не отдаёт температуру ядер CPU/GPU без фирменного драйвера.
- Некоторые операции (сброс сети, пересборка иконок, очистка WinSxS) требуют перезагрузки или перезапуска Explorer.
- Значения реестра и служб могут отличаться на разных сборках Windows; откат возвращает сохранённые исходные значения там, где это предусмотрено.

## Участие

См. [CONTRIBUTING.md](CONTRIBUTING.md). PR и issues приветствуются.

## Лицензия

[MIT](LICENSE) © 2026 PURPLE RUSH contributors.
