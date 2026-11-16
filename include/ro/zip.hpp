#pragma once
#include <filesystem>
#include <string>
#include <vector>

namespace ro::zip {

struct Entry {
    std::string name;
    std::uint64_t size = 0;
    bool is_dir = false;
};

std::vector<Entry> list(const std::filesystem::path& archive, std::string& error);
// Extracts into dest_dir, rejecting path traversal ("../") entries.
bool extract(const std::filesystem::path& archive, const std::filesystem::path& dest_dir,
             std::string& error);
// Extraction restricted to a single entry name.
bool extract_one(const std::filesystem::path& archive, std::string_view entry_name,
                 const std::filesystem::path& dest_file, std::string& error);

}  // namespace ro::zip
