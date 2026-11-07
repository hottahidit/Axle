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
zmodload zsh/mathfunc 2>/dev/null

typeset -gA _axle_jump_count _axle_jump_last
typeset -g  _axle_jump_mtime=''
typeset -ga _axle_jump_more            # folders from elsewhere, ranked below yours (_axle_jump_load_more)

# Folder statistics from the history log, recomputed only when the log has changed.
_axle_jump_load() {
  local -a st
  zstat -A st +mtime -- $_axle_hist_file 2>/dev/null || return 1
  [[ $st[1] == $_axle_jump_mtime ]] && return 0
  _axle_jump_mtime=$st[1]
  _axle_jump_count=() _axle_jump_last=()
  local dir n last
  command awk -F'\t' 'NF == 6 { n[$4]++; if ($1 > l[$4]) l[$4] = $1 }
                      END { for (d in n) print n[d] "\t" l[d] "\t" d }' $_axle_hist_file |
  while IFS=$'\t' read -r n last dir; do
    _axle_jump_count[$dir]=$n _axle_jump_last[$dir]=$last
  done
}

# Folders matching the words, best first (reply=()).
_axle_jump_rank() {
  setopt localoptions extendedglob
  _axle_jump_load
  (( $+functions[_axle_jump_load_more] )) && _axle_jump_load_more
  local -a words=("$@") scored
  local -aU dirs=(${(k)_axle_jump_count})
  (( $# )) && dirs+=($_axle_jump_more)
  local dir pat='(#i)*' w
  for w in $words; do pat+="${(b)w}*"; done
  local last=${(b)words[-1]}
  local -i age
  local -F score
  for dir in $dirs; do
    [[ $dir != $PWD ]] || continue
    if (( ${#words} )); then
      [[ $dir == ${~pat} && ${dir:t} == (#i)*$~last* ]] || continue
    fi
    [[ -d $dir ]] || continue
    age=$(( EPOCHSECONDS - ${_axle_jump_last[$dir]:-0} ))
    score=${_axle_jump_count[$dir]:-0.1}           # (one you've never worked in: below all)
    if   (( age < 3600 ));   then (( score *= 4 ))
    elif (( age < 86400 ));  then (( score *= 2 ))
    elif (( age < 604800 )); then (( score *= 0.5 ))
    else                          (( score *= 0.25 ))
    fi
    scored+=("${(l:12::0:)$(( int(score * 100) ))}"$'\x1f'"$dir")
  done
  reply=("${(@)${(@O)scored}#*$'\x1f'}")
  (( ${#scored} )) || reply=()
}

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
