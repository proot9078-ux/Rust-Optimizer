#include "catch_amalgamated.hpp"

#include <string>

#include "ro/steam.hpp"
#include "ro/str.hpp"

using namespace ro;

TEST_CASE("libraryfolders.vdf path entries are found", "[steam]") {
    const char* vdf =
        "\"libraryfolders\"\n"
        "{\n"
        "\t\"0\"\n"
        "\t{\n"
        "\t\t\"path\"\t\t\"C:\\\\Program Files (x86)\\\\Steam\"\n"
        "\t\t\"apps\"\n"
        "\t\t{\n"
        "\t\t\t\"252490\"\t\t\"123\"\n"
        "\t\t}\n"
        "\t}\n"
        "\t\"1\"\n"
        "\t{\n"
        "\t\t\"path\"\t\t\"D:\\\\SteamLibrary\"\n"
        "\t}\n"
        "}\n";
    const auto libs = steam::parse_library_folders_vdf(vdf);
    REQUIRE(libs.size() == 2);
    REQUIRE(str::narrow(libs[0]) == "C:\\Program Files (x86)\\Steam");
    REQUIRE(str::narrow(libs[1]) == "D:\\SteamLibrary");
}

TEST_CASE("legacy numeric-only libraryfolders.vdf is supported", "[steam]") {
    const char* vdf =
        "\"LibraryFolders\"\n"
        "{\n"
        "\t\"TimeNextStatsReport\"\t\t\"123\"\n"
        "\t\"1\"\t\t\"D:\\\\Games\\\\Steam\"\n"
        "}\n";
    const auto libs = steam::parse_library_folders_vdf(vdf);
    REQUIRE(libs.size() == 1);
    REQUIRE(str::narrow(libs[0]) == "D:\\Games\\Steam");
}

TEST_CASE("appmanifest values are parsed", "[steam]") {
    const char* acf =
        "\"AppState\"\n"
        "{\n"
        "\t\"appid\"\t\t\"252490\"\n"
        "\t\"name\"\t\t\"Rust\"\n"
        "\t\"installdir\"\t\t\"Rust\"\n"
        "\t\"buildid\"\t\t\"123456\"\n"
        "}\n";
    REQUIRE(str::narrow(steam::read_acf_value(acf, L"name").value()) == "Rust");
    REQUIRE(str::narrow(steam::read_acf_value(acf, L"INSTALLDIR").value()) == "Rust");
    REQUIRE(str::narrow(steam::read_acf_value(acf, L"appid").value()) == "252490");
    REQUIRE_FALSE(steam::read_acf_value(acf, L"missing").has_value());
}

TEST_CASE("launch options follow hardware", "[steam]") {
    const std::string low = steam::launch_options(8, "nvidia", false);
    REQUIRE(low.find("-high") != std::string::npos);
    REQUIRE(low.find("-maxMem=") != std::string::npos);
    REQUIRE(low.find("-malloc=system") != std::string::npos);

    const std::string intel = steam::launch_options(16, "intel", false);
    REQUIRE(intel.find("-force-d3d11") != std::string::npos);

    const std::string big = steam::launch_options(64, "amd", true);
    REQUIRE(big.find("-gc.buffer 4096") != std::string::npos);
}
