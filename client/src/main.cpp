// Console "fake game" that talks to the KagrenacServer AI server.
//
// The main thread plays the role of the game thread: it runs a small tick loop
// and is the only thread that calls the GameAdapter. The turn lifecycle (workers,
// mailbox, stale replies, cancellation, actions, voice) is TurnRuntime; this file
// only parses the command line and console input. A real engine plugin owns its
// own TurnRuntime and calls tick() from its game thread the same way.
//
// Usage:
//   KagrenacClient.exe                       interactive console (/unload and /load simulate the NPC leaving)
//   KagrenacClient.exe --version             print the client version and exit (no config needed)
//   KagrenacClient.exe --health              check the server and exit
//   KagrenacClient.exe --say "Follow me"     send one line and exit
//   KagrenacClient.exe --listen speech.wav   optional voice: transcribe, send, exit
//   KagrenacClient.exe --decide "Scout?"     optional: ask which NPC should answer, print it, exit
//   KagrenacClient.exe --event item_given "The player gave a lantern."   log-only game event, exit
//   KagrenacClient.exe --react item_given "The player gave a lantern."   the Guide reacts to it, exit
//   add --config my.json to use another private config file

#include <chrono>
#include <deque>
#include <iostream>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include <windows.h>

#include "ai_client.h"
#include "config.h"
#include "console_game.h"
#include "turn_runtime.h"

namespace {

// Ends the result-report status line: the console's handler is a simulation, not a game.
constexpr const char* kConsoleReportSource = "client-reported, console simulation";

// Typed lines, handed from the blocking input thread to the main thread.
struct Input {
    std::mutex mutex;
    std::deque<std::string> lines;
    bool closed = false;
};

std::string toUtf8(const std::wstring& wide)
{
    if (wide.empty()) {
        return {};
    }
    int size = WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()), nullptr, 0, nullptr, nullptr);
    std::string text(size, '\0');
    WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()), text.data(), size, nullptr, nullptr);
    return text;
}

std::filesystem::path exeFolder()
{
    wchar_t buffer[MAX_PATH];
    GetModuleFileNameW(nullptr, buffer, MAX_PATH);
    return std::filesystem::path(buffer).parent_path();
}

// The console's one action handler. The runtime calls it only for an allowlisted
// follow_player, with the NPC the request was sent to. It returns true only because
// ConsoleGame overrides followPlayer(); a port's handler returns false when its engine
// did not run the action.
void addConsoleHandlers(TurnRuntime& runtime, GameAdapter& game)
{
    runtime.setActionHandler("follow_player", [&game](const std::string& npcId) {
        game.followPlayer(npcId);
        return true;
    });
}

// Status line for a log-only game event (event.php with respond false).
std::string describeLoggedEvent(const TurnResult& result, const std::string& type)
{
    if (!result.ok) {
        return "Event not logged (not retried; request " + result.requestId + "): " + result.error;
    }
    return "Event " + type + " logged by the server (log only; no reply or actions; request " + result.requestId + ").";
}

// Optional NPC selection demo with two fictional NPCs; the guide is the baseline.
// It only reports the choice. It never switches the NPC being talked to or runs actions.
std::string describeDecision(const AiClient& client, const std::string& transcript)
{
    static const std::vector<DecisionCandidate> candidates = {
        {"npc_guide", "Guide", "market guide in the town square"},
        {"npc_scout", "Scout", "scout who knows the north trail"},
    };
    DecisionResult decision = client.decide(transcript, candidates, "npc_guide");
    if (!decision.ok) {
        return "Decision unavailable, keeping npc_guide (request " + decision.requestId + "): " + decision.error;
    }
    return "Decision: " + decision.chosenId + " (" + decision.source + ", " + decision.reason + ", request "
        + decision.requestId + "). Display only; still talking to the same NPC.";
}

// "/event <type> <text>": splits off the type. Returns false when either part is missing.
bool splitEvent(const std::string& rest, std::string& type, std::string& text)
{
    size_t space = rest.find(' ');
    if (space == std::string::npos) {
        return false;
    }
    type = rest.substr(0, space);
    text = rest.substr(space + 1);
    return !type.empty() && !text.empty();
}

// console is used only for the /npc, /unload and /load test commands; everything else goes
// through the GameAdapter interface and TurnRuntime, as a real engine port would.
int runInteractive(TurnRuntime& runtime, GameAdapter& game, ConsoleGame& console)
{
    auto input = std::make_shared<Input>();
    game.showMessage("Type to talk. Commands: /cancel  /listen <file.wav>  /decide <text>  /event <type> <text>"
                     "  /react <type> <text>  /npc guide|scout  /session <id>  /unload  /load  /quit");

    // getline blocks. Shared ownership keeps its queue alive until input ends.
    // /quit also ends this thread; network workers are joined by runtime.shutdown().
    std::thread([input] {
        std::string line;
        while (std::getline(std::cin, line)) {
            std::lock_guard<std::mutex> lock(input->mutex);
            input->lines.push_back(line);
            if (line == "/quit") {
                break;
            }
        }
        std::lock_guard<std::mutex> lock(input->mutex);
        input->closed = true;
    }).detach();

    bool running = true;
    std::string quitMessage;
    while (running) {
        std::deque<std::string> lines;
        bool inputClosed = false;
        {
            std::lock_guard<std::mutex> lock(input->mutex);
            lines.swap(input->lines);
            inputClosed = input->closed;
        }

        for (const std::string& line : lines) {
            if (line.empty()) {
                continue;
            }
            if (line == "/quit") {
                // Shutdown: the pending reply is never applied, and the server is told so it
                // saves no history for it.
                quitMessage = "Quitting: dropped the pending reply for " + runtime.pendingNpcName() + ".";
                running = false;
                break;
            }
            if (line == "/cancel") {
                if (!runtime.cancel("Cancelled.")) {
                    game.showMessage("Nothing to cancel.");
                }
                continue;
            }
            if (line == "/unload") {
                console.unloadNpc();
                continue;
            }
            if (line == "/load") {
                console.loadNpc();
                continue;
            }
            if (line.rfind("/npc ", 0) == 0) {
                if (!console.faceNpc(line.substr(5))) {
                    game.showMessage("Unknown NPC. Use /npc guide or /npc scout.");
                    continue;
                }
                // The player turned away: the other NPC's reply must not arrive later.
                const GameContext* pending = runtime.pendingTurn();
                if (pending && game.readContext().npcId != pending->npcId) {
                    runtime.cancel("Dropped the pending reply for " + pending->npcName + ": you turned to another NPC.");
                }
                continue;
            }
            if (line.rfind("/session ", 0) == 0) {
                std::string sessionId = line.substr(9);
                if (!isValidId(sessionId)) {
                    game.showMessage("Session ids are 1-64 characters of A-Z a-z 0-9 _ . : -");
                    continue;
                }
                if (sessionId == runtime.settings().sessionId) {
                    game.showMessage("Already in session " + sessionId + ".");
                    continue;
                }
                runtime.setSession(sessionId, "Dropped the pending reply for " + runtime.pendingNpcName()
                                                  + ": the session changed.");
                // This client never reads or changes game saves. Server checkpoints are matched
                // to saves by hand, by this id.
                game.showMessage("Session is now " + sessionId + " (manual, like loading another save). "
                                 "Server checkpoints for it: php scripts/checkpoint.php list " + sessionId);
                continue;
            }

            if (line.rfind("/decide ", 0) == 0) {
                runtime.startJob([transcript = line.substr(8)](const AiClient& client) {
                    return describeDecision(client, transcript);
                });
                continue;
            }
            if (line.rfind("/event ", 0) == 0) {
                // Log only: no reply, history or actions, so nothing waits for it.
                std::string type;
                std::string text;
                if (!splitEvent(line.substr(7), type, text) || !isEventType(type)) {
                    game.showMessage("Use /event <type> <text>; types: location_entered item_given combat_started combat_ended");
                    continue;
                }
                runtime.startJob([context = game.readContext(), type, text](const AiClient& client) {
                    return describeLoggedEvent(client.sendEvent(newRequestId("evt"), context, type, text, false), type);
                });
                continue;
            }

            std::string text = line;
            std::string eventType;
            std::filesystem::path speechWav;
            if (line.rfind("/listen ", 0) == 0) {
                text.clear();
                speechWav = std::filesystem::u8path(line.substr(8));
            } else if (line.rfind("/react ", 0) == 0) {
                if (!splitEvent(line.substr(7), eventType, text) || !isEventType(eventType)) {
                    game.showMessage("Use /react <type> <text>; types: location_entered item_given combat_started combat_ended");
                    continue;
                }
            } else if (line[0] == '/') {
                game.showMessage("Unknown command.");
                continue;
            }
            // A new turn replaces any pending one; the server marks the old one stale.
            runtime.submitTurn(text, speechWav, eventType);
        }
        if (running) {
            runtime.tick();
        }
        if (inputClosed && !runtime.hasPending()) {
            running = false;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }
    // Quit drops late replies, actions and voice, and waits for the bounded workers.
    runtime.shutdown(quitMessage);
    return 0;
}

// --say, --listen and --react: one turn through the same runtime, then exit. The subtitle
// and actions are shown before any voice finishes.
int runOnce(TurnRuntime& runtime, const std::string& text, const std::filesystem::path& speechWav,
            const std::string& eventType)
{
    if (runtime.submitTurn(text, speechWav, eventType).empty()) {
        return 1;
    }
    while (!runtime.idle()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
        runtime.tick();
    }
    runtime.shutdown("");
    return runtime.lastTurnOk() ? 0 : 1;
}

}  // namespace

int wmain(int argc, wchar_t** argv)
{
    SetConsoleOutputCP(CP_UTF8);

    std::vector<std::string> args;
    for (int i = 1; i < argc; ++i) {
        args.push_back(toUtf8(argv[i]));
    }
    if (args.size() == 1 && args[0] == "--version") {
        std::cout << "KagrenacClient " << kClientVersion << " (" << kClientBaseline << ", protocol 1)\n";
        return 0;
    }

    // Defaults, then the shared default file, then the private config.
    Config config;
    std::filesystem::path folder = exeFolder();
    std::filesystem::path privateConfig = folder / "config.json";
    std::string mode;
    std::string value;
    std::string eventType;
    for (size_t i = 0; i < args.size(); ++i) {
        bool hasValue = i + 1 < args.size();
        if (args[i] == "--config" && hasValue) {
            privateConfig = std::filesystem::u8path(args[++i]);
        } else if ((args[i] == "--say" || args[i] == "--listen" || args[i] == "--decide") && hasValue) {
            mode = args[i];
            value = args[++i];
        } else if ((args[i] == "--event" || args[i] == "--react") && i + 2 < args.size()) {
            mode = args[i];
            eventType = args[++i];
            value = args[++i];
        } else if (args[i] == "--health") {
            mode = args[i];
        } else {
            std::cerr << "Unknown argument: " << args[i] << "\n";
            return 2;
        }
    }

    std::string error;
    if (!loadConfigFile(folder / "config.default.json", config, error)
        || !loadConfigFile(privateConfig, config, error)) {
        std::cerr << "Config error: " << error << "\n";
        return 2;
    }
    if (config.token.empty()) {
        std::cerr << "No token set. Copy config.default.json to config.json next to the exe and paste the\n"
                     "token from the server's config/config.php, or pass --config <file>.\n";
        return 2;
    }

    const AiClient client(config);
    ConsoleGame game;

    if (mode == "--health") {
        std::string note;
        std::string info;
        std::string problem = client.health(&note, &info);
        if (!problem.empty()) {
            std::cout << "Server problem: " << problem << "\n";
            return 1;
        }
        std::cout << "Server is ready.\n";
        std::cout << "Versions: client " << kClientVersion << ", client baseline " << kClientBaseline << ", " << info
                  << ", protocol 1.\n";
        if (!note.empty()) {
            std::cout << "Note: " << note << "\n";
        }
        return 0;
    }
    if (mode == "--event") {
        TurnResult result = client.sendEvent(newRequestId("evt"), game.readContext(), eventType, value, false);
        game.showMessage(describeLoggedEvent(result, eventType));
        return result.ok ? 0 : 1;
    }
    if (mode == "--decide") {
        std::string message = describeDecision(client, value);
        game.showMessage(message);
        return message.rfind("Decision:", 0) == 0 ? 0 : 1;
    }

    TurnRuntime runtime(game, config, kConsoleReportSource);
    addConsoleHandlers(runtime, game);
    if (mode == "--say" || mode == "--react") {
        return runOnce(runtime, value, {}, eventType);
    }
    if (mode == "--listen") {
        return runOnce(runtime, "", std::filesystem::u8path(value), "");
    }
    return runInteractive(runtime, game, game);
}
