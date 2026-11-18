#include "catch_amalgamated.hpp"

#include <cstring>
#include <string>

#include "ro/steam_launch.hpp"

using namespace ro;

namespace {

const char* kConfig =
    "\"UserLocalConfigStore\"\n"
    "{\n"
    "\t\"Software\"\n"
    "\t{\n"
    "\t\t\"Valve\"\n"
    "\t\t{\n"
    "\t\t\t\"Steam\"\n"
    "\t\t\t{\n"
    "\t\t\t\t\"apps\"\n"
    "\t\t\t\t{\n"
    "\t\t\t\t\t\"252490\"\n"
    "\t\t\t\t\t{\n"
    "\t\t\t\t\t\t\"LastPlayed\"\t\t\"1700000000\"\n"
    "\t\t\t\t\t\t\"LaunchOptions\"\t\t\"-high -malloc=system\"\n"
    "\t\t\t\t\t}\n"
    "\t\t\t\t\t\"730\"\n"
    "\t\t\t\t\t{\n"
    "\t\t\t\t\t\t\"LaunchOptions\"\t\t\"-novid\"\n"
    "\t\t\t\t\t}\n"
    "\t\t\t\t}\n"
    "\t\t\t}\n"
    "\t\t}\n"
    "\t}\n"
    "}\n";

// Same document without the RUST app entry.
const char* kConfigNoApp =
    "\"UserLocalConfigStore\"\n"
    "{\n"
    "\t\"Software\"\n"
    "\t{\n"
    "\t\t\"Valve\"\n"
    "\t\t{\n"
    "\t\t\t\"Steam\"\n"
    "\t\t\t{\n"
    "\t\t\t\t\"apps\"\n"
    "\t\t\t\t{\n"
    "\t\t\t\t\t\"730\"\n"
    "\t\t\t\t\t{\n"
    "\t\t\t\t\t\t\"LaunchOptions\"\t\t\"-novid\"\n"
    "\t\t\t\t\t}\n"
    "\t\t\t\t}\n"
    "\t\t\t}\n"
    "\t\t}\n"
    "\t}\n"
    "}\n";

}  // namespace

TEST_CASE("launch options value is read from localconfig", "[steam_launch]") {
    const auto value = steam_launch::get_launch_options(kConfig, "252490");
    REQUIRE(value.has_value());
    REQUIRE(*value == "-high -malloc=system");
    REQUIRE_FALSE(steam_launch::get_launch_options(kConfig, "999").has_value());
}

TEST_CASE("launch options are replaced without touching other apps", "[steam_launch]") {
    std::string text = kConfig;
    std::string error;
    REQUIRE(steam_launch::set_launch_options(text, "252490", "-high -maxMem=8192", error));
    REQUIRE(steam_launch::get_launch_options(text, "252490").value() == "-high -maxMem=8192");
    REQUIRE(steam_launch::get_launch_options(text, "730").value() == "-novid");
    REQUIRE(text.find("LastPlayed") != std::string::npos);
}

TEST_CASE("missing LaunchOptions key is inserted inside the app block", "[steam_launch]") {
    std::string text = kConfig;
    const std::size_t pos = text.find("\"LaunchOptions\"\t\t\"-high");
    REQUIRE(pos != std::string::npos);
    text.erase(pos, std::strlen("\"LaunchOptions\"\t\t\"-high -malloc=system\""));
    REQUIRE_FALSE(steam_launch::get_launch_options(text, "252490").has_value());

    std::string error;
    REQUIRE(steam_launch::set_launch_options(text, "252490", "-high -nolog", error));
    REQUIRE(steam_launch::get_launch_options(text, "252490").value() == "-high -nolog");
    // Still a well-formed document for the other app.
    REQUIRE(steam_launch::get_launch_options(text, "730").value() == "-novid");
}

TEST_CASE("whole app block is created when RUST was never launched", "[steam_launch]") {
    std::string text = kConfigNoApp;
    std::string error;
    REQUIRE(steam_launch::set_launch_options(text, "252490", "-high -maxMem=8192", error));
    REQUIRE(steam_launch::get_launch_options(text, "252490").value() == "-high -maxMem=8192");
    REQUIRE(steam_launch::get_launch_options(text, "730").value() == "-novid");
}

TEST_CASE("quotes and backslashes survive a round trip", "[steam_launch]") {
    std::string text = kConfig;
    const std::string value = "-high -custom=\"a b\" -path=C:\\Games";
    std::string error;
    REQUIRE(steam_launch::set_launch_options(text, "252490", value, error));
    REQUIRE(steam_launch::get_launch_options(text, "252490").value() == value);
}

TEST_CASE("merge keeps the user's own flags", "[steam_launch]") {
    const std::string merged =
        steam_launch::merge_options("-high -maxMem=4096 -gc.buffer 1024", "-high -maxMem=8192 -nolog -gc.buffer 2048");
    REQUIRE(merged.find("-maxMem=4096") != std::string::npos);
    REQUIRE(merged.find("-maxMem=8192") == std::string::npos);
    REQUIRE(merged.find("-gc.buffer 1024") != std::string::npos);
    REQUIRE(merged.find("-gc.buffer 2048") == std::string::npos);
    REQUIRE(merged.find("-nolog") != std::string::npos);
    // Nothing is duplicated.
    REQUIRE(merged.find("-high", merged.find("-high") + 1) == std::string::npos);
}

TEST_CASE("recommended options follow hardware", "[steam_launch]") {
    const std::string nvidia = steam_launch::recommended(16384, "nvidia", false);
    REQUIRE(nvidia.find("-maxMem=12288") != std::string::npos);
    REQUIRE(nvidia.find("-gc.buffer 2048") != std::string::npos);
    REQUIRE(nvidia.find("-force-d3d11-no-singlethreaded") != std::string::npos);

    const std::string big = steam_launch::recommended(65536, "amd", true);
    REQUIRE(big.find("-gc.buffer 4096") != std::string::npos);

    const std::string intel = steam_launch::recommended(8192, "intel", false);
    REQUIRE(intel.find("-force-d3d11") != std::string::npos);
    REQUIRE(intel.find("no-singlethreaded") == std::string::npos);
}

TEST_CASE("CRLF documents stay valid and keep their line endings", "[steam_launch]") {
    std::string text;
    for (const char c : std::string(kConfigNoApp)) {
        if (c == '\n') text.push_back('\r');
        text.push_back(c);
    }
    std::string error;
    REQUIRE(steam_launch::set_launch_options(text, "252490", "-high -nolog", error));
    REQUIRE(steam_launch::get_launch_options(text, "252490").value() == "-high -nolog");
    REQUIRE(text.find("\r\n") != std::string::npos);
    // No bare LF was introduced by the insertion.
    for (std::size_t i = 0; i < text.size(); ++i) {
        if (text[i] != '\n') continue;
        REQUIRE(i > 0);
        REQUIRE(text[i - 1] == '\r');
    }
}
