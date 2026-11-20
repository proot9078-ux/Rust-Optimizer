#pragma once
#include <string>
#include <vector>

namespace ro::system_tweaks {

bool flush_dns(std::string& error);
// Resets the Winsock catalog (netsh winsock reset) - requires elevation and a
// reboot; offered only with an explicit confirmation in the UI.
bool reset_winsock(std::string& error);
bool set_tcp_autotuning(bool normal, std::string& error);

// Per-application compatibility switches (HKCU, no elevation required).
bool set_fullscreen_optimizations(const std::wstring& exe_path, bool enabled, std::string& error);
bool set_gpu_preference(const std::wstring& exe_path, int preference, std::string& error);
// preference: 0 = let Windows decide, 1 = power saving, 2 = high performance

bool set_game_dvr(bool enabled, std::string& error);
bool set_game_mode(bool enabled, std::string& error);
bool set_hags(bool enabled, std::string& error);

// Power scheme: switches to "Высокая производительность" (or Ultimate
// Performance when available) and remembers the original GUID, so high = false
// restores exactly what the user had. No registry edits, uses PowrProf.
bool set_power_plan(bool high, std::string& error);
bool power_plan_high();

struct GameDvrState {
    bool supported = true;
    bool enabled = false;
    bool game_mode = false;
};
GameDvrState query_game_dvr();

// Clears the shutdown/reboot pending flag for the current user (never touches
// system state, only HKCU MultiMedia flags used by the DVR switch).
bool open_config_folder(const std::wstring& path, std::string& error);

}  // namespace ro::system_tweaks
