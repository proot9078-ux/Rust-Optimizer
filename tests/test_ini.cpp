#include "catch_amalgamated.hpp"

#include <string>

#include "ro/ini.hpp"

using namespace ro;

namespace {
const char* kSample =
    "; Engine settings\n"
    "[SystemSettings]\n"
    "r.MotionBlurQuality=1\n"
    "r.BloomQuality=1\n"
    "\n"
    "[Other]\n"
    "Key=Value\n";
}

TEST_CASE("INI parser keeps comments, order and unknown keys", "[ini]") {
    const auto ini = IniFile::parse(kSample);
    REQUIRE(ini.get("SystemSettings", "r.MotionBlurQuality") == "1");
    REQUIRE(ini.get("Other", "Key") == "Value");
    REQUIRE(ini.has("Other", "key"));  // case-insensitive
    const auto text = ini.serialize();
    REQUIRE(text.find("; Engine settings") == 0);
    REQUIRE(text.find("[SystemSettings]") != std::string::npos);
    REQUIRE(text.find("r.BloomQuality=1") != std::string::npos);
    REQUIRE(text.find("\n\n[Other]") != std::string::npos);
}

TEST_CASE("INI serialize does not append spurious blank lines", "[ini]") {
    const auto ini = IniFile::parse("a=1\n");
    REQUIRE(ini.serialize() == "a=1\n");
}

TEST_CASE("INI set reports whether the value changed", "[ini]") {
    auto ini = IniFile::parse(kSample);
    REQUIRE_FALSE(ini.set("SystemSettings", "r.MotionBlurQuality", "1"));
    REQUIRE(ini.set("SystemSettings", "r.MotionBlurQuality", "0"));
    REQUIRE(ini.get("SystemSettings", "r.MotionBlurQuality") == "0");
    REQUIRE(ini.set("NewSection", "Fresh", "1"));
    REQUIRE(ini.get("NewSection", "Fresh") == "1");
}

TEST_CASE("INI erase removes a single key", "[ini]") {
    auto ini = IniFile::parse(kSample);
    REQUIRE(ini.erase("Other", "Key"));
    REQUIRE_FALSE(ini.has("Other", "Key"));
    REQUIRE_FALSE(ini.erase("Other", "Key"));
}

TEST_CASE("quoted values are unquoted on read", "[ini]") {
    auto ini = IniFile::parse("[S]\nName=\"hello world\"\n");
    REQUIRE(ini.get("S", "Name") == "hello world");
}

TEST_CASE("marked blocks can be written, replaced and removed", "[ini]") {
    auto ini = IniFile::parse("[SystemSettings]\nr.BloomQuality=1\n");
    REQUIRE(ini.set_marked_block("SystemSettings", "fortnite",
                                 {"r.MotionBlurQuality=0", "r.LensFlareQuality=0"}));
    REQUIRE(ini.has_marked_block("fortnite"));
    REQUIRE(ini.get("SystemSettings", "r.MotionBlurQuality") == "0");
    const auto ids = ini.marker_ids();
    REQUIRE(ids.size() == 1);
    REQUIRE(ids[0] == "fortnite");

    // Replacing the block must not duplicate it.
    REQUIRE(ini.set_marked_block("SystemSettings", "fortnite", {"r.MotionBlurQuality=0"}));
    REQUIRE(ini.get("SystemSettings", "r.MotionBlurQuality") == "0");
    REQUIRE(ini.marker_ids().size() == 1);

    REQUIRE(ini.remove_marked_block("fortnite"));
    REQUIRE_FALSE(ini.has_marked_block("fortnite"));
    REQUIRE_FALSE(ini.has("SystemSettings", "r.MotionBlurQuality"));
    // Untouched keys survive.
    REQUIRE(ini.get("SystemSettings", "r.BloomQuality") == "1");
}

TEST_CASE("CRLF files stay CRLF after edits", "[ini]") {
    auto ini = IniFile::parse("[S]\r\nA=1\r\n");
    REQUIRE(ini.uses_crlf());
    ini.set("S", "B", "2");
    const auto out = ini.serialize();
    REQUIRE(out.find("\r\n") != std::string::npos);
    REQUIRE(out.find("A=1\r\n") != std::string::npos);
    REQUIRE(out.find("B=2\r\n") != std::string::npos);
}

TEST_CASE("sections are listed once in order", "[ini]") {
    const auto ini = IniFile::parse("[B]\nx=1\n[A]\ny=2\n[B]\nz=3\n");
    const auto sections = ini.sections();
    REQUIRE(sections.size() == 2);
    REQUIRE(sections[0] == "B");
    REQUIRE(sections[1] == "A");
}
