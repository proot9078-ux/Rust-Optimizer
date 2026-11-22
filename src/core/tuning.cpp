#include "ro/tuning.hpp"

#include <algorithm>
#include <cstdint>

#include "ro/steam_launch.hpp"

namespace ro::tuning {

namespace {

constexpr std::uint64_t kGiB = 1024ull * 1024ull * 1024ull;

int round_down(int value, int step) { return value < 0 ? 0 : (value / step) * step; }

}  // namespace

Profile tune(const HardwareInfo& hw) {
    Profile p;
    p.ram_mb = static_cast<unsigned>(hw.ram_bytes / (1024ull * 1024ull));

    // Garbage collector buffer: RUST holds this many MB of managed heap, so it
    // has to scale with physical RAM or long sessions start to micro-stutter.
    if (p.ram_mb >= 30000u) {
        p.gc_buffer_mb = 4096;
    } else if (p.ram_mb >= 14000u) {
        p.gc_buffer_mb = 2048;
    } else {
        p.gc_buffer_mb = 1024;
    }

    // Never hand the whole machine to the game: Windows, Steam and the browser
    // still need a few GB, so 75% is the ceiling.
    if (p.ram_mb > 0) {
        const int share = static_cast<int>(static_cast<std::uint64_t>(p.ram_mb) * 3ull / 4ull);
        p.max_mem_mb = round_down(std::clamp(share, 4096, 24576), 512);
    }

    // Texture streaming pool for Fortnite: a 6 GB card does not benefit from a
    // 4 GB pool, it just starves the rest of the frame.
    if (hw.gpu.vram_bytes >= 8ull * kGiB) {
        p.pool_size_mb = 4096;
    } else if (hw.gpu.vram_bytes >= 4ull * kGiB) {
        p.pool_size_mb = 2048;
    } else {
        p.pool_size_mb = 1024;
    }

    // Below 4 GB of VRAM (or an integrated Intel adapter) native resolution is
    // not affordable; everywhere else keep the image sharp.
    const bool weak_gpu = hw.gpu.valid && hw.gpu.vram_bytes > 0 && hw.gpu.vram_bytes < 4ull * kGiB;
    p.lowres = weak_gpu || hw.gpu.vendor == "intel";
    p.low_preset = weak_gpu;

    p.launch_options = steam_launch::recommended(p.ram_mb, hw.gpu.vendor, p.gc_buffer_mb >= 4096);

    std::wstring s;
    // Round to the nearest GB: firmware reserves memory, so 16 GB machines
    // report ~15.7 GB and "15 ГБ" would look like a bug.
    s += std::to_wstring((p.ram_mb + 512u) / 1024u) + L" ГБ ОЗУ";
    if (hw.gpu.valid && !hw.gpu.name.empty()) s += L" · " + hw.gpu.name;
    if (hw.refresh_hz > 0 && hw.desktop_width > 0) {
        s += L" · " + std::to_wstring(hw.desktop_width) + L"×" + std::to_wstring(hw.desktop_height) +
             L"@" + std::to_wstring(hw.refresh_hz) + L" Гц";
    }
    s += L" → gc.buffer " + std::to_wstring(p.gc_buffer_mb) + L", -maxMem=" +
         std::to_wstring(p.max_mem_mb) + L", пул " + std::to_wstring(p.pool_size_mb) + L" МБ";
    if (p.lowres) s += L", рендер 85%";
    if (p.low_preset) s += L", низкий профиль графики";
    p.summary = std::move(s);
    return p;
}

}  // namespace ro::tuning
