// Build-time icon generator.
// Produces the .ico used by the executable resource and by the in-app window
// icon. No binary asset is committed to the repository: the icon is drawn
// procedurally from ro::icon.
#include "ro/icon.hpp"

#include <cstdio>
#include <string>

int wmain(int argc, wchar_t** argv) {
    if (argc < 2) {
        std::fputs("usage: ro_icon_gen <output.ico>\n", stderr);
        return 2;
    }
    std::string err;
    if (!ro::icon::init()) {
        std::fputs("GDI+ init failed\n", stderr);
        return 3;
    }
    const bool ok = ro::icon::write_ico_file(std::filesystem::path(argv[1]), {16, 24, 32, 48, 64, 128, 256}, err);
    ro::icon::shutdown();
    if (!ok) {
        std::fprintf(stderr, "icon generation failed: %s\n", err.c_str());
        return 1;
    }
    std::printf("wrote %ls\n", argv[1]);
    return 0;
}
