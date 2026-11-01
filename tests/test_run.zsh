# axle run (docs/legionary/ROADMAP.md). M0: which project, its root, and why.

# A history log line: hist <seconds ago> <dir>
hist() {
  mkdir -p $HOME/.local/share/axle
  print -r -- "$(( EPOCHSECONDS - $1 ))"$'\t0\t0.10\t'"$2"$'\t\tls' >> $HOME/.local/share/axle/history
}

# Two projects under ~/repos: shop-api (Python, with a venv) and cli (git).
projects() {
  mkdir -p $HOME/repos/shop-api/{.venv,app} $HOME/repos/cli/src
  : > $HOME/repos/shop-api/pyproject.toml; : > $HOME/repos/shop-api/.venv/pyvenv.cfg
  mkrepo $HOME/repos/cli >/dev/null
  hist 7200 $HOME/repos/shop-api/app
  hist 60   $HOME/repos/cli/src
  hist 30   $HOME
}

test_run_lazy_and_off_by_default() {
  (
    AXLE_MODULES=(run) load_tool
    [[ $functions[_axle_project_root] == *_axle_lazy_load* ]] || fail "the project helpers load when first used"
  ) || exit 1
  load_tool
  (( ${AXLE_MODULES[(Ie)run]} )) && fail "run is off by default on this branch"
  (( ${+_axle_cmd_fn[run]} )) && fail "not registered unless switched on"
  AXLE_MODULES=(run) load_tool
  assert_eq "${_axle_cmd_fn[run]}" _axle_cmd_run "registered"
  [[ $functions[_axle_cmd_run] == *_axle_lazy_load* ]] || fail "its code isn't loaded at startup"
}

test_run_project_root() {
  AXLE_MODULES=(run) load_tool
  projects
  local -a reply
  _axle_project_root $HOME/repos/shop-api/app
  assert_eq "$reply" "$HOME/repos/shop-api pyproject.toml" "nearest marker up the tree"
  _axle_project_root $HOME/repos/cli/src
  assert_eq "$reply" "$HOME/repos/cli .git" ".git"
  : > $HOME/package.json
  _axle_project_root $HOME && fail "~ itself is never a project"
  mkdir -p $T/plain; _axle_project_root $T/plain && fail "a plain folder isn't one"
  return 0
}

test_run_dry_run_why() {
  AXLE_MODULES=(run) load_tool
  projects
  local out
  cd $HOME/repos/shop-api/app
  out=$(axle run --dry-run 2>&1)
  assert_contains "$out" "root   ~/repos/shop-api" "here: its root"
  assert_contains "$out" "you're in it · marked by pyproject.toml" "here: why"
  assert_contains "$out" "venv   .venv" "its venv"
  cd $HOME
  out=$(axle run --dry-run 2>&1)
  assert_contains "$out" "root   ~/repos/cli" "elsewhere: the last project"
  assert_contains "$out" "the last project you worked in (1m ago)" "elsewhere: why"
  cd $HOME/repos/cli/src
  out=$(axle run -n 2>&1)
  assert_contains "$out" "you're in it" "in cli: cli"
  out=$(axle run shop -n 2>&1)
  assert_contains "$out" "root   ~/repos/shop-api" "words: j's pick"
  assert_contains "$out" 'the best match for "shop"' "words: why"
  out=$(axle run re cl -n 2>&1)
  assert_contains "$out" "root   ~/repos/cli" "several words: path, then the project's name"
  out=$(axle run app -n 2>&1)
  assert_contains "$out" "root   ~/repos/shop-api" "a subfolder's name: j's pick, then its project"
  out=$(axle run $HOME/repos/cli -n 2>&1)
  assert_contains "$out" "the folder you gave" "a path"
}

test_run_last_skips_current() {
  AXLE_MODULES=(run) load_tool
  projects
  local REPLY
  cd $HOME/repos/cli/src
  _axle_run_last; assert_eq "$REPLY" "$HOME/repos/shop-api" "not the one you're in"
  cd $HOME
  _axle_run_last; assert_eq "$REPLY" "$HOME/repos/cli" "the most recent"
  rm -rf $HOME/repos/cli
  _axle_run_last; assert_eq "$REPLY" "$HOME/repos/shop-api" "a project that's gone is skipped"
}

test_run_nothing_to_run() {
  AXLE_MODULES=(run) load_tool
  local out
  cd $HOME
  out=$(axle run -n 2>&1) && fail "no project, no history: an error"
  assert_contains "$out" "none in your history yet"
  out=$(axle run nomatch -n 2>&1) && fail "no match: an error"
  assert_contains "$out" "no project matches 'nomatch'"
  out=$(axle run --bogus 2>&1) && fail "unknown option"
  return 0
}

test_run_state_layout() {
  AXLE_MODULES=(run) load_tool
  _axle_run_state_init
  local d=$HOME/.local/state/axle/run
  [[ -d $d/services && -d $d/projects && -f $d/trust ]] || fail "services/, projects/, trust"
  local REPLY a
  _axle_run_hash /some/root; a=$REPLY
  _axle_run_hash /some/root; assert_eq "$REPLY" "$a" "the hash is stable"
  _axle_run_hash /other/root; [[ $REPLY != $a ]] || fail "and differs per root"
}

test_shared_helpers_without_theme() {
  load_tool
  mkdir -p $T/p/deep/.venv; : > $T/p/package.json; : > $T/p/deep/.venv/pyvenv.cfg
  cd $T/p/deep
  _axle_scan_markers
  assert_eq "${_axle_markers[package.json]}" "$T/p" "markers work without Benzene"
  assert_eq "${_axle_markers[venv]}" "$T/p/deep/.venv" "and find the venv"
  local REPLY; _axle_venv_find $T/p/deep
  assert_eq "$REPLY" "$T/p/deep/.venv" "_axle_venv_find"
}

# --- M1: find and run ---------------------------------------------------------------

# The sample projects, copied out of the repository (else its .git would be their root).
fixtures() {
  mkdir -p $T/fx && cp -R $ROOT/tests/fixtures/run/. $T/fx/
}

# What detection says for a sample: "command | kind | port | what"
detect() {
  local REPLY
  _axle_run_detect $T/fx/$1 || { REPLY='none'; print -r -- none; return }
  _axle_run_show $T/fx/$1
  print -r -- "$REPLY | $_axle_run_kind | $_axle_run_port | $_axle_run_what"
}

test_run_detects_each_sample() {
  AXLE_MODULES=(run) load_tool
  fixtures
  local py=python; whence -p python3 >/dev/null && py=python3
  local -a cases=(
    "fastapi|$py -m uvicorn main:api --reload | service | 8000 | python · FastAPI"
    "flask|$py -m flask --app app.py run --debug --port 5050 | service | 5050 | python · Flask"
    "django|$py manage.py runserver | service | 8000 | python · Django"
    "streamlit|$py -m streamlit run streamlit_app.py | service | 8501 | python · Streamlit"
    "py-script|tool | task |  | python"
    "py-entry|$py main.py | task |  | python"
    "vite|pnpm run dev | service | 5173 | node · Vite (pnpm)"
    "next|npm run dev | service | 3100 | node · Next.js (npm)"
    "node-cli|npm run start | task |  | node (npm)"
    "express|node server.js | service | 4000 | node · express"
    "axum|cargo run | service | 3300 | rust · axum"
    "rust-cli|cargo run | task |  | rust"
    "gin|go run . | service | 9090 | go · gin"
    "go-http|go run . | service | 8081 | go · net/http"
    "go-cli|go run . | task |  | go"
    "static|$py -m http.server 8000 | service | 8000 | static site"
    "nothing|none"
  )
  local c
  for c in $cases; do
    assert_eq "$(detect ${c%%|*})" "${c#*|}" "sample ${c%%|*}"
  done
}

test_run_never_turns_a_file_name_into_an_option() {
  AXLE_MODULES=(run) load_tool
  mkdir -p $T/odd; : > $T/odd/requirements.txt
  print 'import gradio' > $T/odd/-c.py
  print '{"main": "-e", "dependencies": {}}' > $T/odd/package.json; : > $T/odd/-e
  local REPLY
  _axle_run_detect $T/odd && fail "nothing safe to run: ${_axle_run_cmd}"
  return 0
}

test_run_uses_the_venv() {
  AXLE_MODULES=(run) load_tool
  fixtures
  mkdir -p $T/fx/fastapi/.venv/bin; : > $T/fx/fastapi/.venv/pyvenv.cfg
  print '#!/bin/sh' > $T/fx/fastapi/.venv/bin/python; chmod +x $T/fx/fastapi/.venv/bin/python
  assert_eq "$(detect fastapi)" ".venv/bin/python -m uvicorn main:api --reload | service | 8000 | python · FastAPI" "the venv's python"
}

test_run_asks_first_then_remembers() {
  AXLE_MODULES=(run) load_tool
  fixtures
  whence -p python3 >/dev/null || whence -p python >/dev/null || return 0
  cd $T/fx/py-entry
  local out
  out=$(axle run </dev/null 2>&1) && fail "not approved, no terminal to ask in: it doesn't run"
  assert_contains "$out" "First run of this command"
  [[ $out == *"hello from py-entry"* ]] && fail "nothing ran"
  out=$(axle run --dry-run 2>&1)
  assert_contains "$out" "trust  not run before"
  out=$(axle run --yes </dev/null 2>&1) || fail "--yes runs it: $out"
  assert_contains "$out" "hello from py-entry" "it ran, in the foreground"
  assert_contains "$out" "▶ python" "showing the command first"
  out=$(axle run </dev/null 2>&1) || fail "approved once: runs without asking: $out"
  assert_contains "$out" "hello from py-entry"
  # A changed command asks again.
  print '{"scripts": {"start": "node x.js"}}' > package.json
  out=$(axle run </dev/null 2>&1) && fail "a different command asks again"
  return 0
}

test_run_changed_script_asks_again() {
  AXLE_MODULES=(run) load_tool
  fixtures
  local REPLY a
  _axle_run_detect $T/fx/node-cli; _axle_run_trust_key $T/fx/node-cli; a=$REPLY
  sed -E 's/bin\/cli.js/bin\/evil.js/' $T/fx/node-cli/package.json > $T/p.json && mv $T/p.json $T/fx/node-cli/package.json
  _axle_run_detect $T/fx/node-cli; _axle_run_trust_key $T/fx/node-cli
  [[ $REPLY != $a ]] || fail "same command (npm run start), different script: a different key"
}

test_run_from_home_returns_to_last_project() {
  AXLE_MODULES=(run) load_tool
  fixtures
  hist 60 $T/fx/py-entry
  cd $HOME
  local out
  out=$(axle run </dev/null 2>&1; print "pwd=$PWD")
  out=${out//$'\e'\[[0-9;]#m/}                  # (colours)
  assert_contains "$out" "↩ py-entry (last worked on 1m ago)" "says where it goes"
  assert_contains "$out" "pwd=$T/fx/py-entry" "and goes there"
  out=$(axle run --dry-run 2>&1)
  assert_contains "$out" "run    "
}

test_run_static_folder_without_marker() {
  AXLE_MODULES=(run) load_tool
  fixtures
  local out
  out=$(axle run -n $T/fx/static 2>&1) || fail "a lone index.html is runnable: $out"
  assert_contains "$out" "kind   service on http://localhost:8000"
  cd $T/fx/static
  out=$(axle run -n 2>&1)
  assert_contains "$out" "you're in it"
  out=$(axle run -n $T/fx/nothing 2>&1) && fail "a folder with nothing to run isn't a project"
  return 0
}

# The real question in a terminal: n runs nothing and remembers nothing; y runs it once
# and remembers; the next time it just runs.
test_run_question_in_a_terminal() {
  zmodload zsh/zpty 2>/dev/null || return 0
  local py; py=$(whence -p python3 || whence -p python) || return 0
  AXLE_MODULES=(run) load_tool
  fixtures
  print -r -- "open('$T/ran', 'a').write('x')" > $T/fx/py-entry/main.py
  zpty sh "HOME=$HOME XDG_CONFIG_HOME=$XDG_CONFIG_HOME XDG_CACHE_HOME=$XDG_CACHE_HOME XDG_DATA_HOME=$XDG_DATA_HOME HISTFILE=$T/hist TERM=xterm AXLE_UPDATE_CHECK=0 AXLE_MODULES=run zsh -f -i"
  zpty -w sh "PS1='> '; AXLE_MODULES=(run); source $ROOT/axle.plugin.zsh; cd $T/fx/py-entry; : > $T/ready"
  _wait() { local -i i; local c; for i in {1..100}; do while zpty -rt sh c 2>/dev/null; do :; done; [[ -e $1 ]] && return 0; sleep 0.1; done; fail "no answer ($1)" }
  _wait $T/ready
  zpty -w sh "axle run; : > $T/done1"; sleep 0.5; zpty -n -w sh n; _wait $T/done1
  [[ -e $T/ran ]] && fail "answered n: nothing ran"
  [[ -s $HOME/.local/state/axle/run/trust ]] && fail "and nothing is remembered"
  zpty -w sh "axle run; : > $T/done2"; sleep 0.5; zpty -n -w sh y; _wait $T/done2
  assert_eq "$(<$T/ran)" x "answered y: it ran once"
  zpty -w sh "axle run; : > $T/done3"; _wait $T/done3
  assert_eq "$(<$T/ran)" xx "the next time, no question"
  zpty -w sh 'exit'; zpty -d sh 2>/dev/null
  return 0
}

# --- M2: background services ----------------------------------------------------------

# Whatever a service test started is stopped when its shell exits, even after a failure.
# Only in the test's own process: zpty forks it to start a terminal's shell, and that
# copy exiting must not stop anything.
zmodload zsh/system
typeset -g _test_pid=$sysparams[pid]
_stop_services() {
  (( sysparams[pid] == _test_pid )) || return 0
  local d p
  for d in $HOME/.local/state/axle/run/services/*(N/); do
    for p in $d/(watcher|pid)(N); do [[ $(<$p) == $$ ]] || kill -TERM $(<$p) 2>/dev/null; done
  done
}
zshexit_functions+=(_stop_services)

# A free-ish port for this test run.
free_port() { REPLY=$(( 20000 + ($$ * 7 + RANDOM) % 20000 )) }

# Wait (up to 20 s: a cold CI machine starts Python slowly) until a service's state file
# says <state>. On failure, everything needed to see why.
wait_state() {
  local -i i; local s='' d=$HOME/.local/state/axle/run/services/$1
  for i in {1..200}; do
    [[ -r $d/state ]] && s=$(<$d/state)
    [[ $s == $2 ]] && return 0
    sleep 0.1
  done
  local f info=''
  for f in $d/*(N); do [[ ${f:t} == (log|cmd) ]] || info+=" ${f:t}=$(<$f)"; done
  local w='' p=''
  [[ -r $d/watcher ]] && w=$(<$d/watcher); [[ -r $d/pid ]] && p=$(<$d/pid)
  fail "$1 never became $2 (last: ${s:-none};$info; procs: $(ps -o pid=,stat=,args= -p ${w:-1},${p:-1} 2>&1 | cut -c1-80 | tr '\n' ';'); log: $(tail -5 $d/log 2>/dev/null))"
}

# A small web project serving on a port of our choosing: python's http.server.
web_project() {
  mkdir -p $T/web; print '<!doctype html>' > $T/web/index.html; : > $T/web/requirements.txt
  local py; py=$(whence -p python3 || whence -p python) || return 1
  typeset -ga _axle_run_cmd=($py -m http.server $1 --bind 127.0.0.1)
  typeset -g _axle_run_kind=service _axle_run_port=$1
}

test_run_service_lifecycle() {
  AXLE_MODULES=(run) load_tool
  local REPLY port; free_port; port=$REPLY
  web_project $port || return 0
  local dir=$HOME/.local/state/axle/run/services/web drop=$HOME/.cache/axle/drops/run-web
  _axle_run_start $T/web web
  wait_state web up
  local pid=$(<$dir/pid)
  kill -0 $pid || fail "the service runs"
  assert_contains "$(<$drop)" "icon=⚡" "a ⚡ drop"
  assert_contains "$(<$drop)" "text=web :$port" "with its port"
  assert_contains "$(<$drop)" $'\nlink=http://localhost:'$port "and a link"
  assert_contains "$(<$drop)" $'\npid='"$(<$dir/watcher)"$'\n' "and the pid it lives with"
  local out
  out=$(cd $T/web && axle run ls)
  assert_match "$out" "*web*up*$port*http://localhost:$port*" "ls shows it"
  # In the prompt, with Benzene.
  load_theme
  _axle_seg_drops; plain "$REPLY"
  assert_contains "$REPLY" "⚡ web :$port" "the tab in the prompt"
  cd $T/web
  out=$(axle run stop)
  assert_contains "$out" "stopped web"
  sleep 0.2
  kill -0 $pid 2>/dev/null && fail "the process is gone"
  [[ -e $dir || -e $drop ]] && fail "nothing left behind"
  return 0
}

test_run_crash_turns_red() {
  AXLE_MODULES=(run) load_tool
  mkdir -p $T/bad; : > $T/bad/requirements.txt
  typeset -ga _axle_run_cmd=(sh -c 'echo "Traceback: boom" >&2; exit 3')
  typeset -g _axle_run_kind=service _axle_run_port=''
  _axle_run_start $T/bad bad
  wait_state bad crashed
  local drop=$HOME/.cache/axle/drops/run-bad
  assert_contains "$(<$drop)" "level=alarm" "a red tab"
  assert_contains "$(<$drop)" "exited (3)" "with the exit code"
  local out
  out=$(axle run ls)
  assert_match "$out" "*bad*exit 3*" "ls shows the crash"
  out=$(axle run logs bad)
  assert_contains "$out" "Traceback: boom" "logs show its output"
  [[ -e $drop ]] && fail "looking at the logs clears the red tab"
  axle run stop bad >/dev/null
  [[ -e $HOME/.local/state/axle/run/services/bad ]] && fail "stop clears a crashed one"
  return 0
}

test_run_stop_all_leaves_nothing() {
  AXLE_MODULES=(run) load_tool
  local REPLY p1 p2; free_port; p1=$REPLY; p2=$(( p1 + 1 ))
  web_project $p1 || return 0
  _axle_run_start $T/web one
  web_project $p2
  _axle_run_start $T/web two
  wait_state one up; wait_state two up
  local -a pids=($(<$HOME/.local/state/axle/run/services/one/pid) $(<$HOME/.local/state/axle/run/services/two/pid)
                 $(<$HOME/.local/state/axle/run/services/one/watcher) $(<$HOME/.local/state/axle/run/services/two/watcher))
  local out=$(axle run stop all)
  assert_contains "$out" "stopped one"
  assert_contains "$out" "stopped two"
  sleep 0.3
  local p
  for p in $pids; do kill -0 $p 2>/dev/null && fail "process $p still running"; done
  local -a left=($HOME/.local/state/axle/run/services/*(N) $HOME/.cache/axle/drops/run-*(N))
  (( ${#left} )) && fail "files left behind: $left"
  assert_eq "$(axle run ls)" "nothing running"
}

test_run_restart_and_env_file() {
  AXLE_MODULES=(run) load_tool
  mkdir -p $T/envp; : > $T/envp/requirements.txt
  print -l '# settings' 'export GREETING="hello there"' 'TOKEN=abc # comment' 'BAD LINE' 'EVIL=$(touch '$T'/pwned)' > $T/envp/.env
  local -a reply
  _axle_run_envfile $T/envp/.env
  assert_eq "${(j:|:)reply}" "GREETING=hello there|TOKEN=abc|EVIL=\$(touch $T/pwned)" ".env read as data"
  typeset -ga _axle_run_cmd=(sh -c 'echo "$GREETING/$TOKEN/$EVIL" > out.txt; exec sleep 30')
  typeset -g _axle_run_kind=service _axle_run_port=''
  _axle_run_start $T/envp envp
  local -i i; for i in {1..50}; do [[ -s $T/envp/out.txt ]] && break; sleep 0.1; done
  assert_eq "$(<$T/envp/out.txt)" "hello there/abc/\$(touch $T/pwned)" "the values reach the service, as text"
  [[ -e $T/pwned ]] && fail "nothing in .env runs"
  local pid1=$(<$HOME/.local/state/axle/run/services/envp/pid)
  rm $T/envp/out.txt
  axle run restart envp >/dev/null
  for i in {1..50}; do [[ -s $T/envp/out.txt ]] && break; sleep 0.1; done
  local pid2=$(<$HOME/.local/state/axle/run/services/envp/pid)
  [[ $pid1 != $pid2 ]] || fail "restart starts a new process"
  kill -0 $pid1 2>/dev/null && fail "and stops the old one"
  axle run stop all >/dev/null
  return 0
}

test_run_pid_reuse_is_not_ours() {
  AXLE_MODULES=(run) load_tool
  local dir=$HOME/.local/state/axle/run/services/ghost
  mkdir -p $dir
  print $$ > $dir/pid; print 'not-the-start-time' > $dir/pstart; print crashed-not > $dir/state
  _axle_run_alive $dir && fail "a live pid with another start time isn't our service"
  local -a reply; _axle_run_services
  (( ${reply[(Ie)ghost]} )) && fail "and a dead service is cleaned up"
  return 0
}

# From a real terminal: `axle run --bg` starts it, the port comes from what it prints,
# and closing the terminal leaves it running (decided); `stop` ends it.
test_run_service_survives_closing_the_terminal() {
  zmodload zsh/zpty 2>/dev/null || return 0
  local py; py=$(whence -p python3 || whence -p python) || return 0
  AXLE_MODULES=(run) load_tool
  local REPLY port; free_port; port=$REPLY
  mkdir -p $T/srv
  print -l "import http.server, socketserver" \
    "s = socketserver.TCPServer(('127.0.0.1', $port), http.server.SimpleHTTPRequestHandler)" \
    "print('Serving at http://localhost:$port/', flush=True)" "s.serve_forever()" > $T/srv/main.py
  : > $T/srv/requirements.txt
  zpty sh "HOME=$HOME XDG_CONFIG_HOME=$XDG_CONFIG_HOME XDG_CACHE_HOME=$XDG_CACHE_HOME XDG_DATA_HOME=$XDG_DATA_HOME HISTFILE=$T/hist TERM=xterm AXLE_UPDATE_CHECK=0 zsh -f -i"
  zpty -w sh "PS1='> '; AXLE_MODULES=(run); source $ROOT/axle.plugin.zsh; cd $T/srv; axle run --yes --bg; : > $T/started"
  local -i i; local c
  for i in {1..150}; do while zpty -rt sh c 2>/dev/null; do :; done; [[ -e $T/started ]] && break; sleep 0.1; done
  [[ -e $T/started ]] || fail "axle run --bg didn't return"
  wait_state srv up
  local dir=$HOME/.local/state/axle/run/services/srv pid
  pid=$(<$dir/pid)
  assert_eq "$(<$dir/port)" $port "the port it printed"
  zpty -d sh 2>/dev/null                         # close the terminal
  sleep 1
  kill -0 $pid 2>/dev/null || fail "the service keeps running after the terminal closes"
  _axle_run_port_up $port || fail "and still answers"
  cd $T/srv; axle run stop >/dev/null
  sleep 0.2
  kill -0 $pid 2>/dev/null && fail "stop ends it"
  return 0
}

# --- M3: ports ------------------------------------------------------------------------

test_run_port_ways() {
  AXLE_MODULES=(run) load_tool
  fixtures
  local REPLY c
  local -a cases=(
    "fastapi|--port 9001|python3 -m uvicorn main:api --reload --port 9001"
    "flask|(already --port 5050)|python3 -m flask --app app.py run --debug --port 9001"
    "django|9001|python3 manage.py runserver 9001"
    "streamlit|--server.port|python3 -m streamlit run streamlit_app.py --server.port 9001"
    "vite|pnpm: --port|pnpm run dev --port 9001"
    "static|last word|python3 -m http.server 9001"
  )
  local py=python; whence -p python3 >/dev/null && py=python3
  for c in $cases; do
    local name=${c%%|*} want=${${c##*|}//python3/$py}
    _axle_run_detect $T/fx/$name
    _axle_run_apply_port 9001 || fail "$name: the port can be changed"
    _axle_run_show $T/fx/$name
    assert_eq "$REPLY" "$want" "$name: ${${c#*|}%%|*}"
    assert_eq "$_axle_run_port" 9001 "$name: the port is remembered"
  done
  # npm needs `--` before a script's own options; express takes PORT.
  print '{"scripts": {"dev": "vite"}}' > $T/fx/vite/package.json; rm $T/fx/vite/pnpm-lock.yaml
  _axle_run_detect $T/fx/vite; _axle_run_apply_port 9002; _axle_run_show $T/fx/vite
  assert_eq "$REPLY" "npm run dev -- --port 9002" "npm: -- --port"
  _axle_run_detect $T/fx/express; _axle_run_apply_port 9003
  assert_eq "$_axle_run_env" "PORT=9003" "express: PORT"
  # A script with its own port, or a Rust server that doesn't read PORT: can't be changed.
  _axle_run_detect $T/fx/next; _axle_run_apply_port 9004 && fail "next -p 3100 sets its own port"
  _axle_run_detect $T/fx/axum; _axle_run_apply_port 9004 && fail "this axum app has a fixed port"
  return 0
}

test_run_port_from_env_and_vite_config() {
  AXLE_MODULES=(run) load_tool
  fixtures
  print 'PORT=4100' > $T/fx/express/.env
  _axle_run_detect $T/fx/express; assert_eq "$_axle_run_port" 4100 "PORT in .env (for a program that reads it)"
  print 'export default { server: { port: 5200 } }' > $T/fx/vite/vite.config.ts
  _axle_run_detect $T/fx/vite; assert_eq "$_axle_run_port" 5200 "vite.config server.port"
}

test_run_port_holder() {
  AXLE_MODULES=(run) load_tool
  local py; py=$(whence -p python3 || whence -p python) || return 0
  [[ -r /proc/net/tcp ]] || whence -p lsof >/dev/null || return 0
  local REPLY port; free_port; port=$REPLY
  $py -m http.server $port --bind 127.0.0.1 >/dev/null 2>&1 &
  local pid=$!
  local -i i; for i in {1..50}; do _axle_run_port_up $port && break; sleep 0.1; done
  _axle_run_port_holder $port; local got=$REPLY
  kill $pid 2>/dev/null
  assert_eq "$got" "$pid" "the process listening on the port"
  assert_match "$_axle_run_holder" "(#i)*python*" "and its name"
}

test_run_two_projects_same_port() {
  AXLE_MODULES=(run) load_tool
  local REPLY port; free_port; port=$REPLY
  local py; py=$(whence -p python3 || whence -p python) || return 0
  # Two static sites whose default port we pin to the same free one.
  mkdir -p $T/one $T/two
  print '<!doctype html>' > $T/one/index.html; print '<!doctype html>' > $T/two/index.html
  : > $T/one/requirements.txt; : > $T/two/requirements.txt
  functions[_axle_run_detect_orig]=$functions[_axle_run_detect]
  _axle_run_detect >/dev/null 2>&1 $T/one   # (load the real one)
  functions[_axle_run_detect_orig]=$functions[_axle_run_detect]
  _axle_run_detect() { _axle_run_detect_orig "$@" || return 1; _axle_run_cmd[-1]=$port; _axle_run_port=$port }
  local out
  cd $T/one; out=$(axle run --yes </dev/null 2>&1) || fail "the first runs: $out"
  wait_state one up
  cd $T/two; out=$(axle run --yes </dev/null 2>&1) || fail "the second runs: $out"
  assert_contains "$out" "Port $port is taken by your service one" "says who has it"
  wait_state two up
  assert_eq "$(<$HOME/.local/state/axle/run/services/one/port)" $port "the first on the port"
  assert_eq "$(<$HOME/.local/state/axle/run/services/two/port)" $(( port + 1 )) "the second on the next one"
  _axle_run_port_up $port && _axle_run_port_up $(( port + 1 )) || fail "both answer"
  axle run stop all >/dev/null
}

# In a terminal the busy port is a question: ↓ Enter picks "Stop one, then run here".
test_run_port_question_in_a_terminal() {
  zmodload zsh/zpty 2>/dev/null || return 0
  local py; py=$(whence -p python3 || whence -p python) || return 0
  AXLE_MODULES=(run) load_tool
  local REPLY port; free_port; port=$REPLY
  mkdir -p $T/one $T/two
  print '<!doctype html>' > $T/one/index.html; print '<!doctype html>' > $T/two/index.html
  : > $T/one/requirements.txt; : > $T/two/requirements.txt
  print -l "AXLE_MODULES=(run); source $ROOT/axle.plugin.zsh" \
    "_axle_run_detect $T/one >/dev/null 2>&1" \
    'functions[_axle_run_detect_orig]=$functions[_axle_run_detect]' \
    "_axle_run_detect() { _axle_run_detect_orig \"\$@\" || return 1; _axle_run_cmd[-1]=$port; _axle_run_port=$port }" \
    > $T/setup.zsh
  zpty sh "HOME=$HOME XDG_CONFIG_HOME=$XDG_CONFIG_HOME XDG_CACHE_HOME=$XDG_CACHE_HOME XDG_DATA_HOME=$XDG_DATA_HOME HISTFILE=$T/hist TERM=xterm AXLE_UPDATE_CHECK=0 zsh -f -i"
  zpty -w sh "PS1='> '; source $T/setup.zsh; cd $T/one; axle run --yes; cd $T/two; : > $T/ready"
  _wait() { local -i i; local c; for i in {1..150}; do while zpty -rt sh c 2>/dev/null; do :; done; [[ -e $1 ]] && return 0; sleep 0.1; done; fail "no answer ($1)" }
  _wait $T/ready
  wait_state one up
  zpty -w sh "axle run --yes; : > $T/done"
  sleep 1; zpty -n -w sh $'\e[B'; sleep 0.3; zpty -n -w sh $'\r'
  _wait $T/done
  wait_state two up
  [[ -e $HOME/.local/state/axle/run/services/one ]] && fail "one was stopped"
  assert_eq "$(<$HOME/.local/state/axle/run/services/two/port)" $port "two took its port"
  zpty -w sh 'axle run stop all; exit'; sleep 0.5; zpty -d sh 2>/dev/null
  return 0
}
