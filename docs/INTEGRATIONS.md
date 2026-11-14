# Integrations

| Integration | How it gets data | Permission | Default |
|---|---|---|---|
| Claude Code | Claude Code hooks → forwarder script → local socket; plan limits from the status line | none | on (needs Connect) |
| Codex | Codex `notify` → forwarder script → local socket | none | on (needs config line) |
| Focus Timer | local timer | none | on |
| Music | Music / Spotify / TV notifications and AppleScript; browser tabs via AppleScript (title only) and media keys | Automation, Accessibility (browser controls) | on |
| Calls & Microphone | which apps use the mic (Core Audio process list); caller name from the call window title | Accessibility (names, mute buttons) | on |
| Battery | IOKit power sources | none | on |
| Network | `NWPathMonitor` | none | on |
| Downloads | file names and sizes in ~/Downloads | Downloads folder | **off** |
| Clipboard History | `NSPasteboard` change count, every 1 s | Accessibility (paste) | **off** |

## The forwarder script

DevIsland installs a tiny script at
`~/Library/Application Support/DevIsland/bin/devisland-hook` and keeps it up to date.
It forwards each event to DevIsland's socket in the background and always exits right away
with success. It can never slow down or break the tool that runs it. If DevIsland isn't running, it does nothing.

## Claude Code

**Recommended:** click **Dashboard → Agents → Connect Claude Code**, or use the welcome guide. DevIsland then:

1. backs up `~/.claude/settings.json` next to itself (`settings.json.devisland-backup-…`),
2. adds one hook for each of `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `MessageDisplay`, `Notification`, `Stop` and `SessionEnd`,
3. keeps every other setting and hook you already have.

**Disconnect** removes only DevIsland's hooks. The change applies to *new* Claude Code sessions.
If you connected before `PostToolUse` and `MessageDisplay` were added, the Agents page shows **Update Hooks**.

What DevIsland shows:
- what Claude is doing right now:
  - the first line of its message ("I'll check the running app first"),
  - the description it wrote for a command,
  - "Editing IslandView.swift",
  - a subagent's task,
- the plan step ("Step 2 of 5"),
- the session's state (working, needs you, done) and the turn time,
- a one-line summary when a turn finishes,
- the project folder and git branch.

What DevIsland reads:
- `hook_event_name`, `session_id`, `cwd` (folder name only), `tool_name` and `message`
- from `tool_input`, only `description`, `file_path` (file name only), the `url` host, `skill`, and the plan's `status`/`activeForm`
- the first readable line of `MessageDisplay.delta` and `Stop.last_assistant_message`

It never reads your prompts, command contents, file contents or edits. Lines from Claude's messages can be turned off in Settings → Privacy.

Manual setup, if you prefer. Use the same command for every event; `PreToolUse` also gets `"matcher": "*"`:

```json
{ "type": "command", "command": "'/Users/<you>/Library/Application Support/DevIsland/bin/devisland-hook' claude", "timeout": 5 }
```

## Codex

Add this line to `~/.codex/config.toml`. The Agents page shows it with your real path and a Copy button:

```toml
notify = ["/Users/<you>/Library/Application Support/DevIsland/bin/devisland-hook", "codex"]
```

Codex only reports `agent-turn-complete`, so DevIsland shows "Turn finished" but no live tool activity.

## Test the bridge without an AI tool

```sh
echo '{"hook_event_name":"SessionStart","session_id":"demo","cwd":"/tmp/Demo"}' \
  | "$HOME/Library/Application Support/DevIsland/bin/devisland-hook" claude
```

## Adding a new integration

1. Create `Sources/DevIsland/Integrations/<Name>/<Name>Integration.swift` that conforms to `Integration`.
   Give it an `id`, `name`, `summary` and `symbol`, and implement `start`/`stop`. Call `publish(ActivityEvent(...))` when something changes:
   - `.update`: live only
   - `.started`, `.completed`, `.alert`: also saved to history
   - `.ended`: removes the activity
   - `expiresAfter`: how long it may stay without updates
2. For CLI tools, also conform to `BridgeAdapter` and parse the payload in `event(from:)`.
3. Add an instance to the integrations list in `AppModel.init`.
4. Give it a name, icon and color in `SourceStyle` (`DesignSystem/Theme.swift`).
5. Optional: give it a custom island layout. Add a case to `ActivityPresentation` and a view in `IslandActivityViews.swift`.
6. Add tests in `Tests/DevIslandTests`.

## Claude Code plan usage (5-hour and weekly limits)

**Connect** also sets Claude Code's `statusLine` to `~/Library/Application Support/DevIsland/bin/devisland-statusline`.
Claude Code passes its documented `rate_limits.five_hour` and `rate_limits.seven_day` (percent used, reset time) to the status line, and the script forwards them to DevIsland.
If you already had a status line, DevIsland runs yours inside its own, so it keeps showing, and puts it back when you disconnect.
Limits are available on Pro, Max and Ultra plans, after the session's first reply. Codex, Cursor and Antigravity don't report limits yet, so they aren't shown.
