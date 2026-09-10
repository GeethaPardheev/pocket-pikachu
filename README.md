# Pocket Pikachu ⚡

An ultra-realistic Pikachu desk companion for macOS. It types alongside you, plays ball, dances, fires Thunderbolt, naps, and reminds you to focus, stretch and walk. Clicking it never opens a window.

**Author: Geetha Pardheev**

Built on the desk-pet companion originally written by Gopal Goyal and Saksham Batta; see [AUTHORS.md](AUTHORS.md).

## Requirements

- macOS 13 or later. Developed and tested on Apple Silicon; the build script targets the current Mac's architecture. Intel builds have not been tested.
- Apple Xcode Command Line Tools (`xcode-select --install`).
- No third-party packages, API keys, accounts, or network services are needed at runtime.

## Build and run

```bash
git clone https://github.com/GeethaPardheev/pocket-pikachu.git
cd pocket-pikachu
./scripts/build.sh
./scripts/run.sh
```

You can also double-click `build/Pocket Pikachu.app` in Finder. The app appears as a floating Pikachu with a paw icon in the menu bar, without a Dock icon. Keep the full app bundle together. Quit an existing copy before rebuilding or running a copy from another location.

The script compiles Swift against AppKit, ApplicationServices, and CoreAudio, packages all sprite frames, and applies a local ad-hoc signature. This is not a notarized distribution. Building on your own Mac is the supported setup; downloaded binaries may require macOS approval.

To rebuild after changes, quit Pikachu, run `./scripts/build.sh`, then `./scripts/run.sh`. macOS may require renewing Accessibility permission after a rebuild or moving the app.

## Enable typing detection

1. Right-click Pikachu and leave **Typing reactions** checked.
2. Choose **Open keyboard permission settings…**.
3. In System Settings → Privacy & Security → Accessibility, add the exact `build/Pocket Pikachu.app` you launched and enable it.
4. Type in a normal text editor. The menu's typing status indicates whether permission is missing, it is waiting for keys, or it has received keys.

Permission is checked every second. Relaunch if macOS requests it. If the switch is on but the menu still says permission is needed, remove the old Accessibility entry with **−**, add the current app with **+**, and enable it. A prior build's authorization may no longer match.

**Preview typing** tests the animation without keyboard permission. Secure-input/password fields may suppress keyboard events. “Receiving keys” means this session has received keyboard activity, not necessarily that keys are being pressed at that instant.

## Features and controls

Right-click Pikachu or click the menu-bar paw to access all controls.

- **Cursor tracking:** the Pikachu sprite set has no head-turn frames, so Pikachu idles and blinks instead of following the cursor. The tracking code and the Pause cursor following toggle remain for sprite sets that include the sixteen gaze frames.
- **Typing:** alternating paws and a little keyboard; faster typing produces faster taps and “Turbo paws”. Returns to normal after 0.7 seconds without detected keys. Typing interrupts temporary petting/stretch animations and appears during focus; a short active chase/pounce finishes first.
- **Click and drag:** click to wave, double-click to jump, drag to reposition. Position is saved. Small, Large, Extra large and Huge change size for this session; Reset position brings Pikachu to the visible screen.
- **Petting:** rub the pointer across its head for closed eyes and a heart. Pet Pocket Pikachu triggers it manually.
- **Treats:** Give a fish treat, then click the fish for a short pounce and return. Unused fish disappear after 20 seconds.
- **Sleep:** automatic nap after 3 minutes without mouse movement or detected typing; movement/typing wakes it. Nap now is available. Music mode prevents automatic idle naps.
- **Cursor play:** occasional short chases when the moving cursor is nearby, with at least 75 seconds between automatic attempts. Disable Occasional cursor play or trigger Play with cursor manually.
- **Fun dance:** an eight-second dance that bounces and sways through every action pose in the sprite set, from the menu.
- **Thunderbolt:** plays sprite row 8 for about two seconds with a “Pika… CHUUU!” caption, from the menu.
- **Play ball:** a red-and-white Poké Ball-style ball sits at Pikachu's paws. Pikachu swats it, the ball rolls off spinning and slowing to a stop, and Pikachu runs after it while it is still rolling. This repeats five to seven times (random per game); each roll covers 20–30% of the screen width in a random direction that stays on screen, so the path wanders like a screensaver. Then Pikachu trots straight back to exactly where it started and the ball disappears. The cat moves at a steady pace, so longer runs take longer, up to 4 seconds. Dragging Pikachu or starting focus ends the game where it stands.
- **Focus reminders:** enabled by default, every 30 minutes while running. “Hey. Time to focus.” displays for 30 seconds with a brief attention animation (sprite row 8). Skipped while a focus session is already running. Preview focus reminder triggers it immediately. Toggle in the menu.
- **Walking reminders:** enabled by default, every 20 minutes while running. “Stand up & take a short walk” displays for 30 seconds, including during focus and pet naps. Preview walk reminder triggers it immediately. Toggle reminders in the menu.
- **Stretch reminders:** every 30 minutes while awake, with a brief paw-up animation. Focus and sleep defer these reminders. Stretch now is available.
- **Focus:** start 25-minute or 5-minute sessions, or try a 10-second preview. Pikachu naps, shows a countdown, and jumps when done. Cancel from the menu.
- **Homes:** choose a cushion, cardboard box, or no home. Pikachu settles lower in its box during sleep/petting.
- **Headphones:** automatic mode checks whether the default audio output device is active. It cannot distinguish music from notifications, silent streams, or apps keeping audio open. Manual music mode works with any player. Head bobbing is decorative, not synchronized to beats. The headphone drawing positions were fitted to the original cat sprites and may sit oddly on Pikachu.
- **Sounds:** optional synthesized purr and completion/reminder chime. Sounds and purring is off by default.

## Timing, preferences, and limitations

The companion must be running for reminders. There are no scheduled background jobs or automatic login startup items. Restarting begins fresh countdowns; missed walk reminders do not queue up. Re-enabling walk reminders starts a fresh 20 minutes; re-enabling focus reminders starts a fresh 30 minutes. Focus timing uses system uptime and is not intended as an alarm while the Mac is asleep.

Position, typing toggle, automatic nap/play/reminder toggles, sound preference, home, and automatic audio mode use macOS UserDefaults. Size, manual headphones, cursor pause, and active focus timers are session-only.

If Pikachu is hidden, use **paw menu → Reset position**. If you see two Pikachus, quit the other standalone copy. This app currently has no single-instance enforcement across different bundle copies.

## Privacy

The keyboard handlers observe event timing only: they do not read characters/key codes, record typed text, or send it anywhere. Turning typing reactions off removes the keyboard monitors. Cursor tracking reads pointer coordinates. Audio detection reads device-running state; it does not use the microphone or record audio. Preferences stay on the Mac. Runtime code does not make network requests.

## Tests and visual preview

```bash
./scripts/test.sh
"build/Pocket Pikachu.app/Contents/MacOS/PocketPikachu" --render-gallery "$PWD/build/features-preview.png"
```

Tests cover the sixteen gaze directions, compass/deadzone cases, typing expiry and cadence/storage, sleep/wake, focus completion, reminder timing and disabled behavior, excursion return, ball-game run counting and return home, and sprite availability. `"build/Pocket Pikachu.app/Contents/MacOS/PocketPikachu" --play-smoke` runs a real ball game, dance, and focus reminder in the live app loop and checks Pikachu returns to its starting point; it briefly shows a second cat. Gallery rendering requires a logged-in macOS GUI session. Real cross-app typing requires user-granted Accessibility permission; deterministic tests do not prove that system permission is granted.

Optional startup diagnostics (no typed text):

```bash
# Quit the running Pikachu first.
open "build/Pocket Pikachu.app" --args --diagnostics "$PWD/build/typing-diagnostics.txt"
```

This records permission, enabled state, and monitor installation at startup; it is not a live-updating report.

## Source layout

- `Sources/main.swift`: native AppKit window, rendering, input monitoring, behavior state, audio-state detection, and self-tests.
- `Resources/frames/`: the 73 Pikachu frames, named `row-col.png`: row 0 idle, 1 run right, 2 run left, 3 wave, 4 jump, 5 sad, 6 waiting, 7 busy, 8 Thunderbolt, and rows 9–10 (gaze slots) that reuse idle frames.
- `Resources/Info.plist`: application metadata.
- `scripts/`: reproducible build, run, and test commands.

Build products, local diagnostics, temporary generation files, and caches are excluded from version control.

## Artwork and trademark

The Pikachu frames were generated with Google's Gemini image model from a community-made Codex pet as the pose reference, then chroma-keyed and sliced into the sprite grid. Pikachu is a trademark of Nintendo, Game Freak and The Pokémon Company. This is an unofficial fan project for personal desktop use and is not affiliated with or endorsed by them.

See [AUTHORS.md](AUTHORS.md) for credits.

## Contribution and approval policy

All changes to `main` require a pull request, code-owner approval, passing macOS checks, and resolved review conversations. Direct pushes, force pushes, and branch deletion are blocked by repository protection, including for administrators. See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

This repository is publicly readable; public visibility permits viewing and forking, not editing this repository. Its owner can manage access and change protection settings. No open-source license has been selected for this project.

## Terminal notifications (zsh)

Source the integration from your `~/.zshrc`, using the absolute path to this checkout:

```zsh
source /absolute/path/to/pocket-pikachu/integrations/pocket-pikachu.zsh
```

Open a new terminal tab, or run that source command in an existing zsh tab. This works in IDE terminals that start interactive zsh and load that configuration, as well as standalone terminals. Bash, fish, remote hosts, containers, and IDE task runners that do not load this shell configuration are not automatically covered.

Failures are reported when the shell returns to its prompt. Successful commands are reported if they ran for at least three seconds. For explicit input/approval requests, run `pika-help` before the waiting operation. Arbitrary prompts are not inferred from terminal output. A foreground command still running cannot automatically report its own need for input unless it explicitly integrates this signal.

Pikachu displays an alert for 12 seconds and retains the latest 12 alerts under Recent terminal activity. Terminal notifications can be disabled in its menu. Alerts identify the terminal device (for example ttys001); exact IDE-tab activation is not implemented.

Only event kind, numeric exit code, elapsed seconds, timestamp, terminal device label, and coarse terminal application category are written locally. No command text, arguments, working directory, terminal output, or credentials are captured. Events use private files under `~/Library/Application Support/PocketPikachu/events`, overwritten per shell process. The companion reads bounded files once per second and ignores stale events. Very rapid events from the same shell can be coalesced. This is a local convenience notification channel, not a security audit log; another process running as your user can write to it.

Try `sleep 3`, then `false`, then `pika-help`. To uninstall, remove the source line from `.zshrc` and start fresh terminal tabs. Existing tabs retain their hooks until closed. The integration does not execute commands on your behalf.

## Terminals above the pet

The Agent Desk, process scan, connected-agent cards, and personal-assistant/AI chat have been removed. Terminal Desk stays closed until you choose **Open terminals** from the right-click or paw menu; clicking Pikachu never opens a window. It appears above the pet. The title shows the number of open tabs. Each tab is an independent terminal; switch tabs to view its output.

- Type `claude` normally, just as in another terminal. No special launcher is needed for using Claude here.
- **+ Terminal** starts another independent zsh session in your home folder.
- **+ In folder…** lets you choose the working directory for a new tab.
- Drag a window edge to resize, or click **Expand** to zoom. Shell rows/columns update with the view.
- Use the tabs to switch between sessions. **Copy** copies selected terminal text; **Paste** uses the terminal's paste handling.
- Closing the terminal window hides it and keeps sessions running. Use **Open terminals** to reopen it.
- **End tab** asks before closing its shell. Quitting the pet closes all of its terminal sessions. Commands may be interrupted; save your work first.

This is an interactive zsh terminal, not an AI command interpreter. Commands you type have your normal account access and run immediately, just like a normal terminal. The app neither auto-approves Claude prompts nor supplies commands on your behalf. Your ordinary shell startup files and history settings apply. Embedded terminal scrollback stays in memory (3,000 lines); it is not added to a separate pet transcript. Existing optional pikachu-claude launcher sessions still work separately.

Rendering uses locally bundled xterm.js 5.5.0 and addon-fit 0.10.0, with their MIT licenses in Resources/terminal. No CDN or local network server is used. A Python helper owns each pseudo-terminal over private process pipes. The web view is limited to its bundled page, blocks network content, and receives output as bytes rather than HTML. Python and WebKit are needed at runtime, in addition to the macOS requirements above.

Tests: `PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 tests/test_terminal_host.py` verifies shell execution, resize, Ctrl-C, tab isolation, and shutdown using harmless commands. A logged-in GUI session can run `"build/Pocket Pikachu.app/Contents/MacOS/PocketPikachu" --terminal-smoke "$PWD/build/terminal-preview.png"` to verify real shell output reaches the embedded renderer. These tests require PTY access.

## Gemini Live voice for pet terminals

Click **Voice** in Terminal Desk. Enter a Gemini API key in the secure field (never in source code or chat), keep the suggested Live model or enter one available to your account, and click **Start voice**. Grant macOS microphone permission when asked. The key is saved in macOS Keychain, not preferences, source, or logs. Use **Forget saved key** in voice settings to remove it. macOS may request Keychain access after an app update. Google API billing/quota applies; a consumer Gemini subscription is not automatically an API credential.

To allow actions, enable **Allow voice to control this pet’s terminals**. Try:

- “List my terminals.”
- “Create a new terminal.”
- “In terminal 2, type claude and press Enter.”
- “Send hello to terminal 2 without pressing Enter.”
- “Send Control-C to terminal 2.”
- “Press Escape in terminal 2.”

IDs are the stable numbers shown in the tab labels for this app run. New tabs start in your home directory. Only ready, running tabs created by the pet can receive input. Input is a single line, up to 16 KB; control characters are rejected except the separately implemented Enter and interrupt keys. A queued input result does not mean its command succeeded. Claude-specific interactive prompts remain Claude’s responsibility; the voice feature does not auto-approve them. Commands spoken and submitted have your normal terminal permissions. Watch the selected terminal to see actions and their output. Disable terminal control when only chatting.

**Mute** stops sending microphone chunks while leaving the connection/audio engine open; **Stop** disconnects and releases audio capture/playback. Closing settings leaves voice running in the pet bar. **End**, the **Stop** button, saying “hang up”, or quitting the pet stops voice. No background listening starts at launch. Talking over Gemini clears its queued reply audio when the server reports interruption. Use headphones if your audio device's echo cancellation is unavailable. Reconnect after session expiry or device/network failures; session resumption is not implemented.

Scope is intentionally limited to listing/creating pet terminals, sending requested text, and Ctrl-C/Escape. It has no access to external terminal windows, files, or pet configuration. With **Share recent pet terminal output with Gemini** enabled, changed snapshots are sent every four seconds: up to eight tabs, the last 60 rendered lines and at most 4,000 characters per tab. This can include private terminal text; disable sharing to stop future snapshots (already sent context remains in the current session). Snapshots may be truncated or stale. Terminal context is untrusted data and cannot authorize commands. The voice stream, transcription, tool definitions, terminal IDs/folder labels, and tool results are exchanged with Google while connected. Audio/transcripts are not saved to disk; there is no conversation UI. Google's service data policies still apply. The app keeps a per-session tool-call cache so duplicate IDs do not repeat actions and ignores cancelled or post-disconnect calls.

Implementation: native AVAudioEngine microphone/playback and an ephemeral URLSession WebSocket to Google's Live API. Sends 16-bit PCM at the input device's reported rate (Gemini supports resampling) and plays 24 kHz PCM replies. Uses `gemini-3.1-flash-live-preview` by default; preview availability can change. No extra package or server is required.

Validation: native build/self-tests include tool argument validation. `"build/Pocket Pikachu.app/Contents/MacOS/PocketPikachu" --voice-tool-smoke` uses synthetic model calls and real owned shell tabs to test disabled control, stable target routing, duplicate suppression, actual shell delivery, cancellation, and the stop gate. It makes no Gemini request and does not open the microphone. Live authentication, speech recognition, microphone hardware, and reply playback require testing with your key and devices.

Protocol references: [Google Live WebSocket reference](https://ai.google.dev/api/live) and [Live API capabilities](https://ai.google.dev/gemini-api/docs/live-api/capabilities).

The **Voice** button beneath Pikachu opens setup the first time; after saving a key it starts voice directly. The compact bar shows connection, incoming/outgoing audio packet activity, and mute state. **Mute** toggles the microphone stream; **End** hangs up; **⚙** opens settings. Terminal controls and context sharing are enabled by default for the requested assistant workflow and can be disabled in settings. The Terminal Desk toolbar opens settings. Clear spoken commands execute without repeated confirmation; Gemini asks when the target or destructive action is ambiguous.

Audio startup uses the output device’s native format and retries without echo cancellation if voice processing fails. Use headphones when the fallback notice appears. If both attempts fail, the voice window shows the native error domain/code; select working input and output devices in macOS Sound settings and retry.
