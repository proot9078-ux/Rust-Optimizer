#pragma once
#include <string>
#include <vector>

#include "ro/settings.hpp"
#include "ro/steam.hpp"

namespace ro {

struct FindResult {
    GameInstall rust;
    GameInstall fortnite;
    steam::Locator steam;
    std::vector<std::string> trace;  // step-by-step diagnostics for the UI
    std::string elapsed;             // "0.42 s"
};

// Locates both games. When `use_cache` is true the previously resolved paths
// are validated first (and re-used only if they still exist).
FindResult find_games(const GameCache* cache, bool use_cache);

}  // namespace ro
