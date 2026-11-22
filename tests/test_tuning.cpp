#include <catch_amalgamated.hpp>

#include "ro/tuning.hpp"

namespace {

ro::HardwareInfo machine(std::uint64_t ram_gb, std::uint64_t vram_gb, const char* vendor,
                         unsigned refresh_hz = 0) {
    ro::HardwareInfo hw;
    hw.ram_bytes = ram_gb * 1024ull * 1024ull * 1024ull;
    hw.gpu.valid = true;
    hw.gpu.vendor = vendor;
    hw.gpu.vram_bytes = vram_gb * 1024ull * 1024ull * 1024ull;
    hw.gpu.name = L"Test GPU";
    hw.refresh_hz = refresh_hz;
    hw.desktop_width = 1920;
    hw.desktop_height = 1080;
    return hw;
}

}  // namespace

TEST_CASE("16 GB / 6 GB NVIDIA keeps native resolution", "[tuning]") {
    const auto p = ro::tuning::tune(machine(16, 6, "nvidia"));
    REQUIRE(p.ram_mb == 16384u);
    REQUIRE(p.gc_buffer_mb == 2048);
    REQUIRE(p.max_mem_mb == 12288);
    REQUIRE(p.pool_size_mb == 2048);
    REQUIRE_FALSE(p.lowres);
    REQUIRE_FALSE(p.low_preset);
    REQUIRE(p.launch_options.find("-maxMem=12288") != std::string::npos);
    REQUIRE(p.launch_options.find("-gc.buffer 2048") != std::string::npos);
}

TEST_CASE("32 GB / 12 GB machine maxes out the buffers", "[tuning]") {
    const auto p = ro::tuning::tune(machine(32, 12, "amd"));
    REQUIRE(p.gc_buffer_mb == 4096);
    REQUIRE(p.max_mem_mb == 24576);
    REQUIRE(p.pool_size_mb == 4096);
    REQUIRE(p.launch_options.find("-gc.buffer 4096") != std::string::npos);
}

TEST_CASE("8 GB / 2 GB integrated machine drops to the low profile", "[tuning]") {
    const auto p = ro::tuning::tune(machine(8, 2, "intel"));
    REQUIRE(p.gc_buffer_mb == 1024);
    REQUIRE(p.max_mem_mb == 6144);
    REQUIRE(p.pool_size_mb == 1024);
    REQUIRE(p.lowres);
    REQUIRE(p.low_preset);
    REQUIRE(p.launch_options.find("-force-d3d11") != std::string::npos);
}

TEST_CASE("maxMem always leaves a quarter of RAM to Windows", "[tuning]") {
    for (const std::uint64_t gb : {4ull, 8ull, 16ull, 32ull, 64ull}) {
        const auto p = ro::tuning::tune(machine(gb, 8, "nvidia"));
        REQUIRE(p.max_mem_mb <= 24576);
        if (gb >= 8) REQUIRE(static_cast<std::uint64_t>(p.max_mem_mb) <= gb * 1024ull * 3ull / 4ull);
    }
}

TEST_CASE("summary mentions the display and the derived numbers", "[tuning]") {
    const auto p = ro::tuning::tune(machine(16, 6, "nvidia", 180));
    REQUIRE(p.summary.find(L"180 Гц") != std::wstring::npos);
    REQUIRE(p.summary.find(L"gc.buffer 2048") != std::wstring::npos);
}
