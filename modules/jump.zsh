# jump: `j <words>` takes you to the folder you most likely mean, ranked by where you
# actually work: the folders you run commands in, weighted by how often and how recently.
#
#   j api          the best folder whose name matches "api"
#   j re ax        words match the path in order, the last one the folder's own name
#   j              your top folders          j -l <words>   list matches, don't go
#   j -            back to the previous folder
#   j <path>       an existing path just works, like cd
# Tab after `j <words>` offers the matches, best first.
#
#   AXLE_JUMP_CMD=j     the command's name

: ${AXLE_JUMP_CMD:=j}
# The ranking (_axle_jump_rank) is in lib/rank.zsh, shared with `axle run`.

_axle_jump() {
  local -a reply
  case $1 in
    -)  cd - ; return ;;
    -l) shift; _axle_jump_rank "$@"
        print -rl -- ${${reply[1,20]}/#$HOME/\~}
        return ;;
    -h|--help) sed -n '2,10s/^# \{0,1\}//p' $AXLE_ROOT/modules/jump.zsh; return ;;
  esac
  if (( ! $# )); then
    _axle_jump_rank
    (( ${#reply} )) || { print -r -- "axle jump: no folders recorded yet; work in a few and try again"; return 1 }
    local -i i
    for i in {1..${#reply[1,10]}}; do print -r -- "  ${(l:2:)i}  ${reply[i]/#$HOME/~}"; done
    return
  fi
  # A real path (also what Tab completion leaves behind): just go there.
  local target=${@[-1]/#\~/$HOME}
  if [[ -d $target ]]; then cd -- $target; return; fi
  _axle_jump_rank "$@"
  if (( ! ${#reply} )); then
    print -u2 "axle jump: no folder matches '$*'"
    return 1
  fi
  cd -- $reply[1]
}

# Tab completion: the matching folders, best first.
_axle_jump_complete() {
  local -a reply
  _axle_jump_rank "${(@)words[2,CURRENT]}"
  (( ${#reply} )) || return 1
  compadd -U -V axle-jump -Q -- "${(@)reply/#$HOME/~}"
}

functions[$AXLE_JUMP_CMD]='_axle_jump "$@"'
(( $+functions[compdef] )) && compdef _axle_jump_complete $AXLE_JUMP_CMD
axle_command jump _axle_jump tool "jump <words>  ($AXLE_JUMP_CMD)" 'cd to the folder you most likely mean'
