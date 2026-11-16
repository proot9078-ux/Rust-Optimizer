#pragma once
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace ro::str {

// UTF-8 <-> UTF-16 conversion (wrong encodings are replaced, never throw).
std::wstring widen(std::string_view utf8);
std::string narrow(std::wstring_view utf16);

std::string trim(std::string_view s);
std::wstring trim(std::wstring_view s);
std::string to_lower(std::string_view s);
std::wstring to_lower(std::wstring_view s);
bool iequals(std::string_view a, std::string_view b);
bool iequals(std::wstring_view a, std::wstring_view b);
bool starts_with(std::string_view s, std::string_view prefix);
bool ends_with(std::string_view s, std::string_view suffix);
bool contains(std::string_view s, std::string_view needle);
bool icontains(std::string_view s, std::string_view needle);

bool starts_with(std::wstring_view s, std::wstring_view prefix);
bool ends_with(std::wstring_view s, std::wstring_view suffix);
bool contains(std::wstring_view s, std::wstring_view needle);
bool icontains(std::wstring_view s, std::wstring_view needle);

std::vector<std::string> split(std::string_view s, char sep);
std::vector<std::string> split_lines(std::string_view s);
std::string join(const std::vector<std::string>& parts, std::string_view sep);

std::string replace_all(std::string s, std::string_view from, std::string_view to);
// Normalises CRLF/CR to LF and strips a UTF-8 BOM.
std::string normalise_newlines(std::string_view s);
std::string unquote(std::string_view s);  // "a\"b" -> a"b

std::optional<long long> to_int(std::string_view s);
std::optional<bool> to_bool(std::string_view s);
bool parse_bool(std::string_view s, bool fallback);
long long parse_int(std::string_view s, long long fallback);

std::string fmt(const char* pattern, ...);
std::wstring wfmt(const wchar_t* pattern, ...);
std::string human_bytes(std::uint64_t bytes);
std::wstring human_bytes_w(std::uint64_t bytes);
std::string human_ram_gb(std::uint64_t bytes);

// Replaces control characters, keeps the string single-line for logs.
std::string one_line(std::string_view s);

std::uint64_t fnv1a(std::string_view s);

}  // namespace ro::str
