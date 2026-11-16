#pragma once
#include <cstdint>
#include <filesystem>
#include <string>

namespace ro {

// Streaming SHA-256 (FIPS 180-4), used for update and backup integrity checks.
class Sha256 {
public:
    Sha256();
    void update(const void* data, std::size_t size);
    void update(std::string_view text);
    std::string hex_digest();  // finalises; calling update afterwards is UB

private:
    std::uint32_t h_[8];
    std::uint64_t length_ = 0;
    unsigned char buffer_[64];
    std::size_t buffer_len_ = 0;
    void transform(const unsigned char* block);
};

std::string sha256_hex(std::string_view text);
std::string sha256_hex(const void* data, std::size_t size);
std::string sha256_file(const std::filesystem::path& path);

}  // namespace ro
