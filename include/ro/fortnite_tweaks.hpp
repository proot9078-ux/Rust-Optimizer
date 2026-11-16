#pragma once
#include <filesystem>
#include <string>

#include "ro/json.hpp"
#include "ro/report.hpp"

namespace ro::fortnite {

struct Paths {
    std::filesystem::path install_dir;
    std::filesystem::path config_dir;        // %LOCALAPPDATA%\FortniteGame\Saved\Config\WindowsClient
    std::filesystem::path game_user_settings;
    std::filesystem::path engine_ini;
    std::filesystem::path game_ini;
};

struct Options {
    bool vsync_off = true;
    bool unlimited_fps = true;
    int frame_rate_limit = 0;   // 0 = uncapped
    bool fullscreen = true;
    bool motion_blur_off = true;
    bool bloom_off = true;
    bool lens_flare_off = true;
    bool depth_of_field_off = true;
    bool shadow_tweak = true;
    int shadow_resolution = 1024;
    bool streaming_pool = true;
    int pool_size_mb = 2048;
    bool dynamic_res_off = false;
    bool nanite_off = false;
};

Paths resolve_paths(const std::filesystem::path& fortnite_exe);
// The config directory exists independently of the game install.
Paths resolve_user_paths();

ApplyReport apply(const Paths& p, const Options& opt);
ApplyReport revert(const Paths& p, const std::filesystem::path& backup_dir);

json::Value to_json(const Options& o);
Options from_json(const json::Value& v);

}  // namespace ro::fortnite
