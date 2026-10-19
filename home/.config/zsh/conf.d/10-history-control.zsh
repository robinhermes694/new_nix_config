# Per-pane zsh history for herdr and tmux.
#
# Saves zsh history to a separate file per pane so that restoring a session
# also restores that pane's history.
#
# Caveat: the first time a pane is loaded the history is not yet present. Run
# one command (or just hit Enter) and it becomes available. A brand-new pane is
# seeded from the shared history file so `up` is not empty on first use.
#
# Originally adapted for tmux from:
# https://github.com/tmux-plugins/tmux-resurrect/issues/288#issuecomment-706772667
#
# NOTE: this registers into `precmd_functions` via add-zsh-hook instead of
# defining `precmd()` outright, so it composes with starship's own precmd hook
# instead of clobbering it.

HISTS_DIR=${HISTS_DIR:-$HOME/.zsh_history.d}
mkdir -p "${HISTS_DIR}"

# History that predates per-pane splitting, and the fallback for shells with no
# pane id. New per-pane files are seeded from this so a fresh pane starts with
# the shared history instead of an empty `up` arrow. See seedHistFile below.
HISTS_BASE="${HISTS_DIR}/zsh_history_no_tmux"

# add commands to HISTFILE immediately
setopt inc_append_history
setopt no_share_history

# herdr exports HERDR_PANE_ID into every pane shell, already qualified by
# workspace (e.g. "w7:p5"), so it is globally unique on its own -- the
# equivalent of tmux's "#S:#I:#P". Unlike tmux it needs no subprocess, so the
# herdr path costs nothing per prompt.
#
# Colons are legal in filenames but awkward to quote, so they become dashes:
#   w7:p5 -> ~/.zsh_history.d/zsh_history_herdr_w7-p5
#
# A pane moved to another workspace keeps the id it was spawned with, so its
# history follows the shell rather than the screen position.
getHistFile() {
  if [ -n "${HERDR_PANE_ID}" ]; then
    echo "${HISTS_DIR}/zsh_history_herdr_${HERDR_PANE_ID//:/-}"
  elif [ -n "${TMUX_PANE}" ]; then
    # If the tmux call fails, fall back to $TMUX_PANE (e.g. "%3") rather than an
    # empty key, which would make every pane share a single history file.
    local id
    id=$(tmux display-message -t "$TMUX_PANE" -p '#S:#I:#P' 2>/dev/null)
    echo "${HISTS_DIR}/zsh_history_tmux_${id:-${TMUX_PANE#%}}"
  else
    echo "${HISTS_DIR}/zsh_history_no_tmux"
  fi
}

seedHistFile() {
  local target=$1
  # Nothing to do once the pane has its own file, and never seed the base from
  # itself. Missing/unreadable base is fine -- the pane just starts empty.
  [[ -e "$target" || "$target" == "$HISTS_BASE" || ! -r "$HISTS_BASE" ]] && return 0
  # Write via a temp file so a pane that dies mid-copy cannot leave a truncated
  # history behind, and so two panes starting at once cannot interleave.
  local tmp="${target}.seed.$$"
  if cp "$HISTS_BASE" "$tmp" 2>/dev/null; then
    chmod 600 "$tmp" 2>/dev/null
    # noclobber-safe: first pane to land wins, the loser discards its copy.
    if ! ln "$tmp" "$target" 2>/dev/null; then
      rm -f "$tmp" 2>/dev/null
      return 0
    fi
    rm -f "$tmp" 2>/dev/null
  fi
}

initHist() {
  HISTFILE=$(getHistFile)
  seedHistFile "$HISTFILE"
  # Only load history on the second call of this function
  # (the first time through, HISTINIT is 0)
  if ((HISTINIT == 1)); then
    # Clear and read the history from disk
    fc -p "$HISTFILE"
    HISTFILE_LOADED=$HISTFILE
  fi
  if [[ -n "${HISTFILE_LOADED}" && "$HISTFILE" != "$HISTFILE_LOADED" ]]; then
    HISTFILE_LOADED=$HISTFILE
  fi
  if ((HISTINIT <= 1)); then
    ((HISTINIT += 1))
  fi
}

HISTINIT=0

autoload -Uz add-zsh-hook
add-zsh-hook precmd initHist

# Show which history file this pane is using, and where the others are.
#   histfile        -> path for this pane
#   histfile -l     -> all pane history files, newest first
histfile() {
  if [[ "$1" == "-l" ]]; then
    ls -lt "${HISTS_DIR}" 2>/dev/null
  else
    echo "${HISTFILE:-$(getHistFile)}"
  fi
}
