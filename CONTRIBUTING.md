# Участие в проекте

## Требования

- Windows 10/11
- Windows PowerShell 5.1 (встроен)
- Права администратора для полной проверки функций

## Как собрать

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\rebuild-bat.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\RustOptimizer.ps1 -SelfTest
```

`src\RustOptimizer.ps1` генерируется автоматически — не редактируйте его вручную. Правьте файлы в `src\parts\`.

## Правила кода

- PowerShell 5.1, без внешних зависимостей.
- Не добавляйте модули, изменяющие `exe`/`dll` Rust или внедряющиеся в процесс.
- Новый модуль: реализация в `10_modules.ps1`, запись в списке `$script:Tweaks` в `20_tweaks.ps1`, при необходимости — откат.
- Все пользовательские строки — на русском, комментарии — по делу.
- Перед PR: `-SelfTest` должен выводить `SELFTEST OK`.

## Сообщения об ошибках

Приложите:

1. версию Windows;
2. лог `%ProgramData%\RustOptimizer\rust-optimizer.log`;
3. шаги воспроизведения;
4. вывод `-SelfTest`.

## Лицензия вкладов

Отправляя PR, вы соглашаетесь распространять код под MIT License.
