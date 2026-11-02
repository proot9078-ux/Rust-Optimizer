# PURPLE RUSH — RUST PERFORMANCE ENGINE

[![CI](https://github.com/USER/rust-optimizer/actions/workflows/ci.yml/badge.svg)](https://github.com/USER/rust-optimizer/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

Открытый оптимизатор Windows под игру **RUST**. Полностью читаемый исходный код, без обфускации и скрытых бинарников.

---

## Возможности

- **Система**: план питания, приоритеты процессов, отключение Game DVR / Xbox Game Bar, фоновых служб, P2P-раздачи Delivery Optimization, сетевые параметры (TCP NoDelay, TcpAckFrequency, QoS).
- **Сеть**: отключение алгоритма Nagle, TCP-стек под игры, сброс DNS-кэша, отключение энергосбережения сетевого адаптера.
- **Таймер**: точный системный таймер 1 мс на время работы программы и разрешение точных таймеров в Windows.
- **RUST**: официальные переменные `cfg\client.cfg` — трава (`grass.displacement`, `grass.shadow.onlyself`, `grass.distance`), тени, качество, дистанция прорисовки, сглаживание.
- **Бинды**: редактор официального `cfg\keys.cfg` + готовые пресеты.
- **Очистка**: временные файлы, кэш шейдеров DirectX (D3D/NVIDIA/AMD/Intel), корзина, лишние фоновые процессы.
- **Мониторинг**: загрузка CPU и ОЗУ в реальном времени, ACPI-температура (если датчик поддерживается), модель GPU.
- **Отчёт о системе**: ОС, CPU, GPU, ОЗУ, права и пути Steam/RUST — одной кнопкой в буфер обмена.
- **4 темы оформления**: Пурпурная, Тёмно-синяя, Изумрудная, Кримсон. Переключаются мгновенно.
- **Плавный интерфейс**: двойная буферизация, пакетная перерисовка страниц, плавная прокрутка колесом (работает и над навигацией), анимация карточек, акцентные заголовки страниц.
- **Автоперезагрузка** после успешной оптимизации (с подтверждением, откладывается по «Отмена»).
- **Откат**: резервные копии реестра и `cfg`, восстановление применённых модулей; у новых модулей есть честный откат исходных значений.

## Безопасность и EAC

Программа **не** изменяет `RustClient.exe` / `*.dll`, не внедряется в процесс, не эмулирует ввод, не использует оверлеи. Работает только с официальными файлами `cfg\` и стандартными средствами Windows. Это не даёт преимуществ, которые EAC считает читерскими.

> Полностью убрать траву официальными настройками нельзя — это меняет баланс и запрещено. Модуль использует только документированные конвары клиента.

## Запуск

```bat
:: ПКМ -> Запуск от имени администратора (рекомендуется)
RustOptimizer.bat
```

Или напрямую:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\RustOptimizer.ps1
```

Самопроверка без запуска интерфейса:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\RustOptimizer.ps1 -SelfTest
```

## Структура проекта

```
src/
  parts/
    00_header.ps1    константы, логирование, реестр, поиск Steam/Rust
    10_modules.ps1   реализации модулей оптимизации
    20_tweaks.ps1    список модулей, Start-Optimization / Start-Rollback
    30_controls.ps1  тема и анимированные контролы (C#)
    35_selftest.ps1  самопроверка и тест слияния cfg
    39_settings.ps1  панель настроек: темы, отчёт о системе, мониторинг
    40_ui.ps1        окно, навигация, карточки, бинды
    50_actions.ps1   кнопки, таймеры, перезагрузка
  RustOptimizer.ps1  собранный исходник (генерируется)
RustOptimizer.bat    читаемый лаунчер (для GitHub)
rebuild-bat.ps1      сборка src + лаунчер + standalone
dist/                одиночный .bat (создаётся при сборке, в git не входит)
```

## Сборка

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\rebuild-bat.ps1
```

Скрипт:

1. склеивает `src\parts\*.ps1` в `src\RustOptimizer.ps1`;
2. пишет читаемый `RustOptimizer.bat`;
3. собирает одиночный `dist\RustOptimizer-standalone.bat` (base64 payload) для пользователей без папки с исходниками.

## Публикация на GitHub

```bash
git init
git add .
git commit -m "PURPLE RUSH v3.1"
git branch -M main
git remote add origin https://github.com/ВАШ_ЛОГИН/rust-optimizer.git
git push -u origin main
```

Замените `USER` в бейдже CI в начале README и в `.github/workflows/ci.yml` на свой логин.

## Участие

См. [CONTRIBUTING.md](CONTRIBUTING.md). PR и issues приветствуются.

## Лицензия

[MIT](LICENSE) © 2026 PURPLE RUSH contributors.
