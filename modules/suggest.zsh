# Smart autosuggestions, in the spirit of zsh-autosuggestions: as you type, the likeliest
# completion of the line appears in grey after the cursor. → or End accepts it; Ctrl-→ or
# Alt-f accepts one word; Enter runs what you typed. Ctrl-N or Shift-↓ opens a list of the
# other likely options below the line (Ctrl-P / Shift-↑ move back); typing closes it.
#
# Suggestions come from strategies, tried in order until one has an answer:
#   smart       what Axle has seen you run, ranked by this directory, the command before
#               (git add . → git commit -m …), how often and how recently; commands that
#               have only ever failed are left out
#   history     your shell history, newest first (what zsh-autosuggestions does)
#   completion  a command name for the first word, or a real file or folder path
# Lines typed with a leading space aren't recorded (as with HIST_IGNORE_SPACE).
#
#   AXLE_SUGGEST=1                          0 = off (or `axle-suggest-toggle`)
#   AXLE_SUGGEST_STRATEGY=(smart history completion)
#   AXLE_SUGGEST_STYLE='fg=…'               how the suggestion looks (region_highlight)
#   AXLE_SUGGEST_IGNORE=''                  zsh pattern of lines never to suggest, e.g. 'cd *'
#   AXLE_SUGGEST_MAX_BUFFER=0               no suggestions past this many characters (0 = any)
#   AXLE_SUGGEST_LIST=5                     options in the Ctrl-N list
#   AXLE_SUGGEST_LOAD=4000                  recorded commands to learn from
#
# Widgets to bind as you like: axle-suggest-accept, axle-suggest-execute (accept and run),
# axle-suggest-partial (next word), axle-suggest-clear, axle-suggest-toggle,
# axle-suggest-next / axle-suggest-prev (open and move through the list).
# Steps aside when zsh-autosuggestions is loaded.

: ${AXLE_SUGGEST:=1} ${AXLE_SUGGEST_LOAD:=4000} ${AXLE_SUGGEST_LIST:=5} ${AXLE_SUGGEST_MAX_BUFFER:=0}
(( ${+AXLE_SUGGEST_STRATEGY} )) || typeset -ga AXLE_SUGGEST_STRATEGY=(smart history completion)
(( ${+AXLE_SUGGEST_IGNORE} ))   || typeset -g  AXLE_SUGGEST_IGNORE=''
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

# smart: what Axle has seen, best first (reply=()).
_axle_sg_smart() {
  local prefix=$1 c here after
  local -i score age last
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
}

# history: the shell history, newest first (reply=()). $history is keyed by event
# number, and (R) on it returns every match, so take the event numbers newest first.
_axle_sg_history() {
  local prefix=$1 event c
  local -a events=(${(kOn)history[(R)${(b)prefix}?*]})
  reply=()
  for event in ${events[1,300]}; do
    c=$history[$event]
    [[ $c != *$'\n'* ]] && (( ! ${reply[(Ie)$c]} )) && reply+=("$c")
    (( ${#reply} >= $2 )) && break
  done
}

# completion: finish the word being typed (reply=()). The first word is a command
# (aliases, functions, builtins, programs; shortest first); later words are file or
# folder paths, folders with a trailing /.
_axle_sg_completion() {
  setopt localoptions extendedglob nullglob
  local prefix=$1 word=${1##*[[:space:]]} head=${1%"${1##*[[:space:]]}"} c
  reply=()
  [[ -n $word && $word != *[\$\`\"\']* ]] || return
  if [[ $head != *[^[:space:]]* ]]; then
    local -a names=(${(k)aliases[(I)${(b)word}?*]} ${(k)builtins[(I)${(b)word}?*]}
                    ${${(k)functions[(I)${(b)word}?*]}:#_*} ${(k)commands[(I)${(b)word}?*]})
    names=(${(u)names})
    local -a sorted=()
    for c in $names; do sorted+=("${(l:4::0:)#c}"$'\x1f'"$c"); done
    for c in ${${(o)sorted}#*$'\x1f'}; do reply+=("$head$c"); (( ${#reply} >= $2 )) && break; done
  else
    local base=${word/#\~/$HOME} shown
    local -a hits=(${(b)base}*)
    [[ ${base:t} == .* ]] || hits=(${hits:#*/.*} ${hits:#.*})    # hidden files only if asked
    hits=(${(u)hits})
    for c in ${(o)hits}; do
      [[ ${c:t} == .* && ${base:t} != .* ]] && continue
      shown=${c/#$HOME/\~}
      [[ $word != \~* ]] && shown=$c
      [[ -d $c ]] && shown+=/
      reply+=("$head${shown//(#m)[[:space:]\\\'\"\$\`\&\;\|\<\>\(\)\*\?\[\]]/\\$MATCH}")
      (( ${#reply} >= $2 )) && break
    done
    # Keep exactly what was typed as the start (completion escapes only the new part).
    reply=(${(M)reply:#${(b)prefix}?*})
  fi
}

# The likeliest completions of $1, best first, at most $2 (reply=()): the strategies in
# order, without duplicates or ignored lines.
_axle_sg_rank() {
  local prefix=$1 strategy c
  local -i max=${2:-5}
  local -a found=()
  for strategy in $AXLE_SUGGEST_STRATEGY; do
    (( $+functions[_axle_sg_$strategy] )) || continue
    reply=(); _axle_sg_$strategy "$prefix" $max
    for c in $reply; do
      (( ${found[(Ie)$c]} )) && continue
      # Known to have only ever failed: never suggested, whichever strategy found it.
      (( ${+_axle_sg_count[$c]} && ! ${_axle_sg_ok[$c]:-0} )) && continue
      [[ -n $AXLE_SUGGEST_IGNORE && $c == ${~AXLE_SUGGEST_IGNORE} ]] && continue
      found+=("$c")
    done
    (( ${#found} >= max )) && break
  done
  reply=(${found[1,max]})       # (quoted, an empty slice would give one empty word)
}

# The single best completion of $1 (REPLY).
_axle_sg_find() {
  local -a reply
  _axle_sg_rank "$1" 1
  REPLY=${reply[1]}
}

typeset -ga _axle_sg_list
typeset -gi _axle_sg_sel=1 _axle_sg_cursor=-1 _axle_sg_open=0 _axle_sg_hold=0
typeset -g  _axle_sg_ghost=''

# Widgets after which there's no suggestion until you edit (as zsh-autosuggestions):
# moving through history shows the history line as it is.
typeset -g _axle_sg_quiet='(up|down)-(line|history)*|*history-search*|*beginning-search*|history-substring-search-*|(beginning|end)-of-buffer-or-history|*history-incremental*|infer-*'

# Draw the selected option's rest as grey ghost text, and (when opened) the list below.
_axle_sg_render() {
  local ghost='' post=''
  (( ${#_axle_sg_list} )) && ghost=${_axle_sg_list[_axle_sg_sel]#$BUFFER}
  _axle_sg_ghost=$ghost
  region_highlight=(${region_highlight:#*memo=axle-suggest*})
  local -i base=${#BUFFER}
  local style=${AXLE_SUGGEST_STYLE:-fg=${_axle_c[suggest]:-${_axle_c[muted]:-244}}}
  post=$ghost
  [[ -n $ghost ]] && region_highlight+=("$base $(( base + ${#ghost} )) $style,memo=axle-suggest")
  if (( _axle_sg_open && ${#_axle_sg_list} > 1 )); then
    local item mark st
    local -i i start w=$(( ${COLUMNS:-80} - 6 ))
    (( w > 10 )) || w=10
    for i in {1..${#_axle_sg_list}}; do
      item=${_axle_sg_list[i]}
      (( ${#item} > w )) && item="${item[1,w-1]}…"
      if (( i == _axle_sg_sel )); then
        mark='  ▸ ' st="fg=${_axle_c[accent]:-magenta},bold"
      else
        mark='    ' st="fg=${_axle_c[muted]:-244}"
      fi
      start=$(( base + ${#post} + 1 ))
      post+=$'\n'"$mark$item"
      region_highlight+=("$start $(( base + ${#post} )) $st,memo=axle-suggest")
    done
  fi
  POSTDISPLAY=$post
}

_axle_sg_clear() {
  _axle_sg_list=() _axle_sg_ghost='' _axle_sg_open=0
  POSTDISPLAY=''
  region_highlight=(${region_highlight:#*memo=axle-suggest*})
}

# Before every redraw: recompute when the line or cursor changed.
_axle_sg_redraw() {
  (( AXLE_SUGGEST )) || { [[ -n $POSTDISPLAY && -n $_axle_sg_ghost ]] && _axle_sg_clear; return }
  # Tab completion shows its own list: step aside until the next key.
  if [[ $LASTWIDGET == (*complete*|*expand*|menu-select|*list*) ]]; then
    _axle_sg_clear; _axle_sg_buffer=$'\0'; return
  fi
  # History navigation (or our keys falling back to it): no suggestion until an edit.
  if (( _axle_sg_hold )) || [[ $LASTWIDGET == ${~_axle_sg_quiet} ]]; then
    _axle_sg_hold=0
    _axle_sg_clear; _axle_sg_buffer=$BUFFER _axle_sg_cursor=$CURSOR
    return
  fi
  [[ $BUFFER == $_axle_sg_buffer && $CURSOR == $_axle_sg_cursor ]] && return
  _axle_sg_buffer=$BUFFER _axle_sg_cursor=$CURSOR
  (( _axle_sg_ready )) || _axle_sg_init
  _axle_sg_list=() _axle_sg_sel=1 _axle_sg_open=0
  if [[ -n $BUFFER && CURSOR -eq ${#BUFFER} && $BUFFER != *$'\n'* ]] &&
     (( ! AXLE_SUGGEST_MAX_BUFFER || ${#BUFFER} <= AXLE_SUGGEST_MAX_BUFFER )); then
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
  _axle_sg_buffer=$BUFFER _axle_sg_cursor=$CURSOR _axle_sg_open=0
  # Finishing a chosen option word by word: keep just that one.
  if [[ $chosen != $BUFFER ]]; then
    _axle_sg_list=("$chosen") _axle_sg_sel=1
  else
    _axle_sg_list=()
  fi
  _axle_sg_render
}

# Open the list, or move through it (+1 / -1). Fails when there's nothing to choose from.
_axle_sg_cycle() {
  local -i n=${#_axle_sg_list}
  (( n > 1 && CURSOR == ${#BUFFER} )) || return 1
  if (( ! _axle_sg_open )); then
    (( $1 > 0 )) || return 1           # Ctrl-P with the list closed: its usual job
    _axle_sg_open=1
  fi
  _axle_sg_sel=$(( (_axle_sg_sel - 1 + $1 + n) % n + 1 ))
  _axle_sg_render
}

# Keys that open/move the list do their usual job when there's no list. The keymaps as they
# were are kept as copies (axle-orig-emacs, axle-orig-viins); a key's old widget is looked
# up there the first time it's needed, then remembered.
typeset -gA _axle_sg_fallback          # "keymap<US>keys" -> the widget they had before
_axle_sg_key_fallback() {
  # (While editing, $KEYMAP is "main", an alias of emacs or viins.)
  local km w
  for km in $KEYMAP emacs viins; do
    if (( ! ${+_axle_sg_fallback[$km$'\x1f'$KEYS]} )) && (( ${+keymaps} )) &&
       (( ${keymaps[(Ie)axle-orig-$km]} )); then
      _axle_sg_fallback[$km$'\x1f'$KEYS]=${${(z)"$(bindkey -M axle-orig-$km -- $KEYS)"}[2]}
    fi
    w=${_axle_sg_fallback[$km$'\x1f'$KEYS]}
    [[ -n $w && $w != undefined-key ]] && break
  done
  [[ -n $w && $w != undefined-key ]] || return
  [[ $w == ${~_axle_sg_quiet} ]] && _axle_sg_hold=1     # history: no suggestion on it
  zle $w
}
axle-suggest-next() { _axle_sg_cycle 1  || _axle_sg_key_fallback }
axle-suggest-prev() { _axle_sg_cycle -1 || _axle_sg_key_fallback }

# zsh-autosuggestions-style widgets, for your own key bindings.
axle-suggest-accept()  { _axle_sg_take || zle .end-of-line }
axle-suggest-partial() { _axle_sg_take word || zle .forward-word }
axle-suggest-execute() { _axle_sg_take; _axle_sg_clear; zle .accept-line }
axle-suggest-clear()   { _axle_sg_clear; _axle_sg_buffer=$BUFFER _axle_sg_cursor=$CURSOR }
axle-suggest-toggle()  {
  (( AXLE_SUGGEST ^= 1 ))
  if (( AXLE_SUGGEST )); then _axle_sg_buffer=$'\0'; _axle_sg_redraw; else _axle_sg_clear; fi
}

# Accepting all of it, or one word of it, from the usual movement keys.
_axle_sg_forward_char()    { _axle_sg_take       || zle .forward-char }
_axle_sg_end_of_line()     { _axle_sg_take       || zle .end-of-line }
_axle_sg_vi_forward_char() { _axle_sg_take       || zle .vi-forward-char }
_axle_sg_vi_end_of_line()  { _axle_sg_take       || zle .vi-end-of-line }
_axle_sg_vi_add_eol()      { _axle_sg_take; zle .vi-add-eol }
_axle_sg_forward_word()    { _axle_sg_take word  || zle .forward-word }
_axle_sg_emacs_fwd_word()  { _axle_sg_take word  || zle .emacs-forward-word }
_axle_sg_vi_fwd_word()     { _axle_sg_take word  || zle .vi-forward-word }
_axle_sg_vi_fwd_word_end() { _axle_sg_take word  || zle .vi-forward-word-end }
_axle_sg_vi_fwd_blank()    { _axle_sg_take word  || zle .vi-forward-blank-word }
_axle_sg_vi_fwd_blank_end(){ _axle_sg_take word  || zle .vi-forward-blank-word-end }
_axle_sg_accept_line()     { _axle_sg_clear; zle .accept-line }

typeset -gA _axle_sg_widgets=(
  forward-char _axle_sg_forward_char          end-of-line _axle_sg_end_of_line
  vi-forward-char _axle_sg_vi_forward_char    vi-end-of-line _axle_sg_vi_end_of_line
  vi-add-eol _axle_sg_vi_add_eol
  forward-word _axle_sg_forward_word          emacs-forward-word _axle_sg_emacs_fwd_word
  vi-forward-word _axle_sg_vi_fwd_word        vi-forward-word-end _axle_sg_vi_fwd_word_end
  vi-forward-blank-word _axle_sg_vi_fwd_blank vi-forward-blank-word-end _axle_sg_vi_fwd_blank_end
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
  # Ctrl-N / Shift-↓ open the list and move down; Ctrl-P / Shift-↑ move up. With nothing to
  # choose from they keep their usual job (history).
  zle -N axle-suggest-next; zle -N axle-suggest-prev
  for _axle_w in accept partial execute clear toggle; do zle -N axle-suggest-$_axle_w; done
  zmodload zsh/zleparameter 2>/dev/null
  for _axle_km in emacs viins; do
    # A copy of the keymap before we rebind, once (a reload keeps the first copy).
    (( ${keymaps[(Ie)axle-orig-$_axle_km]} )) || bindkey -N axle-orig-$_axle_km $_axle_km
    bindkey -M $_axle_km '^N' axle-suggest-next '^[[1;2B' axle-suggest-next \
                         '^P' axle-suggest-prev '^[[1;2A' axle-suggest-prev
  done
  unset _axle_km _axle_w
  _axle_hook_cmd command-done _axle_sg_cmd_done
fi
