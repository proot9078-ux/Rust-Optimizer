#pragma once
#include <filesystem>
#include <optional>
#include <string>
#include <vector>

// Steam Launch Options writer for RUST (appid 252490).
//
// This module only touches the user's own Steam configuration: it never opens
// the game process and never modifies game memory, so it stays compatible with
// Easy Anti-Cheat. The file is edited surgically (a tiny KeyValues tokenizer
// locates the "252490" block), backed up first and replaced atomically.
namespace ro::steam_launch {

struct Result {
    bool ok = false;
    bool changed = false;
    std::filesystem::path file;
    std::filesystem::path backup_dir;
    std::string options;  // resulting LaunchOptions value
    std::string error;
};

// Recommended RUST launch options for the detected hardware. Values:
//   -high, -maxMem=<75%>, -malloc=system, -nolog, -window-mode exclusive,
//   -force-d3d11-no-singlethreaded (NVIDIA/AMD only) and -gc.buffer.
std::string recommended(unsigned ram_mb, const std::string& gpu_vendor, bool gc_4gb);

// Appends only the missing options: anything the user already set (including
// the same option with a different value) is preserved.
std::string merge_options(std::string_view existing, std::string_view recommended);

// KeyValues helpers (pure, unit tested).
std::string escape(std::string_view raw);
std::string unescape(std::string_view raw);
std::optional<std::string> get_launch_options(std::string_view text, std::string_view appid);
bool set_launch_options(std::string& text, std::string_view appid, std::string_view value,
                        std::string& error);

// Implementation helpers.
bool steam_running();
std::vector<std::filesystem::path> find_configs(const std::wstring& steam_dir);

// Writes the merged recommendation into the most recently used account config.
// Fails without touching anything when Steam is running.
Result apply(const std::wstring& steam_dir, unsigned ram_mb, const std::string& gpu_vendor,
             bool gc_4gb);
// Restores the newest "steam localconfig.vdf" backup made by this app.
Result revert(const std::wstring& steam_dir);

}  // namespace ro::steam_launch
