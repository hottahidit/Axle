# ↑/↓ search history for what you've typed, in the spirit of zsh-history-substring-search:
# type part of a command (`docker`, `push`, `ssh nas`), then ↑ walks back through only the
# history lines that contain it, with the match highlighted; ↓ walks forward, and past the
# newest brings back what you typed. On an empty line ↑/↓ work as usual.
#
#   AXLE_UPSEARCH=1           0 = off
#   AXLE_UPSEARCH_PREFIX=0    1 = only lines that start with what you typed
#   AXLE_UPSEARCH_CASE=0      1 = case-sensitive
#   AXLE_UPSEARCH_STYLE='…'   how the match looks (region_highlight; default: bold accent)
#
# Widgets: axle-history-search-up, axle-history-search-down (bound to ↑ and ↓).

: ${AXLE_UPSEARCH:=1} ${AXLE_UPSEARCH_PREFIX:=0} ${AXLE_UPSEARCH_CASE:=0}

typeset -g  _axle_us_query='' _axle_us_last=''
typeset -ga _axle_us_hits
typeset -gi _axle_us_at=0

# The history events containing the query, newest first, each command once.
_axle_us_find() {
  setopt localoptions extendedglob
  local q=${(b)_axle_us_query} flags='' cmd
  (( AXLE_UPSEARCH_CASE )) || flags='(#i)'
  local pat="${flags}*${q}*"
  (( AXLE_UPSEARCH_PREFIX )) && pat="${flags}${q}*"
  local -a events=(${(kOn)history[(R)$~pat]})
  local -A seen
  _axle_us_hits=()
  for cmd in $events; do
    (( ${+seen[$history[$cmd]]} )) && continue
    [[ $history[$cmd] == $_axle_us_query ]] && continue     # what's already on the line
    seen[$history[$cmd]]=1
    _axle_us_hits+=($cmd)
  done
}

# Highlight the query inside the line.
_axle_us_mark() {
  setopt localoptions extendedglob
  region_highlight=(${region_highlight:#*memo=axle-us*})
  [[ -n $_axle_us_query ]] || return
  local hay=$BUFFER needle=$_axle_us_query
  (( AXLE_UPSEARCH_CASE )) || { hay=${(L)hay}; needle=${(L)needle} }
  local -i at=${hay[(i)$needle]}
  (( at <= ${#hay} )) || return
  local st=${AXLE_UPSEARCH_STYLE:-fg=${_axle_c[accent]:-magenta},bold}
  region_highlight+=("$(( at - 1 )) $(( at - 1 + ${#needle} )) $st,memo=axle-us")
}

_axle_us_move() {   # +1 older, -1 newer
  # A new search unless the line is still what the last step left there.
  if [[ -z $_axle_us_last || $BUFFER != $_axle_us_last ]]; then
    _axle_us_query=$BUFFER _axle_us_at=0
    _axle_us_find
  fi
  local -i n=${#_axle_us_hits} at=$(( _axle_us_at + $1 ))
  if (( at > n )); then
    zle -M "no older match for: $_axle_us_query" 2>/dev/null
    return 0
  fi
  _axle_us_at=$(( at < 0 ? 0 : at ))
  if (( _axle_us_at == 0 )); then
    BUFFER=$_axle_us_query                  # past the newest: what you typed
  else
    BUFFER=$history[$_axle_us_hits[_axle_us_at]]
  fi
  CURSOR=${#BUFFER}
  _axle_us_last=$BUFFER
  _axle_us_mark
}

# Mid-walk: the line is still what the last ↑/↓ put there.
_axle_us_walking() { [[ -n $_axle_us_last && $BUFFER == $_axle_us_last ]] }

axle-history-search-up() {
  # Empty line, or moving between the lines of a multi-line command: the usual ↑.
  if [[ -z $BUFFER ]] || { ! _axle_us_walking && [[ $LBUFFER == *$'\n'* ]] }; then
    zle .up-line-or-history; return
  fi
  _axle_us_move 1
}

axle-history-search-down() {
  if ! _axle_us_walking && [[ -z $BUFFER || $RBUFFER == *$'\n'* ]]; then
    zle .down-line-or-history; return
  fi
  _axle_us_move -1
}

# Editing the line ends the walk, and its highlight.
_axle_us_redraw() {
  _axle_us_walking && return
  _axle_us_last=''
  [[ -n ${(M)region_highlight:#*memo=axle-us*} ]] && region_highlight=(${region_highlight:#*memo=axle-us*})
}

# --- install -------------------------------------------------------------------------

if (( AXLE_UPSEARCH && $+builtins[zle] )); then
  zmodload zsh/parameter 2>/dev/null
  autoload -Uz add-zle-hook-widget
  zle -N axle-history-search-up
  zle -N axle-history-search-down
  add-zle-hook-widget line-pre-redraw _axle_us_redraw
  for _axle_km in emacs viins; do
    bindkey -M $_axle_km '^[[A' axle-history-search-up   '^[OA' axle-history-search-up \
                         '^[[B' axle-history-search-down '^[OB' axle-history-search-down
  done
  unset _axle_km
fi
