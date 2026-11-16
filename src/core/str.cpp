#include "ro/str.hpp"

#include <windows.h>

#include <algorithm>
#include <cctype>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <cwchar>
#include <cwctype>

namespace ro::str {

std::wstring widen(std::string_view utf8) {
    if (utf8.empty()) return {};
    const int need = ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8.data(),
                                           static_cast<int>(utf8.size()), nullptr, 0);
    if (need <= 0) {
        // Fall back to a lossy conversion instead of throwing.
        const int loose = ::MultiByteToWideChar(CP_ACP, 0, utf8.data(),
                                                static_cast<int>(utf8.size()), nullptr, 0);
        if (loose <= 0) return {};
        std::wstring out(static_cast<std::size_t>(loose), L'\0');
        ::MultiByteToWideChar(CP_ACP, 0, utf8.data(), static_cast<int>(utf8.size()), out.data(), loose);
        return out;
    }
    std::wstring out(static_cast<std::size_t>(need), L'\0');
    ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8.data(), static_cast<int>(utf8.size()),
                          out.data(), need);
    return out;
}

std::string narrow(std::wstring_view utf16) {
    if (utf16.empty()) return {};
    const int need = ::WideCharToMultiByte(CP_UTF8, 0, utf16.data(), static_cast<int>(utf16.size()),
                                           nullptr, 0, nullptr, nullptr);
    if (need <= 0) return {};
    std::string out(static_cast<std::size_t>(need), '\0');
    ::WideCharToMultiByte(CP_UTF8, 0, utf16.data(), static_cast<int>(utf16.size()), out.data(), need,
                          nullptr, nullptr);
    return out;
}

std::string trim(std::string_view s) {
    std::size_t b = 0, e = s.size();
    while (b < e && (s[b] == ' ' || s[b] == '\t' || s[b] == '\r' || s[b] == '\n')) ++b;
    while (e > b && (s[e - 1] == ' ' || s[e - 1] == '\t' || s[e - 1] == '\r' || s[e - 1] == '\n')) --e;
    return std::string(s.substr(b, e - b));
}

std::wstring trim(std::wstring_view s) {
    std::size_t b = 0, e = s.size();
    while (b < e && (s[b] == L' ' || s[b] == L'\t' || s[b] == L'\r' || s[b] == L'\n')) ++b;
    while (e > b && (s[e - 1] == L' ' || s[e - 1] == L'\t' || s[e - 1] == L'\r' || s[e - 1] == L'\n')) --e;
    return std::wstring(s.substr(b, e - b));
}

std::string to_lower(std::string_view s) {
    std::string out(s);
    std::transform(out.begin(), out.end(), out.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return out;
}

std::wstring to_lower(std::wstring_view s) {
    std::wstring out(s);
    std::transform(out.begin(), out.end(), out.begin(), [](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
    return out;
}

bool iequals(std::string_view a, std::string_view b) {
    return a.size() == b.size() && std::equal(a.begin(), a.end(), b.begin(), [](char x, char y) {
               return std::tolower(static_cast<unsigned char>(x)) == std::tolower(static_cast<unsigned char>(y));
           });
}

bool iequals(std::wstring_view a, std::wstring_view b) {
    return a.size() == b.size() && std::equal(a.begin(), a.end(), b.begin(), [](wchar_t x, wchar_t y) {
               return std::towlower(x) == std::towlower(y);
           });
}

bool starts_with(std::string_view s, std::string_view prefix) {
    return s.size() >= prefix.size() && s.compare(0, prefix.size(), prefix) == 0;
}

bool ends_with(std::string_view s, std::string_view suffix) {
    return s.size() >= suffix.size() && s.compare(s.size() - suffix.size(), suffix.size(), suffix) == 0;
}

bool contains(std::string_view s, std::string_view needle) {
    return s.find(needle) != std::string_view::npos;
}

bool icontains(std::string_view s, std::string_view needle) {
    return to_lower(s).find(to_lower(needle)) != std::string::npos;
}

bool starts_with(std::wstring_view s, std::wstring_view prefix) {
    return s.size() >= prefix.size() && s.compare(0, prefix.size(), prefix) == 0;
}

bool ends_with(std::wstring_view s, std::wstring_view suffix) {
    return s.size() >= suffix.size() && s.compare(s.size() - suffix.size(), suffix.size(), suffix) == 0;
}

bool contains(std::wstring_view s, std::wstring_view needle) {
    return s.find(needle) != std::wstring_view::npos;
}

bool icontains(std::wstring_view s, std::wstring_view needle) {
    return to_lower(s).find(to_lower(needle)) != std::wstring::npos;
}

std::vector<std::string> split(std::string_view s, char sep) {
    std::vector<std::string> out;
    std::size_t start = 0;
    while (start <= s.size()) {
        const std::size_t pos = s.find(sep, start);
        if (pos == std::string_view::npos) {
            out.emplace_back(s.substr(start));
            break;
        }
        out.emplace_back(s.substr(start, pos - start));
        start = pos + 1;
    }
    return out;
}

std::vector<std::string> split_lines(std::string_view s) {
    std::vector<std::string> out;
    std::size_t start = 0;
    while (start < s.size()) {
        std::size_t pos = s.find('\n', start);
        if (pos == std::string_view::npos) pos = s.size();
        std::string line(s.substr(start, pos - start));
        if (!line.empty() && line.back() == '\r') line.pop_back();
        out.push_back(std::move(line));
        start = pos + 1;
    }
    return out;
}

std::string join(const std::vector<std::string>& parts, std::string_view sep) {
    std::string out;
    for (std::size_t i = 0; i < parts.size(); ++i) {
        if (i) out.append(sep);
        out.append(parts[i]);
    }
    return out;
}

std::string replace_all(std::string s, std::string_view from, std::string_view to) {
    if (from.empty()) return s;
    std::size_t pos = 0;
    while ((pos = s.find(from, pos)) != std::string::npos) {
        s.replace(pos, from.size(), to);
        pos += to.size();
    }
    return s;
}

std::string normalise_newlines(std::string_view s) {
    std::string out;
    out.reserve(s.size());
    if (s.size() >= 3 && static_cast<unsigned char>(s[0]) == 0xEF &&
        static_cast<unsigned char>(s[1]) == 0xBB && static_cast<unsigned char>(s[2]) == 0xBF) {
        s.remove_prefix(3);
    }
    for (std::size_t i = 0; i < s.size(); ++i) {
        if (s[i] == '\r') {
            if (i + 1 < s.size() && s[i + 1] == '\n') continue;
            out.push_back('\n');
        } else {
            out.push_back(s[i]);
        }
    }
    return out;
}

std::string unquote(std::string_view s) {
    s = std::string_view(s.data(), s.size());
    std::string_view t = s;
    while (!t.empty() && (t.front() == ' ' || t.front() == '\t')) t.remove_prefix(1);
    while (!t.empty() && (t.back() == ' ' || t.back() == '\t')) t.remove_suffix(1);
    if (t.size() >= 2 && t.front() == '"' && t.back() == '"') {
        t.remove_prefix(1);
        t.remove_suffix(1);
        std::string out;
        out.reserve(t.size());
        for (std::size_t i = 0; i < t.size(); ++i) {
            if (t[i] == '\\' && i + 1 < t.size() && (t[i + 1] == '"' || t[i + 1] == '\\')) {
                out.push_back(t[++i]);
            } else {
                out.push_back(t[i]);
            }
        }
        return out;
    }
    return std::string(t);
}

std::optional<long long> to_int(std::string_view s) {
    const std::string t = trim(s);
    if (t.empty()) return std::nullopt;
    wchar_t* end = nullptr;
    const std::wstring w = widen(t);
    const long long v = std::wcstoll(w.c_str(), &end, 10);
    if (end == w.c_str() || (end && *end != L'\0')) return std::nullopt;
    return v;
}

std::optional<bool> to_bool(std::string_view s) {
    const std::string t = to_lower(trim(s));
    if (t.empty()) return std::nullopt;
    if (t == "1" || t == "true" || t == "yes" || t == "on") return true;
    if (t == "0" || t == "false" || t == "no" || t == "off") return false;
    if (const auto n = to_int(t)) return *n != 0;
    return std::nullopt;
}

bool parse_bool(std::string_view s, bool fallback) {
    const auto v = to_bool(s);
    return v.value_or(fallback);
}

long long parse_int(std::string_view s, long long fallback) {
    const auto v = to_int(s);
    return v.value_or(fallback);
}

std::string fmt(const char* pattern, ...) {
    char stack[1024];
    va_list args;
    va_start(args, pattern);
    const int n = std::vsnprintf(stack, sizeof(stack), pattern, args);
    va_end(args);
    if (n < 0) return {};
    if (static_cast<std::size_t>(n) < sizeof(stack)) return std::string(stack, static_cast<std::size_t>(n));
    std::string out(static_cast<std::size_t>(n) + 1, '\0');
    va_start(args, pattern);
    std::vsnprintf(out.data(), out.size(), pattern, args);
    va_end(args);
    out.resize(static_cast<std::size_t>(n));
    return out;
}

std::wstring wfmt(const wchar_t* pattern, ...) {
    wchar_t stack[1024];
    va_list args;
    va_start(args, pattern);
    const int n = std::vswprintf(stack, sizeof(stack) / sizeof(wchar_t), pattern, args);
    va_end(args);
    if (n < 0) return {};
    if (static_cast<std::size_t>(n) < sizeof(stack) / sizeof(wchar_t)) return std::wstring(stack, static_cast<std::size_t>(n));
    std::wstring out(static_cast<std::size_t>(n) + 1, L'\0');
    va_start(args, pattern);
    std::vswprintf(out.data(), out.size(), pattern, args);
    va_end(args);
    out.resize(static_cast<std::size_t>(n));
    return out;
}

std::string human_bytes(std::uint64_t bytes) {
    static const char* units[] = {"B", "KB", "MB", "GB", "TB"};
    double v = static_cast<double>(bytes);
    int u = 0;
    while (v >= 1024.0 && u < 4) {
        v /= 1024.0;
        ++u;
    }
    if (u == 0) return fmt("%llu B", static_cast<unsigned long long>(bytes));
    return fmt("%.1f %s", v, units[u]);
}

std::wstring human_bytes_w(std::uint64_t bytes) { return widen(human_bytes(bytes)); }

std::string human_ram_gb(std::uint64_t bytes) {
    const double gb = static_cast<double>(bytes) / (1024.0 * 1024.0 * 1024.0);
    return fmt("%.1f GB", gb);
}

std::string one_line(std::string_view s) {
    std::string out;
    out.reserve(s.size());
    for (char c : s) out.push_back((c == '\r' || c == '\n' || c == '\t') ? ' ' : c);
    return out;
}

std::uint64_t fnv1a(std::string_view s) {
    std::uint64_t h = 1469598103934665603ull;
    for (unsigned char c : s) {
        h ^= c;
        h *= 1099511628211ull;
    }
    return h;
}

}  // namespace ro::str
