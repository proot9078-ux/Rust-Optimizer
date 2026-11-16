#include "ro/zip.hpp"

#include "miniz.h"

#include <cstring>
#include <fstream>
#include <vector>

#include "ro/fs.hpp"
#include "ro/str.hpp"

namespace ro::zip {

namespace {

// miniz' own file helpers take narrow paths, which breaks on non-ASCII user
// profiles (Cyrillic, CJK...). Archives are therefore read into memory and
// written back through std::filesystem::path, which is opened with the wide API.
bool read_bytes(const std::filesystem::path& p, std::vector<char>& out) {
    std::ifstream in(p, std::ios::binary);
    if (!in) return false;
    in.seekg(0, std::ios::end);
    const auto size = in.tellg();
    if (size < 0) return false;
    in.seekg(0, std::ios::beg);
    out.resize(static_cast<std::size_t>(size));
    if (!out.empty()) in.read(out.data(), static_cast<std::streamsize>(out.size()));
    return static_cast<bool>(in) || in.eof();
}

bool write_bytes(const std::filesystem::path& p, const void* data, std::size_t size) {
    std::ofstream out(p, std::ios::binary | std::ios::trunc);
    if (!out) return false;
    if (size > 0) out.write(static_cast<const char*>(data), static_cast<std::streamsize>(size));
    return static_cast<bool>(out);
}

bool safe_entry_name(const std::string& name) {
    if (name.empty()) return false;
    if (name.find("..") != std::string::npos) return false;
    if (name[0] == '/' || name[0] == '\\') return false;
    if (name.find(':') != std::string::npos) return false;
    return true;
}

std::filesystem::path dest_for(const std::filesystem::path& root, const std::string& name) {
    std::filesystem::path rel = std::filesystem::path(str::widen(name));
    std::filesystem::path out = root;
    for (const auto& part : rel) {
        const std::wstring p = part.wstring();
        if (p == L"." || p.empty()) continue;
        out /= part;
    }
    return out;
}

// Owns the archive bytes and the initialized reader for one call.
struct Archive {
    std::vector<char> bytes;
    mz_zip_archive zip{};
    bool open = false;

    bool load(const std::filesystem::path& path) {
        if (!read_bytes(path, bytes) || bytes.empty()) return false;
        open = mz_zip_reader_init_mem(&zip, bytes.data(), bytes.size(), 0) != MZ_FALSE;
        return open;
    }
    ~Archive() {
        if (open) mz_zip_reader_end(&zip);
    }
};

bool extract_entry(Archive& a, mz_uint index, const std::filesystem::path& dest) {
    std::size_t size = 0;
    void* data = mz_zip_reader_extract_to_heap(&a.zip, index, &size, 0);
    if (!data) return false;
    const bool ok = write_bytes(dest, data, size);
    mz_free(data);
    return ok;
}

}  // namespace

std::vector<Entry> list(const std::filesystem::path& archive, std::string& error) {
    std::vector<Entry> out;
    Archive a;
    if (!a.load(archive)) {
        error = "не удалось открыть архив";
        return out;
    }
    const mz_uint count = mz_zip_reader_get_num_files(&a.zip);
    for (mz_uint i = 0; i < count; ++i) {
        mz_zip_archive_file_stat st{};
        if (!mz_zip_reader_file_stat(&a.zip, i, &st)) continue;
        Entry e;
        e.name = st.m_filename;
        e.size = st.m_uncomp_size;
        e.is_dir = mz_zip_reader_is_file_a_directory(&a.zip, i) != MZ_FALSE;
        out.push_back(std::move(e));
    }
    return out;
}

bool extract(const std::filesystem::path& archive, const std::filesystem::path& dest_dir,
             std::string& error) {
    Archive a;
    if (!a.load(archive)) {
        error = "не удалось открыть архив " + archive.filename().string();
        return false;
    }
    if (!fsx::ensure_dir(dest_dir)) {
        error = "не удалось создать папку распаковки";
        return false;
    }
    const mz_uint count = mz_zip_reader_get_num_files(&a.zip);
    int skipped = 0;
    for (mz_uint i = 0; i < count; ++i) {
        mz_zip_archive_file_stat st{};
        if (!mz_zip_reader_file_stat(&a.zip, i, &st)) continue;
        const std::string name = st.m_filename;
        if (!safe_entry_name(name)) {
            ++skipped;
            continue;
        }
        const auto dest = dest_for(dest_dir, name);
        if (mz_zip_reader_is_file_a_directory(&a.zip, i) != MZ_FALSE) {
            fsx::ensure_dir(dest);
            continue;
        }
        fsx::ensure_dir(dest.parent_path());
        if (!extract_entry(a, i, dest)) {
            error = "ошибка распаковки " + name;
            return false;
        }
    }
    if (skipped > 0) error = std::to_string(skipped) + " небезопасных записей пропущено";
    return true;
}

bool extract_one(const std::filesystem::path& archive, std::string_view entry_name,
                 const std::filesystem::path& dest_file, std::string& error) {
    Archive a;
    if (!a.load(archive)) {
        error = "не удалось открыть архив";
        return false;
    }
    const int index = mz_zip_reader_locate_file(&a.zip, std::string(entry_name).c_str(), nullptr, 0);
    if (index < 0) {
        error = "в архиве нет " + std::string(entry_name);
        return false;
    }
    fsx::ensure_dir(dest_file.parent_path());
    const bool ok = extract_entry(a, static_cast<mz_uint>(index), dest_file);
    if (!ok) error = "ошибка распаковки " + std::string(entry_name);
    return ok;
}

}  // namespace ro::zip
