# _Oh! macOS Terminal!_

A collection of macOS terminal enhancement tools, currently containing two independent sub-projects.

## Projects

### key-remap

A system-level keyboard remapping tool. It intercepts keyboard events at the system level and re-sends key sequences according to JSON rules, enabling custom shortcuts.

- **Default rule**: in Terminal.app, **Shift+Enter** inserts a newline; **Ctrl+J** is a pure-zsh fallback
- **Features**: JSON-driven config, single binary, SIGHUP hot reload (blocklist child-process exemption currently disabled)
- **Install**: `curl -fsSL https://raw.githubusercontent.com/DevTora/Oh-Mac-Term/main/key-remap/bin/bootstrap.sh | bash`
- **Docs**: [key-remap/README.md](key-remap/README.md)

### freezeterm

Locks the Terminal window in place. The window position and size are frozen on relaunch, surviving reopening and session restore.

- **Subcommands**: `setup` unlock + move the window, `lock` freeze the position, `unlock` undo
- **Features**: freezes the window by locking `com.apple.Terminal.plist`, supports custom position and column/row count
- **Usage**: `cd freezeterm && ./freezeterm.sh setup` then `./freezeterm.sh lock`
- **Docs**: [freezeterm/README.md](freezeterm/README.md)

## Layout

```
Oh-Mac-Term/
├── key-remap/        # keyboard remapping tool
│   ├── bin/          # install.sh, uninstall.sh, bootstrap.sh
│   ├── src/          # key-remap.swift
│   ├── config/       # config.json
│   ├── zsh/          # key-remap.zsh, shift-enter.zsh
│   └── README.md
└── freezeterm/       # terminal window position lock
    ├── freezeterm.sh
    ├── Basic.terminal
    └── README.md
```

## Requirements

- macOS Terminal.app
- key-remap needs Xcode Command Line Tools (provides `swiftc`)

## License

MIT License — see [LICENSE](LICENSE)
