#pragma once
#include <cstdint>
#include <filesystem>
#include <optional>
#include <string>
#include <vector>

namespace ro::fsx {

namespace fs = std::filesystem;

bool exists(const fs::path& p) noexcept;
bool is_directory(const fs::path& p) noexcept;
bool is_regular_file(const fs::path& p) noexcept;
std::uint64_t file_size(const fs::path& p) noexcept;
std::optional<std::string> read_text(const fs::path& p);
bool write_text(const fs::path& p, std::string_view data);          // plain overwrite
bool write_text_atomic(const fs::path& p, std::string_view data);   // temp + rename
bool ensure_dir(const fs::path& p);
bool copy_file(const fs::path& from, const fs::path& to, bool overwrite = true);
bool remove_file(const fs::path& p) noexcept;

// Non-recursive listing; returns empty vector when the directory is absent.
std::vector<fs::path> list_dir(const fs::path& p);
std::vector<fs::path> list_dir_recursive(const fs::path& p, int max_depth = 3,
                                         std::size_t max_entries = 20000);

// "2026-11-15_18-04-05" local time stamp, safe for file names.
std::string time_stamp();

// Self-contained locations under %LOCALAPPDATA%\RustOptimizer.
fs::path local_appdata();
fs::path data_dir();      // ...\RustOptimizer
fs::path log_dir();       // ...\RustOptimizer\logs
fs::path backup_root();   // ...\RustOptimizer\backups
fs::path profile_dir();   // ...\RustOptimizer\profiles
fs::path staging_dir();   // ...\RustOptimizer\staging
fs::path exe_path();
fs::path exe_dir();

// Creates a timestamped backup folder and returns it. With a source file the
// original is copied inside together with a small JSON manifest.
fs::path make_backup_dir(std::string_view label);
bool backup_file(const fs::path& source, const fs::path& backup_dir, std::string& err);

// Breadth-limited search helper used by the game locator.
std::optional<fs::path> find_file_under(const fs::path& root, std::wstring_view file_name,
                                        int max_depth = 4);
std::optional<fs::path> find_file_under(const fs::path& root, std::wstring_view file_name,
                                        std::wstring_view required_parent, int max_depth);

}  // namespace ro::fsx
