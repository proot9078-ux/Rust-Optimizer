#include "ro/profiles.hpp"

#include <algorithm>

#include "ro/fs.hpp"
#include "ro/log.hpp"
#include "ro/str.hpp"
#include "ro/version.hpp"

namespace ro {

json::Value Profile::to_json() const {
    json::Value j = json::Value::object();
    j["schema"] = 1;
    j["name"] = name;
    j["game"] = game;
    j["created"] = created;
    j["app_version"] = app_version;
    j["notes"] = notes;
    j["options"] = options;
    return j;
}

std::optional<Profile> Profile::from_json(const json::Value& v, std::string* error) {
    if (!v.is_object()) {
        if (error) *error = "профиль не является JSON-объектом";
        return std::nullopt;
    }
    Profile p;
    p.name = json::get_string(v, "name");
    p.game = json::get_string(v, "game", "rust");
    p.created = json::get_string(v, "created");
    p.app_version = json::get_string(v, "app_version");
    p.notes = json::get_string(v, "notes");
    const auto it = v.find("options");
    if (it == v.end() || !it->is_object()) {
        if (error) *error = "в профиле нет блока options";
        return std::nullopt;
    }
    p.options = *it;
    if (p.name.empty()) {
        if (error) *error = "у профиля нет имени";
        return std::nullopt;
    }
    return p;
}

ProfileStore::ProfileStore(std::filesystem::path dir) : dir_(std::move(dir)) {}

std::filesystem::path ProfileStore::path_for(const std::string& name) const {
    std::string safe;
    for (char c : name) {
        safe.push_back((std::isalnum(static_cast<unsigned char>(c)) || c == '-' || c == '_' || c == ' ') ? c : '_');
    }
    if (safe.empty()) safe = "profile";
    return dir_ / (str::widen(safe) + L".json");
}

std::vector<Profile> ProfileStore::load_all() const {
    std::vector<Profile> out;
    for (const auto& f : fsx::list_dir(dir_)) {
        if (!str::iequals(f.extension().string(), ".json")) continue;
        const auto text = fsx::read_text(f);
        if (!text) continue;
        std::string err;
        const auto j = json::parse(*text, &err);
        if (!j) {
            log::warn("profiles: skipping invalid file " + str::narrow(f.wstring()) + ": " + err);
            continue;
        }
        std::string perr;
        if (auto p = Profile::from_json(*j, &perr)) out.push_back(std::move(*p));
        else log::warn("profiles: " + str::narrow(f.wstring()) + ": " + perr);
    }
    std::sort(out.begin(), out.end(), [](const Profile& a, const Profile& b) { return a.name < b.name; });
    return out;
}

bool ProfileStore::save(const Profile& p, std::string& error) const {
    if (p.name.empty()) {
        error = "пустое имя профиля";
        return false;
    }
    if (!fsx::ensure_dir(dir_)) {
        error = "не удалось создать папку профилей";
        return false;
    }
    Profile copy = p;
    if (copy.created.empty()) copy.created = fsx::time_stamp();
    copy.app_version = kVersion;
    if (!json::save_file(path_for(p.name), copy.to_json())) {
        error = "не удалось записать профиль";
        return false;
    }
    log::success("profiles: saved " + p.name);
    return true;
}

bool ProfileStore::remove(const std::string& name, std::string& error) const {
    const auto file = path_for(name);
    if (!fsx::is_regular_file(file)) {
        error = "профиль не найден";
        return false;
    }
    if (!fsx::remove_file(file)) {
        error = "не удалось удалить файл профиля";
        return false;
    }
    return true;
}

bool ProfileStore::export_file(const Profile& p, const std::filesystem::path& file, std::string& error) const {
    if (file.extension() != L".rop") {
        error = "профиль должен иметь расширение .rop";
        return false;
    }
    if (!json::save_file(file, p.to_json())) {
        error = "не удалось записать " + str::narrow(file.wstring());
        return false;
    }
    return true;
}

std::optional<Profile> ProfileStore::import_file(const std::filesystem::path& file, std::string& error) const {
    const auto text = fsx::read_text(file);
    if (!text) {
        error = "файл не читается";
        return std::nullopt;
    }
    const auto j = json::parse(*text, &error);
    if (!j) return std::nullopt;
    auto p = Profile::from_json(*j, &error);
    if (!p) return std::nullopt;
    if (p->name.empty()) p->name = str::narrow(file.stem().wstring());
    return p;
}

}  // namespace ro
