#pragma once
#include <cstdint>
#include <filesystem>
#include <string>
#include <vector>

#include "ro/json.hpp"

namespace ro {

struct GameInstall {
    std::wstring kind;          // L"rust" / L"fortnite"
    std::wstring exe_path;
    std::wstring install_dir;
    std::wstring launcher;      // L"steam" / L"epic"
    std::wstring source;        // how it was located (registry / vdf / manifest / scan / cache)
    std::wstring version;
    std::uint64_t size_bytes = 0;
    bool valid = false;
};

struct AppSettings {
    int schema = 1;
    bool dark_theme = true;
    // Named theme preset (dark, midnight, light, neon, rust, ocean).
    std::string theme = "dark";
    bool check_updates = true;
    bool auto_priority = true;
    bool auto_purge = false;
    int auto_purge_interval_min = 15;
    bool minimize_on_apply = false;
    // Close the optimizer as soon as the game window appears.
    bool close_on_launch = true;
    // Display preset id: off / soft / vivid / cinema (see ro/visuals.hpp).
    std::string image_preset = "off";
    bool allow_affinity = false;
    std::wstring steam_dir;
    std::wstring rust_exe;
    std::wstring fortnite_exe;
    std::wstring last_page = L"overview";
    // Toggle state per page, persisted between runs.
    json::Value toggles = json::Value::object();
    std::wstring last_known_version;
};

class SettingsStore {
public:
    explicit SettingsStore(std::filesystem::path file);
    AppSettings load();
    bool save(const AppSettings& s);
    const std::filesystem::path& path() const { return path_; }
    // Writing the settings never fails the caller silently: the error is logged.
    bool last_save_ok() const { return last_save_ok_; }

private:
    std::filesystem::path path_;
    bool last_save_ok_ = true;
};

// Game location cache (kept apart from settings so a corrupt cache can be
// dropped without losing user preferences).
struct GameCacheEntry {
    std::wstring kind;
    std::wstring exe_path;
    std::wstring install_dir;
    std::wstring launcher;
    std::wstring app_version;
    std::string checked_at;
};

class GameCache {
public:
    explicit GameCache(std::filesystem::path file);
    std::vector<GameCacheEntry> load() const;
    bool save(const std::vector<GameCacheEntry>& entries) const;
    void invalidate();

private:
    std::filesystem::path path_;
};

}  // namespace ro
