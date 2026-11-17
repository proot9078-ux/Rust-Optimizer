#include "ro/cleaner.hpp"

#include <windows.h>

#include <algorithm>
#include <iterator>
#include <system_error>

#include "ro/fs.hpp"
#include "ro/log.hpp"

namespace ro::clean {

namespace {

namespace fs = std::filesystem;

std::wstring env_path(const wchar_t* name) {
    wchar_t buffer[MAX_PATH * 2]{};
    const DWORD n = ::GetEnvironmentVariableW(name, buffer, static_cast<DWORD>(std::size(buffer)));
    if (n == 0 || n >= static_cast<DWORD>(std::size(buffer))) return {};
    return std::wstring(buffer, n);
}

// Walks a directory, accumulating size (scan) and optionally deleting files.
// Files that are locked by another process simply stay; that is not an error.
void walk(const fs::path& root, bool remove, std::uint64_t& bytes, std::size_t& files) {
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
    const auto add = [&out](std::string id, std::wstring title, std::wstring desc, fs::path path) {
        std::error_code ec;
        if (path.empty() || !fs::is_directory(path, ec)) return;
        out.push_back(Target{std::move(id), std::move(title), std::move(desc), std::move(path)});
    };

    const auto temp = env_path(L"TEMP");
    add("user_temp", L"Временные файлы пользователя",
        L"%TEMP% — кэши установщиков, распаковка, эфемерные данные.", temp);
    add("windows_temp", L"Системная папка Temp", L"C:\\Windows\\Temp — требует прав администратора.",
        L"C:\\Windows\\Temp");

    const auto local = fsx::local_appdata();
    add("shader_d3d", L"Кэш шейдеров DirectX", L"Пересоздаётся игрой автоматически.",
        local / L"D3DSCache");
    add("shader_nvidia", L"Кэш шейдеров NVIDIA", L"DXCache и GLCache драйвера.",
        local / L"NVIDIA");
    add("shader_amd", L"Кэш шейдеров AMD", L"DxCache драйвера.", local / L"AMD");
    add("crash_dumps", L"Аварийные дампы", L"Отчёты о падениях приложений.",
        local / L"CrashDumps");
    add("staging", L"Временные файлы обновлений", L"Недокачанные архивы Rust Optimizer.",
        fsx::staging_dir());
    return out;
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
        // Never follow the staging removal into our own data folder.
        if (target.id == "staging" && fs::equivalent(target.path, fsx::data_dir(), ec)) continue;
        walk(target.path, remove, item.bytes, item.files);
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
