# Compat with MnemoCetus (`nemc`), a separate project: github.com/hottahidit/MnemoCetus.
# This is what Axle's `MnemoCetus` branch adds to `main`. Without nemc on PATH it does nothing.
#
#   nemc [command]        nemc, run through axle: the prompt follows it, hook events, never a
#                         nemc that came with a project (`command nemc` skips axle)
#   axle nemc [command]   the same, listed in `axle help` (no command: `nemc status`)
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
# the hook name __nemc_precmd. AXLE_NEMC=0 turns all of it off. It never runs a nemc that came
# with a project (see "which nemc" below).

typeset -g  AXLE_NEMC_COMPAT=0.2.0
: ${AXLE_NEMC:=1} ${AXLE_NEMC_TTL:=60}
typeset -gA _axle_nemc_state _axle_nemc_age     # folder -> "state:findings" / when it was read
typeset -g  _axle_nemc_fd=''

# nemc here, or just installed by install.sh and not on PATH yet.
_axle_nemc_available() {
  (( $+commands[nemc] )) || [[ -n ${AXLE_NEMC_INSTALLED:-} || -x $HOME/.local/bin/nemc ]]
}

# --- which nemc ---------------------------------------------------------------------
#
# The prompt runs nemc without asking, so never one a repository could have put on PATH by
# itself: not one in the venv the env module entered when you cd'd into a project (a cloned
# repo can ship .venv/bin/nemc), nor one from a relative PATH entry (`.`). nemc lives in
# ~/.local/bin (uv, pipx) or wherever you installed it. Typing `nemc` goes through the same
# check (below); `command nemc` runs whatever is first on PATH, as without axle.

# Can a nemc in this folder run unseen?
_axle_nemc_trusted() {
  [[ $1 == /* ]] || return 1
  [[ -n ${_axle_env_auto:-} && ( $1 == $_axle_env_auto || $1 == $_axle_env_auto/* ) ]] && return 1
  return 0
}

typeset -g _axle_nemc_scan_key='' _axle_nemc_scan_bin=''

# The nemc to run (REPLY, a full path), or status 1. Usually the hashed one, checked with two
# comparisons; only when that one isn't trusted is PATH searched past it (once per PATH).
_axle_nemc_bin() {
  REPLY=${commands[nemc]:-}
  [[ -n $REPLY ]] || return 1
  _axle_nemc_trusted ${REPLY:h} && return 0
  local key="${_axle_env_auto:-}|${(j.:.)path}" dir
  if [[ $key != $_axle_nemc_scan_key ]]; then
    _axle_nemc_scan_key=$key _axle_nemc_scan_bin=''
    for dir in $path; do
      _axle_nemc_trusted $dir && [[ -f $dir/nemc && -x $dir/nemc ]] &&
        { _axle_nemc_scan_bin=$dir/nemc; break }
    done
  fi
  REPLY=$_axle_nemc_scan_bin
  [[ -n $REPLY ]]
}

# --- nemc, through axle -------------------------------------------------------------
#
# Typing `nemc` runs it through axle (a function of that name), so it's part of axle:
#   - the prompt's light is read again for every folder right after (a scan changes them)
#   - hook events: nemc-start ($@ = nemc's arguments) and nemc-done ($1 = exit code, then the
#     arguments), for `axle hook nemc-done my_function`
#   - never a nemc that came with a project (see above): it says so and uses yours
# Arguments and output are nemc's own, untouched. `command nemc` skips axle; AXLE_NEMC=0 too.

typeset -ga  _axle_hook_events
typeset -gaU _axle_hook_events=($_axle_hook_events nemc-start nemc-done)
typeset -gA  _axle_hook_about
_axle_hook_about[nemc-start]='nemc is about to run'
_axle_hook_about[nemc-done]='nemc finished'

_axle_nemc_run() {
  local REPLY bin
  (( $+commands[nemc] )) || rehash
  if (( ! $+commands[nemc] )); then
    print -u2 -r -- "axle: MnemoCetus isn't installed: $AXLE_ROOT/install.sh --nemc"
    return 127
  fi
  if ! _axle_nemc_bin; then
    print -u2 -r -- "axle: the only nemc on PATH is ${commands[nemc]/#$HOME/~}, which came with this project; axle won't run it (\`command nemc\` does)"
    return 1
  fi
  bin=$REPLY
  [[ $bin == $commands[nemc] ]] ||
    _axle_printp "%F{${_axle_c[muted]:-244}}axle: using ${${bin/#$HOME/~}//\%/%%}, not this project's ${${commands[nemc]/#$HOME/~}//\%/%%} (\`command nemc\` runs that one)%f" >&2
  (( $+functions[_axle_emit] )) && _axle_emit nemc-start "$@"
  command $bin "$@"
  local -i st=$?
  _axle_nemc_age=()                             # it may have scanned: read every folder again
  (( $+functions[_axle_emit] )) && _axle_emit nemc-done $st "$@"
  return st
}

nemc() {
  (( ${AXLE_NEMC:-1} )) || { command nemc "$@"; return }
  _axle_nemc_run "$@"
}

# `axle nemc`: the same, for finding it in `axle help`; with no command, this folder's state
# (plain `nemc` opens nemc's menu).
_axle_cmd_nemc() {
  (( $# )) || set -- status
  _axle_nemc_run "$@"
}
axle_command nemc _axle_cmd_nemc general 'nemc [command]' 'MnemoCetus: scan, status, secrets, reclaim, ...'

# --- reading the state in the background ------------------------------------------

# One line: folder <TAB> state <TAB> findings. _axle_nemc_worker <folder> [nemc's path]
_axle_nemc_worker() {
  setopt localoptions nobashrematch
  local dir=$1 bin=${2:-} out state='' REPLY
  local -i n=0
  [[ -n $bin ]] || { _axle_nemc_bin || return 0; bin=$REPLY }
  out=$(command $bin status --json --budget 1 $dir 2>/dev/null)
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
  local REPLY
  _axle_nemc_bin || return 0                    # not a nemc that came with this project
  exec {_axle_nemc_fd}< <(_axle_nemc_worker $PWD $REPLY)
  zle -F $_axle_nemc_fd _axle_nemc_done
}

# Commands that change the answer: read it again at the next prompt, not after the TTL. A git
# command changes this folder; nemc (also `command nemc`, which skips the function) any folder.
_axle_nemc_preexec() {
  if [[ $1 == (command\ |)nemc(|\ *) ]]; then
    _axle_nemc_age=()
  elif [[ $1 == git\ (commit|pull|merge|rebase|checkout|switch|reset)(|\ *) ]]; then
    _axle_nemc_age[$PWD]=0
  fi
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
  local REPLY
  if ! _axle_nemc_bin; then
    _dr warn "the only nemc on PATH (${commands[nemc]/#$HOME/~}) came with this project" "the prompt won't run it; install nemc with uv or pipx: $AXLE_ROOT/install.sh --nemc"
    return 0
  fi
  autoload -Uz is-at-least
  local v=${${(s: :)"$(command $REPLY --version 2>/dev/null)"}[2]}
  if [[ -n $v ]] && is-at-least 1.0 $v; then _dr ok "MnemoCetus $v (compat $AXLE_NEMC_COMPAT)"
  else _dr warn "MnemoCetus ${v:-of unknown version}: the compat needs 1.0 or newer" "update nemc"; fi
  (( $+aliases[nemc] )) &&
    _dr warn "an alias nemc='${aliases[nemc]}' skips axle's nemc" "remove it (unalias nemc), or AXLE_NEMC=0 to turn the compat off"
  return 0
}
