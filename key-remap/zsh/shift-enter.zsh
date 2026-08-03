# Shift+Enter / Ctrl+J -> insert newline (add/remove as needed)
shift-enter-insert-newline() { LBUFFER="$LBUFFER"$'\n' }
zle -N shift-enter-insert-newline
bindkey '\e[13;3u' shift-enter-insert-newline

ctrl-j-insert-newline() { LBUFFER="$LBUFFER"$'\n' }
zle -N ctrl-j-insert-newline
bindkey '^J' ctrl-j-insert-newline
