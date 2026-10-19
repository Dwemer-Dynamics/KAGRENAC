// Offline, read-only build identity check: prints the identity the probe DLL uses
// and whether that build is qualified. It does not launch or modify the game.
#include "build_id.h"

#include <cstdio>
#include <string>

int wmain(int argc, wchar_t** argv) {
    if (argc != 2) {
        std::fprintf(stderr, "usage: kagrenac_er_inspect <path to eldenring.exe>\n");
        return 2;
    }
    BuildId id;
    std::string error;
    if (!read_build_id(argv[1], id, error)) {
        std::fprintf(stderr, "error: %s\n", error.c_str());
        return 1;
    }
    std::printf("%s\n", describe_build_id(id).c_str());
    const QualifiedBuild* q = find_qualified_build(id);
    std::printf("qualified: %s\n", q ? q->evidence : "no (fail closed)");
    return q ? 0 : 3;
}
