# hermes [name] — open Claude Code in a named tmux window
#
# Usage:
#   hermes            — attach to hermes tmux session (or create one)
#   hermes <name>     — open Claude Code in a named tmux window with
#                       --effort max --name <name>
#
# Inside tmux:
#   Ctrl-b w          — visual window picker
#   Ctrl-b <number>   — jump to window by index
#   Ctrl-b d          — detach (container keeps running)
hermes() {
    local win_name="$1"

    if [ -n "$TMUX" ]; then
        # Already inside tmux — open a new window or run claude inline
        if [ -n "$win_name" ]; then
            tmux new-window -n "$win_name" -c ~/hermes \
                "claude --effort max --name $win_name"
        else
            cd ~/hermes && claude --effort max
        fi
        return
    fi

    if ! tmux has-session -t hermes 2>/dev/null; then
        # No session — create one
        if [ -n "$win_name" ]; then
            tmux new-session -s hermes -n "$win_name" -c ~/hermes \
                "claude --effort max --name $win_name"
        else
            tmux new-session -s hermes -c ~/hermes "claude --effort max"
        fi
        return
    fi

    # Session exists — create window if needed, attach via grouped session
    if [ -n "$win_name" ]; then
        if ! tmux list-windows -t hermes -F '#{window_name}' | grep -q "^${win_name}$"; then
            tmux new-window -d -t hermes -n "$win_name" -c ~/hermes \
                "claude --effort max --name $win_name"
        fi
        tmux new-session -t hermes \; select-window -t :"$win_name"
    else
        tmux new-session -t hermes
    fi
}
