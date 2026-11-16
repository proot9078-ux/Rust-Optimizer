#include "ro/ini.hpp"

#include <algorithm>
#include <cctype>

#include "ro/str.hpp"

namespace ro {

namespace {
constexpr const char* kMarkerOpen = "; >>> RO:";
constexpr const char* kMarkerClose = "; <<< RO:";
}  // namespace

std::string IniFile::strip_quotes(std::string_view s) { return str::unquote(s); }

IniFile IniFile::parse(std::string_view text) {
    IniFile ini;
    const std::string normalised = str::normalise_newlines(text);
    ini.crlf_ = text.find("\r\n") != std::string_view::npos;
    ini.trailing_newline_ = normalised.empty() || normalised.back() == '\n' ? "\n" : "";

    int section_index = -1;
    std::string section_name;
    std::size_t start = 0;
    while (start < normalised.size()) {
        std::size_t pos = normalised.find('\n', start);
        if (pos == std::string::npos) pos = normalised.size();
        const std::string line = normalised.substr(start, pos - start);
        start = pos + 1;

        const std::string trimmed = str::trim(line);
        Entry e;
        e.section = section_index;
        e.section_name = section_name;
        if (trimmed.empty() || trimmed[0] == ';' || trimmed[0] == '#') {
            e.raw = line;
            ini.entries_.push_back(std::move(e));
            continue;
        }
        if (trimmed.front() == '[' && trimmed.back() == ']') {
            section_name = str::trim(trimmed.substr(1, trimmed.size() - 2));
            ++section_index;
            e.section = section_index;
            e.section_name = section_name;
            e.raw = line;
            ini.entries_.push_back(std::move(e));
            continue;
        }
        const std::size_t eq = trimmed.find('=');
        if (eq == std::string::npos) {
            e.raw = line;
            ini.entries_.push_back(std::move(e));
            continue;
        }
        e.is_kv = true;
        e.key = str::trim(trimmed.substr(0, eq));
        e.value = str::trim(trimmed.substr(eq + 1));
        e.raw = line;
        ini.entries_.push_back(std::move(e));
        if (start > normalised.size()) break;
    }
    return ini;
}

bool IniFile::has(std::string_view section, std::string_view key) const {
    for (const auto& e : entries_) {
        if (e.is_kv && str::iequals(e.section_name, section) && str::iequals(e.key, key)) return true;
    }
    return false;
}

std::string IniFile::get(std::string_view section, std::string_view key, std::string_view fallback) const {
    for (const auto& e : entries_) {
        if (e.is_kv && str::iequals(e.section_name, section) && str::iequals(e.key, key)) {
            return strip_quotes(e.value);
        }
    }
    return std::string(fallback);
}

int IniFile::find_section(std::string_view name) const {
    for (std::size_t i = 0; i < entries_.size(); ++i) {
        const auto& e = entries_[i];
        if (!e.is_kv && e.raw.size() >= 2 && str::trim(e.raw).size() >= 2 && str::trim(e.raw).front() == '[' &&
            str::iequals(e.section_name, name)) {
            return static_cast<int>(i);
        }
    }
    return -1;
}

bool IniFile::set(std::string_view section, std::string_view key, std::string_view value) {
    for (auto& e : entries_) {
        if (e.is_kv && str::iequals(e.section_name, section) && str::iequals(e.key, key)) {
            if (e.value == value) return false;
            e.value = std::string(value);
            return true;
        }
    }
    // Key is missing: append at the end of its section (or create the section).
    const int header = find_section(section);
    if (header < 0) {
        Entry h;
        h.section = entries_.empty() ? 0 : -1;
        h.section_name = std::string(section);
        h.raw = "[" + std::string(section) + "]";
        entries_.push_back(h);
        Entry kv;
        kv.section = 0;
        kv.section_name = std::string(section);
        kv.is_kv = true;
        kv.key = std::string(key);
        kv.value = std::string(value);
        entries_.push_back(std::move(kv));
        return true;
    }
    // Walk to the end of the section.
    std::size_t insert_at = static_cast<std::size_t>(header) + 1;
    for (std::size_t i = static_cast<std::size_t>(header) + 1; i < entries_.size(); ++i) {
        const auto& e = entries_[i];
        const bool is_header = !e.is_kv && str::trim(e.raw).size() >= 2 && str::trim(e.raw).front() == '[';
        if (is_header) break;
        insert_at = i + 1;
    }
    Entry kv;
    kv.section = entries_[static_cast<std::size_t>(header)].section;
    kv.section_name = std::string(section);
    kv.is_kv = true;
    kv.key = std::string(key);
    kv.value = std::string(value);
    entries_.insert(entries_.begin() + static_cast<std::ptrdiff_t>(insert_at), std::move(kv));
    return true;
}

bool IniFile::erase(std::string_view section, std::string_view key) {
    const auto before = entries_.size();
    entries_.erase(std::remove_if(entries_.begin(), entries_.end(),
                                  [&](const Entry& e) {
                                      return e.is_kv && str::iequals(e.section_name, section) &&
                                             str::iequals(e.key, key);
                                  }),
                   entries_.end());
    return entries_.size() != before;
}

bool IniFile::has_marked_block(std::string_view marker_id) const {
    const std::string open = std::string(kMarkerOpen) + std::string(marker_id) + " >>>";
    for (const auto& e : entries_) {
        if (!e.is_kv && str::contains(e.raw, open)) return true;
    }
    return false;
}

std::vector<std::string> IniFile::marker_ids() const {
    std::vector<std::string> ids;
    for (const auto& e : entries_) {
        if (e.is_kv) continue;
        const std::size_t pos = e.raw.find(kMarkerOpen);
        if (pos == std::string::npos) continue;
        std::string rest = e.raw.substr(pos + std::string(kMarkerOpen).size());
        const std::size_t end = rest.find(" >>>");
        if (end == std::string::npos) continue;
        rest.resize(end);
        if (!rest.empty() && std::find(ids.begin(), ids.end(), rest) == ids.end()) ids.push_back(rest);
    }
    return ids;
}

bool IniFile::remove_marked_block(std::string_view marker_id) {
    const std::string open = std::string(kMarkerOpen) + std::string(marker_id) + " >>>";
    const std::string close = std::string(kMarkerClose) + std::string(marker_id) + " <<<";
    auto begin = entries_.end();
    auto end = entries_.end();
    for (auto it = entries_.begin(); it != entries_.end(); ++it) {
        if (!it->is_kv && str::contains(it->raw, open)) begin = it;
        if (begin != entries_.end() && !it->is_kv && str::contains(it->raw, close)) {
            end = it + 1;
            break;
        }
    }
    if (begin == entries_.end()) return false;
    if (end == entries_.end()) end = entries_.end();
    entries_.erase(begin, end);
    return true;
}

bool IniFile::set_marked_block(std::string_view section, std::string_view marker_id,
                               const std::vector<std::string>& lines) {
    remove_marked_block(marker_id);
    std::vector<Entry> block;
    Entry open;
    open.section_name = std::string(section);
    open.raw = std::string(kMarkerOpen) + std::string(marker_id) + " >>>";
    block.push_back(open);
    for (const auto& l : lines) {
        Entry e;
        e.section_name = std::string(section);
        const std::size_t eq = l.find('=');
        if (eq != std::string::npos) {
            e.is_kv = true;
            e.key = str::trim(l.substr(0, eq));
            e.value = str::trim(l.substr(eq + 1));
        } else {
            e.raw = l;
        }
        block.push_back(std::move(e));
    }
    Entry close;
    close.section_name = std::string(section);
    close.raw = std::string(kMarkerClose) + std::string(marker_id) + " <<<";
    block.push_back(close);

    const int header = find_section(section);
    if (header < 0) {
        Entry h;
        h.section = entries_.empty() ? 0 : -1;
        h.section_name = std::string(section);
        h.raw = "[" + std::string(section) + "]";
        entries_.push_back(h);
        for (auto& e : block) {
            e.section = 0;
            entries_.push_back(std::move(e));
        }
        return true;
    }
    std::size_t insert_at = static_cast<std::size_t>(header) + 1;
    for (std::size_t i = static_cast<std::size_t>(header) + 1; i < entries_.size(); ++i) {
        const std::string t = str::trim(entries_[i].raw);
        if (!entries_[i].is_kv && t.size() >= 2 && t.front() == '[') break;
        insert_at = i + 1;
    }
    const int section_index = entries_[static_cast<std::size_t>(header)].section;
    for (auto& e : block) e.section = section_index;
    entries_.insert(entries_.begin() + static_cast<std::ptrdiff_t>(insert_at),
                    std::make_move_iterator(block.begin()), std::make_move_iterator(block.end()));
    return true;
}

std::string IniFile::serialize() const {
    const std::string nl = crlf_ ? "\r\n" : "\n";
    std::string out;
    for (const auto& e : entries_) {
        if (e.is_kv) {
            out += e.key;
            out += '=';
            out += e.value;
        } else {
            out += e.raw;
        }
        out += nl;
    }
    if (!trailing_newline_.empty() && !out.empty()) {
        // out already ends with a newline
    }
    return out;
}

std::vector<std::string> IniFile::sections() const {
    std::vector<std::string> out;
    for (const auto& e : entries_) {
        const std::string t = str::trim(e.raw);
        if (e.is_kv || t.size() < 2 || t.front() != '[') continue;
        if (std::find(out.begin(), out.end(), e.section_name) == out.end()) out.push_back(e.section_name);
    }
    return out;
}

}  // namespace ro
