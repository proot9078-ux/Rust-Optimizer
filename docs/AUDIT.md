# Аудит старой версии и отчёт о переписывании (8.0)

## 1. Что было в репозитории

Фактический стек предыдущих версий — **PowerShell 5.1 + WinForms**, а не Rust:

| Файл | Размер | Комментарий |
|---|---|---|
| `src/RustOptimizer.ps1` | ~682 КБ | монолит: UI, твики, selftest, обновление |
| `src/parts/*.ps1` | 12+ частей | сборка скрипта из фрагментов (`rebuild-bat.ps1`) |
| `tools/make-icon.ps1` | — | иконка из PNG |
| `.github/workflows/ci.yml` | — | только парсинг PS-синтаксиса |

Отдельного Rust-кода в репозитории нет; название проекта («Rust Optimizer»)
относится к игре RUST. Поэтому переписывание выполнено с нуля на C++20, а
PowerShell-исходники оставлены в репозитории как исторический материал и **не
входят в релизные артефакты**.

## 2. Найденные проблемы старой реализации

| # | Проблема | Последствие | Как исправлено в 8.0 |
|---|---|---|---|
| 1 | 598 пустых `catch {}` | ошибки проглатывались, пользователь видел «успех» | каждое действие возвращает отчёт (`ApplyReport`), ошибки идут в лог и статус |
| 2 | Нет реального повышения прав (`Test-Admin` упоминается 2 раза, `runas` отсутствует) | standby purge и часть твиков молча не работали | явный `win::is_admin()`, кнопка «Запустить от админа», статус в сайдбаре, `ShellExecuteW ... runas` |
| 3 | Захардкоженные пути Steam (`C:\Program Files (x86)\Steam`, `D:\Steam`, …) | игра на другом диске не находилась | реестр + `libraryfolders.vdf` + `appmanifest_252490.acf` + кэш с валидацией |
| 4 | RUST искался без проверки `appmanifest_252490.acf` | ложные срабатывания на пустых папках | проверка манифеста и фактического `.exe` |
| 5 | Нет очистки standby-списка (`NtSetSystemInformation` отсутствует) | заявленная функция не существовала | `mem::purge_standby_list()` + привилегия `SeProfileSingleProcessPrivilege` |
| 6 | Нет affinity (`GetSystemCpuSetInformation`/`SetProcessAffinityMask` отсутствуют) | P/E-core и X3D не учитывались | `cpu::detect()` + `recommended_mask()` + `proc::set_affinity()` |
| 7 | Нет самообновления (`api.github.com` отсутствует) | обновление вручную | WinHTTP + GitHub Releases + SHA256 + helper-подмена `.exe` |
| 8 | Нет релизной автоматизации | релизы вручную | workflow `build.yml` + `tools/release.ps1` |
| 9 | Один гигантский скрипт | невозможно тестировать | модули `ro_core` + Catch2-тесты |
| 10 | UI на WinForms, фиксированный DPI | размытие на 125–200 % | Direct2D + PerMonitorV2 + масштабирование |

## 3. Архитектура 8.0

```text
main.cpp ──► ui::run ──► App (Win32 + Direct2D)
                 │          ├── pages.cpp   (модель страниц/строк)
                 │          ├── widgets.cpp (Painter: карточки, toggle, progress)
                 │          └── worker thread (detect/apply/update)
                 ├── tweaks::rust / fortnite / system
                 ├── games::steam / epic / finder
                 ├── net::http (WinHTTP) / zip (miniz) / updater
                 └── core: str, fs, json, log, win32, process, affinity,
                           memory, sha256, settings, hardware, backup
```

Ключевые инварианты:

* никакой инъекции, хуков и чтения памяти игры;
* приоритет максимум `HIGH_PRIORITY_CLASS`;
* `system()` не используется, только `CreateProcessW` + `CREATE_NO_WINDOW`;
* сеть — только проверка обновлений (отключаемая) и загрузка обновления по
  подтверждению;
* все изменения файлов предваряются бэкапом, твики INI — в маркерных блоках.

## 4. Проверка

| Проверка | Статус |
|---|---|
| Сборка MinGW-w64 GCC 16.2 (локально) | ✅ `ro_icon_gen`, `RustOptimizer`, `ro_tests` линкуются |
| `ro_tests` (Catch2) | ✅ см. вывод `ctest` |
| `RustOptimizer.exe --version` / `--selftest` | ✅ smoke-тест в CI |
| MSVC `/W4 /permissive- /WX` | ⏳ проверяется workflow `build.yml` на `windows-latest` (локально MSVC отсутствует) |
| Чистая Windows 10 1607+/11 x64 | ⏳ проверяется на релизном артефакте |

Локальная машина разработки не содержит Visual Studio C++ workload и Windows
SDK, поэтому соответствие требованиям MSVC подтверждается CI, а не локальной
сборкой. MinGW-сборка используется как быстрый функциональный прогон.

## 5. Ограничения и заметки

* Очистка standby-списка требует прав администратора; без них переключатель
  возвращает понятную ошибку, остальные функции работают.
* Fortnite создаёт `GameUserSettings.ini` только после первого запуска; при
  отсутствии файлов приложение пишет об этом в лог, а не создаёт пустышку.
* Самообновление подменяет только `RustOptimizer.exe`; данные пользователя в
  `%LOCALAPPDATA%\RustOptimizer` сохраняются.
* `.rop`-профили не содержат путей и не переносят бэкапы — только значения
  переключателей.
