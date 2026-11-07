# axle run group: several projects started and stopped together (a frontend repo, an API
# repo, a worker...). A group is a list of project folders, kept in axle run's state
# (groups/<name>, one folder a line).
#
#   axle run group                      the groups
#   axle run group dev add [path...]    add this project (or those)
#   axle run group dev rm [path...]     take this project (or those) out; no path, no group
#   axle run group dev                  start them all, in the background (each asked as
#                                       axle run asks)
#   axle run group dev stop             stop all their services

_axle_run_group_file() { REPLY=$_axle_run_dir/groups/$1 }

# A group's folders (reply).
_axle_run_group_load() {
  local REPLY line
  reply=()
  _axle_run_group_file $1
  [[ -r $REPLY ]] || return 1
  while IFS= read -r line; do [[ -n $line ]] && reply+=($line); done < $REPLY
  return 0
}

_axle_run_group_cmd() {
  setopt localoptions extendedglob
  local name=$1 action=$2 REPLY muted=${_axle_c[muted]:-244}
  local -a reply dirs
  _axle_run_state_init
  if [[ -z $name ]]; then                          # the list
    local f
    local -a all=($_axle_run_dir/groups/*(N.:t))
    (( ${#all} )) || { print -r -- "no groups (axle run group <name> add, in a project)"; return 0 }
    for f in $all; do
      _axle_run_group_load $f
      _axle_printp "%B${f//\%/%%}%b  %F{$muted}${(j:, :)${(@)reply:t}//\%/%%}%f"
    done
    return 0
  fi
  if [[ $name != [A-Za-z0-9_.-]## ]]; then
    print -u2 -r -- "axle run group: a name of letters, digits, . _ -"; return 1
  fi
  _axle_run_group_file $name; local file=$REPLY
  shift $(( $# >= 2 ? 2 : 1 ))
  case $action in
    add|rm)
      local p
      local -a given=()
      if (( $# )); then
        for p; do
          p=${${p/#\~/$HOME}:a}
          [[ -d $p ]] || { print -u2 -r -- "axle run group: no folder ${p/#$HOME/~}"; return 1 }
          given+=($p)
        done
      elif [[ $action == add ]]; then
        _axle_run_root_here || return 1
        given=($REPLY)
      fi
      _axle_run_group_load $name; dirs=($reply)
      if [[ $action == add ]]; then
        for p in $given; do (( ${dirs[(Ie)$p]} )) || dirs+=($p); done
      elif (( ${#given} )); then
        for p in $given; do dirs=(${dirs:#$p}); done
      else
        dirs=()
      fi
      command mkdir -p -m 700 -- ${file:h}
      if (( ${#dirs} )); then
        print -rl -- $dirs >| $file
        print -r -- "$name: ${(j:, :)${(@)dirs:t}}"
      else
        command rm -f -- $file
        print -r -- "$name: no more"
      fi ;;
    stop)
      _axle_run_group_load $name || { print -u2 -r -- "axle run group: no group $name"; return 1 }
      dirs=($reply)
      local svc root
      local -i n=0
      _axle_run_services
      for svc in $reply; do
        _axle_run_get $_axle_run_dir/services/$svc root; root=$REPLY
        local p
        for p in $dirs; do
          if [[ $root == $p || $root == $p/* ]]; then
            _axle_run_stop_one $svc && print -r -- "stopped $svc" && _axle_run_watch_stopped $svc && (( n++ ))
            break
          fi
        done
      done
      (( n )) || print -r -- "$name: nothing running" ;;
    '')
      _axle_run_group_load $name || { print -u2 -r -- "axle run group: no group $name (axle run group $name add, in a project)"; return 1 }
      dirs=($reply)
      local p
      local -a failed=()
      for p in $dirs; do
        _axle_printp "%F{$muted}── ${${p/#$HOME/~}//\%/%%}%f"
        if [[ ! -d $p ]]; then failed+=(${p:t}); print -u2 -r -- "  gone: ${p/#$HOME/~}"; continue; fi
        _axle_cmd_run $p --bg || failed+=(${p:t})
      done
      (( ${#failed} )) && { _axle_printp "%F{${_axle_c[error]:-red}}✘%f didn't start: ${(j:, :)failed}"; return 1 }
      return 0 ;;
    *)
      print -u2 -r -- "axle run group: $action? (add, rm, stop, or nothing to start them)"
      return 1 ;;
  esac
}
