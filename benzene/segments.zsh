# Benzene's extension points: your own segments, and the display of "drops" (tabs any
# program can put in the prompt by writing a small file). Part of the theme, so they work
# with or without the axle tool.
#
# Segments
#   axle segment add <name> <function> [left|right] [priority]
#   axle segment rm <name>         axle segment ls
#   The function sets REPLY to the text to show, or leaves it empty to hide. Keep it fast:
#   it runs every prompt (do slow work elsewhere and cache the result).
#   Helpers: axle_style <colour|role> <text>   coloured text in REPLY (% is escaped)
#            axle_alarm [1|2]                  red (1) or amber (2) bubble, never trimmed
#            axle_expanded                     true while the prompt is expanded (Alt-i)
#            axle_link <url> <styled text>     make it Ctrl+clickable
#   In AxoN, a segment shows only while it raises an alarm.
#
# Drops
#   A file in ~/.cache/axle/drops/<name> is shown as a tab in every open prompt. The axle
#   tool writes them (`axle drop`, tools/axle-drop); any program can also write one:
#   "key=value" lines, or just text.
#     text=deploying api      level=ok|info|warn|alarm     icon=…     link=https://…
#     expires=<epoch secs>    pid=<show while alive>       dir=<only under this path>
#     expanded=1 (only in the expanded view)
#   Alarm/warn drops always show; ok/info ones up to AXLE_DROP_MAX (2) while collapsed.
#   Drops are data, never run. Open prompts check for changes every AXLE_DROP_POLL seconds
#   (default 5; 0 = only at the next prompt) and redraw only when something changed.

typeset -gA _axle_ext_segments       # name -> function
typeset -g  _axle_drop_dir=${XDG_CACHE_HOME:-$HOME/.cache}/axle/drops
typeset -gi _axle_pinned=0
: ${AXLE_DROP_POLL:=5} ${AXLE_DROP_MAX:=2}

# --- for segment functions --------------------------------------------------------

axle_style() { REPLY="%F{${_axle_c[$1]:-$1}}${2//\%/%%}%f" }
axle_alarm() { _axle_alarm=${1:-1} }
axle_expanded() { (( ${_axle_detail:-0} )) }
axle_link() {
  if (( $+functions[_axle_link] )); then _axle_link "$1" "$2"; else REPLY=$2; fi
}

# --- segments ---------------------------------------------------------------------

_axle_segment_cmd() {
  case $1 in
    add)
      local name=$2 fn=$3 side=${4:-right} rank=$5
      [[ $name =~ '^[a-z0-9_-]+$' ]] ||
        { print -u2 "axle segment: names are lowercase letters, digits, - and _"; return 1 }
      [[ -n $fn ]] || { print -u2 "usage: axle segment add <name> <function> [left|right] [priority]"; return 1 }
      (( $+functions[_axle_seg_$name] )) && (( ! ${+_axle_ext_segments[$name]} )) &&
        { print -u2 "axle segment: '$name' is built in"; return 1 }
      _axle_ext_segments[$name]=$fn
      functions[_axle_seg_$name]="${(q)fn}"
      # AxoN: only while it raises an alarm.
      functions[_axle_axon_$name]="_axle_alarm=0; ${(q)fn}; (( _axle_alarm )) || REPLY=''"
      local list=AXLE_NOX_RIGHT
      [[ $side == left ]] && list=AXLE_NOX_LEFT
      (( ${${(P)list}[(Ie)$name]} )) || set -A $list ${(P)list} $name
      (( ${AXLE_NOX_CODE[(Ie)$name]} )) || AXLE_NOX_CODE+=($name)
      if (( ${+AXLE_AXON_SHOW} )) && (( ! ${AXLE_AXON_SHOW[(Ie)$name]} )); then
        AXLE_AXON_SHOW[${AXLE_AXON_SHOW[(i)exec]},0]=($name)   # before the run time
      fi
      # Importance: given, or just above the low-priority stats.
      AXLE_NOX_PRIORITY=(${AXLE_NOX_PRIORITY:#$name})
      local -i at=${rank:-${AXLE_NOX_PRIORITY[(i)load]}}
      AXLE_NOX_PRIORITY[at,0]=($name) ;;
    rm)
      local name=$2
      (( ${+_axle_ext_segments[$name]} )) || { print -u2 "axle segment: no added segment '$name'"; return 1 }
      unset "_axle_ext_segments[$name]"
      unfunction _axle_seg_$name _axle_axon_$name 2>/dev/null
      AXLE_NOX_LEFT=(${AXLE_NOX_LEFT:#$name}) AXLE_NOX_RIGHT=(${AXLE_NOX_RIGHT:#$name})
      AXLE_NOX_CODE=(${AXLE_NOX_CODE:#$name}) AXLE_NOX_PRIORITY=(${AXLE_NOX_PRIORITY:#$name})
      (( ${+AXLE_AXON_SHOW} )) && AXLE_AXON_SHOW=(${AXLE_AXON_SHOW:#$name}) ;;
    ls)
      local name
      for name in ${(ok)_axle_ext_segments}; do
        local side=right; (( ${AXLE_NOX_LEFT[(Ie)$name]} )) && side=left
        print -r -- "${(r:14:)name} ${(r:22:)_axle_ext_segments[$name]} $side, priority ${AXLE_NOX_PRIORITY[(ie)$name]}"
      done ;;
    *)
      print -u2 "usage: axle segment add <name> <function> [left|right] [priority] | rm <name> | ls"
      return 1 ;;
  esac
}

# --- drops ------------------------------------------------------------------------

# The segment: live drops, most urgent first. Alarm/warn drops are bubbles, always shown
# (they pin the segment, so it's never trimmed into (+N)); after them, at most
# AXLE_DROP_MAX ok/info drops while collapsed (all when expanded), the rest as "+N".
#   _axle_seg_drops [urgent]   only alarm/warn drops (AxoN)
_axle_seg_drops() {
  local -a files=($_axle_drop_dir/[^.]*(N.))
  (( ${#files} )) || return
  local f line key value sep=" %F{${_axle_c[sep]:-238}}${AXLE_SEP:-│}%f "
  local -a alarms warns others
  for f in $files; do
    local text='' level=info icon='' link='' dir='' pid='' expanded=0
    local -i expires=0 first=1
    while IFS= read -r line || [[ -n $line ]]; do
      if [[ $line == [a-z]##=* ]]; then
        key=${line%%=*} value=${line#*=}
        case $key in
          text) text=$value ;; level) level=$value ;; icon) icon=$value ;; link) link=$value ;;
          dir) dir=$value ;; pid) pid=$value ;; expires) expires=$value ;; expanded) expanded=$value ;;
        esac
      elif (( first )) && [[ -n $line ]]; then
        text=$line                         # a plain-text drop
      fi
      first=0
    done < $f
    # Expired, or its process is gone: clean it up.
    if (( expires && expires <= EPOCHSECONDS )) || { [[ -n $pid ]] && ! kill -0 $pid 2>/dev/null }; then
      rm -f -- $f; continue
    fi
    [[ -n $dir && ${PWD:A} != ${dir%/}(|/*) ]] && continue
    (( expanded && ! ${_axle_detail:-0} )) && continue
    [[ -n $text ]] || continue
    local shown="${icon:+${icon//\%/%%} }${text//\%/%%}"
    case $level in
      alarm) REPLY=$shown; _axle_pill 1 ;;
      warn)  REPLY=$shown; _axle_pill 2 ;;
      ok)    REPLY="%F{${_axle_c[ok]:-green}}$shown%f" ;;
      *)     REPLY="%F{${_axle_c[accent]:-magenta}}$shown%f" ;;
    esac
    [[ -n $link ]] && axle_link $link $REPLY
    case $level in
      alarm) alarms+=("$REPLY") ;;
      warn)  warns+=("$REPLY") ;;
      *)     others+=("$REPLY") ;;
    esac
  done
  (( ${#alarms} + ${#warns} )) && _axle_pinned=1
  [[ $1 == urgent ]] && others=()
  local -i keep=${AXLE_DROP_MAX:-2} more=0
  (( ${_axle_detail:-0} )) && keep=${#others}
  if (( ${#others} > keep )); then
    more=$(( ${#others} - keep )); others=(${others[1,keep]})
  fi
  local -a pieces=($alarms $warns $others)
  (( more )) && pieces+=("%F{${_axle_c[muted]:-244}}+$more%f")
  REPLY=${(pj:$sep:)pieces}
}

# For the redraw timer: how often to look for drop changes while at the prompt.
_axle_drop_poll() {
  REPLY=0
  (( AXLE_DROP_POLL > 0 )) && [[ -d $_axle_drop_dir ]] && REPLY=$AXLE_DROP_POLL
}

# Register the drops segment once (right side, just above the low-priority stats).
(( ${AXLE_NOX_RIGHT[(Ie)drops]} )) || AXLE_NOX_RIGHT[${AXLE_NOX_RIGHT[(i)load]},0]=(drops)
(( ${AXLE_NOX_CODE[(Ie)drops]} )) || AXLE_NOX_CODE[${AXLE_NOX_CODE[(i)battery]},0]=(drops)
(( ${AXLE_NOX_PRIORITY[(Ie)drops]} )) || AXLE_NOX_PRIORITY[${AXLE_NOX_PRIORITY[(i)load]},0]=(drops)
if (( ${+AXLE_AXON_SHOW} )) && (( ! ${AXLE_AXON_SHOW[(Ie)drops]} )); then
  AXLE_AXON_SHOW[${AXLE_AXON_SHOW[(i)exec]},0]=(drops)
fi
# AxoN shows drops only at warn/alarm level.
_axle_axon_drops() {
  _axle_seg_drops urgent
}
