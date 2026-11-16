#include "catch_amalgamated.hpp"

#include <windows.h>

#include <filesystem>
#include <fstream>
#include <string>

#include "ro/fs.hpp"

namespace fs = std::filesystem;
using namespace ro;

namespace {

struct TempDir {
    fs::path path;
    TempDir() {
        path = fs::temp_directory_path() /
               ("ro-tests-" + std::to_string(::GetCurrentProcessId()) + "-" + fsx::time_stamp());
        std::error_code ec;
        fs::create_directories(path, ec);
    }
    ~TempDir() {
        std::error_code ec;
        fs::remove_all(path, ec);
    }
};

}  // namespace

TEST_CASE("text files round trip through write/read", "[fs]") {
    TempDir tmp;
    const auto file = tmp.path / "sample.txt";
    REQUIRE(fsx::write_text(file, "line1\nline2\n"));
    const auto text = fsx::read_text(file);
    REQUIRE(text.has_value());
    REQUIRE(*text == "line1\nline2\n");
    REQUIRE(fsx::file_size(file) == 12);
    REQUIRE(fsx::is_regular_file(file));
}

TEST_CASE("atomic write replaces the previous content", "[fs]") {
    TempDir tmp;
    const auto file = tmp.path / "sub" / "value.json";
    REQUIRE(fsx::ensure_dir(file.parent_path()));
    REQUIRE(fsx::write_text_atomic(file, "old"));
    REQUIRE(fsx::write_text_atomic(file, "new"));
    REQUIRE(fsx::read_text(file).value() == "new");
}

TEST_CASE("missing files are reported without throwing", "[fs]") {
    TempDir tmp;
    REQUIRE_FALSE(fsx::exists(tmp.path / "nope"));
    REQUIRE_FALSE(fsx::read_text(tmp.path / "nope").has_value());
    REQUIRE(fsx::file_size(tmp.path / "nope") == 0);
    REQUIRE(fsx::list_dir(tmp.path / "nope").empty());
}

TEST_CASE("directory listing and removal", "[fs]") {
    TempDir tmp;
    REQUIRE(fsx::write_text(tmp.path / "a.txt", "a"));
    REQUIRE(fsx::write_text(tmp.path / "b.txt", "b"));
    REQUIRE(fsx::list_dir(tmp.path).size() == 2);
    REQUIRE(fsx::remove_file(tmp.path / "a.txt"));
    REQUIRE(fsx::list_dir(tmp.path).size() == 1);
}

TEST_CASE("find_file_under respects depth and file name", "[fs]") {
    TempDir tmp;
    const auto nested = tmp.path / "one" / "two" / "three";
    REQUIRE(fsx::ensure_dir(nested));
    REQUIRE(fsx::write_text(nested / "target.cfg", "x"));
    const auto found = fsx::find_file_under(tmp.path, L"target.cfg", 4);
    REQUIRE(found.has_value());
    REQUIRE(found->filename() == L"target.cfg");
    REQUIRE_FALSE(fsx::find_file_under(tmp.path, L"target.cfg", 1).has_value());
}

TEST_CASE("time stamp is filename safe", "[fs]") {
    const std::string stamp = fsx::time_stamp();
    REQUIRE(stamp.size() >= 10);
    REQUIRE(stamp.find(':') == std::string::npos);
    REQUIRE(stamp.find('/') == std::string::npos);
}

TEST_CASE("self-contained directories live under local appdata", "[fs]") {
    const auto base = fsx::data_dir();
    REQUIRE(fsx::log_dir().wstring().find(base.wstring()) == 0);
    REQUIRE(fsx::profile_dir().wstring().find(base.wstring()) == 0);
    REQUIRE(fsx::backup_root().wstring().find(base.wstring()) == 0);
}
