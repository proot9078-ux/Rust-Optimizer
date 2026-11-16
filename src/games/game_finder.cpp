#include "ro/game_finder.hpp"

#include <chrono>

#include "ro/epic.hpp"
#include "ro/fs.hpp"
#include "ro/log.hpp"
#include "ro/str.hpp"
#include "ro/win32.hpp"

namespace ro {

namespace {

bool install_alive(const GameInstall& g) {
    return g.valid && fsx::is_regular_file(std::filesystem::path(g.exe_path));
}

GameInstall from_cache(const GameCacheEntry& e) {
    GameInstall g;
    g.kind = e.kind;
    g.exe_path = e.exe_path;
    g.install_dir = e.install_dir;
    g.launcher = e.launcher;
    g.source = L"cache";
    g.valid = fsx::is_regular_file(std::filesystem::path(e.exe_path));
    if (g.valid) g.size_bytes = fsx::file_size(std::filesystem::path(e.exe_path));
    return g;
}

}  // namespace

FindResult find_games(const GameCache* cache, bool use_cache) {
    const auto started = std::chrono::steady_clock::now();
    FindResult result;

    if (use_cache && cache) {
        for (const auto& e : cache->load()) {
            if (str::iequals(e.kind, L"rust") && !result.rust.valid) result.rust = from_cache(e);
            if (str::iequals(e.kind, L"fortnite") && !result.fortnite.valid) result.fortnite = from_cache(e);
        }
        if (result.rust.valid) {
            result.trace.push_back("RUST: подтверждён кэш " + str::narrow(result.rust.exe_path));
            log::info("games: RUST from cache");
        }
        if (result.fortnite.valid) {
            result.trace.push_back("FORTNITE: подтверждён кэш " + str::narrow(result.fortnite.exe_path));
            log::info("games: Fortnite from cache");
        }
    }

    if (!result.rust.valid) {
        result.steam = steam::locate();
        result.rust = steam::find_rust(result.steam, &result.trace);
        if (result.rust.valid) {
            log::success("games: RUST located at " + str::narrow(result.rust.exe_path));
        } else {
            log::warn("games: RUST not found");
            result.trace.push_back("RUST: не найден (Steam/библиотеки проверены)");
        }
    } else if (result.steam.steam_dir.empty()) {
        result.steam = steam::locate();
    }

    if (!result.fortnite.valid) {
        result.fortnite = epic::find_fortnite(&result.trace);
        if (result.fortnite.valid) {
            log::success("games: Fortnite located at " + str::narrow(result.fortnite.exe_path));
        } else {
            log::warn("games: Fortnite not found");
            result.trace.push_back("FORTNITE: не найден (Epic-манифесты и диски проверены)");
        }
    }

    if (cache) {
        std::vector<GameCacheEntry> entries;
        const auto stamp = fsx::time_stamp();
        if (install_alive(result.rust)) {
            entries.push_back(GameCacheEntry{result.rust.kind, result.rust.exe_path, result.rust.install_dir,
                                             result.rust.launcher, result.rust.version, stamp});
        }
        if (install_alive(result.fortnite)) {
            entries.push_back(GameCacheEntry{result.fortnite.kind, result.fortnite.exe_path,
                                             result.fortnite.install_dir, result.fortnite.launcher,
                                             result.fortnite.version, stamp});
        }
        if (!entries.empty() && !cache->save(entries)) {
            log::warn("games: cache write failed");
        }
    }

    const auto elapsed = std::chrono::duration<double>(std::chrono::steady_clock::now() - started).count();
    result.elapsed = str::fmt("%.2f s", elapsed);
    log::info("games: detection finished in " + result.elapsed);
    return result;
}

}  // namespace ro
