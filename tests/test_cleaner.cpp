#include <catch_amalgamated.hpp>

#include <algorithm>
#include <set>
#include <string>

#include "ro/cleaner.hpp"

TEST_CASE("cleaner targets have unique ids", "[cleaner]") {
    const auto targets = ro::clean::targets();
    std::set<std::string> ids;
    for (const auto& t : targets) {
        REQUIRE(!t.id.empty());
        REQUIRE(!t.title.empty());
        REQUIRE(ids.insert(t.id).second);
    }
}

TEST_CASE("boost ids reference existing targets and stay non-empty", "[cleaner]") {
    const auto targets = ro::clean::targets();
    std::set<std::string> ids;
    for (const auto& t : targets) ids.insert(t.id);

    const auto boost = ro::clean::boost_ids();
    for (const auto& id : boost) REQUIRE(ids.count(id) == 1);
    REQUIRE(!boost.empty());
}

TEST_CASE("the user TEMP folder is always offered", "[cleaner]") {
    const auto targets = ro::clean::targets();
    const auto it = std::find_if(targets.begin(), targets.end(),
                                 [](const ro::clean::Target& t) { return t.id == "user_temp"; });
    REQUIRE(it != targets.end());
    REQUIRE(it->boost);
}

TEST_CASE("administrator-only targets are excluded from boost", "[cleaner]") {
    const auto boost = ro::clean::boost_ids();
    const auto has = [&boost](const char* id) {
        return std::find(boost.begin(), boost.end(), id) != boost.end();
    };
    REQUIRE_FALSE(has("windows_temp"));
    REQUIRE_FALSE(has("programdata_temp"));
    REQUIRE_FALSE(has("windows_update"));
    REQUIRE_FALSE(has("recycle_bin"));
}

TEST_CASE("scan with a bogus id deletes nothing", "[cleaner]") {
    const auto result = ro::clean::scan({"definitely-not-a-real-target"});
    REQUIRE(result.items.empty());
    REQUIRE(result.bytes == 0);
    REQUIRE(result.files == 0);
}
