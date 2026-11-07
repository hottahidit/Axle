# axle run's supervisor: a zsh process of its own beside each background service (started
# by _axle_run_start, in modules/run/service.zsh, which it also loads). It starts the
# service and stays with it:
#
#   - its state for everyone (<state>/services/<name>/: pid, state, port, url, code...) and
#     its tab in every prompt (a drop): starting, up, unhealthy, restarting, crashed;
#   - up once its port answers (and its health path: axle run set health);
#   - its log kept small (AXLE_RUN_LOG_MAX), every 2 s;
#   - after a crash, started again (axle run set restart on-crash), 1, 2, 4... s apart;
#   - a desktop notification (AXLE_RUN_NOTIFY);
#   - with AXLE_RUN_ON_EXIT=stop, ended with the shell that started it.
#
# It ignores the terminal closing (HUP, INT...); TERM to it stops the service as `axle run
# stop` does. Nothing here runs in your shell.

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
  # Killing the supervisor (by hand, from a process list: its command line has the
  # project's name, the service's often doesn't) stops the service, as `axle run stop`.
  local -i spid=0
  trap '_axle_run_sup_term; exit 0' TERM
  # AXLE_RUN_DEBUG: a trace of the supervisor in <dir>/trace (the tests turn it on).
  if [[ -n $AXLE_RUN_DEBUG ]]; then exec 2>>$dir/trace; setopt xtrace; fi
  _axle_run_put $dir watcher $$
  cd -- $root || { _axle_run_put $dir state crashed; _axle_run_put $dir code 1; return 1 }
  local REPLY e use=$AXLE_RUN_USE_VENV owner=$AXLE_RUN_OWNER open=$AXLE_RUN_OPEN_URL
  local onfail=$AXLE_RUN_ONFAIL logmax=$AXLE_RUN_LOG_MAX notify=$AXLE_RUN_NOTIFY health=$AXLE_RUN_HEALTH
  local -i unit=${_AXLE_RUN_BACKOFF_CS:-100}         # (a restart's second; the tests shorten it)
  local -i worker=${AXLE_RUN_WORKER:-0}              # (no port: up once it's run 2 s)
  local -i reload=${AXLE_RUN_ENV_RELOAD:-1} envchanged=0
  unset AXLE_RUN_USE_VENV AXLE_RUN_OWNER AXLE_RUN_OPEN_URL AXLE_RUN_ONFAIL AXLE_RUN_LOG_MAX AXLE_RUN_NOTIFY \
        AXLE_RUN_HEALTH AXLE_RUN_WORKER AXLE_RUN_ENV_RELOAD
  # Its .env files, watched: changed, it starts again with them (AXLE_RUN_ENV_RELOAD=0: not).
  local -a watch=($root/.env)
  if [[ -r $dir/envfiles ]]; then local -a reply; _axle_run_words $dir/envfiles; watch=($reply); fi
  _axle_run_env_stamp $watch; local stamp=$REPLY
  [[ -z $use ]] && _axle_venv_find $root && use=$REPLY
  _axle_run_enter_venv "$use"
  [[ -n $port ]] && export PORT=$port
  for e in $envs; do export "$e"; done             # .env values (data) and ours, as given
  _axle_run_size $logmax; local -i maxbytes=$REPLY
  local -i restarts=0 fast=0 started code
  local url='' first_port=$port

  # Run it; again after a crash with AXLE_RUN_RESTART / `axle run set restart on-crash`.
  while :; do
    "${cmd[@]}" 2>&1 &                             # (its errors to the log too)
    spid=$! started=$EPOCHSECONDS port=$first_port url=''
    _axle_run_pstart $spid && _axle_run_put $dir pstart $REPLY
    _axle_run_put $dir pid $spid
    _axle_run_put $dir state starting
    # The tab lives as long as the service (not this supervisor, which could be killed).
    _axle_run_drop $name starting '' '' $spid

    # Until it answers: the port it printed in its log (a dev server may pick the next
    # free one), else the one detected.
    while kill -0 $spid 2>/dev/null; do
      _axle_run_owner_gone $owner && { _axle_run_sup_term; return 0 }
      if _axle_run_log_port $dir/log; then
        port=$REPLY url=$_axle_run_logurl
      fi
      # (with a health path, up once that answers: axle run set health /healthz)
      if [[ -n $port ]] && _axle_run_port_up $port && { [[ -z $health ]] || _axle_run_health_ok $port $health }; then
        url=${url:-http://localhost:$port}
        _axle_run_put $dir port $port
        _axle_run_put $dir url $url
        _axle_run_put $dir state up
        _axle_run_drop $name up $port $url $spid '' $restarts
        (( open && ! restarts )) && _axle_run_browse $url
        [[ $notify == (ready|all) ]] && (( ! restarts )) && _axle_run_notify "axle run: $name" "up on $url"
        break
      fi
      # A worker (a Procfile's worker:, css:...) listens on nothing: up once it's lasted.
      if (( worker )) && [[ -z $port ]] && (( EPOCHSECONDS - started >= 2 )); then
        _axle_run_put $dir state up
        _axle_run_drop $name up '' '' $spid '' $restarts
        [[ $notify == (ready|all) ]] && (( ! restarts )) && _axle_run_notify "axle run: $name" "running"
        break
      fi
      _axle_run_log_trim $dir $maxbytes
      _axle_run_sup_envcheck && break
      zselect -t 25
    done
    # Then every 2 s: its terminal (AXLE_RUN_ON_EXIT=stop), and its log's size; every 10 s
    # its health path (3 failures in a row: unhealthy, until it answers again).
    local -i beat=0 fails=0 every=${_AXLE_RUN_HEALTH_EVERY:-5}   # (2 s beats; the tests: fewer)
    while kill -0 $spid 2>/dev/null; do
      _axle_run_owner_gone $owner && { _axle_run_sup_term; return 0 }
      _axle_run_log_trim $dir $maxbytes
      _axle_run_sup_envcheck && break
      if [[ -n $health && -n $port ]] && (( ++beat % every == 0 )); then
        if _axle_run_health_ok $port $health; then
          if (( fails >= 3 )); then                # (the tab first: whoever sees the state finds it)
            _axle_run_drop $name up $port $url $spid '' $restarts
            _axle_run_put $dir state up
          fi
          fails=0
        elif (( ++fails == 3 )); then
          _axle_run_drop $name unhealthy $port $url $spid
          _axle_run_put $dir state unhealthy
          print -r -- "axle run: $name doesn't answer $health (3 times in a row)"
          [[ $notify == (crash|all) ]] && _axle_run_notify "axle run: $name unhealthy" "$health doesn't answer"
        fi
      fi
      zselect -t 200
    done
    wait $spid
    code=$?
    [[ -e $dir/stopping || ! -d $dir ]] && return 0
    if (( envchanged )); then                      # (stopped by us: not a crash)
      envchanged=0
      print -r -- "axle run: ${(j:, :)${(@)watch:t}} changed: starting $name again with it"
      _axle_run_sup_reenv
      continue
    fi
    if (( code == 0 || code == 130 || code == 143 )); then
      _axle_run_forget $name        # it finished, or was stopped (INT, TERM): nothing to show
      return 0
    fi
    # A crash. Again, after 1, 2, 4... s (at most 30), unless it keeps crashing right away:
    # 5 times within 30 s of starting, and it stays down.
    if [[ $onfail == on-crash ]]; then
      if (( EPOCHSECONDS - started < 30 )); then (( fast++ )); else fast=1; fi
      if (( fast <= 5 )); then
        local -i delay=$(( 1 << (fast - 1) ))
        (( delay > 30 )) && delay=30
        (( restarts++ ))
        _axle_run_put $dir restarts $restarts
        _axle_run_put $dir code $code
        _axle_run_put $dir state restarting
        _axle_run_drop $name restarting '' '' '' $code $restarts
        print -r -- "axle run: $name exited (code $code); starting it again in ${delay}s (restart $restarts)"
        [[ $notify == (crash|all) ]] && _axle_run_notify "axle run: $name crashed" "exit $code - starting it again (restart $restarts)"
        zselect -t $(( delay * unit ))
        [[ -e $dir/stopping || ! -d $dir ]] && return 0
        continue
      fi
      print -r -- "axle run: $name crashed $fast times in a row, each within 30 s: leaving it stopped"
    fi
    _axle_run_put $dir state crashed
    _axle_run_put $dir code $code
    _axle_run_drop $name crashed '' '' '' $code
    [[ $notify == (crash|all) ]] && _axle_run_notify "axle run: $name crashed" "exit $code - axle run logs $name"
    return 0
  done
}

# Its .env files' times and sizes (REPLY), to notice a change.
_axle_run_env_stamp() {
  local f
  local -A st
  REPLY=''
  for f; do
    if zstat -H st -- $f 2>/dev/null; then REPLY+="$st[mtime].$st[size]:"; else REPLY+='-:'; fi
  done
}

# Has a watched .env file changed (the supervisor's variables in scope)? Then the service
# is stopped (it's started again with the new values), status 0.
_axle_run_sup_envcheck() {
  (( reload )) || return 1
  local REPLY
  _axle_run_env_stamp $watch
  [[ $REPLY == $stamp ]] && return 1
  zselect -t 30                                    # (an editor may write it in two steps)
  _axle_run_env_stamp $watch
  stamp=$REPLY envchanged=1
  local -a reply left
  local pid
  _axle_run_tree $spid
  local -a pids=($reply)
  kill -TERM $pids 2>/dev/null
  local -i i
  for i in {1..50}; do                             # up to 5 s, then forced
    left=()
    for pid in $pids; do kill -0 $pid 2>/dev/null && left+=($pid); done
    (( ${#left} )) || break
    zselect -t 10
  done
  (( ${#left} )) && kill -KILL $left 2>/dev/null
  return 0
}

# The .env values again (the supervisor's envs): ones gone are unset, then the files'
# values and axle run's own (<dir>/env) exported.
_axle_run_sup_reenv() {
  local -a reply fresh=() ours=()
  local f e
  for f in $watch; do _axle_run_envfile $f && fresh+=($reply); done
  [[ -r $dir/env ]] && { _axle_run_words $dir/env; ours=($reply) }
  local -A now=()
  for e in $fresh $ours; do now[${e%%=*}]=1; done
  for e in $envs; do (( ${+now[${e%%=*}]} )) || unset -- ${e%%=*}; done
  for e in $fresh $ours; do export "$e"; done
  envs=($fresh $ours)
}

# The supervisor got TERM (its variables in scope): stop the service and everything it
# started, then forget it. `axle run stop` sends it TERM too, and does that itself.
_axle_run_sup_term() {
  [[ -e $dir/stopping || ! -d $dir ]] && return 0
  : >| $dir/stopping
  if (( spid )); then
    local -a reply left
    local pid
    _axle_run_tree $spid
    local -a pids=($reply)
    kill -TERM $pids 2>/dev/null
    local -i i
    for i in {1..50}; do                           # up to 5 s, then forced
      left=()
      for pid in $pids; do kill -0 $pid 2>/dev/null && left+=($pid); done
      (( ${#left} )) || break
      zselect -t 10
    done
    (( ${#left} )) && kill -KILL $left 2>/dev/null
  fi
  _axle_run_forget $name
}

# Has the shell that started it ended (_axle_run_owner_gone <pid:start time>)?
_axle_run_owner_gone() {
  [[ -n $1 ]] || return 1
  local REPLY
  kill -0 ${1%%:*} 2>/dev/null || return 0
  _axle_run_pstart ${1%%:*} && [[ $REPLY != ${1#*:} ]]
}

# A log past <bytes>: its lines so far go to log.1 (replacing the one before) and it starts
# again, empty. (Copied, then emptied: the service keeps writing to the same file, opened
# for appending.) It costs one stat every 2 s while it's small.
_axle_run_log_trim() {
  local dir=$1; local -i max=$2
  (( max > 0 )) || return 0
  local -a st
  zstat -A st +size -- $dir/log 2>/dev/null || return 0
  (( st[1] > max )) || return 0
  command cp -f -- $dir/log $dir/log.1 2>/dev/null && : >| $dir/log
  print -r -- "axle run: the log reached ${logmax:-10M}; what came before is in log.1" >> $dir/log
}

# A size like 10M, 500K, 1G or bytes, in bytes (REPLY; 0: no limit).
_axle_run_size() {
  local v=${1:-10M}
  local -i n=${v%%[KkMmGg]*}
  case $v in
    *[Kk]) REPLY=$(( n * 1024 )) ;;
    *[Mm]) REPLY=$(( n * 1048576 )) ;;
    *[Gg]) REPLY=$(( n * 1073741824 )) ;;
    *)     REPLY=$n ;;
  esac
}

# Does http://localhost:<port><path> answer 2xx or 3xx? (zsh's own TCP: no curl.)
_axle_run_health_ok() {
  setopt localoptions extendedglob
  zmodload zsh/net/tcp 2>/dev/null || return 0     # (can't ask: don't hold it back)
  local REPLY line
  ztcp 127.0.0.1 $1 2>/dev/null || return 1
  local -i fd=$REPLY
  print -u $fd -rn -- "GET $2 HTTP/1.0"$'\r\n'"Host: localhost"$'\r\n\r\n' 2>/dev/null
  IFS= read -t 2 -r -u $fd line 2>/dev/null
  ztcp -c $fd 2>/dev/null
  [[ $line == HTTP/[0-9.]##' '[23][0-9][0-9]* ]]
}

# A desktop notification (AXLE_RUN_NOTIFY): _axle_run_notify <title> <message>. In the
# background, never waited for. Only letters, digits and plain punctuation reach the program
# (a name from a project never becomes a command). WSL: a Windows toast (through PowerShell,
# under its name); macOS: osascript; Linux: notify-send. None of those: nothing.
_axle_run_notify() {
  setopt localoptions extendedglob
  local title=${1//[^A-Za-z0-9 ._:()\/-]/} msg=${2//[^A-Za-z0-9 ._:()\/-]/}
  if [[ -n $_AXLE_RUN_NOTIFY_TO ]]; then           # (the tests: to a file, not the desktop)
    print -r -- "$title|$msg" >> $_AXLE_RUN_NOTIFY_TO
  elif [[ -r /proc/version && $(</proc/version) == *[Mm]icrosoft* ]] && (( $+commands[powershell.exe] )); then
    local ps="\$m=[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime];
\$x=\$m::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02);
\$t=\$x.GetElementsByTagName('text');
[void]\$t.Item(0).AppendChild(\$x.CreateTextNode('$title'));
[void]\$t.Item(1).AppendChild(\$x.CreateTextNode('$msg'));
\$m::CreateToastNotifier('{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\\WindowsPowerShell\\v1.0\\powershell.exe').Show([Windows.UI.Notifications.ToastNotification]::new(\$x))"
    ( print -r -- $ps | command powershell.exe -NoProfile -NonInteractive -Command - ) >/dev/null 2>&1 </dev/null &!
  elif [[ $OSTYPE == darwin* ]]; then
    command osascript -e "display notification \"$msg\" with title \"$title\"" >/dev/null 2>&1 </dev/null &!
  elif (( $+commands[notify-send] )); then
    command notify-send -a axle "$title" "$msg" >/dev/null 2>&1 </dev/null &!
  fi
  return 0
}
