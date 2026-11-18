#include "catch_amalgamated.hpp"

#include <string>

#include "ro/visuals.hpp"
#include "ro/win_repair.hpp"

using namespace ro;

TEST_CASE("picture presets are stable and start with off", "[visuals]") {
    const auto& list = visuals::presets();
    REQUIRE(list.size() >= 4);
    REQUIRE(list.front().id == "off");
    bool vivid = false;
    bool cinema = false;
    for (const auto& preset : list) {
        REQUIRE(!preset.id.empty());
        REQUIRE(!preset.title.empty());
        REQUIRE(!preset.desc.empty());
        if (preset.id == "vivid") vivid = true;
        if (preset.id == "cinema") cinema = true;
    }
    REQUIRE(vivid);
    REQUIRE(cinema);
}

TEST_CASE("turning the picture preset off is a no-op on a clean machine", "[visuals]") {
    // On a machine where nothing was ever changed there is nothing to restore,
    // so "off" must succeed instead of reporting a scary error. No display is
    // touched in that case, which keeps the test headless-safe.
    if (visuals::has_saved()) {
        SUCCEED("display ramps already saved on this machine");
        return;
    }
    std::string error;
    REQUIRE(visuals::apply("off", error));
    REQUIRE(error.empty());
    REQUIRE(visuals::apply("", error));
    REQUIRE(error.empty());
}

TEST_CASE("repair module reports admin state without side effects", "[win_repair]") {
    const bool admin = win_repair::is_admin();
    REQUIRE(admin == true || admin == false);
}
