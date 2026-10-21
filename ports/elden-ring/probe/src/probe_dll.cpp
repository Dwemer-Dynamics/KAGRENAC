// KAGRENAC Elden Ring diagnostic probe (x64 DLL). Loaded as an me3 native with
// `initializer = { function = "kagrenac_probe_init" }`. At me3 v0.13.0 that symbol runs
// on a thread me3 spawns after the game's main function has started; it is not a
// verified game thread.
//
// What it reads: the host executable file on disk (version resource, PE headers,
// SHA-256) and the PE headers of the host image loaded in this process. Nothing else:
// no actor or game-state access, no memory writes, no hooks, no threads, no hotkeys, no
// per-frame work, no network. It writes one diagnostic log next to the DLL, falling back
// to OutputDebugString when that log cannot be written.
//
// Hold, follow and attack are not implemented: no qualified game-thread, actor or action
// backend is integrated (see docs/engine-packs/elden-ring.md), so each is logged as
// unsupported.
#include "build_id.h"

#include <windows.h>

#include <atomic>
#include <cstdio>
#include <string>

namespace {

HMODULE g_self = nullptr;
std::atomic<bool> g_initialized{false};

std::wstring module_path(HMODULE module) {
    std::wstring path(MAX_PATH, L'\0');
    for (;;) {
        DWORD n = GetModuleFileNameW(module, path.data(), static_cast<DWORD>(path.size()));
        if (n == 0) return {};
        if (n < path.size()) {
            path.resize(n);
            return path;
        }
        if (path.size() >= 32768) return {};
        path.resize(path.size() * 2);
    }
}

std::wstring file_name(const std::wstring& path) {
    size_t slash = path.find_last_of(L"\\/");
    return slash == std::wstring::npos ? path : path.substr(slash + 1);
}

// The log file next to the DLL. If it cannot be opened or written, one bounded
// OutputDebugString message says so, and further lines are dropped.
class Log {
public:
    explicit Log(const std::wstring& dll_path) {
        std::wstring path = dll_path;
        size_t slash = path.find_last_of(L"\\/");
        path = (slash == std::wstring::npos ? L"" : path.substr(0, slash + 1)) +
               L"kagrenac_er_probe.log";
        file_ = CreateFileW(path.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr, CREATE_ALWAYS,
                            FILE_ATTRIBUTE_NORMAL, nullptr);
        if (file_ == INVALID_HANDLE_VALUE) {
            fail("cannot open kagrenac_er_probe.log", GetLastError());
        }
    }
    ~Log() {
        if (file_ != INVALID_HANDLE_VALUE) CloseHandle(file_);
    }
    void line(const std::string& text) {
        if (file_ == INVALID_HANDLE_VALUE) return;
        std::string out = text + "\r\n";
        DWORD written = 0;
        if (!WriteFile(file_, out.data(), static_cast<DWORD>(out.size()), &written, nullptr) ||
            written != out.size()) {
            DWORD code = GetLastError();
            CloseHandle(file_);
            file_ = INVALID_HANDLE_VALUE;
            fail("cannot write kagrenac_er_probe.log", code);
        }
    }

private:
    static void fail(const char* what, DWORD code) {
        char text[128];
        std::snprintf(text, sizeof(text), "kagrenac_er_probe: %s (error %lu); log disabled\n",
                      what, code);
        OutputDebugStringA(text);
    }

    HANDLE file_ = INVALID_HANDLE_VALUE;
};

std::string narrow(const std::wstring& text) {
    if (text.empty()) return {};
    int n = WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr,
                                0, nullptr, nullptr);
    std::string out(static_cast<size_t>(n), '\0');
    WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), n,
                        nullptr, nullptr);
    return out;
}

// Header identity only: the loaded host image's PE TimeDateStamp and SizeOfImage equal
// those of the file on disk. It reads this process's own PE headers and says nothing
// about code or data in memory, which loaders, protection and other mods may patch.
bool loaded_pe_headers_match_file(const BuildId& id) {
    auto base = reinterpret_cast<const unsigned char*>(GetModuleHandleW(nullptr));
    if (!base) return false;
    auto dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
    if (dos->e_magic != IMAGE_DOS_SIGNATURE || dos->e_lfanew <= 0 || dos->e_lfanew > 4096) {
        return false;
    }
    auto nt = reinterpret_cast<const IMAGE_NT_HEADERS64*>(base + dos->e_lfanew);
    return nt->Signature == IMAGE_NT_SIGNATURE &&
           nt->FileHeader.Machine == IMAGE_FILE_MACHINE_AMD64 &&
           nt->FileHeader.TimeDateStamp == id.pe_timestamp &&
           nt->OptionalHeader.SizeOfImage == id.size_of_image;
}

void log_actions_unsupported(Log& log) {
    for (const char* action : {"hold", "follow", "attack"}) {
        log.line(std::string("action ") + action +
                 ": unsupported (no qualified game-thread/actor/action backend integrated; "
                 "nothing sent to the game)");
    }
}

bool run_probe() {
    Log log(module_path(g_self));
    log.line("kagrenac_er_probe diagnostics (no game control)");

    std::wstring host = module_path(nullptr);
    log.line("host: " + narrow(file_name(host)));
    if (_wcsicmp(file_name(host).c_str(), L"eldenring.exe") != 0) {
        log.line("blocked: host is not eldenring.exe");
        log_actions_unsupported(log);
        return false;
    }

    // Hashes the whole executable (about 87 MB) once, on me3's spawned loader thread.
    BuildId id;
    std::string error;
    if (!read_build_id(host, id, error)) {
        log.line("blocked: cannot identify host build: " + error);
        log_actions_unsupported(log);
        return false;
    }
    log.line("build: " + describe_build_id(id));
    const bool headers_match = loaded_pe_headers_match_file(id);
    log.line(std::string("loaded PE header identity matches file: ") +
             (headers_match ? "yes" : "no"));

    const QualifiedBuild* qualified = headers_match ? find_qualified_build(id) : nullptr;
    log.line(qualified ? std::string("build qualified: ") + qualified->evidence
                       : "blocked: build not in the qualified table (fail closed)");
    log_actions_unsupported(log);
    return false;
}

}  // namespace

// Always returns false: me3 then logs "native failed to initialize", which is the
// expected result for this diagnostic probe. A second call does nothing.
extern "C" __declspec(dllexport) bool kagrenac_probe_init() {
    if (g_initialized.exchange(true)) return false;
    return run_probe();
}

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        g_self = module;
        DisableThreadLibraryCalls(module);
    }
    return TRUE;
}
