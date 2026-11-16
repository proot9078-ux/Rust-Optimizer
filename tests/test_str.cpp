#include "catch_amalgamated.hpp"

#include <string>
#include <vector>

#include "ro/str.hpp"

using namespace ro;

TEST_CASE("UTF-8 <-> UTF-16 round trip", "[str]") {
    const std::string original = "Rust Optimizer — тест 日本語";
    const std::wstring wide = str::widen(original);
    REQUIRE_FALSE(wide.empty());
    REQUIRE(str::narrow(wide) == original);
}

TEST_CASE("trim strips only surrounding whitespace", "[str]") {
    REQUIRE(str::trim("  a b  ") == "a b");
    REQUIRE(str::trim("\r\n\t x \t") == "x");
    REQUIRE(str::trim("").empty());
    REQUIRE(str::trim(L"  y  ") == std::wstring(L"y"));
}

TEST_CASE("case helpers", "[str]") {
    REQUIRE(str::to_lower("HeLLo") == "hello");
    REQUIRE(str::iequals("RustClient.exe", "rustclient.EXE"));
    REQUIRE_FALSE(str::iequals("a", "ab"));
    REQUIRE(str::starts_with("RustOptimizer.exe", "Rust"));
    REQUIRE(str::ends_with("app.ico", ".ico"));
    REQUIRE(str::contains("abc", "b"));
    REQUIRE(str::icontains("Fortnite", "FORT"));
}

TEST_CASE("split keeps empty fields and joins back", "[str]") {
    const auto parts = str::split("a:b::c", ':');
    REQUIRE(parts.size() == 4);
    REQUIRE(parts[2].empty());
    REQUIRE(str::join(parts, ":") == "a:b::c");
    REQUIRE(str::split("", ':').size() == 1);
}

TEST_CASE("line splitting normalises CRLF", "[str]") {
    const auto lines = str::split_lines("a\r\nb\r\n\r\nc");
    REQUIRE(lines.size() == 4);
    REQUIRE(lines[1] == "b");
    REQUIRE(lines[2].empty());
    REQUIRE(lines[3] == "c");
}

TEST_CASE("newline normalisation strips BOM and CR", "[str]") {
    const std::string input = "\xEF\xBB\xBF" "a\r\nb\rc\n";
    REQUIRE(str::normalise_newlines(input) == "a\nb\nc\n");
}

TEST_CASE("number and bool parsing", "[str]") {
    REQUIRE(str::to_int("42").value() == 42);
    REQUIRE_FALSE(str::to_int("4x2").has_value());
    REQUIRE(str::to_bool("true").value());
    REQUIRE_FALSE(str::to_bool("off").value());
    REQUIRE(str::parse_bool("yes", false));
    REQUIRE_FALSE(str::parse_bool("nonsense", false));
    REQUIRE(str::parse_int("bad", 7) == 7);
}

TEST_CASE("human readable sizes", "[str]") {
    REQUIRE(str::human_bytes(512) == "512 B");
    REQUIRE(str::human_bytes(1536) == "1.5 KB");
    REQUIRE(str::human_ram_gb(16ull * 1024 * 1024 * 1024) == "16.0 GB");
}

TEST_CASE("one_line removes control characters", "[str]") {
    REQUIRE(str::one_line("a\nb\tc") == "a b c");
}

TEST_CASE("unquote handles escaped quotes", "[str]") {
    REQUIRE(str::unquote("\"a\"") == "a");
    REQUIRE(str::unquote("plain") == "plain");
    REQUIRE(str::unquote("\"a\\\"b\"") == "a\"b");
}

TEST_CASE("fnv1a is stable and distinguishes input", "[str]") {
    REQUIRE(str::fnv1a("abc") == str::fnv1a("abc"));
    REQUIRE(str::fnv1a("abc") != str::fnv1a("abd"));
}
