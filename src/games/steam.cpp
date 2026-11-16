#include "ro/steam.hpp"

#include <windows.h>

#include <algorithm>
#include <cctype>

#include "ro/fs.hpp"
#include "ro/log.hpp"
#include "ro/str.hpp"
#include "ro/win32.hpp"

namespace ro::steam {

namespace {

std::wstring path_from_registry() {
    if (auto p = win::reg_read_string(HKEY_CURRENT_USER, L"Software\\Valve\\Steam", L"SteamPath")) {
        return *p;
    }
    if (auto p = win::reg_read_string(HKEY_LOCAL_MACHINE, L"SOFTWARE\\WOW6432Node\\Valve\\Steam", L"InstallPath")) {
        return *p;
    }
    if (auto p = win::reg_read_string(HKEY_LOCAL_MACHINE, L"SOFTWARE\\Valve\\Steam", L"InstallPath")) {
        return *p;
    }
    return {};
}

// Enumerates fixed and removable drives and keeps the ones that look like a
// Steam library. Cheap because it only probes a handful of well-known paths.
std::vector<std::wstring> scan_drives() {
    std::vector<std::wstring> found;
    const DWORD drives = ::GetLogicalDrives();
    for (int i = 0; i < 26; ++i) {
        if ((drives & (1u << i)) == 0) continue;
        const wchar_t letter = static_cast<wchar_t>(L'A' + i);
        const std::wstring root = std::wstring(1, letter) + L":\\";
        const UINT type = ::GetDriveTypeW(root.c_str());
        if (type != DRIVE_FIXED && type != DRIVE_REMOVABLE) continue;
        for (const wchar_t* sub : {L"Steam", L"SteamLibrary", L"Games\\Steam", L"Games\\SteamLibrary",
                                   L"Program Files (x86)\\Steam", L"Program Files\\Steam"}) {
            const std::wstring candidate = root + sub;
            if (looks_like_library(candidate)) found.push_back(candidate);
        }
    }
    return found;
}

}  // namespace

bool looks_like_library(const std::filesystem::path& p) {
    return fsx::is_directory(p / L"steamapps");
}

std::vector<std::wstring> parse_library_folders_vdf(std::string_view text) {
    std::vector<std::wstring> out;
    const std::string normalised = str::normalise_newlines(text);
    const auto lines = str::split_lines(normalised);
    for (const auto& raw : lines) {
        const std::string line = str::trim(raw);
        if (line.empty() || line[0] == '/' || line[0] == '#') continue;
        // Only "path" entries matter; app entries ("apps" blocks with numbers)
        // are ignored because their keys are numeric.
        if (!str::starts_with(str::to_lower(line), "\"path\"")) continue;
        const std::size_t first = line.find('"');
        const std::size_t second = line.find('"', first + 1);
        const std::size_t third = line.find('"', second + 1);
        const std::size_t fourth = line.find('"', third + 1);
        if (third == std::string::npos || fourth == std::string::npos) continue;
        std::string value = line.substr(third + 1, fourth - third - 1);
        value = str::replace_all(value, "\\\\", "\\");
        if (value.empty()) continue;
        out.push_back(str::widen(value));
    }
    // Old (pre-2019) format uses numeric keys with quotes only:
    // "1" "D:\\SteamLibrary"  -> keep those as well.
    bool has_path_key = !out.empty();
    if (!has_path_key) {
        for (const auto& raw : lines) {
            const std::string line = str::trim(raw);
            const std::size_t first = line.find('"');
            const std::size_t second = line.find('"', first + 1);
            const std::size_t third = line.find('"', second + 1);
            const std::size_t fourth = line.find('"', third + 1);
            if (second == std::string::npos || third == std::string::npos || fourth == std::string::npos) continue;
            const std::string key = line.substr(first + 1, second - first - 1);
            if (key.empty() || !std::all_of(key.begin(), key.end(), [](unsigned char c) { return std::isdigit(c); })) {
                continue;
            }
            std::string value = line.substr(third + 1, fourth - third - 1);
            value = str::replace_all(value, "\\\\", "\\");
            if (value.size() > 2 && value[1] == ':') out.push_back(str::widen(value));
        }
    }
    return out;
}

std::optional<std::wstring> read_acf_value(std::string_view text, std::wstring_view key) {
    const auto lines = str::split_lines(str::normalise_newlines(text));
    const std::wstring wanted = str::to_lower(key);
    for (const auto& raw : lines) {
        const std::string line = str::trim(raw);
        const std::size_t first = line.find('"');
        if (first == std::string::npos) continue;
        const std::size_t second = line.find('"', first + 1);
        if (second == std::string::npos) continue;
        const std::size_t third = line.find('"', second + 1);
        if (third == std::string::npos) continue;
        const std::size_t fourth = line.find('"', third + 1);
        if (fourth == std::string::npos) continue;
        const std::wstring name = str::to_lower(str::widen(line.substr(first + 1, second - first - 1)));
        if (name != wanted) continue;
        std::string value = line.substr(third + 1, fourth - third - 1);
        value = str::replace_all(value, "\\\\", "\\");
        return str::widen(value);
    }
    return std::nullopt;
}

Locator locate() {
    Locator loc;
    std::wstring root = path_from_registry();
    if (!root.empty()) {
        const std::filesystem::path p = std::filesystem::path(root);
        if (fsx::is_directory(p)) {
            loc.steam_dir = p.wstring();
            loc.found_steam = true;
        }
    }
    if (loc.steam_dir.empty()) {
        // Fallback: a small set of conventional locations plus a drive scan.
        for (const wchar_t* guess : {L"C:\\Program Files (x86)\\Steam", L"C:\\Program Files\\Steam",
                                     L"D:\\Steam", L"E:\\Steam", L"D:\\SteamLibrary"}) {
            if (fsx::is_directory(guess)) {
                loc.steam_dir = guess;
                loc.found_steam = true;
                break;
            }
        }
    }
    if (loc.steam_dir.empty()) {
        for (const auto& d : scan_drives()) {
            if (fsx::is_directory(std::filesystem::path(d) / L"config") ||
                fsx::is_directory(std::filesystem::path(d) / L"steamapps")) {
                loc.steam_dir = d;
                loc.found_steam = true;
                break;
            }
        }
    }

    if (!loc.steam_dir.empty()) {
        loc.libraries.push_back(Library{loc.steam_dir, L"steam_root"});
        const auto vdf = std::filesystem::path(loc.steam_dir) / L"steamapps" / L"libraryfolders.vdf";
        if (const auto text = fsx::read_text(vdf)) {
            for (const auto& lib : parse_library_folders_vdf(*text)) {
                loc.libraries.push_back(Library{lib, L"libraryfolders.vdf"});
            }
        } else {
            log::warn("steam: libraryfolders.vdf not readable");
        }
    }

    // Deduplicate and drop entries that do not exist.
    std::vector<Library> unique;
    for (const auto& lib : loc.libraries) {
        std::error_code ec;
        const auto normal = std::filesystem::weakly_canonical(lib.path, ec);
        const std::wstring key = str::to_lower(ec ? lib.path : normal.wstring());
        const bool duplicate = std::any_of(unique.begin(), unique.end(), [&](const Library& l) {
            std::error_code ec2;
            const auto n2 = std::filesystem::weakly_canonical(l.path, ec2);
            return str::iequals(str::to_lower(ec2 ? l.path : n2.wstring()), key);
        });
        if (duplicate) continue;
        if (!fsx::is_directory(lib.path)) {
            log::debug("steam: library path missing: " + str::narrow(lib.path));
            continue;
        }
        unique.push_back(lib);
    }
    loc.libraries = std::move(unique);
    return loc;
}

GameInstall find_rust(const Locator& loc, std::vector<std::string>* trace) {
    GameInstall install;
    install.kind = L"rust";
    install.launcher = L"steam";
    auto note = [&](const std::string& s) {
        if (trace) trace->push_back(s);
        log::debug("steam: " + s);
    };

    if (!loc.found_steam) {
        note("Steam not detected in the registry");
        return install;
    }
    note("Steam root: " + str::narrow(loc.steam_dir));

    for (const auto& lib : loc.libraries) {
        const auto steamapps = std::filesystem::path(lib.path) / L"steamapps";
        if (!fsx::is_directory(steamapps)) continue;

        std::wstring sub_dir;
        const auto manifest = steamapps / (std::wstring(L"appmanifest_") + kRustAppId + L".acf");
        if (const auto text = fsx::read_text(manifest)) {
            if (auto dir = read_acf_value(*text, L"installdir")) sub_dir = *dir;
            if (auto name = read_acf_value(*text, L"name")) {
                note("appmanifest found: " + str::narrow(*name));
            }
        }
        if (sub_dir.empty()) sub_dir = L"Rust";
        const auto candidate = steamapps / L"common" / sub_dir / L"RustClient.exe";
        if (fsx::is_regular_file(candidate)) {
            install.valid = true;
            install.exe_path = candidate.wstring();
            install.install_dir = candidate.parent_path().wstring();
            install.source = L"appmanifest_252490.acf";
            install.size_bytes = fsx::file_size(candidate);
            note("RustClient.exe: " + str::narrow(candidate.wstring()));
            return install;
        }
        note("library checked, RUST absent: " + str::narrow(lib.path));
    }

    // Last resort: bounded scan of the Steam root for RustClient.exe.
    if (auto found = fsx::find_file_under(loc.steam_dir, L"RustClient.exe", L"Rust", 4)) {
        install.valid = true;
        install.exe_path = found->wstring();
        install.install_dir = found->parent_path().wstring();
        install.source = L"scan";
        install.size_bytes = fsx::file_size(*found);
        note("found by scan: " + str::narrow(found->wstring()));
    }
    return install;
}

std::string launch_options(unsigned ram_mb, const std::string& gpu_vendor, bool gc_4gb) {
    std::string options = "-high";
    if (ram_mb > 0) options += " -maxMem=" + std::to_string(ram_mb);
    options += " -malloc=system";
    if (gpu_vendor == "intel") {
        options += " -force-d3d11";
    }
    if (gc_4gb) {
        options += " -gc.buffer 4096";
    } else if (ram_mb >= 15000) {
        options += " -gc.buffer 2048";
    }
    return options;
}

}  // namespace ro::steam
