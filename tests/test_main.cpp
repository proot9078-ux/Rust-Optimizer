#include "catch_amalgamated.hpp"

#include <string>

#include "ro/log.hpp"
#include "ro/str.hpp"
#include "ro/version.hpp"

TEST_CASE("build identity is wired from CMake", "[main]") {
    REQUIRE(std::string(ro::kVersion).find('.') != std::string::npos);
    REQUIRE(std::string(ro::kAppId) == "RustOptimizer");
    REQUIRE(std::string(ro::kGithubOwner) == "proot9078-ux");
    REQUIRE(std::string(ro::kGithubRepo) == "Rust-Optimizer");
}

TEST_CASE("logger never throws and keeps records", "[main][log]") {
    ro::log::info("unit-test message");
    const auto all = ro::log::Logger::instance().all();
    REQUIRE_FALSE(all.empty());
    bool found = false;
    for (const auto& r : all) {
        if (r.text == "unit-test message") found = true;
    }
    REQUIRE(found);
}
