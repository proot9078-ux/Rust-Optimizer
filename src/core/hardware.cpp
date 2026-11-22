#include "ro/hardware.hpp"

#include <windows.h>

#include <algorithm>
#include <cstdio>

#include "ro/affinity.hpp"
#include "ro/memory.hpp"
#include "ro/str.hpp"
#include "ro/win32.hpp"

namespace ro {

namespace {

constexpr const wchar_t* kDisplayClass =
    L"SYSTEM\\CurrentControlSet\\Control\\Class\\{4d36e968-e325-11ce-bfc1-08002be10318}";
constexpr const wchar_t* kGraphicsDrivers = L"SYSTEM\\CurrentControlSet\\Control\\GraphicsDrivers";

GpuInfo read_gpu_from(HKEY root, const std::wstring& sub) {
    GpuInfo g;
    const auto desc = win::reg_read_string(root, sub.c_str(), L"DriverDesc");
    if (!desc || desc->empty()) return g;
    g.name = *desc;
    if (auto vram = win::reg_read_qword(root, sub.c_str(), L"HardwareInformation.qwMemorySize")) {
        g.vram_bytes = *vram;
    } else if (auto adapter = win::reg_read_string(root, sub.c_str(), L"HardwareInformation.AdapterString")) {
        (void)adapter;
    }
    const std::string lowered = str::to_lower(str::narrow(g.name));
    if (str::icontains(lowered, "nvidia") || str::icontains(lowered, "geforce") || str::icontains(lowered, "rtx")) {
        g.vendor = "nvidia";
    } else if (str::icontains(lowered, "amd") || str::icontains(lowered, "radeon")) {
        g.vendor = "amd";
    } else if (str::icontains(lowered, "intel") || str::icontains(lowered, "arc") || str::icontains(lowered, "uhd")) {
        g.vendor = "intel";
    } else {
        g.vendor = "other";
    }
    g.valid = true;
    return g;
}

bool dword_to_bool(std::optional<std::uint32_t> v, bool fallback = false) {
    return v ? (*v != 0) : fallback;
}

}  // namespace

std::vector<GpuInfo> enumerate_gpus() {
    std::vector<GpuInfo> out;
    for (int i = 0; i < 16; ++i) {
        const std::wstring sub = std::wstring(kDisplayClass) + str::wfmt(L"\\%04d", i);
        GpuInfo g = read_gpu_from(HKEY_LOCAL_MACHINE, sub);
        if (!g.valid) continue;
        // Skip software/virtual adapters.
        if (str::icontains(str::narrow(g.name), "basic render") ||
            str::icontains(str::narrow(g.name), "remote display")) {
            continue;
        }
        if (g.vram_bytes == 0) g.vram_bytes = 0;
        out.push_back(std::move(g));
    }
    return out;
}

HardwareInfo gather() {
    HardwareInfo hw;
    const cpu::Topology t = cpu::detect();
    hw.cpu_name = t.cpu_name;
    hw.logical_cores = t.logical;
    hw.physical_cores = t.physical;

    const mem::Snapshot m = mem::snapshot();
    hw.ram_bytes = m.total_bytes;

    const auto gpus = enumerate_gpus();
    if (!gpus.empty()) {
        // Prefer the discrete adapter with the most VRAM.
        hw.gpu = *std::max_element(gpus.begin(), gpus.end(), [](const GpuInfo& a, const GpuInfo& b) {
            return a.vram_bytes < b.vram_bytes;
        });
    }

    DEVMODEW dm{};
    dm.dmSize = sizeof(dm);
    if (::EnumDisplaySettingsW(nullptr, ENUM_CURRENT_SETTINGS, &dm)) {
        hw.desktop_width = dm.dmPelsWidth;
        hw.desktop_height = dm.dmPelsHeight;
        // Some virtual/remote adapters report 0 or 1 Hz.
        hw.refresh_hz = dm.dmDisplayFrequency >= 24 ? dm.dmDisplayFrequency : 0;
    }

    hw.os = win::windows_build_string();
    const bool win11 = win::is_windows_11();
    hw.os_display = (win11 ? L"Windows 11" : L"Windows 10") + std::wstring(L" · ") + hw.os;

    const auto hw_sch = win::reg_read_dword(HKEY_LOCAL_MACHINE, kGraphicsDrivers, L"HwSchMode");
    hw.hags_supported = hw_sch.has_value();
    hw.hags_enabled = hw_sch.value_or(0) == 2;

    const auto dvr = win::reg_read_dword(HKEY_CURRENT_USER, L"System\\GameConfigStore", L"GameDVR_Enabled");
    hw.game_dvr_enabled = dword_to_bool(dvr, true);
    hw.game_mode_enabled = dword_to_bool(
        win::reg_read_dword(HKEY_CURRENT_USER, L"Software\\Microsoft\\GameBar", L"AutoGameModeEnabled"), true);
    return hw;
}

bool set_hags(bool enabled, std::string& error) {
    if (!win::is_admin()) {
        error = "требуются права администратора";
        return false;
    }
    const std::uint32_t mode = enabled ? 2u : 1u;
    if (!win::reg_write_dword(HKEY_LOCAL_MACHINE, kGraphicsDrivers, L"HwSchMode", mode)) {
        error = "не удалось записать HwSchMode: " + win::last_error_text();
        return false;
    }
    return true;
}

}  // namespace ro
