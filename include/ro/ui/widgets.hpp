#pragma once
#include <d2d1.h>
#include <dwrite.h>

#include <string>
#include <vector>

#include "ro/ui/theme.hpp"

namespace ro::ui {

struct Rect {
    float x = 0, y = 0, w = 0, h = 0;
    bool contains(float px, float py) const {
        return px >= x && px <= x + w && py >= y && py <= y + h;
    }
};

// Drawing helpers bound to one render target + DirectWrite factory.
class Painter {
public:
    Painter(ID2D1RenderTarget* rt, IDWriteFactory* dw, const Themed& theme, float scale);
    ~Painter();

    void fill(const Rect& r, const D2D1_COLOR_F& c);
    void fill_round(const Rect& r, float radius, const D2D1_COLOR_F& c);
    void stroke_round(const Rect& r, float radius, const D2D1_COLOR_F& c, float width = 1.0f);
    void gradient_round(const Rect& r, float radius, const D2D1_COLOR_F& top,
                        const D2D1_COLOR_F& bottom);
    void line(float x1, float y1, float x2, float y2, const D2D1_COLOR_F& c, float width = 1.0f);

    void text(const std::wstring& s, const Rect& r, const D2D1_COLOR_F& c, float size,
              int weight = 400, int align = 0 /*0 left,1 center,2 right*/, bool wrap = false,
              bool ellipsis = true);

    void toggle(const Rect& r, bool on, bool hovered);
    void button(const Rect& r, const std::wstring& label, bool primary, bool hovered,
                bool enabled = true);
    void progress(const Rect& r, float fraction, const D2D1_COLOR_F& color);
    void card(const Rect& r, bool hovered);

    const Themed& theme() const { return theme_; }
    float scale() const { return scale_; }

    ID2D1RenderTarget* rt() const { return rt_; }

private:
    struct TextFormatCache;
    ID2D1RenderTarget* rt_;
    IDWriteFactory* dw_;
    const Themed& theme_;
    float scale_;
    std::vector<std::pair<std::wstring, ID2D1SolidColorBrush*>> brushes_;
    ID2D1SolidColorBrush* brush(const D2D1_COLOR_F& c);
    IDWriteTextFormat* format(float size, int weight, int align, bool wrap);
    std::vector<std::pair<std::wstring, IDWriteTextFormat*>> formats_;
};

}  // namespace ro::ui
