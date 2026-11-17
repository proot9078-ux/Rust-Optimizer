#pragma once
#include <cstdint>
#include <filesystem>
#include <string>
#include <vector>

namespace ro::clean {

struct Target {
    std::string id;
    std::wstring title;
    std::wstring desc;
    std::filesystem::path path;
};

struct ItemResult {
    std::string id;
    std::wstring title;
    std::uint64_t bytes = 0;
    std::size_t files = 0;
    bool ok = true;
    std::wstring note;
};

struct Result {
    std::vector<ItemResult> items;
    std::uint64_t bytes = 0;
    std::size_t files = 0;
    bool ok = true;
    std::wstring error;
};

// Targets that actually exist on this machine (TEMP, GPU shader caches,
// crash dumps and the updater staging folder).
std::vector<Target> targets();

// Both scan() and clean() accept a list of target ids; empty means "all".
// Only caches and temporary data are touched - never game configs, saves or
// other user documents.
Result scan(const std::vector<std::string>& ids);
Result clean(const std::vector<std::string>& ids);

}  // namespace ro::clean
