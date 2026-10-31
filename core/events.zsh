# The axle tool's core: its own command events (so it works under any prompt), the hooks
# API built on them, and the shared command history that suggest, jump, search and stats
# read.
#
# Hooks
#   axle hook <event> <function>   axle hook rm <event> <function>   axle hook ls
#   command-start  before a command runs              $1 = the command line
#   command-done   after it finishes                  $1 = exit code, $2 = seconds, $3 = command
#   prompt         before each prompt is drawn
#   dir            the directory changed              $1 = new directory
#   expand         Alt-i toggled (Benzene)            $1 = 1 expanded, 0 collapsed
#   During command-done, $_axle_ev_dir is where the command ran and $_axle_ev_prev the
#   command before it.
#
# History
#   Every command is appended to ${XDG_DATA_HOME:-~/.local/share}/axle/history, one line
#   each: epoch <TAB> exit <TAB> seconds <TAB> dir <TAB> previous command <TAB> command
#   (newlines in commands written as \n). Lines typed with a leading space aren't recorded.

zmodload zsh/datetime 2>/dev/null
autoload -Uz add-zsh-hook

for _axle_e in command_start command_done prompt expand dir; do
  (( ${(P)+${:-_axle_hook_$_axle_e}} )) || typeset -ga _axle_hook_$_axle_e
done
unset _axle_e

# --- hooks ------------------------------------------------------------------------

# The engine calls this at each event; hooks run in order, in this shell.
_axle_emit() {
  local event=${1//-/_} fn; shift
  local -a fns=(${(P)${:-_axle_hook_$event}})
  for fn in $fns; do
    (( $+functions[$fn] )) && $fn "$@"      # (not $commands: its first use scans all of PATH)
  done
  return 0
}

_axle_hook_cmd() {
  local -a events=(command-start command-done prompt expand dir)
  case $1 in
    ls)
      local e var
      for e in $events; do
        var=_axle_hook_${e//-/_}
        (( ${#${(P)var}} )) && print -r -- "${(r:14:)e} ${(P)var}"
      done ;;
    rm)
      (( ${events[(Ie)$2]} )) || { print -u2 "axle hook: no event '$2' (events: $events)"; return 1 }
      local var=_axle_hook_${2//-/_}
      set -A $var ${(P)var:#$3} ;;
    *)
      (( ${events[(Ie)$1]} )) || { print -u2 "usage: axle hook <event> <function>  (events: $events)"; return 1 }
      [[ -n $2 ]] || { print -u2 "axle hook: which function?"; return 1 }
      local var=_axle_hook_${1//-/_}
      (( ${${(P)var}[(Ie)$2]} )) || set -A $var ${(P)var} $2 ;;
  esac
}


# --- events -----------------------------------------------------------------------
# The tool's own hooks (named _axt_*, which a theme reload never touches). zsh hands every
# precmd hook the command's real exit status, so this works after any prompt's hooks.

typeset -gF _axle_ev_start=0
typeset -g  _axle_ev_cmd='' _axle_ev_dir='' _axle_ev_prev=''
typeset -g  _axle_hist_file=${XDG_DATA_HOME:-$HOME/.local/share}/axle/history

_axt_preexec() {
  _axle_ev_start=$EPOCHREALTIME _axle_ev_cmd=$1 _axle_ev_dir=$PWD
  _axle_emit command-start "$1"
}

_axt_precmd() {
  local -i st=$?
  if (( _axle_ev_start )); then
    local -F secs=$(( EPOCHREALTIME - _axle_ev_start ))
    _axle_ev_start=0
    _axle_emit command-done $st $secs "$_axle_ev_cmd"
    _axle_hist_record $st $secs "$_axle_ev_cmd"
  fi
  _axle_emit prompt
}

_axt_chpwd() {
  _axle_emit dir "$PWD"
}

# Append a finished command to the history log (and remember it as "previous").
_axle_hist_record() {
  setopt localoptions extendedglob
  local cmd=$3
  [[ -n ${cmd//[[:space:]]/} && $cmd != ' '* ]] || return
  cmd=${cmd%%[[:space:]]#}
  local dur; printf -v dur '%.2f' $2
  mkdir -p ${_axle_hist_file:h} 2>/dev/null
  print -r -- "$EPOCHSECONDS"$'\t'"$1"$'\t'"$dur"$'\t'"${_axle_ev_dir:-$PWD}"$'\t'"${${_axle_ev_prev//$'\t'/ }//$'\n'/\\n}"$'\t'"${${cmd//$'\t'/ }//$'\n'/\\n}" >> $_axle_hist_file 2>/dev/null
  _axle_ev_prev=$cmd
}

add-zsh-hook preexec _axt_preexec
add-zsh-hook precmd  _axt_precmd
add-zsh-hook chpwd   _axt_chpwd
