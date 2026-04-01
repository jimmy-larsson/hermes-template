# hermes [name] — open Claude Code in a named tmux window
#
# Usage:
#   hermes            — attach to hermes tmux session (or create one)
#   hermes <name>     — open Claude Code in a named tmux window with
#                       --effort max --name <name>
#   hermes list       — show all hermes windows
#
# Inside tmux:
#   Ctrl-b w          — visual window picker
#   Ctrl-b <number>   — jump to window by index
#   Ctrl-b d          — detach (container keeps running)
#
# Architecture:
#   One anchor session holds all windows. Each terminal connects via a grouped
#   session with destroy-unattached, so orphans are impossible. If the original
#   "hermes" session is gone, any surviving grouped session serves as anchor.

# Helper: find any hermes session (base "hermes" preferred, else first hermes-*)
__hermes_find_anchor() {
    local base
    base=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -m1 '^hermes$')
    if [ -n "$base" ]; then
        echo "$base"
        return 0
    fi
    local grouped
    grouped=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -m1 '^hermes-[0-9]*$')
    if [ -n "$grouped" ]; then
        echo "$grouped"
        return 0
    fi
    return 1
}

hermes() {
    local win_name="$1"

    # Subcommand: list all windows
    if [ "$win_name" = "list" ]; then
        local anchor
        anchor=$(__hermes_find_anchor)
        if [ -n "$anchor" ]; then
            echo -e '\033[1;33mHermes windows:\033[0m'
            tmux list-windows -t "$anchor" -F '  #{window_index}: #{window_name}'
        else
            echo 'No Hermes session running.'
        fi
        return
    fi

    # Already inside tmux — reuse existing window or create a new one
    if [ -n "$TMUX" ]; then
        if [ -n "$win_name" ]; then
            if tmux list-windows -F '#{window_name}' 2>/dev/null | grep -q "^${win_name}$"; then
                tmux select-window -t :"$win_name"
            else
                tmux new-window -n "$win_name" -c ~/hermes \
                    "claude --effort max --name $win_name"
            fi
        else
            cd ~/hermes && claude --effort max
        fi
        return
    fi

    # Find any existing hermes session
    local anchor
    anchor=$(__hermes_find_anchor)

    # No existing session — create one
    if [ -z "$anchor" ]; then
        if [ -n "$win_name" ]; then
            tmux new-session -s hermes -n "$win_name" -c ~/hermes \
                "claude --effort max --name $win_name"
        else
            tmux new-session -s hermes -c ~/hermes "claude --effort max"
        fi
        return
    fi

    # Session exists — attach via a grouped session for independent window selection.
    # destroy-unattached auto-cleans the grouped session on detach/disconnect,
    # while the anchor session (and all its windows) persists.
    if [ -n "$win_name" ]; then
        if ! tmux list-windows -t "$anchor" -F '#{window_name}' 2>/dev/null | grep -q "^${win_name}$"; then
            tmux new-window -d -t "$anchor" -n "$win_name" -c ~/hermes \
                "claude --effort max --name $win_name"
        fi
        tmux new-session -t "$anchor" \; set-option destroy-unattached on \; select-window -t :"$win_name"
    else
        tmux new-session -t "$anchor" \; set-option destroy-unattached on
    fi
}
