cmake_minimum_required(VERSION 3.21)

project(RustOptimizer
        VERSION 8.2.2
        DESCRIPTION "Rust Optimizer - external performance engine for RUST and FORTNITE"
        LANGUAGES C CXX RC)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

option(RO_BUILD_TESTS "Build unit tests" ON)
option(RO_WARNINGS_AS_ERRORS "Treat warnings as errors" OFF)

# ---------------------------------------------------------------------------
# Single self-contained .exe: statically linked CRT.
# ---------------------------------------------------------------------------
if(MSVC)
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
else()
  add_link_options(-static -static-libgcc -static-libstdc++)
endif()

# ---------------------------------------------------------------------------
# Warnings: MSVC /W4 (as required by the spec), GCC/Clang -Wall -Wextra.
# ---------------------------------------------------------------------------
function(ro_set_warnings target)
  if(MSVC)
    target_compile_options(${target} PRIVATE /W4 /permissive- /utf-8 /Zc:__cplusplus)
    if(RO_WARNINGS_AS_ERRORS)
      target_compile_options(${target} PRIVATE /WX)
    endif()
  else()
    target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic)
    if(RO_WARNINGS_AS_ERRORS)
      target_compile_options(${target} PRIVATE -Werror)
    endif()
  endif()
endfunction()

set(RO_VERSION_STRING "${PROJECT_VERSION}")

# ---------------------------------------------------------------------------
# Third-party (vendored, no network needed at configure/build time)
# ---------------------------------------------------------------------------
add_library(ro_thirdparty STATIC
    third_party/miniz.c
    third_party/miniz_tdef.c
    third_party/miniz_tinfl.c
    third_party/miniz_zip.c)
target_include_directories(ro_thirdparty PUBLIC third_party)
if(MSVC)
  target_compile_options(ro_thirdparty PRIVATE /W0)
else()
  target_compile_options(ro_thirdparty PRIVATE -w)
endif()

# ---------------------------------------------------------------------------
# Core library (everything except WinMain) so tests can link it directly.
# ---------------------------------------------------------------------------
set(RO_CORE_SOURCES
    src/core/str.cpp
    src/core/fs.cpp
    src/core/json.cpp
    src/core/log.cpp
    src/core/win32.cpp
    src/core/shortcut.cpp
    src/core/backup.cpp
    src/core/process.cpp
    src/core/affinity.cpp
    src/core/memory.cpp
    src/core/sha256.cpp
    src/core/settings.cpp
    src/core/hardware.cpp
    src/core/cleaner.cpp
src/core/tuning.cpp
    src/core/diagnostics.cpp
    src/core/visuals.cpp
    src/core/win_repair.cpp
    src/games/steam.cpp
    src/games/steam_launch.cpp
    src/games/epic.cpp
    src/games/game_finder.cpp
    src/tweaks/ini.cpp
    src/tweaks/rust_tweaks.cpp
    src/tweaks/fortnite_tweaks.cpp
    src/tweaks/system_tweaks.cpp
    src/tweaks/profiles.cpp
    src/net/http.cpp
    src/net/zip.cpp
    src/net/updater.cpp
    src/icon.cpp)

add_library(ro_core STATIC ${RO_CORE_SOURCES})
target_include_directories(ro_core PUBLIC include)
target_link_libraries(ro_core PUBLIC ro_thirdparty winhttp dwrite d2d1 gdiplus gdi32 user32 ole32 shell32 advapi32 psapi dnsapi version winmm powrprof)
target_compile_definitions(ro_core PUBLIC
    UNICODE _UNICODE
    WIN32_LEAN_AND_MEAN
    NOMINMAX
    RO_VERSION="${RO_VERSION_STRING}"
    RO_GITHUB_OWNER="proot9078-ux"
    RO_GITHUB_REPO="Rust-Optimizer")
ro_set_warnings(ro_core)

# ---------------------------------------------------------------------------
# Icon generator: the .ico is produced programmatically during the build,
# no binary asset is stored in the repository.
# ---------------------------------------------------------------------------
add_executable(ro_icon_gen tools/gen_icon.cpp)
target_include_directories(ro_icon_gen PRIVATE include third_party)
target_link_libraries(ro_icon_gen PRIVATE ro_core)
target_compile_definitions(ro_icon_gen PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX RO_VERSION="${RO_VERSION_STRING}")
if(NOT MSVC)
  # wmain() needs the unicode CRT entry point when linking with MinGW.
  target_link_options(ro_icon_gen PRIVATE -municode)
endif()
ro_set_warnings(ro_icon_gen)

set(RO_ICON_FILE "${CMAKE_CURRENT_BINARY_DIR}/generated/app.ico")
add_custom_command(
    OUTPUT "${RO_ICON_FILE}"
    COMMAND ro_icon_gen "${RO_ICON_FILE}"
    DEPENDS ro_icon_gen
    COMMENT "Generating application icon"
    VERBATIM)
add_custom_target(ro_icon DEPENDS "${RO_ICON_FILE}")

# ---------------------------------------------------------------------------
# Application resources: generated from a template so the icon path and the
# version numbers always match the build (no hand-edited .rc in the repo).
# ---------------------------------------------------------------------------
set(RO_MANIFEST_FILE "${CMAKE_CURRENT_SOURCE_DIR}/resources/app.manifest")
set(RO_VERSION_COMMA "${PROJECT_VERSION_MAJOR},${PROJECT_VERSION_MINOR},${PROJECT_VERSION_PATCH},0")
file(TO_CMAKE_PATH "${RO_ICON_FILE}" RO_ICON_FILE_RC)
file(TO_CMAKE_PATH "${RO_MANIFEST_FILE}" RO_MANIFEST_FILE_RC)
if(MSVC)
  # The MSVC linker always embeds its own manifest as resource 1; adding a
  # second RT_MANIFEST with the same id fails with CVT1100. Instead the linker
  # merges our DPI/v2 manifest with its default one via /MANIFESTINPUT.
  set(RO_MANIFEST_RESOURCE "")
else()
  # MinGW's ld already adds a default manifest; a second one is a link error.
  set(RO_MANIFEST_RESOURCE "")
endif()
configure_file(resources/app.rc.in "${CMAKE_CURRENT_BINARY_DIR}/app.rc" @ONLY)

# ---------------------------------------------------------------------------
# Application
# ---------------------------------------------------------------------------
add_executable(RustOptimizer WIN32
    src/main.cpp
    src/ui/theme.cpp
    src/ui/widgets.cpp
    src/ui/pages.cpp
    src/ui/app_window.cpp
    "${CMAKE_CURRENT_BINARY_DIR}/app.rc")
target_link_libraries(RustOptimizer PRIVATE ro_core)
target_include_directories(RustOptimizer PRIVATE include)
if(MSVC)
  # Merge the PerMonitorV2 manifest into the linker-generated one (see above).
  target_link_options(RustOptimizer PRIVATE "/MANIFESTINPUT:${RO_MANIFEST_FILE}")
endif()
target_compile_definitions(RustOptimizer PRIVATE RO_ICON_PATH="${RO_ICON_FILE}")
set_source_files_properties("${CMAKE_CURRENT_BINARY_DIR}/app.rc" PROPERTIES OBJECT_DEPENDS "${RO_ICON_FILE}")
add_dependencies(RustOptimizer ro_icon)
ro_set_warnings(RustOptimizer)
if(NOT MSVC)
  # wWinMain() needs the unicode CRT startup with MinGW.
  target_link_options(RustOptimizer PRIVATE -municode)
endif()

# Keep the binary small and startup fast.
if(MSVC)
  target_link_options(RustOptimizer PRIVATE /OPT:REF /OPT:ICF /INCREMENTAL:NO)
endif()

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
if(RO_BUILD_TESTS)
  enable_testing()
  add_executable(ro_tests
      tests/test_main.cpp
      tests/test_str.cpp
      tests/test_fs.cpp
      tests/test_ini.cpp
      tests/test_steam.cpp
      tests/test_steam_launch.cpp
      tests/test_updater.cpp
      tests/test_visuals.cpp
    tests/test_cleaner.cpp
    tests/test_rust_options.cpp
tests/test_tuning.cpp
      third_party/catch_amalgamated.cpp)
  target_include_directories(ro_tests PRIVATE include third_party tests)
  target_link_libraries(ro_tests PRIVATE ro_core)
  if(MSVC)
    target_compile_options(ro_tests PRIVATE /W0 /utf-8)
  else()
    target_compile_options(ro_tests PRIVATE -w)
    # Catch2 uses wmain() because the project is compiled with _UNICODE.
    target_link_options(ro_tests PRIVATE -municode)
  endif()
  add_test(NAME unit COMMAND ro_tests --reporter compact)
endif()
