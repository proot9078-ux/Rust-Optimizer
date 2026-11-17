# Участие в проекте

## Требования

- Windows 10/11 x64
- CMake 3.21+ и любой из тулчейнов: MSVC 2022+ (Visual Studio Build Tools) или MinGW-w64 (GCC 13+)
- Права администратора для полной проверки системных функций

## Как собрать

```powershell
cmake -S . -B build -DRO_BUILD_TESTS=ON
cmake --build build --config Release --parallel
ctest --test-dir build -C Release --output-on-failure
.\build\Release\RustOptimizer.exe --selftest
```

MinGW:

```powershell
cmake -S . -B build -G "MinGW Makefiles" -DRO_BUILD_TESTS=ON
cmake --build build -j 8
.\build\ro_tests.exe
```

## Правила кода

- C++20, Win32 + Direct2D/DirectWrite, без сторонних UI-фреймворков.
- Никакого внедрения в процессы, хуков и правки `exe`/`dll` игр — только внешние
  настройки (файлы конфигов, приоритет, affinity, очистка standby-списка).
- Новый твик: структура опций в `include/ro/*.hpp`, применение в
  `src/tweaks/*.cpp`, строка в `src/ui/pages.cpp`, обработчик в
  `src/ui/app_window.cpp` и тест в `tests/`.
- Пользовательские строки — на русском, файлы в UTF-8.
- Обновления обязательные: не добавляйте переключатель «не проверять».
- Перед PR: `ctest` зелёный, `--selftest` работает, MSVC `/W4 /WX` без
  предупреждений (это проверяет CI).

## Сообщения об ошибках

Приложите:

1. версию Windows и версию Rust Optimizer (`--version`);
2. лог из `%LOCALAPPDATA%\RustOptimizer\logs`;
3. шаги воспроизведения;
4. вывод `--selftest`.

## Лицензия вкладов

Отправляя PR, вы соглашаетесь распространять код под MIT License.
