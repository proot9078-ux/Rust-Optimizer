#include "catch_amalgamated.hpp"

#include <string>

#include "ro/updater.hpp"

using namespace ro;

TEST_CASE("semantic version comparison", "[updater]") {
    REQUIRE(update::compare_versions("1.0.0", "1.0.0") == 0);
    REQUIRE(update::compare_versions("v1.2.3", "1.2.3") == 0);
    REQUIRE(update::compare_versions("8.0.0", "7.9.9") == 1);
    REQUIRE(update::compare_versions("7.9.9", "8.0.0") == -1);
    REQUIRE(update::compare_versions("1.10", "1.9") == 1);
    REQUIRE(update::compare_versions("1.0", "1.0.1") == -1);
    REQUIRE(update::compare_versions("2.0.0-beta.1", "1.9.0") == 1);
}

TEST_CASE("GitHub release JSON is parsed", "[updater]") {
    const char* json = R"({
        "tag_name": "v8.0.0",
        "name": "Rust Optimizer 8.0.0",
        "body": "notes",
        "html_url": "https://github.com/proot9078-ux/Rust-Optimizer/releases/tag/v8.0.0",
        "published_at": "2026-11-15T10:00:00Z",
        "prerelease": false,
        "assets": [
            {"name": "RustOptimizer.zip", "browser_download_url": "https://example.com/a.zip",
             "size": 1234, "content_type": "application/zip"},
            {"name": "SHA256SUMS.txt", "browser_download_url": "https://example.com/sums",
             "size": 64, "content_type": "text/plain"}
        ]
    })";
    std::string error;
    const auto release = update::parse_release(json, &error);
    REQUIRE(release.has_value());
    REQUIRE(error.empty());
    REQUIRE(release->tag == "v8.0.0");
    REQUIRE(release->name == "Rust Optimizer 8.0.0");
    REQUIRE_FALSE(release->prerelease);
    REQUIRE(release->assets.size() == 2);
    REQUIRE(release->find_asset("RustOptimizer.zip") != nullptr);
    REQUIRE(release->find_asset("RustOptimizer.zip")->size == 1234);
    REQUIRE(release->find_first({".zip"}) != nullptr);
    REQUIRE(release->find_first({".zip"})->name == "RustOptimizer.zip");
    REQUIRE(release->find_asset("absent") == nullptr);
}

TEST_CASE("malformed release JSON is rejected, not thrown", "[updater]") {
    std::string error;
    REQUIRE_FALSE(update::parse_release("{not json", &error).has_value());
    REQUIRE_FALSE(error.empty());

    error.clear();
    REQUIRE_FALSE(update::parse_release("{\"name\":\"no tag\"}", &error).has_value());
    REQUIRE_FALSE(error.empty());
}
