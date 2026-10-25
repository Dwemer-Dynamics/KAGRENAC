#pragma once
// The turn lifecycle a game port reuses: bounded worker pools, the mailbox between threads,
// the pending request, NPC instance checks, server cancellation, action dispatch, optional
// voice and optional result reports. One port owns one TurnRuntime.
//
// Every public method runs on the game thread, the same thread that calls the GameAdapter.
// Workers only make blocking HTTP calls and post what they got to the mailbox; they never
// call the game. tick() applies the mailbox on the game thread.

#include <filesystem>
#include <functional>
#include <future>
#include <map>
#include <memory>
#include <string>
#include <utility>
#include <vector>

#include "ai_client.h"
#include "config.h"
#include "game_adapter.h"

class TurnRuntime {
public:
    // Runs one allowlisted action on the game thread. npcId is always the NPC the request was
    // sent to. Returns true only when the engine ran the action; false when nothing ran or it
    // failed (reported "failed"). A handler that throws is treated as false.
    using ActionHandler = std::function<bool(const std::string& npcId)>;
    // Runs on a worker with the settings current when it was started; returns a status line
    // that tick() shows on the game thread. It must not touch the game. A running job is
    // waited for, never stopped: anything it captures by reference or pointer must stay valid
    // until shutdown() or the destructor returns. A job that throws shows a fixed failure line.
    using Job = std::function<std::string(const AiClient&)>;

    // reportSource ends the result-report status line, e.g. "client-reported".
    TurnRuntime(GameAdapter& game, const Config& config, std::string reportSource = "client-reported");
    // Waits for workers still out (each bounded by timeout_seconds) without calling the game;
    // it never detaches them. Never let it run from DllMain or a global or static destructor,
    // where the wait can hang: the port owns the runtime and destroys it from the engine's
    // unload hook on the game thread, before teardown.
    ~TurnRuntime();
    TurnRuntime(const TurnRuntime&) = delete;
    TurnRuntime& operator=(const TurnRuntime&) = delete;

    // Registers the port's handler for one action name (1-40 characters of A-Z a-z 0-9 _).
    // An action runs only if it is in the config's allowed_actions and has a handler here;
    // with none registered, every returned action is rejected. Returns false for a bad name.
    bool setActionHandler(const std::string& name, ActionHandler handler);

    // Starts a turn to the NPC readContext() names now: a typed line, a WAV to transcribe
    // first (text is then ignored), or with eventType a game event the NPC reacts to. It
    // replaces any pending turn or voice. Returns the request id, or "" when refused (the
    // reason was shown).
    std::string submitTurn(const std::string& text, const std::filesystem::path& speechWav = {},
                           const std::string& eventType = "");

    // Runs a job on a normal worker, e.g. a log-only event or a decision. Returns false
    // when every worker is busy (shown, not queued).
    bool startJob(Job job);

    // Drops the pending turn (and tells the server, in the session it was sent in) or the
    // pending voice, showing message when it is not empty. Returns false if nothing was pending.
    bool cancel(const std::string& message);

    // Switches session, like loading another save: drops anything pending with dropMessage,
    // then new requests use sessionId. Requests already out keep their settings. Returns
    // false, changing nothing, when sessionId is not a valid protocol id.
    bool setSession(const std::string& sessionId, const std::string& dropMessage);

    // Call once per game tick: shows worker messages, drops replies for an NPC that left,
    // applies the pending turn's reply and actions, then plays its voice when that arrives.
    void tick();

    // Drops anything pending (showing message), waits for every worker and shows their
    // status lines and cancel answers. Replies and voice still out are never applied, and
    // no worker calls the game. Later calls do nothing. cancelOnServer false drops the pending
    // turn locally without starting a server cancel (for engines whose ENGINE_PACK does not
    // allow one at quit); requests already out are still waited for. Same hook rule as the
    // destructor: never from DllMain or a static destructor.
    void shutdown(const std::string& message, bool cancelOnServer = true);

    bool hasPending() const;                   // a turn or its voice is still wanted
    bool idle() const;                         // nothing pending and no worker out
    const GameContext* pendingTurn() const;    // the NPC of the pending turn, or nullptr
    std::string pendingNpcName() const;        // the NPC of the pending turn or voice
    const Config& settings() const;            // the settings new requests use
    bool lastTurnOk() const;                   // the last finished turn was applied

private:
    struct Mailbox;
    struct CancelDone;
    struct VoiceDone;
    using ClientPtr = std::shared_ptr<const AiClient>;
    // A request the game still waits for; requestId is "" when there is none.
    struct Pending {
        std::string requestId;
        GameContext context;
        ClientPtr client;
    };

    size_t busyWorkers() const;
    void reapWorkers();
    void releaseTurnWorker();
    bool queueCancel(const ClientPtr& sender, const std::string& npcId);
    bool drop(const std::string& message, bool cancelOnServer);
    void handleResult(const TurnResult& result);
    std::vector<ActionReport> applyResult(const Pending& turn, const TurnResult& result);
    void startVoice(const Pending& turn, const TurnResult& result);
    void handleVoice(const VoiceDone& done);
    void waitAll();

    static constexpr size_t kMaxWorkers = 4;        // turns, events, decisions, voice, reports
    static constexpr size_t kMaxCancelWorkers = 2;  // reserved for server cancellations

    GameAdapter& game_;
    ClientPtr client_;
    std::string reportSource_;
    std::shared_ptr<Mailbox> mailbox_;
    std::map<std::string, ActionHandler> handlers_;
    std::vector<std::future<void>> workers_;
    std::vector<std::future<void>> cancelWorkers_;
    std::future<void> turnWorker_;  // the pending turn's worker, counted as a normal worker
    Pending turn_;
    Pending voice_;  // requestId is the turn's id while its voice is still wanted
    std::string lastAppliedRequestId_;
    bool lastTurnOk_ = false;
    // Server cancels still out, by session and NPC id, with the newest cancel's number.
    std::map<std::pair<std::string, std::string>, unsigned long long> cancelling_;
    unsigned long long lastCancelId_ = 0;
    bool stopped_ = false;
};
