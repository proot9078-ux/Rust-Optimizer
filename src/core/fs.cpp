#include "ro/fs.hpp"

#include <windows.h>
#include <shlobj.h>

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <system_error>

#include "ro/log.hpp"
#include "ro/str.hpp"
#include "ro/win32.hpp"

namespace ro::fsx {

namespace {

std::string win_path(const fs::path& p) { return str::narrow(p.wstring()); }

}  // namespace

bool exists(const fs::path& p) noexcept {
    std::error_code ec;
    const bool e = fs::exists(p, ec);
    return e && !ec;
}

bool is_directory(const fs::path& p) noexcept {
    std::error_code ec;
    const bool e = fs::is_directory(p, ec);
    return e && !ec;
}

bool is_regular_file(const fs::path& p) noexcept {
    std::error_code ec;
    const bool e = fs::is_regular_file(p, ec);
    return e && !ec;
}

std::uint64_t file_size(const fs::path& p) noexcept {
    std::error_code ec;
    const auto s = fs::file_size(p, ec);
    return ec ? 0 : static_cast<std::uint64_t>(s);
}

std::optional<std::string> read_text(const fs::path& p) {
    if (!ro::fsx::is_regular_file(p)) return std::nullopt;
    std::ifstream in(p, std::ios::binary);
    if (!in) {
        log::warn("read_text: cannot open " + win_path(p) + " (" + win::last_error_text() + ")");
        return std::nullopt;
    }
    std::string data((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    if (in.bad()) {
        log::warn("read_text: read failure " + win_path(p));
        return std::nullopt;
    }
    return data;
}

bool write_text(const fs::path& p, std::string_view data) {
    std::error_code ec;
    if (!p.parent_path().empty()) fs::create_directories(p.parent_path(), ec);
    std::ofstream out(p, std::ios::binary | std::ios::trunc);
    if (!out) {
        log::error("write_text: cannot create " + win_path(p) + " (" + win::last_error_text() + ")");
        return false;
    }
    out.write(data.data(), static_cast<std::streamsize>(data.size()));
    out.flush();
    if (!out.good()) {
        log::error("write_text: write failure " + win_path(p));
        return false;
    }
    return true;
}

bool write_text_atomic(const fs::path& p, std::string_view data) {
    const fs::path tmp = p.wstring() + L".tmp";
    if (!write_text(tmp, data)) return false;
    std::error_code ec;
    fs::rename(tmp, p, ec);
    if (ec) {
        // Retry: some editors hold a lock on the destination; retry once after
        // removing the destination.
        fs::remove(p, ec);
        ec.clear();
        fs::rename(tmp, p, ec);
    }
    if (ec) {
        log::error("write_text_atomic: rename failed for " + win_path(p) + ": " + ec.message());
        std::error_code ignored;
        fs::remove(tmp, ignored);
        return false;
    }
    return true;
}

bool ensure_dir(const fs::path& p) {
    std::error_code ec;
    if (p.empty()) return false;
    fs::create_directories(p, ec);
    return !ec || ro::fsx::is_directory(p);
}

bool copy_file(const fs::path& from, const fs::path& to, bool overwrite) {
    std::error_code ec;
    if (!to.parent_path().empty()) fs::create_directories(to.parent_path(), ec);
    ec.clear();
    fs::copy_file(from, to, overwrite ? fs::copy_options::overwrite_existing : fs::copy_options::none, ec);
    if (ec) log::error("copy_file " + win_path(from) + " -> " + win_path(to) + ": " + ec.message());
    return !ec;
}

bool remove_file(const fs::path& p) noexcept {
    std::error_code ec;
    return fs::remove(p, ec) && !ec;
}

std::vector<fs::path> list_dir(const fs::path& p) {
    std::vector<fs::path> out;
    std::error_code ec;
    if (!ro::fsx::is_directory(p)) return out;
    for (fs::directory_iterator it(p, ec), end; !ec && it != end; it.increment(ec)) {
        out.push_back(it->path());
    }
    std::sort(out.begin(), out.end());
    return out;
}

namespace {

void walk(const fs::path& dir, int depth, int max_depth, std::size_t max_entries,
          std::vector<fs::path>& out) {
    if (depth > max_depth || out.size() >= max_entries) return;
    std::error_code ec;
    for (fs::directory_iterator it(dir, fs::directory_options::skip_permission_denied, ec), end;
         !ec && it != end; it.increment(ec)) {
        if (out.size() >= max_entries) return;
        const auto& e = *it;
        std::error_code ec2;
        if (e.is_directory(ec2)) {
            const std::wstring name = e.path().filename().wstring();
            // Skip reparse points to avoid cycles and huge system trees.
            if (ec2) continue;
            walk(e.path(), depth + 1, max_depth, max_entries, out);
        } else if (e.is_regular_file(ec2)) {
            out.push_back(e.path());
        }
    }
}

}  // namespace

std::vector<fs::path> list_dir_recursive(const fs::path& p, int max_depth, std::size_t max_entries) {
    std::vector<fs::path> out;
    if (!ro::fsx::is_directory(p)) return out;
    walk(p, 0, max_depth, max_entries, out);
    return out;
}

std::string time_stamp() {
    SYSTEMTIME st{};
    ::GetLocalTime(&st);
    return str::fmt("%04u-%02u-%02u_%02u-%02u-%02u", st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);
}

fs::path local_appdata() {
    wchar_t buffer[MAX_PATH * 2]{};
    const DWORD n = ::GetEnvironmentVariableW(L"LOCALAPPDATA", buffer, static_cast<DWORD>(std::size(buffer)));
    if (n > 0 && n < std::size(buffer)) return fs::path(buffer);
    PWSTR known = nullptr;
    if (SUCCEEDED(::SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &known)) && known) {
        fs::path p(known);
        ::CoTaskMemFree(known);
        return p;
    }
    return fs::temp_directory_path();
}

fs::path data_dir() { return local_appdata() / L"RustOptimizer"; }
fs::path log_dir() { return data_dir() / L"logs"; }
fs::path backup_root() { return data_dir() / L"backups"; }
fs::path profile_dir() { return data_dir() / L"profiles"; }
fs::path staging_dir() { return data_dir() / L"staging"; }

fs::path exe_path() {
    wchar_t buffer[32768]{};
    const DWORD n = ::GetModuleFileNameW(nullptr, buffer, static_cast<DWORD>(std::size(buffer)));
    if (n == 0 || n >= std::size(buffer)) return {};
    return fs::path(std::wstring(buffer, n));
}

fs::path exe_dir() {
    const auto p = exe_path();
    return p.empty() ? fs::path{} : p.parent_path();
}

fs::path make_backup_dir(std::string_view label) {
    std::string safe;
    for (char c : label) safe.push_back((std::isalnum(static_cast<unsigned char>(c)) || c == '-' || c == '_') ? c : '-');
    if (safe.size() > 40) safe.resize(40);
    const fs::path dir = backup_root() / (time_stamp() + "_" + (safe.empty() ? "backup" : safe));
    ensure_dir(dir);
    return dir;
}

bool backup_file(const fs::path& source, const fs::path& backup_dir, std::string& err) {
    if (!ro::fsx::is_regular_file(source)) {
        err = "file not found: " + win_path(source);
        return false;
    }
    if (!ensure_dir(backup_dir)) {
        err = "cannot create backup dir: " + win_path(backup_dir);
        return false;
    }
    const fs::path dest = backup_dir / source.filename();
    if (!copy_file(source, dest, true)) {
        err = "copy failed: " + win_path(source);
        return false;
    }
    return true;
}

namespace {
bool name_matches(const fs::path& p, std::wstring_view wanted) {
    const std::wstring name = p.filename().wstring();
    if (str::iequals(name, wanted)) return true;
    // Allow "RustClient" to match "RustClient.exe".
    if (wanted.find(L'.') == std::wstring_view::npos &&
        str::iequals(name, std::wstring(wanted) + L".exe")) {
        return true;
    }
    return false;
}
}  // namespace

std::optional<fs::path> find_file_under(const fs::path& root, std::wstring_view file_name, int max_depth) {
    if (!ro::fsx::is_directory(root)) return std::nullopt;
    // Breadth-first: shallow matches win.
    std::vector<fs::path> level{root};
    for (int depth = 0; depth <= max_depth && !level.empty(); ++depth) {
        std::vector<fs::path> next;
        for (const auto& dir : level) {
            std::error_code ec;
            for (fs::directory_iterator it(dir, fs::directory_options::skip_permission_denied, ec), end;
                 !ec && it != end; it.increment(ec)) {
                std::error_code ec2;
                if (it->is_directory(ec2)) {
                    const std::wstring n = it->path().filename().wstring();
                    if (n == L"Windows" || n == L"$Recycle.Bin" || n == L"System Volume Information") continue;
                    next.push_back(it->path());
                } else if (it->is_regular_file(ec2) && name_matches(it->path(), file_name)) {
                    return it->path();
                }
            }
        }
        level.swap(next);
    }
    return std::nullopt;
}

std::optional<fs::path> find_file_under(const fs::path& root, std::wstring_view file_name,
                                        std::wstring_view required_parent, int max_depth) {
    if (!ro::fsx::is_directory(root)) return std::nullopt;
    std::vector<fs::path> level{root};
    for (int depth = 0; depth <= max_depth && !level.empty(); ++depth) {
        std::vector<fs::path> next;
        for (const auto& dir : level) {
            std::error_code ec;
            for (fs::directory_iterator it(dir, fs::directory_options::skip_permission_denied, ec), end;
                 !ec && it != end; it.increment(ec)) {
                std::error_code ec2;
                if (it->is_directory(ec2)) {
                    next.push_back(it->path());
                } else if (it->is_regular_file(ec2) && name_matches(it->path(), file_name)) {
                    if (str::iequals(it->path().parent_path().filename().wstring(), required_parent)) {
                        return it->path();
                    }
                }
            }
        }
        level.swap(next);
    }
    return std::nullopt;
}

}  // namespace ro::fsx


