#include <catch_amalgamated.hpp>

#include "ro/rust_tweaks.hpp"

namespace {
ro::rust::Options aggressive() {
    ro::rust::Options o;
    o.grass_off = true;
    o.clouds_off = true;
    o.fog_off = true;
    o.quality_low = true;
    o.maxdecals_off = true;
    o.occlusion_on = true;
    o.lowres = false;
    o.gc_buffer = true;
    o.gc_buffer_mb = 4096;
    return o;
}
}  // namespace

TEST_CASE("rust options survive a JSON round-trip", "[rust]") {
    const auto before = aggressive();
    const auto after = ro::rust::from_json(ro::rust::to_json(before));
    REQUIRE(after.grass_off == before.grass_off);
    REQUIRE(after.clouds_off == before.clouds_off);
    REQUIRE(after.fog_off == before.fog_off);
    REQUIRE(after.quality_low == before.quality_low);
    REQUIRE(after.maxdecals_off == before.maxdecals_off);
    REQUIRE(after.occlusion_on == before.occlusion_on);
    REQUIRE(after.lowres == before.lowres);
    REQUIRE(after.gc_buffer == before.gc_buffer);
    REQUIRE(after.gc_buffer_mb == before.gc_buffer_mb);
}

TEST_CASE("volumetrics default to off and quality defaults to minimum", "[rust]") {
    const ro::rust::Options defaults;
    REQUIRE(defaults.clouds_off);
    REQUIRE(defaults.fog_off);
    REQUIRE(defaults.grass_off);
    REQUIRE(defaults.quality_low);
    REQUIRE_FALSE(defaults.lowres);
}

TEST_CASE("launch options mention the right buffer for 16 GB", "[rust]") {
    const auto opts = ro::rust::recommended_launch_options(16384, "nvidia");
    REQUIRE(opts.find("-high") != std::string::npos);
    REQUIRE(opts.find("-maxMem=16384") != std::string::npos);
    REQUIRE(opts.find("-gc.buffer 2048") != std::string::npos);
}
