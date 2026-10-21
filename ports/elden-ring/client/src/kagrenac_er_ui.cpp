// UI thread: a message-only window for timers and worker results, and the
// conversation box, a plain Win32 window owned by the game's window. The box is a mod-owned
// window over the game, not drawn in the game's frame. F8 is polled only while a window of
// this process is in front; Enter sends, Esc cancels and closes, closing never unloads. One line
// above the status shows the game link and the last order's answer, apart from the reply.
#include "kagrenac_er.h"

#include <mmsystem.h>

#include <algorithm>

namespace kagrenac_er {
namespace {

constexpr wchar_t kMessageClass[] = L"KagrenacER_Messages";
constexpr wchar_t kBoxClass[] = L"KagrenacER_ConversationBox";
constexpr UINT_PTR kHotkeyTimer = 1;
constexpr UINT_PTR kWatchdogTimer = 2;
constexpr UINT kHotkeyPollMs = 50;
constexpr int kHotkey = VK_F8;
constexpr int IDC_LABEL = 101, IDC_INPUT = 102, IDC_REPLY_LABEL = 103, IDC_REPLY = 104, IDC_STATUS = 105,
              IDC_LINK = 106;

// The configured npc_name, final before the UI thread starts.
std::wstring npcName()
{
    return toWide(context().npcName);
}

// UI thread only. Heap, never freed (process lifetime).
struct Ui {
    HWND messages = nullptr;
    HWND box = nullptr, owner = nullptr;
    HWND label = nullptr, input = nullptr, replyLabel = nullptr, reply = nullptr, status = nullptr, link = nullptr;
    HFONT font = nullptr;
    bool hotkeyWasDown = true;  // ignore a key already held when polling starts
    uint64_t watched = 0;       // generation the watchdog runs for, 0 when idle
    bool textShown = false;     // the watched line already has its reply text
    std::wstring you;           // the watched line, as shown
    std::wstring transcript;    // kept so a recreated box shows the last exchange
    std::wstring statusText = L"Enter sends. Esc cancels, asks " + npcName() + L" to hold, closes. F8 hides.";
    std::wstring linkText = L"Game link: not verified yet; " + npcName() + L" cannot act in the game.";
    std::string audio;          // owned until playback is stopped or replaced
};
Ui* g_ui = nullptr;

bool ownedByThisProcess(HWND window)
{
    DWORD pid = 0;
    return window && GetWindowThreadProcessId(window, &pid) && pid == GetCurrentProcessId();
}

// A console attached to the game reports this process too; it never owns the box.
bool isConsole(HWND window)
{
    wchar_t cls[32] = {};
    return GetClassNameW(window, cls, 32) && wcscmp(cls, L"ConsoleWindowClass") == 0;
}

// The game window: the root owner of the foreground window when that is ours, else the
// largest visible unowned top-level window of this process.
struct Search {
    HWND best = nullptr;
    long long area = 0;
};
BOOL CALLBACK considerWindow(HWND window, LPARAM param)
{
    auto* search = reinterpret_cast<Search*>(param);
    RECT r{};
    if (window != g_ui->box && ownedByThisProcess(window) && IsWindowVisible(window) && !GetWindow(window, GW_OWNER)
        && !isConsole(window) && GetWindowRect(window, &r)) {
        long long area = static_cast<long long>(r.right - r.left) * (r.bottom - r.top);
        if (area > search->area) {
            search->best = window;
            search->area = area;
        }
    }
    return TRUE;
}
HWND findGameWindow()
{
    HWND front = GetForegroundWindow();
    if (ownedByThisProcess(front)) {
        HWND root = GetAncestor(front, GA_ROOTOWNER);
        if (root && root != g_ui->box && root != g_ui->messages && !isConsole(root)) {
            return root;
        }
    }
    Search search;
    EnumWindows(considerWindow, reinterpret_cast<LPARAM>(&search));
    return search.best;
}

int scaled(int value, UINT dpi)
{
    return MulDiv(value, static_cast<int>(dpi), 96);
}

UINT windowDpi(HWND window)
{
    UINT dpi = window ? GetDpiForWindow(window) : 0;
    return dpi ? dpi : 96;
}

void setStatus(const std::wstring& text)
{
    g_ui->statusText = text;
    if (g_ui->status) {
        SetWindowTextW(g_ui->status, text.c_str());
        NotifyWinEvent(EVENT_OBJECT_NAMECHANGE, g_ui->status, OBJID_CLIENT, CHILDID_SELF);
    }
}

void setLink(const std::wstring& text)
{
    g_ui->linkText = text;
    if (g_ui->link) {
        SetWindowTextW(g_ui->link, text.c_str());
        NotifyWinEvent(EVENT_OBJECT_NAMECHANGE, g_ui->link, OBJID_CLIENT, CHILDID_SELF);
    }
}

void setTranscript(const std::wstring& text)
{
    g_ui->transcript = text;
    if (g_ui->reply) {
        SetWindowTextW(g_ui->reply, text.c_str());
    }
}

// Reply text from the server uses \n; edit controls need \r\n.
std::wstring forEdit(const std::string& utf8)
{
    std::wstring in = toWide(utf8), out;
    out.reserve(in.size() + 16);
    for (wchar_t c : in) {
        if (c == L'\n') {
            out += L"\r\n";
        } else if (c != L'\r') {
            out += c;
        }
    }
    return out;
}

void stopAudio()
{
    if (!g_ui->audio.empty()) {
        PlaySoundW(nullptr, nullptr, 0);  // stops our async sound before its buffer goes
        g_ui->audio.clear();
    }
}

void stopWatchdog()
{
    g_ui->watched = 0;
    KillTimer(g_ui->messages, kWatchdogTimer);
}

void layout()
{
    UINT dpi = windowDpi(g_ui->box);
    RECT client{};
    GetClientRect(g_ui->box, &client);
    int pad = scaled(8, dpi), line = scaled(20, dpi), edit = scaled(24, dpi);
    int width = client.right - 2 * pad;
    int y = pad;
    MoveWindow(g_ui->label, pad, y, width, line, TRUE);
    y += line;
    MoveWindow(g_ui->input, pad, y, width, edit, TRUE);
    y += edit + pad;
    MoveWindow(g_ui->replyLabel, pad, y, width, line, TRUE);
    y += line;
    int statusTop = client.bottom - pad - line, linkTop = statusTop - line;
    MoveWindow(g_ui->reply, pad, y, width, linkTop - pad - y, TRUE);
    MoveWindow(g_ui->link, pad, linkTop, width, line, TRUE);
    MoveWindow(g_ui->status, pad, statusTop, width, line, TRUE);
}

void applyFont()
{
    UINT dpi = windowDpi(g_ui->box);
    HFONT font = CreateFontW(-MulDiv(10, static_cast<int>(dpi), 72), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                             DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                             DEFAULT_PITCH, L"Segoe UI");
    for (HWND child : {g_ui->label, g_ui->input, g_ui->replyLabel, g_ui->reply, g_ui->link, g_ui->status}) {
        SendMessageW(child, WM_SETFONT, reinterpret_cast<WPARAM>(font ? font : GetStockObject(DEFAULT_GUI_FONT)), TRUE);
    }
    if (g_ui->font) {
        DeleteObject(g_ui->font);
    }
    g_ui->font = font;
}

// Near the bottom centre of the game window, kept inside that monitor's work area.
void placeBox()
{
    UINT dpi = windowDpi(g_ui->owner);
    int width = scaled(560, dpi), height = scaled(280, dpi);
    MONITORINFO monitor{sizeof(monitor)};
    GetMonitorInfoW(MonitorFromWindow(g_ui->owner, MONITOR_DEFAULTTOPRIMARY), &monitor);
    RECT area = monitor.rcWork;
    RECT game{};
    if (IsIconic(g_ui->owner) || !GetWindowRect(g_ui->owner, &game)) {
        game = area;
    }
    int x = (game.left + game.right - width) / 2;
    int y = game.bottom - height - scaled(48, dpi);
    x = std::max(static_cast<int>(area.left), std::min(x, static_cast<int>(area.right) - width));
    y = std::max(static_cast<int>(area.top), std::min(y, static_cast<int>(area.bottom) - height));
    SetWindowPos(g_ui->box, nullptr, x, y, width, height, SWP_NOZORDER | SWP_NOACTIVATE);
}

void hideBox()
{
    if (!g_ui->box || !IsWindowVisible(g_ui->box)) {
        return;
    }
    ShowWindow(g_ui->box, SW_HIDE);
    // We are the foreground process here, so returning focus to the game is allowed.
    if (IsWindow(g_ui->owner)) {
        SetForegroundWindow(g_ui->owner);
    }
}

// Esc, the close button and Alt+F4: cancel what is pending, drop any unsent order and ask
// the companion to hold (only queued, never waited for), stop the voice, hide.
void cancelAndClose()
{
    bool busy = g_ui->watched != 0;
    if (busy) {
        invalidate("player closed the box");
        stopWatchdog();
        setStatus(L"Cancelled. Type a new line after F8.");
    } else {
        cancelOrders();
    }
    stopAudio();
    hideBox();
}

void submit()
{
    wchar_t buffer[kMaxInputChars + 1] = {};
    int length = GetWindowTextW(g_ui->input, buffer, kMaxInputChars + 1);
    std::wstring line(buffer, static_cast<size_t>(std::max(length, 0)));
    size_t first = line.find_first_not_of(L" \t\r\n"), last = line.find_last_not_of(L" \t\r\n");
    if (first == std::wstring::npos) {
        setStatus(L"Type something for " + npcName() + L" first.");
        return;
    }
    line = line.substr(first, last - first + 1);
    if (!context().notConnected.empty()) {
        setStatus(L"Not connected: " + toWide(context().notConnected) + L". Nothing was sent.");
        return;
    }
    // "/follow", "/hold", "/attack": straight to the game link, no model call, same allowlist.
    Order order = Order::Hold;
    bool command = exactCommand(line, order);
    if (command) {
        const char* name = kActionNames[static_cast<int>(order) - 1];
        const auto& allowed = context().allowedActions;
        if (std::find(allowed.begin(), allowed.end(), name) == allowed.end()) {
            setStatus(toWide(name) + L" is not in allowed_actions in config.json. Nothing was sent.");
            return;
        }
    }
    stopAudio();
    bool waits = false;
    g_ui->watched = submitLine(toUtf8(line), command ? static_cast<int>(order) : 0, waits);
    SetTimer(g_ui->messages, kWatchdogTimer, kLineBudgetMs, nullptr);
    SetWindowTextW(g_ui->input, L"");
    g_ui->you = L"You: " + line;
    g_ui->textShown = false;
    setTranscript(g_ui->you + (command ? L"\r\n\r\nGame order: ..." : L"\r\n\r\n" + npcName() + L": ..."));
    setStatus(waits     ? L"Waiting for the earlier request to return (it was cancelled)..."
              : command ? L"Asking the game..."
                        : npcName() + L" is thinking...");
}

LRESULT handleBox(HWND window, UINT message, WPARAM wParam, LPARAM lParam)
{
    switch (message) {
    case WM_NCDESTROY:
        // Also when the game window goes and takes its owned box along: no stale handles.
        if (window == g_ui->box) {
            g_ui->box = g_ui->label = g_ui->input = g_ui->replyLabel = g_ui->reply = g_ui->status = g_ui->link = nullptr;
        }
        break;
    case WM_COMMAND:
        if (LOWORD(wParam) == IDOK) {
            submit();
            return 0;
        }
        if (LOWORD(wParam) == IDCANCEL) {
            cancelAndClose();
            return 0;
        }
        break;
    case WM_CLOSE:
        cancelAndClose();  // hide, never destroy or unload
        return 0;
    case WM_SIZE:
        if (g_ui->status) {
            layout();
        }
        return 0;
    case WM_DPICHANGED: {
        auto* suggested = reinterpret_cast<const RECT*>(lParam);
        SetWindowPos(window, nullptr, suggested->left, suggested->top, suggested->right - suggested->left,
                     suggested->bottom - suggested->top, SWP_NOZORDER | SWP_NOACTIVATE);
        applyFont();
        layout();
        return 0;
    }
    case WM_ACTIVATE:
        if (LOWORD(wParam) != WA_INACTIVE && g_ui->input) {
            SetFocus(g_ui->input);
        }
        return 0;
    }
    return DefWindowProcW(window, message, wParam, lParam);
}

// No C++ exception may cross the Win32 callback boundary: drop the message instead.
LRESULT CALLBACK boxProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam)
{
    try {
        return handleBox(window, message, wParam, lParam);
    } catch (...) {
        OutputDebugStringA("kagrenac_er: box message dropped after an internal error\n");
        return 0;
    }
}

HWND child(const wchar_t* cls, const wchar_t* text, DWORD style, DWORD exStyle, int id)
{
    return CreateWindowExW(exStyle, cls, text, WS_CHILD | WS_VISIBLE | style, 0, 0, 0, 0, g_ui->box,
                           reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), GetModuleHandleW(nullptr), nullptr);
}

bool createBox(HWND owner)
{
    if (g_ui->box) {
        DestroyWindow(g_ui->box);  // the game window changed; children and their state go with it
        g_ui->box = g_ui->label = g_ui->input = g_ui->replyLabel = g_ui->reply = g_ui->status = g_ui->link = nullptr;
    }
    g_ui->owner = owner;
    std::wstring name = npcName();
    g_ui->box = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_CONTROLPARENT, kBoxClass, name.c_str(),
                                WS_POPUP | WS_CAPTION | WS_SYSMENU | WS_CLIPCHILDREN, 0, 0, 0, 0, owner, nullptr,
                                GetModuleHandleW(nullptr), nullptr);
    if (!g_ui->box) {
        log("ui: cannot create the box (error " + std::to_string(GetLastError()) + ")");
        return false;
    }
    // Labels come right before their fields so screen readers use them as names. An & in the
    // name is doubled, so it shows as itself and only S stays the access key.
    std::wstring label = L"&Say to ";
    for (wchar_t c : name) {
        label += c == L'&' ? std::wstring(L"&&") : std::wstring(1, c);
    }
    g_ui->label = child(L"STATIC", (label + L":").c_str(), SS_LEFT, 0, IDC_LABEL);
    g_ui->input = child(L"EDIT", L"", WS_TABSTOP | ES_AUTOHSCROLL, WS_EX_CLIENTEDGE, IDC_INPUT);
    g_ui->replyLabel = child(L"STATIC", L"&Conversation:", SS_LEFT, 0, IDC_REPLY_LABEL);
    g_ui->reply = child(L"EDIT", g_ui->transcript.c_str(),
                        WS_TABSTOP | WS_VSCROLL | ES_MULTILINE | ES_READONLY | ES_AUTOVSCROLL, WS_EX_CLIENTEDGE,
                        IDC_REPLY);
    g_ui->link = child(L"STATIC", g_ui->linkText.c_str(), SS_LEFT | SS_NOPREFIX | SS_ENDELLIPSIS, 0, IDC_LINK);
    g_ui->status = child(L"STATIC", g_ui->statusText.c_str(), SS_LEFT | SS_NOPREFIX | SS_ENDELLIPSIS, 0, IDC_STATUS);
    SendMessageW(g_ui->input, EM_LIMITTEXT, kMaxInputChars, 0);
    applyFont();
    log("ui: box created, owned by the game window");
    return true;
}

void showBox()
{
    HWND game = findGameWindow();
    if (!game) {
        log("ui: no visible window of this process to own the box");
        return;
    }
    if ((!g_ui->box || g_ui->owner != game || !IsWindow(g_ui->owner)) && !createBox(game)) {
        return;
    }
    placeBox();
    layout();
    ShowWindow(g_ui->box, SW_SHOW);
    SetForegroundWindow(g_ui->box);
    SetFocus(g_ui->input);
}

// Edge-triggered F8, only while a window of this process is in front: never a global hotkey.
void pollHotkey()
{
    bool down = (GetAsyncKeyState(kHotkey) & 0x8000) != 0;
    bool wasDown = g_ui->hotkeyWasDown;
    g_ui->hotkeyWasDown = down;
    if (!down || wasDown || !ownedByThisProcess(GetForegroundWindow())) {
        return;
    }
    if (g_ui->box && IsWindowVisible(g_ui->box)) {
        hideBox();
    } else {
        showBox();
    }
}

void onOutcome(Outcome* raw)
{
    std::unique_ptr<Outcome> outcome(raw);
    if (!isCurrent(outcome->generation) || outcome->generation != g_ui->watched) {
        log("ui: outcome for gen " + std::to_string(outcome->generation) + " is stale; not shown or played");
        return;
    }
    const std::wstring& you = g_ui->you;
    if (outcome->kind == Outcome::Order) {
        stopWatchdog();
        setTranscript(you + L"\r\n\r\nGame order " + toWide(outcome->reply));
        setStatus(outcome->ok ? L"The game event accepted it; that does not confirm " + npcName() + L" moved."
                              : L"No order was confirmed. The game keeps running.");
        return;
    }
    if (outcome->kind == Outcome::Text) {
        if (!outcome->ok) {
            stopWatchdog();
            setTranscript(you + L"\r\n\r\n" + npcName() + L" did not answer.");
            setStatus(L"Error: " + toWide(outcome->error) + L". The game keeps running; type again to retry.");
            return;
        }
        g_ui->textShown = true;
        setTranscript(you + L"\r\n\r\n" + npcName() + L": " + forEdit(outcome->reply));
        setStatus(L"Getting " + npcName() + L"'s voice...");
        return;
    }
    stopWatchdog();
    if (!outcome->ok) {
        setStatus(L"Text only: voice unavailable (" + toWide(outcome->error) + L").");
        return;
    }
    stopAudio();
    g_ui->audio = std::move(outcome->wav);
    if (PlaySoundW(reinterpret_cast<LPCWSTR>(g_ui->audio.data()), nullptr, SND_MEMORY | SND_ASYNC | SND_NODEFAULT)) {
        setStatus(npcName() + L" is speaking. Esc stops and closes; F8 hides.");
    } else {
        g_ui->audio.clear();
        setStatus(L"Text only: Windows could not play the voice.");
        log("ui: PlaySound failed");
    }
}

void onWatchdog()
{
    uint64_t watched = g_ui->watched;
    stopWatchdog();
    if (watched == 0 || !isCurrent(watched)) {
        return;
    }
    invalidate("line budget");
    std::wstring budget = std::to_wstring(kLineBudgetMs / 1000) + L" s";
    setStatus(g_ui->textShown ? L"Voice did not arrive within " + budget + L"; text only. The game keeps running."
                              : L"No reply within " + budget + L"; the line was cancelled. The game keeps running.");
}

LRESULT handleMessages(HWND window, UINT message, WPARAM wParam, LPARAM lParam)
{
    if (message == WM_TIMER && wParam == kHotkeyTimer) {
        pollHotkey();
        return 0;
    }
    if (message == WM_TIMER && wParam == kWatchdogTimer) {
        onWatchdog();
        return 0;
    }
    if (message == kMsgOutcome) {
        onOutcome(reinterpret_cast<Outcome*>(lParam));
        return 0;
    }
    if (message == kMsgNote) {
        std::unique_ptr<std::wstring> text(reinterpret_cast<std::wstring*>(lParam));
        setLink(*text);
        return 0;
    }
#ifdef KAGRENAC_ER_TEST_HOST
    if (message == kMsgTestShow) {
        showBox();
        return 0;
    }
#endif
    return DefWindowProcW(window, message, wParam, lParam);
}

LRESULT CALLBACK messageProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam)
{
    try {
        return handleMessages(window, message, wParam, lParam);
    } catch (...) {
        OutputDebugStringA("kagrenac_er: message dropped after an internal error\n");
        return 0;
    }
}

}  // namespace

void runUiThread()
{
    g_ui = new (std::nothrow) Ui();
    if (!g_ui) {
        log("ui: out of memory; no box");
        return;
    }
    HINSTANCE instance = GetModuleHandleW(nullptr);
    WNDCLASSEXW messageClass{sizeof(messageClass)};
    messageClass.lpfnWndProc = messageProc;
    messageClass.hInstance = instance;
    messageClass.lpszClassName = kMessageClass;
    WNDCLASSEXW boxClass{sizeof(boxClass)};
    boxClass.lpfnWndProc = boxProc;
    boxClass.hInstance = instance;
    boxClass.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    boxClass.hbrBackground = GetSysColorBrush(COLOR_BTNFACE);
    boxClass.lpszClassName = kBoxClass;
    if (!RegisterClassExW(&messageClass) || !RegisterClassExW(&boxClass)) {
        log("ui: cannot register window classes (error " + std::to_string(GetLastError()) + ")");
        return;
    }
    g_ui->messages = CreateWindowExW(0, kMessageClass, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr, instance, nullptr);
    if (!g_ui->messages || !SetTimer(g_ui->messages, kHotkeyTimer, kHotkeyPollMs, nullptr)) {
        log("ui: cannot create the message window or hotkey timer (error " + std::to_string(GetLastError()) + ")");
        return;
    }
    {
        std::lock_guard<std::mutex> lock(context().mutex);
        context().messageWindow = g_ui->messages;
    }
    log("ui: ready");

    MSG msg;
    while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
        // Dialog keys in the box: Tab moves, Enter is IDOK, Esc is IDCANCEL.
        if (g_ui->box && IsDialogMessageW(g_ui->box, &msg)) {
            continue;
        }
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
}

}  // namespace kagrenac_er
