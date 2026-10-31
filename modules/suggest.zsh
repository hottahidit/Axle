# Smart autosuggestions: as you type, the likeliest completion of the line appears in
# grey after the cursor, and when there are other likely ones, a short list of them
# below the line. → or End accepts the selected one; Ctrl-→ or Alt-f accepts one word;
# Ctrl-N / Ctrl-P (or Shift-↓ / Shift-↑) move through the list; Enter runs what you typed.
#
# "Smart" because it learns from the history the axle core records (where each command
# ran, how it ended, what came before it) and ranks matches by:
#   - runs in this directory           (what you do *here*)
#   - runs right after the last command (git add . → git commit -m …)
#   - how often and how recently
# and leaves out commands that have only ever failed. With no smart match it falls back to
# plain shell history. Lines typed with a leading space aren't recorded (as with
# HIST_IGNORE_SPACE).
#
#   AXLE_SUGGEST=1            0 = off
#   AXLE_SUGGEST_LOAD=4000    how many recorded commands to learn from at startup
#   AXLE_SUGGEST_LIST=5       options in the list (1 = just the inline suggestion)
#
# Steps aside when zsh-autosuggestions is loaded.

: ${AXLE_SUGGEST:=1} ${AXLE_SUGGEST_LOAD:=4000} ${AXLE_SUGGEST_LIST:=5}
# The history log is the core's (core/events.zsh); this module keeps learned counts.
typeset -g _axle_sg_file=$_axle_hist_file
typeset -g _axle_sg_cache=${_axle_sg_file:h}/suggest-cache.zsh

# command -> runs, successes, last run (epoch); "dir<US>command" and "prev<US>command" -> runs
typeset -gA _axle_sg_count _axle_sg_ok _axle_sg_last _axle_sg_dir _axle_sg_next
typeset -g  _axle_sg_buffer=$'\0'
typeset -gi _axle_sg_ready=0

# --- learning -----------------------------------------------------------------------

# Count one run. $1 epoch, $2 exit code, $3 dir, $4 previous command, $5 command.
# (Keys are whole command lines, so they're never put inside (( )), where characters
# like $( ) ] * would be parsed as arithmetic.)
_axle_sg_learn() {
  local cmd=$5 here=$3$'\x1f'$5 after=$4$'\x1f'$5
  _axle_sg_count[$cmd]=$(( ${_axle_sg_count[$cmd]:-0} + 1 ))
  [[ $2 == 0 ]] && _axle_sg_ok[$cmd]=$(( ${_axle_sg_ok[$cmd]:-0} + 1 ))
  [[ $1 -gt ${_axle_sg_last[$cmd]:-0} ]] && _axle_sg_last[$cmd]=$1
  _axle_sg_dir[$here]=$(( ${_axle_sg_dir[$here]:-0} + 1 ))
  [[ -n $4 ]] && _axle_sg_next[$after]=$(( ${_axle_sg_next[$after]:-0} + 1 ))
}

# Learn from the most recent recorded commands.
_axle_sg_load() {
  [[ -r $_axle_sg_file ]] || return
  local line
  local -a f
  for line in "${(@f)$(command tail -n $AXLE_SUGGEST_LOAD $_axle_sg_file 2>/dev/null)}"; do
    f=("${(@ps:\t:)line}")
    (( ${#f} == 6 )) || continue
    _axle_sg_learn $f[1] $f[2] $f[4] "${f[5]//\\n/$'\n'}" "${f[6]//\\n/$'\n'}"
  done
}

# Save what was learned as a file zsh loads in one go (instead of re-reading the log).
_axle_sg_dump() {
  local tmp=$_axle_sg_cache.$$
  {
    print -r -- "_axle_sg_count=(${(@qqqqkv)_axle_sg_count})"
    print -r -- "_axle_sg_ok=(${(@qqqqkv)_axle_sg_ok})"
    print -r -- "_axle_sg_last=(${(@qqqqkv)_axle_sg_last})"
    print -r -- "_axle_sg_dir=(${(@qqqqkv)_axle_sg_dir})"
    print -r -- "_axle_sg_next=(${(@qqqqkv)_axle_sg_next})"
  } > $tmp 2>/dev/null && mv -f $tmp $_axle_sg_cache 2>/dev/null
}

# At startup: load the cache (fast); if the log has moved on since, rebuild the cache in
# the background for the next shell. Only the very first run reads the log directly.
# Run on the first keystroke, not at shell startup, so new shells don't pay for it.
_axle_sg_init() {
  _axle_sg_ready=1
  if [[ -r $_axle_sg_cache ]]; then
    source $_axle_sg_cache 2>/dev/null
    if [[ $_axle_sg_file -nt $_axle_sg_cache ]]; then
      ( _axle_sg_count=() _axle_sg_ok=() _axle_sg_last=() _axle_sg_dir=() _axle_sg_next=()
        _axle_sg_load; _axle_sg_dump ) &!
    fi
  elif [[ -r $_axle_sg_file ]]; then
    _axle_sg_load; _axle_sg_dump
  fi
}

# Learn from a finished command (hook: command-done $1 exit, $2 seconds, $3 command line;
# the core provides where it ran and what came before it). The core writes the log.
_axle_sg_cmd_done() {
  setopt localoptions extendedglob
  (( _axle_sg_ready )) || _axle_sg_init
  local cmd=$3
  [[ -n ${cmd//[[:space:]]/} && $cmd != ' '* ]] || return
  _axle_sg_learn $EPOCHSECONDS $1 ${_axle_ev_dir:-$PWD} "$_axle_ev_prev" "${cmd%%[[:space:]]#}"
}

# --- suggesting ---------------------------------------------------------------------

# The likeliest completions of $1, best first, at most $2 (reply=()). Commands Axle has
# seen come first, ranked by this directory, the previous command, frequency and
# recency; then shell history (newest first) fills the rest. Duplicates, multi-line
# entries and commands that have only ever failed are left out.
_axle_sg_rank() {
  local prefix=$1 c here after event
  local -i max=${2:-5} score age last
  local -a scored
  for c in ${(k)_axle_sg_count[(I)${(b)prefix}?*]}; do
    [[ ${_axle_sg_ok[$c]:-0} -gt 0 && $c != *$'\n'* ]] || continue
    here=$PWD$'\x1f'$c after=$_axle_ev_prev$'\x1f'$c
    score=$(( ${_axle_sg_count[$c]} + 3 * ${_axle_sg_dir[$here]:-0} + 5 * ${_axle_sg_next[$after]:-0} ))
    last=${_axle_sg_last[$c]:-0} age=$(( EPOCHSECONDS - last ))
    if   (( age < 3600 ));   then (( score += 3 ))
    elif (( age < 86400 ));  then (( score += 2 ))
    elif (( age < 604800 )); then (( score += 1 ))
    fi
    scored+=("${(l:8::0:)score}${(l:12::0:)last}"$'\x1f'"$c")     # sorts by score, then recency
  done
  reply=("${(@)${(@O)scored}#*$'\x1f'}")
  (( ${#scored} )) || reply=()
  if (( ${#reply} < max )); then
    # $history is keyed by event number, and (R) on it returns every match: take the
    # matching event numbers newest first.
    local -a events=(${(kOn)history[(R)${(b)prefix}?*]})
    for event in ${events[1,300]}; do
      c=$history[$event]
      [[ $c != *$'\n'* ]] || continue
      (( ${reply[(Ie)$c]} )) && continue
      (( ! ${+_axle_sg_count[$c]} || ${_axle_sg_ok[$c]:-0} )) || continue
      reply+=("$c")
      (( ${#reply} >= max )) && break
    done
  fi
  reply=("${(@)reply[1,max]}")
}

# The single best completion of $1 (REPLY).
_axle_sg_find() {
  local -a reply
  _axle_sg_rank "$1" 1
  REPLY=${reply[1]}
}

typeset -ga _axle_sg_list
typeset -gi _axle_sg_sel=1 _axle_sg_cursor=-1
typeset -g  _axle_sg_ghost=''

# Draw the selected option's rest as grey ghost text, and (with 2+ options) the list
# below the line, the selected one marked.
_axle_sg_render() {
  local ghost='' post=''
  (( ${#_axle_sg_list} )) && ghost=${_axle_sg_list[_axle_sg_sel]#$BUFFER}
  _axle_sg_ghost=$ghost
  region_highlight=(${region_highlight:#*memo=axle-suggest*})
  local -i base=${#BUFFER}
  post=$ghost
  [[ -n $ghost ]] && region_highlight+=(
    "$base $(( base + ${#ghost} )) fg=${_axle_c[suggest]:-${_axle_c[muted]:-244}},memo=axle-suggest")
  if (( ${#_axle_sg_list} > 1 )); then
    local item mark style
    local -i i start w=$(( ${COLUMNS:-80} - 6 ))
    (( w > 10 )) || w=10
    for i in {1..${#_axle_sg_list}}; do
      item=${_axle_sg_list[i]}
      (( ${#item} > w )) && item="${item[1,w-1]}…"
      if (( i == _axle_sg_sel )); then
        mark='  ▸ ' style="fg=${_axle_c[accent]:-magenta},bold"
      else
        mark='    ' style="fg=${_axle_c[muted]:-244}"
      fi
      start=$(( base + ${#post} + 1 ))
      post+=$'\n'"$mark$item"
      region_highlight+=("$start $(( base + ${#post} )) $style,memo=axle-suggest")
    done
  fi
  POSTDISPLAY=$post
}

_axle_sg_clear() {
  _axle_sg_list=() _axle_sg_ghost=''
  POSTDISPLAY=''
  region_highlight=(${region_highlight:#*memo=axle-suggest*})
}

# Before every redraw: recompute when the line or cursor changed.
_axle_sg_redraw() {
  (( AXLE_SUGGEST )) || return
  # Tab completion shows its own list: step aside until the next key.
  if [[ $LASTWIDGET == (*complete*|*expand*|menu-select|*list*) ]]; then
    _axle_sg_clear; _axle_sg_buffer=$'\0'; return
  fi
  [[ $BUFFER == $_axle_sg_buffer && $CURSOR == $_axle_sg_cursor ]] && return
  _axle_sg_buffer=$BUFFER _axle_sg_cursor=$CURSOR
  (( _axle_sg_ready )) || _axle_sg_init
  _axle_sg_list=() _axle_sg_sel=1
  if [[ -n $BUFFER && CURSOR -eq ${#BUFFER} && $BUFFER != *$'\n'* ]]; then
    local -a reply
    _axle_sg_rank "$BUFFER" $AXLE_SUGGEST_LIST
    _axle_sg_list=("${(@)reply}")
  fi
  _axle_sg_render
}

# Take the selected option, whole or (with "word") its next word. Fails when there's none.
_axle_sg_take() {
  setopt localoptions extendedglob
  [[ -n $_axle_sg_ghost && CURSOR -eq ${#BUFFER} ]] || return 1
  local take=$_axle_sg_ghost chosen=${_axle_sg_list[_axle_sg_sel]}
  [[ $1 == word ]] && take=${(M)_axle_sg_ghost##[[:space:]]#[^[:space:]]##}
  BUFFER+=$take
  CURSOR=${#BUFFER}
  _axle_sg_buffer=$BUFFER _axle_sg_cursor=$CURSOR
  # Finishing a chosen option word by word: keep just that one.
  if [[ $chosen != $BUFFER ]]; then
    _axle_sg_list=("$chosen") _axle_sg_sel=1
  else
    _axle_sg_list=()
  fi
  _axle_sg_render
}

# Move through the list (+1 / -1). Fails when no list is showing.
_axle_sg_cycle() {
  local -i n=${#_axle_sg_list}
  (( n > 1 && CURSOR == ${#BUFFER} )) || return 1
  _axle_sg_sel=$(( (_axle_sg_sel - 1 + $1 + n) % n + 1 ))
  _axle_sg_render
}

# Keys that move through the list do their usual job when there's no list.
typeset -gA _axle_sg_fallback          # "keymap<US>keys" -> the widget they had before
_axle_sg_key_fallback() {
  # (While editing, $KEYMAP is "main", an alias of emacs or viins.)
  local km w
  for km in $KEYMAP emacs viins; do
    w=${_axle_sg_fallback[$km$'\x1f'$KEYS]}
    [[ -n $w ]] && break
  done
  [[ -n $w && $w != undefined-key ]] && zle $w
}
axle-suggest-next() { _axle_sg_cycle 1  || _axle_sg_key_fallback }
axle-suggest-prev() { _axle_sg_cycle -1 || _axle_sg_key_fallback }

_axle_sg_forward_char()    { _axle_sg_take       || zle .forward-char }
_axle_sg_end_of_line()     { _axle_sg_take       || zle .end-of-line }
_axle_sg_vi_forward_char() { _axle_sg_take       || zle .vi-forward-char }
_axle_sg_vi_end_of_line()  { _axle_sg_take       || zle .vi-end-of-line }
_axle_sg_forward_word()    { _axle_sg_take word  || zle .forward-word }
_axle_sg_emacs_fwd_word()  { _axle_sg_take word  || zle .emacs-forward-word }
_axle_sg_accept_line()     { _axle_sg_clear; zle .accept-line }

typeset -gA _axle_sg_widgets=(
  forward-char _axle_sg_forward_char        end-of-line _axle_sg_end_of_line
  vi-forward-char _axle_sg_vi_forward_char  vi-end-of-line _axle_sg_vi_end_of_line
  forward-word _axle_sg_forward_word        emacs-forward-word _axle_sg_emacs_fwd_word
  accept-line _axle_sg_accept_line
)

# --- install -------------------------------------------------------------------------

_axt_cleanup_suggest() {
  local w
  if (( $+builtins[zle] )); then
    for w in ${(k)_axle_sg_widgets}; do
      [[ ${widgets[$w]} == user:_axle_sg_* ]] && zle -A .$w $w
    done
  fi
}

if (( AXLE_SUGGEST && $+builtins[zle] )) && (( ! $+functions[_zsh_autosuggest_start] )); then
  autoload -Uz add-zle-hook-widget
  add-zle-hook-widget line-pre-redraw _axle_sg_redraw
  for _axle_w in ${(k)_axle_sg_widgets}; do
    zle -N $_axle_w $_axle_sg_widgets[$_axle_w]
  done
  unset _axle_w
  bindkey -M emacs '^[[1;5C' forward-word 2>/dev/null       # Ctrl-→ (one word)
  bindkey -M viins '^[[1;5C' forward-word 2>/dev/null
  # Ctrl-N / Ctrl-P and Shift-↓ / Shift-↑ move through the list (and keep their old job
  # when there's no list).
  zle -N axle-suggest-next; zle -N axle-suggest-prev
  for _axle_km in emacs viins; do
    for _axle_k in '^N' '^[[1;2B'; do
      _axle_sg_fallback[$_axle_km$'\x1f'${(g:c:)_axle_k}]=${${(z)"$(bindkey -M $_axle_km $_axle_k)"}[2]}
      bindkey -M $_axle_km $_axle_k axle-suggest-next
    done
    for _axle_k in '^P' '^[[1;2A'; do
      _axle_sg_fallback[$_axle_km$'\x1f'${(g:c:)_axle_k}]=${${(z)"$(bindkey -M $_axle_km $_axle_k)"}[2]}
      bindkey -M $_axle_km $_axle_k axle-suggest-prev
    done
  done
  unset _axle_km _axle_k
  _axle_hook_cmd command-done _axle_sg_cmd_done
fi
