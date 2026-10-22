#pragma once
// The player's in-game composer without the game: who the line is for, the editable draft,
// optional push-to-talk into that draft, and when the port must capture input or open the
// microphone. It draws nothing and reads no keys: the port's own native text field, header,
// key bindings and microphone capture drive it and show what it says. One port owns one,
// next to its TurnRuntime, and calls it on the game thread only.
//
// Lifecycle: Closed -> Editing -> (Recording -> Transcribing -> Editing) -> sent (Closed).
// Every exit path ends with wantsInputCapture() and wantsMicOpen() false. Nothing is ever sent
// without enter(), and a refused line stays in the draft for the player to send again. A sent
// line whose turn later fails comes back to the draft (see tick()); it is never resent.

#include <filesystem>
#include <string>

#include "game_adapter.h"
#include "turn_runtime.h"

class ChatInput {
public:
    enum class State { Closed, Editing, Recording, Transcribing };

    // Construct after the runtime and destroy before it (the destructor drops its transcription).
    explicit ChatInput(TurnRuntime& runtime);
    ~ChatInput();
    ChatInput(const ChatInput&) = delete;
    ChatInput& operator=(const ChatInput&) = delete;

    // Opens the composer for the recipient the port just read with readContext() and shows as
    // "To: <npcName>", in the runtime's current session. Returns false and changes nothing when
    // it is already open or the recipient has no npcId (the port says there is no one to talk
    // to). The draft is kept. A failed line held since the composer closed is put back in an
    // empty draft only for the same recipient instance and session; otherwise it is dropped
    // and statusLine() says so.
    bool open(const GameContext& recipient);
    // Closes from any state: drops a recording or transcription, keeps the draft, releases
    // capture and microphone. Safe to repeat. The port calls it on pause, loading screen,
    // death, recipient unload, focus loss, mod shutdown, and whenever its field is not visible.
    void close(const std::string& status = "");
    // The port's text field changed (typing, paste, IME). Ignored unless Editing.
    void setDraft(const std::string& text);
    // Enter: sends the draft, cleaned as turn.php's require_text() does (each run of control
    // characters becomes one space, then trimmed), with TurnRuntime::submitTurnTo() to the
    // shown recipient. True when sent: the draft clears and the composer closes. False when
    // nothing was sent (not valid UTF-8, empty, too long, already waiting for that line, the
    // session changed, not Editing, or the runtime refused): the draft is kept unchanged and
    // statusLine() says why; the player retries with Enter.
    bool enter();
    // Esc: Recording discards the audio and Transcribing drops the request (both back to
    // Editing); Editing closes with the draft kept. Cancelling a sent line is the port's own
    // cancel key calling TurnRuntime::cancel().
    void escape();
    // Push-to-talk pressed, only with speech_input_enabled and while Editing: Recording, and
    // wantsMicOpen() turns true. Returns false otherwise (the microphone stays closed).
    bool pttDown();
    // Push-to-talk released: the port closed the microphone and wrote wav (at most
    // kMaxSpeechWavBytes), or passes an empty path with captureError when capture failed. It
    // starts transcription; the runtime's worker deletes wav. Not Recording: wav is deleted.
    void pttUp(const std::filesystem::path& wav, const std::string& captureError = "");
    // Call after TurnRuntime::tick(): notices a transcription the runtime dropped (session
    // change, shutdown) and returns to Editing. Also notices when the last line enter() sent
    // failed (TurnRuntime::lastTurnEnd(), matched by request id): the line goes back into an
    // empty draft while Editing for the same recipient instance and session, or is held for
    // the next open() while Closed; a newer draft or another recipient is never overwritten.
    // A cancelled, replaced or dropped line, or one that was answered, is not put back.
    void tick();

    State state() const { return state_; }
    bool wantsInputCapture() const { return state_ != State::Closed; }  // game controls get no input
    bool wantsMicOpen() const { return state_ == State::Recording; }
    bool speechInput() const;                                        // offer push-to-talk at all
    const GameContext& recipient() const { return recipient_; }
    const std::string& draft() const { return draft_; }
    size_t draftChars() const;  // Unicode characters after cleaning, as turn.php counts them (limit kMaxTurnTextChars)
    // Changes whenever ChatInput itself changed the draft (a transcript or a send); the port
    // then copies draft() into its field and moves the caret to the end.
    unsigned draftRevision() const { return draftRevision_; }
    const std::string& statusLine() const { return status_; }

private:
    void editing(const std::string& status);
    void dropTranscription();
    void onTranscript(const TurnRuntime::Transcript& transcript);
    void sentLineFailed(const std::string& error);
    bool restoreFailedLine();

    TurnRuntime& runtime_;
    State state_ = State::Closed;
    GameContext recipient_;
    std::string draft_;
    unsigned draftRevision_ = 0;
    std::string status_;
    std::string sessionId_;     // the runtime session recipient_ was read in
    std::string sttRequestId_;  // the transcription this composer waits for
    // The last line sent, for duplicate detection and, if its turn fails, for the draft again.
    std::string sentText_;
    GameContext sentRecipient_;
    std::string sentSessionId_;
    std::string sentRequestId_;  // its turn while it may still fail, else ""
    bool failedHeld_ = false;    // it failed while Closed; next open() decides
};
