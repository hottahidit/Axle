# Python venvs and toolchain pins.

_mkvenv() {   # _mkvenv <dir> [prompt]
  mkdir -p $1/bin
  { print 'home = /usr/bin'; [[ -n $2 ]] && print "prompt = '$2'" } > $1/pyvenv.cfg
}

test_venv_name_from_pyvenv_prompt() {
  load_theme
  _mkvenv $T/proj/.venv shop-api
  _axle_venv_name $T/proj/.venv; assert_eq $REPLY shop-api "named by its prompt"
  _mkvenv $T/other/.venv
  _axle_venv_name $T/other/.venv; assert_eq $REPLY other "named by its project"
}

test_venv_states() {
  load_theme
  _mkvenv $T/proj/.venv shop-api; mkdir -p $T/proj/src $T/elsewhere
  local -a reply
  cd $T/proj/src; _axle_scan_markers; unset VIRTUAL_ENV
  _axle_venv_state; assert_eq "$reply[1] $reply[2]" "inactive shop-api" "project venv not active"
  VIRTUAL_ENV=$T/proj/.venv
  _axle_venv_state; assert_eq "$reply[1]" ok "active in its own project"
  cd $T/elsewhere; _axle_scan_markers
  _axle_venv_state; assert_eq "$reply[1] $reply[2]" "elsewhere shop-api" "active outside its project"
}

test_home_venv_is_not_a_project_venv() {
  load_theme
  _mkvenv $HOME/.venv; mkdir -p $HOME/code
  cd $HOME/code; _axle_scan_markers
  assert_eq "${_axle_markers[venv]:-none}" none "a venv directly in ~ doesn't count"
}

test_toolchain_pins() {
  load_theme
  mkdir -p $T/p/deep && print 20 > $T/p/.nvmrc && print 22 > $T/p/deep/.nvmrc
  print -l 'nodejs 18.19.0' 'python 3.11.9' > $T/p/.tool-versions
  cd $T/p; _axle_scan_markers; _axle_pin node; assert_eq $REPLY 20 ".nvmrc"
  cd $T/p/deep; _axle_scan_markers; _axle_pin node; assert_eq $REPLY 22 "the nearest pin wins"
  print 'lts/iron' > $T/p/deep/.nvmrc; _axle_pin node; assert_eq "$REPLY" "" "lts/* means unknown: no warning"
  cd $T/p; rm $T/p/.nvmrc; _axle_scan_markers; _axle_pin node; assert_eq $REPLY 18.19.0 ".tool-versions"
  _axle_pin rust; assert_eq "$REPLY" "" "a tool .tool-versions doesn't mention"
  _axle_pin_ok 20 20.11.1 || fail "20 matches 20.11.1"
  _axle_pin_ok 3.12 3.12.3 || fail "3.12 matches 3.12.3"
  ! _axle_pin_ok 20 25.6.0 || fail "20 doesn't match 25.6.0"
  REPLY='' _axle_alarm=0; _axle_lang node 25.6.0 20; plain "$REPLY"
  assert_eq "$REPLY" "node 25.6.0 (wants 20)" "flagged"
  assert_eq $_axle_alarm 2 "as an amber alarm"
}

# `deactivate` in a venv the env module turned on: off until you leave the project.
test_env_deactivate() {
  AXLE_MODULES=(env) load_tool
  _mkvenv $T/proj/.venv; print > $T/proj/requirements.txt; mkdir -p $T/proj/src $T/out
  unset VIRTUAL_ENV
  local out
  cd $T/proj; _axle_env_sync
  assert_eq "$VIRTUAL_ENV" $T/proj/.venv "on when entering"
  (( $+functions[deactivate] )) || fail "deactivate exists"
  out=$(deactivate 2>&1; print "venv=$VIRTUAL_ENV")
  assert_contains "$out" "left the proj venv" "says so"
  deactivate >/dev/null 2>&1
  assert_eq "${VIRTUAL_ENV:-none}" none "off"
  (( ${path[(Ie)$T/proj/.venv/bin]} )) && fail "and its bin/ is off PATH"
  (( $+functions[deactivate] )) && fail "deactivate is gone with it"
  cd $T/proj/src; _axle_env_sync
  assert_eq "${VIRTUAL_ENV:-none}" none "stays off inside the project"
  cd $T/out; _axle_env_sync; cd $T/proj; _axle_env_sync
  assert_eq "$VIRTUAL_ENV" $T/proj/.venv "back on when entering again"
  # A venv's own activate script calls `deactivate nondestructive` first: quietly make way.
  out=$(deactivate nondestructive 2>&1)
  assert_eq "$out" "" "nothing said for activate's call"
}

# `exec zsh` (or a nested shell) in a project: the venv the module turned on is still its own.
test_env_child_shell_keeps_switching() {
  AXLE_MODULES=(env) load_tool
  _mkvenv $T/proj/.venv; print > $T/proj/requirements.txt; mkdir -p $T/out
  unset VIRTUAL_ENV
  cd $T/proj; _axle_env_sync >/dev/null
  local out
  out=$(cd $T/proj && AXLE_MODULES=(env) zsh -fc "source $ROOT/tests/lib.zsh; load_tool
    (( \$+functions[deactivate] )) && print has-deactivate
    cd $T/out; _axle_env_sync; print venv=\${VIRTUAL_ENV:-none}" 2>&1)
  assert_contains "$out" "has-deactivate"
  assert_contains "$out" "left the proj venv"
  assert_contains "$out" "venv=none" "switched off on leaving"
  # One you activated yourself is still left alone.
  out=$(cd $T/proj && AXLE_ENV_AUTO= zsh -fc "source $ROOT/tests/lib.zsh; AXLE_MODULES=(env) load_tool
    cd $T/out; _axle_env_sync; print venv=\$VIRTUAL_ENV" 2>&1)
  assert_contains "$out" "venv=$T/proj/.venv"
}
