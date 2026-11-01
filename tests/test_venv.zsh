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
