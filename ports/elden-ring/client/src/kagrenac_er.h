#pragma once
// Kagrenac Elden Ring native client: shared state of the DLL's four threads (UI, network worker,
// cancel, game link). One heap Context lives for the whole process and is never destroyed: the
// DLL is pinned and never unloads, so no cleanup runs under the loader lock (see README, Lifetime).

#include <windows.h>

#include <condition_variable>
#include <cstdint>
#include <filesystem>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "ai_client.h"

namespace kagrenac_er {

// Used when config.json has no npc_id or npc_name (protocol npc.id and npc.name).
constexpr const char* kDefaultNpcId = "companion";
constexpr const char* kDefaultNpcName = "Companion";
constexpr int kMaxPhaseSeconds = 20;                     // per WinHTTP phase
#ifdef KAGRENAC_ER_TEST_HOST
constexpr UINT kLineBudgetMs = 8000;  // test variant only, so the harness reaches the watchdog
#else
constexpr UINT kLineBudgetMs = 45000;  // UI watchdog per line
#endif
constexpr size_t kMaxWavBytes = 20'000'000;              // same cap as ai_client.cpp
constexpr int kMaxInputChars = 500;                      // protocol allows 1000 characters

// Posted from the network worker to the UI thread's message window.
constexpr UINT kMsgOutcome = WM_APP + 1;
#ifdef KAGRENAC_ER_TEST_HOST
constexpr UINT kMsgTestShow = WM_APP + 2;
#endif
// A short game-link line (heap std::wstring) for the box, from the worker or the bridge thread.
constexpr UINT kMsgNote = WM_APP + 3;

// What the network worker found for one line. Text and voice arrive as separate outcomes; an
// exact command ("/follow") gets one Order outcome instead (ok: the game event accepted it).
struct Outcome {
    enum Kind { Text, Voice, Order } kind = Text;
    uint64_t generation = 0;
    bool ok = false;
    std::string error;  // shown to the player, never logged
    std::string reply;  // Order: what happened to the order
    std::string wav;    // validated WAV bytes when a voice outcome is ok
};

struct Context {
    std::filesystem::path runtimeDir;
    std::filesystem::path voiceDir;
    std::string notConnected;  // non-empty: why no request is sent
    bool voiceEnabled = false;
    std::vector<std::string> allowedActions;  // config.json allowlist, the three action names only; set
                                              // once before the threads start, read-only afterwards
    std::string npcId = kDefaultNpcId;        // config.json identity, validated; same lifetime rule
    std::string npcName = kDefaultNpcName;
    std::unique_ptr<AiClient> turnClient;    // network worker only
    std::unique_ptr<AiClient> cancelClient;  // cancel thread only

    std::mutex logMutex;
    HANDLE logFile = INVALID_HANDLE_VALUE;
    ULONGLONG startTick = 0;

    // Everything below is guarded by mutex. Only the UI thread changes generation.
    std::mutex mutex;
    std::condition_variable workCv;
    std::condition_variable cancelCv;
    uint64_t generation = 0;
    bool hasPending = false;  // one replace-only slot, never a queue
    uint64_t pendingGeneration = 0;
    std::string pendingText;
    int pendingOrder = 0;  // 1-3: an exact command (Order), sent to the game link, not the model
    bool turnInFlight = false;
    bool cancelRequested = false;
    bool cancelRunning = false;
    HWND messageWindow = nullptr;  // the UI thread's message-only window
};

// The process-lifetime context, created once by the initializer.
Context& context();

// One log line: ids, timings and status only, never text, replies, names, tokens or keys.
void log(const std::string& line);
// A loggable summary of an AiClient error: its HTTP status or WinHTTP code, no text.
std::string errorCode(const std::string& error);

std::string toUtf8(const std::wstring& text);
std::wstring toWide(const std::string& text);

// UI thread side of the request state (kagrenac_er_dll.cpp). Both return the new generation.
// order: 0 for a line for the model, 1-3 (Order) for an exact command.
uint64_t submitLine(const std::string& text, int order, bool& waitsForOlder);
// Also drops any game order not yet sent and, with a verified link, asks the companion to hold.
uint64_t invalidate(const char* reason);
bool isCurrent(uint64_t generation);

// The UI thread's entry point (kagrenac_er_ui.cpp).
void runUiThread();

// Path of a loaded module (nullptr: the host executable); empty on failure.
std::filesystem::path modulePath(HMODULE module);
// Shows one game-link line in the box (any thread; dropped if the UI is not up).
void note(const std::wstring& text);

// Game link (kagrenac_er_bridge.cpp): the control package's mailbox event in the game's own event
// flags, found and verified by the bridge thread. Orders are requests the game event accepts or
// refuses; neither means the companion moved.
enum class Order { Follow = 1, Hold = 2, Attack = 3 };
constexpr const char* kActionNames[] = {"follow_player", "hold_position", "attack_hostile"};  // Order 1-3

struct OrderResult {
    enum Kind { Pending, Accepted, Refused, Failed } kind = Pending;
    std::string reason;  // short, no player text
};

// The bridge thread's entry point; runs for the process lifetime.
void runBridgeThread();
// Fills game.details (at most 9 entries) and game.offeredActions from the latest fresh snapshot,
// limited to the names in allowed; returns the bridge session the snapshot belongs to (0: none).
uint64_t describeGame(GameContext& game, const std::vector<std::string>& allowed);
// Queues one order (replace-only). generation: the line it came from, re-checked with
// isCurrent() just before it is written (0: not tied to a line). session: from describeGame
// (0: the current one). False with why when the link cannot take it now.
bool requestOrder(Order order, uint64_t generation, uint64_t session, uint64_t& ticket, std::string& why);
// Waits up to waitMs for that order's result; Pending if none yet.
OrderResult orderResult(uint64_t ticket, DWORD waitMs);
// Esc: drops an order not yet written and, with a verified link, asks the game to hold.
void cancelOrders();
// Exact typed commands that skip the model: "/follow", "/hold", "/attack".
bool exactCommand(const std::wstring& line, Order& order);

}  // namespace kagrenac_er
