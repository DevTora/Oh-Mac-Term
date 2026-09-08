# key-remap

A system-level keyboard remapping tool. It intercepts keyboard events and re-sends key sequences according to JSON rules, enabling custom shortcuts like "press A, send B". No external dependencies, single binary.

Default rule: in Terminal.app, pressing **Shift+Enter** inserts a newline (nicer multi-line command editing). **Ctrl+J** is a pure-zsh fallback that needs no permission.

> Note: Ctrl+J normally submits the command in zsh; the fallback remaps it to insert a newline instead. If you rely on Ctrl+J to execute, remove the ctrl-j section from `~/.zshrc.d/shift-enter.zsh`.

## Features

- System-level interception: captures keys before apps see them, configurable for any foreground app
- JSON-driven: rules are config, apply instantly after `key-remap-reload`, no recompiling
- Child-process exemption: `blocklist` keeps vim / less / ssh etc. untouched by remapping (currently disabled — see [Blocklist status](#blocklist-status))
- Single binary: compiled from Swift, no runtime deps
- SIGHUP hot reload: `key-remap-reload` applies config changes immediately

## Install

Quick install (requires only `curl`, no git needed):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/DevTora/Oh-Mac-Term/main/key-remap/bin/bootstrap.sh)
```

Or clone and install manually:

```bash
git clone https://github.com/DevTora/Oh-Mac-Term.git
cd Oh-Mac-Term/key-remap
./bin/install.sh
```

install.sh will:

1. Check environment (macOS + Swift)
2. Compile `key-remap.swift` to `~/.local/bin/key-remap`
3. Install zsh integration scripts (`key-remap.zsh`, `shift-enter.zsh`) to `~/.zshrc.d/`
4. Install default config to `~/.config/key-remap/config.json`
5. Add the `.zshrc.d` loader to `~/.zshrc` if it does not load it already
6. Install a LaunchAgent (`com.devtora.key-remap`) so the daemon starts at login
7. Check accessibility permission (a dialog naming **key-remap** appears on first run; grant it in the opened Accessibility pane — macOS shows no Allow button for ad-hoc binaries)

Re-running install.sh when already installed asks for confirmation (default: skip). The binary is always rebuilt; **key-remap.zsh is always updated**, while `config.json` and `shift-enter.zsh` are refreshed only when their content is unchanged — if you've customized either, you'll be asked whether to overwrite (default: keep). The installer requires an interactive terminal, so use `bash <(curl -fsSL .../bin/bootstrap.sh)` for a quick (re)install.

> If the permission check fails, grant accessibility permission (System Settings → Privacy & Security → Accessibility → add `~/.local/bin/key-remap`) and run `launchctl kickstart gui/$UID/com.devtora.key-remap` — no need to re-run the installer.

## Configuration

Config file: `~/.config/key-remap/config.json`

```jsonc
{
  "apps": {
    "com.apple.Terminal": {
      "blocklist": ["vim", "nvim", "vi", "less", "more", "cat", "htop", "top", "btm", "man", "ssh"]
    }
  },
  "rules": [
    {
      "apps": ["com.apple.Terminal"],
      "key": "return",
      "modifiers": ["shift"],
      "notModifiers": ["alt", "ctrl", "cmd"],
      "send": "\u001b[13;3u"
    }
  ]
}
```

Field reference:

| Field | Meaning |
| --- | --- |
| `apps` | Per-app settings, key is the app bundle id (e.g. `com.apple.Terminal`) |
| `apps.*.blocklist` | Child-process blacklist. Remapping is disabled for the app while these run (**currently disabled**, see [Blocklist status](#blocklist-status)) |
| `rules[].apps` | Bundle ids where the rule applies |
| `rules[].key` | Trigger key name (`return`, `tab`, `a`-`z`, `0`-`9`, `f1`-`f12`, etc.) |
| `rules[].modifiers` | Required modifiers: `shift`, `ctrl`, `alt`, `cmd` |
| `rules[].notModifiers` | Forbidden modifiers (any present prevents the trigger) |
| `rules[].send` | Key sequence to send on match (string or escape sequence like `\u001b[13;3u`) |

Key codes follow the US keyboard layout; on non-US layouts the physical key position matches the US label.

### Validation

Config is validated on startup and on every reload:

- Unknown key or modifier names are printed to `stderr` and that rule is skipped
- An empty `apps` list, or a modifier conflict (`modifiers` overlapping `notModifiers`), also skips the rule with a warning
- If no rule survives validation, the previous config is kept and the error is printed; on first run the program exits with an error instead

> Don't map a key to send a sequence containing the same keycode with no modifiers (e.g. `"key": "a"`, `"send": "a"`): it can't trigger an infinite loop (events injected by key-remap carry a marker and are passed through without re-matching), but it also sends exactly what you typed, so the rule is pointless.

After editing the config, run in a terminal:

```bash
key-remap-reload
```

To use a custom config path instead of the default `~/.config/key-remap/config.json`:

```bash
~/.local/bin/key-remap /path/to/config.json
```

## Uninstall

Quick uninstall (requires only `curl`, no git needed):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/DevTora/Oh-Mac-Term/main/key-remap/bin/uninstall.sh)
```

Or clone and uninstall manually:

```bash
cd Oh-Mac-Term/key-remap
./bin/uninstall.sh
```

Removes the LaunchAgent, stops the daemon, deletes the binary and `key-remap.zsh`, and clears the singleton lock. Config, log and `shift-enter.zsh` are kept by default (the script prompts before removing them). The loader line is removed from `~/.zshrc` **only if** `~/.zshrc.d` becomes empty; if other scripts remain there, the loader is kept. The uninstaller requires an interactive terminal and refuses to run when stdin is not a tty, so always use `bash <(curl -fsSL ...)` — not `curl ... | bash`.

> The TCC accessibility entry cannot be reset via `tccutil` (path-based client has no bundle id). When run interactively, uninstall.sh opens System Settings so you can remove the **key-remap** entry manually (select it, press `-`).

## Permission

key-remap needs the **Accessibility** permission. The daemon runs via LaunchAgent, so the request is made by key-remap itself: on first launch a dialog naming **key-remap** appears. macOS shows no Allow button for ad-hoc binaries — grant it in the opened System Settings pane instead.

Manual grant: System Settings → Privacy & Security → Accessibility → add `~/.local/bin/key-remap`.

If re-granting fails and no dialog ever appears, a stale TCC entry from an earlier install may be blocking the request: remove the old **key-remap** entry in the Accessibility list (select it, press `-`), then add it again.

After granting, restart the daemon:

```bash
launchctl kickstart gui/$UID/com.devtora.key-remap
```

Check permission (exit code `0` = granted, `1` = denied; read-only, triggers no dialog):

```bash
~/.local/bin/key-remap --check-permission
```

> When run from a shell, TCC attributes even this read-only check to the hosting terminal app, so the result may reflect the terminal's own accessibility state rather than key-remap's. The authoritative check is whether the daemon stays running: `pgrep -f "\.local/bin/key-remap"`.

Hence, launching it from a shell is unsafe:

> Do not start the binary directly from a shell: macOS attributes the accessibility prompt to the responsible terminal app (the historical source of misattributed dialogs). Use the LaunchAgent or `key-remap-start` instead.

## Log

Startup errors and config-validation warnings go to `~/.local/var/log/key-remap.log` (stdout + stderr, appended). Check it if the daemon fails to start or a rule is silently skipped:

```bash
tail -20 ~/.local/var/log/key-remap.log
```

## How it works

1. key-remap captures key events at the system level via `CGEventTap` (`.cgSessionEventTap`)
2. Rules match on bundle id + key code + modifier combination
3. On match it cancels the original event and posts the `send` sequence (`CGEvent` unicode injection)
4. zsh uses `bindkey` to map the received sequence (e.g. `\e[13;3u`) to "insert newline"

The frontmost app result is cached briefly (sub-second) to avoid expensive lookups on every keystroke; the cache is invalidated immediately when the frontmost app changes. (The old blocklist result cache was removed along with the disabled feature.)

## Blocklist status

The `blocklist` feature is **currently disabled** because the check ran a synchronous `ps` scan of all processes on every key press, causing noticeable input lag.

- The related Swift code is commented out in `src/key-remap.swift` (see the `// MARK: - Blocklist` section, plus the commented `isBlocked()` call in the tap callback and `blCache.removeAll()` in `reloadConfig()`).
- `apps` keys in the config are accepted but ignored by `JSONDecoder` (the `apps` field is commented out in `Config`), so the default `config.json` can stay unchanged.
- To re-enable: uncomment those code blocks, rebuild (`swiftc -O -o ~/.local/bin/key-remap key-remap/src/key-remap.swift`), and restart the daemon.

## Limitations

- Rules match the cached frontmost app, so up to ~150 ms after switching apps the old bundle id may still be used (only relevant if you type immediately and your rules target other apps)
- (Blocklist limitations do not apply while the feature is disabled)

## Requirements

- macOS (compiled on your machine, so the binary always matches your system version)
- Xcode Command Line Tools (provides `swiftc`)

## License

MIT — see [LICENSE](../LICENSE)
