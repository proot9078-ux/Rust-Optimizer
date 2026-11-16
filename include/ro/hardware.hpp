#pragma once
#include <cstdint>
#include <string>
#include <vector>

namespace ro {

struct GpuInfo {
    std::wstring name;
    std::string vendor;        // "nvidia" | "amd" | "intel" | "other"
    std::uint64_t vram_bytes = 0;
    bool valid = false;
    bool suggests_d3d11() const { return vendor == "intel"; }
};

struct HardwareInfo {
    std::wstring cpu_name;
    unsigned logical_cores = 0;
    unsigned physical_cores = 0;
    std::uint64_t ram_bytes = 0;
    GpuInfo gpu;
    std::wstring os;
    std::wstring os_display;   // "Windows 11 24H2 (build 26100)"
    bool hags_supported = false;
    bool hags_enabled = false;
    bool hags_reboot_pending = false;
    bool game_dvr_enabled = false;
    bool game_mode_enabled = false;
};

HardwareInfo gather();
std::vector<GpuInfo> enumerate_gpus();
bool set_hags(bool enabled, std::string& error);

}  // namespace ro
