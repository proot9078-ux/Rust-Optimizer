#pragma once
#include <filesystem>
#include <optional>
#include <string>
#include <vector>

namespace ro::backup {

// A backup entry describes one file this application has modified.
struct Entry {
    std::string file;      // absolute path (utf8)
    std::string stamp;     // ISO-ish timestamp
    std::string original_sha256;
    std::string backup_file;  // file name inside the backup folder
    std::string label;        // human readable origin ("rust client.cfg")
};

struct Manifest {
    int schema = 1;
    std::string created;
    std::string app_version;
    std::string label;
    std::vector<Entry> entries;
};

// Creates %LOCALAPPDATA%\RustOptimizer\backups\<stamp>_<label> and returns it.
std::filesystem::path create(std::string_view label);
bool add_file(const std::filesystem::path& backup_dir, const std::filesystem::path& source,
              std::string_view label, std::string& error);
std::optional<Manifest> load(const std::filesystem::path& backup_dir);
std::vector<std::filesystem::path> list_dirs();
std::filesystem::path latest_for(std::string_view label);
bool restore(const std::filesystem::path& backup_dir, std::string& error);

}  // namespace ro::backup
