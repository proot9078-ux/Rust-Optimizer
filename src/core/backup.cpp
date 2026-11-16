#include "ro/backup.hpp"

#include <algorithm>

#include "ro/fs.hpp"
#include "ro/json.hpp"
#include "ro/log.hpp"
#include "ro/sha256.hpp"
#include "ro/str.hpp"
#include "ro/version.hpp"

namespace ro::backup {

namespace {

constexpr const char* kManifestName = "manifest.json";

bool save_manifest(const std::filesystem::path& dir, const Manifest& m) {
    json::Value j = json::Value::object();
    j["schema"] = m.schema;
    j["created"] = m.created;
    j["app_version"] = m.app_version;
    j["label"] = m.label;
    json::Value entries = json::Value::array();
    for (const auto& e : m.entries) {
        json::Value o = json::Value::object();
        o["file"] = e.file;
        o["stamp"] = e.stamp;
        o["sha256"] = e.original_sha256;
        o["backup_file"] = e.backup_file;
        o["label"] = e.label;
        entries.push_back(std::move(o));
    }
    j["entries"] = std::move(entries);
    return json::save_file(dir / kManifestName, j);
}

}  // namespace

std::filesystem::path create(std::string_view label) { return fsx::make_backup_dir(label); }

bool add_file(const std::filesystem::path& backup_dir, const std::filesystem::path& source,
              std::string_view label, std::string& error) {
    if (!fsx::is_regular_file(source)) {
        error = "backup: source missing " + str::narrow(source.wstring());
        return false;
    }
    if (!fsx::ensure_dir(backup_dir)) {
        error = "backup: cannot create " + str::narrow(backup_dir.wstring());
        return false;
    }
    std::wstring rel = source.filename().wstring();
    // Disambiguate identical file names coming from different folders
    // (GameUserSettings.ini + Engine.ini have distinct names, but be safe).
    std::filesystem::path dest = backup_dir / rel;
    int suffix = 1;
    while (fsx::exists(dest)) {
        dest = backup_dir / (str::widen(str::fmt("%d_", suffix)) + rel);
        ++suffix;
    }
    if (!fsx::copy_file(source, dest, false)) {
        error = "backup: copy failed for " + str::narrow(source.wstring());
        return false;
    }
    Manifest m = load(backup_dir).value_or(Manifest{});
    if (m.created.empty()) {
        m.created = fsx::time_stamp();
        m.app_version = kVersion;
        m.label = std::string(label);
    }
    Entry e;
    e.file = str::narrow(source.wstring());
    e.stamp = fsx::time_stamp();
    e.original_sha256 = sha256_file(source);
    e.backup_file = str::narrow(dest.filename().wstring());
    e.label = std::string(label);
    m.entries.push_back(std::move(e));
    if (!save_manifest(backup_dir, m)) {
        error = "backup: manifest write failed";
        return false;
    }
    log::info("backup: " + str::narrow(source.filename().wstring()) + " -> " +
              str::narrow(backup_dir.filename().wstring()));
    return true;
}

std::optional<Manifest> load(const std::filesystem::path& backup_dir) {
    const auto file = backup_dir / kManifestName;
    const auto text = fsx::read_text(file);
    if (!text) return std::nullopt;
    std::string err;
    const auto j = json::parse(*text, &err);
    if (!j || !j->is_object()) return std::nullopt;
    Manifest m;
    m.schema = static_cast<int>(json::get_int(*j, "schema", 1));
    m.created = json::get_string(*j, "created");
    m.app_version = json::get_string(*j, "app_version");
    m.label = json::get_string(*j, "label");
    if (auto it = j->find("entries"); it != j->end() && it->is_array()) {
        for (const auto& e : *it) {
            if (!e.is_object()) continue;
            Entry entry;
            entry.file = json::get_string(e, "file");
            entry.stamp = json::get_string(e, "stamp");
            entry.original_sha256 = json::get_string(e, "sha256");
            entry.backup_file = json::get_string(e, "backup_file");
            entry.label = json::get_string(e, "label");
            m.entries.push_back(std::move(entry));
        }
    }
    return m;
}

std::vector<std::filesystem::path> list_dirs() {
    std::vector<std::filesystem::path> out;
    for (const auto& p : fsx::list_dir(fsx::backup_root())) {
        if (fsx::is_directory(p)) out.push_back(p);
    }
    // Newest first (names start with a timestamp).
    std::sort(out.begin(), out.end(), [](const auto& a, const auto& b) {
        return a.filename().wstring() > b.filename().wstring();
    });
    return out;
}

std::filesystem::path latest_for(std::string_view label) {
    for (const auto& dir : list_dirs()) {
        const auto m = load(dir);
        if (!m) continue;
        if (m->label == label) return dir;
        for (const auto& e : m->entries) {
            if (str::iequals(e.label, label)) return dir;
        }
    }
    return {};
}

bool restore(const std::filesystem::path& backup_dir, std::string& error) {
    const auto m = load(backup_dir);
    if (!m) {
        error = "backup: manifest missing in " + str::narrow(backup_dir.wstring());
        return false;
    }
    if (m->entries.empty()) {
        error = "backup: nothing to restore";
        return false;
    }
    int restored = 0;
    for (const auto& e : m->entries) {
        const auto src = backup_dir / str::widen(e.backup_file);
        const auto dst = std::filesystem::path(str::widen(e.file));
        if (!fsx::is_regular_file(src)) {
            error = "backup: missing " + e.backup_file;
            continue;
        }
        // Safety: the destination must live under a user profile or a game dir.
        if (!fsx::copy_file(src, dst, true)) {
            error = "backup: cannot restore " + e.file;
            continue;
        }
        ++restored;
    }
    if (restored == 0) {
        if (error.empty()) error = "backup: nothing restored";
        return false;
    }
    log::success(str::fmt("backup: restored %d file(s) from %s", restored,
                          str::narrow(backup_dir.filename().wstring()).c_str()));
    return true;
}

}  // namespace ro::backup
