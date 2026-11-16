#include "ro/epic.hpp"

#include <windows.h>

#include <algorithm>

#include "ro/fs.hpp"
#include "ro/hardware.hpp"
#include "ro/json.hpp"
#include "ro/log.hpp"
#include "ro/str.hpp"
#include "ro/win32.hpp"

namespace ro::epic {

namespace {

std::filesystem::path launcher_data_dir() {
    if (auto p = win::reg_read_string(HKEY_LOCAL_MACHINE, L"SOFTWARE\\EpicGames\\EpicGamesLauncher", L"AppDataPath")) {
        const std::filesystem::path dir(*p);
        if (fsx::is_directory(dir)) return dir;
    }
    // Conventional location if the key is missing.
    if (auto program_data = win::reg_read_string(HKEY_LOCAL_MACHINE,
                                                 L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion",
                                                 L"CommonFilesDir")) {
        (void)program_data;
    }
    return std::filesystem::path(L"C:\\ProgramData\\Epic\\EpicGamesLauncher\\Data");
}

std::wstring strip_version_suffix(std::wstring name) {
    const std::size_t pos = name.find(L"-Win64-Shipping");
    if (pos != std::wstring::npos) name.resize(pos);
    return name;
}

}  // namespace

std::filesystem::path manifests_dir() { return launcher_data_dir() / L"Manifests"; }

bool is_fortnite_name(std::string_view app_name) {
    return str::iequals(app_name, "Fortnite") || str::iequals(app_name, "Fortnite_Studio") ||
           str::icontains(app_name, "Fortnite");
}

std::optional<Manifest> parse_manifest(std::string_view json_text) {
    std::string err;
    const auto j = json::parse(json_text, &err);
    if (!j || !j->is_object()) {
        log::debug("epic: manifest JSON rejected (" + err + ")");
        return std::nullopt;
    }
    Manifest m;
    m.app_name = str::widen(json::get_string(*j, "AppName"));
    m.display_name = str::widen(json::get_string(*j, "DisplayName"));
    m.install_location = str::widen(json::get_string(*j, "InstallLocation"));
    m.launch_executable = str::widen(json::get_string(*j, "LaunchExecutable"));
    m.catalog_item_id = str::widen(json::get_string(*j, "CatalogItemId"));
    if (m.app_name.empty() && m.install_location.empty()) return std::nullopt;
    return m;
}

std::vector<Manifest> read_manifests() {
    std::vector<Manifest> out;
    const auto dir = manifests_dir();
    if (!fsx::is_directory(dir)) {
        log::warn("epic: manifests folder missing: " + str::narrow(dir.wstring()));
        return out;
    }
    for (const auto& file : fsx::list_dir(dir)) {
        if (!str::iequals(file.extension().string(), ".item")) continue;
        const auto text = fsx::read_text(file);
        if (!text) continue;
        if (auto m = parse_manifest(*text)) {
            m->raw_path = file.wstring();
            out.push_back(std::move(*m));
        }
    }
    return out;
}

std::vector<Manifest> read_launcher_installed() {
    std::vector<Manifest> out;
    const std::filesystem::path file =
        std::filesystem::path(L"C:\\ProgramData\\Epic\\UnrealEngineLauncher\\LauncherInstalled.dat");
    const auto text = fsx::read_text(file);
    if (!text) return out;
    std::string err;
    const auto j = json::parse(*text, &err);
    if (!j || !j->is_object()) return out;
    const auto it = j->find("InstallationList");
    if (it == j->end() || !it->is_array()) return out;
    for (const auto& e : *it) {
        if (!e.is_object()) continue;
        Manifest m;
        m.app_name = str::widen(json::get_string(e, "AppName"));
        m.install_location = str::widen(json::get_string(e, "InstallLocation"));
        m.raw_path = file.wstring();
        if (!m.install_location.empty()) out.push_back(std::move(m));
    }
    return out;
}

std::filesystem::path user_config_dir() {
    wchar_t buffer[MAX_PATH * 2]{};
    const DWORD n = ::GetEnvironmentVariableW(L"LOCALAPPDATA", buffer, static_cast<DWORD>(std::size(buffer)));
    const std::filesystem::path local = (n > 0) ? std::filesystem::path(buffer) : fsx::local_appdata();
    return local / L"FortniteGame" / L"Saved" / L"Config" / L"WindowsClient";
}

GameInstall find_fortnite(std::vector<std::string>* trace) {
    GameInstall install;
    install.kind = L"fortnite";
    install.launcher = L"epic";
    auto note = [&](const std::string& s) {
        if (trace) trace->push_back(s);
        log::debug("epic: " + s);
    };

    const auto complete = [&](const Manifest& m, const wchar_t* source) -> bool {
        const std::filesystem::path base(m.install_location);
        const std::filesystem::path exe = base / L"FortniteGame" / L"Binaries" / L"Win64" /
                                          L"FortniteClient-Win64-Shipping.exe";
        if (!fsx::is_regular_file(exe)) return false;
        install.valid = true;
        install.exe_path = exe.wstring();
        install.install_dir = base.wstring();
        install.source = source;
        install.version.clear();
        install.size_bytes = fsx::file_size(exe);
        if (!m.display_name.empty()) install.version = m.display_name;
        note(std::string("found: ") + str::narrow(exe.wstring()));
        return true;
    };

    for (const auto& m : read_manifests()) {
        if (!is_fortnite_name(str::narrow(m.app_name))) continue;
        if (complete(m, L"epic manifest")) return install;
        note("manifest points to a missing install: " + str::narrow(m.install_location));
    }
    note("no usable .item manifest");

    for (const auto& m : read_launcher_installed()) {
        if (!is_fortnite_name(str::narrow(m.app_name))) continue;
        if (complete(m, L"LauncherInstalled.dat")) return install;
    }

    // Fallback: conventional Epic Games folders on every drive.
    const DWORD drives = ::GetLogicalDrives();
    for (int i = 0; i < 26; ++i) {
        if ((drives & (1u << i)) == 0) continue;
        const std::wstring root = std::wstring(1, static_cast<wchar_t>(L'A' + i)) + L":\\";
        for (const wchar_t* sub : {L"Program Files\\Epic Games", L"Epic Games", L"Games\\Epic Games",
                                   L"Program Files (x86)\\Epic Games"}) {
            const std::filesystem::path base = std::filesystem::path(root) / sub;
            if (!fsx::is_directory(base)) continue;
            if (auto exe = fsx::find_file_under(base, L"FortniteClient-Win64-Shipping.exe", L"Win64", 4)) {
                install.valid = true;
                install.exe_path = exe->wstring();
                install.install_dir = base.wstring();
                install.source = L"drive scan";
                install.size_bytes = fsx::file_size(*exe);
                note("found by scan: " + str::narrow(exe->wstring()));
                return install;
            }
        }
    }
    note("Fortnite not installed");
    return install;
}

}  // namespace ro::epic
