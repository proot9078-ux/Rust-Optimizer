#include "ro/ui/app_window.hpp"

#include <windows.h>
#include <commdlg.h>
#include <d2d1.h>
#include <dwrite.h>
#include <shellapi.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cwchar>
#include <functional>
#include <iterator>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "ro/backup.hpp"
#include "ro/cleaner.hpp"
#include "ro/diagnostics.hpp"
#include "ro/fs.hpp"
#include "ro/game_finder.hpp"
#include "ro/hardware.hpp"
#include "ro/icon.hpp"
#include "ro/log.hpp"
#include "ro/memory.hpp"
#include "ro/process.hpp"
#include "ro/profiles.hpp"
#include "ro/settings.hpp"
#include "ro/shortcut.hpp"
#include "ro/steam_launch.hpp"
#include "ro/str.hpp"
#include "ro/system_tweaks.hpp"
#include "ro/ui/pages.hpp"
#include "ro/ui/theme.hpp"
#include "ro/ui/widgets.hpp"
#include "ro/updater.hpp"
#include "ro/version.hpp"
#include "ro/visuals.hpp"
#include "ro/win32.hpp"
#include "ro/win_repair.hpp"

namespace ro::ui {

namespace {

constexpr int kSidebarWidth = 236;
constexpr int kHeaderHeight = 108;
constexpr int kFooterHeight = 92;
constexpr int kPadding = 28;
constexpr int kRowGap = 10;
constexpr UINT_PTR kTimerId = 1;
constexpr UINT_PTR kAnimTimerId = 2;
constexpr UINT WM_APP_REFRESH = WM_APP + 1;
constexpr UINT WM_APP_QUIT = WM_APP + 2;

struct NavItem {
    const char* id;
    const wchar_t* label;
};

const NavItem kNav[] = {
    {"overview", L"Обзор"},   {"rust", L"RUST"},         {"fortnite", L"FORTNITE"},
    {"system", L"Система"},   {"cleaner", L"Очистка"},   {"diagnostics", L"Диагностика"},
    {"profiles", L"Профили"}, {"settings", L"Настройки"}, {"logs", L"Логи"},
};

struct Shared {
    std::mutex mutex;
    AppSettings settings;
    HardwareInfo hw;
    cpu::Topology cpu;
    FindResult games;
    std::map<std::string, bool> toggles;
    std::vector<log::Record> logs;
    std::wstring status = L"Инициализация…";
    std::atomic<bool> busy{false};
    std::atomic<int> progress{0};
    std::atomic<bool> closing{false};
    // Set by the autopilot: close the window as soon as a game starts, even if
    // the user switched "close_on_launch" off.
    std::atomic<bool> close_after_launch{false};
    // A worker changed settings and the UI thread must persist them (it owns
    // the toggle map, so saving from the worker would drop recent switches).
    std::atomic<bool> settings_dirty{false};
    HWND hwnd = nullptr;
    bool update_available = false;
    std::string latest_version;
    std::filesystem::path pending_update;
    // Mandatory auto-update: once a newer release is found the app downloads,
    // swaps the binary and restarts itself; the UI locks into a progress card.
    std::atomic<bool> update_mandatory{false};
    std::atomic<bool> update_installing{false};
    std::atomic<bool> update_checking{false};
    std::atomic<int> update_progress{0};
    std::wstring update_version;
    std::wstring update_status = L"Проверка обновлений…";
    std::wstring update_error;
    std::chrono::steady_clock::time_point last_purge{};
};

struct SharedSink : log::Sink {
    std::shared_ptr<Shared> state;
    void on_log(const log::Record& record) override {
        {
            std::lock_guard<std::mutex> lock(state->mutex);
            state->logs.push_back(record);
            if (state->logs.size() > 800) state->logs.erase(state->logs.begin(), state->logs.begin() + 200);
        }
        if (!state->closing.load() && state->hwnd) ::PostMessageW(state->hwnd, WM_APP_REFRESH, 0, 0);
    }
};

struct Hit {
    Rect rect;
    std::string action;
    bool interactive = true;
};

class App {
public:
    App(std::shared_ptr<Shared> state, HINSTANCE instance) : state_(std::move(state)), instance_(instance) {}
    ~App() {
        if (rt_) rt_->Release();
        if (dw_) dw_->Release();
        if (d2d_) d2d_->Release();
        if (icon_big_) ::DestroyIcon(icon_big_);
        if (icon_small_) ::DestroyIcon(icon_small_);
    }

    // Builds the taskbar / title-bar icon from code (no binary asset ships).
    void load_icons() {
        icon_big_ = icon::create(32);
        icon_small_ = icon::create(16);
        if (!icon_big_) log::warn("ui: 32px icon creation failed");
        if (!icon_small_) icon_small_ = icon_big_;
    }

    bool create() {
        is_admin_ = win::is_admin();
        state_->settings.theme = normalise_theme(state_->settings.theme);
        theme_ = preset(state_->settings.theme);
        WNDCLASSEXW wc{};
        wc.cbSize = sizeof(wc);
        wc.style = CS_HREDRAW | CS_VREDRAW;
        wc.lpfnWndProc = &App::wnd_proc;
        wc.hInstance = instance_;
        wc.hCursor = ::LoadCursorW(nullptr, IDC_ARROW);
        wc.hIcon = icon_big_ ? icon_big_ : ::LoadIconW(nullptr, IDI_APPLICATION);
        wc.hIconSm = icon_small_ ? icon_small_ : wc.hIcon;
        wc.lpszClassName = L"RustOptimizerWindow";
        wc.hbrBackground = nullptr;
        if (!::RegisterClassExW(&wc)) {
            log::error("ui: RegisterClassEx failed: " + win::last_error_text());
            return false;
        }
        const std::wstring title = L"Rust Optimizer " + str::widen(kVersion);
        hwnd_ = ::CreateWindowExW(0, wc.lpszClassName, title.c_str(), WS_OVERLAPPEDWINDOW, CW_USEDEFAULT,
                                  CW_USEDEFAULT, 1180, 820, nullptr, nullptr, instance_, this);
        if (!hwnd_) {
            log::error("ui: CreateWindowEx failed: " + win::last_error_text());
            return false;
        }
        state_->hwnd = hwnd_;
        if (icon_big_) ::SendMessageW(hwnd_, WM_SETICON, ICON_BIG, reinterpret_cast<LPARAM>(icon_big_));
        if (icon_small_) ::SendMessageW(hwnd_, WM_SETICON, ICON_SMALL, reinterpret_cast<LPARAM>(icon_small_));
        scale_ = dpi_scale();
        ::ShowWindow(hwnd_, SW_SHOW);
        ::UpdateWindow(hwnd_);
        return true;
    }

    // Starts the cheap background loop (priority guard + optional auto purge),
    // the desktop shortcut refresh and the mandatory update worker.
    void start_background() {
        ::SetTimer(hwnd_, kTimerId, 4000, nullptr);
        // 60 fps animation timer for smooth scrolling and page transitions.
        ::SetTimer(hwnd_, kAnimTimerId, 16, nullptr);

        std::thread([]() {
            // Keep the desktop / Start menu icon in place even if the user moved
            // the executable or deleted the shortcut.
            shortcut::ensure(fsx::exe_path());
            // Remove the previous build and abandoned staging folders.
            update::cleanup_stale(fsx::exe_path());
        }).detach();

        start_update_check();
    }

    // Manual trigger (F5 / Settings button). Safe to call anytime: the worker
    // exits immediately when a mandatory install is already running.
    void start_update_check() {
        if (state_->update_mandatory.load()) return;
        // One check at a time: F5 pressed repeatedly must not spawn an army of
        // workers hitting the GitHub API.
        if (state_->update_checking.exchange(true)) return;
        set_status(L"Проверяю обновления на GitHub…");
        auto shared = state_;
        std::thread([shared]() {
            update_worker(shared);
            shared->update_checking = false;
        }).detach();
    }

    // Mandatory update: check, download, verify, swap and relaunch. There is no
    // "later" button — a released build is installed on the next start.
    static void update_worker(std::shared_ptr<Shared> shared) {
        for (int attempt = 0; attempt < 6 && !shared->closing.load(); ++attempt) {
            net::Client client;
            const auto result = update::check(client, kGithubOwner, kGithubRepo, kVersion);
            if (shared->closing.load()) return;
            if (!result.ok) {
                log::warn("update: check failed: " + result.error);
                if (!wait_or_close(shared, 45)) return;
                continue;
            }
            if (!result.update_available) {
                log::info("update: up to date (" + std::string(kVersion) + ")");
                {
                    std::lock_guard<std::mutex> lock(shared->mutex);
                    shared->update_available = false;
                    shared->latest_version = result.latest_version;
                    shared->status = L"Установлена последняя версия (" + str::widen(kVersion) + L")";
                }
                post_refresh(shared);
                return;
            }

            log::info("update: new version " + result.latest_version + " — installing automatically");
            {
                std::lock_guard<std::mutex> lock(shared->mutex);
                shared->update_version = str::widen(result.latest_version);
                shared->update_status = L"Скачиваю обновление…";
                shared->update_error.clear();
                shared->latest_version = result.latest_version;
                shared->update_available = true;
            }
            shared->update_progress = 0;
            shared->update_mandatory = true;
            post_refresh(shared);

            std::atomic<std::uint64_t> last_percent{999};
            const auto progress = [shared, &last_percent](std::uint64_t done, std::uint64_t total) {
                if (total == 0) return;
                const auto percent = static_cast<std::uint64_t>(done * 100 / total);
                if (percent == last_percent.load()) return;
                last_percent = percent;
                // Reserve the last 10% for unpacking + restart.
                shared->update_progress = static_cast<int>(percent * 9 / 10);
                post_refresh(shared);
            };

            const auto stage =
                update::download_and_stage(client, result.release, fsx::staging_dir(), progress, nullptr);
            if (!stage.ok) {
                log::error("update: " + stage.error);
                {
                    std::lock_guard<std::mutex> lock(shared->mutex);
                    shared->update_status = L"Не удалось скачать обновление";
                    shared->update_error = str::widen(stage.error);
                }
                shared->update_progress = 0;
                post_refresh(shared);
                if (!wait_or_close(shared, 20)) return;
                continue;
            }

            {
                std::lock_guard<std::mutex> lock(shared->mutex);
                shared->update_status = L"Распаковка и установка…";
                shared->update_error.clear();
            }
            shared->update_progress = 95;
            shared->update_installing = true;
            post_refresh(shared);

            log::success("update: staged " + str::narrow(stage.staged_exe.wstring()));
            if (!update::spawn_applier(stage.staged_exe, fsx::exe_path())) {
                {
                    std::lock_guard<std::mutex> lock(shared->mutex);
                    shared->update_status = L"Не удалось запустить установщик";
                    shared->update_error = L"Проверьте права на папку с программой";
                }
                shared->update_installing = false;
                post_refresh(shared);
                if (!wait_or_close(shared, 20)) return;
                continue;
            }

            {
                std::lock_guard<std::mutex> lock(shared->mutex);
                shared->update_status = L"Перезапуск новой версии…";
            }
            shared->update_progress = 100;
            post_refresh(shared);

            // Give the applier time to spawn before this process disappears.
            for (int i = 0; i < 30 && !shared->closing.load(); ++i) {
                std::this_thread::sleep_for(std::chrono::milliseconds(100));
            }
            if (!shared->closing.load() && shared->hwnd) {
                ::PostMessageW(shared->hwnd, WM_APP_QUIT, 0, 0);
            }
            return;
        }
    }

    static bool wait_or_close(const std::shared_ptr<Shared>& shared, int seconds) {
        for (int i = 0; i < seconds * 10; ++i) {
            if (shared->closing.load()) return false;
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
        return true;
    }

    static void post_refresh(const std::shared_ptr<Shared>& shared) {
        if (!shared->closing.load() && shared->hwnd) ::PostMessageW(shared->hwnd, WM_APP_REFRESH, 0, 0);
    }

    int run() {
        MSG msg{};
        while (::GetMessageW(&msg, nullptr, 0, 0) > 0) {
            ::TranslateMessage(&msg);
            ::DispatchMessageW(&msg);
        }
        return static_cast<int>(msg.wParam);
    }

private:
    // ---------------------------------------------------------------- window
    static LRESULT CALLBACK wnd_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
        App* self = reinterpret_cast<App*>(::GetWindowLongPtrW(hwnd, GWLP_USERDATA));
        if (msg == WM_NCCREATE) {
            auto* cs = reinterpret_cast<CREATESTRUCTW*>(lp);
            self = static_cast<App*>(cs->lpCreateParams);
            ::SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
            // hwnd_ is only assigned after CreateWindowEx returns, but the very
            // first messages arrive during creation: without this every
            // DefWindowProc call below would get a null handle.
            if (self) self->hwnd_ = hwnd;
        }
        if (!self) return ::DefWindowProcW(hwnd, msg, wp, lp);
        return self->handle(msg, wp, lp);
    }

    LRESULT handle(UINT msg, WPARAM wp, LPARAM lp) {
        switch (msg) {
            case WM_PAINT: {
                PAINTSTRUCT ps{};
                ::BeginPaint(hwnd_, &ps);
                render();
                ::EndPaint(hwnd_, &ps);
                return 0;
            }
            case WM_ERASEBKGND:
                return 1;
            case WM_SIZE:
                if (rt_) {
                    rt_->Resize(D2D1::SizeU(LOWORD(lp), HIWORD(lp)));
                }
                ::InvalidateRect(hwnd_, nullptr, FALSE);
                return 0;
            case WM_DPICHANGED: {
                scale_ = static_cast<float>(HIWORD(wp)) / 96.0f;
                const auto* rect = reinterpret_cast<const RECT*>(lp);
                ::SetWindowPos(hwnd_, nullptr, rect->left, rect->top, rect->right - rect->left,
                               rect->bottom - rect->top, SWP_NOZORDER | SWP_NOACTIVATE);
                if (rt_) {
                    rt_->SetDpi(96.0f, 96.0f);
                    rt_->Release();
                    rt_ = nullptr;
                }
                ::InvalidateRect(hwnd_, nullptr, FALSE);
                return 0;
            }
            case WM_MOUSEMOVE:
                on_mouse_move(GET_X_LPARAM_(lp), GET_Y_LPARAM_(lp));
                return 0;
            case WM_MOUSELEAVE:
                hover_ = -1;
                ::InvalidateRect(hwnd_, nullptr, FALSE);
                return 0;
            case WM_MOUSEWHEEL: {
                const int delta = GET_WHEEL_DELTA_WPARAM(wp);
                scroll_by(-static_cast<float>(delta) / 120.0f * 64.0f);
                return 0;
            }
            case WM_KEYDOWN: {
                // Keyboard scrolling: essential when the wheel/touchpad fails.
                const float step = scroll_view_h_ * 0.9f;
                switch (wp) {
                    case VK_DOWN:
                        scroll_by(56.0f);
                        return 0;
                    case VK_UP:
                        scroll_by(-56.0f);
                        return 0;
                    case VK_NEXT:
                        scroll_by(step);
                        return 0;
                    case VK_PRIOR:
                        scroll_by(-step);
                        return 0;
                    case VK_HOME:
                        scroll_to(0.0f);
                        return 0;
                    case VK_END:
                        scroll_to(max_scroll_);
                        return 0;
                    case VK_F5:
                        start_update_check();
                        return 0;
                    default:
                        break;
                }
                // Ctrl+1..9 jumps straight to a page.
                if ((::GetKeyState(VK_CONTROL) & 0x8000) && wp >= '1' && wp <= '9') {
                    const int index = static_cast<int>(wp - '1');
                    if (index < static_cast<int>(pages_.size())) {
                        page_index_ = index;
                        page_anim_ = 0.0f;
                        ::InvalidateRect(hwnd_, nullptr, FALSE);
                    }
                    return 0;
                }
                break;
            }
            case WM_LBUTTONDOWN: {
                ::SetCapture(hwnd_);
                click_x_ = GET_X_LPARAM_(lp);
                click_y_ = GET_Y_LPARAM_(lp);
                const float x = static_cast<float>(click_x_) / scale_;
                const float y = static_cast<float>(click_y_) / scale_;
                if (!state_->update_mandatory.load() && scrollbar_active_ &&
                    scroll_track_.contains(x, y)) {
                    if (scroll_thumb_.contains(x, y)) {
                        scroll_drag_ = true;
                        scroll_drag_offset_ = y - scroll_thumb_.y;
                    } else {
                        // Click above/below the thumb pages the content.
                        const float step = scroll_view_h_ * 0.9f;
                        scroll_by(y < scroll_thumb_.y ? -step : step);
                    }
                }
                return 0;
            }
            case WM_LBUTTONUP: {
                ::ReleaseCapture();
                if (scroll_drag_) {
                    scroll_drag_ = false;
                    ::InvalidateRect(hwnd_, nullptr, FALSE);
                    return 0;
                }
                on_click(GET_X_LPARAM_(lp), GET_Y_LPARAM_(lp));
                return 0;
            }
            case WM_SETCURSOR: {
                if (LOWORD(lp) == HTCLIENT && cursor_hand_) {
                    ::SetCursor(::LoadCursorW(nullptr, IDC_HAND));
                    return TRUE;
                }
                break;
            }
            case WM_TIMER:
                if (wp == kTimerId) tick();
                else if (wp == kAnimTimerId) tick_anim();
                return 0;
            case WM_APP_REFRESH:
                refresh_pages();
                ::InvalidateRect(hwnd_, nullptr, FALSE);
                return 0;
            case WM_APP_QUIT:
                ::DestroyWindow(hwnd_);
                return 0;
            case WM_GETMINMAXINFO: {
                auto* mmi = reinterpret_cast<MINMAXINFO*>(lp);
                mmi->ptMinTrackSize.x = 980;
                mmi->ptMinTrackSize.y = 680;
                return 0;
            }
            case WM_CLOSE:
                state_->closing = true;
                {
                    std::lock_guard<std::mutex> lock(state_->mutex);
                    state_->settings.toggles = toggles_json();
                    save_settings_locked();
                }
                ::DestroyWindow(hwnd_);
                return 0;
            case WM_DESTROY:
                state_->closing = true;
                state_->hwnd = nullptr;
                ::KillTimer(hwnd_, kTimerId);
                ::KillTimer(hwnd_, kAnimTimerId);
                ::PostQuitMessage(0);
                return 0;
            default:
                break;
        }
        return ::DefWindowProcW(hwnd_, msg, wp, lp);
    }

    static int GET_X_LPARAM_(LPARAM lp) { return static_cast<short>(LOWORD(lp)); }
    static int GET_Y_LPARAM_(LPARAM lp) { return static_cast<short>(HIWORD(lp)); }

    float dpi_scale() const {
        using GetDpiFn = UINT(WINAPI*)(HWND);
        static GetDpiFn get_dpi = []() -> GetDpiFn {
            HMODULE user = ::GetModuleHandleW(L"user32.dll");
            if (!user) return nullptr;
            return reinterpret_cast<GetDpiFn>(reinterpret_cast<void*>(::GetProcAddress(user, "GetDpiForWindow")));
        }();
        UINT dpi = get_dpi ? get_dpi(hwnd_) : 96;
        if (dpi == 0) dpi = 96;
        return static_cast<float>(dpi) / 96.0f;
    }

    // ---------------------------------------------------------------- settings
    json::Value toggles_json() {
        json::Value j = json::Value::object();
        for (const auto& [k, v] : state_->toggles) j[k] = v;
        return j;
    }

    void save_settings_locked() {
        state_->settings.toggles = toggles_json();
        SettingsStore store(fsx::data_dir() / L"settings.json");
        if (!store.save(state_->settings)) log::warn("ui: settings save failed");
    }

    void save_settings() {
        std::lock_guard<std::mutex> lock(state_->mutex);
        save_settings_locked();
    }

    bool toggle(const std::string& page, const std::string& row, bool current) {
        std::lock_guard<std::mutex> lock(state_->mutex);
        const std::string key = page + "." + row;
        auto it = state_->toggles.find(key);
        // First click on a row without a saved value: trust what the user sees
        // and store the opposite.
        const bool value = it == state_->toggles.end() ? !current : !it->second;
        state_->toggles[key] = value;
        // Some switches mirror a settings field that the timer reads live.
        if (key == "settings.close_on_launch") state_->settings.close_on_launch = value;
        save_settings_locked();
        return value;
    }

    bool is_on(const std::string& page, const std::string& row) const {
        std::lock_guard<std::mutex> lock(state_->mutex);
        const auto it = state_->toggles.find(page + "." + row);
        return it != state_->toggles.end() && it->second;
    }

    // ---------------------------------------------------------------- pages
    void refresh_pages() {
        // The worker thread updates games/toggles/update info under the mutex;
        // snapshot everything the page builder reads.
        PageContext ctx;
        std::wstring last_page;
        {
            std::lock_guard<std::mutex> lock(state_->mutex);
            ctx.settings = &state_->settings;
            ctx.hw = &state_->hw;
            ctx.cpu = &state_->cpu;
            ctx.rust = &state_->games.rust;
            ctx.fortnite = &state_->games.fortnite;
            ctx.toggles = &state_->toggles;
            ctx.update_available = state_->update_available;
            ctx.latest_version = state_->latest_version;
            ctx.steam_dir = state_->games.steam.steam_dir;
            ctx.theme_id = state_->settings.theme;
            ctx.image_preset = state_->settings.image_preset;
            last_page = state_->settings.last_page;
            ctx.admin = is_admin_;
            pages_ = build_pages(ctx);
        }
        if (pages_.empty()) page_index_ = 0;
        else if (page_index_ >= static_cast<int>(pages_.size())) page_index_ = 0;
        // Restore the page the user closed the app on (once per session).
        if (!page_restored_ && !last_page.empty()) {
            for (std::size_t i = 0; i < pages_.size(); ++i) {
                if (pages_[i].id == str::narrow(last_page)) {
                    page_index_ = static_cast<int>(i);
                    break;
                }
            }
        }
        page_restored_ = true;
    }

    // ---------------------------------------------------------------- render
    void ensure_target() {
        if (!d2d_) {
            if (FAILED(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, &d2d_)) || !d2d_) {
                log::error("ui: D2D1CreateFactory failed");
                return;
            }
        }
        if (!dw_) {
            if (FAILED(::DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory),
                                             reinterpret_cast<IUnknown**>(&dw_))) ||
                !dw_) {
                log::error("ui: DWriteCreateFactory failed");
                return;
            }
        }
        RECT rc{};
        ::GetClientRect(hwnd_, &rc);
        const D2D1_SIZE_U size = D2D1::SizeU(static_cast<UINT32>(rc.right - rc.left),
                                             static_cast<UINT32>(rc.bottom - rc.top));
        if (rt_ && (rt_pixel_w_ != size.width || rt_pixel_h_ != size.height)) {
            rt_->Release();
            rt_ = nullptr;
        }
        if (!rt_) {
            const auto props = D2D1::RenderTargetProperties(D2D1_RENDER_TARGET_TYPE_DEFAULT, D2D1::PixelFormat(),
                                                           96.0f, 96.0f);
            const auto hwnd_props = D2D1::HwndRenderTargetProperties(hwnd_, size);
            if (FAILED(d2d_->CreateHwndRenderTarget(props, hwnd_props, &rt_)) || !rt_) {
                log::error("ui: CreateHwndRenderTarget failed");
                return;
            }
            rt_->SetAntialiasMode(D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
            rt_->SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_CLEARTYPE);
            rt_pixel_w_ = size.width;
            rt_pixel_h_ = size.height;
        }
    }

    void render() {
        ensure_target();
        if (!rt_) return;
        refresh_pages();

        RECT rc{};
        ::GetClientRect(hwnd_, &rc);
        const float width = static_cast<float>(rc.right - rc.left) / scale_;
        const float height = static_cast<float>(rc.bottom - rc.top) / scale_;

        if (pages_.empty()) {
            rt_->BeginDraw();
            rt_->Clear(theme_.bg);
            rt_->EndDraw();
            return;
        }

        rt_->BeginDraw();
        rt_->SetTransform(D2D1::Matrix3x2F::Scale(scale_, scale_));
        if (rt_->GetSize().width == 0) {
            rt_->EndDraw();
            return;
        }

        hits_.clear();
        const Themed& theme = theme_;
        Painter p(rt_, dw_, theme, scale_);

        // Background.
        p.fill(Rect{0, 0, width, height}, theme.bg);
        draw_sidebar(p, height);

        const Page& page = pages_[static_cast<std::size_t>(page_index_)];
        // Page slide-in: rows ease in from the right after navigation.
        const float slide = (1.0f - page_anim_) * 22.0f;
        const float content_x = kSidebarWidth + slide;
        const float content_w = width - kSidebarWidth - slide;

        // Header.
        p.text(page.title, Rect{content_x + kPadding, 26, content_w - kPadding * 2, 40}, theme.text, 27, 600, 0,
               false);
        p.text(page.subtitle, Rect{content_x + kPadding, 64, content_w - kPadding * 2 - 200, 22}, theme.text_dim, 12.5f,
               400, 0);
        // Version / admin chip.
        {
            const std::wstring chip = is_admin_ ? L"ADMIN" : L"USER";
            const Rect chip_rect{width - kPadding - 84, 30, 84, 26};
            p.fill_round(chip_rect, 13.0f, is_admin_ ? theme.accent_soft : theme.card);
            p.text(chip, chip_rect, is_admin_ ? theme.accent : theme.text_muted, 10.5f, 600, 1);
        }
        p.text(L"v" + str::widen(kVersion), Rect{width - kPadding - 84, 62, 84, 18}, theme.text_muted, 11, 400, 2);

        // Rows.
        const float footer_h = page.has_apply ? kFooterHeight : 40.0f;
        const float view_top = kHeaderHeight;
        const float view_bottom = height - footer_h;
        const float view_h = view_bottom - view_top;
        scroll_view_h_ = view_h;
        float y = view_top - scroll_for(page.id);
        // Right margin reserved for the scrollbar so rows never slide under it.
        const float row_w = content_w - kPadding * 2 - 16.0f;
        std::vector<Hit>& hits = hits_;

        rt_->PushAxisAlignedClip(D2D1::RectF(content_x, view_top, width, view_bottom),
                                 D2D1_ANTIALIAS_MODE_ALIASED);
        if (page.id == "logs") {
            draw_logs(p, page, content_x + kPadding, y, row_w, view_top, view_bottom, hits);
            y += static_cast<float>(state_->logs.size()) * 20.0f + 200.0f;
        } else {
            for (std::size_t i = 0; i < page.rows.size(); ++i) {
                const Row& row = page.rows[i];
                float h = row_height(row);
                if (y + h >= view_top - 40 && y <= view_bottom + 40) {
                    draw_row(p, page, row, i, content_x + kPadding, y, row_w, h, hits);
                }
                y += h + kRowGap;
            }
        }
        rt_->PopAxisAlignedClip();

        // Remember the max scroll for clamping.
        const float content_end = y + scroll_for(page.id);
        max_scroll_ = (std::max)(0.0f, content_end - (view_bottom - view_top) + 24.0f);
        if (scroll_for(page.id) > max_scroll_) scroll_[page.id] = max_scroll_;
        if (scroll_target_for(page.id) > max_scroll_) scroll_target_[page.id] = max_scroll_;

        // Scrollbar last so it draws above clipped content.
        draw_scrollbar(p, width, view_top, view_bottom);

        // Footer.
        if (page.has_apply) draw_footer(p, page, width, height, hits);

        // Busy strip.
        if (state_->busy.load()) {
            const Rect track{content_x + kPadding, height - footer_h + 14, row_w, 4};
            const float fraction = static_cast<float>(state_->progress.load()) / 100.0f;
            p.progress(track, fraction, theme.accent);
        }

        // Mandatory update card sits above everything and swallows input.
        if (state_->update_mandatory.load()) draw_update_overlay(p, width, height);

        const HRESULT hr = rt_->EndDraw();
        if (hr == D2DERR_RECREATE_TARGET) {
            rt_->Release();
            rt_ = nullptr;
        }
    }

    // Full-window modal shown while a release is downloaded and installed.
    void draw_update_overlay(Painter& p, float width, float height) {
        const Themed& theme = theme_;
        p.fill(Rect{0, 0, width, height}, rgb(0x05030A, 0.82f));

        std::wstring version;
        std::wstring status;
        std::wstring error;
        {
            std::lock_guard<std::mutex> lock(state_->mutex);
            version = state_->update_version;
            status = state_->update_status;
            error = state_->update_error;
        }
        const int percent = static_cast<int>(display_progress_ + 0.5f);
        const bool installing = state_->update_installing.load();

        const float card_w = 560.0f;
        const float card_h = 312.0f;
        const Rect card{(width - card_w) * 0.5f, (height - card_h) * 0.5f, card_w, card_h};

        // Soft shadow + surface.
        p.fill_round(Rect{card.x, card.y + 12, card.w, card.h}, 22.0f, rgb(0x000000, 0.35f));
        p.fill_round(card, 20.0f, theme.card);
        p.stroke_round(card, 20.0f, theme.accent_soft, 1.5f);

        // Accent badge.
        const Rect badge{card.x + 28, card.y + 26, 46, 46};
        p.gradient_round(badge, 15.0f, theme.accent, rgb(0x3B1D6E));
        p.text(L"↓", Rect{badge.x, badge.y - 2, badge.w, badge.h}, theme.accent_text, 22, 700, 1);

        p.text(L"Обновление Rust Optimizer", Rect{card.x + 90, card.y + 24, card.w - 118, 26}, theme.text, 19.0f, 700, 0);
        p.text(version.empty() ? std::wstring(L"Поиск новой версии…")
                               : L"Версия " + version + L" · устанавливается автоматически",
               Rect{card.x + 90, card.y + 52, card.w - 118, 20}, theme.text_dim, 12.5f, 400, 0);

        // Progress bar + percentage.
        const Rect track{card.x + 28, card.y + 116, card.w - 56, 9};
        p.progress(track, static_cast<float>(percent) / 100.0f, theme.accent);
        p.text(std::to_wstring(percent) + L"%", Rect{track.x, track.y + 16, track.w, 20}, theme.text, 12.0f, 600, 2);

        p.text(status, Rect{card.x + 28, card.y + 164, card.w - 56, 24}, theme.text, 13.5f, 500, 0);
        if (!error.empty()) {
            p.text(error, Rect{card.x + 28, card.y + 192, card.w - 56, 40}, theme.err, 11.5f, 400, 0, true);
        }

        p.line(card.x + 28, card.y + card.h - 64, card.x + card.w - 28, card.y + card.h - 64, theme.border, 1.0f);
        p.text(installing ? std::wstring(L"Сейчас программа закроется, обновится и запустится заново.")
                          : std::wstring(L"Не закрывайте окно — установка продолжится автоматически."),
               Rect{card.x + 28, card.y + card.h - 52, card.w - 56, 36}, theme.text_muted, 11.5f, 400, 0, true);
    }

    float row_height(const Row& row) const {
        switch (row.kind) {
            case RowKind::Section: return 42.0f;
            case RowKind::Toggle: return 96.0f;
            case RowKind::Info: return 66.0f;
            case RowKind::Button: return 54.0f;
            case RowKind::Note: return 44.0f;
            case RowKind::Spacer: return 12.0f;
        }
        return 0.0f;
    }

    void draw_sidebar(Painter& p, float height) {
        const Themed& theme = theme_;
        p.fill(Rect{0, 0, kSidebarWidth, height}, theme.sidebar);
        p.line(kSidebarWidth - 1, 0, kSidebarWidth - 1, height, theme.border, 1.0f);

        // Logo mark.
        const Rect logo{22, 24, 40, 40};
        p.gradient_round(logo, 12.0f, theme.accent, rgb(0x3B1D6E));
        p.text(L"R", Rect{logo.x, logo.y - 1, logo.w, logo.h}, theme.accent_text, 22, 700, 1);
        p.text(L"RUST OPTIMIZER", Rect{72, 26, 150, 18}, theme.text, 12.5f, 700, 0);
        p.text(L"performance engine", Rect{72, 44, 150, 16}, theme.text_muted, 10.5f, 400, 0);

        float y = 92;
        const std::string active_id = pages_.empty() ? std::string() : pages_[static_cast<std::size_t>(page_index_)].id;
        for (int i = 0; i < static_cast<int>(std::size(kNav)); ++i) {
            const bool active = kNav[i].id == active_id;
            const Rect item{14, y, kSidebarWidth - 28, 42};
            if (active) {
                p.fill_round(item, 12.0f, theme.accent_soft);
                p.fill_round(Rect{item.x + 2, item.y + 12, 3, 18}, 1.5f, theme.accent);
            } else if (hover_ == static_cast<int>(1000 + i)) {
                p.fill_round(item, 12.0f, theme.card);
            }
            const D2D1_COLOR_F color = active ? theme.text : theme.text_dim;
            p.text(kNav[i].label, Rect{item.x + 18, item.y, item.w - 24, item.h}, color, 13.5f,
                   active ? 600 : 400, 0);
            hits_.push_back(Hit{item, std::string("nav:") + kNav[i].id, true});
            y += 46;
        }

        // Status chip at the bottom.
        const Rect card{14, height - 92, kSidebarWidth - 28, 74};
        p.fill_round(card, 14.0f, theme.card);
        p.stroke_round(card, 14.0f, theme.border, 1.0f);
        const bool admin = is_admin_;
        p.text(admin ? L"Администратор" : L"Обычный режим", Rect{card.x + 14, card.y + 10, card.w - 28, 18},
               admin ? theme.ok : theme.warn, 11.5f, 600, 0);
        p.text(admin ? L"Standby-список доступен" : L"Нужен перезапуск от админа",
               Rect{card.x + 14, card.y + 30, card.w - 28, 34}, theme.text_muted, 10.5f, 400, 0, true);
    }

    void draw_row(Painter& p, const Page& page, const Row& row, std::size_t index, float x, float y, float w, float h,
                  std::vector<Hit>& hits) {
        const Themed& theme = theme_;
        const bool hovered = hover_ == static_cast<int>(index) || hover_ == static_cast<int>(10000 + index);

        switch (row.kind) {
            case RowKind::Section: {
                p.text(row.title, Rect{x, y + 14, w, 18}, theme.text_muted, 10.5f, 700, 0);
                p.line(x, y + 38, x + w, y + 38, theme.border, 1.0f);
                break;
            }
            case RowKind::Toggle: {
                p.card(Rect{x, y, w, h - 6}, hovered);
                p.text(row.title, Rect{x + 20, y + 16, w - 150, 24}, row.danger ? theme.warn : theme.text, 14.0f,
                       600, 0);
                p.text(row.desc, Rect{x + 20, y + 44, w - 150, 40}, theme.text_dim, 11.5f, 400, 0, true);
                const Rect sw{x + w - 78, y + (h - 6) / 2 - 13, 26, 26};
                p.toggle(sw, row.on, hovered);
                hits.push_back(Hit{Rect{x, y, w, h - 6}, "toggle:" + page.id + ":" + row.id, true});
                break;
            }
            case RowKind::Info: {
                p.fill_round(Rect{x, y, w, h - 6}, 14.0f, theme.card);
                p.text(row.title, Rect{x + 20, y + 12, w * 0.42f, 18}, theme.text_dim, 11.0f, 500, 0);
                p.text(row.desc, Rect{x + 20, y + 30, w - 40, 26}, theme.text, 13.0f, 500, 0);
                break;
            }
            case RowKind::Button: {
                const Rect btn{x, y + 2, 348, 40};
                p.button(btn, row.title, row.primary, hovered, row.enabled);
                if (row.enabled) hits.push_back(Hit{btn, "action:" + row.action, true});
                break;
            }
            case RowKind::Note: {
                p.text(row.title, Rect{x + 4, y + 6, w - 8, 34}, theme.text_muted, 11.0f, 400, 0, true);
                break;
            }
            case RowKind::Spacer:
                break;
        }
    }

    void draw_footer(Painter& p, const Page& page, float width, float height, std::vector<Hit>& hits) {
        const Themed& theme = theme_;
        const float top = height - kFooterHeight;
        p.fill(Rect{kSidebarWidth, top, width - kSidebarWidth, kFooterHeight}, theme.sidebar);
        p.line(kSidebarWidth, top, width, top, theme.border, 1.0f);

        std::wstring status;
        int progress = 0;
        bool busy = false;
        {
            std::lock_guard<std::mutex> lock(state_->mutex);
            status = state_->status;
        }
        busy = state_->busy.load();
        progress = state_->progress.load();

        const float text_w = width - kSidebarWidth - kPadding * 2 - 260;
        p.text(status, Rect{kSidebarWidth + kPadding, top + 22, text_w, 22}, busy ? theme.text : theme.text_dim,
               12.0f, 400, 0);
        if (busy) {
            p.progress(Rect{kSidebarWidth + kPadding, top + 52, text_w, 6}, static_cast<float>(progress) / 100.0f,
                       theme.accent);
        } else {
            p.text(L"Все изменения обратимы: перед правкой файлов создаётся резервная копия.",
                   Rect{kSidebarWidth + kPadding, top + 50, text_w, 20}, theme.text_muted, 10.5f, 400, 0);
        }
        const Rect apply{width - kPadding - 216, top + 26, 216, 44};
        p.button(apply, page.apply_label, true, hover_ == 90000, !busy);
        if (!busy) hits.push_back(Hit{apply, "action:__apply__", true});
    }

    void draw_logs(Painter& p, const Page& page, float x, float y, float w, float top, float bottom,
                   std::vector<Hit>& hits) {
        (void)page;
        (void)hits;
        const Themed& theme = theme_;
        std::vector<log::Record> logs;
        {
            std::lock_guard<std::mutex> lock(state_->mutex);
            logs = state_->logs;
        }
        const int max_lines = static_cast<int>((bottom - top) / 20.0f) + 4;
        int start = static_cast<int>(logs.size()) - max_lines;
        if (start < 0) start = 0;
        float cursor = y + 8;
        // Page header rows (paths/buttons) come first; the log itself follows.
        p.text(L"ЖУРНАЛ СЕССИИ", Rect{x, cursor, w, 20}, theme.text_muted, 10.5f, 700, 0);
        cursor += 30;
        for (int i = start; i < static_cast<int>(logs.size()); ++i) {
            if (cursor > bottom) break;
            const auto& record = logs[static_cast<std::size_t>(i)];
            D2D1_COLOR_F color = theme.text_dim;
            switch (record.level) {
                case log::Level::Error: color = theme.err; break;
                case log::Level::Warn: color = theme.warn; break;
                case log::Level::Success: color = theme.ok; break;
                case log::Level::Debug: color = theme.text_muted; break;
                default: color = theme.text_dim; break;
            }
            p.text(str::widen(record.time), Rect{x, cursor, 56, 18}, theme.text_muted, 10.5f, 500, 0);
            p.text(str::widen(record.text), Rect{x + 62, cursor, w - 70, 18}, color, 11.0f, 400, 0);
            cursor += 20;
        }
    }

    float scroll_for(const std::string& page) const {
        const auto it = scroll_.find(page);
        return it == scroll_.end() ? 0.0f : it->second;
    }

    float scroll_target_for(const std::string& page) const {
        const auto it = scroll_target_.find(page);
        if (it != scroll_target_.end()) return it->second;
        return scroll_for(page);
    }

    // Wheel / keyboard input updates the target; the animation timer eases the
    // visible offset towards it, so long pages glide instead of jumping.
    void scroll_by(float delta) {
        if (pages_.empty()) return;
        const std::string id = pages_[static_cast<std::size_t>(page_index_)].id;
        scroll_target_[id] =
            std::clamp(scroll_target_for(id) + delta, 0.0f, (std::max)(0.0f, max_scroll_));
        ::InvalidateRect(hwnd_, nullptr, FALSE);
    }

    // Dragging the thumb must track the cursor exactly, so it sets both values.
    void scroll_to(float value) {
        if (pages_.empty()) return;
        const std::string id = pages_[static_cast<std::size_t>(page_index_)].id;
        const float clamped = std::clamp(value, 0.0f, (std::max)(0.0f, max_scroll_));
        scroll_[id] = clamped;
        scroll_target_[id] = clamped;
        ::InvalidateRect(hwnd_, nullptr, FALSE);
    }

    // Scrollbar geometry is recomputed on every paint, so the thumb always
    // matches the current content height.
    void draw_scrollbar(Painter& p, float width, float view_top, float view_bottom) {
        scrollbar_active_ = false;
        scroll_track_ = Rect{};
        scroll_thumb_ = Rect{};
        const float view_h = view_bottom - view_top;
        if (max_scroll_ <= 0.5f || view_h < 60.0f) {
            scroll_drag_ = false;
            return;
        }
        const float track_w = 8.0f;
        const Rect track{width - 12.0f - track_w, view_top + 6.0f, track_w, view_h - 12.0f};
        if (track.h < 24.0f) return;
        scrollbar_active_ = true;
        scroll_track_ = track;
        p.fill_round(track, track_w * 0.5f, theme_.toggle_off);

        const float content_h = view_h + max_scroll_;
        float thumb_h = track.h * (view_h / content_h);
        thumb_h = std::clamp(thumb_h, 40.0f, track.h);
        const std::string id = pages_.empty() ? std::string() : pages_[static_cast<std::size_t>(page_index_)].id;
        const float ratio = max_scroll_ <= 0.0f ? 0.0f : scroll_for(id) / max_scroll_;
        const Rect thumb{track.x, track.y + ratio * (track.h - thumb_h), track_w, thumb_h};
        scroll_thumb_ = thumb;
        const D2D1_COLOR_F color = scroll_drag_ ? theme_.accent
                                  : scrollbar_hover_ ? theme_.text_dim
                                                     : theme_.text_muted;
        p.fill_round(thumb, track_w * 0.5f, color);
    }

    void drag_scroll_to(float py) {
        if (!scrollbar_active_) return;
        const float span = scroll_track_.h - scroll_thumb_.h;
        if (span <= 0.0f) return;
        const float rel = std::clamp(py - scroll_drag_offset_ - scroll_track_.y, 0.0f, span);
        scroll_to(rel / span * max_scroll_);
    }

    // ---------------------------------------------------------------- input
    void on_mouse_move(int px, int py) {
        const float x = static_cast<float>(px) / scale_;
        const float y = static_cast<float>(py) / scale_;
        if (scroll_drag_) {
            drag_scroll_to(y);
            return;
        }
        const bool over_bar = scrollbar_active_ && scroll_track_.contains(x, y);
        if (over_bar != scrollbar_hover_) {
            scrollbar_hover_ = over_bar;
            ::InvalidateRect(hwnd_, nullptr, FALSE);
        }
        int new_hover = -1;
        bool hand = over_bar;
        for (std::size_t i = 0; i < hits_.size(); ++i) {
            if (!hits_[i].interactive) continue;
            if (hits_[i].rect.contains(x, y)) {
                new_hover = static_cast<int>(i);
                hand = true;
                break;
            }
        }
        // Sidebar items are addressed separately so their index is stable.
        for (int i = 0; i < static_cast<int>(std::size(kNav)); ++i) {
            const Rect item{14, 92.0f + i * 46.0f, kSidebarWidth - 28, 42};
            if (item.contains(x, y)) {
                new_hover = 1000 + i;
                hand = true;
                break;
            }
        }
        if (new_hover == 90000 || (new_hover >= 90000)) hand = true;
        cursor_hand_ = hand;
        if (!tracking_leave_) {
            TRACKMOUSEEVENT tme{};
            tme.cbSize = sizeof(tme);
            tme.dwFlags = TME_LEAVE;
            tme.hwndTrack = hwnd_;
            ::TrackMouseEvent(&tme);
            tracking_leave_ = true;
        }
        if (new_hover != hover_) {
            hover_ = new_hover;
            ::InvalidateRect(hwnd_, nullptr, FALSE);
        }
    }

    void on_click(int px, int py) {
        // A mandatory update owns the window: no page switching, no toggles.
        if (state_->update_mandatory.load()) return;
        const float x = static_cast<float>(px) / scale_;
        const float y = static_cast<float>(py) / scale_;
        // Apply button is not in hits_ when busy; hover id is synthetic.
        for (int i = 0; i < static_cast<int>(std::size(kNav)); ++i) {
            const Rect item{14, 92.0f + i * 46.0f, kSidebarWidth - 28, 42};
            if (item.contains(x, y)) {
                // Resolve by page id: the sidebar order and the page order are
                // separate lists and used to drift apart.
                for (std::size_t p = 0; p < pages_.size(); ++p) {
                    if (pages_[p].id == kNav[i].id) {
                        page_index_ = static_cast<int>(p);
                        break;
                    }
                }
                page_anim_ = 0.0f;
                ::InvalidateRect(hwnd_, nullptr, FALSE);
                return;
            }
        }
        for (const auto& hit : hits_) {
            if (!hit.rect.contains(x, y)) continue;
            dispatch(hit.action);
            return;
        }
    }

    // ---------------------------------------------------------------- actions
    void dispatch(const std::string& raw_action) {
        // Button rows arrive as "action:<name>"; nav/toggle rows do not. Strip
        // the prefix once so "action:theme:ocean" and "theme:ocean" behave the
        // same - that mismatch used to make the theme buttons dead.
        std::string action = raw_action;
        const bool is_button = str::starts_with(action, "action:");
        if (is_button) action = action.substr(7);

        if (action == "__apply__") {
            apply_page();
            return;
        }
        if (!is_button && str::starts_with(action, "nav:")) {
            const std::string id = action.substr(4);
            for (std::size_t i = 0; i < pages_.size(); ++i) {
                if (pages_[i].id == id) {
                    page_index_ = static_cast<int>(i);
                    page_anim_ = 0.0f;
                    {
                        std::lock_guard<std::mutex> lock(state_->mutex);
                        state_->settings.last_page = str::widen(id);
                        save_settings_locked();
                    }
                    ::InvalidateRect(hwnd_, nullptr, FALSE);
                    return;
                }
            }
            return;
        }
        if (str::starts_with(action, "theme:")) {
            const std::string id = normalise_theme(action.substr(6));
            {
                std::lock_guard<std::mutex> lock(state_->mutex);
                state_->settings.theme = id;
                state_->settings.dark_theme = preset(id).dark;
                save_settings_locked();
            }
            theme_ = preset(id);
            refresh_pages();
            set_status(L"Тема применена: " + std::wstring(theme_title(id)));
            log::info("ui: theme = " + id);
            ::InvalidateRect(hwnd_, nullptr, FALSE);
            return;
        }
        if (str::starts_with(action, "visual:")) {
            const std::string id = action.substr(7);
            std::string error;
            const bool ok = visuals::apply(id, error);
            if (ok) {
                std::lock_guard<std::mutex> lock(state_->mutex);
                state_->settings.image_preset = id;
                save_settings_locked();
            }
            refresh_pages();
            std::wstring label = str::widen(id);
            for (const auto& preset : visuals::presets()) {
                if (preset.id == id) label = preset.title;
            }
            set_status(ok ? L"Картинка: " + label + L" применено" : L"Картинка не изменена: " + str::widen(error));
            log::info("ui: visual preset = " + id + (ok ? " (ok)" : " (failed)"));
            ::InvalidateRect(hwnd_, nullptr, FALSE);
            return;
        }
        if (str::starts_with(action, "toggle:")) {
            const auto parts = str::split(action.substr(7), ':');
            if (parts.size() < 2) return;
            bool current = false;
            for (const auto& page : pages_) {
                if (page.id != parts[0]) continue;
                for (const auto& row : page.rows) {
                    if (row.id == parts[1] && row.kind == RowKind::Toggle) current = row.on;
                }
            }
            const bool value = toggle(parts[0], parts[1], current);
            // Keep the in-memory row in sync so the switch animates immediately.
            for (auto& page : pages_) {
                if (page.id != parts[0]) continue;
                for (auto& row : page.rows) {
                    if (row.id == parts[1] && row.kind == RowKind::Toggle) row.on = value;
                }
            }
            log::info(std::string("ui: ") + parts[0] + "." + parts[1] + (value ? " = on" : " = off"));
            ::InvalidateRect(hwnd_, nullptr, FALSE);
            return;
        }
        if (is_button) execute(action);
    }

    void apply_page() {
        const Page& page = pages_[static_cast<std::size_t>(page_index_)];
        if (page.id == "rust") apply_rust();
        else if (page.id == "fortnite") apply_fortnite();
        else if (page.id == "system") apply_system();
        else if (page.id == "settings") apply_settings_page();
        else if (page.id == "overview") apply_overview();
    }

    void set_status(const std::wstring& text) {
        std::lock_guard<std::mutex> lock(state_->mutex);
        state_->status = text;
    }

    void run_async(const std::wstring& label, std::function<std::wstring()> job, bool minimize_after = false) {
        if (state_->busy.exchange(true)) return;
        state_->progress = 3;
        set_status(label);
        ::InvalidateRect(hwnd_, nullptr, FALSE);
        auto shared = state_;
        std::thread([shared, label, minimize_after, job = std::move(job)]() mutable {
            std::wstring result;
            try {
                result = job();
            } catch (const std::exception& e) {
                result = L"Ошибка: " + str::widen(e.what());
            } catch (...) {
                result = L"Неизвестная ошибка";
            }
            if (result.empty()) result = label;
            bool minimize = false;
            {
                std::lock_guard<std::mutex> lock(shared->mutex);
                shared->status = result;
                minimize = minimize_after && shared->settings.minimize_on_apply;
            }
            shared->progress = 100;
            shared->busy = false;
            const HWND hwnd = shared->hwnd;
            if (!shared->closing.load() && hwnd) {
                if (minimize) ::PostMessageW(hwnd, WM_SYSCOMMAND, SC_MINIMIZE, 0);
                ::PostMessageW(hwnd, WM_APP_REFRESH, 0, 0);
            }
        }).detach();
    }

    rust::Options rust_options() {
        rust::Options o;
        std::lock_guard<std::mutex> lock(state_->mutex);
        const auto get = [&](const char* id, bool fallback) {
            const auto it = state_->toggles.find(std::string("rust.") + id);
            return it == state_->toggles.end() ? fallback : it->second;
        };
        o.grass_off = get("grass_off", true);
        o.grass_displacement = get("grass_displacement", false);
        o.grass_shadowcast = get("grass_shadowcast", false);
        o.grass_shadowreceive = get("grass_shadowreceive", false);
        o.ssaa_off = get("ssaa_off", true);
        o.vsync_off = get("vsync_off", true);
        o.shadows_off = get("shadows_off", false);
        o.half_res_sss = get("half_res_sss", true);
        o.pixellight_off = get("pixellight_off", true);
        o.depth_of_field_off = get("dof_off", true);
        o.motion_blur_off = get("motion_blur_off", true);
        o.parallax_off = get("parallax_off", false);
        o.shafts_off = get("shafts_off", true);
        o.chromatic_off = get("chromatic_off", true);
        o.quality_low = get("quality_low", true);
        o.maxdecals_off = get("maxdecals_off", true);
        o.occlusion_on = get("occlusion_on", true);
        o.lowres = get("lowres", false);
        o.clouds_off = get("clouds_off", true);
        o.fog_off = get("fog_off", true);
        o.gc_buffer = get("gc_buffer", false);
        o.gc_buffer_mb = state_->hw.ram_bytes >= 32ull * 1024 * 1024 * 1024 ? 4096 : 2048;
        o.launch_options = rust::recommended_launch_options(
            static_cast<unsigned>(state_->hw.ram_bytes / (1024 * 1024)), state_->hw.gpu.vendor);
        return o;
    }

    fortnite::Options fortnite_options() {
        fortnite::Options o;
        std::lock_guard<std::mutex> lock(state_->mutex);
        const auto get = [&](const char* id, bool fallback) {
            const auto it = state_->toggles.find(std::string("fortnite.") + id);
            return it == state_->toggles.end() ? fallback : it->second;
        };
        o.vsync_off = get("vsync_off", true);
        o.unlimited_fps = get("unlimited_fps", true);
        o.fullscreen = get("fullscreen", true);
        o.motion_blur_off = get("motion_blur_off", true);
        o.bloom_off = get("bloom_off", true);
        o.lens_flare_off = get("lens_flare_off", true);
        o.depth_of_field_off = get("dof_off", true);
        o.shadow_tweak = get("shadow_tweak", true);
        o.streaming_pool = get("streaming_pool", true);
        o.dynamic_res_off = get("dynamic_res_off", false);
        o.pool_size_mb = state_->hw.gpu.vram_bytes >= 8ull * 1024 * 1024 * 1024 ? 4096 : 2048;
        return o;
    }

    void apply_rust() {
        const auto exe = state_->games.rust.exe_path;
        if (exe.empty()) {
            set_status(L"RUST не найден — сначала выполните поиск игр");
            return;
        }
        const auto options = rust_options();
        run_async(L"Применяю client.cfg…", [this, exe, options]() -> std::wstring {
            const auto report = rust::apply(rust::resolve_paths(exe), options);
            for (const auto& note : report.notes) log::info("rust: " + note);
            if (report.ok) return L"client.cfg обновлён. Бэкап: " + str::widen(report.backup_dir);
            return L"Не удалось применить client.cfg — подробности в журнале";
        }, true);
    }

    void apply_fortnite() {
        const auto options = fortnite_options();
        run_async(L"Применяю конфиги Fortnite…", [options]() -> std::wstring {
            const auto paths = fortnite::resolve_user_paths();
            const auto report = fortnite::apply(paths, options);
            for (const auto& note : report.notes) log::info("fortnite: " + note);
            if (report.ok) return L"Конфиги Fortnite обновлены. Бэкап: " + str::widen(report.backup_dir);
            return L"Не удалось применить конфиги Fortnite — подробности в журнале";
        }, true);
    }

    void apply_system() {
        const bool purge = is_on("system", "purge_on_apply");
        const bool dvr_off = is_on("system", "dvr_off");
        const bool game_mode = is_on("system", "game_mode_on");
        const bool fse_off = is_on("system", "fse_off");
        const bool hags = is_on("system", "hags_on");
        const bool dns = is_on("system", "dns_flush");
        const bool tcp = is_on("system", "tcp_tuning");
        const bool power = is_on("system", "power_high");
        const bool affinity = is_on("system", "affinity");
        const auto cpu = state_->cpu;
        const auto rust_exe = state_->games.rust.exe_path;
        const auto fn_exe = state_->games.fortnite.exe_path;
        run_async(L"Применяю системные твики…", [=]() -> std::wstring {
            int ok = 0;
            std::string error;
            if (purge) {
                const auto r = mem::purge_standby_list();
                if (r.ok) {
                    ++ok;
                    log::success("system: standby purge, freed " + str::human_bytes(r.freed_bytes));
                } else {
                    log::warn("system: standby purge: " + str::narrow(r.message));
                }
            }
            if (dvr_off && system_tweaks::set_game_dvr(false, error)) ++ok;
            if (game_mode && system_tweaks::set_game_mode(true, error)) ++ok;
            if (hags && system_tweaks::set_hags(true, error)) ++ok;
            if (dns && system_tweaks::flush_dns(error)) ++ok;
            if (tcp && system_tweaks::set_tcp_autotuning(false, error)) ++ok;
            if (power && system_tweaks::set_power_plan(true, error)) ++ok;
            if (fse_off) {
                if (!rust_exe.empty() && system_tweaks::set_fullscreen_optimizations(rust_exe, false, error)) ++ok;
                if (!fn_exe.empty() && system_tweaks::set_fullscreen_optimizations(fn_exe, false, error)) ++ok;
            }
            if (affinity) {
                const auto mask = static_cast<DWORD_PTR>(cpu::recommended_mask(cpu));
                bool applied = false;
                for (const auto& name : {L"RustClient.exe", L"FortniteClient-Win64-Shipping.exe"}) {
                    for (const auto& e : proc::find(name)) {
                        if (proc::set_affinity(e.pid, mask)) applied = true;
                    }
                }
                if (applied) ++ok;
                else log::info("system: affinity — игра не запущена, применится при старте");
            }
            if (ok == 0) return std::wstring(L"Изменений нет или не хватает прав — смотрите журнал");
            return str::wfmt(L"Системные твики применены: %d", ok);
        }, true);
    }

    void apply_settings_page() {
        // Read the switch states before taking the lock: is_on() locks as well and
        // std::mutex is not recursive.
        const bool minimize = is_on("settings", "minimize_on_apply");
        const bool close_on_launch = is_on("settings", "close_on_launch");
        const bool priority = is_on("settings", "autostart_priority");
        {
            std::lock_guard<std::mutex> lock(state_->mutex);
            state_->settings.minimize_on_apply = minimize;
            state_->settings.close_on_launch = close_on_launch;
            // Updates are mandatory: the switch was removed from the UI, but an
            // older settings.json may still carry "false".
            state_->settings.check_updates = true;
            state_->settings.auto_priority = priority;
            save_settings_locked();
        }
        refresh_pages();
        set_status(L"Настройки сохранены");
        ::InvalidateRect(hwnd_, nullptr, FALSE);
    }

    void apply_overview() {
        // One job so the three stages run in order instead of fighting over the
        // busy flag: Rust config, Fortnite config, then the system switches.
        const auto rust_opt = rust_options();
        const auto fn_opt = fortnite_options();
        const auto rust_exe = state_->games.rust.exe_path;
        const bool purge = is_on("system", "purge_on_apply");
        const bool dvr_off = is_on("system", "dvr_off");
        const bool game_mode = is_on("system", "game_mode_on");
        const bool fse_off = is_on("system", "fse_off");
        const bool hags = is_on("system", "hags_on");
        const bool dns = is_on("system", "dns_flush");
        const bool power = is_on("system", "power_high");
        const auto fn_exe = state_->games.fortnite.exe_path;

        run_async(L"Применяю рекомендованный профиль…", [=]() -> std::wstring {
            int ok = 0;
            if (!rust_exe.empty()) {
                const auto report = rust::apply(rust::resolve_paths(rust_exe), rust_opt);
                for (const auto& note : report.notes) log::info("rust: " + note);
                if (report.ok) ++ok;
            }
            {
                const auto report = fortnite::apply(fortnite::resolve_user_paths(), fn_opt);
                for (const auto& note : report.notes) log::info("fortnite: " + note);
                if (report.ok) ++ok;
            }
            std::string error;
            if (purge) {
                const auto r = mem::purge_standby_list();
                if (r.ok) {
                    ++ok;
                    log::success("system: standby purge, freed " + str::human_bytes(r.freed_bytes));
                } else {
                    log::warn("system: standby purge: " + str::narrow(r.message));
                }
            }
            if (dvr_off && system_tweaks::set_game_dvr(false, error)) ++ok;
            if (game_mode && system_tweaks::set_game_mode(true, error)) ++ok;
            if (hags && system_tweaks::set_hags(true, error)) ++ok;
            if (dns && system_tweaks::flush_dns(error)) ++ok;
            if (power && system_tweaks::set_power_plan(true, error)) ++ok;
            if (fse_off) {
                if (!rust_exe.empty() && system_tweaks::set_fullscreen_optimizations(rust_exe, false, error)) ++ok;
                if (!fn_exe.empty() && system_tweaks::set_fullscreen_optimizations(fn_exe, false, error)) ++ok;
            }
            if (ok == 0) return std::wstring(L"Изменений нет или не хватает прав — смотрите журнал");
            return str::wfmt(L"Профиль применён: %d шагов", ok);
        }, true);
    }

    void execute(const std::string& id) {
        if (id == "detect") {
            run_async(L"Ищу установки RUST и FORTNITE…", [this]() -> std::wstring {
                GameCache cache(fsx::data_dir() / L"games-cache.json");
                auto found = find_games(&cache, false);
                {
                    std::lock_guard<std::mutex> lock(state_->mutex);
                    state_->games = found;
                }
                state_->progress = 100;
                const bool rust = found.rust.valid;
                const bool fn = found.fortnite.valid;
                return str::wfmt(L"Поиск завершён за %s: RUST %s, FORTNITE %s", str::widen(found.elapsed).c_str(),
                                 rust ? L"найден" : L"не найден", fn ? L"найден" : L"не найден");
            });
            return;
        }
        if (id == "launch_rust") {
            win::shell_open(L"steam://rungameid/252490");
            log::info("ui: launching RUST through Steam");
            return;
        }
        if (id == "launch_fortnite") {
            win::shell_open(L"com.epicgames.launcher://apps/Fortnite?action=launch&silent=true");
            log::info("ui: launching FORTNITE through Epic Games");
            return;
        }
        if (id == "purge") {
            run_async(L"Очищаю standby-список…", []() -> std::wstring {
                const auto r = mem::purge_standby_list();
                if (!r.ok) return std::wstring(L"Standby: ") + r.message;
                return L"Standby-список очищен, освобождено " + str::human_bytes_w(r.freed_bytes);
            });
            return;
        }
        if (id == "flush_dns") {
            run_async(L"Сбрасываю DNS-кэш…", []() -> std::wstring {
                std::string error;
                if (system_tweaks::flush_dns(error)) return L"DNS-кэш сброшен";
                return L"DNS: " + str::widen(error);
            });
            return;
        }
        if (id == "elevate") {
            log::info("ui: requesting elevation");
            if (!win::relaunch_elevated(L"")) log::warn("ui: elevation declined");
            return;
        }
        if (id == "open_rust_cfg") {
            if (state_->games.rust.exe_path.empty()) {
                set_status(L"RUST не найден — сначала выполните поиск игр");
                return;
            }
            const auto paths = rust::resolve_paths(state_->games.rust.exe_path);
            std::string error;
            if (!system_tweaks::open_config_folder(paths.cfg_dir.wstring(), error)) log::warn(error);
            return;
        }
        if (id == "open_fortnite_cfg") {
            std::string error;
            if (!system_tweaks::open_config_folder(fortnite::resolve_user_paths().config_dir.wstring(), error)) {
                log::warn(error);
            }
            return;
        }
        if (id == "revert_rust") {
            if (state_->games.rust.exe_path.empty()) {
                set_status(L"RUST не найден — откатывать нечего");
                return;
            }
            const auto paths = rust::resolve_paths(state_->games.rust.exe_path);
            run_async(L"Откатываю client.cfg…", [paths]() -> std::wstring {
                const auto report = rust::revert(paths, {});
                for (const auto& note : report.notes) log::info("rust: " + note);
                return report.ok ? std::wstring(L"client.cfg восстановлен") : std::wstring(L"Откат не выполнен");
            });
            return;
        }
        if (id == "revert_fortnite") {
            run_async(L"Откатываю конфиги Fortnite…", []() -> std::wstring {
                const auto report = fortnite::revert(fortnite::resolve_user_paths(), {});
                for (const auto& note : report.notes) log::info("fortnite: " + note);
                return report.ok ? std::wstring(L"Конфиги Fortnite восстановлены") : std::wstring(L"Откат не выполнен");
            });
            return;
        }
        if (id == "export_rust") {
            const auto file = pick_save(L"RUST-optimizer.rop", L"Профили Rust Optimizer (*.rop)\0*.rop\0");
            if (file.empty()) return;
            ProfileStore store(fsx::profile_dir());
            Profile p;
            p.name = "RUST";
            p.game = "rust";
            p.options = rust::to_json(rust_options());
            std::string error;
            if (store.export_file(p, file, error)) {
                set_status(L"Профиль сохранён: " + file.wstring());
                log::success("profiles: exported " + str::narrow(file.wstring()));
            } else {
                set_status(L"Экспорт не удался: " + str::widen(error));
            }
            return;
        }
        if (id == "profile_save_rust" || id == "profile_save_fortnite") {
            const bool is_rust = id == "profile_save_rust";
            Profile p;
            p.name = is_rust ? "RUST" : "FORTNITE";
            p.game = is_rust ? "rust" : "fortnite";
            p.options = is_rust ? rust::to_json(rust_options()) : fortnite::to_json(fortnite_options());
            std::string error;
            ProfileStore store(fsx::profile_dir());
            if (store.save(p, error)) set_status(L"Профиль " + str::widen(p.name) + L" сохранён");
            else set_status(L"Профиль не сохранён: " + str::widen(error));
            return;
        }
        if (id == "profile_load_rust" || id == "profile_load_fortnite") {
            const bool is_rust = id == "profile_load_rust";
            ProfileStore store(fsx::profile_dir());
            const auto all = store.load_all();
            const std::string wanted = is_rust ? "RUST" : "FORTNITE";
            auto it = std::find_if(all.begin(), all.end(), [&](const Profile& p) { return p.name == wanted; });
            if (it == all.end()) {
                set_status(L"Профиль " + str::widen(wanted) + L" не найден");
                return;
            }
            {
                std::lock_guard<std::mutex> lock(state_->mutex);
                const auto& opts = it->options;
                auto set = [&](const char* page, const char* row, const char* key, bool fallback) {
                    state_->toggles[std::string(page) + "." + row] = json::get_bool(opts, key, fallback);
                };
                if (is_rust) {
                    const auto o = rust::from_json(opts);
                    set("rust", "grass_off", "grass_off", o.grass_off);
                    set("rust", "grass_displacement", "grass_displacement", o.grass_displacement);
                    set("rust", "grass_shadowcast", "grass_shadowcast", o.grass_shadowcast);
                    set("rust", "grass_shadowreceive", "grass_shadowreceive", o.grass_shadowreceive);
                    set("rust", "ssaa_off", "ssaa_off", o.ssaa_off);
                    set("rust", "vsync_off", "vsync_off", o.vsync_off);
                    set("rust", "shadows_off", "shadows_off", o.shadows_off);
                    set("rust", "half_res_sss", "half_res_sss", o.half_res_sss);
                    set("rust", "pixellight_off", "pixellight_off", o.pixellight_off);
                    set("rust", "dof_off", "depth_of_field_off", o.depth_of_field_off);
                    set("rust", "motion_blur_off", "motion_blur_off", o.motion_blur_off);
                    set("rust", "parallax_off", "parallax_off", o.parallax_off);
                    set("rust", "shafts_off", "shafts_off", o.shafts_off);
                    set("rust", "chromatic_off", "chromatic_off", o.chromatic_off);
                    set("rust", "gc_buffer", "gc_buffer", o.gc_buffer);
                } else {
                    const auto o = fortnite::from_json(opts);
                    set("fortnite", "vsync_off", "vsync_off", o.vsync_off);
                    set("fortnite", "unlimited_fps", "unlimited_fps", o.unlimited_fps);
                    set("fortnite", "fullscreen", "fullscreen", o.fullscreen);
                    set("fortnite", "motion_blur_off", "motion_blur_off", o.motion_blur_off);
                    set("fortnite", "bloom_off", "bloom_off", o.bloom_off);
                    set("fortnite", "lens_flare_off", "lens_flare_off", o.lens_flare_off);
                    set("fortnite", "dof_off", "depth_of_field_off", o.depth_of_field_off);
                    set("fortnite", "shadow_tweak", "shadow_tweak", o.shadow_tweak);
                    set("fortnite", "streaming_pool", "streaming_pool", o.streaming_pool);
                    set("fortnite", "dynamic_res_off", "dynamic_res_off", o.dynamic_res_off);
                }
                save_settings_locked();
            }
            set_status(L"Профиль " + str::widen(wanted) + L" загружен");
            refresh_pages();
            ::InvalidateRect(hwnd_, nullptr, FALSE);
            return;
        }
        if (id == "profile_export" || id == "profile_import") {
            if (id == "profile_export") {
                const auto file = pick_save(L"RUST-optimizer.rop", L"Профили Rust Optimizer (*.rop)\0*.rop\0");
                if (file.empty()) return;
                Profile p;
                p.name = "RUST";
                p.game = "rust";
                p.options = rust::to_json(rust_options());
                std::string error;
                ProfileStore store(fsx::profile_dir());
                if (store.export_file(p, file, error)) log::success("profiles: exported " + str::narrow(file.wstring()));
                else log::error("profiles: " + error);
            } else {
                const auto file = pick_open(L"Профили Rust Optimizer (*.rop)\0*.rop\0");
                if (file.empty()) return;
                ProfileStore store(fsx::profile_dir());
                std::string error;
                if (auto p = store.import_file(file, error)) {
                    if (store.save(*p, error)) {
                        set_status(L"Импортирован профиль " + str::widen(p->name));
                        log::success("profiles: imported " + p->name);
                    }
                } else {
                    set_status(L"Импорт не удался: " + str::widen(error));
                }
            }
            return;
        }
        if (id == "open_profiles" || id == "open_data" || id == "open_logs") {
            const auto dir = id == "open_profiles" ? fsx::profile_dir()
                             : id == "open_data"  ? fsx::data_dir()
                                                  : fsx::log_dir();
            std::string error;
            if (!system_tweaks::open_config_folder(dir.wstring(), error)) log::warn(error);
            return;
        }
        if (id == "clear_logs") {
            {
                std::lock_guard<std::mutex> lock(state_->mutex);
                state_->logs.clear();
            }
            log::info("ui: on-screen log cleared");
            ::InvalidateRect(hwnd_, nullptr, FALSE);
            return;
        }
        if (id == "update_check") {
            // Same mandatory path the startup worker uses: the card appears and
            // installs the release without any extra confirmation.
            start_update_check();
            return;
        }
        if (id == "update_install") {
            // Legacy action kept for compatibility: the mandatory worker handles
            // download and install, so just restart the check.
            start_update_check();
            return;
        }
        if (id == "cleaner_scan" || id == "cleaner_clean") {
            std::vector<std::string> ids;
            {
                std::lock_guard<std::mutex> lock(state_->mutex);
                for (const auto& target : clean::targets()) {
                    const auto it = state_->toggles.find("cleaner." + target.id);
                    if (it == state_->toggles.end() || it->second) ids.push_back(target.id);
                }
            }
            if (ids.empty()) {
                set_status(L"Не выбрано ни одного пункта очистки");
                return;
            }
            const bool remove = id == "cleaner_clean";
            if (remove) {
                const int answer = ::MessageBoxW(hwnd_,
                                                 L"Удалить выбранные временные файлы и кэши?\n"
                                                 L"Конфиги и сохранения игр не затрагиваются.",
                                                 L"Rust Optimizer", MB_YESNO | MB_ICONWARNING | MB_DEFBUTTON2);
                if (answer != IDYES) return;
            }
            run_async(remove ? L"Очищаю выбранные папки…" : L"Сканирую выбранные папки…",
                      [ids, remove]() -> std::wstring {
                          const auto result = remove ? clean::clean(ids) : clean::scan(ids);
                          if (!result.ok) return L"Очистка: " + result.error;
                          if (result.files == 0) return L"Выбранные папки уже пусты";
                          return str::wfmt(remove ? L"Очищено: %s в %zu файлах"
                                                  : L"Найдено: %s в %zu файлах",
                                           str::human_bytes_w(result.bytes).c_str(), result.files);
                      },
                      false);
            return;
        }
        if (id == "diag_report") {
            HardwareInfo hw;
            AppSettings settings;
            std::wstring rust_dir;
            std::wstring fn_dir;
            {
                std::lock_guard<std::mutex> lock(state_->mutex);
                hw = state_->hw;
                settings = state_->settings;
                rust_dir = state_->games.rust.install_dir;
                fn_dir = state_->games.fortnite.install_dir;
            }
            run_async(L"Собираю диагностический отчёт…", [hw, settings, rust_dir, fn_dir]() -> std::wstring {
                std::string error;
                const auto file = diag::write_report(hw, settings, rust_dir, fn_dir, error);
                if (file.empty()) return L"Отчёт не создан: " + str::widen(error);
                return L"Отчёт создан: " + file.wstring();
            });
            return;
        }
        if (id == "open_reports") {
            fsx::ensure_dir(diag::reports_dir());
            win::shell_open(diag::reports_dir().wstring());
            return;
        }
        if (id == "reset_toggles") {
            {
                std::lock_guard<std::mutex> lock(state_->mutex);
                state_->toggles = default_toggles();
                save_settings_locked();
            }
            refresh_pages();
            set_status(L"Твики сброшены к значениям по умолчанию");
            ::InvalidateRect(hwnd_, nullptr, FALSE);
            return;
        }
        if (id == "priority_now") {
            boost_priority(true);
            return;
        }
        if (id == "apply_launch_options" || id == "revert_launch_options") {
            const auto steam_dir = state_->games.steam.steam_dir;
            const unsigned ram_mb = static_cast<unsigned>(state_->hw.ram_bytes / (1024ull * 1024ull));
            const std::string vendor = state_->hw.gpu.vendor;
            const bool gc_4gb = state_->hw.ram_bytes >= 32ull * 1024ull * 1024ull * 1024ull;
            const bool revert = id == "revert_launch_options";
            run_async(revert ? L"Возвращаю параметры запуска Steam…" : L"Записываю параметры запуска в Steam…",
                      [steam_dir, ram_mb, vendor, gc_4gb, revert]() -> std::wstring {
                          const auto r = revert ? steam_launch::revert(steam_dir)
                                                : steam_launch::apply(steam_dir, ram_mb, vendor, gc_4gb);
                          if (!r.ok) return L"Параметры запуска не изменены: " + str::widen(r.error);
                          if (!revert && !r.changed) return L"Параметры запуска уже актуальны";
                          return std::wstring(revert ? L"Параметры запуска восстановлены из бэкапа"
                                                     : L"Параметры запуска записаны") +
                                  L". Бэкап: " + r.backup_dir.wstring();
                      });
            return;
        }
        if (id == "open_nvidia_panel") {
            std::string error;
            if (visuals::open_nvidia_panel(error)) set_status(L"Панель NVIDIA открыта");
            else set_status(L"Панель NVIDIA: " + str::widen(error));
            return;
        }
        if (id == "repair_windows") {
            if (!win_repair::is_admin()) {
                set_status(L"Для SFC и DISM нужны права администратора");
                return;
            }
            const int answer = ::MessageBoxW(
                hwnd_,
                L"Запустить проверку и исправление системных файлов Windows?\n\n"
                L"sfc /scannow и DISM /RestoreHealth могут занять 10-30 минут.\n"
                L"Журнал будет сохранён в папку логов.",
                L"Rust Optimizer", MB_YESNO | MB_ICONQUESTION | MB_DEFBUTTON2);
            if (answer != IDYES) return;
            run_async(L"Проверяю и исправляю системные файлы Windows…", []() -> std::wstring {
                const auto result = win_repair::run_all();
                return result.summary;
            });
            return;
        }
        if (id == "auto_pilot" || id == "boost_fps") {
            // "boost_fps" is the one-click maximum-FPS switch: every tweak,
            // every cache, power plan and launch options are forced on, then
            // RUST starts and the window closes itself. "auto_pilot" obeys the
            // per-page toggles instead.
            const bool boost = id == "boost_fps";
            const auto exe = state_->games.rust.exe_path;
            if (exe.empty()) {
                set_status(L"RUST не найден — сначала выполните поиск игр");
                return;
            }
            auto rust_opt = rust_options();
            if (boost) {
                // Maximum-FPS preset regardless of the page switches.
                rust_opt.grass_off = true;
                rust_opt.grass_displacement = true;
                rust_opt.grass_shadowcast = true;
                rust_opt.grass_shadowreceive = true;
                rust_opt.ssaa_off = true;
                rust_opt.vsync_off = true;
                rust_opt.shadows_off = true;
                rust_opt.half_res_sss = true;
                rust_opt.pixellight_off = true;
                rust_opt.depth_of_field_off = true;
                rust_opt.motion_blur_off = true;
                rust_opt.parallax_off = true;
                rust_opt.shafts_off = true;
                rust_opt.chromatic_off = true;
                rust_opt.quality_low = true;
                rust_opt.maxdecals_off = true;
                rust_opt.occlusion_on = true;
                rust_opt.lowres = false;  // keep native resolution: no blur
                rust_opt.clouds_off = true;
                rust_opt.fog_off = true;
                rust_opt.gc_buffer = false;
                rust_opt.gc_buffer_mb = state_->hw.ram_bytes >= 32ull * 1024ull * 1024ull * 1024ull ? 4096 : 2048;
            }
            const auto fn_opt = fortnite_options();
            const auto fn_exe = state_->games.fortnite.exe_path;
            const auto steam_dir = state_->games.steam.steam_dir;
            const unsigned ram_mb = static_cast<unsigned>(state_->hw.ram_bytes / (1024ull * 1024ull));
            const std::string vendor = state_->hw.gpu.vendor;
            const bool gc_4gb = state_->hw.ram_bytes >= 32ull * 1024ull * 1024ull * 1024ull;
            const bool purge = boost || is_on("system", "purge_on_apply");
            const bool dvr_off = boost || is_on("system", "dvr_off");
            const bool game_mode = boost || is_on("system", "game_mode_on");
            const bool fse_off = boost || is_on("system", "fse_off");
            const bool hags = boost || is_on("system", "hags_on");
            const bool dns = boost || is_on("system", "dns_flush");
            const bool power_high = boost || is_on("system", "power_high");
            const bool want_clean = boost || is_on("overview", "autopilot_clean");
            const bool want_visuals = boost || is_on("overview", "autopilot_visuals");
            const bool want_repair = !boost && is_on("overview", "repair_windows") && win_repair::is_admin();
            std::vector<std::string> clean_ids;
            std::string preset_id;
            {
                std::lock_guard<std::mutex> lock(state_->mutex);
                if (boost) {
                    clean_ids = clean::boost_ids();
                } else {
                    for (const auto& target : clean::targets()) {
                        const auto it = state_->toggles.find("cleaner." + target.id);
                        if (it == state_->toggles.end() || it->second) clean_ids.push_back(target.id);
                    }
                }
                preset_id = state_->settings.image_preset;
            }

            run_async(boost ? L"БУСТ FPS: чищу, применяю всё и запускаю RUST…"
                            : L"Автопилот: чиню, чищу и запускаю RUST…",
                      [=, shared = state_]() -> std::wstring {
                          int ok = 0;
                          std::wstring problems;
                          const auto add_problem = [&problems](const std::wstring& text) {
                              if (!problems.empty()) problems += L" ";
                              problems += text;
                          };

                          // 1. Windows integrity, only when the user asked for it.
                          if (want_repair) {
                              const auto repair = win_repair::run_all();
                              if (repair.sfc.ok && repair.dism.ok) ++ok;
                              else add_problem(repair.summary);
                          }

                          // 2. Temporary files and shader caches.
                          if (want_clean && !clean_ids.empty()) {
                              const auto clean_result = clean::clean(clean_ids);
                              if (clean_result.ok) {
                                  ++ok;
                                  log::success("autopilot: cleaned " + str::human_bytes(clean_result.bytes) + " in " +
                                               std::to_string(clean_result.files) + " files");
                              }
                          }

                          const auto rust_report = rust::apply(rust::resolve_paths(exe), rust_opt);
                          for (const auto& note : rust_report.notes) log::info("rust: " + note);
                          if (rust_report.ok) ++ok;
                          else add_problem(L"client.cfg не обновлён.");

                          if (!fn_exe.empty()) {
                              const auto fn_report = fortnite::apply(fortnite::resolve_user_paths(), fn_opt);
                              for (const auto& note : fn_report.notes) log::info("fortnite: " + note);
                              if (fn_report.ok) ++ok;
                              else add_problem(L"Конфиги Fortnite не обновлены.");
                          }

                          std::string error;
                          if (dvr_off && system_tweaks::set_game_dvr(false, error)) ++ok;
                          if (game_mode && system_tweaks::set_game_mode(true, error)) ++ok;
                          if (hags && system_tweaks::set_hags(true, error)) ++ok;
                          if (dns && system_tweaks::flush_dns(error)) ++ok;
                          if (power_high && system_tweaks::set_power_plan(true, error)) ++ok;
                          if (fse_off && system_tweaks::set_fullscreen_optimizations(exe, false, error)) ++ok;
                          if (fse_off && !fn_exe.empty() &&
                              system_tweaks::set_fullscreen_optimizations(fn_exe, false, error)) {
                              ++ok;
                          }
                          if (purge) {
                              const auto r = mem::purge_standby_list();
                              if (r.ok) {
                                  ++ok;
                                  log::success("autopilot: standby purge, freed " + str::human_bytes(r.freed_bytes));
                              }
                          }

                          // Launch Options need Steam closed; this also reports back
                          // when the user has to close it first.
                          const auto opts = steam_launch::apply(steam_dir, ram_mb, vendor, gc_4gb);
                          std::wstring opts_text;
                          if (opts.ok && opts.changed) {
                              ++ok;
                              opts_text = L"Параметры запуска Steam обновлены.";
                          } else if (opts.ok) {
                              opts_text = L"Параметры запуска уже актуальны.";
                          } else {
                              opts_text = L"Параметры запуска пропущены: " + str::widen(opts.error) + L".";
                          }

                          // Vivid picture: gamma ramp applied before the game
                          // starts, so the first frame is already "juicy".
                          std::wstring visual_text;
                          if (want_visuals) {
                              const std::string applied_id = preset_id == "off" ? "vivid" : preset_id;
                              std::string visual_error;
                              const bool visual_ok = visuals::apply(applied_id, visual_error);
                              if (visual_ok) {
                                  ++ok;
                                  {
                                      // Remember the fallback preset so it is
                                      // re-applied on the next start.
                                      std::lock_guard<std::mutex> lock(shared->mutex);
                                      shared->settings.image_preset = applied_id;
                                  }
                                  shared->settings_dirty = true;
                                  visual_text = L"Картинка включена.";
                              } else {
                                  visual_text = L"Картинка не изменена: " + str::widen(visual_error) + L".";
                              }
                          }

                          win::shell_open(L"steam://rungameid/252490");
                          log::success("autopilot: launching RUST through Steam");
                          // tick() closes the window as soon as RustClient.exe
                          // appears, even if "close_on_launch" is switched off.
                          shared->close_after_launch = true;

                          std::wstring status = (boost ? L"БУСТ FPS: " : L"Автопилот: ") +
                                                std::to_wstring(ok) + L" шагов применено. ";
                          status += opts_text + L" " + visual_text + L" RUST запускается. ";
                          status += L"Окно закроется само при появлении игры.";
                          if (!problems.empty()) status += L" " + problems;
                          return status;
                      },
                      true);
            return;
        }
    }

    std::filesystem::path pick_open(const wchar_t* filter) {
        wchar_t file[MAX_PATH]{};
        OPENFILENAMEW ofn{};
        ofn.lStructSize = sizeof(ofn);
        ofn.hwndOwner = hwnd_;
        ofn.lpstrFilter = filter;
        ofn.lpstrFile = file;
        ofn.nMaxFile = MAX_PATH;
        ofn.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST;
        if (!::GetOpenFileNameW(&ofn)) return {};
        return std::filesystem::path(file);
    }

    std::filesystem::path pick_save(const wchar_t* name, const wchar_t* filter) {
        wchar_t file[MAX_PATH]{};
        const std::size_t name_len = (std::min)(std::wcslen(name), static_cast<std::size_t>(MAX_PATH - 1));
        std::copy_n(name, name_len, file);
        OPENFILENAMEW ofn{};
        ofn.lStructSize = sizeof(ofn);
        ofn.hwndOwner = hwnd_;
        ofn.lpstrFilter = filter;
        ofn.lpstrFile = file;
        ofn.nMaxFile = MAX_PATH;
        ofn.lpstrDefExt = L"rop";
        ofn.Flags = OFN_OVERWRITEPROMPT | OFN_PATHMUSTEXIST;
        if (!::GetSaveFileNameW(&ofn)) return {};
        return std::filesystem::path(file);
    }

    void boost_priority(bool report) {
        bool changed = false;
        for (const auto& name : {L"RustClient.exe", L"FortniteClient-Win64-Shipping.exe"}) {
            for (const auto& e : proc::find(name)) {
                const auto current = proc::get_priority(e.pid);
                if (current && *current == HIGH_PRIORITY_CLASS) continue;
                if (proc::set_priority(e.pid, HIGH_PRIORITY_CLASS)) {
                    changed = true;
                    log::success("priority: " + str::narrow(e.name) + " -> HIGH (" + std::to_string(e.pid) + ")");
                }
            }
        }
        if (report) set_status(changed ? L"Приоритет игры повышен" : L"Игра не запущена — приоритет применится позже");
    }

    // 60 fps easing: scroll, page slide-in and update progress all settle here.
    void tick_anim() {
        bool changed = false;
        if (!pages_.empty()) {
            const std::string id = pages_[static_cast<std::size_t>(page_index_)].id;
            const float current = scroll_for(id);
            float target = scroll_target_for(id);
            target = std::clamp(target, 0.0f, (std::max)(0.0f, max_scroll_));
            if (std::abs(target - current) > 0.5f) {
                scroll_[id] = current + (target - current) * 0.30f;
                changed = true;
            } else if (current != target) {
                scroll_[id] = target;
                changed = true;
            }
        }
        if (page_anim_ < 1.0f) {
            page_anim_ = (std::min)(1.0f, page_anim_ + 0.12f);
            changed = true;
        }
        const float update_target = static_cast<float>(state_->update_progress.load());
        if (std::abs(update_target - display_progress_) > 0.05f) {
            display_progress_ += (update_target - display_progress_) * 0.22f;
            changed = true;
        }
        if (changed) ::InvalidateRect(hwnd_, nullptr, FALSE);
    }

    // Windows were told to close by WM_CLOSE once the game is up. The autopilot
    // arms this too, so "optimize → launch → close" is a single click.
    void maybe_close_on_launch() {
        const bool rust_running = proc::is_running(L"RustClient.exe");
        const bool fortnite_running =
            !rust_running && proc::is_running(L"FortniteClient-Win64-Shipping.exe");
        const bool running = rust_running || fortnite_running;
        if (!game_seen_ready_) {
            // A game that was already running at startup is not a "launch".
            game_seen_ = running;
            game_seen_ready_ = true;
        }
        const bool newly_running = running && !game_seen_;
        game_seen_ = running;
        if (!running) return;

        // The autopilot always wants to close; otherwise it is the user's
        // "Закрываться при запуске игры" switch and only a fresh launch counts.
        const bool armed = state_->close_after_launch.load();
        if (!armed && !newly_running) return;
        if (!armed) {
            std::lock_guard<std::mutex> lock(state_->mutex);
            if (!state_->settings.close_on_launch) return;
        }
        // Never interrupt an update in flight.
        if (state_->update_installing.load() || state_->update_mandatory.load()) return;
        if (state_->busy.load()) {
            // A worker is still writing configs; try again on the next tick.
            return;
        }
        state_->close_after_launch = false;
        log::info(std::string("ui: ") + (rust_running ? "RustClient.exe" : "FortniteClient-Win64-Shipping.exe") +
                  " detected, closing optimizer");
        ::PostMessageW(hwnd_, WM_CLOSE, 0, 0);
    }

    void tick() {
        // Priority + optional purge timer, both non-blocking and cheap.
        maybe_close_on_launch();
        if (state_->settings_dirty.exchange(false)) save_settings();
        if (is_on("overview", "auto_priority") && state_->settings.auto_priority) boost_priority(false);
        if (is_on("overview", "auto_purge")) {
            const auto now = std::chrono::steady_clock::now();
            if (now - state_->last_purge > std::chrono::minutes(15)) {
                state_->last_purge = now;
                std::thread([]() {
                    const auto r = mem::purge_standby_list();
                    if (r.ok) log::success("auto: standby purged, freed " + str::human_bytes(r.freed_bytes));
                }).detach();
            }
        }
        ::InvalidateRect(hwnd_, nullptr, FALSE);
    }

    // ---------------------------------------------------------------- fields
    std::shared_ptr<Shared> state_;
    HINSTANCE instance_ = nullptr;
    HWND hwnd_ = nullptr;
    ID2D1Factory* d2d_ = nullptr;
    IDWriteFactory* dw_ = nullptr;
    ID2D1HwndRenderTarget* rt_ = nullptr;
    UINT32 rt_pixel_w_ = 0;
    UINT32 rt_pixel_h_ = 0;
    Themed theme_ = dark();
    std::vector<Page> pages_;
    int page_index_ = 0;
    bool page_restored_ = false;
    std::map<std::string, float> scroll_;
    std::map<std::string, float> scroll_target_;
    float page_anim_ = 1.0f;
    bool game_seen_ = false;
    bool game_seen_ready_ = false;
    float display_progress_ = 0.0f;
    std::vector<Hit> hits_;
    int hover_ = -1;
    float scale_ = 1.0f;
    float max_scroll_ = 0.0f;
    // Scrollbar state (the mouse wheel is not always available, so the content
    // area gets a draggable thumb plus clickable track).
    Rect scroll_track_{};
    Rect scroll_thumb_{};
    bool scrollbar_active_ = false;
    bool scroll_drag_ = false;
    bool scrollbar_hover_ = false;
    float scroll_drag_offset_ = 0.0f;
    float scroll_view_h_ = 0.0f;
    bool cursor_hand_ = false;
    bool tracking_leave_ = false;
    int click_x_ = 0;
    int click_y_ = 0;
    bool is_admin_ = false;
    HICON icon_big_ = nullptr;
    HICON icon_small_ = nullptr;
};

std::shared_ptr<Shared> make_state() {
    auto state = std::make_shared<Shared>();
    SettingsStore store(fsx::data_dir() / L"settings.json");
    state->settings = store.load();
    state->toggles = default_toggles();
    if (state->settings.toggles.is_object()) {
        for (auto it = state->settings.toggles.begin(); it != state->settings.toggles.end(); ++it) {
            if (it.value().is_boolean()) state->toggles[it.key()] = it.value().get<bool>();
        }
    }
    return state;
}

}  // namespace

int run(const StartOptions& options) {
    // Global services first: logging, DPI, GDI+.
    fsx::ensure_dir(fsx::log_dir());
    log::Logger::instance().set_log_file(
        str::narrow((fsx::log_dir() / (L"app-" + str::widen(fsx::time_stamp()) + L".log")).wstring()));
    log::info(std::string("=== Rust Optimizer ") + kVersion + " starting ===");

    win::set_dpi_awareness();
    if (!icon::init()) log::warn("icon: GDI+ init failed");

    auto state = make_state();
    // A chosen picture preset survives restarts: the saved original ramps make
    // it safe to re-apply, and "off" still restores the untouched desktop.
    if (state->settings.image_preset != "off") {
        std::string visual_error;
        if (!visuals::apply(state->settings.image_preset, visual_error)) {
            log::warn("visuals: startup preset skipped: " + visual_error);
        }
    }
    state->hw = gather();
    state->cpu = cpu::detect();
    log::info("hw: " + str::narrow(state->hw.cpu_name) + " / " + state->hw.gpu.vendor);

    SharedSink sink;
    sink.state = state;
    log::Logger::instance().add_sink(&sink);

    App app(state, options.instance);
    app.load_icons();
    if (!app.create()) {
        log::Logger::instance().remove_sink(&sink);
        log::Logger::instance().flush();
        icon::shutdown();
        return 1;
    }

    // Cache-first detection keeps startup instant; a full scan runs when needed.
    GameCache cache(fsx::data_dir() / L"games-cache.json");
    state->games = find_games(&cache, true);
    {
        std::lock_guard<std::mutex> lock(state->mutex);
        const bool r = state->games.rust.valid;
        const bool f = state->games.fortnite.valid;
        if (r && f) state->status = L"Готово · RUST и FORTNITE найдены";
        else if (r) state->status = L"Готово · найден RUST, FORTNITE не обнаружен";
        else if (f) state->status = L"Готово · найден FORTNITE, RUST не обнаружен";
        else state->status = L"Игры не найдены — проверьте установку Steam/Epic";
    }
    ::PostMessageW(state->hwnd, WM_APP_REFRESH, 0, 0);

    app.start_background();
    const int code = app.run();

    log::Logger::instance().remove_sink(&sink);
    log::Logger::instance().flush();
    icon::shutdown();
    return code;
}

namespace {

// Writes diagnostics to the inherited handle. A GUI binary is commonly started
// with stdout redirected to a pipe or file (CI, bug reports), so a console-only
// write would silently produce nothing.
void write_stdout(const std::wstring& text) {
    HANDLE out = ::GetStdHandle(STD_OUTPUT_HANDLE);
    if (out == nullptr || out == INVALID_HANDLE_VALUE) {
        if (!::AllocConsole()) return;
        out = ::GetStdHandle(STD_OUTPUT_HANDLE);
        if (out == nullptr || out == INVALID_HANDLE_VALUE) return;
    }
    DWORD mode = 0;
    if (::GetConsoleMode(out, &mode) != 0) {
        DWORD written = 0;
        ::WriteConsoleW(out, text.c_str(), static_cast<DWORD>(text.size()), &written, nullptr);
        return;
    }
    const std::string utf8 = str::narrow(text);
    DWORD written = 0;
    ::WriteFile(out, utf8.data(), static_cast<DWORD>(utf8.size()), &written, nullptr);
}

}  // namespace

int selftest() {
    // Console diagnostics used by CI and by users who file an issue.
    const auto line = [](const std::wstring& s) { write_stdout(s + L"\n"); };

    win::set_dpi_awareness();
    line(L"Rust Optimizer " + str::widen(kVersion) + L" - self-test");
    line(L"------------------------------------------------------------");

    const auto hw = gather();
    line(L"OS:        " + hw.os_display);
    line(L"CPU:       " + hw.cpu_name + L" (" + std::to_wstring(hw.physical_cores) + L"c/" +
         std::to_wstring(hw.logical_cores) + L"t)");
    line(L"RAM:       " + str::human_bytes_w(hw.ram_bytes));
    line(L"GPU:       " + hw.gpu.name + L" [" + str::widen(hw.gpu.vendor) + L", " +
         str::human_bytes_w(hw.gpu.vram_bytes) + L" VRAM]");

    const auto topo = cpu::detect();
    line(L"Topology:  " + topo.summary);
    if (!topo.note.empty()) line(L"Note:      " + topo.note);

    line(std::wstring(L"Elevated:  ") + (win::is_admin() ? L"yes" : L"no (standby purge unavailable)"));

    const auto found = find_games(nullptr, false);
    line(L"Steam:     " + (found.steam.found_steam ? found.steam.steam_dir : std::wstring(L"not found")));
    line(L"RUST:      " + (found.rust.valid ? found.rust.exe_path : std::wstring(L"not found")));
    line(L"FORTNITE:  " + (found.fortnite.valid ? found.fortnite.exe_path : std::wstring(L"not found")));
    for (const auto& t : found.trace) line(L"  trace:   " + str::widen(t));
    line(L"Elapsed:   " + str::widen(found.elapsed));

    const auto mem = proc::find(L"RustClient.exe");
    line(L"RUST proc: " + (mem.empty() ? std::wstring(L"not running") : L"running (pid " + std::to_wstring(mem[0].pid) + L")"));

    line(L"Logs:      " + fsx::log_dir().wstring());
    line(L"Settings:  " + (fsx::data_dir() / L"settings.json").wstring());
    line(L"Update:    " + std::wstring(L"releases from github.com/") + str::widen(kGithubOwner) + L"/" +
         str::widen(kGithubRepo));
    line(L"------------------------------------------------------------");
    line(L"self-test finished");
    log::Logger::instance().flush();
    return 0;
}

int print_version() {
    write_stdout(L"Rust Optimizer " + str::widen(kVersion) + L"\n");
    return 0;
}

}  // namespace ro::ui
