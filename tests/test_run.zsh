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
  out=$(axle run -n $T/fx/nothing 2>&1) && fail "a folder with nothing to run isn't a project: $out"
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
  [[ -n $TMUX_TMPDIR ]] && whence -p tmux >/dev/null && command tmux kill-server 2>/dev/null
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
  # The annotation CI shows is cut at 1500 characters: what matters most goes first.
  local w='' p='' tr=''
  [[ -r $d/watcher ]] && w=$(<$d/watcher); [[ -r $d/pid ]] && p=$(<$d/pid)
  [[ -r $d/trace ]] && tr=$(tail -14 $d/trace | sed -E 's|/[^ ]*/(services\|work)/|…/|g' | cut -c1-80)
  fail "$1 never became $2 (last: ${s:-none})
service: $(lsof -nP -a -p ${p:-1} -iTCP 2>/dev/null | tail -n +2 | awk '{print $8, $9, $10}' | tr '\n' ';') stack: $(command -v sample >/dev/null && sample ${p:-1} 1 -mayDie 2>/dev/null | grep -oE 'getaddrinfo|getnameinfo|gethostby[a-z_]*|getfqdn|poll|select|accept|__recvfrom' | sort -u | tr '\n' ' ')
children of the supervisor: $(ps -A -o ppid=,pid=,stat=,etime=,comm= | awk -v w="${w:-1}" '$1 == w { print $2, $3, $4, $5 }' | sed 's|/[^ ]*/||' | tr '\n' ';')
trace end:
$tr
log: $(tail -3 $d/log 2>/dev/null | cut -c1-80)"
}

# A small web project serving on a port of our choosing (tests/serve.py).
web_project() {
  mkdir -p $T/web; print '<!doctype html>' > $T/web/index.html; : > $T/web/requirements.txt
  local py; py=$(whence -p python3 || whence -p python) || return 1
  typeset -ga _axle_run_cmd=($py $ROOT/tests/serve.py $1)
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
  assert_contains "$(<$drop)" "icon=✘" "and not the ⚡ of a running one"
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
  assert_eq "$(<$T/envp/out.txt)" "hello there/abc/\$(touch $T/pwned)" "the same command, with all its words, and .env"
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
  $py $ROOT/tests/serve.py $port >/dev/null 2>&1 &
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
  _axle_run_detect() { _axle_run_detect_orig "$@" || return 1; _axle_run_cmd=($_axle_run_cmd[1] $ROOT/tests/serve.py $port); _axle_run_port=$port }
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
    "_axle_run_detect() { _axle_run_detect_orig \"\$@\" || return 1; _axle_run_cmd=(\$_axle_run_cmd[1] $ROOT/tests/serve.py $port); _axle_run_port=$port }" \
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

# A server listening only on IPv6 (like Vite on ::1) counts as up.
test_run_ipv6_only_server_is_up() {
  AXLE_MODULES=(run) load_tool
  local py; py=$(whence -p python3 || whence -p python) || return 0
  local REPLY port; free_port; port=$REPLY
  $py $ROOT/tests/serve.py $port ::1 >/dev/null 2>&1 &
  local pid=$!
  local -i i ok=0
  for i in {1..50}; do _axle_run_port_up $port && { ok=1; break }; sleep 0.1; done
  # (No IPv6 on this machine: python couldn't bind, nothing to check.)
  if ! kill -0 $pid 2>/dev/null; then return 0; fi
  kill $pid 2>/dev/null
  (( ok )) || fail "an IPv6-only listener on $port is up"
  local -i j; for j in {1..30}; do _axle_run_port_up $port || break; sleep 0.1; done
  _axle_run_port_up $port && fail "and down once it's gone"
  return 0
}

# --- M4: more projects ----------------------------------------------------------------

test_run_detects_more_samples() {
  AXLE_MODULES=(run) load_tool
  fixtures
  local -a cases=(
    "compose-app|docker compose -f compose.yaml up -d | compose | 8080 | docker compose (2 services)"
    "procfile-web|sh -c 'python3 -m http.server \$PORT' | service | 5000 | Procfile"
    "make-run|make run | task |  | make"
    "just-dev|just dev | task |  | just"
    "rust-lib|none"
  )
  local c
  for c in $cases; do
    assert_eq "$(detect ${c%%|*})" "${c#*|}" "sample ${c%%|*}"
  done
}

test_run_finds_parts() {
  AXLE_MODULES=(run) load_tool
  fixtures
  local -a reply
  _axle_run_parts $T/fx/monorepo
  assert_eq "${(j: :)reply}" "api web" "a frontend and a backend (docs isn't a part)"
  _axle_run_parts $T/fx/cargo-ws
  assert_eq "${(j: :)reply}" "cli" "a Cargo workspace: the member with a binary"
  _axle_run_parts $T/fx/compose-app
  assert_eq "${(j: :)reply}" "." "compose runs the whole project"
  local REPLY
  _axle_run_partname $T/fx/monorepo web; assert_eq $REPLY monorepo-web "part names"
}

# A project of two static parts (on free ports) and one task part, for running.
parts_project() {
  local REPLY; free_port; typeset -g P1=$REPLY P2=$(( REPLY + 50 ))
  mkdir -p $T/shop/{one,two,cli}
  print '{"name": "shop", "workspaces": ["one", "two", "cli"]}' > $T/shop/package.json
  print '<!doctype html>' > $T/shop/one/index.html; print '<!doctype html>' > $T/shop/two/index.html
  print 'print("hello from cli", flush=True)' > $T/shop/cli/main.py; : > $T/shop/cli/requirements.txt
  _axle_run_detect $T/shop >/dev/null 2>&1        # (load the real one)
  functions[_axle_run_detect_orig]=$functions[_axle_run_detect]
  _axle_run_detect() {
    _axle_run_detect_orig "$@" || return 1
    case $1 in
      */one) _axle_run_cmd=($_axle_run_cmd[1] $ROOT/tests/serve.py $P1); _axle_run_port=$P1 ;;
      */two) _axle_run_cmd=($_axle_run_cmd[1] $ROOT/tests/serve.py $P2); _axle_run_port=$P2 ;;
    esac
    return 0
  }
}

test_run_parts_first_run_saves_the_choice() {
  AXLE_MODULES=(run) load_tool
  whence -p python3 >/dev/null || return 0
  parts_project
  rm -rf $T/shop/cli
  cd $T/shop
  local out
  out=$(axle run --yes </dev/null 2>&1) || fail "starts: $out"
  wait_state shop-one up; wait_state shop-two up
  local -a reply; _axle_run_choice_load $T/shop
  assert_eq "${(j: :)reply}" "one two" "no terminal to ask in: all, saved"
  out=$(axle run -n 2>&1)
  assert_contains "$out" "saved choice: one, two"
  axle run stop >/dev/null
  local -a left=($HOME/.local/state/axle/run/services/*(N))
  (( ${#left} )) && fail "stop in the project stops all its parts: $left"
  # A saved part that's gone: said, skipped, the rest runs.
  _axle_run_choice_save $T/shop two gone
  out=$(axle run --yes </dev/null 2>&1)
  assert_contains "$out" "saved part gone has nothing to run any more: skipped"
  wait_state shop-two up
  [[ -e $HOME/.local/state/axle/run/services/shop-one ]] && fail "only the saved parts start"
  axle run stop all >/dev/null
  return 0
}

test_run_failing_part_shows_its_whole_log() {
  AXLE_MODULES=(run) load_tool
  mkdir -p $T/app
  print -l 'web: echo first line; seq 1 40; echo last line; exit 4' > $T/app/Procfile
  cd $T/app
  local out
  local -i rc=0
  out=$(axle run --yes </dev/null 2>&1) || rc=$?
  assert_contains "$out" "exited (code 4)"
  assert_contains "$out" "│ first line" "the whole log, from the first line"
  assert_contains "$out" "│ 20" "the middle"
  assert_contains "$out" "│ last line" "to the last"
  assert_contains "$out" "didn't start: app"
  (( rc )) || fail "a part that fails: an error status"
  return 0
}

test_run_verbose_without_tmux() {
  AXLE_MODULES=(run) load_tool
  whence -p python3 >/dev/null || return 0
  parts_project
  _axle_run_partname x y                          # (load parts.zsh, then replace its check)
  _axle_run_have_tmux() { return 1 }
  cd $T/shop
  local out
  out=$(axle run --yes --verbose 'shop-one, shop-two' </dev/null 2>&1) && fail "two verbose parts, no tmux"
  assert_contains "$out" "too many to show verbosely in one shell (2)"
  local -a left=($HOME/.local/state/axle/run/services/*(N))
  (( ${#left} )) && fail "nothing started: $left"
  # One verbose part: the others start in the background, then it runs here.
  out=$(axle run --yes --verbose cli </dev/null 2>&1) || fail "runs: $out"
  assert_contains "$out" "hello from cli" "the verbose part's output, in this shell"
  wait_state shop-one up; wait_state shop-two up
  axle run stop all >/dev/null
  # --only: just that one.
  out=$(axle run --yes --verbose cli --only </dev/null 2>&1)
  assert_contains "$out" "hello from cli"
  left=($HOME/.local/state/axle/run/services/*(N))
  (( ${#left} )) && fail "--only starts nothing else: $left"
  out=$(axle run --yes --verbose nope </dev/null 2>&1) && fail "an unknown part"
  assert_contains "$out" "no part 'nope' in shop (parts: shop-cli, shop-one, shop-two)"
  return 0
}

test_run_verbose_with_tmux() {
  AXLE_MODULES=(run) load_tool
  whence -p python3 >/dev/null || return 0
  parts_project
  # A stand-in tmux that records what it's asked.
  mkdir -p $T/bin
  print -l '#!/bin/sh' 'case $1 in has-session) exit 1 ;; esac' \
    'printf "%s|" "$@" >> "$TMUX_LOG"; echo >> "$TMUX_LOG"' > $T/bin/tmux
  chmod +x $T/bin/tmux
  path=($T/bin $path); export TMUX_LOG=$T/tmux.log
  cd $T/shop
  local out
  out=$(axle run --yes --verbose shop-one,shop-two --only </dev/null 2>&1) || fail "runs: $out"
  assert_contains "$out" "tmux sessions: shop-one, shop-two"
  local log=$(<$T/tmux.log)
  assert_contains "$log" "new-session|-d|-s|shop-one|-c|$T/shop/one|-e|PORT=$P1|--|" "a session per part, in its folder, with its port"
  assert_contains "$log" "|axle-run|python3|$ROOT/tests/serve.py|$P1|" "the command as words, kept open after it ends"
  assert_contains "$log" "new-session|-d|-s|shop-two|" "the second"
  local -a left=($HOME/.local/state/axle/run/services/*(N))
  (( ${#left} )) && fail "--only: nothing in the background: $left"
  return 0
}

test_run_config_asks_again() {
  zmodload zsh/zpty 2>/dev/null || return 0
  AXLE_MODULES=(run) load_tool
  parts_project
  _axle_run_choice_save $T/shop one two
  print -l "AXLE_MODULES=(run); source $ROOT/axle.plugin.zsh" "cd $T/shop" \
    "_axle_run_partname x y" "_axle_run_have_tmux() { return 1 }" > $T/setup.zsh
  zpty sh "HOME=$HOME XDG_CONFIG_HOME=$XDG_CONFIG_HOME XDG_CACHE_HOME=$XDG_CACHE_HOME XDG_DATA_HOME=$XDG_DATA_HOME HISTFILE=$T/hist TERM=xterm AXLE_UPDATE_CHECK=0 zsh -f -i"
  zpty -w sh "PS1='> '; source $T/setup.zsh; : > $T/ready"
  _wait() { local -i i; local c; for i in {1..150}; do while zpty -rt sh c 2>/dev/null; do :; done; [[ -e $1 ]] && return 0; sleep 0.1; done; fail "no answer ($1)" }
  _wait $T/ready
  # The list: shop-cli, shop-one, shop-two, with one and two ticked. Tick cli, untick one.
  zpty -w sh "axle run --yes --config --only --verbose cli; : > $T/done"
  sleep 1; zpty -n -w sh ' '; sleep 0.2; zpty -n -w sh $'\e[B'; sleep 0.2; zpty -n -w sh ' '; sleep 0.2
  zpty -n -w sh $'\r'
  _wait $T/done
  zpty -w sh 'exit'; zpty -d sh 2>/dev/null
  local -a reply; _axle_run_choice_load $T/shop
  assert_eq "${(j: :)reply}" "cli two" "--config: chosen again, and saved"
}

# What you actually read: `axle run` waits for the server and says where it is, and `ls`
# gives the uptime with its unit.
test_run_says_when_the_server_is_up() {
  AXLE_MODULES=(run) load_tool
  whence -p python3 >/dev/null || return 0
  local REPLY port; free_port; port=$REPLY
  mkdir -p $T/site; print '<!doctype html>' > $T/site/index.html
  _axle_run_detect $T/site >/dev/null 2>&1
  functions[_axle_run_detect_orig]=$functions[_axle_run_detect]
  _axle_run_detect() { _axle_run_detect_orig "$@" || return 1; _axle_run_cmd=($_axle_run_cmd[1] $ROOT/tests/serve.py $port); _axle_run_port=$port }
  cd $T/site
  local out=$(axle run --yes </dev/null 2>&1)
  assert_contains "$out" "site" "names it"
  assert_contains "$out" "running on http://localhost:$port" "and waits until it's up"
  assert_match "$(axle run ls)" "*up*$port*[0-9]s *" "uptime with its unit"
  axle run stop >/dev/null
}

# The real tmux, on the test's own server (TMUX_TMPDIR): the session runs the part in its
# folder with its environment, and stays open with the output after the program ends.
test_run_verbose_with_real_tmux() {
  AXLE_MODULES=(run) load_tool
  whence -p tmux >/dev/null || return 0
  [[ $(command tmux -V) == (#b)*\ ([0-9]##).([0-9]##)* ]] && (( match[1] > 3 || (match[1] == 3 && match[2] >= 2) )) || return 0
  mkdir -p $T/mono/a $T/mono/b
  print '{"workspaces": ["a", "b"]}' > $T/mono/package.json
  print -l 'web: echo "from a in $(basename "$PWD") GREET=$GREET"; exit 3' > $T/mono/a/Procfile
  print 'GREET=hello' > $T/mono/a/.env
  print -l 'web: exit 0' > $T/mono/b/Procfile
  cd $T/mono
  local out; local -i rc=0
  out=$(axle run --yes --verbose mono-a --only </dev/null 2>&1) || rc=$?
  (( rc == 0 )) || fail "started: $out"
  assert_contains "$out" "tmux sessions: mono-a"
  command tmux has-session -t '=mono-a' || fail "the session exists"
  local -i i; local pane=''
  for i in {1..50}; do
    pane=$(command tmux capture-pane -p -t '=mono-a:')
    [[ $pane == *"exited with code"* ]] && break
    sleep 0.1
  done
  command tmux kill-server 2>/dev/null
  assert_contains "$pane" "from a in a GREET=hello" "its folder and .env, still readable after it ended"
  assert_contains "$pane" "exited with code 3" "and how it ended"
}

# In the foreground a project gets the same environment as in the background.
test_run_foreground_gets_env_file_and_port() {
  AXLE_MODULES=(run) load_tool
  mkdir -p $T/fg
  print 'GREET=hello' > $T/fg/.env
  print 'web: echo "GREET=$GREET PORT=$PORT"' > $T/fg/Procfile
  cd $T/fg
  local out=$(axle run --yes --fg </dev/null 2>&1)
  assert_contains "$out" "GREET=hello PORT=" ".env in the foreground"
  [[ $out == *"PORT=5"* ]] || [[ $out == *"PORT="[0-9]* ]] || fail "and its port: $out"
}
