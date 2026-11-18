#include "ro/steam_launch.hpp"

#include <windows.h>

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <string_view>
#include <system_error>
#include <vector>

#include "ro/backup.hpp"
#include "ro/fs.hpp"
#include "ro/log.hpp"
#include "ro/process.hpp"
#include "ro/str.hpp"
#include "ro/win32.hpp"

namespace ro::steam_launch {

namespace {

constexpr std::string_view kRustAppId = "252490";
constexpr std::string_view kBackupLabel = "steam localconfig.vdf";

enum class Kind { Text, Open, Close };

struct Token {
    Kind kind = Kind::Text;
    std::size_t begin = 0;
    std::size_t end = 0;  // exclusive
    std::string text;     // unescaped for Text tokens
};

struct Block {
    bool found = false;
    std::size_t open = 0;   // token index of '{'
    std::size_t close = 0;  // token index of '}'
};

bool iequals(std::string_view a, std::string_view b) { return str::iequals(a, b); }

bool tokenize(std::string_view text, std::vector<Token>& out, std::string& error) {
    out.clear();
    out.reserve(text.size() / 6 + 8);
    std::size_t i = 0;
    const std::size_t n = text.size();
    while (i < n) {
        const char c = text[i];
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
            ++i;
            continue;
        }
        if (c == '/' && i + 1 < n && text[i + 1] == '/') {
            const auto eol = text.find('\n', i);
            i = eol == std::string_view::npos ? n : eol + 1;
            continue;
        }
        if (c == '{' || c == '}') {
            Token t;
            t.kind = c == '{' ? Kind::Open : Kind::Close;
            t.begin = i;
            t.end = i + 1;
            out.push_back(std::move(t));
            ++i;
            continue;
        }
        if (c == '"') {
            Token t;
            t.begin = i;
            ++i;
            std::string value;
            bool closed = false;
            while (i < n) {
                const char ch = text[i];
                if (ch == '\\' && i + 1 < n) {
                    const char next = text[i + 1];
                    value.push_back(next == 'n' ? '\n' : next == 't' ? '\t' : next);
                    i += 2;
                    continue;
                }
                if (ch == '"') {
                    closed = true;
                    ++i;
                    break;
                }
                if (ch == '\r' || ch == '\n') break;
                value.push_back(ch);
                ++i;
            }
            if (!closed) {
                error = "повреждённая строка KeyValues: нет закрывающей кавычки";
                return false;
            }
            t.end = i;
            t.text = std::move(value);
            out.push_back(std::move(t));
            continue;
        }
        // Unquoted token (conditionals like [$WIN32], stray values).
        Token t;
        t.begin = i;
        while (i < n && text[i] != ' ' && text[i] != '\t' && text[i] != '\r' && text[i] != '\n' &&
               text[i] != '{' && text[i] != '}') {
            ++i;
        }
        t.end = i;
        t.text.assign(text.substr(t.begin, t.end - t.begin));
        out.push_back(std::move(t));
    }
    return true;
}

std::size_t matching_close(const std::vector<Token>& t, std::size_t open) {
    int depth = 0;
    for (std::size_t i = open; i < t.size(); ++i) {
        if (t[i].kind == Kind::Open) ++depth;
        else if (t[i].kind == Kind::Close && --depth == 0) return i;
    }
    return t.size() - 1;
}

// Finds "key" { ... } inside the token range [from, to).
Block find_block(const std::vector<Token>& t, std::size_t from, std::size_t to, std::string_view key) {
    Block b;
    std::size_t i = from;
    while (i < to && i < t.size()) {
        if (t[i].kind == Kind::Open) {
            i = matching_close(t, i) + 1;
            continue;
        }
        if (t[i].kind == Kind::Close) {
            ++i;
            continue;
        }
        if (i + 1 < to && t[i + 1].kind == Kind::Open) {
            if (iequals(t[i].text, key)) {
                b.found = true;
                b.open = i + 1;
                b.close = matching_close(t, i + 1);
                return b;
            }
            i = matching_close(t, i + 1) + 1;
            continue;
        }
        if (i + 1 < to && t[i + 1].kind == Kind::Text) {
            i += 2;
        } else {
            ++i;
        }
    }
    return b;
}

std::optional<std::size_t> find_string_value(const std::vector<Token>& t, const Block& block,
                                             std::string_view key) {
    if (!block.found) return std::nullopt;
    std::size_t i = block.open + 1;
    while (i + 1 < block.close) {
        if (t[i].kind == Kind::Text && t[i + 1].kind == Kind::Text && iequals(t[i].text, key)) {
            return i + 1;
        }
        if (t[i].kind == Kind::Open) {
            i = matching_close(t, i) + 1;
            continue;
        }
        ++i;
    }
    return std::nullopt;
}

std::size_t line_start(std::string_view text, std::size_t pos) {
    const auto p = text.rfind('\n', pos);
    return p == std::string_view::npos ? 0 : p + 1;
}

std::string line_indent(std::string_view text, std::size_t pos) {
    const std::size_t start = line_start(text, pos);
    std::size_t i = start;
    while (i < text.size() && (text[i] == ' ' || text[i] == '\t')) ++i;
    return std::string(text.substr(start, i - start));
}

std::string newline_of(std::string_view text) {
    return text.find("\r\n") != std::string_view::npos ? "\r\n" : "\n";
}

std::vector<std::string> split_tokens(std::string_view text) {
    std::vector<std::string> out;
    std::size_t i = 0;
    while (i < text.size()) {
        while (i < text.size() && (text[i] == ' ' || text[i] == '\t')) ++i;
        if (i >= text.size()) break;
        const std::size_t start = i;
        if (text[i] == '"') {
            ++i;
            while (i < text.size() && text[i] != '"') {
                if (text[i] == '\\' && i + 1 < text.size()) ++i;
                ++i;
            }
            if (i < text.size()) ++i;
        } else {
            while (i < text.size() && text[i] != ' ' && text[i] != '\t') ++i;
        }
        out.emplace_back(text.substr(start, i - start));
    }
    return out;
}

std::string option_key(std::string_view token) {
    if (token.empty() || token[0] != '-') return {};
    const auto eq = token.find('=');
    return std::string(token.substr(0, eq));
}

bool write_atomic_replace(const std::filesystem::path& file, std::string_view data) {
    const std::filesystem::path tmp = file.wstring() + L".ro.tmp";
    if (!fsx::write_text(tmp, data)) return false;
    if (::MoveFileExW(tmp.c_str(), file.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        return true;
    }
    log::error("steam: MoveFileEx failed for " + str::narrow(file.wstring()) + ": " +
               str::narrow(win::last_error_text()));
    fsx::remove_file(tmp);
    return false;
}

}  // namespace

std::string escape(std::string_view raw) {
    std::string out;
    out.reserve(raw.size() + 8);
    for (const char c : raw) {
        if (c == '\\' || c == '"') out.push_back('\\');
        out.push_back(c);
    }
    return out;
}

std::string unescape(std::string_view raw) {
    std::string out;
    out.reserve(raw.size());
    for (std::size_t i = 0; i < raw.size(); ++i) {
        if (raw[i] == '\\' && i + 1 < raw.size()) ++i;
        out.push_back(raw[i]);
    }
    return out;
}

std::string recommended(unsigned ram_mb, const std::string& gpu_vendor, bool gc_4gb) {
    std::string options = "-high";
    if (ram_mb > 0) {
        std::uint64_t max_mem = static_cast<std::uint64_t>(ram_mb) * 3 / 4;
        options += " -maxMem=" + std::to_string(max_mem);
    }
    options += " -malloc=system -nolog -window-mode exclusive";
    if (gpu_vendor == "nvidia" || gpu_vendor == "amd") {
        options += " -force-d3d11-no-singlethreaded";
    } else if (gpu_vendor == "intel") {
        options += " -force-d3d11";
    }
    const int buffer = gc_4gb || ram_mb >= 30000 ? 4096 : 2048;
    options += " -gc.buffer " + std::to_string(buffer);
    return options;
}

std::string merge_options(std::string_view existing, std::string_view recommended_text) {
    const std::string base = str::trim(existing);
    const auto existing_tokens = split_tokens(base);
    std::vector<std::string> keys;
    keys.reserve(existing_tokens.size());
    for (const auto& token : existing_tokens) {
        const auto key = option_key(token);
        if (!key.empty()) keys.push_back(key);
    }

    // Recommended options arrive as "-flag" or "-flag value" units.
    const auto tokens = split_tokens(recommended_text);
    std::string out = base;
    for (std::size_t i = 0; i < tokens.size();) {
        const std::string& token = tokens[i];
        std::string key = option_key(token);
        if (key.empty()) {
            ++i;
            continue;
        }
        std::string unit = token;
        std::size_t used = 1;
        if (i + 1 < tokens.size() && option_key(tokens[i + 1]).empty()) {
            unit += " " + tokens[i + 1];
            used = 2;
        }
        if (std::find(keys.begin(), keys.end(), key) == keys.end()) {
            if (!out.empty()) out.push_back(' ');
            out += unit;
            keys.push_back(std::move(key));
        }
        i += used;
    }
    return out;
}

std::optional<std::string> get_launch_options(std::string_view text, std::string_view appid) {
    std::vector<Token> tokens;
    std::string error;
    if (!tokenize(text, tokens, error)) return std::nullopt;
    Block root = find_block(tokens, 0, tokens.size(), "UserLocalConfigStore");
    if (!root.found) return std::nullopt;
    const std::string_view path[] = {"Software", "Valve", "Steam", "apps"};
    Block cur = root;
    for (const std::string_view key : path) {
        cur = find_block(tokens, cur.open + 1, cur.close, key);
        if (!cur.found) return std::nullopt;
    }
    Block app = find_block(tokens, cur.open + 1, cur.close, appid);
    if (!app.found) return std::nullopt;
    const auto value = find_string_value(tokens, app, "LaunchOptions");
    if (!value) return std::nullopt;
    return tokens[*value].text;
}

bool set_launch_options(std::string& text, std::string_view appid, std::string_view value,
                        std::string& error) {
    std::vector<Token> tokens;
    if (!tokenize(text, tokens, error)) return false;
    Block root = find_block(tokens, 0, tokens.size(), "UserLocalConfigStore");
    if (!root.found) {
        error = "в localconfig.vdf нет блока UserLocalConfigStore";
        return false;
    }
    Block cur = root;
    for (const std::string_view key : {"Software", "Valve", "Steam", "apps"}) {
        cur = find_block(tokens, cur.open + 1, cur.close, key);
        if (!cur.found) {
            error = "в localconfig.vdf нет блока \"" + std::string(key) + "\"";
            return false;
        }
    }

    const std::string quoted = "\"" + escape(value) + "\"";
    Block app = find_block(tokens, cur.open + 1, cur.close, appid);
    if (app.found) {
        const auto existing = find_string_value(tokens, app, "LaunchOptions");
        if (existing) {
            const Token& t = tokens[*existing];
            text.replace(t.begin, t.end - t.begin, quoted);
            return true;
        }
        const Token& close = tokens[app.close];
        const std::size_t at = line_start(text, close.begin);
        const std::string indent = line_indent(text, close.begin);
        const std::string nl = newline_of(text);
        text.insert(at, indent + "\t\"LaunchOptions\"\t\t" + quoted + nl);
        return true;
    }

    // No app entry yet: add one inside "apps".
    const Token& close = tokens[cur.close];
    const std::size_t at = line_start(text, close.begin);
    const std::string indent = line_indent(text, close.begin);
    const std::string nl = newline_of(text);
    const std::string inner = indent + "\t";
    std::string block;
    block += inner + "\"" + std::string(appid) + "\"" + nl;
    block += inner + "{" + nl;
    block += inner + "\t\"LaunchOptions\"\t\t" + quoted + nl;
    block += inner + "}" + nl;
    text.insert(at, block);
    return true;
}

bool steam_running() {
    return proc::is_running(L"steam.exe") || proc::is_running(L"steamwebhelper.exe");
}

std::vector<std::filesystem::path> find_configs(const std::wstring& steam_dir) {
    std::vector<std::filesystem::path> out;
    if (steam_dir.empty()) return out;
    const std::filesystem::path userdata = std::filesystem::path(steam_dir) / L"userdata";
    for (const auto& account : fsx::list_dir(userdata)) {
        const auto cfg = account / L"config" / L"localconfig.vdf";
        if (fsx::is_regular_file(cfg)) out.push_back(cfg);
    }
    std::error_code ec;
    std::sort(out.begin(), out.end(), [&ec](const auto& a, const auto& b) {
        return std::filesystem::last_write_time(a, ec) > std::filesystem::last_write_time(b, ec);
    });
    return out;
}

Result apply(const std::wstring& steam_dir, unsigned ram_mb, const std::string& gpu_vendor,
             bool gc_4gb) {
    Result result;
    if (steam_running()) {
        result.error = "Steam запущен — закройте Steam и повторите";
        return result;
    }
    if (proc::is_running(L"RustClient.exe")) {
        result.error = "RUST запущен — закройте игру и повторите";
        return result;
    }
    const auto configs = find_configs(steam_dir);
    if (configs.empty()) {
        result.error = "localconfig.vdf не найден (Steam не найден или вход не выполнялся)";
        return result;
    }
    result.file = configs.front();
    const auto text = fsx::read_text(result.file);
    if (!text) {
        result.error = "localconfig.vdf не читается";
        return result;
    }

    const std::string current = get_launch_options(*text, kRustAppId).value_or("");
    const std::string merged = merge_options(current, recommended(ram_mb, gpu_vendor, gc_4gb));
    result.options = merged;
    if (merged == current) {
        result.ok = true;
        result.changed = false;
        log::info("steam: launch options already up to date");
        return result;
    }

    std::string edited = *text;
    std::string error;
    if (!set_launch_options(edited, kRustAppId, merged, error)) {
        result.error = error;
        return result;
    }

    std::string backup_error;
    result.backup_dir = backup::create(kBackupLabel);
    if (!backup::add_file(result.backup_dir, result.file, kBackupLabel, backup_error)) {
        result.error = "бэкап не создан: " + backup_error;
        return result;
    }

    if (!write_atomic_replace(result.file, edited)) {
        result.error = "не удалось записать localconfig.vdf";
        return result;
    }

    // Re-read: a truncated or reformatted write would be silent data loss.
    const auto verify = fsx::read_text(result.file);
    if (!verify) {
        result.error = "localconfig.vdf не читается после записи";
        return result;
    }
    const auto written = get_launch_options(*verify, kRustAppId);
    if (!written || *written != merged) {
        // Put the original back; the backup is authoritative.
        std::string restore_error;
        backup::restore(result.backup_dir, restore_error);
        result.error = "проверка записи не удалась, файл восстановлен из бэкапа";
        return result;
    }

    result.ok = true;
    result.changed = true;
    log::success("steam: LaunchOptions for 252490 updated (" + std::to_string(merged.size()) + " chars)");
    return result;
}

Result revert(const std::wstring& steam_dir) {
    Result result;
    if (steam_running()) {
        result.error = "Steam запущен — закройте Steam и повторите";
        return result;
    }
    const auto dir = backup::latest_for(kBackupLabel);
    if (dir.empty()) {
        result.error = "бэкап Launch Options не найден";
        return result;
    }
    const auto manifest = backup::load(dir);
    if (!manifest) {
        result.error = "манифест бэкапа повреждён";
        return result;
    }
    for (const auto& entry : manifest->entries) {
        if (str::iequals(entry.label, kBackupLabel)) {
            result.file = std::filesystem::path(str::widen(entry.file));
            break;
        }
    }
    if (result.file.empty()) {
        // Fall back to the newest account config of this Steam install.
        const auto configs = find_configs(steam_dir);
        if (configs.empty()) {
            result.error = "localconfig.vdf не найден";
            return result;
        }
        result.file = configs.front();
    }
    std::string error;
    if (!backup::restore(dir, error)) {
        result.error = error;
        return result;
    }
    result.ok = true;
    result.changed = true;
    result.backup_dir = dir;
    if (const auto text = fsx::read_text(result.file)) {
        result.options = get_launch_options(*text, kRustAppId).value_or("");
    }
    log::success("steam: launch options restored from backup");
    return result;
}

}  // namespace ro::steam_launch
