# Compat with MnemoCetus (`nemc`), a separate project: github.com/hottahidit/MnemoCetus.
# This is what Axle's `MnemoCetus` branch adds to `main`. Without nemc on PATH it does nothing.
#
#   axle nemc [command]   nemc as a tool of axle (no command: `nemc status`)
#   Benzene segment       nemc's state for this folder, read from memory on every prompt
#                         and refreshed in the background (the prompt never waits on Python)
#
#     security  red bubble with the number of findings (also in AxoN)
#     changed   amber dot: files or commits since the last scan
#     clean     green dot, only when expanded (Alt-i)
#
# With the segment on, nemc's own prompt light (`nemc init zsh`) stands down, so there's one
# light whichever loads first. Under another prompt, nemc's own light stays.
#
# What this relies on from nemc 1.0+: `status --json --budget` (fields state, findings) and
# the hook name __nemc_precmd. AXLE_NEMC=0 turns all of it off.

typeset -g  AXLE_NEMC_COMPAT=0.1.1
: ${AXLE_NEMC:=1} ${AXLE_NEMC_TTL:=60}
typeset -gA _axle_nemc_state _axle_nemc_age     # folder -> "state:findings" / when it was read
typeset -g  _axle_nemc_fd=''

# --- the command ------------------------------------------------------------------

_axle_cmd_nemc() {
  (( $+commands[nemc] )) || rehash
  if (( ! $+commands[nemc] )); then
    print -u2 -r -- "axle: MnemoCetus isn't installed: $AXLE_ROOT/install.sh --nemc"
    return 1
  fi
  (( $# )) || set -- status
  command nemc "$@"
  local -i st=$?
  _axle_nemc_age=()                             # it may have scanned: read the state again
  return st
}
axle_command nemc _axle_cmd_nemc general 'nemc [command]' 'MnemoCetus: scan, status, secrets, reclaim, ...'

# --- reading the state in the background ------------------------------------------

# One line: folder <TAB> state <TAB> findings.
_axle_nemc_worker() {
  setopt localoptions nobashrematch
  local dir=$1 out state=''
  local -i n=0
  out=$(command nemc status --json --budget 1 $dir 2>/dev/null)
  [[ $out =~ '"state": *"([a-z]+)"' ]] && state=$match[1]
  [[ $out =~ '"findings": *([0-9]+)' ]] && n=$match[1]
  print -r -- "$dir"$'\t'"$state"$'\t'"$n"
}

_axle_nemc_take() {
  local -a f=("${(@ps:\t:)1}")
  [[ -n $f[1] ]] || return 1
  (( ${#_axle_nemc_state} > 256 )) && { _axle_nemc_state=(); _axle_nemc_age=() }
  _axle_nemc_state[$f[1]]="$f[2]:${f[3]:-0}"
  _axle_nemc_age[$f[1]]=$EPOCHSECONDS
}

# zle -F callback: the worker finished; redraw if what's on screen changed.
_axle_nemc_done() {
  local fd=$1 line
  [[ $fd == $_axle_nemc_fd ]] || { zle -F $fd; exec {fd}<&-; return }
  IFS= read -r -u $fd line
  zle -F $fd
  exec {fd}<&-
  _axle_nemc_fd=''
  local was=${_axle_nemc_state[$PWD]}
  _axle_nemc_take "$line"
  if [[ ${_axle_nemc_state[$PWD]} != $was ]] && (( $+functions[_axle_render] )); then
    _axle_render
    zle reset-prompt
  fi
}

# nemc's own light: its hook runs Python before every prompt, and we already show the state.
_axle_nemc_stand_down() {
  (( ${precmd_functions[(Ie)__nemc_precmd]} )) || return 0
  add-zsh-hook -d precmd __nemc_precmd
  PROMPT=${PROMPT//'${__NEMC_LIGHT}'/}
  typeset -g __NEMC_LIGHT=''
}

_axle_nemc_precmd() {
  (( AXLE_NEMC && $+commands[nemc] )) || return 0
  _axle_nemc_stand_down
  [[ -z $_axle_nemc_fd ]] || return 0
  (( EPOCHSECONDS - ${_axle_nemc_age[$PWD]:-0} >= AXLE_NEMC_TTL )) || return 0
  (( $+builtins[zle] )) || return 0
  exec {_axle_nemc_fd}< <(_axle_nemc_worker $PWD)
  zle -F $_axle_nemc_fd _axle_nemc_done
}

# Commands that change the answer: read it again at the next prompt, not after the TTL.
_axle_nemc_preexec() {
  [[ $1 == (nemc|axle\ nemc|git\ (commit|pull|merge|rebase|checkout|switch|reset))(|\ *) ]] &&
    _axle_nemc_age[$PWD]=0
  return 0
}

# --- the Benzene segment ----------------------------------------------------------

_axle_nemc_seg() {
  REPLY=''
  (( AXLE_NEMC )) || return 0
  local entry=${_axle_nemc_state[$PWD]}
  case ${entry%%:*} in
    security) axle_style error "nemc ● ${entry##*:}"; axle_alarm 1 ;;
    changed)  axle_style warn "nemc ●" ;;
    clean)    axle_expanded && axle_style ok "nemc ●" ;;
  esac
  return 0
}

# Called each time a variant loads. nemc is looked for at each prompt, not here: ~/.zshrc
# often adds to PATH after the theme has loaded.
_axle_nemc_attach() {
  (( AXLE_NEMC )) || return 0
  _axle_segment_cmd add nemc _axle_nemc_seg right
  add-zsh-hook precmd  _axle_nemc_precmd
  add-zsh-hook preexec _axle_nemc_preexec
}

# --- axle doctor ------------------------------------------------------------------

_axle_nemc_doctor() {
  (( AXLE_NEMC )) || return 0
  if (( ! $+commands[nemc] )); then
    _dr warn "MnemoCetus not found (this is Axle's MnemoCetus branch)" "$AXLE_ROOT/install.sh --nemc, or AXLE_NEMC=0 to turn the compat off"
    return 0
  fi
  autoload -Uz is-at-least
  local v=${${(s: :)"$(command nemc --version 2>/dev/null)"}[2]}
  if [[ -n $v ]] && is-at-least 1.0 $v; then _dr ok "MnemoCetus $v (compat $AXLE_NEMC_COMPAT)"
  else _dr warn "MnemoCetus ${v:-of unknown version}: the compat needs 1.0 or newer" "update nemc"; fi
}
