#include "ro/icon.hpp"

// IStream / STREAM_SEEK_* are needed for the PNG encoder; MinGW's gdiplus.h
// only forward-declares them, so pull the COM interface in first.
#include <objidl.h>
#include <gdiplus.h>

#include <cmath>
#include <cstdio>
#include <cstring>
#include <memory>
#include <vector>

#include "ro/fs.hpp"

namespace ro::icon {

namespace {

ULONG_PTR g_token = 0;
bool g_ready = false;

constexpr float kPi = 3.14159265358979323846f;

Gdiplus::Color argb(unsigned char a, unsigned char r, unsigned char g, unsigned char b) {
    return Gdiplus::Color(a, r, g, b);
}

// Draws the mark at `size` px. Kept in one place so the window icon and the
// .ico file can never drift apart.
void paint(Gdiplus::Graphics& g, int size) {
    const float s = static_cast<float>(size);
    g.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    g.SetPixelOffsetMode(Gdiplus::PixelOffsetModeHighQuality);

    // Rounded plate with a vertical purple gradient.
    const float inset = s * 0.03f;
    Gdiplus::GraphicsPath plate;
    const float radius = s * 0.22f;
    const Gdiplus::RectF rect(inset, inset, s - inset * 2, s - inset * 2);
    {
        const float d = radius * 2;
        plate.AddArc(rect.X, rect.Y, d, d, 180, 90);
        plate.AddArc(rect.GetRight() - d, rect.Y, d, d, 270, 90);
        plate.AddArc(rect.GetRight() - d, rect.GetBottom() - d, d, d, 0, 90);
        plate.AddArc(rect.X, rect.GetBottom() - d, d, d, 90, 90);
        plate.CloseFigure();
    }
    Gdiplus::LinearGradientBrush bg(Gdiplus::PointF(0, 0), Gdiplus::PointF(s, s),
                                    argb(255, 124, 58, 237), argb(255, 30, 20, 60));
    g.FillPath(&bg, &plate);

    // Subtle top highlight.
    Gdiplus::LinearGradientBrush shine(Gdiplus::PointF(0, 0), Gdiplus::PointF(0, s * 0.55f),
                                       argb(70, 255, 255, 255), argb(0, 255, 255, 255));
    g.FillPath(&shine, &plate);

    // Gear ring with 10 teeth.
    const float cx = s * 0.5f;
    const float cy = s * 0.5f;
    const float r_outer = s * 0.34f;
    const float r_ring = s * 0.25f;
    const float r_hole = s * 0.17f;
    const int teeth = 10;
    std::vector<Gdiplus::PointF> gear;
    gear.reserve(static_cast<std::size_t>(teeth) * 4);
    for (int i = 0; i < teeth; ++i) {
        const float a0 = (static_cast<float>(i) / teeth) * 2 * kPi;
        const float step = (2 * kPi / teeth) / 4.0f;
        const float a1 = a0 + step;
        const float a2 = a0 + step * 2;
        const float a3 = a0 + step * 3;
        gear.emplace_back(cx + r_outer * std::cos(a0), cy + r_outer * std::sin(a0));
        gear.emplace_back(cx + r_outer * std::cos(a1), cy + r_outer * std::sin(a1));
        gear.emplace_back(cx + r_ring * std::cos(a2), cy + r_ring * std::sin(a2));
        gear.emplace_back(cx + r_ring * std::cos(a3), cy + r_ring * std::sin(a3));
    }
    Gdiplus::GraphicsPath ring;
    ring.AddPolygon(gear.data(), static_cast<INT>(gear.size()));
    ring.SetFillMode(Gdiplus::FillModeWinding);
    // Punch the centre hole using an alternate-wound inner circle.
    ring.AddEllipse(cx - r_hole, cy - r_hole, r_hole * 2, r_hole * 2);
    ring.SetFillMode(Gdiplus::FillModeAlternate);
    Gdiplus::LinearGradientBrush metal(Gdiplus::PointF(0, 0), Gdiplus::PointF(0, s),
                                       argb(255, 233, 213, 255), argb(255, 167, 139, 250));
    g.FillPath(&metal, &ring);

    // Lightning bolt in the middle.
    Gdiplus::PointF bolt[] = {
        {cx + s * 0.06f, cy - s * 0.145f}, {cx - s * 0.085f, cy + s * 0.015f},
        {cx - s * 0.005f, cy + s * 0.015f}, {cx - s * 0.045f, cy + s * 0.15f},
        {cx + s * 0.10f, cy - s * 0.02f},  {cx + s * 0.015f, cy - s * 0.02f},
    };
    Gdiplus::GraphicsPath bolt_path;
    bolt_path.AddPolygon(bolt, static_cast<INT>(std::size(bolt)));
    Gdiplus::SolidBrush bolt_brush(argb(255, 12, 8, 24));
    g.FillPath(&bolt_brush, &bolt_path);

    // Outer hairline for contrast on light taskbars.
    Gdiplus::Pen border(argb(120, 196, 181, 253), s * 0.012f);
    g.DrawPath(&border, &plate);
}

std::unique_ptr<Gdiplus::Bitmap> render(int size) {
    // PixelFormat32bppARGB is a macro in gdipluspixelformats.h and must not be
    // namespace-qualified (MSVC and MinGW both expand it to a cast).
    auto bmp = std::make_unique<Gdiplus::Bitmap>(static_cast<INT>(size), static_cast<INT>(size), PixelFormat32bppARGB);
    if (bmp->GetLastStatus() != Gdiplus::Ok) return nullptr;
    Gdiplus::Graphics g(bmp.get());
    paint(g, size);
    return bmp;
}

std::vector<unsigned char> png_bytes(Gdiplus::Bitmap& bmp, bool& ok) {
    ok = false;
    IStream* stream = nullptr;
    if (::CreateStreamOnHGlobal(nullptr, TRUE, &stream) != S_OK) return {};
    CLSID encoder{};
    UINT num = 0, size = 0;
    Gdiplus::GetImageEncodersSize(&num, &size);
    if (size == 0) {
        stream->Release();
        return {};
    }
    std::vector<unsigned char> buffer(size);
    auto* codecs = reinterpret_cast<Gdiplus::ImageCodecInfo*>(buffer.data());
    Gdiplus::GetImageEncoders(num, size, codecs);
    for (UINT i = 0; i < num; ++i) {
        if (wcscmp(codecs[i].MimeType, L"image/png") == 0) {
            encoder = codecs[i].Clsid;
            break;
        }
    }
    if (encoder == CLSID{}) {
        stream->Release();
        return {};
    }
    if (bmp.Save(stream, &encoder, nullptr) != Gdiplus::Ok) {
        stream->Release();
        return {};
    }
    STATSTG stat{};
    if (stream->Stat(&stat, STATFLAG_NONAME) != S_OK) {
        stream->Release();
        return {};
    }
    const ULONG bytes = static_cast<ULONG>(stat.cbSize.QuadPart);
    std::vector<unsigned char> data(bytes);
    LARGE_INTEGER zero{};
    stream->Seek(zero, STREAM_SEEK_SET, nullptr);
    ULONG read = 0;
    const HRESULT hr = stream->Read(data.data(), bytes, &read);
    stream->Release();
    if (hr != S_OK || read != bytes) return {};
    ok = true;
    return data;
}

}  // namespace

bool init() {
    if (g_ready) return true;
    Gdiplus::GdiplusStartupInput input;
    if (Gdiplus::GdiplusStartup(&g_token, &input, nullptr) != Gdiplus::Ok) return false;
    g_ready = true;
    return true;
}

void shutdown() {
    if (!g_ready) return;
    Gdiplus::GdiplusShutdown(g_token);
    g_token = 0;
    g_ready = false;
}

HICON create(int size) {
    if (size <= 0) size = 32;
    if (!g_ready && !init()) return nullptr;
    auto bmp = render(size);
    if (!bmp) return nullptr;
    HICON hicon = nullptr;
    if (bmp->GetHICON(&hicon) != Gdiplus::Ok) return nullptr;
    return hicon;
}

bool write_ico_file(const std::filesystem::path& file, const std::vector<int>& sizes, std::string& error) {
    if (!g_ready && !init()) {
        error = "GDI+ РЅРµ РёРЅРёС†РёР°Р»РёР·РёСЂРѕРІР°РЅ";
        return false;
    }
    struct Frame {
        int size;
        std::vector<unsigned char> data;
    };
    std::vector<Frame> frames;
    for (int size : sizes) {
        if (size <= 0 || size > 256) continue;
        auto bmp = render(size);
        if (!bmp) {
            error = "РЅРµ СѓРґР°Р»РѕСЃСЊ РѕС‚СЂРёСЃРѕРІР°С‚СЊ РєР°РґСЂ";
            return false;
        }
        bool ok = false;
        auto data = png_bytes(*bmp, ok);
        if (!ok) {
            error = "РЅРµ СѓРґР°Р»РѕСЃСЊ Р·Р°РєРѕРґРёСЂРѕРІР°С‚СЊ PNG";
            return false;
        }
        frames.push_back(Frame{size, std::move(data)});
    }
    if (frames.empty()) {
        error = "РЅРµС‚ РєР°РґСЂРѕРІ РґР»СЏ Р·Р°РїРёСЃРё";
        return false;
    }

    fsx::ensure_dir(file.parent_path());
    FILE* f = _wfopen(file.wstring().c_str(), L"wb");
    if (!f) {
        error = "РЅРµ СѓРґР°Р»РѕСЃСЊ СЃРѕР·РґР°С‚СЊ " + file.filename().string();
        return false;
    }
    const std::uint16_t count = static_cast<std::uint16_t>(frames.size());
    const unsigned char header[6] = {0, 0, 1, 0, static_cast<unsigned char>(count & 0xFF),
                                     static_cast<unsigned char>(count >> 8)};
    std::fwrite(header, 1, sizeof(header), f);

    const std::uint32_t first_offset = 6 + 16u * count;
    std::uint32_t offset = first_offset;
    bool ok = true;
    for (const auto& frame : frames) {
        unsigned char entry[16]{};
        entry[0] = static_cast<unsigned char>(frame.size == 256 ? 0 : frame.size);
        entry[1] = static_cast<unsigned char>(frame.size == 256 ? 0 : frame.size);
        entry[2] = 0;  // palette
        entry[3] = 0;  // reserved
        entry[4] = 1;  // planes lo
        entry[5] = 0;  // planes hi
        entry[6] = 32; // bits per pixel
        entry[7] = 0;
        const std::uint32_t bytes = static_cast<std::uint32_t>(frame.data.size());
        entry[8] = static_cast<unsigned char>(bytes & 0xFF);
        entry[9] = static_cast<unsigned char>((bytes >> 8) & 0xFF);
        entry[10] = static_cast<unsigned char>((bytes >> 16) & 0xFF);
        entry[11] = static_cast<unsigned char>((bytes >> 24) & 0xFF);
        entry[12] = static_cast<unsigned char>(offset & 0xFF);
        entry[13] = static_cast<unsigned char>((offset >> 8) & 0xFF);
        entry[14] = static_cast<unsigned char>((offset >> 16) & 0xFF);
        entry[15] = static_cast<unsigned char>((offset >> 24) & 0xFF);
        ok = ok && std::fwrite(entry, 1, sizeof(entry), f) == sizeof(entry);
        offset += bytes;
    }
    for (const auto& frame : frames) {
        ok = ok && std::fwrite(frame.data.data(), 1, frame.data.size(), f) == frame.data.size();
    }
    std::fclose(f);
    if (!ok) {
        error = "РѕС€РёР±РєР° Р·Р°РїРёСЃРё .ico";
        fsx::remove_file(file);
        return false;
    }
    return true;
}

}  // namespace ro::icon

