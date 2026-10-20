// Game link (see kagrenac_er.h). The control package's mailbox event publishes its state in
// 96 event flags of the game's own save data, 1042369800-1042369895 (layout in
// ports/elden-ring/control/kagrenac_control.js.in). This
// thread finds that window in this process's own committed private read-write memory by its
// beacon, verifies it is live, and then only reads it, apart from the one command byte the
// script reserves for the DLL. It calls no game code, installs no hook and uses no address
// from a symbol table; every access is ReadProcessMemory or WriteProcessMemory on this process,
// so a freed or protected page is a failed call, never a fault.
//
// Locks: Context::mutex before Bridge::mutex, never the reverse. No call to log(), note(),
// isCurrent() or context() is made while Bridge::mutex is held, and no wait here blocks the UI
// or the network worker for longer than one short system call.
#include "kagrenac_er.h"

#include <bcrypt.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <cwctype>

namespace kagrenac_er {
namespace {

constexpr size_t kWindow = 12;          // flags 1042369800-895, byte n = flags 8n to 8n+7
// Constant bytes in flag order (flag 8n+k is bit k); memory may hold either bit order.
constexpr uint8_t kBeacon0 = 0xE5, kBeacon1 = 0x96, kGuard6 = 0x8B, kGuard8 = 0x5C;
constexpr const char* kMapName = "m60_42_36_00";
constexpr const char* kHostile = "1042360215";
constexpr ULONGLONG kFreshMs = 4000;    // the mailbox steps every 0.5 s plus up to 1 s of waiting
constexpr ULONGLONG kAnswerMs = 2500;   // a command byte not cleared by then ends the session
constexpr ULONGLONG kPollMs = 200;
constexpr ULONGLONG kVerifyMs = 8000;
constexpr size_t kChunk = size_t(4) << 20;
constexpr uint64_t kScanByteCap = uint64_t(16) << 30;
constexpr ULONGLONG kScanTimeCapMs = 120000;
#ifndef KAGRENAC_ER_TEST_HOST
// docs/engine-packs/elden-ring.md, "Engine and version": the only build this link accepts.
constexpr const char* kExeSha256 = "1a3547101327f65d0c76da2f9190ac0aa66871ea42bae2aecc61e11a8b597891";
constexpr DWORD kExeTimestamp = 0x6a96b418;
constexpr DWORD kExeSizeOfImage = 0x05e0da00;
#endif

constexpr uint8_t reverseBits(uint8_t b)
{
    b = static_cast<uint8_t>((b & 0xF0) >> 4 | (b & 0x0F) << 4);
    b = static_cast<uint8_t>((b & 0xCC) >> 2 | (b & 0x33) << 2);
    return static_cast<uint8_t>((b & 0xAA) >> 1 | (b & 0x55) << 1);
}

// A 4-bit Johnson counter in flag order: one flag changes per step. -1: not a counter state.
int johnson(int nibble)
{
    static constexpr int states[8] = {0x0, 0x1, 0x3, 0x7, 0xF, 0xE, 0xC, 0x8};
    for (int i = 0; i < 8; ++i) {
        if (states[i] == nibble) {
            return i;
        }
    }
    return -1;
}

// Byte 3: sensors. Byte 4: order state and busy (bit 7). Byte 5: acknowledgement.
// Byte 7: command, bits 0-2 nonce, 3-4 op (1 follow, 2 hold, 3 attack, 0 no-op), 5 valid.
bool bit(uint8_t b, int k) { return ((b >> k) & 1) != 0; }

// Busy (flag 39) is on while the event writes sensors or handles a command; it is set before the
// event touches the command byte and cleared only after the whole byte is clear, whatever order
// the clear writes its bits in. So, read after a zero command byte, busy off means no clear is
// still running. A separate one-byte read, so it is never read before the command byte.
bool idleAfterCommand(uintptr_t at, bool msb)
{
    uint8_t b = 0;
    SIZE_T n = 0;
    if (!ReadProcessMemory(GetCurrentProcess(), reinterpret_cast<LPCVOID>(at + 4), &b, 1, &n) || n != 1) {
        return false;
    }
    return !bit(msb ? reverseBits(b) : b, 7);
}

bool shapeOk(const uint8_t* w)
{
    return w[0] == kBeacon0 && w[1] == kBeacon1 && w[6] == kGuard6 && w[8] == kGuard8 && w[9] == 0 && w[10] == 0
        && w[11] == 0 && johnson(w[2] & 0xF) >= 0 && johnson(w[2] >> 4) >= 0 && !bit(w[5], 7) && (w[7] & 0xC0) == 0;
}

// Copies the window onto the caller's stack in flag order. Never kept on the heap, so the
// scanner cannot mistake a copy of ours for the game's.
bool readWindow(uintptr_t at, bool msb, uint8_t* w)
{
    SIZE_T n = 0;
    if (!ReadProcessMemory(GetCurrentProcess(), reinterpret_cast<LPCVOID>(at), w, kWindow, &n) || n != kWindow) {
        return false;
    }
    if (msb) {
        for (size_t i = 0; i < kWindow; ++i) {
            w[i] = reverseBits(w[i]);
        }
    }
    return true;
}

bool pageOk(uintptr_t at)
{
    MEMORY_BASIC_INFORMATION m{};
    if (!VirtualQuery(reinterpret_cast<LPCVOID>(at), &m, sizeof(m))) {
        return false;
    }
    uintptr_t end = reinterpret_cast<uintptr_t>(m.BaseAddress) + m.RegionSize;
    return m.State == MEM_COMMIT && m.Type == MEM_PRIVATE && m.Protect == PAGE_READWRITE && at + kWindow <= end;
}

struct Snapshot {
    bool companionLoaded = false, companionAlive = false, hostileLoaded = false, hostileAlive = false;
    bool within4 = false, within15 = false, hostileNear = false, inMap = false, pending = false;
    int order = 0;  // 1 follow, 3 attack, 0 or 2 hold
    ULONGLONG readTick = 0, stepTick = 0;
    FILETIME utc{};
};

struct Slot {
    uint64_t ticket = 0;
    Order order = Order::Hold;
    uint64_t generation = 0;
    uint64_t session = 0;
};

struct Entry {
    uint64_t ticket = 0;
    OrderResult result;
};

// Process-lifetime state, allocated once and never destroyed (no global destructor).
struct Bridge {
    std::mutex mutex;
    std::condition_variable cv;
    std::string status = "starting";
    uint64_t sessions = 0;  // monotonic; a session is one verified link, epoch and companion
    uint64_t session = 0;   // 0: no link
    bool armed = false;
    bool haveSnapshot = false;
    Snapshot snapshot;
    bool hasPending = false;  // one replace-only slot
    Slot pending;
    uint64_t tickets = 0;
    std::array<Entry, 8> results{};
};

Bridge& bridge()
{
    static Bridge* b = new Bridge();
    return *b;
}

// Bridge::mutex held.
void setResult(Bridge& b, uint64_t ticket, OrderResult::Kind kind, const char* reason)
{
    Entry& e = b.results[ticket % b.results.size()];
    if (ticket && e.ticket == ticket && e.result.kind == OrderResult::Pending) {
        e.result.kind = kind;
        e.result.reason = reason;
    }
}

// Bridge::mutex held. Ends the session: no captured order or session id is valid afterwards.
void endSession(Bridge& b, bool linked, const char* reason)
{
    if (b.hasPending) {
        setResult(b, b.pending.ticket, OrderResult::Failed, reason);
        b.hasPending = false;
    }
    b.session = linked ? ++b.sessions : 0;
    b.armed = false;
    if (!linked) {
        b.haveSnapshot = false;
    }
}

bool fresh(const Snapshot& s, ULONGLONG now)
{
    return now - s.readTick <= kFreshMs && now - s.stepTick <= kFreshMs;
}

// Why the game would refuse this order now (nullptr: it may accept).
const char* precondition(Order order, bool companionReady, bool hostileReady)
{
    if (!companionReady) {
        return "the companion is not loaded and alive";
    }
    if (order == Order::Attack && !hostileReady) {
        return "the configured hostile is not loaded, alive and near";
    }
    return nullptr;
}

bool companionReady(const uint8_t* w) { return bit(w[3], 0) && bit(w[3], 1); }
bool hostileReady(const uint8_t* w) { return bit(w[3], 2) && bit(w[3], 3) && bit(w[3], 6); }

#ifndef KAGRENAC_ER_TEST_HOST
bool sha256File(const std::filesystem::path& file, std::string& hex)
{
    HANDLE h = CreateFileW(file.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
                           OPEN_EXISTING, FILE_FLAG_SEQUENTIAL_SCAN, nullptr);
    if (h == INVALID_HANDLE_VALUE) {
        return false;
    }
    BCRYPT_ALG_HANDLE alg = nullptr;
    BCRYPT_HASH_HANDLE hash = nullptr;
    bool ok = BCryptOpenAlgorithmProvider(&alg, BCRYPT_SHA256_ALGORITHM, nullptr, 0) == 0
        && BCryptCreateHash(alg, &hash, nullptr, 0, nullptr, 0, 0) == 0;
    std::vector<unsigned char> buffer(ok ? 1 << 20 : 0);
    for (DWORD read = 1; ok && read;) {
        ok = ReadFile(h, buffer.data(), static_cast<DWORD>(buffer.size()), &read, nullptr)
            && BCryptHashData(hash, buffer.data(), read, 0) == 0;
    }
    unsigned char digest[32] = {};
    ok = ok && BCryptFinishHash(hash, digest, sizeof(digest), 0) == 0;
    if (hash) BCryptDestroyHash(hash);
    if (alg) BCryptCloseAlgorithmProvider(alg, 0);
    CloseHandle(h);
    char text[65] = {};
    for (int i = 0; ok && i < 32; ++i) {
        std::snprintf(text + i * 2, 3, "%02x", digest[i]);
    }
    hex = text;
    return ok;
}
#endif

// The exact executable the engine pack recorded, by file hash and by the loaded PE headers.
bool buildGate(std::string& why)
{
#ifdef KAGRENAC_ER_TEST_HOST
    why = "test host: build gate skipped";
    return true;
#else
    std::string hex;
    if (!sha256File(modulePath(nullptr), hex) || hex != kExeSha256) {
        why = "the game executable is not the recorded build";
        return false;
    }
    auto base = reinterpret_cast<const unsigned char*>(GetModuleHandleW(nullptr));
    IMAGE_DOS_HEADER dos{};
    IMAGE_NT_HEADERS64 nt{};
    SIZE_T n = 0;
    bool ok = ReadProcessMemory(GetCurrentProcess(), base, &dos, sizeof(dos), &n) && n == sizeof(dos)
        && dos.e_magic == IMAGE_DOS_SIGNATURE && dos.e_lfanew > 0 && dos.e_lfanew < 4096
        && ReadProcessMemory(GetCurrentProcess(), base + dos.e_lfanew, &nt, sizeof(nt), &n) && n == sizeof(nt)
        && nt.Signature == IMAGE_NT_SIGNATURE && nt.FileHeader.TimeDateStamp == kExeTimestamp
        && nt.OptionalHeader.SizeOfImage == kExeSizeOfImage;
    why = ok ? "build 2.7.1.0 by SHA-256 and PE headers" : "the loaded game image headers do not match";
    return ok;
#endif
}

// Bounded scan of committed private read-write memory, outside our module, this thread's
// stack and our scan buffer. Returns the number of candidates (the first in at/msb), -1 when
// a cap stopped it.
int scan(uint8_t* buffer, uintptr_t& at, bool& msb)
{
    ULONG_PTR stackLow = 0, stackHigh = 0;
    GetCurrentThreadStackLimits(&stackLow, &stackHigh);
    MEMORY_BASIC_INFORMATION self{};
    VirtualQuery(reinterpret_cast<LPCVOID>(&scan), &self, sizeof(self));
    constexpr uint8_t m0 = reverseBits(kBeacon0), m1 = reverseBits(kBeacon1), m6 = reverseBits(kGuard6),
                      m8 = reverseBits(kGuard8);
    ULONGLONG start = GetTickCount64();
    uint64_t scanned = 0;
    int found = 0;
    MEMORY_BASIC_INFORMATION m{};
    for (uintptr_t p = 0; VirtualQuery(reinterpret_cast<LPCVOID>(p), &m, sizeof(m)); ) {
        uintptr_t base = reinterpret_cast<uintptr_t>(m.BaseAddress), end = base + m.RegionSize;
        if (end <= p) {
            break;
        }
        p = end;
        if (m.State != MEM_COMMIT || m.Type != MEM_PRIVATE || m.Protect != PAGE_READWRITE
            || m.AllocationBase == buffer || m.AllocationBase == self.AllocationBase
            || (base < stackHigh && end > stackLow)) {
            continue;
        }
        for (uintptr_t q = base; q + kWindow <= end;) {
            if (scanned > kScanByteCap || GetTickCount64() - start > kScanTimeCapMs) {
                return -1;
            }
            size_t len = static_cast<size_t>(std::min<uintptr_t>(kChunk, end - q));
            SIZE_T n = 0;
            if (ReadProcessMemory(GetCurrentProcess(), reinterpret_cast<LPCVOID>(q), buffer, len, &n) && n == len) {
                for (size_t i = 0; i + kWindow <= len; ++i) {
                    const uint8_t* c = buffer + i;
                    bool lsb = c[0] == kBeacon0 && c[1] == kBeacon1 && c[6] == kGuard6 && c[8] == kGuard8;
                    bool rev = c[0] == m0 && c[1] == m1 && c[6] == m6 && c[8] == m8;
                    if ((lsb || rev) && c[9] == 0 && c[10] == 0 && c[11] == 0) {
                        if (found++ == 0) {
                            at = q + i;
                            msb = rev;
                        }
                    }
                }
            }
            scanned += len;
            Sleep(2);  // CPU cap: the scan yields after every chunk
            q += len == kChunk ? len - (kWindow - 1) : len;
        }
    }
    return found;
}

// Live: two consecutive heartbeat steps, with the beacon, guards and epoch unchanged and the
// sensors not mid-write at the last one.
bool verify(uintptr_t at, bool msb, int& epoch, int& heartbeat)
{
    uint8_t w[kWindow];
    if (!pageOk(at) || !readWindow(at, msb, w) || !shapeOk(w)) {
        return false;
    }
    epoch = w[2] >> 4;
    heartbeat = johnson(w[2] & 0xF);
    int steps = 0;
    ULONGLONG start = GetTickCount64(), last = start;
    while (GetTickCount64() - start < kVerifyMs) {
        Sleep(static_cast<DWORD>(kPollMs));
        if (!pageOk(at) || !readWindow(at, msb, w) || !shapeOk(w) || (w[2] >> 4) != epoch) {
            return false;
        }
        int h = johnson(w[2] & 0xF);
        if (h != heartbeat) {
            if (h != (heartbeat + 1) % 8) {
                return false;
            }
            heartbeat = h;
            last = GetTickCount64();
            ++steps;
        } else if (GetTickCount64() - last > kFreshMs) {
            return false;
        }
        if (steps >= 2 && !bit(w[4], 7)) {
            return true;
        }
    }
    return false;
}

// Worker-only state of one verified link.
struct Link {
    uintptr_t at = 0;
    bool msb = false;
    int epoch = 0;
    int heartbeat = 0;
    ULONGLONG lastStep = 0;
    bool companion = false;
    bool inFlight = false;
    bool challenge = false;
    uint64_t ticket = 0;
    int nonce = 0;
    int op = 0;
    ULONGLONG writtenAt = 0;
    ULONGLONG busySince = 0;  // 0: busy was off at the last poll
};

// writeCommand's answer when the event is busy: nothing written, try again at the next poll.
constexpr const char* kBusy = "the mailbox is busy";

// Writes the command byte once, only while it is zero, busy is off and the window still checks
// out. Returns nullptr on success, kBusy to retry later, else why nothing was written.
const char* writeCommand(Link& link, int op, Order order)
{
    uint8_t w[kWindow];
    if (!pageOk(link.at) || !readWindow(link.at, link.msb, w) || !shapeOk(w) || (w[2] >> 4) != link.epoch) {
        return "the mailbox changed";
    }
    if (GetTickCount64() - link.lastStep > kFreshMs) {
        return "the mailbox is not fresh";
    }
    if (bit(w[4], 7)) {
        return kBusy;
    }
    if (w[7] != 0) {
        return "the command byte is busy";
    }
    if (op != 0) {
        if (const char* why = precondition(order, companionReady(w), hostileReady(w))) {
            return why;
        }
    }
    int nonce = (link.nonce + 1) & 7;
    if (nonce == (w[5] & 7)) {
        nonce = (nonce + 1) & 7;  // never the nonce the last answer echoes
    }
    uint8_t command = static_cast<uint8_t>(nonce | op << 3 | 0x20);
    uint8_t raw = link.msb ? reverseBits(command) : command;
    // Last look, the command byte and then busy, right before the write.
    if (!readWindow(link.at, link.msb, w) || w[7] != 0 || !idleAfterCommand(link.at, link.msb)) {
        return kBusy;
    }
    SIZE_T n = 0;
    if (!WriteProcessMemory(GetCurrentProcess(), reinterpret_cast<LPVOID>(link.at + 7), &raw, 1, &n) || n != 1) {
        return "the write failed";
    }
    link.nonce = nonce;
    link.op = op;
    link.inFlight = true;
    link.writtenAt = GetTickCount64();
    return nullptr;
}

// Sends the pending order, if any. Context::mutex then Bridge::mutex, so a generation change
// either happens before the check or after the write. False: the link must end.
bool dispatch(Link& link)
{
    Bridge& b = bridge();
    Context& ctx = context();
    Slot s;
    const char* failed = nullptr;
    {
        std::lock_guard<std::mutex> lock(ctx.mutex);
        std::lock_guard<std::mutex> bridgeLock(b.mutex);
        if (!b.hasPending || !b.armed) {
            return true;
        }
        s = b.pending;
        b.hasPending = false;
        if (s.generation && ctx.generation != s.generation) {
            failed = "superseded by a newer line before it was sent";
        } else if (s.session != b.session) {
            failed = "the game session changed before it was sent";
        } else {
            failed = writeCommand(link, static_cast<int>(s.order), s.order);
            if (failed == kBusy) {
                b.hasPending = true;  // still this order (the lock was held): sent at a later poll
                return true;
            }
        }
        if (failed) {
            setResult(b, s.ticket, OrderResult::Failed, failed);
        } else {
            link.ticket = s.ticket;
            link.challenge = false;
        }
    }
    b.cv.notify_all();
    log("bridge: ticket " + std::to_string(s.ticket) + " " + kActionNames[static_cast<int>(s.order) - 1] + ": "
        + (failed ? std::string("not sent (") + failed + ")" : "sent, nonce " + std::to_string(link.nonce)));
    return !failed || std::strcmp(failed, "the write failed") != 0;
}

// The verified link's loop. Returns why it ended.
const char* runLink(uintptr_t at, bool msb, int epoch, int heartbeat)
{
    Bridge& b = bridge();
    Link link;
    link.at = at;
    link.msb = msb;
    link.epoch = epoch;
    link.heartbeat = heartbeat;
    link.lastStep = GetTickCount64();
    uint64_t session = 0;
    {
        std::lock_guard<std::mutex> lock(b.mutex);
        endSession(b, true, "a new game link started");
        session = b.session;
        b.status = "verified, arming";
    }
    log("bridge: mailbox verified (" + std::string(msb ? "high" : "low") + " bit first), session "
        + std::to_string(session));
    for (;;) {
        {
            std::unique_lock<std::mutex> lock(b.mutex);
            b.cv.wait_for(lock, std::chrono::milliseconds(kPollMs));
        }
        uint8_t w[kWindow];
        if (!pageOk(at) || !readWindow(at, msb, w)) {
            return "the mailbox can no longer be read";
        }
        if (!shapeOk(w)) {
            return "the mailbox layout changed";
        }
        ULONGLONG now = GetTickCount64();
        if ((w[2] >> 4) != link.epoch) {
            // A load or rest: the init event cleared command, answer and arming.
            link.epoch = w[2] >> 4;
            link.inFlight = false;
            link.challenge = false;
            {
                std::lock_guard<std::mutex> lock(b.mutex);
                if (link.ticket) {
                    setResult(b, link.ticket, OrderResult::Failed, "the game reloaded before it answered");
                }
                endSession(b, true, "the game reloaded");
                session = b.session;
                b.status = "verified, arming";
            }
            link.ticket = 0;
            b.cv.notify_all();
            log("bridge: load epoch changed; session " + std::to_string(session));
        }
        int h = johnson(w[2] & 0xF);
        if (h != link.heartbeat) {
            link.heartbeat = h;
            link.lastStep = now;
        }
        if (now - link.lastStep > kFreshMs) {
            return "the mailbox heartbeat stopped";
        }
        // The event is busy for one pass's sensors or one command, never for seconds.
        bool busy = bit(w[4], 7);
        if (!busy) {
            link.busySince = 0;
        } else if (!link.busySince) {
            link.busySince = now;
        } else if (now - link.busySince > kFreshMs) {
            if (link.ticket) {
                std::lock_guard<std::mutex> lock(b.mutex);
                setResult(b, link.ticket, OrderResult::Failed, "the game did not finish answering");
            }
            return "the mailbox stayed busy";
        }
        if (!busy) {
            Snapshot s;
            s.companionLoaded = bit(w[3], 0);
            s.companionAlive = bit(w[3], 1);
            s.hostileLoaded = bit(w[3], 2);
            s.hostileAlive = bit(w[3], 3);
            s.within4 = bit(w[3], 4);
            s.within15 = bit(w[3], 5);
            s.hostileNear = bit(w[3], 6);
            s.inMap = bit(w[3], 7);
            s.order = w[4] & 3;
            s.pending = bit(w[4], 4);
            s.readTick = now;
            s.stepTick = link.lastStep;
            GetSystemTimeAsFileTime(&s.utc);
            bool present = s.companionLoaded && s.companionAlive;
            bool lost = link.companion && !present;
            link.companion = present;
            {
                std::lock_guard<std::mutex> lock(b.mutex);
                b.snapshot = s;
                b.haveSnapshot = true;
                if (lost) {
                    bool armed = b.armed;
                    endSession(b, true, "the companion unloaded or died");
                    b.armed = armed;  // arming is per load, the session is per companion
                    session = b.session;
                }
            }
            if (lost) {
                log("bridge: companion lost; session " + std::to_string(session));
            }
        }
        if (link.inFlight) {
            // Answered: the command byte zero and then, read after it, busy off.
            if (w[7] != 0 || busy || !idleAfterCommand(at, msb)) {
                if (now - link.writtenAt <= kAnswerMs) {
                    continue;
                }
                std::lock_guard<std::mutex> lock(b.mutex);
                setResult(b, link.ticket, OrderResult::Failed, "written but the game did not answer; outcome unconfirmed, the game may still act");
                return "the game did not answer a command";
            }
            // Busy off is the event's last write for a command; read the answer after seeing it.
            if (!readWindow(at, msb, w)) {
                return "the mailbox can no longer be read";
            }
            link.inFlight = false;
            bool accepted = bit(w[5], 5), refused = bit(w[5], 6);
            bool matched = (w[5] & 7) == link.nonce && ((w[5] >> 3) & 3) == link.op && accepted != refused;
            {
                std::lock_guard<std::mutex> lock(b.mutex);
                if (!matched) {
                    setResult(b, link.ticket, OrderResult::Failed, "the game's answer did not match");
                } else if (link.challenge) {
                    b.armed = accepted && bit(w[4], 3);
                    b.status = b.armed ? "verified and armed" : "arming refused";
                } else {
                    setResult(b, link.ticket, accepted ? OrderResult::Accepted : OrderResult::Refused,
                              accepted ? "the game event accepted it; that is not yet movement"
                                       : "the game event refused it");
                }
            }
            b.cv.notify_all();
            if (!matched) {
                return "an answer did not match its command";
            }
            if (link.challenge) {
                link.challenge = false;
                if (!accepted || !bit(w[4], 3)) {
                    return "the arming challenge was refused";
                }
                log("bridge: armed, session " + std::to_string(session));
                note(L"Game link ready: " + toWide(context().npcName) + L" can ask the game to follow, hold or attack.");
            } else {
                log("bridge: ticket " + std::to_string(link.ticket) + (accepted ? " accepted" : " refused"));
            }
            link.ticket = 0;
            continue;
        }
        if (w[7] != 0) {
            return "the command byte changed without a command of ours";
        }
        if (busy) {
            continue;  // no challenge or order while the event is busy
        }
        bool armed = false;
        {
            std::lock_guard<std::mutex> lock(b.mutex);
            armed = b.armed;
        }
        if (!armed) {
            if (const char* why = writeCommand(link, 0, Order::Hold)) {
                if (why != kBusy) {
                    log(std::string("bridge: arming challenge not sent (") + why + ")");
                }
                if (std::strcmp(why, "the write failed") == 0) {
                    return why;
                }
            } else {
                link.challenge = true;
            }
        } else if (!dispatch(link)) {
            return "the write failed";
        }
    }
}

void dropLink(const char* why)
{
    Bridge& b = bridge();
    {
        std::lock_guard<std::mutex> lock(b.mutex);
        for (Entry& e : b.results) {
            setResult(b, e.ticket, OrderResult::Failed, "the game link was lost");
        }
        endSession(b, false, "the game link was lost");
        b.status = why;
    }
    b.cv.notify_all();
}

void bridgeMain()
{
    std::string why;
    if (!buildGate(why)) {
        dropLink("unsupported game build");
        log("bridge: off, " + why);
        return;
    }
    log("bridge: " + why);
    auto* buffer = static_cast<uint8_t*>(VirtualAlloc(nullptr, kChunk, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE));
    if (!buffer) {
        dropLink("no memory for the scan");
        return;
    }
    DWORD backoff = 2000;
    for (;;) {
        uintptr_t at = 0;
        bool msb = false;
        int epoch = 0, heartbeat = 0;
        ULONGLONG start = GetTickCount64();
        int found = scan(buffer, at, msb);
        const char* reason = found < 0 ? "the scan hit its cap"
            : found == 0               ? "no mailbox found (no save loaded, or no control package)"
            : found > 1                ? "several mailbox candidates; none trusted"
                                       : nullptr;
        if (!reason && !verify(at, msb, epoch, heartbeat)) {
            reason = "the mailbox candidate is not live";
        }
        log("bridge: scan " + std::to_string(GetTickCount64() - start) + " ms, " + std::to_string(found)
            + " candidates" + (reason ? std::string("; ") + reason : ""));
        if (!reason) {
            backoff = 2000;
            reason = runLink(at, msb, epoch, heartbeat);
            log(std::string("bridge: link ended, ") + reason);
            note(L"Game link lost: " + toWide(context().npcName) + L" cannot act until it is found again.");
        }
        dropLink(reason);
        Sleep(backoff);
        backoff = std::min<DWORD>(backoff * 2, 60000);
    }
}

std::string clip(std::string text)
{
    if (text.size() > 200) {
        text.resize(200);
    }
    return text;
}

}  // namespace

void runBridgeThread()
{
    for (;;) {
        try {
            bridgeMain();
            return;
        } catch (...) {
            // Fail closed: no link, every order still open fails; try again much later.
            try {
                dropLink("internal error");
                log("bridge: internal error; link off");
            } catch (...) {
                OutputDebugStringA("kagrenac_er: bridge internal error; not logged\n");
            }
            Sleep(30000);
        }
    }
}

uint64_t describeGame(GameContext& game, const std::vector<std::string>& allowed)
{
    Bridge& b = bridge();
    Snapshot s;
    bool have = false, armed = false;
    uint64_t session = 0;
    std::string status;
    {
        std::lock_guard<std::mutex> lock(b.mutex);
        s = b.snapshot;
        have = b.haveSnapshot && b.session != 0;
        armed = b.armed;
        session = b.session;
        status = b.status;
    }
    ULONGLONG now = GetTickCount64();
    game.offerActions = true;
    game.offeredActions.clear();
    game.details.clear();
    game.details["game"] = "Elden Ring (offline)";
    game.details["inventory"] = "unavailable";
    game.details["combat"] = "unavailable";
    if (!have || !fresh(s, now)) {
        game.details["location"] = "unavailable";
        game.details["nearby_actors"] = "unavailable";
        game.details["companion_state"] = "unavailable";
        game.details["observation_source"] = clip("none: the game link is not verified and fresh (" + status + ")");
        game.details["actions"] = "none: no verified game link; the companion cannot act in the game";
        return 0;
    }
    char age[96];
    std::snprintf(age, sizeof(age), "read %.1f s ago, heartbeat %.1f s ago", (now - s.readTick) / 1000.0,
                  (now - s.stepTick) / 1000.0);
    SYSTEMTIME utc{};
    FileTimeToSystemTime(&s.utc, &utc);
    char stamp[32];
    std::snprintf(stamp, sizeof(stamp), "%04u-%02u-%02uT%02u:%02u:%02uZ", utc.wYear, utc.wMonth, utc.wDay, utc.wHour,
                  utc.wMinute, utc.wSecond);
    bool present = s.companionLoaded && s.companionAlive;
    bool hostile = s.hostileLoaded && s.hostileAlive;
    const char* order = s.order == 1 ? "follow" : s.order == 3 ? "attack" : "hold";
    game.details["location"] = s.inMap
        ? std::string("The First Step area (player in map tile ") + kMapName + ")"
        : std::string("unavailable (player not in map tile ") + kMapName + ")";
    game.details["nearby_actors"] = clip(std::string("unavailable except the configured hostile, a Man-Bat (entity ")
        + kHostile + "): " + (hostile ? "loaded and alive" : "not loaded and alive")
        + (s.hostileNear ? ", within 30 m of the player" : ", not within 30 m of the player"));
    game.details["companion_state"] = present
        ? clip(std::string("loaded, alive; player ") + (s.within4 ? "within 4 m" : s.within15 ? "within 15 m" : "over 15 m away")
               + "; current order " + order + (s.pending ? "; an order is pending" : ""))
        : "not loaded and alive";
    game.details["observation_source"] = clip(std::string("the companion mailbox event flags (1042369800-895), ") + age);
    game.details["snapshot_utc"] = stamp;
    if (armed && present) {
        for (int i = 0; i < 3; ++i) {
            bool ready = i < 2 || (hostile && s.hostileNear);
            if (ready && std::find(allowed.begin(), allowed.end(), kActionNames[i]) != allowed.end()) {
                game.offeredActions.push_back(kActionNames[i]);
            }
        }
    }
    game.details["actions"] = game.offeredActions.empty()
        ? std::string("none right now: ") + (armed ? "the companion or the hostile is not ready" : "the game link is not armed")
        : "requests only: the game event accepts or refuses, and acceptance is not movement";
    return session;
}

bool requestOrder(Order order, uint64_t generation, uint64_t session, uint64_t& ticket, std::string& why)
{
    Bridge& b = bridge();
    {
        std::lock_guard<std::mutex> lock(b.mutex);
        ULONGLONG now = GetTickCount64();
        const Snapshot& s = b.snapshot;
        if (!b.session || !b.armed || !b.haveSnapshot || !fresh(s, now)) {
            why = "the game link is not verified, armed and fresh";
        } else if (session && session != b.session) {
            why = "the game session changed since this line was described";
        } else if (const char* refused = precondition(order, s.companionLoaded && s.companionAlive,
                                                      s.hostileLoaded && s.hostileAlive && s.hostileNear)) {
            why = refused;
        } else {
            if (b.hasPending) {
                setResult(b, b.pending.ticket, OrderResult::Failed, "replaced by a newer order before it was sent");
            }
            ticket = ++b.tickets;
            b.pending = {ticket, order, generation, b.session};
            b.hasPending = true;
            Entry& e = b.results[ticket % b.results.size()];
            e.ticket = ticket;
            e.result = OrderResult{};
            why.clear();
        }
    }
    if (!why.empty()) {
        return false;
    }
    b.cv.notify_all();
    return true;
}

OrderResult orderResult(uint64_t ticket, DWORD waitMs)
{
    Bridge& b = bridge();
    std::unique_lock<std::mutex> lock(b.mutex);
    const Entry& e = b.results[ticket % b.results.size()];
    b.cv.wait_for(lock, std::chrono::milliseconds(waitMs),
                  [&] { return e.ticket != ticket || e.result.kind != OrderResult::Pending; });
    if (e.ticket != ticket) {
        return {OrderResult::Failed, "unknown or expired order"};
    }
    return e.result;
}

void cancelOrders()
{
    Bridge& b = bridge();
    uint64_t hold = 0;
    {
        std::lock_guard<std::mutex> lock(b.mutex);
        if (b.hasPending) {
            setResult(b, b.pending.ticket, OrderResult::Failed, "cancelled");
            b.hasPending = false;
        }
        if (b.session && b.armed && b.haveSnapshot && fresh(b.snapshot, GetTickCount64())) {
            hold = ++b.tickets;
            b.pending = {hold, Order::Hold, 0, b.session};
            b.hasPending = true;
            Entry& e = b.results[hold % b.results.size()];
            e.ticket = hold;
            e.result = OrderResult{};
        }
    }
    b.cv.notify_all();
    log(hold ? "bridge: cancelled; safe hold queued as ticket " + std::to_string(hold)
             : std::string("bridge: cancelled; no verified link for a safe hold"));
}

bool exactCommand(const std::wstring& line, Order& order)
{
    size_t first = line.find_first_not_of(L" \t\r\n");
    size_t last = line.find_last_not_of(L" \t\r\n");
    if (first == std::wstring::npos || last - first > 8) {
        return false;
    }
    std::wstring word = line.substr(first, last - first + 1);
    for (wchar_t& c : word) {
        c = static_cast<wchar_t>(std::towlower(c));
    }
    if (word == L"/follow") {
        order = Order::Follow;
    } else if (word == L"/hold") {
        order = Order::Hold;
    } else if (word == L"/attack") {
        order = Order::Attack;
    } else {
        return false;
    }
    return true;
}

}  // namespace kagrenac_er
