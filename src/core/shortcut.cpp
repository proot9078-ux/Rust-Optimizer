#include "ro/shortcut.hpp"

#include <windows.h>
#include <objbase.h>
#include <shlobj.h>
#include <shobjidl.h>

#include <string>

#include "ro/fs.hpp"
#include "ro/log.hpp"
#include "ro/str.hpp"
#include "ro/win32.hpp"

namespace ro::shortcut {

namespace {

constexpr wchar_t kLinkName[] = L"Rust Optimizer.lnk";

// COM must be initialized on whichever thread builds the link; the applier runs
// on a fresh process, the UI on a worker thread.
class ComScope {
public:
    ComScope() {
        const HRESULT hr = ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
        owned_ = SUCCEEDED(hr);
    }
    ~ComScope() {
        if (owned_) ::CoUninitialize();
    }
    ComScope(const ComScope&) = delete;
    ComScope& operator=(const ComScope&) = delete;

private:
    bool owned_ = false;
};

std::filesystem::path known_folder(REFKNOWNFOLDERID id) {
    PWSTR raw = nullptr;
    if (FAILED(::SHGetKnownFolderPath(id, KF_FLAG_CREATE, nullptr, &raw)) || !raw) return {};
    std::filesystem::path out(raw);
    ::CoTaskMemFree(raw);
    return out;
}

bool write_link(const std::filesystem::path& dir, const std::filesystem::path& exe, std::string* error) {
    if (dir.empty()) {
        if (error) *error = "не удалось определить папку для ярлыка";
        return false;
    }
    std::error_code ec;
    std::filesystem::create_directories(dir, ec);

    const std::filesystem::path link_path = dir / kLinkName;
    IShellLinkW* link = nullptr;
    HRESULT hr = ::CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_IShellLinkW,
                                    reinterpret_cast<void**>(&link));
    if (FAILED(hr) || !link) {
        if (error) *error = "CoCreateInstance(ShellLink) failed: " + str::fmt("0x%08lX", static_cast<unsigned long>(hr));
        return false;
    }

    link->SetPath(exe.wstring().c_str());
    std::filesystem::path work_dir = exe.parent_path();
    link->SetWorkingDirectory(work_dir.wstring().c_str());
    link->SetDescription(L"Rust Optimizer — оптимизация RUST и FORTNITE");
    link->SetIconLocation(exe.wstring().c_str(), 0);

    IPersistFile* file = nullptr;
    hr = link->QueryInterface(IID_IPersistFile, reinterpret_cast<void**>(&file));
    if (FAILED(hr) || !file) {
        if (error) *error = "IPersistFile unavailable: " + str::fmt("0x%08lX", static_cast<unsigned long>(hr));
        link->Release();
        return false;
    }
    hr = file->Save(link_path.wstring().c_str(), TRUE);
    file->Release();
    link->Release();
    if (FAILED(hr)) {
        if (error) *error = "не удалось сохранить ярлык: " + str::fmt("0x%08lX", static_cast<unsigned long>(hr));
        return false;
    }
    log::info("shortcut: " + str::narrow(link_path.wstring()));
    return true;
}

}  // namespace

bool create_desktop(const std::filesystem::path& exe, std::string* error) {
    ComScope com;
    return write_link(known_folder(FOLDERID_Desktop), exe, error);
}

bool create_start_menu(const std::filesystem::path& exe, std::string* error) {
    ComScope com;
    return write_link(known_folder(FOLDERID_Programs), exe, error);
}

bool ensure(const std::filesystem::path& exe) {
    if (exe.empty()) return false;
    std::string err;
    const bool desktop = create_desktop(exe, &err);
    if (!desktop) log::warn("shortcut: desktop failed: " + err);
    std::string err2;
    if (!create_start_menu(exe, &err2)) log::warn("shortcut: start menu failed: " + err2);
    return desktop;
}

}  // namespace ro::shortcut

