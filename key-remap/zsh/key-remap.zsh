# key-remap daemon manager

# The daemon is managed by LaunchAgent (com.devtora.key-remap) and starts at
# login. Do not spawn it from shells: the accessibility prompt would be
# misattributed to the terminal app. Start/restart manually instead:

# Make the bare `key-remap` command resolve to ~/.local/bin/key-remap.

if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  export PATH="$HOME/.local/bin:$PATH"
fi

key-remap-start() {
  launchctl kickstart gui/$UID/com.devtora.key-remap && echo "key-remap started"
}

key-remap-reload() {
  local pid; pid=$(pgrep -f "/\.local/bin/key-remap" 2>/dev/null)
  if [[ -n "$pid" ]]; then kill -HUP "$pid"; echo "key-remap config reloaded (pid $pid)"
  else echo "key-remap not running"; fi
}
