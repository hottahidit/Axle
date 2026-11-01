# Fix the last command, in the spirit of thefuck (and oh-my-zsh's sudo plugin): after a
# typo or a "permission denied", `fix` (or Esc Esc) puts the corrected command on the line
# for you to check, then Enter runs it. Nothing runs by itself.
#
#   gti status            → git status            (a command that doesn't exist)
#   git psuh              → git push              (a git subcommand that doesn't exist)
#   git push              → git push -u origin x  (the branch has no upstream yet)
#   cd Donwloads          → cd Downloads          (a file or folder that doesn't exist)
#   ./deploy.sh           → chmod +x ./deploy.sh && ./deploy.sh
#   apt install htop      → sudo apt install htop (needs root)
#
# Esc Esc on an empty line: the fix, or the last command with sudo. On a line you're
# typing: adds or removes sudo.
#
#   AXLE_FIX_CMD=fix      the command's name ('' = none; Esc Esc still works)
#   AXLE_FIX_KEY='^[^['   the key (Esc Esc; '' = none)

: ${AXLE_FIX_CMD=fix}
(( ${+AXLE_FIX_KEY} )) || typeset -g AXLE_FIX_KEY='^[^['

typeset -ga _axle_fix_git_cmds

# Edit distance where swapping two neighbouring letters counts as one mistake (REPLY).
_axle_fix_distance() {
  local a=$1 b=$2
  local -i la=${#a} lb=${#b} i j cost best
  local -A d
  for (( i = 0; i <= la; i++ )); do d[$i,0]=$i; done
  for (( j = 0; j <= lb; j++ )); do d[0,$j]=$j; done
  for (( i = 1; i <= la; i++ )); do
    for (( j = 1; j <= lb; j++ )); do
      [[ ${a[i]} == ${b[j]} ]] && cost=0 || cost=1
      best=$(( d[$((i-1)),$j] + 1 ))
      (( d[$i,$((j-1))] + 1 < best )) && best=$(( d[$i,$((j-1))] + 1 ))
      (( d[$((i-1)),$((j-1))] + cost < best )) && best=$(( d[$((i-1)),$((j-1))] + cost ))
      if (( i > 1 && j > 1 )) && [[ ${a[i]} == ${b[j-1]} && ${a[i-1]} == ${b[j]} ]]; then
        (( d[$((i-2)),$((j-2))] + 1 < best )) && best=$(( d[$((i-2)),$((j-2))] + 1 ))
      fi
      d[$i,$j]=$best
    done
  done
  REPLY=${d[$la,$lb]}
}

# The closest of the candidates to a word (REPLY), or status 1. Close means one mistake for
# short words, two for longer ones; ties go to the candidate you use most, then the shorter.
_axle_fix_closest() {
  local word=$1 c; shift
  local -i max=$(( ${#word} > 4 ? 2 : 1 )) best=99 uses bestuses=-1
  local found=''
  for c; do
    [[ $c == $word ]] && continue
    (( ${#c} - ${#word} <= max && ${#word} - ${#c} <= max )) || continue
    # Cheap first: share the first letter, or the first two are swapped (sl → ls).
    [[ ${c[1]} == ${word[1]} || ( ${c[1]} == ${word[2]} && ${c[2]} == ${word[1]} ) ]] || continue
    _axle_fix_distance $word $c
    (( REPLY <= max )) || continue
    uses=${_axle_sg_count[$c]:-0}
    if (( REPLY < best || ( REPLY == best && uses > bestuses ) ||
          ( REPLY == best && uses == bestuses && ${#c} < ${#found} ) )); then
      best=$REPLY found=$c bestuses=$uses
    fi
  done
  REPLY=$found
  [[ -n $found ]]
}

# Commands worth comparing a typo against: what you've run, aliases, functions, builtins,
# then (only if that finds nothing) everything on PATH.
_axle_fix_command() {
  local word=$1 c
  local -a mine=()
  for c in ${(k)_axle_sg_count}; do mine+=(${c%% *}); done
  mine=(${(u)mine} ${(k)aliases} ${(k)builtins} ${${(k)functions}:#_*})
  _axle_fix_closest $word $mine && return 0
  _axle_fix_closest $word ${(k)commands}
}

# The best fix for a command that failed with <exit> in <dir> (REPLY), or status 1.
_axle_fix_suggest() {
  setopt localoptions extendedglob
  local cmd=$1 dir=${3:-$PWD}
  local -i exit=$2
  local -a w=(${(z)cmd})
  (( ${#w} )) || return 1
  local first=${(Q)w[1]} word arg new i
  REPLY=''

  # Not executable: make it so, then run it.
  if (( exit == 126 )) && [[ $first == */* && -f ${~first} && ! -x ${~first} ]]; then
    REPLY="chmod +x ${w[1]} && $cmd"; return 0
  fi

  if [[ $first == git && exit -ne 0 ]]; then
    # git push on a branch with no upstream yet.
    if [[ $w[2] == push && ${#w} == 2 ]] && ! command git -C $dir rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
      local branch=$(command git -C $dir symbolic-ref --short HEAD 2>/dev/null)
      local remote=$(command git -C $dir remote 2>/dev/null | head -1)
      [[ -n $branch && -n $remote ]] && { REPLY="git push -u ${remote} ${branch}"; return 0 }
    fi
    # A git subcommand that doesn't exist (git's own list, and your aliases).
    if [[ -n $w[2] && $w[2] != -* ]]; then
      (( ${#_axle_fix_git_cmds} )) ||
        _axle_fix_git_cmds=(${(f)"$(command git --list-cmds=main,others,alias,nohelpers 2>/dev/null)"})
      if (( ${#_axle_fix_git_cmds} )) && (( ! ${_axle_fix_git_cmds[(Ie)$w[2]]} )) &&
         _axle_fix_closest $w[2] $_axle_fix_git_cmds; then
        w[2]=$REPLY; REPLY=${(j: :)w}; return 0
      fi
    fi
  fi

  # A command that doesn't exist.
  if (( exit == 127 )) && [[ $first != */* ]]; then
    _axle_fix_command $first && { w[1]=$REPLY; REPLY=${(j: :)w}; return 0 }
    return 1
  fi

  # A file or folder that doesn't exist: the closest name in its folder.
  if (( exit != 0 )); then
    for (( i = 2; i <= ${#w}; i++ )); do
      arg=${(Q)w[i]}
      [[ $arg == -* || $arg == *[\*\?\[\$\`]* || -z $arg ]] && continue
      local full=${~arg}
      [[ $full != /* ]] && full=$dir/$full
      [[ -e $full ]] && continue
      local parent=${full:h} name=${full:t}
      [[ -d $parent ]] || continue
      local -a entries=($parent/*(DN:t))
      new=''
      # Only the case differs (readme.md → README.md), else the closest name.
      new=${(M)entries:#(#i)${(b)name}}
      [[ -n $new ]] || { _axle_fix_closest $name $entries && new=$REPLY }
      if [[ -n $new ]]; then
        [[ $arg == */* ]] && new=${arg:h}/$new
        w[i]=${(q-)new}
        REPLY=${(j: :)w}; return 0
      fi
    done
  fi

  # Needs root.
  if (( exit != 0 )) && [[ $first != (sudo|doas) ]]; then
    local needs=0
    case $first in
      apt|apt-get|aptitude|dnf|yum|zypper|pacman|apk|snap|flatpak)
        [[ ${w[2]} == (install|remove|purge|update|upgrade|autoremove|dist-upgrade|full-upgrade|reinstall|-S*|-R*|-U*|add|del) ]] && needs=1 ;;
      systemctl|service)
        [[ ${(j: :)w} == *(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload)* ]] && needs=1 ;;
      mount|umount|modprobe|useradd|userdel|usermod|groupadd|ufw|iptables|nft|reboot|shutdown|poweroff|chroot|visudo)
        needs=1 ;;
      chown|chmod|chgrp)
        local last=${~${(Q)w[-1]}}
        [[ -e $last && ! -O $last ]] && needs=1 ;;
      tee|cp|mv|rm|mkdir|touch|ln|vi|vim|nvim|nano)
        local t=${~${(Q)w[-1]}}
        [[ $t == /* && $t != $HOME(|/*) && $t != /tmp(|/*) ]] && needs=1 ;;
    esac
    (( needs )) && { REPLY="sudo $cmd"; return 0 }
  fi
  return 1
}

# `fix`: the corrected last command, on the line to check.
_axle_fix_cmd() {
  local last=$_axle_ev_last_cmd
  [[ -n $last ]] || { print -u2 "axle: nothing to fix yet"; return 1 }
  if (( _axle_ev_last_exit == 0 )); then
    print -u2 -r -- "axle: the last command worked: $last"; return 1
  fi
  if _axle_fix_suggest "$last" $_axle_ev_last_exit "$_axle_ev_last_dir"; then
    print -z -r -- "$REPLY"
  else
    print -u2 -r -- "axle: no fix found for: $last"; return 1
  fi
}

# Esc Esc: on an empty line the fix (or the last command with sudo); else toggle sudo.
axle-fix() {
  if [[ -z $BUFFER ]]; then
    local last=$_axle_ev_last_cmd
    [[ -n $last ]] || return 0
    if (( _axle_ev_last_exit )) && _axle_fix_suggest "$last" $_axle_ev_last_exit "$_axle_ev_last_dir"; then
      BUFFER=$REPLY
    else
      BUFFER="sudo $last"
    fi
  elif [[ $BUFFER == sudo\ * ]]; then
    BUFFER=${BUFFER#sudo }
  else
    BUFFER="sudo $BUFFER"
  fi
  CURSOR=${#BUFFER}
}

# --- install -------------------------------------------------------------------------

if [[ -n $AXLE_FIX_CMD ]]; then
  functions[$AXLE_FIX_CMD]='_axle_fix_cmd "$@"'
  axle_command fix _axle_fix_cmd tool "fix  ($AXLE_FIX_CMD)" 'correct the last command (on the line, to check)'
fi
if (( $+builtins[zle] )) && [[ -n $AXLE_FIX_KEY ]]; then
  zle -N axle-fix
  bindkey -M emacs "$AXLE_FIX_KEY" axle-fix
fi
