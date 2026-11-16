#pragma once
#include <string>
#include <string_view>
#include <vector>

#include "ro/report.hpp"

namespace ro {

// INI / CFG file that preserves ordering, comments and unknown keys.
// Used for Fortnite GameUserSettings/Engine.ini and for RUST client.cfg.
class IniFile {
public:
    static IniFile parse(std::string_view text);
    std::string serialize() const;

    bool has(std::string_view section, std::string_view key) const;
    std::string get(std::string_view section, std::string_view key,
                    std::string_view fallback = {}) const;
    // Returns true when the value actually changed.
    bool set(std::string_view section, std::string_view key, std::string_view value);
    bool erase(std::string_view section, std::string_view key);

    // Sets or replaces a dedicated block delimited by markers so that reverting
    // is a pure string operation and nothing else in the file is touched.
    bool set_marked_block(std::string_view section, std::string_view marker_id,
                          const std::vector<std::string>& lines);
    bool remove_marked_block(std::string_view marker_id);
    bool has_marked_block(std::string_view marker_id) const;
    std::vector<std::string> marker_ids() const;
    // Returns true when the file had no trailing newline / used CRLF.
    bool uses_crlf() const { return crlf_; }

    std::vector<std::string> sections() const;

private:
    struct Entry {
        int section = -1;        // -1 = before the first section
        std::string section_name;
        std::string key;
        std::string value;
        std::string raw;         // original line (for comments / blanks)
        bool is_kv = false;
    };
    std::vector<Entry> entries_;
    bool crlf_ = false;
    std::string trailing_newline_ = "\n";
    int find_section(std::string_view name) const;
    static std::string strip_quotes(std::string_view s);
};

}  // namespace ro
