#pragma once
#include <optional>
#include <string>
#include <vector>

#include "ro/settings.hpp"  // GameInstall

namespace ro::steam {

// AppID of RUST on Steam.
inline constexpr const wchar_t* kRustAppId = L"252490";

struct Library {
    std::wstring path;     // steam library root (contains "steamapps")
    std::wstring source;
};

struct Locator {
    std::wstring steam_dir;        // ...\Steam
    std::vector<Library> libraries;
    bool found_steam = false;
};

// Reads HKCU/HKLM (incl. Wow6432Node) and falls back to a drive scan.
Locator locate();
// Parses libraryfolders.vdf text. `steam_root` may be empty.
std::vector<std::wstring> parse_library_folders_vdf(std::string_view text);
// True when the path looks like a Steam library (has a steamapps folder).
bool looks_like_library(const std::filesystem::path& p);

// Finds RUST: uses appmanifest_252490.acf when present, otherwise probes the
// default install folder. Returns an invalid GameInstall when not installed.
GameInstall find_rust(const Locator& loc, std::vector<std::string>* trace = nullptr);
// Parses an ACF/VDF "key" "value" pair map (flat, case-insensitive).
std::optional<std::wstring> read_acf_value(std::string_view text, std::wstring_view key);

// Builds the launch options string recommended for the detected hardware.
std::string launch_options(unsigned ram_mb, const std::string& gpu_vendor, bool gc_4gb);

}  // namespace ro::steam
