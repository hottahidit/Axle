# axle run: when it goes wrong. A service that crashed (or a task that failed) is looked at
# for a known cause: its log's last lines, then the project itself. The cause is said in a
# line, and the command that fixes it goes to the fix module: Esc Esc (or `fix`) puts it on
# the line, to check; nothing runs by itself.
#
#   No module named 'x'                → pip install x into the project's venv
#                                        (-r requirements.txt if it's listed there; uv sync)
#   ... and the project has no venv    → python3 -m venv .venv && .venv/bin/pip install ...
#   Cannot find module 'x', no node_modules, `vite: not found`
#                                      → npm / pnpm / yarn / bun install (or add x)
#   address already in use (port P)    → axle run set port <a free one> && axle run
#   database not reachable             → docker compose up -d <its service>, if the project's
#                                        compose file has it; else start it (service / brew)
#
#   _axle_run_diagnose <dir> [log] [port]   _axle_run_cause, _axle_run_remedy (status 1: unknown)
#   _axle_run_explain <dir> <log> <rerun>   says it, and hands the fix to Esc Esc

typeset -g _axle_run_cause='' _axle_run_remedy=''

# Python import name → its package on PyPI, where they differ (pip reads - and _ alike).
typeset -gA _axle_run_pipname=(
  cv2 opencv-python  PIL pillow  yaml pyyaml  sklearn scikit-learn  skimage scikit-image
  bs4 beautifulsoup4  dotenv python-dotenv  jwt PyJWT  dateutil python-dateutil
  magic python-magic  serial pyserial  usb pyusb  Crypto pycryptodome  OpenSSL pyOpenSSL
  attr attrs  docx python-docx  pptx python-pptx  fitz pymupdf  socketio python-socketio
  engineio python-engineio  multipart python-multipart  jose python-jose  gi PyGObject
  psycopg2 psycopg2-binary  MySQLdb mysqlclient  telegram python-telegram-bot
  discord discord.py  win32api pywin32  google google-api-python-client
)

# A command run in <dir>: as is when you're there, else after a cd (REPLY).
_axle_run_in() {
  local d=$1
  [[ $PWD == $d ]] && { REPLY=$2; return }
  if [[ $d == $HOME/* && ${(q-)d} == $d ]]; then d="~/${d#$HOME/}"; else d=${(q-)d}; fi
  REPLY="cd $d && $2"
}

_axle_run_diagnose() {
  setopt localoptions extendedglob
  local dir=$1 log=$2 port=$3 text='' REPLY
  _axle_run_cause='' _axle_run_remedy=''
  if [[ -r $log ]]; then
    text=$(command tail -n 80 -- $log 2>/dev/null)
    text=${text//$'\e'\[[0-9;?]#[a-zA-Z]/}         # (colours)
  fi
  if [[ -n $text ]]; then
    _axle_run_diag_python $dir "$text" && return 0
    _axle_run_diag_node $dir "$text" && return 0
    _axle_run_diag_port $dir "$text" $port && return 0
    _axle_run_diag_db $dir "$text" && return 0
  fi
  _axle_run_diag_state $dir
}

# The project's package manager for Node (lockfiles, here or in the folder above).
_axle_run_diag_pm() {
  local d
  REPLY=npm
  for d in $1 ${1:h}; do
    if   [[ -f $d/pnpm-lock.yaml ]]; then REPLY=pnpm; return
    elif [[ -f $d/yarn.lock ]]; then REPLY=yarn; return
    elif [[ -f $d/bun.lockb || -f $d/bun.lock ]]; then REPLY=bun; return
    elif [[ -f $d/package-lock.json ]]; then return
    fi
  done
}

# --- Python ---------------------------------------------------------------------------

_axle_run_diag_python() {
  local dir=$1 text=$2 REPLY
  [[ $text =~ "No module named '?([A-Za-z0-9_.]+)'?" ]] || return 1
  local mod=${match[1]%%.*}
  # One of the project's own modules: it's run from the wrong place, not missing.
  if [[ -e $dir/$mod.py || -d $dir/$mod ]]; then
    _axle_run_cause="no module named $mod, though it's in the project (started from another folder?)"
    return 0
  fi
  local pkg=${_axle_run_pipname[$mod]:-$mod} venv='' py=python3 install req=''
  (( $+commands[python3] )) || py=python
  _axle_venv_find $dir && venv=$REPLY
  # requirements.txt, and whether it lists the package (names compared the way pip does).
  if [[ -f $dir/requirements.txt ]]; then
    local norm=${${(L)pkg}//[-_.]##/-} line
    req=listed-not
    while IFS= read -r line; do
      line=${${(L)line%%[<>=!~;\[ #]*}//[-_.]##/-}
      [[ $line == $norm ]] && { req=listed; break }
    done < $dir/requirements.txt
  fi
  # A venv it shares with other projects (or would: AXLE_RUN_UNIVENV): axle run deps
  # installs into it only what fits it, else gives the project its own.
  local -i share=0
  if [[ -f $dir/uv.lock ]]; then share=0
  elif [[ -n $venv ]]; then [[ -x $venv/bin/python ]] && _axle_run_venv_shared $dir $venv && share=1
  else _axle_run_unifolder $dir && share=1
  fi
  if (( share )); then
    local where=${${venv:-$REPLY/.venv}/#$HOME/~}
    if [[ -n $venv ]]; then
      _axle_run_cause="no module named $mod (not in the shared venv $where)"
    else
      _axle_run_cause="no module named $mod, and the project has no venv (it can share $where)"
    fi
    install='axle run deps'
    if [[ -z $req ]]; then                           # (listed in pyproject.toml?)
      local -a reply; local d
      _axle_run_deps_list $dir
      for d in $reply; do [[ ${${(L)d%%[<>=!~;\[ ]*}//[-_.]##/-} == ${${(L)pkg}//[-_.]##/-} ]] && req=listed; done
    fi
    [[ $req == listed ]] || install+=" ${(q-)pkg}"
    _axle_run_in $dir $install; _axle_run_remedy=$REPLY
    return 0
  fi
  if [[ -f $dir/uv.lock ]] && (( $+commands[uv] )); then
    _axle_run_cause="no module named $mod: the project's packages aren't installed (uv)"
    install='uv sync'
  elif [[ -z $venv || ! -x $venv/bin/python ]]; then
    local at=.venv clear=''
    if [[ -n $venv ]]; then
      _axle_run_cause="no module named $mod, and ${venv:t} has no working Python"
      [[ $venv == $dir/* ]] && at=${venv#$dir/} || at=${(q-)venv}
      clear=' --clear'
    else
      _axle_run_cause="no module named $mod, and the project has no venv"
    fi
    if [[ -n $req ]]; then install='-r requirements.txt'; else install=${(q-)pkg}; fi
    install="$py -m venv$clear $at && $at/bin/pip install $install"
  else
    local pip=$venv/bin/pip
    [[ $venv == $dir/* ]] && pip=${venv#$dir/}/bin/pip
    if [[ $req == listed ]]; then
      _axle_run_cause="no module named $mod: requirements.txt isn't installed in ${venv:t}"
      install="$pip install -r requirements.txt"
    else
      _axle_run_cause="no module named $mod (not installed in ${venv:t})"
      install="$pip install ${(q-)pkg}"
    fi
  fi
  _axle_run_in $dir $install; _axle_run_remedy=$REPLY
}

# --- Node -----------------------------------------------------------------------------

_axle_run_diag_node() {
  local dir=$1 text=$2 REPLY m=''
  [[ -f $dir/package.json ]] || return 1
  if [[ $text =~ "Cannot find (module|package) '([^']+)'" ]]; then
    m=$match[2]
  elif [[ $text =~ "([A-Za-z0-9_.-]+): (command )?not found" ]]; then
    m=:bin:$match[1]
  else
    return 1
  fi
  [[ $m == node:* ]] && return 1
  if [[ $m == (.|/)* ]]; then
    _axle_run_cause="a file it imports is missing: $m"
    return 0
  fi
  _axle_run_diag_pm $dir; local pm=$REPLY
  local add=add; [[ $pm == npm ]] && add=install
  if [[ ! -d $dir/node_modules && ! -d ${dir:h}/node_modules ]]; then
    _axle_run_cause="its packages aren't installed (no node_modules)"
    _axle_run_in $dir "$pm install"
  elif [[ $m == :bin:* ]]; then
    _axle_run_cause="${m#:bin:} isn't installed (node_modules is missing it)"
    _axle_run_in $dir "$pm install"
  else
    local -a parts=(${(s:/:)m})                                     # @scope/pkg or pkg
    if [[ $m == @* ]]; then m=${(j:/:)parts[1,2]}; else m=$parts[1]; fi
    _axle_run_read $dir/package.json
    if [[ $REPLY == *\"$m\"* ]]; then
      _axle_run_cause="$m isn't installed (it's in package.json)"
      _axle_run_in $dir "$pm install"
    else
      _axle_run_cause="$m isn't in package.json"
      _axle_run_in $dir "$pm $add ${(q-)m}"
    fi
  fi
  _axle_run_remedy=$REPLY
}

# --- A port that's taken ----------------------------------------------------------------

_axle_run_diag_port() {
  setopt localoptions extendedglob
  local dir=$1 text=$2 port=$3 REPLY l
  local -a lines=(${(M)${(f)text}:#(#i)*(address already in use|eaddrinuse|only one usage of each socket address|port <-> is (already )#(in use|allocated))*})
  (( ${#lines} )) || return 1
  for l in ${(Oa)lines}; do
    if [[ $l =~ "[Pp]ort ([0-9]{2,5})" || $l =~ ":([0-9]{2,5})([^0-9]|$)" ]]; then
      port=$match[1]; break
    fi
  done
  if [[ -z $port ]]; then
    _axle_run_cause="its port is taken (address already in use)"
    return 0
  fi
  local who=''
  _axle_run_port_holder $port && who=" (by ${_axle_run_holder:-pid $REPLY})"
  _axle_run_cause="port $port is taken$who"
  _axle_run_free_port $port || return 0
  _axle_run_in $dir "axle run set port $_axle_run_freed && axle run"
  _axle_run_remedy=$REPLY
  typeset -g _axle_run_remedy_reruns=1
}

# --- A database that isn't running ------------------------------------------------------

_axle_run_diag_db() {
  setopt localoptions extendedglob
  local dir=$1 text=$2 REPLY kind='' port='' p
  [[ $text == (#i)*(connection refused|econnrefused|could not connect|can\'t connect|error 111|serverselectionerror|is the server running|connection to server at)* ]] || return 1
  local -A by_port=(5432 postgres 3306 mysql 6379 redis 27017 mongodb 5672 rabbitmq)
  for p in ${(k)by_port}; do
    [[ $text == *[^0-9]$p([^0-9]*|) ]] && { kind=$by_port[$p] port=$p; break }
  done
  if [[ -z $kind ]]; then
    case $text in
      (#i)*(postgres|psycopg|asyncpg)*) kind=postgres port=5432 ;;
      (#i)*(mysql|mariadb)*)            kind=mysql port=3306 ;;
      (#i)*redis*)                      kind=redis port=6379 ;;
      (#i)*mongo*)                      kind=mongodb port=27017 ;;
      (#i)*(amqp|rabbit)*)              kind=rabbitmq port=5672 ;;
      *) return 1 ;;
    esac
  fi
  # In the project's compose file: start that service.
  local d f svc=''
  for d in $dir ${dir:h}; do
    for f in $d/(compose.yaml|compose.yml|docker-compose.yml|docker-compose.yaml)(N.); do
      _axle_run_compose_db $f $kind && { svc=$REPLY; break 2 }
    done
  done
  if [[ -n $svc ]]; then
    _axle_run_cause="can't reach $kind (:$port): it's $svc in ${f:t}, not started"
    _axle_run_in ${f:h} "docker compose up -d ${(q-)svc}"; _axle_run_remedy=$REPLY
    return 0
  fi
  _axle_run_cause="can't reach $kind on :$port: it isn't running"
  local -A unit=(postgres postgresql mysql mysql redis redis-server mongodb mongod rabbitmq rabbitmq-server)
  local -A formula=(postgres postgresql mysql mysql redis redis mongodb mongodb-community rabbitmq rabbitmq)
  if [[ $OSTYPE == darwin* ]]; then
    (( $+commands[brew] )) && _axle_run_remedy="brew services start $formula[$kind]"
  elif [[ -e /etc/init.d/$unit[$kind] || -e /lib/systemd/system/$unit[$kind].service ||
          -e /usr/lib/systemd/system/$unit[$kind].service ]]; then
    _axle_run_remedy="sudo service $unit[$kind] start"
  else
    _axle_run_cause+=" (nor installed here)"
  fi
  return 0
}

# The service in compose file <f> that runs a <kind> database (REPLY): by its image, else
# its name. Read as text, line by line (two-space services under `services:`).
_axle_run_compose_db() {
  setopt localoptions extendedglob
  local f=$1 kind=$2 line cur='' in=0 byname=''
  local pat
  case $kind in
    postgres) pat='(postgres|postgis|timescale)' ;;
    mysql)    pat='(mysql|mariadb)' ;;
    redis)    pat='(redis|valkey)' ;;
    mongodb)  pat='mongo' ;;
    rabbitmq) pat='rabbitmq' ;;
  esac
  REPLY=''
  while IFS= read -r line; do
    if [[ $line == services:* ]]; then in=1; continue; fi
    (( in )) || continue
    [[ $line == [^[:space:]#]* ]] && { in=0; continue }        # the next top-level key
    if [[ $line =~ '^  ([A-Za-z0-9_.-]+):[[:space:]]*$' ]]; then
      cur=$match[1]
      [[ -z $byname && $cur == (#i)*${~pat}* ]] && byname=$cur
    elif [[ -n $cur && $line == [[:space:]]##image:* ]]; then
      local img=${${${line#*image:}##[[:space:]]#}//[\"\']/}
      [[ ${${img%% *}:t} == (#i)${~pat}* ]] && { REPLY=$cur; return 0 }
    fi
  done < $f
  REPLY=$byname
  [[ -n $REPLY ]]
}

# --- Nothing in the log: the project itself -------------------------------------------

_axle_run_diag_state() {
  local dir=$1 REPLY
  if [[ -f $dir/package.json && ! -d $dir/node_modules && ! -d ${dir:h}/node_modules ]]; then
    _axle_run_read $dir/package.json
    if [[ $REPLY == *\"(dependencies|devDependencies)\"* ]]; then
      _axle_run_diag_pm $dir
      _axle_run_cause="its packages aren't installed (no node_modules)"
      _axle_run_in $dir "$REPLY install"; _axle_run_remedy=$REPLY
      return 0
    fi
  fi
  if [[ -f $dir/requirements.txt ]] && ! _axle_venv_find $dir && _axle_run_unifolder $dir; then
    _axle_run_cause="the project has no venv (its requirements.txt isn't installed; it can share ${REPLY/#$HOME/~}/.venv)"
    _axle_run_in $dir 'axle run deps'; _axle_run_remedy=$REPLY
    return 0
  fi
  if [[ -f $dir/requirements.txt ]] && ! _axle_venv_find $dir; then
    local py=python3; (( $+commands[python3] )) || py=python
    _axle_run_cause="the project has no venv (its requirements.txt isn't installed)"
    _axle_run_in $dir "$py -m venv .venv && .venv/bin/pip install -r requirements.txt"
    _axle_run_remedy=$REPLY
    return 0
  fi
  return 1
}

# --- Saying it ------------------------------------------------------------------------

# The command Esc Esc / `fix` puts on the line: until the next command you run.
_axle_run_fix_set() {
  typeset -g _axle_run_fix=$1
  (( ${preexec_functions[(Ie)_axle_run_fix_clear]} )) || preexec_functions+=(_axle_run_fix_clear)
}
_axle_run_fix_clear() {
  [[ -n $AXLE_FIX_CMD && ${1%% *} == $AXLE_FIX_CMD ]] && return 0   # (`fix` reads it)
  _axle_run_fix=''
  preexec_functions=(${preexec_functions:#_axle_run_fix_clear})
}

# _axle_run_explain <dir> <log> <rerun> [port]: the cause and fix of a failure, said under
# its log. <rerun> runs it again after the fix (e.g. axle run restart web).
_axle_run_explain() {
  local dir=$1 log=$2 rerun=$3 port=$4
  typeset -g _axle_run_remedy_reruns=0
  _axle_run_diagnose $dir "$log" $port || return 1
  local muted=${_axle_c[muted]:-244} a=${_axle_c[accent]:-magenta} fixcmd=$_axle_run_remedy
  _axle_printp "%F{${_axle_c[warn]:-yellow}}→%f ${_axle_run_cause//\%/%%}"
  [[ -n $fixcmd ]] || return 0
  (( _axle_run_remedy_reruns )) || [[ -z $rerun ]] || fixcmd+=" && $rerun"
  local how='copy it'
  if [[ -n $AXLE_FIX_KEY ]] && (( $+functions[axle-fix] )); then how='Esc Esc puts it on the line'
  elif [[ -n $AXLE_FIX_CMD ]] && (( $+functions[_axle_fix_cmd] )); then how="$AXLE_FIX_CMD puts it on the line"
  fi
  _axle_printp "  %F{$a}${fixcmd//\%/%%}%f  %F{$muted}($how)%f"
  _axle_run_fix_set $fixcmd
}
