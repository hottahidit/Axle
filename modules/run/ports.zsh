# Ports for `axle run`: who holds a port, the next free
# one, giving a service another port, and what to do when its port is taken. Loaded when
# first needed.

# Who listens on <port>: REPLY = pid ('' if it can't be seen, e.g. another user's or a
# Windows program under WSL), _axle_run_holder = its name. Linux: /proc, no subprocess;
# elsewhere: lsof.
_axle_run_port_holder() {
  setopt localoptions extendedglob
  local port=$1 hex f line inode='' pid
  REPLY=''
  typeset -g _axle_run_holder=''
  if [[ -r /proc/net/tcp ]]; then
    printf -v hex '%04X' $port
    for f in /proc/net/tcp /proc/net/tcp6; do
      [[ -r $f ]] || continue
      while IFS= read -r line; do
        local -a w=(${=line})
        # local_address is HOST:PORT in hex; st 0A = listening; field 10 = the socket's inode
        [[ ${w[2]##*:} == $hex && $w[4] == 0A ]] && { inode=$w[10]; break 2 }
      done < $f
    done
    [[ -n $inode && $inode != 0 ]] || return 1
    local -a links
    for f in /proc/<->/fd/<->(N); do
      zstat -L -A links +link -- $f 2>/dev/null || continue
      if [[ $links[1] == "socket:[$inode]" ]]; then
        pid=${${f#/proc/}%%/*}
        REPLY=$pid
        [[ -r /proc/$pid/comm ]] && IFS= read -r _axle_run_holder < /proc/$pid/comm
        return 0
      fi
    done
    return 1
  fi
  whence -p lsof >/dev/null || return 1
  local -a pids=(${(f)"$(command lsof -nP -iTCP:$port -sTCP:LISTEN -t 2>/dev/null)"})
  pid=$pids[1]
  [[ -n $pid ]] || return 1
  REPLY=$pid
  _axle_run_holder=$(command ps -o comm= -p $pid 2>/dev/null)
  _axle_run_holder=${_axle_run_holder:t}
  return 0
}

# The axle run service using <port>, if any (REPLY = its name).
_axle_run_port_service() {
  local d
  for d in $_axle_run_dir/services/*(N/); do
    _axle_run_get $d port && [[ $REPLY == $1 ]] || continue
    _axle_run_alive $d || continue
    REPLY=${d:t}
    return 0
  done
  REPLY=''
  return 1
}

# The first port after <port> that nothing answers on and no service of ours has
# claimed (_axle_run_freed).
_axle_run_free_port() {
  local -i p=$1
  local REPLY
  typeset -g _axle_run_freed=''
  while (( ++p <= $1 + 100 && p < 65536 )); do
    _axle_run_port_up $p && continue
    _axle_run_port_service $p && continue
    _axle_run_freed=$p
    return 0
  done
  return 1
}

# Give the detected command another port, the way its framework takes one
# (_axle_run_portway). Returns 1 when it can't be changed.
_axle_run_apply_port() {
  local port=$1 way=$_axle_run_portway
  local -i i
  case $way in
    flag:*)
      local flag=${way#flag:}
      i=${_axle_run_cmd[(ie)$flag]}
      if (( i <= ${#_axle_run_cmd} )); then _axle_run_cmd[i+1]=$port
      else _axle_run_cmd+=($flag $port); fi ;;
    script:*)
      local flag=${way#script:}
      if [[ $_axle_run_cmd[1] == npm ]]; then _axle_run_cmd+=(-- $flag $port)
      else _axle_run_cmd+=($flag $port); fi ;;
    django)
      i=${_axle_run_cmd[(ie)runserver]}
      if [[ ${_axle_run_cmd[i+1]} == [0-9]## ]]; then _axle_run_cmd[i+1]=$port
      else _axle_run_cmd[i,i]=(runserver $port); fi ;;
    last)
      _axle_run_cmd[-1]=$port ;;
    python)                                        # modules/run/py/sitecustomize.py
      local hook=PYTHONPATH=$AXLE_ROOT/modules/run/py
      _axle_run_env=(${_axle_run_env:#AXLE_RUN_PORT=*} AXLE_RUN_PORT=$port)
      [[ -n ${(M)_axle_run_env:#$hook*} ]] || _axle_run_env+=($hook${PYTHONPATH:+:$PYTHONPATH}) ;;
    env:*)
      local var=${way#env:}
      _axle_run_env=(${_axle_run_env:#$var=*} $var=$port) ;;
    *) return 1 ;;
  esac
  _axle_run_port=$port
  return 0
}

# Before starting a service: is its port free? If not, choose (in a terminal) or take
# the next free port (without one). Returns 1 to cancel.
_axle_run_resolve_port() {
  local root=$1 name=$2 port=$_axle_run_port REPLY
  [[ -n $port ]] || return 0
  _axle_run_port_up $port || return 0
  local muted=${_axle_c[muted]:-244} warn=${_axle_c[warn]:-yellow}
  local who='' other='' pid=''
  if _axle_run_port_service $port; then
    other=$REPLY who="your service $REPLY (axle run)"
  elif _axle_run_port_holder $port; then
    pid=$REPLY who="$_axle_run_holder (pid $REPLY)"
  else
    who='a program not visible from here'
  fi
  local next=''
  [[ -n $_axle_run_portway ]] && _axle_run_free_port $port && next=$_axle_run_freed
  # Another checkout of this project (a git worktree) has it: the next one, unasked.
  if [[ -n $other && -n $next ]]; then
    local -a reply mine
    _axle_run_checkout $root && mine=($reply)
    _axle_run_get $_axle_run_dir/services/$other root
    if (( ${#mine} )) && _axle_run_checkout $REPLY && [[ $reply[1] == $mine[1] && $reply[2] != $mine[2] ]]; then
      _axle_printp "%F{$muted}(port $port: ${other//\%/%%}, another checkout of this project; this one gets $next)%f"
      _axle_run_apply_port $next
      return 0
    fi
  fi
  _axle_printp "%F{$warn}!%f Port $port is taken by ${who//\%/%%}."
  [[ -z $next && -z $_axle_run_portway ]] &&
    _axle_printp "%F{$muted}  (its command can't be given another port)%f"
  local -a opts=()
  [[ -n $next ]]  && opts+=("Use port $next instead:next")
  [[ -n $other ]] && opts+=("Stop $other, then run here:stop")
  [[ -n $pid ]]   && opts+=("Stop ${_axle_run_holder//:/ } (pid $pid), then run here:kill")
  opts+=("Cancel:cancel")
  local choice=${${next:+next}:-cancel}
  if _axle_ui_tty; then
    axle_select "What now?" $choice $opts || return 1
    choice=$REPLY
  elif [[ -n $next ]]; then
    _axle_printp "%F{$muted}(no terminal to ask in: using port $next)%f"
  fi
  case $choice in
    next) _axle_run_apply_port $next ;;
    stop) _axle_run_stop_one $other && print -r -- "stopped $other" ;;
    kill)
      axle_confirm "Stop ${_axle_run_holder} (pid $pid)? It isn't started by axle run." n || return 1
      kill -TERM $pid 2>/dev/null || { print -u2 -r -- "axle run: can't stop pid $pid"; return 1 }
      local -i i
      for i in {1..30}; do _axle_run_port_up $port || break; zselect -t 10; done
      _axle_run_port_up $port && { print -u2 -r -- "axle run: port $port is still taken"; return 1 } ;;
    *) return 1 ;;
  esac
  return 0
}
