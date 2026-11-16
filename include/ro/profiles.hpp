#pragma once
#include <filesystem>
#include <optional>
#include <string>
#include <vector>

#include "ro/json.hpp"

namespace ro {

// A profile is a portable JSON document holding the tweak options of one page,
// so users can share/export/import settings without touching any game file.
struct Profile {
    std::string name;
    std::string game;               // "rust" | "fortnite" | "system"
    std::string created;            // ISO-ish timestamp
    std::string app_version;
    json::Value options = json::Value::object();
    std::string notes;

    json::Value to_json() const;
    static std::optional<Profile> from_json(const json::Value& v, std::string* error = nullptr);
};

class ProfileStore {
public:
    explicit ProfileStore(std::filesystem::path dir);
    std::vector<Profile> load_all() const;
    bool save(const Profile& p, std::string& error) const;
    bool remove(const std::string& name, std::string& error) const;
    // Export/import use the .rop extension (Rust Optimizer Profile).
    bool export_file(const Profile& p, const std::filesystem::path& file, std::string& error) const;
    std::optional<Profile> import_file(const std::filesystem::path& file, std::string& error) const;
    std::filesystem::path path_for(const std::string& name) const;

private:
    std::filesystem::path dir_;
};

}  // namespace ro
