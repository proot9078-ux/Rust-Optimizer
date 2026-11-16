#include "ro/settings.hpp"

#include <cstring>

#include "ro/fs.hpp"
#include "ro/log.hpp"
#include "ro/str.hpp"
#include "ro/version.hpp"

namespace ro {

namespace {

std::wstring get_w(const json::Value& v, const char* key, const std::wstring& fallback) {
    const auto it = v.find(key);
    if (it == v.end() || !it->is_string()) return fallback;
    return str::widen(it->get<std::string>());
}

}  // namespace

SettingsStore::SettingsStore(std::filesystem::path file) : path_(std::move(file)) {}

AppSettings SettingsStore::load() {
    AppSettings s;
    const auto text = fsx::read_text(path_);
    if (!text) {
        log::info("settings: no file yet, using defaults");
        return s;
    }
    std::string err;
    const auto parsed = json::parse(*text, &err);
    if (!parsed || !parsed->is_object()) {
        log::warn("settings: invalid JSON (" + err + "), keeping defaults; file kept for inspection");
        return s;
    }
    const auto& j = *parsed;
    try {
        s.schema = static_cast<int>(json::get_int(j, "schema", 1));
        s.dark_theme = json::get_bool(j, "dark_theme", true);
        s.check_updates = json::get_bool(j, "check_updates", true);
        s.auto_priority = json::get_bool(j, "auto_priority", true);
        s.auto_purge = json::get_bool(j, "auto_purge", false);
        s.auto_purge_interval_min = static_cast<int>(json::get_int(j, "auto_purge_interval_min", 15));
        s.minimize_on_apply = json::get_bool(j, "minimize_on_apply", false);
        s.allow_affinity = json::get_bool(j, "allow_affinity", false);
        s.steam_dir = get_w(j, "steam_dir", {});
        s.rust_exe = get_w(j, "rust_exe", {});
        s.fortnite_exe = get_w(j, "fortnite_exe", {});
        s.last_page = get_w(j, "last_page", L"overview");
        s.last_known_version = get_w(j, "last_known_version", {});
        if (auto it = j.find("toggles"); it != j.end() && it->is_object()) s.toggles = *it;
    } catch (const std::exception& e) {
        log::warn(std::string("settings: partially unreadable: ") + e.what());
    }
    return s;
}

bool SettingsStore::save(const AppSettings& s) {
    json::Value j = json::Value::object();
    j["schema"] = s.schema;
    j["dark_theme"] = s.dark_theme;
    j["check_updates"] = s.check_updates;
    j["auto_priority"] = s.auto_priority;
    j["auto_purge"] = s.auto_purge;
    j["auto_purge_interval_min"] = s.auto_purge_interval_min;
    j["minimize_on_apply"] = s.minimize_on_apply;
    j["allow_affinity"] = s.allow_affinity;
    j["steam_dir"] = str::narrow(s.steam_dir);
    j["rust_exe"] = str::narrow(s.rust_exe);
    j["fortnite_exe"] = str::narrow(s.fortnite_exe);
    j["last_page"] = str::narrow(s.last_page);
    j["last_known_version"] = str::narrow(s.last_known_version);
    j["toggles"] = s.toggles.is_object() ? s.toggles : json::Value::object();
    j["app_version"] = kVersion;

    fsx::ensure_dir(path_.parent_path());
    if (!fsx::write_text_atomic(path_, json::dump(j, true))) {
        last_save_ok_ = false;
        return false;
    }
    last_save_ok_ = true;
    return true;
}

GameCache::GameCache(std::filesystem::path file) : path_(std::move(file)) {}

std::vector<GameCacheEntry> GameCache::load() const {
    std::vector<GameCacheEntry> out;
    const auto text = fsx::read_text(path_);
    if (!text) return out;
    std::string err;
    const auto j = json::parse(*text, &err);
    if (!j || !j->is_object()) return out;
    const auto it = j->find("games");
    if (it == j->end() || !it->is_array()) return out;
    for (const auto& e : *it) {
        if (!e.is_object()) continue;
        GameCacheEntry entry;
        entry.kind = str::widen(json::get_string(e, "kind"));
        entry.exe_path = str::widen(json::get_string(e, "exe"));
        entry.install_dir = str::widen(json::get_string(e, "dir"));
        entry.launcher = str::widen(json::get_string(e, "launcher"));
        entry.app_version = str::widen(json::get_string(e, "version"));
        entry.checked_at = json::get_string(e, "checked_at");
        if (!entry.exe_path.empty()) out.push_back(std::move(entry));
    }
    return out;
}

bool GameCache::save(const std::vector<GameCacheEntry>& entries) const {
    json::Value root = json::Value::object();
    root["schema"] = 1;
    json::Value arr = json::Value::array();
    for (const auto& e : entries) {
        json::Value o = json::Value::object();
        o["kind"] = str::narrow(e.kind);
        o["exe"] = str::narrow(e.exe_path);
        o["dir"] = str::narrow(e.install_dir);
        o["launcher"] = str::narrow(e.launcher);
        o["version"] = str::narrow(e.app_version);
        o["checked_at"] = e.checked_at;
        arr.push_back(std::move(o));
    }
    root["games"] = std::move(arr);
    fsx::ensure_dir(path_.parent_path());
    return json::save_file(path_, root);
}

void GameCache::invalidate() {
    const auto text = fsx::read_text(path_);
    if (!text) return;
    fsx::remove_file(path_);
}

}  // namespace ro
