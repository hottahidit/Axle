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
