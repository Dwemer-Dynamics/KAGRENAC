// Exact build identity of an executable file on disk, used to fail closed on any
// game build that has not been qualified. The SHA-256 fingerprints the file; it is
// not a check of the code running in memory. Windows system libraries only.
#pragma once

#include <cstdint>
#include <string>

struct BuildId {
    uint16_t file_version[4] = {};  // VS_FIXEDFILEINFO file version, not the title patch
    uint32_t pe_timestamp = 0;      // IMAGE_FILE_HEADER::TimeDateStamp
    uint32_t size_of_image = 0;     // IMAGE_OPTIONAL_HEADER64::SizeOfImage
    uint64_t file_size = 0;
    std::string sha256;             // lowercase hex of the whole file
};

// Reads the version resource, PE headers and SHA-256 of the file at `path`.
// Read-only. On failure returns false and sets `error` to a short reason.
bool read_build_id(const std::wstring& path, BuildId& out, std::string& error);

std::string describe_build_id(const BuildId& id);

// A build is qualified only when every field matches an entry recorded from
// in-engine evidence. The table is empty: no build has been qualified yet.
struct QualifiedBuild {
    uint16_t file_version[4];
    uint32_t pe_timestamp;
    uint32_t size_of_image;
    uint64_t file_size;
    const char* sha256;
    const char* evidence;  // where the in-engine evidence is recorded
};

const QualifiedBuild* find_qualified_build(const BuildId& id);
