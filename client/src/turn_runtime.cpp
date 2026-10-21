#include "turn_runtime.h"

#include <algorithm>
#include <chrono>
#include <deque>
#include <mutex>
#include <system_error>

// A server cancellation that finished (error is "" when the server confirmed it).
struct TurnRuntime::CancelDone {
    std::string sessionId;
    std::string npcId;
    unsigned long long id = 0;
    std::string error;
};

// A finished text-to-speech call for an applied turn (file is empty when it failed).
struct TurnRuntime::VoiceDone {
    std::string requestId;       // the turn the voice belongs to
    std::string speakRequestId;
    std::filesystem::path file;
    std::string error;
};

// Hand-off between threads. Workers only push; only the game thread (tick, shutdown) reads.
struct TurnRuntime::Mailbox {
    std::mutex mutex;
    std::deque<TurnResult> results;    // finished turns
    std::deque<CancelDone> cancels;    // finished server cancellations
    std::deque<VoiceDone> voices;      // finished voice for applied turns
    std::deque<std::string> messages;  // status lines from other workers
    bool reportsOff = false;           // set when the server has no result.php
};

namespace {

// Every worker catches its own exceptions and posts a failure, so get() has nothing to
// rethrow; the catch only keeps anything unexpected out of the game thread.
void finish(std::future<void>& worker)
{
    try {
        worker.get();
    } catch (...) {
    }
}

void reap(std::vector<std::future<void>>& pool)
{
    for (auto worker = pool.begin(); worker != pool.end();) {
        if (worker->wait_for(std::chrono::seconds(0)) == std::future_status::ready) {
            finish(*worker);
            worker = pool.erase(worker);
        } else {
            ++worker;
        }
    }
}

bool isActionName(const std::string& name)
{
    if (name.empty() || name.size() > 40) {
        return false;
    }
    return std::all_of(name.begin(), name.end(), [](char c) {
        return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
    });
}

// A port's handler that throws counts as failed, so the exception never leaves tick().
bool runHandler(const TurnRuntime::ActionHandler& handler, const std::string& npcId)
{
    try {
        return handler(npcId);
    } catch (...) {
        return false;
    }
}

// Status line for a finished server cancellation. Failed cancels are never retried.
std::string describeCancel(const std::string& error, const std::string& npcId, const std::string& sessionId)
{
    if (!error.empty()) {
        return "Server cancel failed (not retried; you can send again): " + error;
    }
    return "Server confirmed the cancel for " + npcId + " in session " + sessionId + ".";
}

// One line naming every request id of a turn, printed on success and failure, so the server's
// Logs and Connector calls pages can be searched for them. Voice has its own line later.
std::string traceLine(const TurnResult& result)
{
    std::string line = "Trace: turn " + result.requestId;
    if (!result.listenRequestId.empty()) {
        line += ", speech-to-text " + result.listenRequestId;
    }
    return line + (result.ok ? " (ok)" : " (failed)");
}

// Runs on a worker thread: optional speech-to-text, then the AI turn. With eventType set, the
// line is an explicit game event the NPC reacts to (event.php, respond true). Voice is made
// later, after the game thread has shown the text and run the actions.
TurnResult runTurn(const AiClient& client, const std::string& requestId, const GameContext& context,
                   std::string text, const std::filesystem::path& speechWav, const std::string& eventType)
{
    std::string heard;
    // Voice calls get their own request ids, with this turn's id as their parent, so the
    // server's Connector calls page can show them under the turn.
    std::string listenRequestId;
    if (!speechWav.empty()) {
        std::string error;
        listenRequestId = newRequestId("stt");
        if (!client.listen(speechWav, text, error, listenRequestId, requestId)) {
            TurnResult failed;
            failed.requestId = requestId;
            failed.listenRequestId = listenRequestId;
            failed.error = "speech to text failed (" + error + "), please type instead";
            return failed;
        }
        heard = text;
        if (text.empty()) {
            TurnResult failed;
            failed.requestId = requestId;
            failed.listenRequestId = listenRequestId;
            failed.error = "no speech was recognized, please type instead";
            return failed;
        }
    }
    TurnResult result = eventType.empty() ? client.sendTurn(requestId, context, text)
                                          : client.sendEvent(requestId, context, eventType, text, true);
    result.heard = heard;
    result.listenRequestId = listenRequestId;
    return result;
}

// Runs on a worker thread. A failed report never changes the reply or actions already applied.
std::string sendReport(const AiClient& client, const std::string& requestId, const std::string& npcId,
                       const std::vector<ActionReport>& reports, const std::string& source, bool& unsupported)
{
    std::string error = client.reportResult(requestId, npcId, reports, unsupported);
    if (unsupported) {
        return "Result reports off: this server has no result.php.";
    }
    if (!error.empty()) {
        return "Result report failed (reply and actions kept): " + error;
    }
    std::string names;
    for (const ActionReport& report : reports) {
        names += (names.empty() ? "" : ", ") + report.name + " " + report.status;
    }
    // What this client's handlers did, not a receipt the game observed the outcome.
    return "Result reported to server: " + names + " (" + source + ").";
}

}  // namespace

TurnRuntime::TurnRuntime(GameAdapter& game, const Config& config, std::string reportSource)
    : game_(game),
      client_(std::make_shared<const AiClient>(config)),
      reportSource_(std::move(reportSource)),
      mailbox_(std::make_shared<Mailbox>())
{
}

TurnRuntime::~TurnRuntime()
{
    waitAll();
}

bool TurnRuntime::setActionHandler(const std::string& name, ActionHandler handler)
{
    if (!isActionName(name) || !handler) {
        return false;
    }
    handlers_[name] = std::move(handler);
    return true;
}

size_t TurnRuntime::busyWorkers() const
{
    return workers_.size() + (turnWorker_.valid() ? 1 : 0);
}

void TurnRuntime::reapWorkers()
{
    reap(workers_);
    reap(cancelWorkers_);
}

// The pending turn was dropped: its worker stays counted until it finishes.
void TurnRuntime::releaseTurnWorker()
{
    if (turnWorker_.valid()) {
        workers_.push_back(std::move(turnWorker_));
    }
}

// Tells the server to drop the in-flight turn, in the session it was sent in. The reply is
// already discarded locally. Returns false when no cancel slot was free. A failed cancel is
// reported, never retried. A cancel makes every turn the server has for that NPC in that
// session stale, so new turns there wait until it is answered (see submitTurn).
bool TurnRuntime::queueCancel(const ClientPtr& sender, const std::string& npcId)
{
    if (cancelWorkers_.size() >= kMaxCancelWorkers) {
        return false;
    }
    unsigned long long id = ++lastCancelId_;
    std::string sessionId = sender->config().sessionId;
    cancelling_[{sessionId, npcId}] = id;
    cancelWorkers_.push_back(std::async(std::launch::async, [sender, mailbox = mailbox_, sessionId, npcId, id] {
        // Worker failures are posted with a fixed text, never what(): it could carry provider
        // details. Posting always clears the wait for this NPC.
        std::string error;
        try {
            error = sender->cancel(npcId);
        } catch (...) {
            error = "the client failed before the server answered";
        }
        std::lock_guard<std::mutex> lock(mailbox->mutex);
        mailbox->cancels.push_back({sessionId, npcId, id, error});
    }));
    return true;
}

std::string TurnRuntime::submitTurn(const std::string& text, const std::filesystem::path& speechWav,
                                    const std::string& eventType)
{
    if (stopped_) {
        return "";
    }
    reapWorkers();
    if (busyWorkers() >= kMaxWorkers) {
        game_.showMessage("Workers busy; please try again when a request finishes.");
        return "";
    }
    GameContext context = game_.readContext();
    if (context.npcId.empty()) {
        game_.showMessage("No NPC here to talk to.");
        return "";
    }
    if (cancelling_.count({client_->config().sessionId, context.npcId}) > 0) {
        game_.showMessage("Waiting for the server to confirm the cancel for " + context.npcName
                          + "; send again after it answers (not queued).");
        return "";
    }
    // Keep one cancel slot free for this new turn, after any cancel for the old one. A new
    // turn to the same NPC needs no cancel: the server marks the old one stale.
    bool replacesOther = !turn_.requestId.empty() && context.npcId != turn_.context.npcId;
    if (cancelWorkers_.size() + (replacesOther ? 1 : 0) >= kMaxCancelWorkers) {
        game_.showMessage("Waiting for a server cancel to answer; send again after it does (not queued).");
        return "";
    }
    if (replacesOther && !queueCancel(turn_.client, turn_.context.npcId)) {
        // Not expected: the check above left a slot. The old reply is not wanted either way.
        game_.showMessage("Cancel slots busy; old reply discarded locally. Server cancellation was not sent.");
    }
    releaseTurnWorker();
    if (!voice_.requestId.empty()) {
        game_.showMessage("Dropped the voice for request " + voice_.requestId
                          + ": a new line replaced it (its text was already shown).");
        voice_.requestId.clear();
    }
    turn_ = {newRequestId(), context, client_};
    game_.showMessage("(waiting for " + context.npcName + "...)");
    turnWorker_ = std::async(std::launch::async, [sender = client_, mailbox = mailbox_, requestId = turn_.requestId,
                                                   context, text, speechWav, eventType] {
        TurnResult result;
        try {
            result = runTurn(*sender, requestId, context, text, speechWav, eventType);
        } catch (...) {
            // Posted as this turn's failure, so tick() leaves the pending state as for any
            // other error. Never retried.
            result.requestId = requestId;
            result.error = "the client failed while handling this request";
        }
        std::lock_guard<std::mutex> lock(mailbox->mutex);
        mailbox->results.push_back(std::move(result));
    });
    return turn_.requestId;
}

bool TurnRuntime::startJob(Job job)
{
    if (stopped_ || !job) {
        return false;
    }
    reapWorkers();
    if (busyWorkers() >= kMaxWorkers) {
        game_.showMessage("Workers busy; please try again when a request finishes.");
        return false;
    }
    workers_.push_back(std::async(std::launch::async, [sender = client_, mailbox = mailbox_, job = std::move(job)] {
        std::string message;
        try {
            message = job(*sender);
        } catch (...) {
            message = "A background request failed in the client (not retried).";
        }
        std::lock_guard<std::mutex> lock(mailbox->mutex);
        mailbox->messages.push_back(message);
    }));
    return true;
}

bool TurnRuntime::cancel(const std::string& message)
{
    return drop(message, true);
}

bool TurnRuntime::drop(const std::string& message, bool cancelOnServer)
{
    if (!turn_.requestId.empty()) {
        turn_.requestId.clear();
        releaseTurnWorker();
        if (!message.empty()) {
            game_.showMessage(message);
        }
        if (cancelOnServer && !queueCancel(turn_.client, turn_.context.npcId)) {
            game_.showMessage("Cancel slots busy; reply discarded locally. Server cancellation was not sent.");
        }
        return true;
    }
    if (!voice_.requestId.empty()) {
        // The turn is already saved on the server; only the local voice is dropped.
        voice_.requestId.clear();
        if (!message.empty()) {
            game_.showMessage(message);
        }
        game_.showMessage("Its text was already shown; its voice will not play.");
        return true;
    }
    return false;
}

bool TurnRuntime::setSession(const std::string& sessionId, const std::string& dropMessage)
{
    if (stopped_ || !isValidId(sessionId)) {
        return false;
    }
    cancel(dropMessage);
    Config next = client_->config();
    next.sessionId = sessionId;
    client_ = std::make_shared<const AiClient>(next);
    return true;
}

void TurnRuntime::tick()
{
    if (stopped_) {
        return;
    }
    reapWorkers();
    std::deque<TurnResult> results;
    std::deque<CancelDone> cancels;
    std::deque<VoiceDone> voices;
    std::deque<std::string> messages;
    {
        std::lock_guard<std::mutex> lock(mailbox_->mutex);
        results.swap(mailbox_->results);
        cancels.swap(mailbox_->cancels);
        voices.swap(mailbox_->voices);
        messages.swap(mailbox_->messages);
    }
    for (const std::string& message : messages) {
        game_.showMessage(message);
    }
    for (const CancelDone& done : cancels) {
        // Only the newest cancel's answer for a session and NPC clears it.
        auto waiting = cancelling_.find({done.sessionId, done.npcId});
        if (waiting != cancelling_.end() && waiting->second == done.id) {
            cancelling_.erase(waiting);
        }
        game_.showMessage(describeCancel(done.error, done.npcId, done.sessionId));
    }
    // If the NPC left while its reply or voice is out, drop it now (and tell the server).
    for (const Pending* pending : {&turn_, &voice_}) {
        if (!pending->requestId.empty() && !game_.isSameNpc(pending->context)) {
            const std::string& name = pending->context.npcName;
            cancel("Dropped the pending reply for " + name + ": " + name + " is no longer here.");
        }
    }
    for (const TurnResult& result : results) {
        handleResult(result);
    }
    for (const VoiceDone& done : voices) {
        handleVoice(done);
    }
}

void TurnRuntime::handleResult(const TurnResult& result)
{
    if (!lastAppliedRequestId_.empty() && result.requestId == lastAppliedRequestId_) {
        game_.showMessage("Ignored a second copy of a reply that was already applied.");
        return;
    }
    if (result.requestId != turn_.requestId) {
        game_.showMessage("Ignored a stale reply (request " + result.requestId + "; it was cancelled or replaced).");
        return;
    }
    Pending turn = turn_;
    turn_.requestId.clear();
    if (turnWorker_.valid()) {
        finish(turnWorker_);  // posting this result was its last step
    }
    lastTurnOk_ = false;
    // Recheck on the game thread right before applying: the NPC may have been unloaded,
    // deleted or replaced while the request was out. Nothing is applied or reported then.
    if (!game_.isSameNpc(turn.context)) {
        game_.showMessage("Dropped the reply and its actions: " + turn.context.npcName + " is no longer here (request "
                          + result.requestId + ").");
        return;
    }
    lastAppliedRequestId_ = result.requestId;
    lastTurnOk_ = result.ok;
    std::vector<ActionReport> reports = applyResult(turn, result);
    bool reportsOff = false;
    {
        std::lock_guard<std::mutex> lock(mailbox_->mutex);
        reportsOff = mailbox_->reportsOff;
    }
    // Optional report, queued after the game thread ran the actions and before the optional
    // voice, so the server's only record of the actions gets the last free worker. Skipped
    // when there is nothing to report or the server could not log the turn.
    if (!reports.empty() && result.logged && !reportsOff) {
        if (busyWorkers() >= kMaxWorkers) {
            game_.showMessage("Workers busy; result report skipped (reply and actions kept).");
        } else {
            workers_.push_back(std::async(std::launch::async, [sender = turn.client, mailbox = mailbox_,
                                                               requestId = result.requestId,
                                                               npcId = turn.context.npcId, reports,
                                                               source = reportSource_] {
                bool unsupported = false;
                std::string message;
                try {
                    message = sendReport(*sender, requestId, npcId, reports, source, unsupported);
                } catch (...) {
                    message = "Result report failed in the client (reply and actions kept).";
                }
                std::lock_guard<std::mutex> lock(mailbox->mutex);
                mailbox->reportsOff = mailbox->reportsOff || unsupported;
                mailbox->messages.push_back(message);
            }));
        }
    }
    startVoice(turn, result);
}

// Runs on the game thread, once per applied turn. An action runs only if it is allowlisted
// and the port registered a handler for that exact name. Returns what happened to each
// returned action, for the optional result report.
std::vector<ActionReport> TurnRuntime::applyResult(const Pending& turn, const TurnResult& result)
{
    std::vector<ActionReport> reports;
    if (!result.heard.empty()) {
        game_.showMessage("You said: " + result.heard);
    }
    if (!result.ok) {
        // Never retried automatically: a retry could repeat a reply or an action.
        game_.showMessage("AI unavailable: " + result.error + " (not retried; send again for a new request)");
        game_.showMessage(traceLine(result));
        return reports;
    }
    game_.showSubtitle(turn.context.npcName, result.reply);
    const std::vector<std::string>& allowed = turn.client->config().allowedActions;
    for (const TurnAction& action : result.actions) {
        ActionReport report{action.name, "handled", ""};
        auto handler = handlers_.find(action.name);
        if (!action.problem.empty()) {
            game_.showMessage("Rejected action " + (action.name.empty() ? std::string("(malformed)") : action.name)
                              + ": " + action.problem);
            report = {action.name, "rejected", action.problem};
        } else if (std::find(allowed.begin(), allowed.end(), action.name) == allowed.end()) {
            game_.showMessage("Rejected action not allowed by this mod: " + action.name);
            report = {action.name, "rejected", "not allowed by this mod"};
        } else if (handler == handlers_.end()) {
            game_.showMessage("Rejected action with no handler in this port: " + action.name);
            report = {action.name, "rejected", "no handler in this port"};
        } else if (!runHandler(handler->second, turn.context.npcId)) {
            // The target is the NPC this request was sent to; a sent target_id was checked
            // against it already.
            game_.showMessage("Action " + action.name + " failed in the game's handler.");
            report = {action.name, "failed", "handler failed"};
        }
        if (reports.size() < 4 && !action.name.empty()) {  // result.php limits
            reports.push_back(report);
        }
    }
    game_.showMessage(traceLine(result));
    return reports;
}

// Optional voice, made after the text and actions were applied, so a slow voice service
// never delays them. Its completion is applied only if this turn's voice is still wanted.
void TurnRuntime::startVoice(const Pending& turn, const TurnResult& result)
{
    if (!result.ok || !turn.client->config().voiceEnabled) {
        return;
    }
    if (busyWorkers() >= kMaxWorkers) {
        game_.showMessage("Workers busy; voice skipped, text only (request " + result.requestId + ").");
        return;
    }
    voice_ = turn;
    std::string speakRequestId = newRequestId("tts");
    workers_.push_back(std::async(std::launch::async, [sender = turn.client, mailbox = mailbox_,
                                                       requestId = result.requestId, speakRequestId,
                                                       reply = result.reply, npcId = turn.context.npcId] {
        VoiceDone done{requestId, speakRequestId, {}, {}};
        try {
            std::error_code failed;
            std::filesystem::path folder = std::filesystem::temp_directory_path(failed);
            if (failed) {
                done.error = "no temporary folder for the WAV file";
            } else {
                std::filesystem::path wav = folder / "dwemer-ai-example" / (requestId + ".wav");
                if (sender->speak(reply, wav, done.error, speakRequestId, requestId, npcId)) {
                    done.file = wav;
                }
            }
        } catch (...) {
            done.file.clear();
            done.error = "the client failed while making the voice";
        }
        std::lock_guard<std::mutex> lock(mailbox->mutex);
        mailbox->voices.push_back(std::move(done));
    }));
}

void TurnRuntime::handleVoice(const VoiceDone& done)
{
    std::string trace = "Trace: voice " + done.speakRequestId + " for turn " + done.requestId;
    if (voice_.requestId.empty() || done.requestId != voice_.requestId) {
        game_.showMessage("Ignored voice that is no longer wanted (cancelled or replaced). " + trace + " (dropped)");
        return;
    }
    Pending voice = voice_;
    voice_.requestId.clear();
    if (voice.client->config().sessionId != client_->config().sessionId || !game_.isSameNpc(voice.context)) {
        game_.showMessage("Dropped the voice: the session changed or " + voice.context.npcName + " is no longer here. "
                          + trace + " (dropped)");
        return;
    }
    if (!done.file.empty()) {
        game_.playVoice(done.file);
        game_.showMessage(trace + " (ok)");
    } else {
        game_.showMessage("Voice unavailable, text only: " + done.error);
        game_.showMessage(trace + " (failed)");
    }
}

void TurnRuntime::shutdown(const std::string& message, bool cancelOnServer)
{
    if (stopped_) {
        return;
    }
    drop(message, cancelOnServer);
    stopped_ = true;
    releaseTurnWorker();
    // At most kMaxWorkers + kMaxCancelWorkers requests are out and each blocking HTTP call
    // ends within its timeouts, so this wait is bounded. Nothing they return is applied.
    if (!workers_.empty() || !cancelWorkers_.empty()) {
        game_.showMessage("Waiting for " + std::to_string(workers_.size() + cancelWorkers_.size())
                          + " request(s) to finish; replies are not applied.");
    }
    for (std::future<void>& worker : cancelWorkers_) {
        finish(worker);
    }
    for (std::future<void>& worker : workers_) {
        finish(worker);
    }
    cancelWorkers_.clear();
    workers_.clear();
    std::deque<CancelDone> cancels;
    std::deque<std::string> messages;
    {
        std::lock_guard<std::mutex> lock(mailbox_->mutex);
        cancels.swap(mailbox_->cancels);
        messages.swap(mailbox_->messages);
    }
    for (const std::string& line : messages) {
        game_.showMessage(line);
    }
    for (const CancelDone& done : cancels) {
        game_.showMessage(describeCancel(done.error, done.npcId, done.sessionId));
    }
}

void TurnRuntime::waitAll()
{
    if (turnWorker_.valid()) {
        turnWorker_.wait();
    }
    for (std::future<void>& worker : cancelWorkers_) {
        worker.wait();
    }
    for (std::future<void>& worker : workers_) {
        worker.wait();
    }
}

bool TurnRuntime::hasPending() const
{
    return !turn_.requestId.empty() || !voice_.requestId.empty();
}

bool TurnRuntime::idle() const
{
    return !hasPending() && workers_.empty() && cancelWorkers_.empty() && !turnWorker_.valid();
}

const GameContext* TurnRuntime::pendingTurn() const
{
    return turn_.requestId.empty() ? nullptr : &turn_.context;
}

std::string TurnRuntime::pendingNpcName() const
{
    return !turn_.requestId.empty() ? turn_.context.npcName : voice_.requestId.empty() ? "" : voice_.context.npcName;
}

const Config& TurnRuntime::settings() const
{
    return client_->config();
}

bool TurnRuntime::lastTurnOk() const
{
    return lastTurnOk_;
}
