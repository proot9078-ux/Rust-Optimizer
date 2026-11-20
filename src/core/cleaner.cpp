#include "ro/cleaner.hpp"

#include <windows.h>
#include <shellapi.h>

#include <algorithm>
#include <array>
#include <iterator>
#include <string_view>
#include <system_error>

#include "ro/fs.hpp"
#include "ro/log.hpp"
#include "ro/str.hpp"

namespace ro::clean {

namespace {

namespace fs = std::filesystem;

std::wstring env_path(const wchar_t* name) {
    wchar_t buffer[MAX_PATH * 2]{};
    const DWORD n = ::GetEnvironmentVariableW(name, buffer, static_cast<DWORD>(std::size(buffer)));
    if (n == 0 || n >= static_cast<DWORD>(std::size(buffer))) return {};
    return std::wstring(buffer, n);
}

// Folder names that contain nothing but disposable cache data. A target with
// cache_only = true only descends into these.
constexpr std::array<std::wstring_view, 18> kCacheDirs = {
    L"cache",          L"code cache",     L"gpucache",       L"shadercache",
    L"grshadercache",  L"cachestorage",   L"service worker", L"scriptcache",
    L"dawncache",      L"graphitedawncache", L"component_crx_cache",
    L"extensions_crx_cache", L"media cache", L"startupcache", L"cache2",
    L"shader-cache",   L"thumbnails",     L"offlinecache",
};

bool is_cache_dir(std::wstring_view name) {
    for (const auto dir : kCacheDirs) {
        if (str::iequals(name, dir)) return true;
    }
    return false;
}

// path inside `root` (the file name excluded) walks upwards until root.
bool in_cache_subdir(const fs::path& root, const fs::path& file) {
    fs::path parent = file.parent_path();
    while (!parent.empty() && parent != root && parent != parent.root_path()) {
        if (is_cache_dir(parent.filename().wstring())) return true;
        const auto up = parent.parent_path();
        if (up == parent) break;
        parent = up;
    }
    return false;
}

// Walks a directory, accumulating size (scan) and optionally deleting files.
// Files that are locked by another process simply stay; that is not an error.
void walk(const fs::path& root, bool remove, bool cache_only, std::uint64_t& bytes,
          std::size_t& files) {
    std::error_code ec;
    if (!fs::is_directory(root, ec)) return;
    fs::recursive_directory_iterator it(
        root, fs::directory_options::skip_permission_denied, ec);
    const fs::recursive_directory_iterator end;
    while (!ec && it != end) {
        std::error_code entry_ec;
        const fs::path entry = it->path();
        if (it->is_symlink(entry_ec)) {
            it.increment(ec);
            continue;
        }
        if (it->is_regular_file(entry_ec)) {
            if (cache_only && !in_cache_subdir(root, entry)) {
                it.increment(ec);
                continue;
            }
            std::error_code size_ec;
            const auto size = fs::file_size(entry, size_ec);
            if (!size_ec) bytes += size;
            ++files;
            if (remove) {
                std::error_code rm_ec;
                fs::remove(entry, rm_ec);
            }
        }
        it.increment(ec);
    }
}

}  // namespace

std::vector<Target> targets() {
    std::vector<Target> out;
    const auto add = [&out](std::string id, std::wstring title, std::wstring desc, fs::path path,
                            bool cache_only = false, bool boost = true) {
        std::error_code ec;
        if (path.empty() || !fs::is_directory(path, ec)) return;
        Target t;
        t.id = std::move(id);
        t.title = std::move(title);
        t.desc = std::move(desc);
        t.path = std::move(path);
        t.cache_only = cache_only;
        t.boost = boost;
        out.push_back(std::move(t));
    };

    const auto local = fsx::local_appdata();
    const auto roaming = fs::path(env_path(L"APPDATA"));
    const auto program_data = fs::path(env_path(L"ProgramData"));
    const auto program_files_x86 = fs::path(env_path(L"ProgramFiles(x86)"));

    // ---- Windows ---------------------------------------------------------
    add("user_temp", L"Временные файлы пользователя",
        L"%TEMP% — кэши установщиков, распаковка, эфемерные данные.", env_path(L"TEMP"));
    add("windows_temp", L"Системная папка Temp",
        L"C:\\Windows\\Temp — требует прав администратора.", L"C:\\Windows\\Temp", false, false);
    add("inetcache", L"Кэш Internet Explorer / WinINet",
        L"INetCache — кэш встроенного браузера Windows.", local / L"Microsoft" / L"Windows" / L"INetCache");
    add("wer", L"Отчёты об ошибках Windows",
        L"WER — дампы и журналы сбоев приложений.", local / L"Microsoft" / L"Windows" / L"WER");
    add("download_installers", L"Старые установщики",
        L"Downloaded Installations — распакованные пакеты MSI.", local / L"Downloaded Installations");
    add("store_cache", L"Кэш Microsoft Store",
        L"LocalCache магазина приложений.", local / L"Packages" /
            L"Microsoft.WindowsStore_8wekyb3d8bbwe" / L"LocalCache");
    add("windows_update", L"Кэш обновлений Windows",
        L"SoftwareDistribution\\Download — требует прав администратора.", L"C:\\Windows\\SoftwareDistribution\\Download",
        false, false);
    add("recycle_bin", L"Корзина",
        L"Очищает корзину всех дисков (файлы будут удалены безвозвратно).", L"C:\\\\$Recycle.Bin",
        false, false);

    // ---- GPU / shaders ---------------------------------------------------
    add("shader_d3d", L"Кэш шейдеров DirectX", L"Пересоздаётся игрой автоматически.",
        local / L"D3DSCache");
    add("shader_nvidia", L"Кэш шейдеров NVIDIA", L"DXCache и GLCache драйвера.", local / L"NVIDIA");
    add("shader_amd", L"Кэш шейдеров AMD", L"DxCache драйвера.", local / L"AMD");
    add("shader_intel", L"Кэш шейдеров Intel", L"Intel\\ShaderCache.", local / L"Intel" / L"ShaderCache");
    add("crash_dumps", L"Аварийные дампы", L"Отчёты о падениях приложений.",
        local / L"CrashDumps");
    add("staging", L"Временные файлы обновлений", L"Недокачанные архивы Rust Optimizer.",
        fsx::staging_dir());

    // ---- Browsers --------------------------------------------------------
    add("chrome", L"Google Chrome",
        L"Cache, Code Cache, GPUCache, ShaderCache всех профилей. Закладки и пароли не трогаются.",
        local / L"Google" / L"Chrome" / L"User Data", true);
    add("edge", L"Microsoft Edge",
        L"Кэши всех профилей Chromium. История и логины остаются.", local / L"Microsoft" / L"Edge" / L"User Data",
        true);
    add("brave", L"Brave",
        L"Кэши всех профилей.", local / L"BraveSoftware" / L"Brave-Browser" / L"User Data", true);
    add("vivaldi", L"Vivaldi", L"Кэши всех профилей.", local / L"Vivaldi" / L"User Data", true);
    add("yandex", L"Яндекс Браузер", L"Кэши всех профилей.", local / L"Yandex" / L"YandexBrowser" / L"User Data",
        true);
    add("chromium", L"Chromium", L"Кэши всех профилей.", local / L"Chromium" / L"User Data", true);
    add("opera", L"Opera", L"Кэш, Code Cache и GPUCache.", roaming / L"Opera Software" / L"Opera Stable", true);
    add("opera_gx", L"Opera GX", L"Кэш, Code Cache и GPUCache.", roaming / L"Opera Software" / L"Opera GX Stable",
        true);
    add("firefox", L"Mozilla Firefox",
        L"cache2, startupCache, shader-cache, thumbnails всех профилей.", local / L"Mozilla" / L"Firefox" / L"Profiles",
        true);

    // ---- Launchers / chat ------------------------------------------------
    add("discord", L"Discord", L"Cache, Code Cache и GPUCache (не сообщения).", roaming / L"discord", true);
    add("teams", L"Microsoft Teams", L"Кэши клиента Teams.", roaming / L"Microsoft" / L"Teams", true);
    add("epic_webcache", L"Epic Games Launcher", L"WebCache лаунчера.",
        local / L"EpicGamesLauncher" / L"Saved" / L"WebCache");
    add("steam_cache", L"Steam (кэш браузера)", L"appcache и httpcache Steam.",
        program_files_x86 / L"Steam" / L"appcache");
    add("spotify", L"Spotify", L"Кэш прослушанных треков (Storage).", local / L"Spotify" / L"Storage");
    add("unity_cache", L"Unity", L"Кэш редактора Unity.", local / L"Unity" / L"cache");
    add("programdata_temp", L"Temp всех пользователей",
        L"ProgramData\\Temp — требует прав администратора.", program_data / L"Temp", false, false);

    return out;
}

std::vector<std::string> boost_ids() {
    std::vector<std::string> ids;
    for (const auto& target : targets()) {
        if (target.boost) ids.push_back(target.id);
    }
    return ids;
}

namespace {

Result run(const std::vector<std::string>& ids, bool remove) {
    Result result;
    const auto all = targets();
    if (all.empty()) {
        result.ok = false;
        result.error = L"Не найдено ни одной папки для очистки";
        return result;
    }
    for (const auto& target : all) {
        if (!ids.empty() && std::find(ids.begin(), ids.end(), target.id) == ids.end()) continue;
        ItemResult item;
        item.id = target.id;
        item.title = target.title;
        std::error_code ec;
        if (target.id == "recycle_bin") {
            SHQUERYRBINFO info{};
            info.cbSize = static_cast<DWORD>(sizeof(info));
            if (SUCCEEDED(::SHQueryRecycleBinW(nullptr, &info))) {
                item.bytes = static_cast<std::uint64_t>(info.i64Size);
                item.files = static_cast<std::size_t>(info.i64NumItems);
            }
            if (remove) {
                ::SHEmptyRecycleBinW(nullptr, nullptr,
                                     SHERB_NOCONFIRMATION | SHERB_NOPROGRESSUI | SHERB_NOSOUND);
            }
            item.note = remove ? L"очищено" : L"готово к очистке";
            result.bytes += item.bytes;
            result.files += item.files;
            result.items.push_back(std::move(item));
            continue;
        }
        // Never follow the staging removal into our own data folder.
        if (target.id == "staging" && fs::equivalent(target.path, fsx::data_dir(), ec)) continue;
        walk(target.path, remove, target.cache_only, item.bytes, item.files);
        result.bytes += item.bytes;
        result.files += item.files;
        if (item.files == 0) item.note = L"пусто";
        else if (!remove) item.note = L"готово к очистке";
        else item.note = L"очищено";
        log::info(std::string("cleaner: ") + (remove ? "clean " : "scan ") + target.id + " -> " +
                  std::to_string(item.files) + " files, " + std::to_string(item.bytes) + " bytes");
        result.items.push_back(std::move(item));
    }
    if (result.items.empty()) {
        result.ok = false;
        result.error = L"Не выбрано ни одного пункта";
    }
    return result;
}

}  // namespace

Result scan(const std::vector<std::string>& ids) { return run(ids, false); }

Result clean(const std::vector<std::string>& ids) { return run(ids, true); }

}  // namespace ro::clean
