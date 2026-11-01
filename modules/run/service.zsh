# Background services for `axle run` (M2 of docs/legionary/ROADMAP.md). Loaded when first
# needed.
#
# Each service has a supervisor: a small zsh subshell that starts it, waits until its
# port answers, and (as its parent) learns how it ended. It keeps the drop in the prompt
# up to date: ⏳ name while starting, ⚡ name :port when up, red when it exits with an
# error. No daemon: one supervisor per running service, gone with it.
#
# State: $_axle_run_dir/services/<name>/ holds one value per file: root, cmd (words,
# NUL-separated), kind, port, url, pid + pstart (the service process and its start time,
# so a reused pid is never mistaken for it), watcher (the supervisor's pid), started
# (epoch), state (starting | up | crashed), code (exit code), and log (its output).
# Drops are ~/.cache/axle/drops/run-<name>.

zmodload zsh/system zsh/zselect zsh/net/tcp zsh/mapfile zsh/datetime zsh/parameter 2>/dev/null
zmodload -F zsh/stat b:zstat 2>/dev/null

typeset -g _axle_run_dir=${_axle_run_dir:-${XDG_STATE_HOME:-$HOME/.local/state}/axle/run}
typeset -g _axle_run_drops=${_axle_drop_dir:-${XDG_CACHE_HOME:-$HOME/.cache}/axle/drops}

# --- small helpers ------------------------------------------------------------------

_axle_run_put() { print -r -- "$3" >| $1/$2 }
_axle_run_get() { REPLY=''; [[ -r $1/$2 ]] && IFS= read -r REPLY < $1/$2; [[ -n $REPLY ]] }

# A process's start time (REPLY), to tell it apart from a later one with the same pid.
_axle_run_pstart() {
  REPLY=''
  local line
  if [[ -r /proc/$1/stat ]]; then
    IFS= read -r line < /proc/$1/stat 2>/dev/null || return 1
    local -a f=(${=${line##*\) }})
    REPLY=$f[20]
  else
    REPLY=${$(command ps -o lstart= -p $1 2>/dev/null)// /_}
  fi
  [[ -n $REPLY ]]
}

# Is the service in <dir> still the process we started?
_axle_run_alive() {
  local REPLY pid
  _axle_run_get $1 pid || return 1
  pid=$REPLY
  kill -0 $pid 2>/dev/null || return 1
  _axle_run_get $1 pstart || return 0
  local want=$REPLY
  _axle_run_pstart $pid && [[ $REPLY == $want ]]
}

# Does something answer on this port (IPv4 or IPv6 localhost)? No subprocess.
_axle_run_port_up() {
  local host fd
  for host in 127.0.0.1 ::1; do
    ztcp $host $1 2>/dev/null || continue
    fd=$REPLY; ztcp -c $fd 2>/dev/null
    return 0
  done
  return 1
}

# The first local URL a server printed in its log (REPLY = port, _axle_run_logurl = URL).
_axle_run_log_port() {
  setopt localoptions extendedglob
  REPLY=''
  typeset -g _axle_run_logurl=''
  local -a st
  zstat -A st +size -- $1 2>/dev/null || return 1
  (( st[1] < 1048576 )) || return 1
  local text=${mapfile[$1]}                         # (zsh/mapfile: no terminal involved)
  text=${text//$'\e'\[[0-9;]#m/}
  [[ $text == (#b)*(http(|s)://(localhost|127.0.0.1|0.0.0.0|\[::1\]|\[::\]):([0-9](#c2,5)))* ]] || return 1
  REPLY=$match[4] _axle_run_logurl=${match[1]/0.0.0.0/localhost}
}

# A .env file as data (reply = KEY=value ...): never sourced. Comments, blank lines and
# `export ` are skipped; matching quotes around a value are removed.
_axle_run_envfile() {
  setopt localoptions extendedglob
  reply=()
  [[ -f $1 && -r $1 ]] || return 1
  local line key value
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line##[[:space:]]#}
    [[ -z $line || $line == \#* ]] && continue
    line=${line#export[[:space:]]##}
    [[ $line == (#b)([A-Za-z_][A-Za-z0-9_]#)[[:space:]]#=[[:space:]]#(*) ]] || continue
    key=$match[1] value=$match[2]
    if [[ $value == \"*\" || $value == \'*\' ]] && (( ${#value} >= 2 )); then
      value=${value[2,-2]}
    else
      value=${${value%%[[:space:]]##\#*}%%[[:space:]]#}
    fi
    reply+=("$key=$value")
  done < $1
  return 0
}

# The process and all its descendants (reply), from one `ps`.
_axle_run_tree() {
  local -a lines=(${(f)"$(command ps -A -o pid= -o ppid= 2>/dev/null)"})
  local -A kids
  local l pid ppid
  for l in $lines; do
    l=${l## #}; pid=${l%% *}; ppid=${${l#* }## #}
    kids[$ppid]+=" $pid"
  done
  reply=($1)
  local -i i=1
  while (( i <= ${#reply} )); do
    reply+=(${=kids[$reply[i]]})
    (( i++ ))
  done
}

# A drop for a service: _axle_run_drop <name> starting|up|crashed [port] [url] [code]
_axle_run_drop() {
  local name=$1 file=$_axle_run_drops/run-$1
  mkdir -p $_axle_run_drops 2>/dev/null
  local nl=$'\n' body
  case $2 in
    starting) body="text=$name${nl}icon=⏳${nl}level=info${nl}pid=$5" ;;
    up)       body="text=$name${3:+ :$3}${nl}icon=⚡${nl}level=ok${nl}pid=$5${4:+${nl}link=$4}" ;;
    crashed)  body="text=$name exited ($6) · axle run logs${nl}icon=⚡${nl}level=alarm" ;;
  esac
  print -r -- "$body" >| $file.$$ && command mv -f -- $file.$$ $file
}

# --- names ----------------------------------------------------------------------------

# The service name for a project root (REPLY): its folder name, made safe; another
# project already using it gets -2, -3, ...
_axle_run_name() {
  local root=$1 base=${${1:t}//[^A-Za-z0-9._-]/-} name REPLY2
  [[ $base == .* || -z $base ]] && base=project${base}
  local -i n=1
  name=$base
  while [[ -d $_axle_run_dir/services/$name ]]; do
    _axle_run_get $_axle_run_dir/services/$name root
    [[ $REPLY == $root ]] && break
    (( n++ )); name=$base-$n
  done
  REPLY=$name
}

# Services, after clearing out ones whose processes are gone without a trace (reply).
_axle_run_services() {
  local d REPLY
  reply=()
  for d in $_axle_run_dir/services/*(N/); do
    if ! _axle_run_alive $d; then
      _axle_run_get $d state
      if [[ $REPLY != crashed ]]; then
        _axle_run_get $d watcher
        if [[ -z $REPLY ]] || ! kill -0 $REPLY 2>/dev/null; then
          _axle_run_forget ${d:t}; continue
        fi
      fi
    fi
    reply+=(${d:t})
  done
}

# The service the command means (REPLY): the one named, else this project's, else the
# only one.
_axle_run_which() {
  local -a reply
  _axle_run_services
  local -a all=($reply)
  if [[ -n $1 ]]; then
    (( ${all[(Ie)$1]} )) && { REPLY=$1; return 0 }
    print -u2 -r -- "axle run: no service '$1'${all:+ (running: ${(j:, :)all})}"
    return 1
  fi
  local here=${PWD:a} s
  for s in $all; do
    _axle_run_get $_axle_run_dir/services/$s root
    [[ $here == $REPLY || $here == $REPLY/* ]] && { REPLY=$s; return 0 }
  done
  (( ${#all} == 1 )) && { REPLY=$all[1]; return 0 }
  if (( ${#all} )); then
    print -u2 -r -- "axle run: which one? ${(j:, :)all}"
  else
    print -u2 -r -- "axle run: nothing is running (axle run starts this project)"
  fi
  return 1
}

# Remove a service's state and drop (exact paths only).
_axle_run_forget() {
  [[ -n $1 && $1 != */* && $1 != .* ]] || return 1
  command rm -rf -- $_axle_run_dir/services/$1
  command rm -f -- $_axle_run_drops/run-$1
}

# --- start ------------------------------------------------------------------------------

# Start the detected command (_axle_run_cmd, _axle_run_port) in the background as service
# <name> of project <root>. Returns once the supervisor has started it.
_axle_run_start() {
  local root=$1 name=$2 REPLY
  _axle_run_state_init || return 1
  local dir=$_axle_run_dir/services/$name
  _axle_run_forget $name
  mkdir -p -m 700 $dir || return 1
  _axle_run_put $dir root $root
  print -rn -- "${(pj:\0:)_axle_run_cmd}" >| $dir/cmd
  _axle_run_put $dir kind ${_axle_run_kind:-service}
  _axle_run_put $dir port "$_axle_run_port"
  _axle_run_put $dir started $EPOCHSECONDS
  _axle_run_put $dir state starting
  # Logs are kept to about 5 MB: the previous run's moves to log.1.
  local -a st
  [[ -f $dir/log ]] && zstat -A st +size -- $dir/log 2>/dev/null && (( st[1] > 5242880 )) &&
    command mv -f -- $dir/log $dir/log.1

  # The environment: .env values (data), then what axle run sets (e.g. a changed port).
  local -a envs=()
  _axle_run_envfile $root/.env && envs=($reply)
  envs+=($_axle_run_env)
  (( ${#_axle_run_env} )) && print -rn -- "${(pj:\0:)_axle_run_env}" >| $dir/env
  # The supervisor is a fresh, non-interactive zsh, not a subshell of this one: a subshell
  # of an interactive shell keeps its terminal open and fails once the terminal closes.
  local zsh_bin=${commands[zsh]:-zsh}
  [[ -x /proc/$$/exe ]] && zsh_bin=/proc/$$/exe      # (the very zsh running now)
  $zsh_bin -f -c 'source "$1/lib/project.zsh" && source "$1/modules/run/service.zsh" &&
                  shift && _axle_run_supervise "$@"' axle-run \
    $AXLE_ROOT $root $name $dir "$_axle_run_port" ${#envs} "${envs[@]}" "${_axle_run_cmd[@]}" \
    </dev/null >>$dir/log 2>&1 &!
  # Wait (briefly) until the supervisor has recorded the service's pid.
  local -i i
  for i in {1..50}; do
    [[ -s $dir/pid ]] && return 0
    zselect -t 2
  done
  return 0
}

# The supervisor (its own zsh process, output already going to the log):
#   _axle_run_supervise <root> <name> <dir> <port> <n> <n .env values...> <command...>
_axle_run_supervise() {
  local root=$1 name=$2 dir=$3 port=$4; shift 4
  local -i n=$1; shift
  local -a envs=()
  (( n )) && envs=("${@[1,n]}")
  shift $n
  local -a cmd=("$@")
  typeset -g _axle_run_dir=${dir:h:h}
  trap '' HUP INT QUIT TTOU TTIN                   # keeps running when the terminal closes
  _axle_run_put $dir watcher $$
  cd -- $root || { _axle_run_put $dir state crashed; _axle_run_put $dir code 1; return 1 }
  local REPLY e
  if _axle_venv_in $root; then
    export VIRTUAL_ENV=$REPLY
    path=($REPLY/bin ${path:#$REPLY/bin})
    unset PYTHONHOME
  fi
  [[ -n $port ]] && export PORT=$port
  for e in $envs; do export "$e"; done             # .env values (data) and ours, as given
  "${cmd[@]}" &
  local -i spid=$!
  _axle_run_pstart $spid && _axle_run_put $dir pstart $REPLY
  _axle_run_put $dir pid $spid
  _axle_run_drop $name starting '' '' $$

  # Until it answers: the port it printed in its log (a dev server may pick the next
  # free one), else the one detected.
  local url=''
  while kill -0 $spid 2>/dev/null; do
    if _axle_run_log_port $dir/log; then
      port=$REPLY url=$_axle_run_logurl
    fi
    if [[ -n $port ]] && _axle_run_port_up $port; then
      url=${url:-http://localhost:$port}
      _axle_run_put $dir port $port
      _axle_run_put $dir url $url
      _axle_run_put $dir state up
      _axle_run_drop $name up $port $url $$
      break
    fi
    zselect -t 25
  done
  wait $spid
  local -i code=$?
  [[ -e $dir/stopping || ! -d $dir ]] && return 0
  if (( code == 0 )); then
    _axle_run_forget $name                          # it finished on its own: nothing to show
  else
    _axle_run_put $dir state crashed
    _axle_run_put $dir code $code
    _axle_run_drop $name crashed '' '' '' $code
  fi
}

# --- the commands -----------------------------------------------------------------------

# Start the detected service from `axle run`, then wait a moment to say how it went.
_axle_run_bg() {
  local root=$1 name=$2 REPLY
  local muted=${_axle_c[muted]:-244} ok=${_axle_c[ok]:-green} err=${_axle_c[error]:-red}
  local dir=$_axle_run_dir/services/$name
  if _axle_run_alive $dir; then
    _axle_run_get $dir url
    _axle_printp "%F{$ok}⚡%f %B${name//\%/%%}%b is already running${REPLY:+ on ${REPLY//\%/%%}} %F{$muted}(axle run restart · logs · open)%f"
    return 0
  fi
  _axle_run_start $root $name || return 1
  # Up to ~10 s for it to answer (Ctrl-C stops waiting, not the service).
  local -i i
  local state=''
  for i in {1..40}; do
    _axle_run_get $dir state; state=$REPLY
    [[ $state == (up|crashed) || ! -d $dir ]] && break
    zselect -t 25 || break
  done
  case $state in
    up)
      _axle_run_get $dir url
      _axle_printp "%F{$ok}⚡%f %B${name//\%/%%}%b running on ${REPLY//\%/%%}  %F{$muted}(background · axle run logs · stop)%f" ;;
    crashed)
      _axle_run_get $dir code
      _axle_printp "%F{$err}✘%f %B${name//\%/%%}%b exited (code $REPLY). Its last lines:"
      command tail -n 15 -- $dir/log 2>/dev/null | sed 's/^/  /'
      return 1 ;;
    *)
      if [[ ! -d $dir ]]; then
        _axle_printp "%F{$muted}${name//\%/%%} finished.%f"
      else
        _axle_printp "%F{$muted}⏳%f %B${name//\%/%%}%b is starting in the background %F{$muted}(it shows in the prompt when ready · axle run logs)%f"
      fi ;;
  esac
  return 0
}

_axle_run_ls() {
  local -a reply
  _axle_run_services
  local -a names=($reply)
  if (( ! ${#names} )); then print -r -- "nothing running"; return 0; fi
  # Memory: each service with its child processes, from one `ps`.
  local -A rss kids
  local l pid ppid r
  for l in ${(f)"$(command ps -A -o pid= -o ppid= -o rss= 2>/dev/null)"}; do
    local -a f=(${=l})
    rss[$f[1]]=$f[3]; kids[$f[2]]+=" $f[1]"
  done
  local muted=${_axle_c[muted]:-244}
  _axle_printp "%F{$muted}${(r:18:):-NAME}${(r:10:):-STATE}${(r:7:):-PORT}${(r:9:):-UPTIME}${(r:9:):-MEMORY}URL%f"
  local name dir state port up mem url REPLY
  for name in $names; do
    dir=$_axle_run_dir/services/$name
    _axle_run_get $dir state; state=$REPLY
    _axle_run_get $dir port;  port=${REPLY:--}
    _axle_run_get $dir url;   url=$REPLY
    _axle_run_get $dir started
    _axle_fmt_duration $(( EPOCHSECONDS - ${REPLY:-$EPOCHSECONDS} )); up=${REPLY%.??s}
    mem=-
    if [[ $state == crashed ]]; then
      _axle_run_get $dir code; state="exit $REPLY"; up=-
    elif _axle_run_get $dir pid; then
      local -a tree=($REPLY); local -i i=1 kb=0
      while (( i <= ${#tree} )); do tree+=(${=kids[$tree[i]]}); (( kb += ${rss[$tree[i]]:-0} )); (( i++ )); done
      (( kb )) && mem="$(( kb / 1024 ))M"
    fi
    print -r -- "${(r:18:)name}${(r:10:)state}${(r:7:)port}${(r:9:)up}${(r:9:)mem}$url"
  done
}

# Stop service <name>: the supervisor, the service and everything it started.
_axle_run_stop_one() {
  local name=$1 dir=$_axle_run_dir/services/$1 REPLY
  [[ -d $dir ]] || return 1
  : >| $dir/stopping
  local -a pids=() left=() reply
  local pid
  _axle_run_get $dir watcher && kill -0 $REPLY 2>/dev/null && { _axle_run_tree $REPLY; pids+=($reply) }
  _axle_run_alive $dir && _axle_run_get $dir pid && { _axle_run_tree $REPLY; pids+=($reply) }
  pids=(${(u)pids})
  if (( ${#pids} )); then
    kill -TERM $pids 2>/dev/null
    local -i i
    for i in {1..50}; do                           # up to 5 s to finish, then forced
      left=()
      for pid in $pids; do kill -0 $pid 2>/dev/null && left+=($pid); done
      (( ${#left} )) || break
      zselect -t 10
    done
    (( ${#left} )) && kill -KILL $left 2>/dev/null
  fi
  _axle_run_forget $name
}

_axle_run_stop() {
  local REPLY
  local -a reply names
  if [[ $1 == all ]]; then
    _axle_run_services; names=($reply)
    (( ${#names} )) || { print -r -- "nothing running"; return 0 }
  else
    _axle_run_which $1 || return 1
    names=($REPLY)
  fi
  local name
  for name in $names; do
    _axle_run_stop_one $name && print -r -- "stopped $name"
  done
}

_axle_run_restart() {
  local REPLY
  _axle_run_which $1 || return 1
  local name=$REPLY dir=$_axle_run_dir/services/$REPLY
  local root port kind
  _axle_run_get $dir root; root=$REPLY
  _axle_run_get $dir port; port=$REPLY
  _axle_run_get $dir kind; kind=$REPLY
  [[ -r $dir/cmd ]] || { print -u2 "axle run: don't know how $name was started"; return 1 }
  local cmd; IFS= read -rd '' cmd < $dir/cmd
  local -a words=("${(@0)cmd}") extra=()
  if [[ -r $dir/env ]]; then
    local e; IFS= read -rd '' e < $dir/env; extra=("${(@0)e}")
  fi
  _axle_run_stop_one $name
  typeset -ga _axle_run_cmd=($words) _axle_run_env=($extra)
  typeset -g _axle_run_port=$port _axle_run_kind=${kind:-service}
  _axle_run_bg $root $name
}

_axle_run_logs() {
  local follow=0 REPLY
  [[ $1 == -f ]] && { follow=1; shift }
  _axle_run_which $1 || return 1
  local name=$REPLY dir=$_axle_run_dir/services/$REPLY
  [[ -r $dir/log ]] || { print -r -- "$name: no output yet"; return 0 }
  # Looking at a crash is what clears its red tab.
  _axle_run_get $dir state
  [[ $REPLY == crashed ]] && command rm -f -- $_axle_run_drops/run-$name
  if (( follow )); then
    command tail -n 50 -f -- $dir/log
  else
    command tail -n 50 -- $dir/log
  fi
}

_axle_run_open() {
  local REPLY
  _axle_run_which $1 || return 1
  local name=$REPLY dir=$_axle_run_dir/services/$REPLY url
  _axle_run_get $dir url; url=$REPLY
  [[ -n $url ]] || { print -u2 -r -- "axle run: $name has no URL (yet)"; return 1 }
  local opener
  local -a openers=(wslview xdg-open)
  [[ $OSTYPE == darwin* ]] && openers=(open)
  for opener in $openers; do
    whence -p $opener >/dev/null || continue
    print -r -- "opening $url"
    command $opener $url >/dev/null 2>&1 &!
    return 0
  done
  print -r -- "$url"
}
