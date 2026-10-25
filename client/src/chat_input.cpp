#include "chat_input.h"

#include <system_error>

namespace {

// Well-formed UTF-8 as PHP's /u patterns require: no overlong forms, surrogates or code points
// above U+10FFFF. turn.php treats anything else as empty text.
bool validUtf8(const std::string& text)
{
    size_t i = 0;
    while (i < text.size()) {
        unsigned char c = static_cast<unsigned char>(text[i]);
        size_t extra = 0;
        unsigned long cp = 0;
        unsigned long min = 0;
        if (c < 0x80) {
            ++i;
            continue;
        } else if (c >= 0xC2 && c <= 0xDF) {
            extra = 1, cp = c & 0x1F, min = 0x80;
        } else if (c >= 0xE0 && c <= 0xEF) {
            extra = 2, cp = c & 0x0F, min = 0x800;
        } else if (c >= 0xF0 && c <= 0xF4) {
            extra = 3, cp = c & 0x07, min = 0x10000;
        } else {
            return false;
        }
        if (text.size() - i <= extra) {
            return false;
        }
        for (size_t k = 1; k <= extra; ++k) {
            unsigned char next = static_cast<unsigned char>(text[i + k]);
            if ((next & 0xC0) != 0x80) {
                return false;
            }
            cp = (cp << 6) | (next & 0x3F);
        }
        if (cp < min || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) {
            return false;
        }
        i += extra + 1;
    }
    return true;
}

// lib/app.php clean_line() for valid UTF-8: each run of control characters (line breaks too)
// becomes one space, then the line is trimmed.
std::string cleanLine(const std::string& text)
{
    std::string line;
    bool inRun = false;
    for (char ch : text) {
        unsigned char c = static_cast<unsigned char>(ch);
        bool control = c < 0x20 || c == 0x7F;
        if (control && !inRun) {
            line += ' ';
        } else if (!control) {
            line += ch;
        }
        inRun = control;
    }
    size_t first = line.find_first_not_of(' ');
    if (first == std::string::npos) {
        return "";
    }
    return line.substr(first, line.find_last_not_of(' ') - first + 1);
}

bool blank(const std::string& draft)
{
    return validUtf8(draft) && cleanLine(draft).empty();
}

size_t utf8Chars(const std::string& text)
{
    size_t count = 0;
    for (unsigned char c : text) {
        count += (c & 0xC0) != 0x80 ? 1 : 0;
    }
    return count;
}

}  // namespace

ChatInput::ChatInput(TurnRuntime& runtime) : runtime_(runtime) {}

ChatInput::~ChatInput()
{
    close();
}

bool ChatInput::speechInput() const
{
    return runtime_.settings().speechInputEnabled;
}

size_t ChatInput::draftChars() const
{
    return utf8Chars(cleanLine(draft_));
}

bool ChatInput::open(const GameContext& recipient)
{
    if (state_ != State::Closed || recipient.npcId.empty()) {
        return false;
    }
    recipient_ = recipient;
    sessionId_ = runtime_.settings().sessionId;
    editing("");
    if (failedHeld_) {
        failedHeld_ = false;
        status_ = restoreFailedLine()
                      ? "Your line to " + sentRecipient_.npcName
                            + " was not answered; it is back in the draft. Press Enter to send it again."
                      : "Your unanswered line to " + sentRecipient_.npcName
                            + " was not put back (newer text, another recipient or a new session).";
    }
    return true;
}

// Cancels the runtime's transcription only if it is still this composer's own.
void ChatInput::dropTranscription()
{
    if (!sttRequestId_.empty() && runtime_.pendingTranscription() == sttRequestId_) {
        runtime_.cancelTranscription();
    }
    sttRequestId_.clear();
}

void ChatInput::close(const std::string& status)
{
    dropTranscription();
    state_ = State::Closed;
    status_ = status;
}

void ChatInput::editing(const std::string& status)
{
    state_ = State::Editing;
    if (!status.empty()) {
        status_ = status;
    } else {
        status_ = speechInput() ? "Enter to send, Esc to close, hold the talk key to speak" : "Enter to send, Esc to close";
    }
}

void ChatInput::setDraft(const std::string& text)
{
    if (state_ == State::Editing) {
        draft_ = text;
    }
}

bool ChatInput::enter()
{
    if (state_ != State::Editing) {
        return false;
    }
    if (!validUtf8(draft_)) {
        status_ = "Not sent: your line has characters that are not valid text. Edit it and press Enter.";
        return false;
    }
    std::string text = cleanLine(draft_);
    if (text.empty()) {
        status_ = "Type something to say first.";
        return false;
    }
    size_t chars = utf8Chars(text);
    if (chars > kMaxTurnTextChars) {
        status_ = "Too long: " + std::to_string(chars) + " of " + std::to_string(kMaxTurnTextChars) + " characters.";
        return false;
    }
    if (runtime_.settings().sessionId != sessionId_) {
        status_ = "Not sent: the game session changed. Close and reopen to choose who to talk to.";
        return false;
    }
    if (!sentRequestId_.empty() && runtime_.pendingTurnId() == sentRequestId_
        && sentRecipient_.npcId == recipient_.npcId && text == sentText_) {
        status_ = "Already waiting for " + recipient_.npcName + " to answer that.";
        return false;
    }
    std::string requestId = runtime_.submitTurnTo(recipient_, text);
    if (requestId.empty()) {
        // The runtime showed why; nothing is queued or resent automatically.
        status_ = "Not sent; your line is kept. Press Enter to try again.";
        return false;
    }
    sentText_ = text;
    sentRecipient_ = recipient_;
    sentSessionId_ = sessionId_;
    sentRequestId_ = requestId;
    failedHeld_ = false;
    draft_.clear();
    ++draftRevision_;
    close("");
    return true;
}

void ChatInput::escape()
{
    switch (state_) {
    case State::Recording:
        editing("Recording discarded.");
        break;
    case State::Transcribing:
        dropTranscription();
        editing("Speech input cancelled.");
        break;
    case State::Editing:
        close("");
        break;
    case State::Closed:
        break;
    }
}

bool ChatInput::pttDown()
{
    if (state_ != State::Editing || !speechInput()) {
        return false;
    }
    state_ = State::Recording;
    status_ = "Recording... release to stop";
    return true;
}

void ChatInput::pttUp(const std::filesystem::path& wav, const std::string& captureError)
{
    if (state_ != State::Recording) {
        if (!wav.empty()) {
            std::error_code ignored;
            std::filesystem::remove(wav, ignored);
        }
        return;
    }
    if (wav.empty()) {
        editing("No recording (" + (captureError.empty() ? std::string("no microphone") : captureError)
                + "); type instead.");
        return;
    }
    sttRequestId_ = runtime_.transcribe(
        wav, [this](const TurnRuntime::Transcript& transcript) { onTranscript(transcript); }, true);
    if (sttRequestId_.empty()) {
        std::error_code ignored;
        std::filesystem::remove(wav, ignored);
        editing("Speech input unavailable; type instead.");
        return;
    }
    state_ = State::Transcribing;
    status_ = "Transcribing...";
}

void ChatInput::onTranscript(const TurnRuntime::Transcript& transcript)
{
    if (state_ != State::Transcribing || transcript.requestId != sttRequestId_) {
        return;
    }
    sttRequestId_.clear();
    if (!transcript.error.empty()) {
        bool off = transcript.error.find("stt_disabled") != std::string::npos;
        editing(off ? "Speech input is off on the server; type instead."
                    : "Didn't catch that (" + transcript.error + "); type instead.");
        return;
    }
    std::string heard = validUtf8(transcript.text) ? cleanLine(transcript.text) : "";
    if (heard.empty()) {
        editing("Didn't catch that; type instead.");
        return;
    }
    draft_ = blank(draft_) ? heard : draft_ + " " + heard;
    ++draftRevision_;
    editing("Check the text, then press Enter to send.");
}

void ChatInput::tick()
{
    if (state_ == State::Transcribing && runtime_.pendingTranscription() != sttRequestId_) {
        sttRequestId_.clear();
        editing("Speech input was dropped; type instead.");
    }
    if (sentRequestId_.empty()) {
        return;
    }
    const TurnRuntime::TurnEnd& end = runtime_.lastTurnEnd();
    if (end.requestId == sentRequestId_) {
        sentRequestId_.clear();
        if (!end.ok) {
            sentLineFailed(end.error);
        }
    } else if (runtime_.pendingTurnId() != sentRequestId_) {
        sentRequestId_.clear();  // cancelled, replaced or dropped: not put back
    }
}

// The last line sent failed after it was accepted. It is never resent: it goes back to the
// draft for the player to check and send with Enter, without replacing anything newer.
void ChatInput::sentLineFailed(const std::string& error)
{
    std::string why = "Your line to " + sentRecipient_.npcName + " failed (" + error + ")";
    if (state_ == State::Closed) {
        failedHeld_ = true;
        status_ = why + "; open the composer to send it again.";
    } else if (state_ == State::Editing && restoreFailedLine()) {
        status_ = why + "; it is back in the draft. Press Enter to send it again.";
    } else {
        status_ = why + " and was not resent; your current draft is kept.";
    }
}

// Puts the failed line in an empty draft, only for the same recipient instance and session.
bool ChatInput::restoreFailedLine()
{
    if (state_ != State::Editing || !blank(draft_) || recipient_.npcId != sentRecipient_.npcId
        || recipient_.npcInstance != sentRecipient_.npcInstance || sessionId_ != sentSessionId_
        || runtime_.settings().sessionId != sentSessionId_) {
        return false;
    }
    draft_ = sentText_;
    ++draftRevision_;
    return true;
}
