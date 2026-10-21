// Kagrenac Elden Ring native client (x64 DLL). Loaded by me3 as a native with
// `initializer = { function = "kagrenac_init" }`, which me3 v0.13.0 calls on a thread it
// spawns after the game's main function has started (docs/engine-packs/elden-ring.md).
//
// The initializer pins the DLL, reads the private config, starts four detached threads and
// returns: the UI thread (kagrenac_er_ui.cpp), one network worker (turn.php, speak.php,
// result.php), one cancel thread (cancel.php, its own AiClient) and the game link
// (kagrenac_er_bridge.cpp). The box
// is a mod-owned window over the game. The game link is a bounded mailbox prototype: it reads
// the control package's event flags and writes only its one command byte, so an order is a
// request the game event accepts or refuses, never confirmed movement.
#include "kagrenac_er.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <fstream>
#include <stdexcept>
#include <system_error>
#include <thread>

#include <nlohmann/json.hpp>

namespace kagrenac_er {
namespace {

HMODULE g_self = nullptr;
std::atomic<bool> g_started{false};
Context* g_context = nullptr;  // never freed: process lifetime

#ifdef KAGRENAC_ER_TEST_HOST
// Test variant only: runs in the temporary harness and refuses the game.
constexpr const wchar_t* kHostExe = L"kagrenac_er_harness.exe";
#else
constexpr const wchar_t* kHostExe = L"eldenring.exe";
#endif

// The longest wait for one order's answer: the bridge ends a link whose command byte is not
// cleared within 2.5 s, so by then the result is known.
constexpr DWORD kOrderWaitMs = 4000;

}  // namespace

std::filesystem::path modulePath(HMODULE module)
{
    std::wstring path(MAX_PATH, L'\0');
    while (path.size() <= 32768) {
        DWORD n = GetModuleFileNameW(module, path.data(), static_cast<DWORD>(path.size()));
        if (n == 0) {
            return {};
        }
        if (n < path.size()) {
            path.resize(n);
            return path;
        }
        path.resize(path.size() * 2);
    }
    return {};
}

namespace {

long long msSince(std::chrono::steady_clock::time_point start)
{
    return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - start).count();
}

// The DLL lives in <runtime>/natives/; config.json is only <runtime>/config.json, never a
// shared location another project could have written.
std::filesystem::path findConfig(const std::filesystem::path& runtimeDir)
{
    std::error_code ec;
    std::filesystem::path beside = runtimeDir / "config.json";
    if (std::filesystem::is_regular_file(beside, ec)) {
        return beside;
    }
    return {};
}

// npc_name as protocol npc.name: 1-64 characters of UTF-8, here with no control character and
// no space at either end, so the server's cleaning never changes it.
bool isValidName(const std::string& name)
{
    if (name.empty() || name.size() > 256 || name.front() == ' ' || name.back() == ' '
        || MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, name.data(), static_cast<int>(name.size()), nullptr, 0)
            <= 0) {
        return false;
    }
    size_t chars = 0;
    for (unsigned char c : name) {
        if (c < 0x20 || c == 0x7F) {
            return false;
        }
        chars += (c & 0xC0) != 0x80;
    }
    return chars <= 64;
}

// The companion's identity, the one setting the shared loader does not read: optional npc_id
// and npc_name in the same file, read once here. Returns "" or which field is bad, never its value.
std::string loadIdentity(const std::filesystem::path& path, Context& ctx)
{
    std::ifstream file(path, std::ios::binary);
    nlohmann::json json = nlohmann::json::parse(file, nullptr, false);
    if (json.is_discarded() || !json.is_object()) {
        return "config.json is not a valid JSON object";
    }
    std::string id = ctx.npcId, name = ctx.npcName;
    if (json.contains("npc_id") && (!json["npc_id"].is_string() || !isValidId(id = json["npc_id"].get<std::string>()))) {
        return "config.json npc_id is not a valid protocol id";
    }
    if (json.contains("npc_name")
        && (!json["npc_name"].is_string() || !isValidName(name = json["npc_name"].get<std::string>()))) {
        return "config.json npc_name is not 1-64 characters without control characters or edge spaces";
    }
    ctx.npcId = id;
    ctx.npcName = name;
    return "";
}

// Reads the private config with the shared client's loader, then applies this client's own rules:
// allowed_actions keeps only the three action names (absent or [] means none), at most
// kMaxPhaseSeconds per WinHTTP phase, and the optional companion identity.
void loadSettings(Context& ctx)
{
    std::filesystem::path path = findConfig(ctx.runtimeDir);
    if (path.empty()) {
        ctx.notConnected = "no config.json in the runtime folder (the parent of natives)";
        log("config: not found; not connected");
        return;
    }
    Config config;
    config.allowedActions.clear();  // the shared default allows follow_player; this client's is none
    std::string error;
    if (!loadConfigFile(path, config, error)) {
        ctx.notConnected = "config.json is not valid (" + error + ")";
        log("config: invalid; not connected");
        return;
    }
    std::vector<std::string> allowed;
    for (const std::string& name : config.allowedActions) {
        bool known = std::find(std::begin(kActionNames), std::end(kActionNames), name) != std::end(kActionNames);
        if (known && std::find(allowed.begin(), allowed.end(), name) == allowed.end()) {
            allowed.push_back(name);
        }
    }
    if (allowed.size() != config.allowedActions.size()) {
        log("config: allowed_actions had " + std::to_string(config.allowedActions.size() - allowed.size())
            + " unknown or repeated entries; ignored");
    }
    config.allowedActions = allowed;
    if (config.timeoutSeconds > kMaxPhaseSeconds) {
        config.timeoutSeconds = kMaxPhaseSeconds;
    }
    if (config.token.empty()) {
        ctx.notConnected = "config.json has no token";
        log("config: no token; not connected");
        return;
    }
    if (!isValidId(config.sessionId)) {
        ctx.notConnected = "config.json session_id is not a valid protocol id";
        log("config: invalid session_id; not connected");
        return;
    }
    std::string bad = loadIdentity(path, ctx);
    if (!bad.empty()) {
        ctx.notConnected = bad;
        log("config: invalid companion identity; not connected");
        return;
    }
    ctx.voiceEnabled = config.voiceEnabled;
    ctx.allowedActions = allowed;
    std::string names;
    for (const std::string& name : allowed) {
        names += (names.empty() ? "" : " ") + name;
    }
    log("config: loaded, timeout_seconds " + std::to_string(config.timeoutSeconds) + ", voice "
        + (config.voiceEnabled ? "on" : "off") + ", actions " + (names.empty() ? "none" : names) + ", identity "
        + (ctx.npcId == kDefaultNpcId && ctx.npcName == kDefaultNpcName ? "default" : "from config"));
    ctx.turnClient = std::make_unique<AiClient>(config);
    ctx.cancelClient = std::make_unique<AiClient>(config);
}

void post(std::unique_ptr<Outcome> outcome)
{
    HWND target = nullptr;
    {
        std::lock_guard<std::mutex> lock(context().mutex);
        target = context().messageWindow;
    }
    if (target && PostMessageW(target, kMsgOutcome, 0, reinterpret_cast<LPARAM>(outcome.get()))) {
        outcome.release();  // the UI thread owns it now
    }
}

// Reads our own WAV file back into memory, then deletes it. Only files this worker named.
bool takeWav(const std::filesystem::path& file, std::string& bytes)
{
    std::error_code ec;
    auto size = std::filesystem::file_size(file, ec);
    bool ok = !ec && size >= 44 && size <= kMaxWavBytes;
    if (ok) {
        std::ifstream in(file, std::ios::binary);
        bytes.resize(static_cast<size_t>(size));
        ok = static_cast<bool>(in.read(bytes.data(), static_cast<std::streamsize>(size)));
    }
    std::filesystem::remove(file, ec);
    return ok && bytes.compare(0, 4, "RIFF") == 0 && bytes.compare(8, 4, "WAVE") == 0;
}

// For catch blocks: never throws (not even bad_alloc), so nothing escapes a thread from here.
// The line still waits for the UI watchdog if the error outcome cannot be posted.
void reportInternalError(const char* where, uint64_t generation, bool textPosted) noexcept
{
    try {
        log(std::string(where) + " gen " + std::to_string(generation) + ": internal error; dropped");
        if (generation && isCurrent(generation)) {
            auto failed = std::make_unique<Outcome>();
            failed->kind = textPosted ? Outcome::Voice : Outcome::Text;
            failed->generation = generation;
            failed->error = "the companion client had an internal error";
            post(std::move(failed));
        }
    } catch (...) {
        OutputDebugStringA("kagrenac_er: internal error; not logged\n");
    }
}

// What happened to one order, for the box and the log. Accepted is the game event's answer;
// it never confirms that the companion moved.
std::string describeOrder(const std::string& name, const OrderResult& result)
{
    switch (result.kind) {
    case OrderResult::Accepted:
        return name + ": accepted by the game event (movement not confirmed)";
    case OrderResult::Refused:
        return name + ": refused by the game event (" + result.reason + ")";
    case OrderResult::Pending:
        return name + ": failed (no answer from the game link within " + std::to_string(kOrderWaitMs / 1000) + " s)";
    default:
        return name + ": failed (" + result.reason + ")";
    }
}

// result.php status: handled only when the game event accepted the order.
const char* reportStatus(const OrderResult& result)
{
    return result.kind == OrderResult::Accepted ? "handled"
        : result.kind == OrderResult::Refused   ? "rejected"
                                                : "failed";
}

std::string clipReason(const std::string& reason)
{
    return reason.size() > 120 ? reason.substr(0, 120) : reason;
}

// Waits for a queued order's answer. With none in time, the order must not run later unseen:
// cancelOrders() drops it if it is still queued and asks for a safe hold. An order already
// written may still have been acted on, so that case says only that its outcome is unconfirmed.
// Network worker only, never under Context::mutex (cancelOrders takes the Bridge lock).
OrderResult settleOrder(uint64_t ticket)
{
    OrderResult result = orderResult(ticket, kOrderWaitMs);
    if (result.kind != OrderResult::Pending) {
        return result;
    }
    cancelOrders();
    OrderResult after = orderResult(ticket, 0);
    std::string wait = std::to_string(kOrderWaitMs / 1000) + " s";
    if (after.kind == OrderResult::Failed && after.reason == "cancelled") {
        return {OrderResult::Failed, "no answer from the game link within " + wait + "; cancelled before it was sent"};
    }
    return {OrderResult::Failed, "outcome unconfirmed: no answer within " + wait + "; a safe hold was requested if the link allows"};
}

// An exact command typed in the box ("/follow"): no model call, no turn and so no report.
// Runs on the network worker, so the UI never waits for the game's answer.
void runCommand(uint64_t generation, Order order)
{
    std::string name = kActionNames[static_cast<int>(order) - 1];
    std::string gen = "gen " + std::to_string(generation);
    if (!isCurrent(generation)) {
        log("command " + gen + " " + name + ": superseded before sending; dropped");
        return;
    }
    uint64_t ticket = 0;
    std::string why;
    OrderResult result;
    if (requestOrder(order, generation, 0, ticket, why)) {
        result = settleOrder(ticket);
    } else {
        result = {OrderResult::Failed, "not sent: " + why};
    }
    std::string line = describeOrder(name, result);
    log("command " + gen + " " + name + ": ticket " + std::to_string(ticket) + ", " + reportStatus(result));
    note(L"Game order " + toWide(line));
    auto shown = std::make_unique<Outcome>();
    shown->kind = Outcome::Order;
    shown->generation = generation;
    shown->ok = result.kind == OrderResult::Accepted;
    shown->reply = line;
    post(std::move(shown));
}

// Checks the turn's returned actions and queues at most one order; every named action gets a
// report entry. Returns the ticket and sets queued to its report (0 and -1: nothing queued).
uint64_t queueActions(uint64_t generation, uint64_t session, const GameContext& game, const TurnResult& result,
                      std::vector<ActionReport>& reports, int& queued)
{
    Context& ctx = context();
    queued = -1;
    std::vector<size_t> valid;  // indexes into reports
    for (const TurnAction& action : result.actions) {
        if (action.name.empty()) {
            continue;  // malformed: no name the server could match in a report
        }
        const char* why = nullptr;
        if (!action.problem.empty()) {
            why = action.problem.c_str();  // the client's own fixed text, never model output
        } else if (std::find(std::begin(kActionNames), std::end(kActionNames), action.name) == std::end(kActionNames)) {
            why = "not a companion action";
        } else if (action.targetId != game.npcId) {
            why = "target is not this companion";
        } else if (std::find(game.offeredActions.begin(), game.offeredActions.end(), action.name)
                   == game.offeredActions.end()) {
            why = "not offered for this line";
        } else if (std::find(ctx.allowedActions.begin(), ctx.allowedActions.end(), action.name)
                   == ctx.allowedActions.end()) {
            why = "not in allowed_actions";
        } else {
            valid.push_back(reports.size());
        }
        reports.push_back({action.name, "rejected", why ? why : ""});
    }
    if (valid.size() > 1) {
        // Never "last one wins": conflicting orders in one reply all stay unsent.
        for (size_t i : valid) {
            reports[i].reason = "several orders in one reply; none sent";
        }
        log("turn gen " + std::to_string(generation) + ": " + std::to_string(valid.size())
            + " orders in one reply; none sent");
        note(L"Game order: the reply asked for several orders at once; none was sent.");
        return 0;
    }
    if (valid.empty()) {
        if (!reports.empty()) {
            note(L"Game order " + toWide(reports[0].name) + L": not sent (" + toWide(reports[0].reason) + L")");
        }
        return 0;
    }
    ActionReport& report = reports[valid[0]];
    auto order = static_cast<Order>(
        std::find(std::begin(kActionNames), std::end(kActionNames), report.name) - std::begin(kActionNames) + 1);
    uint64_t ticket = 0;
    std::string why;
    if (!isCurrent(generation)) {
        why = "superseded by a newer line before it was sent";
    } else if (!requestOrder(order, generation, session, ticket, why)) {
        why = "not sent: " + why;
    }
    if (!why.empty()) {
        report.status = "failed";
        report.reason = clipReason(why);
        note(L"Game order " + toWide(describeOrder(report.name, {OrderResult::Failed, why})));
        return 0;
    }
    queued = static_cast<int>(valid[0]);
    return ticket;
}

// Optional voice for a reply already shown.
void speakReply(uint64_t generation, const std::string& reply, const std::string& requestId)
{
    Context& ctx = context();
    std::string gen = "gen " + std::to_string(generation);
    auto voice = std::make_unique<Outcome>();
    voice->kind = Outcome::Voice;
    voice->generation = generation;
    if (!ctx.voiceEnabled) {
        voice->error = "voice_enabled is false in config.json";
        post(std::move(voice));
        return;
    }
    if (!isCurrent(generation)) {
        log("speak " + gen + ": skipped, turn already stale");
        return;
    }
    std::string speakId = newRequestId("tts");
    std::filesystem::path file = ctx.voiceDir
        / ("kagrenac-er-" + std::to_string(GetCurrentProcessId()) + "-" + std::to_string(generation) + ".wav");
    std::string error;
    auto start = std::chrono::steady_clock::now();
    bool spoke = ctx.turnClient->speak(reply, file, error, speakId, requestId, ctx.npcId);
    long long ttsMs = msSince(start);
    if (spoke && !takeWav(file, voice->wav)) {
        spoke = false;
        error = "the voice file was not a usable WAV";
    } else if (!spoke) {
        std::error_code ec;
        std::filesystem::remove(file, ec);
    }
    if (!isCurrent(generation)) {
        log("speak " + gen + " " + speakId + ": stale after " + std::to_string(ttsMs) + " ms; dropped, not played");
        return;
    }
    voice->ok = spoke;
    voice->error = error;
    log("speak " + gen + " " + speakId + ": " + (spoke ? "ok" : "failed (" + errorCode(error) + ")") + ", tts "
        + std::to_string(ttsMs) + " ms, " + std::to_string(voice->wav.size()) + " bytes");
    post(std::move(voice));
}

// Returns true when turn.php failed with no confirmed answer (transport error, timeout or a late
// reply discarded), so the server may still be running that turn and the worker must cancel it.
bool runTurn(uint64_t generation, const std::string& text, bool& textPosted)
{
    Context& ctx = context();
    std::string gen = "gen " + std::to_string(generation);
    if (!isCurrent(generation)) {
        log("turn " + gen + ": superseded before sending; dropped");
        return false;
    }
    // The game link's latest fresh snapshot, or "unavailable" for whatever it cannot vouch for.
    // offered_actions is always sent, so an empty list tells the model it cannot act.
    GameContext game;
    game.playerName = "Tarnished";
    game.npcId = ctx.npcId;
    game.npcName = ctx.npcName;
    uint64_t session = describeGame(game, ctx.allowedActions);
    game.offerActions = true;
    if (game.details.find("snapshot_utc") == game.details.end()) {
        SYSTEMTIME utc{};
        GetSystemTime(&utc);
        char snapshot[64];
        std::snprintf(snapshot, sizeof(snapshot), "%04u-%02u-%02uT%02u:%02u:%02uZ, request time; no game capture",
                      utc.wYear, utc.wMonth, utc.wDay, utc.wHour, utc.wMinute, utc.wSecond);
        game.details["snapshot_utc"] = snapshot;
    }

    std::string requestId = newRequestId("req");
    log("turn " + gen + " " + requestId + ": sent, game session " + std::to_string(session) + ", "
        + std::to_string(game.offeredActions.size()) + " actions offered");
    auto start = std::chrono::steady_clock::now();
    TurnResult result = ctx.turnClient->sendTurn(requestId, game, text);
    long long llmMs = msSince(start);
    std::string code = result.ok ? "ok" : errorCode(result.error);
    bool orphaned = !result.ok && (code.rfind("WinHTTP", 0) == 0 || code == "late reply discarded");
#ifdef KAGRENAC_ER_TEST_HOST
    if (text == "kagrenac-test-throw") {
        throw std::runtime_error("test variant: internal error after turn.php");
    }
#endif
    if (!isCurrent(generation)) {
        log("turn " + gen + " " + requestId + ": stale after " + std::to_string(llmMs) + " ms (" + code
            + "); dropped, not shown");
        return orphaned;
    }
    auto shown = std::make_unique<Outcome>();
    shown->kind = Outcome::Text;
    shown->generation = generation;
    shown->ok = result.ok;
    if (!result.ok) {
        log("turn " + gen + " " + requestId + ": failed after " + std::to_string(llmMs) + " ms (" + code + ")");
        shown->error = result.error;
        post(std::move(shown));
        return orphaned;
    }
    log("turn " + gen + " " + requestId + ": ok, llm " + std::to_string(llmMs) + " ms, reply "
        + std::to_string(result.reply.size()) + " bytes, " + std::to_string(result.actions.size()) + " action tags");
    shown->reply = result.reply;
    post(std::move(shown));
    textPosted = true;

    // Text first; the order goes to the game link while the voice is fetched, and its answer is
    // collected after the voice, so neither waits for the other.
    std::vector<ActionReport> reports;
    int queued = -1;
    uint64_t ticket = queueActions(generation, session, game, result, reports, queued);
    speakReply(generation, result.reply, requestId);
    if (ticket) {
        OrderResult order = settleOrder(ticket);
        ActionReport& report = reports[static_cast<size_t>(queued)];
        report.status = reportStatus(order);
        report.reason = order.kind == OrderResult::Accepted ? "" : clipReason(order.reason);
        log("turn " + gen + " " + requestId + ": " + report.name + " ticket " + std::to_string(ticket) + ", "
            + report.status);
        note(L"Game order " + toWide(describeOrder(report.name, order)));
    }
    if (reports.empty()) {
        return false;
    }
    // A newer line waits for this worker; an informational report is not worth delaying it.
    if (!isCurrent(generation)) {
        log("result " + gen + " " + requestId + ": not sent, a newer line is waiting");
        return false;
    }
    bool unsupported = false;
    std::string error = ctx.turnClient->reportResult(requestId, ctx.npcId, reports, unsupported);
    log("result " + gen + " " + requestId + ": " + std::to_string(reports.size()) + " entries, "
        + (error.empty() ? std::string("ok") : unsupported ? std::string("server has no result.php")
                                                           : "failed (" + errorCode(error) + ")"));
    return false;
}

// Network worker: one turn at a time. The next line waits until the old request returned and
// any cancel for it has finished, so a late cancel.php can never cancel the newer turn. An exact
// command sends no turn.php, so it waits only for the worker, not for that cancel.
// A turn.php with no confirmed answer, or an internal error, gets its own cancel, requested
// under the same lock that frees the worker, so the next line also waits for that cancel.
void runNetworkWorker()
{
    Context& ctx = context();
    for (;;) {
        uint64_t generation = 0;
        std::string text;
        int order = 0;
        {
            std::unique_lock<std::mutex> lock(ctx.mutex);
            ctx.workCv.wait(lock, [&] {
                return ctx.hasPending && (ctx.pendingOrder != 0 || (!ctx.cancelRequested && !ctx.cancelRunning));
            });
            generation = ctx.pendingGeneration;
            text.swap(ctx.pendingText);
            order = ctx.pendingOrder;
            ctx.hasPending = false;
            ctx.turnInFlight = true;
        }
        auto start = std::chrono::steady_clock::now();
        bool textPosted = false;
        bool orphaned = true;  // after an internal error the server's state is unknown: cancel
        try {
            if (order != 0) {
                orphaned = false;  // no turn.php was sent
                runCommand(generation, static_cast<Order>(order));
            } else {
                orphaned = runTurn(generation, text, textPosted);
            }
        } catch (...) {
            reportInternalError("turn", generation, textPosted);
        }
        {
            std::lock_guard<std::mutex> lock(ctx.mutex);
            ctx.turnInFlight = false;
            if (orphaned) {
                ctx.cancelRequested = true;
            }
        }
        if (orphaned) {
            ctx.cancelCv.notify_one();
        }
        log("worker: free after " + std::to_string(msSince(start)) + " ms (gen " + std::to_string(generation) + ")"
            + (orphaned ? "; no confirmed answer, cancel requested" : ""));
    }
}

// Cancel thread: at most one cancel.php in flight; requests made meanwhile coalesce into one.
void runCancelThread()
{
    Context& ctx = context();
    for (;;) {
        {
            std::unique_lock<std::mutex> lock(ctx.mutex);
            ctx.cancelCv.wait(lock, [&] { return ctx.cancelRequested; });
            ctx.cancelRequested = false;
            ctx.cancelRunning = true;
        }
        try {
            auto start = std::chrono::steady_clock::now();
            std::string error = ctx.cancelClient->cancel(ctx.npcId);
            log("cancel: " + (error.empty() ? std::string("ok") : "failed (" + errorCode(error) + ")") + " after "
                + std::to_string(msSince(start)) + " ms");
        } catch (...) {
            reportInternalError("cancel", 0, false);
        }
        {
            std::lock_guard<std::mutex> lock(ctx.mutex);
            ctx.cancelRunning = false;
        }
        ctx.workCv.notify_all();
    }
}

bool startThread(void (*entry)(), const char* name)
{
    try {
        // Never joined: process-lifetime thread, handle dropped. Last boundary: no C++
        // exception may leave the thread (std::terminate would end the game). That thread then
        // stops; the UI watchdog still ends a waiting line.
        std::thread([entry]() noexcept {
            try {
                entry();
            } catch (...) {
                OutputDebugStringA("kagrenac_er: a thread stopped after an internal error\n");
            }
        }).detach();
        return true;
    } catch (const std::system_error&) {
        log(std::string("init: cannot start the ") + name + " thread");
        return false;
    }
}

bool initialize()
{
    std::filesystem::path dll = modulePath(g_self);
    std::filesystem::path moduleDir = dll.parent_path();
    auto* ctx = new (std::nothrow) Context();
    if (!ctx || moduleDir.empty()) {
        OutputDebugStringA("kagrenac_er: cannot initialize (no memory or module path)\n");
        return false;
    }
    ctx->startTick = GetTickCount64();
    ctx->runtimeDir = _wcsicmp(moduleDir.filename().c_str(), L"natives") == 0 ? moduleDir.parent_path() : moduleDir;
    ctx->voiceDir = ctx->runtimeDir / "voice";
    ctx->logFile = CreateFileW((moduleDir / "kagrenac_elden_ring.log").c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr,
                               CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (ctx->logFile == INVALID_HANDLE_VALUE) {
        char text[96];
        std::snprintf(text, sizeof(text), "kagrenac_er: cannot open kagrenac_elden_ring.log (error %lu); log disabled\n", GetLastError());
        OutputDebugStringA(text);
    }
    g_context = ctx;
    // PID and local time tell this launch's log from a stale one (README, manual test step 2).
    SYSTEMTIME now{};
    GetLocalTime(&now);
    char header[80];
    std::snprintf(header, sizeof(header), "pid %lu, local time %04u-%02u-%02u %02u:%02u:%02u; ", GetCurrentProcessId(),
                  now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute, now.wSecond);
    log(std::string(header) + "Kagrenac Elden Ring native client, client " + kClientVersion
        + "; mod-owned box, game link by bounded mailbox (orders are requests, not confirmed movement)");

    std::filesystem::path host = modulePath(nullptr);
    if (_wcsicmp(host.filename().c_str(), kHostExe) != 0) {
        log("init: host is not the expected executable; the client stays off");
        return false;
    }
    // Pinned: the DLL can never be unloaded while its threads run. me3 has no finalizer call
    // site at the cited pin, so no unload path exists to clean up for.
    HMODULE pinned = nullptr;
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
                            reinterpret_cast<LPCWSTR>(&initialize), &pinned)) {
        log("init: cannot pin the DLL (error " + std::to_string(GetLastError()) + "); the client stays off");
        return false;
    }
    loadSettings(*ctx);
    // Workers first: notConnected is final before the UI thread starts reading it.
    if (ctx->turnClient && !(startThread(runNetworkWorker, "network") && startThread(runCancelThread, "cancel"))) {
        ctx->notConnected = "a client worker thread could not start";
    }
    // The game link only reads and requests; without a connection it has nobody to serve.
    if (ctx->turnClient && ctx->notConnected.empty() && !startThread(runBridgeThread, "game link")) {
        log("init: no game link; the companion talks but cannot act or observe");
    }
    if (!startThread(runUiThread, "UI")) {
        return false;
    }
    log("init: threads started; F8 opens the box while the game is in front");
    return true;
}

}  // namespace

Context& context()
{
    return *g_context;
}

void log(const std::string& line)
{
    Context& ctx = context();
    std::lock_guard<std::mutex> lock(ctx.logMutex);
    if (ctx.logFile == INVALID_HANDLE_VALUE) {
        return;
    }
    char stamp[32];
    std::snprintf(stamp, sizeof(stamp), "%10llu ms  ", GetTickCount64() - ctx.startTick);
    std::string out = stamp + line + "\r\n";
    DWORD written = 0;
    if (!WriteFile(ctx.logFile, out.data(), static_cast<DWORD>(out.size()), &written, nullptr)) {
        CloseHandle(ctx.logFile);
        ctx.logFile = INVALID_HANDLE_VALUE;
        OutputDebugStringA("kagrenac_er: cannot write kagrenac_elden_ring.log; log disabled\n");
    }
}

std::string errorCode(const std::string& error)
{
    if (error.rfind("HTTP ", 0) == 0) {
        return error.substr(0, error.find_first_not_of("0123456789", 5));
    }
    size_t at = error.find("WinHTTP error ");
    if (at != std::string::npos) {
        size_t start = at + 14;
        return "WinHTTP " + error.substr(start, error.find_first_not_of("0123456789", start) - start);
    }
    if (error.find("timeout_seconds") != std::string::npos) {
        return "late reply discarded";
    }
    return "client error";
}

std::string toUtf8(const std::wstring& text)
{
    if (text.empty() || text.size() > 100000) {
        return {};
    }
    int n = WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
    if (n <= 0) {
        return {};
    }
    std::string out(static_cast<size_t>(n), '\0');
    WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), n, nullptr, nullptr);
    return out;
}

std::wstring toWide(const std::string& text)
{
    if (text.empty() || text.size() > 100000) {
        return {};
    }
    int n = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
    if (n <= 0) {
        return {};
    }
    std::wstring out(static_cast<size_t>(n), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), n);
    return out;
}

// The UI thread owns and frees the posted text.
void note(const std::wstring& text)
{
    try {
        HWND target = nullptr;
        {
            std::lock_guard<std::mutex> lock(context().mutex);
            target = context().messageWindow;
        }
        auto line = std::make_unique<std::wstring>(text.substr(0, 240));
        if (target && PostMessageW(target, kMsgNote, 0, reinterpret_cast<LPARAM>(line.get()))) {
            line.release();
        }
    } catch (...) {
        OutputDebugStringA("kagrenac_er: game-link note dropped\n");
    }
}

uint64_t submitLine(const std::string& text, int order, bool& waitsForOlder)
{
    Context& ctx = context();
    uint64_t generation = 0;
    {
        std::lock_guard<std::mutex> lock(ctx.mutex);
        generation = ++ctx.generation;
        if (ctx.turnInFlight) {
            ctx.cancelRequested = true;  // the older turn is superseded at once
        }
        ctx.hasPending = true;  // replaces any line still waiting
        ctx.pendingGeneration = generation;
        ctx.pendingText = text;
        ctx.pendingOrder = order;
        waitsForOlder = ctx.turnInFlight || (order == 0 && (ctx.cancelRequested || ctx.cancelRunning));
    }
    ctx.cancelCv.notify_one();
    ctx.workCv.notify_all();
    log("line gen " + std::to_string(generation) + ": queued" + (waitsForOlder ? ", waits for the older request" : ""));
    return generation;
}

uint64_t invalidate(const char* reason)
{
    Context& ctx = context();
    uint64_t generation = 0;
    bool cancelled = false;
    {
        std::lock_guard<std::mutex> lock(ctx.mutex);
        generation = ++ctx.generation;
        ctx.hasPending = false;
        ctx.pendingText.clear();
        if (ctx.turnInFlight) {
            ctx.cancelRequested = cancelled = true;
        }
    }
    ctx.cancelCv.notify_one();
    cancelOrders();  // after Context::mutex is released: Context before Bridge, never nested here
    log(std::string("invalidate (") + reason + "): now gen " + std::to_string(generation)
        + (cancelled ? ", cancel requested" : ""));
    return generation;
}

bool isCurrent(uint64_t generation)
{
    std::lock_guard<std::mutex> lock(context().mutex);
    return context().generation == generation;
}

}  // namespace kagrenac_er

// me3 initializer. Returns true once the threads are running; false (logged) otherwise.
// A second call does nothing and returns false. No exception may cross into me3 (Rust aborts
// on a foreign unwind), so a throw from initialize() becomes false with a static message only.
extern "C" __declspec(dllexport) bool kagrenac_init()
{
    if (kagrenac_er::g_started.exchange(true)) {
        return false;
    }
    try {
        return kagrenac_er::initialize();
    } catch (...) {
        OutputDebugStringA("kagrenac_er: initialization failed (exception); the client stays off\n");
        return false;
    }
}

#ifdef KAGRENAC_ER_TEST_HOST
// Test variant only: opens the box without F8, so the harness need not inject keys.
extern "C" __declspec(dllexport) void kagrenac_test_show()
{
    if (!kagrenac_er::g_context) {
        return;
    }
    HWND target = nullptr;
    {
        std::lock_guard<std::mutex> lock(kagrenac_er::context().mutex);
        target = kagrenac_er::context().messageWindow;
    }
    if (target) {
        PostMessageW(target, kagrenac_er::kMsgTestShow, 0, 0);
    }
}
#endif

// No threads, waits or cleanup here. Process detach intentionally frees nothing.
BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID)
{
    if (reason == DLL_PROCESS_ATTACH) {
        kagrenac_er::g_self = module;
        DisableThreadLibraryCalls(module);
    }
    return TRUE;
}
