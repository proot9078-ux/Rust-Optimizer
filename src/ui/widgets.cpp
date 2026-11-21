#include "ro/ui/widgets.hpp"

#include <algorithm>
#include <cstdio>

#pragma comment(lib, "d2d1.lib")
#pragma comment(lib, "dwrite.lib")

namespace ro::ui {

namespace {

std::wstring key_of(const D2D1_COLOR_F& c) {
    wchar_t buf[96];
    std::swprintf(buf, 96, L"%.4f_%.4f_%.4f_%.4f", c.r, c.g, c.b, c.a);
    return buf;
}

D2D1_RECT_F to_rect(const Rect& r) { return D2D1::RectF(r.x, r.y, r.x + r.w, r.y + r.h); }

// Blends `c` towards white (t > 0) or black (t < 0) by |t|. Keeps alpha.
D2D1_COLOR_F shade(const D2D1_COLOR_F& c, float t) {
    const float to = t >= 0.0f ? 1.0f : 0.0f;
    const float k = std::clamp(t >= 0.0f ? t : -t, 0.0f, 1.0f);
    return D2D1::ColorF(c.r + (to - c.r) * k, c.g + (to - c.g) * k, c.b + (to - c.b) * k, c.a);
}

}  // namespace

Painter::Painter(ID2D1RenderTarget* rt, IDWriteFactory* dw, const Themed& theme, float scale)
    : rt_(rt), dw_(dw), theme_(theme), scale_(scale) {}

Painter::~Painter() {
    for (auto& [key, brush] : brushes_) {
        (void)key;
        if (brush) brush->Release();
    }
    for (auto& [key, format] : formats_) {
        (void)key;
        if (format) format->Release();
    }
}

ID2D1SolidColorBrush* Painter::brush(const D2D1_COLOR_F& c) {
    const std::wstring key = key_of(c);
    for (auto& [k, b] : brushes_) {
        if (k == key) return b;
    }
    ID2D1SolidColorBrush* b = nullptr;
    if (FAILED(rt_->CreateSolidColorBrush(c, &b)) || !b) return nullptr;
    brushes_.emplace_back(key, b);
    return b;
}

IDWriteTextFormat* Painter::format(float size, int weight, int align, bool wrap) {
    wchar_t key[64];
    std::swprintf(key, 64, L"%d_%d_%d_%d", static_cast<int>(size * 10), weight, align, wrap ? 1 : 0);
    for (auto& [k, f] : formats_) {
        if (k == key) return f;
    }
    static const wchar_t* families[] = {L"Segoe UI Variable Text", L"Segoe UI", L"Tahoma"};
    IDWriteTextFormat* fmt = nullptr;
    for (const wchar_t* family : families) {
        if (SUCCEEDED(dw_->CreateTextFormat(family, nullptr, static_cast<DWRITE_FONT_WEIGHT>(weight),
                                            DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_STRETCH_NORMAL, size, L"ru-ru",
                                            &fmt)) &&
            fmt) {
            break;
        }
    }
    if (!fmt) return nullptr;
    fmt->SetTextAlignment(align == 1 ? DWRITE_TEXT_ALIGNMENT_CENTER
                                     : (align == 2 ? DWRITE_TEXT_ALIGNMENT_TRAILING : DWRITE_TEXT_ALIGNMENT_LEADING));
    fmt->SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_CENTER);
    fmt->SetWordWrapping(wrap ? DWRITE_WORD_WRAPPING_WRAP : DWRITE_WORD_WRAPPING_NO_WRAP);
    if (!wrap) {
        IDWriteInlineObject* trimming = nullptr;
        if (SUCCEEDED(dw_->CreateEllipsisTrimmingSign(fmt, &trimming)) && trimming) {
            DWRITE_TRIMMING trimming_options{DWRITE_TRIMMING_GRANULARITY_CHARACTER, 0, 0};
            fmt->SetTrimming(&trimming_options, trimming);
            trimming->Release();
        }
    }
    formats_.emplace_back(key, fmt);
    return fmt;
}

void Painter::fill(const Rect& r, const D2D1_COLOR_F& c) {
    if (auto b = brush(c)) rt_->FillRectangle(to_rect(r), b);
}

void Painter::fill_round(const Rect& r, float radius, const D2D1_COLOR_F& c) {
    if (auto b = brush(c)) rt_->FillRoundedRectangle(D2D1::RoundedRect(to_rect(r), radius, radius), b);
}

void Painter::stroke_round(const Rect& r, float radius, const D2D1_COLOR_F& c, float width) {
    if (auto b = brush(c)) rt_->DrawRoundedRectangle(D2D1::RoundedRect(to_rect(r), radius, radius), b, width);
}

void Painter::gradient_round(const Rect& r, float radius, const D2D1_COLOR_F& top, const D2D1_COLOR_F& bottom) {
    ID2D1GradientStopCollection* stops = nullptr;
    const D2D1_GRADIENT_STOP stop_data[2] = {{0.0f, top}, {1.0f, bottom}};
    if (FAILED(rt_->CreateGradientStopCollection(stop_data, 2, D2D1_GAMMA_2_2, D2D1_EXTEND_MODE_CLAMP, &stops)) ||
        !stops) {
        fill_round(r, radius, top);
        return;
    }
    ID2D1LinearGradientBrush* grad = nullptr;
    if (SUCCEEDED(rt_->CreateLinearGradientBrush(
            D2D1::LinearGradientBrushProperties(D2D1::Point2F(r.x, r.y), D2D1::Point2F(r.x, r.y + r.h)), stops,
            &grad)) &&
        grad) {
        rt_->FillRoundedRectangle(D2D1::RoundedRect(to_rect(r), radius, radius), grad);
        grad->Release();
    }
    stops->Release();
}

void Painter::line(float x1, float y1, float x2, float y2, const D2D1_COLOR_F& c, float width) {
    if (auto b = brush(c)) rt_->DrawLine(D2D1::Point2F(x1, y1), D2D1::Point2F(x2, y2), b, width);
}

void Painter::text(const std::wstring& s, const Rect& r, const D2D1_COLOR_F& c, float size, int weight, int align,
                   bool wrap, bool ellipsis) {
    (void)ellipsis;
    if (s.empty()) return;
    IDWriteTextFormat* fmt = format(size, weight, align, wrap);
    if (!fmt) return;
    auto b = brush(c);
    if (!b) return;
    // Vertical centring is done by DirectWrite's paragraph alignment.
    rt_->DrawTextW(s.c_str(), static_cast<UINT32>(s.size()), fmt, to_rect(r), b);
}

void Painter::toggle(const Rect& r, bool on, bool hovered) {
    const float h = r.h;
    const float w = h * 1.85f;
    const Rect track{r.x, r.y, w, h};
    fill_round(track, h * 0.5f, on ? theme_.accent : theme_.toggle_off);
    if (hovered && !on) stroke_round(track, h * 0.5f, theme_.text_muted, 1.0f);
    const float knob = h - 6.0f;
    const float x = on ? (track.x + track.w - knob - 3.0f) : (track.x + 3.0f);
    fill_round(Rect{x, track.y + 3.0f, knob, knob}, knob * 0.5f, on ? theme_.accent_text : theme_.text_dim);
}

void Painter::button(const Rect& r, const std::wstring& label, bool primary, bool hovered, bool enabled) {
    const float radius = r.h * 0.5f;
    if (primary) {
        // Vertical accent gradient with a brighter top edge; hover lifts it.
        const auto base = theme_.accent;
        const D2D1_COLOR_F top =
            enabled ? shade(base, hovered ? 0.34f : 0.22f) : theme_.toggle_off;
        const D2D1_COLOR_F bottom =
            enabled ? (hovered ? base : shade(base, -0.10f)) : theme_.toggle_off;
        gradient_round(r, radius, top, bottom);
        if (enabled && hovered) stroke_round(r, radius, shade(base, 0.45f), 1.2f);
        text(label, r, enabled ? theme_.accent_text : theme_.text_muted, r.h * 0.38f, 700, 1, false);
    } else {
        fill_round(r, radius, hovered ? theme_.card_hover : theme_.card);
        stroke_round(r, radius, hovered ? theme_.accent : theme_.border, hovered ? 1.4f : 1.0f);
        text(label, r, enabled ? theme_.text : theme_.text_muted, r.h * 0.36f, 500, 1, false);
    }
}

void Painter::progress(const Rect& r, float fraction, const D2D1_COLOR_F& color) {
    fill_round(r, r.h * 0.5f, theme_.toggle_off);
    const float f = std::clamp(fraction, 0.0f, 1.0f);
    if (f <= 0.0f) return;
    const float w = (std::max)(r.h, r.w * f);
    fill_round(Rect{r.x, r.y, w, r.h}, r.h * 0.5f, color);
}

void Painter::card(const Rect& r, bool hovered) {
    fill_round(r, 16.0f, hovered ? theme_.card_hover : theme_.card);
    stroke_round(r, 16.0f, hovered ? theme_.accent : theme_.border, hovered ? 1.4f : 1.0f);
}

}  // namespace ro::ui
