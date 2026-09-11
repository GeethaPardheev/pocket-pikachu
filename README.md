# Pocket Pikachu ⚡

A realistic Pikachu that lives on your Mac desktop. It types along with you, plays ball, dances, fires Thunderbolt, naps, and reminds you to focus, stretch and walk. Clicking it never opens a window.

**Author: Geetha Pardheev.** Built on the desk-pet companion originally written by Gopal Goyal and Saksham Batta; see [AUTHORS.md](AUTHORS.md).

## Requirements

- macOS 13 or later. Built and tested on Apple Silicon; Intel is untested.
- Xcode Command Line Tools (`xcode-select --install`).
- Nothing else. The pet needs no accounts, keys or network. The built-in terminals use the Python and WebKit that ship with macOS.

## Build and run

```bash
git clone https://github.com/GeethaPardheev/pocket-pikachu.git
cd pocket-pikachu
./scripts/build.sh
./scripts/run.sh
```

Or double-click `build/Pocket Pikachu.app`. Pikachu floats on the desktop with a paw icon in the menu bar and no Dock icon. Keep the app bundle together, and quit a running copy before rebuilding. The build is ad-hoc signed, not notarized, so macOS may ask you to renew the Accessibility permission after a rebuild or a move.

## Typing detection (optional)

Pikachu taps along when you type. That needs Accessibility permission:

1. Right-click Pikachu, keep **Typing reactions** on, and choose **Open keyboard permission settings…**.
2. In Privacy & Security → Accessibility, add the exact `build/Pocket Pikachu.app` you launched and turn it on.
3. Type anywhere. The menu shows whether permission is missing, waiting for keys, or receiving keys.

If it still says permission is needed after a rebuild, remove the old entry and add the new one. **Preview typing** shows the animation without permission. Password fields may not report keys. The app only learns that a key was pressed, never which one.

## What Pikachu does

Everything is in the right-click menu, or under the paw in the menu bar.

**Play**

- **Play ball.** A Poké Ball appears at its paws. Pikachu swats it, the ball rolls off spinning and slowing down, and Pikachu gallops after it. Five to seven rolls per game, each 20–30% of the screen width in a random direction, then it trots back to exactly where it started. Dragging Pikachu or starting a focus session ends the game.
- **Fun dance.** Eight seconds of bouncing through every pose in the sprite set.
- **Thunderbolt.** A two-second attack with a “Pika… CHUUU!” caption.
- **Play with cursor.** A short chase toward the pointer. Pikachu also does this on its own when the cursor moves nearby, at most once every 75 seconds. **Occasional cursor play** turns that off.
- **Give a fish treat.** A fish appears; click it and Pikachu pounces on it and comes back. Uneaten fish vanish after 20 seconds.
- **Pet Pocket Pikachu**, or rub the pointer over its head, for closed eyes and a heart.
- **Wave**, **Jump**, **Thinking.** One-off animations. A single click waves, a double-click jumps, and dragging moves it. The position is saved.

**Reminders** (on by default, each with a toggle and a preview in the menu)

- **Focus**, every 30 minutes: “Hey. Time to focus.” for 30 seconds, with a Thunderbolt. Skipped while a focus session is running.
- **Walk**, every 20 minutes: “Stand up & take a short walk” for 30 seconds, even during focus or naps.
- **Stretch**, every 30 minutes while awake, with a paw-up stretch. Deferred during focus and sleep. **Stretch now** triggers it.

**Focus timer.** Start a 25-minute or 5-minute session, or a 10-second preview. Pikachu naps with a countdown and jumps when it ends. Cancel from the menu.

**Everyday behaviour**

- **Typing.** Pikachu sits behind a little laptop and types with alternating paws; the faster you type, the faster it goes, up to “Turbo paws”. Stops 0.7 seconds after the last key.
- **Naps** after 3 minutes without mouse or keyboard activity; any movement wakes it. **Nap now** forces one. Music mode prevents automatic naps.
- **Homes.** Cushion, cardboard box, or none. Pikachu settles into the box when sleeping or being petted.
- **Headphones.** Pikachu puts on a pair of black over-ear headphones while your Mac is playing audio (it can't tell music from notifications), or when you turn on music mode. They show in the idle and typing poses; other poses play without them.
- **Sounds.** Optional purr and chime, off by default.
- **Facing.** Pikachu always faces into the screen: on the left half of the display its poses are mirrored to face right.
- **Size.** Small, Large (the default), Extra large, Huge. A chosen size lasts for the session. **Reset position** brings Pikachu back on screen.
- **Cursor tracking.** This sprite set has no head-turn frames, so Pikachu idles and blinks instead of following the pointer. **Pause cursor following** therefore has no visible effect.

## Good to know

- Reminders fire only while the app is running. There are no background jobs or login items, and restarting resets every countdown. Focus timing uses system uptime, so it is not an alarm while the Mac sleeps.
- Saved between launches: position, typing toggle, nap, play and reminder toggles, sounds, home, automatic headphones. Session only: size, manual headphones, cursor pause, a running focus timer.
- Two Pikachus means two copies are running; quit one. There is no single-instance check.

## Privacy

The keyboard monitors see timing only, never characters or key codes, and turning typing reactions off removes them. Cursor position is read only for petting and cursor play. Audio detection reads whether the output device is active; no microphone, no recording. Preferences stay on the Mac. The pet itself makes no network requests. Only the optional voice feature below talks to Google, and only while you have turned it on.

## Terminal notifications (zsh, optional)

Add this line to `~/.zshrc`, then open a new tab or source it in the current one:

```zsh
source /absolute/path/to/pocket-pikachu/integrations/pocket-pikachu.zsh
```

It works in any interactive zsh, including IDE terminals that load your zshrc. Bash, fish, remote hosts and containers are not covered.

- A failed command, or a successful one that ran 3 seconds or more, shows a 12-second alert on Pikachu. The last 12 appear under **Recent terminal activity**. **Terminal notifications** turns them off.
- Run `pika-help` before a command that will wait for you to get a “needs your help” alert. Prompts are not detected automatically.
- Only the event kind, exit code, duration, timestamp, tty name and terminal type are written, to private files under `~/Library/Application Support/PocketPikachu/events`. No command text, paths or output. Any process running as you could write there too, so treat it as a convenience, not an audit log.
- Try `sleep 3`, then `false`, then `pika-help`. To remove it, delete the line and open fresh tabs.

## Terminals above the pet

**Open terminals** in the menu opens Terminal Desk, a window of zsh tabs above Pikachu. It never opens at launch or on click.

- **+ Terminal** starts a shell in your home folder; **+ In folder…** lets you pick one. **End tab** asks before closing a shell. **Expand**, **Copy** and **Paste** do what they say, and you can drag the edges to resize.
- Closing the window hides it and keeps the shells running; **Open terminals** brings it back. Quitting Pikachu ends all of its shells, so save your work first.
- These are real shells with your normal permissions. Type `claude` here like anywhere else; nothing is auto-approved or typed for you. Scrollback is 3,000 lines, in memory only.
- Rendering uses bundled xterm.js 5.5.0 and addon-fit 0.10.0 (MIT, licenses in `Resources/terminal`) and a local Python PTY helper over pipes. No network.

## Voice control of the terminals (Gemini Live, optional)

Choose **Voice assistant…** in the right-click menu, or click **Voice** in Terminal Desk. Enter a Gemini API key, which is stored only in macOS Keychain and removable with **Forget saved key**. Keep the suggested Live model (`gemini-3.1-flash-live-preview`), click **Start voice**, and allow the microphone. Google API billing applies; a consumer Gemini subscription is not an API key.

Say things like “List my terminals”, “Create a new terminal”, “In terminal 2, type claude and press Enter”, “Send Control-C to terminal 2”, or “Press Escape in terminal 2”. Terminal IDs are the numbers on the tab labels.

- It can list and create Pikachu's own terminals, type one line (up to 16 KB, no control characters) with or without Enter, and send Ctrl-C or Escape. Nothing else: no other windows, files or settings.
- **Allow voice to control this pet's terminals** and **Share recent pet terminal output with Gemini** are on by default and can be turned off in settings (⚙). Sharing sends changed screen snapshots every 4 seconds, up to 8 tabs, the last 60 lines and 4,000 characters each. That can include private text.
- **Mute** in the voice window stops sending audio. **Stop**, saying “hang up”, or quitting the app disconnects. Nothing listens at launch. Audio and transcripts are not saved and there is no chat window. While connected, your audio, transcripts, tool calls and terminal snapshots go to Google under Google's data policies.
- Spoken commands run with your normal permissions, so watch the terminal. Gemini asks when a target or a destructive command is unclear. Duplicate or cancelled tool calls are ignored.
- Under the hood: AVAudioEngine and a WebSocket to Google's Live API, 16-bit PCM in and 24 kHz out. If audio fails to start it retries without echo cancellation; use headphones then. Reconnect by hand after a dropped session.

## Tests

```bash
./scripts/test.sh
PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 tests/test_terminal_host.py
```

The self-tests cover gaze directions, typing cadence, sleep and wake, focus, reminder timing, chase return, ball-game run counting and return home, and that every frame exists. From a logged-in session the app binary at `build/Pocket Pikachu.app/Contents/MacOS/PocketPikachu` also accepts:

- `--play-smoke`: plays a real ball game, dance and reminder and checks that Pikachu comes home. It shows a second Pikachu briefly.
- `--terminal-smoke out.png` and `--voice-tool-smoke`: exercise the terminals and voice tool routing. No Gemini request, no microphone.
- `--render-gallery out.png` and `--diagnostics file.txt`: a frame gallery, and permission and monitor state at startup.

None of these prove that macOS has granted Accessibility; only you can check that.

## Source layout

- `Sources/main.swift`: window, drawing, input monitoring, behaviour, terminals, self-tests. `Sources/GeminiVoice.swift`: voice.
- `Resources/frames/`: 73 PNGs named `row-col.png`. Row 0 idle, 1 run right, 2 run left, 3 wave, 4 jump, 5 sad, 6 waiting, 7 busy, 8 Thunderbolt, 9 typing at the laptop, 10 spare slots that reuse idle. `h0-*` and `h9-*` are the same idle and typing poses wearing headphones.
- `Resources/terminal/`: the xterm.js page and Python PTY helper. `integrations/`: the zsh hook and the `pikachu-claude` launcher. `scripts/`: build, run, test.

## Artwork and trademark

The frames were generated with Google's Gemini image model, using a community Codex pet as the pose reference, then chroma-keyed and sliced into the sprite grid. Pikachu is a trademark of Nintendo, Game Freak and The Pokémon Company. This is an unofficial fan project for personal use, not affiliated with or endorsed by them.

## Contributing

Changes go through pull requests with code-owner review; see [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md). No open-source license has been chosen, so the code can be read but all rights are reserved.
