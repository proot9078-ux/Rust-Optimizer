#pragma once
#include <optional>
#include <string>
#include <vector>

#include "ro/settings.hpp"

namespace ro::epic {

struct Manifest {
    std::wstring app_name;
    std::wstring display_name;
    std::wstring install_location;
    std::wstring launch_executable;
    std::wstring catalog_item_id;
    std::wstring raw_path;
};

// Reads *.item manifests from ProgramData\Epic\EpicGamesLauncher\Data\Manifests.
std::vector<Manifest> read_manifests();
// Parses a single manifest JSON document (exposed for tests).
std::optional<Manifest> parse_manifest(std::string_view json_text);
// Returns the directory holding the manifests (may not exist).
std::filesystem::path manifests_dir();
// Reads launcherinstalled.dat as a secondary source.
std::vector<Manifest> read_launcher_installed();

GameInstall find_fortnite(std::vector<std::string>* trace = nullptr);
bool is_fortnite_name(std::string_view app_name);
// "%LOCALAPPDATA%\FortniteGame\Saved\Config\WindowsClient".
std::filesystem::path user_config_dir();

}  // namespace ro::epic
