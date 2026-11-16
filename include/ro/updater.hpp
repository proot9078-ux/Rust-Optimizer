#pragma once
#include <atomic>
#include <cstdint>
#include <filesystem>
#include <optional>
#include <string>
#include <vector>

#include "ro/http.hpp"

namespace ro::update {

struct Asset {
    std::string name;
    std::string url;
    std::uint64_t size = 0;
    std::string content_type;
};

struct Release {
    std::string tag;
    std::string name;
    std::string body;
    std::string html_url;
    std::string published_at;
    bool prerelease = false;
    std::vector<Asset> assets;

    const Asset* find_asset(std::string_view name) const;
    const Asset* find_first(const std::vector<std::string>& suffixes) const;
};

struct CheckResult {
    bool ok = false;
    bool update_available = false;
    std::string error;
    Release release;
    std::string current_version;
    std::string latest_version;
};

// Compares dotted versions with optional leading "v". Returns -1/0/1.
int compare_versions(std::string_view a, std::string_view b);
std::optional<Release> parse_release(std::string_view json_text, std::string* error = nullptr);

CheckResult check(const net::Client& client, std::string_view owner, std::string_view repo,
                  std::string_view current_version);

struct StageResult {
    bool ok = false;
    std::filesystem::path staged_exe;
    std::string error;
    std::string sha256;
};

// Downloads the zip asset, verifies SHA256SUMS when published, extracts the new
// executable into a staging folder.
StageResult download_and_stage(const net::Client& client, const Release& rel,
                               const std::filesystem::path& staging_root,
                               const net::ProgressFn& progress, std::atomic<bool>* cancel);

// Spawns "<current exe> --apply-update <staged> <target> <parent-pid>" and exits
// the UI; the helper waits for this process to end and swaps the binaries.
bool spawn_applier(const std::filesystem::path& staged_exe,
                   const std::filesystem::path& target_exe);
// Runs inside the helper process. Returns process exit code.
int run_applier(const std::filesystem::path& staged_exe,
                const std::filesystem::path& target_exe, std::uint32_t parent_pid);

// Startup janitor: the applier cannot delete the previous binary while its own
// image is still mapped, so the freshly started build removes "<exe>.old" and
// any leftover staging folders.
void cleanup_stale(const std::filesystem::path& exe);

}  // namespace ro::update
