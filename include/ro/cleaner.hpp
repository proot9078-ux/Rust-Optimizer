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
    // When true only files inside well-known cache subfolders (Cache,
    // Code Cache, GPUCache, ...) are counted and deleted. That makes it safe to
    // point a target at a whole browser profile without touching logins,
    // cookies, history or bookmarks.
    bool cache_only = false;
    // Included in the one-click "БУСТ FPS" sweep.
    bool boost = true;
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

// Targets that actually exist on this machine: TEMP, browser caches (Chrome,
// Edge, Firefox, Opera, Brave, Vivaldi, Yandex, Chromium), Discord/Epic/Teams
// caches, GPU shader caches, crash dumps, the updater staging folder and the
// recycle bin.
std::vector<Target> targets();

// Ids of the targets the "БУСТ FPS" button cleans: everything except items
// that need elevation or delete recoverable user files.
std::vector<std::string> boost_ids();

// Both scan() and clean() accept a list of target ids; empty means "all".
// Only caches and temporary data are touched - never game configs, saves,
// logins or other user documents.
Result scan(const std::vector<std::string>& ids);
Result clean(const std::vector<std::string>& ids);

}  // namespace ro::clean
