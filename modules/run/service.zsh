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

zmodload zsh/system zsh/zselect zsh/mapfile zsh/datetime zsh/parameter 2>/dev/null
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

# Put a venv on this process's PATH instead of any active one, the way the env module does
# it (never `activate`). <venv>: its path, or - to leave the environment as it is.
_axle_run_enter_venv() {
  [[ $1 == - || -z $1 ]] && return 0
  [[ -n $VIRTUAL_ENV && $VIRTUAL_ENV != $1 ]] && path=(${path:#$VIRTUAL_ENV/bin})
  export VIRTUAL_ENV=$1
  path=($1/bin ${path:#$1/bin})
  unset PYTHONHOME
}

# A file of NUL-separated words (reply). (`read -d ''` would stop at the first one.)
_axle_run_words() { reply=("${(@0)mapfile[$1]}") }

# Is the service in <dir> still the process we started?
_axle_run_alive() {
  local REPLY pid
  _axle_run_get $1 kind && [[ $REPLY == compose ]] && return 0   # docker runs those
  _axle_run_get $1 pid || return 1
  pid=$REPLY
  kill -0 $pid 2>/dev/null || return 1
  _axle_run_get $1 pstart || return 0
  local want=$REPLY
  _axle_run_pstart $pid && [[ $REPLY == $want ]]
}

# Is something listening on this port, IPv4 or IPv6? Never by connecting from this shell:
# zsh's ztcp can block for good (it did on macOS, stalling the supervisor), and it has no
# IPv6. Linux: /proc/net/tcp and tcp6 (no subprocess). Elsewhere: lsof, which only sees
# your own processes, then nc for anyone else's; each gets 2 s at most.
_axle_run_port_up() {
  local port=$1 f line hex
  if [[ -r /proc/net/tcp ]]; then
    printf -v hex '%04X' $port
    for f in /proc/net/tcp /proc/net/tcp6; do
      [[ -r $f ]] || continue
      while IFS= read -r line; do
        local -a w=(${=line})
        [[ ${w[2]##*:} == $hex && $w[4] == 0A ]] && return 0
      done < $f
    done
    return 1
  fi
  whence -p lsof >/dev/null &&
    _axle_run_bounded command lsof -nP -iTCP:$port -sTCP:LISTEN -t && return 0
  whence -p nc >/dev/null &&
    _axle_run_bounded command nc -z -w 1 127.0.0.1 $port && return 0
  return 1
}

# Run a command for at most 2 s (its status; 1 if it took longer, and it's ended).
_axle_run_bounded() {
  "$@" </dev/null >/dev/null 2>&1 &
  local -i pid=$! i
  for i in {1..40}; do
    if ! kill -0 $pid 2>/dev/null; then wait $pid; return; fi
    zselect -t 5
  done
  kill -KILL $pid 2>/dev/null
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

# A drop for a service: _axle_run_drop <name> starting|up|restarting|crashed [port] [url]
# [pid] [code] [restarts]
_axle_run_drop() {
  local name=$1 file=$_axle_run_drops/run-$1
  mkdir -p $_axle_run_drops 2>/dev/null
  local nl=$'\n' body
  case $2 in
    starting) body="text=$name${nl}icon=⏳${nl}level=info${nl}pid=$5" ;;
    up)       body="text=$name${3:+ :$3}${${7:#0}:+ ↻$7}${nl}icon=⚡${nl}level=ok${nl}pid=$5${4:+${nl}link=$4}" ;;
    restarting) body="text=$name exited ($6), starting again${nl}icon=↻${nl}level=warn" ;;
    unhealthy) body="text=$name${3:+ :$3} unhealthy${nl}icon=⚡${nl}level=warn${nl}pid=$5${4:+${nl}link=$4}" ;;
    crashed)  body="text=$name exited ($6) · axle run logs${nl}icon=✘${nl}level=alarm" ;;
  esac
  print -r -- "$body" >| $file.$$ && command mv -f -- $file.$$ $file
}

# The values of a run's .env files, in order (reply): _axle_run_envfiles (set by
# detection: .env or yours, then the profile's), else <folder>/.env.
_axle_run_dotenv() {
  local f
  local -a all=() files=(${_axle_run_envfiles:-$1/.env})
  for f in $files; do _axle_run_envfile $f && all+=($reply); done
  reply=($all)
  (( ${#reply} ))
}

# Open a URL in the browser (REPLY = the program used); status 1 if there's none.
_axle_run_browse() {
  local opener
  local -a openers=(wslview xdg-open)
  [[ $OSTYPE == darwin* ]] && openers=(open)
  for opener in $openers; do
    whence -p $opener >/dev/null || continue
    command $opener $1 >/dev/null 2>&1 &!
    REPLY=$opener
    return 0
  done
  return 1
}

# --- names ----------------------------------------------------------------------------

# The service name for a project (part) folder (REPLY): <base> (default: its folder name),
# made safe; another folder already using it gets -2, -3, ...
_axle_run_name() {
  local root=$1 base=${${2:-${1:t}}//[^A-Za-z0-9._-]/-} name
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
  # After a crash: start it again (AXLE_RUN_RESTART, or `axle run set restart on-crash`).
  local onfail=${_axle_run_onfail:-${AXLE_RUN_RESTART:-no}}
  _axle_run_put $dir onfail $onfail
  _axle_run_put $dir health "$_axle_run_health"

  # The environment: .env values (data), then what axle run sets (e.g. a changed port).
  local -a envs=()
  _axle_run_dotenv $root && envs=($reply)
  envs+=($_axle_run_env)
  (( ${#_axle_run_env} )) && print -rn -- "${(pj:\0:)_axle_run_env}" >| $dir/env
  (( ${#_axle_run_envfiles} )) && print -rn -- "${(pj:\0:)_axle_run_envfiles}" >| $dir/envfiles
  # AXLE_RUN_ON_EXIT=stop: it ends with this shell (the supervisor watches it).
  local owner=''
  if [[ $AXLE_RUN_ON_EXIT == stop && -o interactive ]]; then   # (not a script's: it ends now)
    _axle_run_pstart $$ && owner="$$:$REPLY"
  fi
  # AXLE_RUN_OPEN=1: the browser opens once it answers (not on a restart).
  local open=0
  [[ $AXLE_RUN_OPEN == 1 ]] && (( ! _axle_run_no_open )) && open=1
  # The supervisor is a fresh, non-interactive zsh, not a subshell of this one: a subshell
  # of an interactive shell keeps its terminal open and fails once the terminal closes.
  local zsh_bin=${commands[zsh]:-zsh}
  [[ -x /proc/$$/exe ]] && zsh_bin=/proc/$$/exe      # (the very zsh running now)
  _axle_run_put $dir venv "$_axle_run_use_venv"
  (( ${_axle_run_worker:-0} )) && _axle_run_put $dir worker 1
  AXLE_RUN_USE_VENV=$_axle_run_use_venv AXLE_RUN_OWNER=$owner AXLE_RUN_OPEN_URL=$open \
  AXLE_RUN_ONFAIL=$onfail AXLE_RUN_LOG_MAX=${AXLE_RUN_LOG_MAX:-10M} AXLE_RUN_NOTIFY=${AXLE_RUN_NOTIFY:-off} \
  AXLE_RUN_HEALTH=$_axle_run_health AXLE_RUN_WORKER=${_axle_run_worker:-0} \
  $zsh_bin -f -c 'source "$1/lib/project.zsh" && source "$1/modules/run/service.zsh" &&
                  source "$1/modules/run/supervise.zsh" &&
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

# --- the commands -----------------------------------------------------------------------

# A failed service's whole log, indented, between rules (it's the evidence).
_axle_run_show_log() {
  local muted=${_axle_c[muted]:-244} line
  _axle_printp "%F{$muted}  ┌─ ${${1/#$HOME/~}//\%/%%}%f"
  if [[ -s $1 ]]; then
    while IFS= read -r line || [[ -n $line ]]; do print -r -- "  │ $line"; done < $1
  else
    _axle_printp "  │ %F{$muted}(no output)%f"
  fi
  _axle_printp "%F{$muted}  └─%f"
}

# The services of the project you're in (reply): started from here, above or below.
_axle_run_mine() {
  local -a all mine=()
  local s REPLY here=${PWD:a}
  _axle_run_services; all=($reply)
  for s in $all; do
    _axle_run_get $_axle_run_dir/services/$s root
    [[ $here == $REPLY || $here == $REPLY/* || $REPLY == $here/* ]] && mine+=($s)
  done
  reply=($mine)
  (( ${#reply} ))
}

# Start the detected service from `axle run`, then wait a moment to say how it went.
_axle_run_bg() {
  local root=$1 name=$2 REPLY
  local muted=${_axle_c[muted]:-244} ok=${_axle_c[ok]:-green} err=${_axle_c[error]:-red}
  local dir=$_axle_run_dir/services/$name q=0
  _axle_run_quiet && q=1                           # (no hints)
  if _axle_run_alive $dir; then
    _axle_run_get $dir url
    _axle_printp "%F{$ok}⚡%f %B${name//\%/%%}%b is already running${REPLY:+ on ${REPLY//\%/%%}}${${q:#1}:+ %F{$muted\}(axle run restart · logs · open)%f}"
    return 0
  fi
  _axle_run_start $root $name || return 1
  _axle_emit run-start $name $root service
  _axle_run_watch_add $name
  # Up to ~10 s for it to answer (Ctrl-C stops waiting, not the service).
  local -i i
  local state=''
  for i in {1..40}; do
    _axle_run_get $dir state; state=$REPLY
    [[ $state == (up|crashed|restarting) || ! -d $dir ]] && break
    zselect -t 25                                  # (its status is 1 on a plain timeout)
  done
  (( ${+_axle_run_watch[$name]} )) && _axle_run_watch_check
  case $state in
    up)
      _axle_run_get $dir url
      _axle_printp "%F{$ok}⚡%f %B${name//\%/%%}%b running${REPLY:+ on ${REPLY//\%/%%}}${${q:#1}:+  %F{$muted\}(background · axle run logs · stop)%f}" ;;
    restarting)
      _axle_run_get $dir code
      _axle_printp "%F{${_axle_c[warn]:-yellow}}↻%f %B${name//\%/%%}%b exited (code $REPLY), and starts again by itself (restart on-crash). Its log:"
      _axle_run_show_log $dir/log
      _axle_run_explain $root $dir/log "axle run restart $name" ''
      return 0 ;;
    crashed)
      _axle_run_get $dir code
      _axle_printp "%F{$err}✘%f %B${name//\%/%%}%b exited (code $REPLY). Its log:"
      _axle_run_show_log $dir/log
      _axle_run_get $dir port
      _axle_run_explain $root $dir/log "axle run restart $name" $REPLY
      return 1 ;;
    *)
      if [[ ! -d $dir ]]; then
        _axle_printp "%F{$muted}${name//\%/%%} finished.%f"
      else
        _axle_printp "%F{$muted}⏳%f %B${name//\%/%%}%b is starting in the background${${q:#1}:+ %F{$muted\}(it shows in the prompt when ready · axle run logs)%f}"
      fi ;;
  esac
  return 0
}

# A JSON string of $1 (REPLY), quotes included.
_axle_run_json_str() {
  setopt localoptions extendedglob
  local s=${1//\\/\\\\}
  s=${s//\"/\\\"}; s=${s//$'\n'/\\n}; s=${s//$'\t'/\\t}; s=${s//$'\r'/\\r}
  s=${s//[$'\x01'-$'\x1f']/}                       # (other control characters: dropped)
  REPLY="\"$s\""
}

# axle run ls [--json]: the services, a table (colours in a terminal, plain in a pipe), or
# with --json an array of objects for scripts and editors:
#   name state code port url pid uptime memory_kb restarts kind root log
# (state: starting, up, restarting, unhealthy, crashed, or compose; numbers or null).
_axle_run_ls() {
  local -i json=0
  case $1 in
    --json) json=1 ;;
    '') ;;
    *) print -u2 -r -- "axle run ls: $1? (axle run ls [--json])"; return 1 ;;
  esac
  local -a reply
  _axle_run_services
  local -a names=($reply)
  if (( ! ${#names} )); then
    if (( json )); then print -r -- '[]'; else print -r -- "nothing running"; fi
    return 0
  fi
  # Memory: each service with its child processes, from one `ps`.
  local -A rss kids
  local l
  for l in ${(f)"$(command ps -A -o pid= -o ppid= -o rss= 2>/dev/null)"}; do
    local -a f=(${=l})
    rss[$f[1]]=$f[3]; kids[$f[2]]+=" $f[1]"
  done
  local muted=${_axle_c[muted]:-244}
  (( json )) ||
    _axle_printp "%F{$muted}${(r:18:):-NAME}${(r:10:):-STATE}${(r:7:):-PORT}${(r:9:):-UPTIME}${(r:9:):-MEMORY}URL%f"
  local name dir state port up mem url REPLY kind code pid started restarts root
  local -a objs=()
  local -i kb secs
  for name in $names; do
    dir=$_axle_run_dir/services/$name
    _axle_run_get $dir state; state=$REPLY
    _axle_run_get $dir port;  port=$REPLY
    _axle_run_get $dir url;   url=$REPLY
    _axle_run_get $dir kind;  kind=${REPLY:-service}
    _axle_run_get $dir code;  code=$REPLY
    _axle_run_get $dir root;  root=$REPLY
    _axle_run_get $dir restarts; restarts=${REPLY:-0}
    _axle_run_get $dir started; started=$REPLY
    secs=$(( EPOCHSECONDS - ${started:-$EPOCHSECONDS} ))
    pid='' kb=0
    if [[ $kind == compose ]]; then
      state=compose
    elif [[ $state == crashed ]]; then
      port='' url='' secs=0                         # (nothing listens)
    elif _axle_run_get $dir pid; then
      pid=$REPLY
      local -a tree=($pid); local -i i=1
      while (( i <= ${#tree} )); do tree+=(${=kids[$tree[i]]}); (( kb += ${rss[$tree[i]]:-0} )); (( i++ )); done
    fi
    if (( json )); then
      local o=''
      _axle_run_json_str $name;  o+="{\"name\":$REPLY"
      _axle_run_json_str ${state:-starting}; o+=",\"state\":$REPLY"
      o+=",\"code\":${${state:#crashed}:+null}${${(M)state:#crashed}:+${code:-null}}"
      o+=",\"port\":${port:-null}"
      if [[ -n $url ]]; then _axle_run_json_str $url; o+=",\"url\":$REPLY"; else o+=",\"url\":null"; fi
      o+=",\"pid\":${pid:-null}"
      o+=",\"uptime\":${${${(M)state:#crashed}:+null}:-$secs}"
      o+=",\"memory_kb\":${${kb:#0}:-null}"
      o+=",\"restarts\":$restarts"
      _axle_run_json_str $kind;  o+=",\"kind\":$REPLY"
      _axle_run_json_str $root;  o+=",\"root\":$REPLY"
      _axle_run_json_str $dir/log; o+=",\"log\":$REPLY}"
      objs+=($o)
      continue
    fi
    _axle_fmt_duration $secs; up=${REPLY/.??s/s}
    mem=-
    (( kb )) && mem="$(( kb / 1024 ))M"
    [[ $state == crashed ]] && { state="exit $code"; up=- }
    local row="${(r:18:)name}${(r:10:)state}${(r:7:)${port:--}}${(r:9:)up}${(r:9:)mem}"
    if [[ -t 1 ]]; then                            # (colours for you, plain for a pipe)
      local c=${_axle_c[muted]:-244}
      case $state in
        up|compose)            c=${_axle_c[ok]:-green} ;;
        exit*)                 c=${_axle_c[error]:-red} ;;
        restarting|unhealthy)  c=${_axle_c[warn]:-yellow} ;;
      esac
      _axle_printp "%B${row[1,18]//\%/%%}%b%F{$c}${row[19,28]//\%/%%}%f${row[29,-1]//\%/%%}%F{${_axle_c[path]:-cyan}}${url//\%/%%}%f"
    else
      print -r -- "$row$url"
    fi
  done
  (( json )) && print -r -- "[${(j:,:)objs}]"
  return 0
}

# Run `docker compose -f <file> <args>` for a compose service, in its folder.
_axle_run_compose() {
  local dir=$1 REPLY; shift
  _axle_run_get $dir root
  local root=$REPLY
  local -a reply words
  _axle_run_words $dir/cmd; words=($reply)         # docker compose -f <file> up -d
  ( cd -- $root && command "${(@)words[1,4]}" "$@" )
}

# Stop service <name>: the supervisor, the service and everything it started.
_axle_run_stop_one() {
  local name=$1 dir=$_axle_run_dir/services/$1 REPLY
  [[ -d $dir ]] || return 1
  if _axle_run_get $dir kind && [[ $REPLY == compose ]]; then
    _axle_run_compose $dir down || return 1
    _axle_run_forget $name
    return 0
  fi
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
  elif [[ -z $1 ]] && _axle_run_mine; then
    names=($reply)                                 # this project's (all its parts)
  else
    _axle_run_which $1 || return 1
    names=($REPLY)
  fi
  local name
  for name in $names; do
    _axle_run_stop_one $name && print -r -- "stopped $name" && _axle_run_watch_stopped $name
  done
}

_axle_run_restart() {
  local REPLY
  _axle_run_which $1 || return 1
  local name=$REPLY dir=$_axle_run_dir/services/$REPLY
  local root port kind
  if _axle_run_get $dir kind && [[ $REPLY == compose ]]; then
    _axle_run_compose $dir restart && print -r -- "restarted $name"
    return
  fi
  _axle_run_get $dir root; root=$REPLY
  _axle_run_get $dir venv; typeset -g _axle_run_use_venv=$REPLY
  _axle_run_get $dir port; port=$REPLY
  _axle_run_get $dir kind; kind=$REPLY
  _axle_run_get $dir onfail; local _axle_run_onfail=$REPLY
  _axle_run_get $dir health; local _axle_run_health=$REPLY
  _axle_run_get $dir worker; local -i _axle_run_worker=${REPLY:-0}
  [[ -r $dir/cmd ]] || { print -u2 "axle run: don't know how $name was started"; return 1 }
  local -a reply words extra=()
  _axle_run_words $dir/cmd; words=($reply)
  [[ -r $dir/env ]] && { _axle_run_words $dir/env; extra=($reply) }
  local -a files=()
  [[ -r $dir/envfiles ]] && { _axle_run_words $dir/envfiles; files=($reply) }
  _axle_run_stop_one $name
  _axle_run_watch_stopped $name
  typeset -ga _axle_run_cmd=($words) _axle_run_env=($extra) _axle_run_envfiles=($files)
  typeset -g _axle_run_port=$port _axle_run_kind=${kind:-service}
  local -i _axle_run_no_open=1
  _axle_run_bg $root $name
}

# axle run logs all [-f] [-n N]: every service's log, each line after its name (like
# docker compose logs), in one `tail` (in a terminal, each name in its own colour).
_axle_run_logs_all() {
  local follow=$1 lines=$2 REPLY s
  local -a reply files=() names=() skipped=()
  _axle_run_services
  for s in $reply; do
    if _axle_run_get $_axle_run_dir/services/$s kind && [[ $REPLY == compose ]]; then
      skipped+=($s)
    elif [[ -r $_axle_run_dir/services/$s/log ]]; then
      files+=($_axle_run_dir/services/$s/log) names+=($s)
    fi
  done
  (( ${#skipped} )) &&
    print -u2 -r -- "(not here: ${(j:, :)skipped}: docker compose's own, axle run logs <name>)"
  (( ${#files} )) || { print -r -- "no logs (nothing running)"; return 0 }
  local -i width=0 colour=0
  for s in $names; do (( ${#s} > width )) && width=${#s}; done
  [[ -t 1 && -z $NO_COLOR ]] && colour=1
  local -a opts=(-n $lines)
  (( follow )) && opts+=(-F)
  # tail marks each file's lines with "==> <file> <==" (after a blank line): those become
  # the name in front of each line.
  command tail $opts -- $files 2>/dev/null | command awk -v w=$width -v c=$colour -v one=$names[1] \
    -v all="${(j: :)names}" '
    BEGIN { n = split(all, a, " "); for (i = 1; i <= n; i++) col[a[i]] = 31 + i % 6; cur = one }
    /^==> .* <==$/ { p = $0; sub(/^==> /, "", p); sub(/\/log <==$/, "", p); k = split(p, b, "/"); cur = b[k]; blank = 0; next }
    /^$/ { blank++; next }
    {
      tag = sprintf("%-" w "s │", cur)
      if (c) tag = "\033[" col[cur] "m" tag "\033[0m"
      for (; blank > 0; blank--) print tag
      print tag " " $0; fflush()
    }'
  return 0
}

_axle_run_logs() {
  local follow=0 lines=50 REPLY
  local -a which=()
  while (( $# )); do                               # (options before or after the name)
    case $1 in
      -f|--follow) follow=1 ;;
      -n) [[ $2 == <-> ]] || { print -u2 -r -- "axle run logs: -n needs a number"; return 1 }
          lines=$2; shift ;;
      -n<->) lines=${1#-n} ;;
      --lines=<->) lines=${1#*=} ;;
      -*) print -u2 -r -- "axle run logs: $1? (axle run logs [name|all] [-f] [-n lines])"; return 1 ;;
      *)  which+=($1) ;;
    esac
    shift
  done
  (( ${#which} > 1 )) && { print -u2 -r -- "axle run logs: one name, or all"; return 1 }
  [[ $which[1] == all ]] && { _axle_run_logs_all $follow $lines; return }
  _axle_run_which $which[1] || return 1
  local name=$REPLY dir=$_axle_run_dir/services/$REPLY
  if _axle_run_get $dir kind && [[ $REPLY == compose ]]; then
    if (( follow )); then _axle_run_compose $dir logs --tail 200 -f
    else _axle_run_compose $dir logs --tail 200; fi
    return
  fi
  [[ -r $dir/log ]] || { print -r -- "$name: no output yet"; return 0 }
  # Looking at a crash is what clears its red tab.
  _axle_run_get $dir state
  local crashed=$REPLY
  [[ $crashed == crashed ]] && command rm -f -- $_axle_run_drops/run-$name
  # (In a terminal, which log first; piped, just the log.)
  [[ -t 1 ]] && ! _axle_run_quiet && _axle_printp "%F{${_axle_c[muted]:-244}}── ${name//\%/%%}: ${${dir/#$HOME/~}//\%/%%}/log, the last $lines lines${${follow:#0}:+, then as it grows (Ctrl-C stops)}%f"
  if (( follow )); then
    command tail -n $lines -f -- $dir/log
  else
    command tail -n $lines -- $dir/log
    if [[ $crashed == crashed && -t 1 ]]; then        # and why, if it's a known cause (not
                                                      # into a pipe: | head, | grep get the log)
      local root port
      _axle_run_get $dir root; root=$REPLY
      _axle_run_get $dir port; port=$REPLY
      [[ -d $root ]] && _axle_run_explain $root $dir/log "axle run restart $name" $port
    fi
    return 0
  fi
}

_axle_run_open() {
  local REPLY
  _axle_run_which $1 || return 1
  local name=$REPLY dir=$_axle_run_dir/services/$REPLY url
  _axle_run_get $dir url; url=$REPLY
  [[ -n $url ]] || { print -u2 -r -- "axle run: $name has no URL (yet)"; return 1 }
  if _axle_run_browse $url; then print -r -- "opening $url"; else print -r -- "$url"; fi
}
