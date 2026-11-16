#include "ro/updater.hpp"

#include <windows.h>
#include <shellapi.h>

#include <algorithm>
#include <chrono>
#include <thread>

#include "ro/fs.hpp"
#include "ro/json.hpp"
#include "ro/log.hpp"
#include "ro/sha256.hpp"
#include "ro/shortcut.hpp"
#include "ro/str.hpp"
#include "ro/version.hpp"
#include "ro/win32.hpp"
#include "ro/zip.hpp"

namespace ro::update {

namespace {

std::string normalise_version(std::string_view v) {
    std::string s = str::trim(v);
    if (!s.empty() && (s[0] == 'v' || s[0] == 'V')) s.erase(s.begin());
    return s;
}

std::vector<int> version_parts(std::string_view v) {
    std::vector<int> out;
    const std::string norm = normalise_version(v);
    std::string current;
    for (char c : norm) {
        if (std::isdigit(static_cast<unsigned char>(c))) {
            current.push_back(c);
        } else if (c == '.' || c == '-' || c == '+') {
            if (!current.empty()) {
                out.push_back(std::atoi(current.c_str()));
                current.clear();
            }
            if (c != '.') break;  // pre-release suffix: stop comparing numerics
        } else {
            break;
        }
    }
    if (!current.empty()) out.push_back(std::atoi(current.c_str()));
    return out;
}

std::string find_checksum(std::string_view file_name, std::string_view sums_text) {
    for (const auto& line : str::split_lines(sums_text)) {
        const std::string t = str::trim(line);
        if (t.empty()) continue;
        const std::size_t split = t.find_first_of(" \t*");
        if (split == std::string::npos) continue;
        const std::string hash = str::to_lower(t.substr(0, split));
        const std::string name = str::trim(t.substr(split + 1));
        const std::size_t slash = name.find_last_of("/\\");
        const std::string base = slash == std::string::npos ? name : name.substr(slash + 1);
        if (base == file_name && hash.size() == 64) return hash;
    }
    return {};
}

}  // namespace

const Asset* Release::find_asset(std::string_view name) const {
    for (const auto& a : assets) {
        if (str::iequals(a.name, name)) return &a;
    }
    return nullptr;
}

const Asset* Release::find_first(const std::vector<std::string>& suffixes) const {
    for (const auto& suffix : suffixes) {
        for (const auto& a : assets) {
            if (str::ends_with(str::to_lower(a.name), str::to_lower(suffix))) return &a;
        }
    }
    return nullptr;
}

int compare_versions(std::string_view a, std::string_view b) {
    const auto pa = version_parts(a);
    const auto pb = version_parts(b);
    const std::size_t n = (std::max)(pa.size(), pb.size());
    for (std::size_t i = 0; i < n; ++i) {
        const int va = i < pa.size() ? pa[i] : 0;
        const int vb = i < pb.size() ? pb[i] : 0;
        if (va != vb) return va < vb ? -1 : 1;
    }
    return 0;
}

std::optional<Release> parse_release(std::string_view json_text, std::string* error) {
    std::string parse_error;
    const auto j = json::parse(json_text, &parse_error);
    if (!j || !j->is_object()) {
        if (error) *error = "ответ GitHub не является JSON: " + parse_error;
        return std::nullopt;
    }
    Release r;
    r.tag = json::get_string(*j, "tag_name");
    r.name = json::get_string(*j, "name");
    r.body = json::get_string(*j, "body");
    r.html_url = json::get_string(*j, "html_url");
    r.published_at = json::get_string(*j, "published_at");
    r.prerelease = json::get_bool(*j, "prerelease", false);
    if (r.tag.empty()) {
        if (error) *error = "в релизе нет tag_name";
        return std::nullopt;
    }
    const auto assets = j->find("assets");
    if (assets != j->end() && assets->is_array()) {
        for (const auto& a : *assets) {
            if (!a.is_object()) continue;
            Asset asset;
            asset.name = json::get_string(a, "name");
            asset.url = json::get_string(a, "browser_download_url");
            asset.size = static_cast<std::uint64_t>(json::get_int(a, "size", 0));
            asset.content_type = json::get_string(a, "content_type");
            if (!asset.name.empty() && !asset.url.empty()) r.assets.push_back(std::move(asset));
        }
    }
    return r;
}

CheckResult check(const net::Client& client, std::string_view owner, std::string_view repo,
                  std::string_view current_version) {
    CheckResult result;
    result.current_version = normalise_version(current_version);
    const std::wstring url = L"https://api.github.com/repos/" + str::widen(std::string(owner)) + L"/" +
                             str::widen(std::string(repo)) + L"/releases/latest";
    const auto resp = client.get(url, {{L"User-Agent", str::widen(kUserAgent)},
                                       {L"Accept", L"application/vnd.github+json"}});
    if (!resp.error.empty()) {
        result.error = resp.error;
        return result;
    }
    if (resp.status == 404) {
        result.error = "релизы не найдены (404)";
        return result;
    }
    if (resp.status != 200) {
        result.error = str::fmt("GitHub API вернул HTTP %d", resp.status);
        return result;
    }
    std::string err;
    auto release = parse_release(resp.body, &err);
    if (!release) {
        result.error = err;
        return result;
    }
    result.release = std::move(*release);
    result.latest_version = normalise_version(result.release.tag);
    result.ok = true;
    result.update_available = compare_versions(result.latest_version, result.current_version) > 0;
    return result;
}

StageResult download_and_stage(const net::Client& client, const Release& rel,
                               const std::filesystem::path& staging_root, const net::ProgressFn& progress,
                               std::atomic<bool>* cancel) {
    StageResult result;
    const Asset* zip_asset = rel.find_first({".zip"});
    if (!zip_asset) {
        result.error = "в релизе нет .zip ассета";
        return result;
    }
    const auto work = staging_root / ("update_" + rel.tag);
    fsx::ensure_dir(work);

    const auto zip_path = work / str::widen(zip_asset->name);
    log::info("update: downloading " + zip_asset->name);
    if (!client.download(str::widen(zip_asset->url), zip_path, progress, cancel, result.error)) {
        return result;
    }

    // Optional integrity check.
    if (const Asset* sums = rel.find_first({"sha256sums", "sha256sums.txt", ".sha256"})) {
        const auto sums_path = work / L"SHA256SUMS";
        std::string dl_error;
        if (client.download(str::widen(sums->url), sums_path, nullptr, nullptr, dl_error)) {
            const auto text = fsx::read_text(sums_path);
            if (text) {
                const std::string expected = find_checksum(zip_asset->name, *text);
                if (!expected.empty()) {
                    const std::string actual = ro::sha256_file(zip_path);
                    if (actual != expected) {
                        result.error = "контрольная сумма SHA-256 не совпала";
                        log::error("update: checksum mismatch (expected " + expected + ", got " + actual + ")");
                        fsx::remove_file(zip_path);
                        return result;
                    }
                    log::success("update: SHA-256 verified");
                } else {
                    log::warn("update: SHA256SUMS не содержит файл " + zip_asset->name);
                }
            }
        } else {
            log::warn("update: не удалось скачать SHA256SUMS: " + dl_error);
        }
    }

    const auto extract_dir = work / L"extracted";
    std::string zip_error;
    if (!zip::extract(zip_path, extract_dir, zip_error)) {
        result.error = "распаковка не удалась: " + zip_error;
        return result;
    }

    // Locate the new executable (root or one nested folder).
    std::optional<std::filesystem::path> exe;
    for (const auto& f : fsx::list_dir(extract_dir)) {
        if (fsx::is_regular_file(f) && str::iequals(f.extension().string(), ".exe")) {
            exe = f;
            break;
        }
    }
    if (!exe) {
        for (const auto& f : fsx::list_dir_recursive(extract_dir, 2, 500)) {
            if (str::iequals(f.filename().string(), "RustOptimizer.exe")) {
                exe = f;
                break;
            }
        }
    }
    if (!exe) {
        result.error = "в архиве нет .exe";
        return result;
    }
    result.staged_exe = *exe;
    result.sha256 = ro::sha256_file(*exe);
    result.ok = true;
    return result;
}

bool spawn_applier(const std::filesystem::path& staged_exe, const std::filesystem::path& target_exe) {
    const auto self = fsx::exe_path();
    if (self.empty()) return false;
    std::wstring cmd = L"\"" + self.wstring() + L"\" --apply-update \"" + staged_exe.wstring() + L"\" \"" +
                       target_exe.wstring() + L"\" " + std::to_wstring(::GetCurrentProcessId());
    STARTUPINFOW si{};
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;
    PROCESS_INFORMATION pi{};
    std::vector<wchar_t> buffer(cmd.begin(), cmd.end());
    buffer.push_back(L'\0');
    if (!::CreateProcessW(nullptr, buffer.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi)) {
        log::error("update: cannot spawn applier: " + win::last_error_text());
        return false;
    }
    ::CloseHandle(pi.hThread);
    ::CloseHandle(pi.hProcess);
    return true;
}

int run_applier(const std::filesystem::path& staged_exe, const std::filesystem::path& target_exe,
                std::uint32_t parent_pid) {
    // 1. Wait for the running instance to release the image.
    if (parent_pid != 0) {
        HANDLE parent = ::OpenProcess(SYNCHRONIZE, FALSE, parent_pid);
        if (parent) {
            ::WaitForSingleObject(parent, 20000);
            ::CloseHandle(parent);
        }
    }
    if (!fsx::is_regular_file(staged_exe)) return 10;

    // 2. Swap, retrying while the old file is still mapped.
    bool replaced = false;
    for (int attempt = 0; attempt < 60; ++attempt) {
        const auto backup = target_exe.wstring() + L".old";
        if (fsx::is_regular_file(target_exe)) {
            ::MoveFileExW(target_exe.wstring().c_str(), backup.c_str(),
                          MOVEFILE_REPLACE_EXISTING | MOVEFILE_COPY_ALLOWED);
        }
        if (::MoveFileExW(staged_exe.wstring().c_str(), target_exe.wstring().c_str(),
                          MOVEFILE_REPLACE_EXISTING | MOVEFILE_COPY_ALLOWED)) {
            replaced = true;
            break;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(250));
    }
    if (!replaced) {
        log::error("update: cannot replace " + str::narrow(target_exe.wstring()));
        return 11;
    }

    // 3. Refresh the desktop / Start menu shortcuts so they point at the new
    //    build (the path is unchanged, but the icon cache and target are).
    shortcut::ensure(target_exe);

    // 4. Start the new build.
    const std::wstring params = L"";
    const HINSTANCE launched = ::ShellExecuteW(nullptr, L"open", target_exe.wstring().c_str(),
                                               params.empty() ? nullptr : params.c_str(), nullptr, SW_SHOWNORMAL);
    if (reinterpret_cast<INT_PTR>(launched) <= 32) {
        log::warn("update: ShellExecute failed, falling back to CreateProcess");
        std::wstring cmd = L"\"" + target_exe.wstring() + L"\"";
        STARTUPINFOW si{};
        si.cb = sizeof(si);
        PROCESS_INFORMATION pi{};
        std::vector<wchar_t> buffer(cmd.begin(), cmd.end());
        buffer.push_back(L'\0');
        if (::CreateProcessW(nullptr, buffer.data(), nullptr, nullptr, FALSE, 0, nullptr, nullptr, &si, &pi)) {
            ::CloseHandle(pi.hThread);
            ::CloseHandle(pi.hProcess);
        }
    }

    // 5. Remove the previous binary and the whole staging folder.
    std::this_thread::sleep_for(std::chrono::milliseconds(1500));
    fsx::remove_file(target_exe.wstring() + L".old");
    std::error_code ec;
    std::filesystem::path staging = staged_exe.parent_path();
    while (!staging.empty() && staging.has_parent_path()) {
        const std::wstring name = staging.filename().wstring();
        if (name.rfind(L"update_", 0) == 0) break;
        staging = staging.parent_path();
    }
    if (!staging.empty() && staging.has_parent_path()) {
        std::filesystem::remove_all(staging, ec);
    }
    return 0;
}

void cleanup_stale(const std::filesystem::path& exe) {
    // 1. The previous build is renamed to "<exe>.old" by the applier, but it is
    //    the applier's own image, so the delete can only succeed after that
    //    process has fully exited. Retry for a few seconds.
    if (!exe.empty()) {
        const std::filesystem::path old = std::filesystem::path(exe.wstring() + L".old");
        for (int attempt = 0; attempt < 40; ++attempt) {
            if (!fsx::is_regular_file(old)) break;
            if (fsx::remove_file(old)) {
                log::info("update: previous build removed");
                break;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(250));
        }
    }

    // 2. Drop staging folders left behind by an interrupted download. Fresh
    //    ones (< 5 min) may belong to the update worker that just started.
    std::error_code ec;
    const auto now = std::filesystem::file_time_type::clock::now();
    for (const auto& dir : fsx::list_dir(fsx::staging_dir())) {
        if (!fsx::is_directory(dir)) continue;
        if (dir.filename().wstring().rfind(L"update_", 0) != 0) continue;
        const auto stamp = std::filesystem::last_write_time(dir, ec);
        if (ec) continue;
        if (now - stamp < std::chrono::minutes(5)) continue;
        std::filesystem::remove_all(dir, ec);
        if (!ec) log::debug("update: stale staging removed");
    }
}

}  // namespace ro::update