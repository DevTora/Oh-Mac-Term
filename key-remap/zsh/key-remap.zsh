# key-remap daemon manager
if ! pgrep -qf "/\.local/bin/key-remap" >/dev/null 2>&1; then
  mkdir -p ~/.local/var/log
  ~/.local/bin/key-remap >>~/.local/var/log/key-remap.log 2>&1 &!
fi

key-remap-reload() {
  local pid; pid=$(pgrep -f "/\.local/bin/key-remap" 2>/dev/null)
  if [[ -n "$pid" ]]; then kill -HUP "$pid"; echo "key-remap config reloaded (pid $pid)"
  else echo "key-remap not running"; fi
}
