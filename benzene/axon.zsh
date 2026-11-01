# AxoN (axon) — the focus variant: one quiet line, the folder and the arrow.
# Everything else appears only when it needs attention.
#
#   axle $                              outside a repo
#   axle(main) $                        on a branch, nothing to commit
#   axle(main)*+ $                      unstaged (*) and staged (+) changes
#   axle(other) REBASE 2/5 =1 ✗1 $      mid-rebase, a conflict, last command failed
#   axle(@368f5f1) $                    detached HEAD
#   nas stacks(main) &1 sudo 42s ✗130 $ over SSH, a background job, sudo still active,
#                                       a slow command that was interrupted
#
# The $ is coloured by state: mauve, red after a failure, deep red at 80%+ RAM.
#
# Built on NoxA's engine: the same background git, sudo tracking, timers, compact past
# lines, AI status and settings (AXLE_NERD_FONT, AXLE_PALETTE, ...). Alt-i shows the
# full NoxA prompt until the next command.
#
# Settings (in ~/.zshrc, before oh-my-zsh is sourced):
#   AXLE_AXON_SHOW=(...)    attention markers, in order:
#                           host inside dir git venv direnv toolchain jobs tmux sudo battery exec
#                           (all by default)
#   AXLE_AXON_SLOW=10       show run time at or above this many seconds (0 = never)
#   AXLE_AXON_CHAR='$'      the prompt character (AXLE_AXON_CHAR_VICMD=':' in vi command mode)

source "$AXLE_ROOT/benzene/nox.zsh"

(( ${+AXLE_AXON_SHOW} )) || typeset -ga AXLE_AXON_SHOW=(host inside dir git venv direnv toolchain jobs tmux sudo battery exec)
: ${AXLE_AXON_SLOW:=10} ${AXLE_AXON_CHAR:=\$} ${AXLE_AXON_CHAR_VICMD:=:}

# NoxA's two-line layout stays available as the expanded view.
functions -c _axle_render _axle_render_full

# --- attention markers -------------------------------------------------------
# Each _axle_axon_<name> sets REPLY, or leaves it empty when there's nothing to say.

# Which machine, only when it isn't this one: SSH session or container.
_axle_axon_host() {
  if [[ -n $SSH_CONNECTION || -n $SSH_TTY ]]; then
    REPLY="%F{$_axle_c[ssh]}$_axle_i[remote]%m%f"
  elif _axle_container_name; then
    REPLY="%F{$_axle_c[docker]}$_axle_i[toolbox]${REPLY//\%/%%}%f"
  elif [[ -f /.dockerenv || -f /run/.containerenv ]]; then
    REPLY="%F{$_axle_c[docker]}$_axle_i[container]%m%f"
  fi
}

# In a shell started from another program (ranger, vim :sh, ...): "exit" goes back.
_axle_axon_inside() {
  _axle_seg_inside
}

# An .envrc direnv hasn't been allowed to load.
_axle_axon_direnv() {
  _axle_alarm=0; _axle_seg_direnv
  (( _axle_alarm )) && REPLY="%F{$_axle_c[warn]}direnv blocked%f" || REPLY=''
}

# Just the folder name (~ at home), amber on a Windows drive, then git's dirty mark.
_axle_axon_dir() {
  local colour=$_axle_c[path]
  _axle_on_windows_drive && colour=$_axle_c[windows]
  local out="%F{$colour}%1~%f"
  [[ -w $PWD ]] || out+="%F{$_axle_c[error]}$_axle_i[lock]%f"
  # In a repo: axle(main), then * for unstaged changes and + for staged ones.
  if (( ${AXLE_AXON_SHOW[(Ie)git]} )); then
    local ref=''
    if _axle_axon_flag branch; then
      ref=${REPLY//\%/%%}
    elif _axle_axon_flag detached; then
      ref="@$REPLY"
    fi
    if [[ -n $ref ]]; then
      local bc=$_axle_c[clean]
      _axle_axon_flag dirty && bc=$_axle_c[dirty]
      out+="%F{$_axle_c[muted]}(%f%F{$bc}$ref%f%F{$_axle_c[muted]})%f"
      _axle_axon_flag unstaged && out+="%F{$_axle_c[changed]}*%f"
      _axle_axon_flag staged   && out+="%F{$_axle_c[staged]}+%f"
    fi
  fi
  REPLY=$out
}

# Read one key from the git worker's raw flags (for $PWD only); sets the value in REPLY.
_axle_axon_flag() {
  setopt localoptions extendedglob
  local -a part=("${(@ps:\x1f:)_axle_seg[git]}")    # quoted: keep empty fields
  local flags=" $part[3]" value
  [[ $_axle_git_pwd == $PWD && -n $part[3] ]] || return 1
  [[ $flags == *" $1="* ]] || return 1
  value=${${flags#* $1=}%% [a-z]##=*}
  [[ -n $value && $value != 0 ]] || return 1
  REPLY=$value
}

# Git trouble beyond the branch: an operation in progress, conflicts.
_axle_axon_git() {
  local out=''
  _axle_axon_flag action    && out+=" %B%F{$_axle_c[action]}$REPLY%f%b"
  _axle_axon_flag conflicts && out+=" %F{$_axle_c[conflict]}=$REPLY%f"
  REPLY=${out# }
}

# The wrong venv for this folder (see NoxA's _axle_venv_state): amber, named.
_axle_axon_venv() {
  local -a reply
  _axle_venv_state
  case $reply[1] in
    inactive)  REPLY="%F{$_axle_c[warn]}${reply[2]//\%/%%} (inactive)%f" ;;
    elsewhere) REPLY="%F{$_axle_c[warn]}${reply[2]//\%/%%} (other project)%f" ;;
  esac
}

# A pinned toolchain version that doesn't match the active one: "node 25.6.0 (wants 20)".
_axle_axon_toolchain() {
  local name out='' have
  for name in node python rust go ruby java php lua perl scala flutter; do
    REPLY='' _axle_alarm=0
    _axle_seg_$name
    (( _axle_alarm == 2 )) && [[ $REPLY == *(wants|not\ installed)* ]] || continue
    out+="${out:+ }%F{$_axle_c[warn]}${${REPLY//\%F\{[^\}]#\}/}//\%f/}%f"
  done
  REPLY=$out
}

# Detached tmux sessions waiting (NoxA's tmux segment stays quiet otherwise here).
_axle_axon_tmux() {
  [[ -z $TMUX ]] && _axle_seg_tmux
}

_axle_axon_jobs() {
  (( ${#jobstates} )) && REPLY="%F{$_axle_c[jobs]}&${#jobstates}%f"
}

# sudo won't ask for a password right now (no countdown; expand for the time left).
_axle_axon_sudo() {
  (( _axle_sudo_until < 0 || _axle_sudo_until > EPOCHSECONDS )) && REPLY="%F{$_axle_c[sudo]}sudo%f"
}

# Low battery only (NoxA's segment already stays quiet otherwise).
_axle_axon_battery() {
  _axle_seg_battery
}

# Slow run time and/or failure: "42s", "✗1", "42s ✗130", "✗0|1|0" for a pipeline.
_axle_axon_exec() {
  local -a st=($_axle_last_status)
  (( ${#st} )) || return
  local out=''
  if (( AXLE_AXON_SLOW > 0 && _axle_elapsed >= AXLE_AXON_SLOW )); then
    _axle_fmt_duration $_axle_elapsed
    out="%F{$_axle_c[muted]}$REPLY%f"
  fi
  if [[ ${(j::)st} == *[1-9]* ]]; then
    local code=$st[1]
    (( ${#st} > 1 )) && code=${(j:|:)st}
    out+="${out:+ }%F{$_axle_c[error]}✗$code%f"
  fi
  REPLY=$out
}

# --- layout ------------------------------------------------------------------

_axle_render() {
  if (( _axle_detail )); then
    _axle_render_full
    return
  fi
  # The $ carries the state in its colour (bold, so one character still reads): accent,
  # deep red under memory pressure, red after a failure. # for root, : in vi command mode.
  local char=$AXLE_AXON_CHAR colour=$_axle_c[accent]
  (( _axle_mem_used >= AXLE_MEM_WARN )) && colour=$_axle_c[pressure]
  [[ ${(j::)_axle_last_status} == *[1-9]* ]] && colour=$_axle_c[error]
  (( _axle_uid == 0 )) && char='#'
  [[ $_axle_keymap == vicmd ]] && char=$AXLE_AXON_CHAR_VICMD

  local name line='' _axle_plain=1       # alarms as coloured text, not bubbles
  for name in $AXLE_AXON_SHOW; do
    REPLY=''
    (( $+functions[_axle_axon_$name] )) && _axle_axon_$name
    [[ -n $REPLY ]] && line+="${line:+ }$REPLY"
  done
  _axle_ps1="${line:+$line }%B%F{$colour}${char//\%/%%}%f%b "
  _axle_rps1='' _axle_bottom=''
}

# Collapsed, nothing ticks (no clock); expanded, NoxA's segments are on screen.
_axle_visible_segments() {
  reply=()
  (( _axle_detail )) && reply=($AXLE_NOX_LEFT $AXLE_NOX_RIGHT)
}

# Past prompts: just where and what, dimmed.
_axle_compact_line() {
  REPLY="%F{$_axle_c[muted]}%1~ ${AXLE_AXON_CHAR//\%/%%}%f "
}
