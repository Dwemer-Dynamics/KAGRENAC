#include "build_id.h"

#include <windows.h>
#include <bcrypt.h>

#include <array>
#include <cstdio>
#include <cstring>
#include <span>
#include <vector>

namespace {

// Entries are added only together with in-engine evidence in
// docs/engine-packs/elden-ring.md. Never add an entry from a file version alone.
constexpr std::array<QualifiedBuild, 0> kQualifiedBuilds{};

struct FileHandle {
    HANDLE h = INVALID_HANDLE_VALUE;
    ~FileHandle() {
        if (h != INVALID_HANDLE_VALUE) CloseHandle(h);
    }
};

bool read_version(const std::wstring& path, BuildId& out) {
    DWORD ignored = 0;
    DWORD size = GetFileVersionInfoSizeW(path.c_str(), &ignored);
    if (size == 0) return false;
    std::vector<unsigned char> data(size);
    if (!GetFileVersionInfoW(path.c_str(), 0, size, data.data())) return false;
    VS_FIXEDFILEINFO* info = nullptr;
    UINT len = 0;
    if (!VerQueryValueW(data.data(), L"\\", reinterpret_cast<void**>(&info), &len) ||
        len < sizeof(VS_FIXEDFILEINFO) || info->dwSignature != 0xFEEF04BD) {
        return false;
    }
    out.file_version[0] = HIWORD(info->dwFileVersionMS);
    out.file_version[1] = LOWORD(info->dwFileVersionMS);
    out.file_version[2] = HIWORD(info->dwFileVersionLS);
    out.file_version[3] = LOWORD(info->dwFileVersionLS);
    return true;
}

bool read_pe_headers(std::span<const unsigned char> head, BuildId& out) {
    if (head.size() < sizeof(IMAGE_DOS_HEADER)) return false;
    IMAGE_DOS_HEADER dos;
    std::memcpy(&dos, head.data(), sizeof(dos));
    if (dos.e_magic != IMAGE_DOS_SIGNATURE || dos.e_lfanew < 0) return false;
    size_t offset = static_cast<size_t>(dos.e_lfanew);
    if (offset + sizeof(IMAGE_NT_HEADERS64) > head.size()) return false;
    IMAGE_NT_HEADERS64 nt;
    std::memcpy(&nt, head.data() + offset, sizeof(nt));
    if (nt.Signature != IMAGE_NT_SIGNATURE ||
        nt.FileHeader.Machine != IMAGE_FILE_MACHINE_AMD64 ||
        nt.OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR64_MAGIC) {
        return false;
    }
    out.pe_timestamp = nt.FileHeader.TimeDateStamp;
    out.size_of_image = nt.OptionalHeader.SizeOfImage;
    return true;
}

}  // namespace

bool read_build_id(const std::wstring& path, BuildId& out, std::string& error) {
    out = BuildId{};
    if (GetFileAttributesW(path.c_str()) == INVALID_FILE_ATTRIBUTES) {
        error = "file not found or not accessible";
        return false;
    }
    if (!read_version(path, out)) {
        error = "no readable version resource";
        return false;
    }
    FileHandle file;
    file.h = CreateFileW(path.c_str(), GENERIC_READ,
                         FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
                         OPEN_EXISTING, FILE_FLAG_SEQUENTIAL_SCAN, nullptr);
    if (file.h == INVALID_HANDLE_VALUE) {
        error = "cannot open file for reading";
        return false;
    }
    LARGE_INTEGER size{};
    if (!GetFileSizeEx(file.h, &size)) {
        error = "cannot read file size";
        return false;
    }
    out.file_size = static_cast<uint64_t>(size.QuadPart);

    BCRYPT_ALG_HANDLE alg = nullptr;
    BCRYPT_HASH_HANDLE hash = nullptr;
    if (BCryptOpenAlgorithmProvider(&alg, BCRYPT_SHA256_ALGORITHM, nullptr, 0) != 0) {
        error = "SHA-256 provider unavailable";
        return false;
    }
    bool ok = BCryptCreateHash(alg, &hash, nullptr, 0, nullptr, 0, 0) == 0;
    std::vector<unsigned char> buffer(1 << 20);
    bool first = true;
    while (ok) {
        DWORD read = 0;
        if (!ReadFile(file.h, buffer.data(), static_cast<DWORD>(buffer.size()), &read, nullptr)) {
            ok = false;
            break;
        }
        if (read == 0) break;
        if (first) {
            if (!read_pe_headers(std::span(buffer.data(), read), out)) {
                error = "not an x64 PE image";
                ok = false;
                break;
            }
            first = false;
        }
        ok = BCryptHashData(hash, buffer.data(), read, 0) == 0;
    }
    unsigned char digest[32] = {};
    if (ok) ok = !first && BCryptFinishHash(hash, digest, sizeof(digest), 0) == 0;
    if (hash) BCryptDestroyHash(hash);
    BCryptCloseAlgorithmProvider(alg, 0);
    if (!ok) {
        if (error.empty()) error = "failed to read or hash file";
        return false;
    }
    char hex[65] = {};
    for (int i = 0; i < 32; ++i) std::snprintf(hex + i * 2, 3, "%02x", digest[i]);
    out.sha256 = hex;
    return true;
}

std::string describe_build_id(const BuildId& id) {
    char text[256];
    std::snprintf(text, sizeof(text),
                  "file_version=%u.%u.%u.%u pe_timestamp=0x%08x size_of_image=0x%08x "
                  "file_size=%llu sha256=%s",
                  id.file_version[0], id.file_version[1], id.file_version[2],
                  id.file_version[3], id.pe_timestamp, id.size_of_image,
                  static_cast<unsigned long long>(id.file_size), id.sha256.c_str());
    return text;
}

const QualifiedBuild* find_qualified_build(const BuildId& id) {
    for (const QualifiedBuild& q : kQualifiedBuilds) {
        if (std::memcmp(q.file_version, id.file_version, sizeof(q.file_version)) == 0 &&
            q.pe_timestamp == id.pe_timestamp && q.size_of_image == id.size_of_image &&
            q.file_size == id.file_size && id.sha256 == q.sha256) {
            return &q;
        }
    }
    return nullptr;
}
