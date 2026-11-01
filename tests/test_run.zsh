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
