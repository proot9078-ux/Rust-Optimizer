#pragma once
#include <filesystem>
#include <string>

#include "ro/ini.hpp"
#include "ro/json.hpp"
#include "ro/report.hpp"

namespace ro::rust {

struct Paths {
    std::filesystem::path install_dir;
    std::filesystem::path cfg_dir;
    std::filesystem::path client_cfg;
    std::filesystem::path keys_cfg;
};

struct Options {
    bool grass_off = true;
    bool grass_displacement = false;
    bool grass_shadowcast = false;
    bool grass_shadowreceive = false;
    bool ssaa_off = true;
    bool vsync_off = true;
    bool shadows_off = false;
    bool half_res_sss = true;
    bool pixellight_off = true;
    bool depth_of_field_off = true;
    bool motion_blur_off = true;
    bool parallax_off = false;
    bool shafts_off = true;
    bool chromatic_off = true;
    bool gc_buffer = false;
    int gc_buffer_mb = 2048;
    bool net_backup = false;
    bool launcher_gpu_high = false;
    std::string launch_options;  // informational: what the user set in Steam
};

// Resolves <install>\cfg\client.cfg, creating nothing.
Paths resolve_paths(const std::filesystem::path& rust_exe);

// Merges the tweaks into client.cfg. Only keys the game already understands are
// written; anything else is appended inside a marked block that can be removed
// cleanly. A timestamped backup is always created first.
ApplyReport apply(const Paths& p, const Options& opt);

// Removes every tweak written by this app and restores from the newest backup.
ApplyReport revert(const Paths& p, const std::filesystem::path& backup_dir);

json::Value to_json(const Options& o);
Options from_json(const json::Value& v);

// Launch-option recommendation for the current hardware.
std::string recommended_launch_options(unsigned ram_mb, const std::string& gpu_vendor);

}  // namespace ro::rust
