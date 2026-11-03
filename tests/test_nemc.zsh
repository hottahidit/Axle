# The compat with MnemoCetus: axle nemc, the segment, the stand-down, the installer.

# A fake nemc on PATH that logs its arguments and answers `status --json` with $T/answer.
_fake_nemc() {
  mkdir -p $T/bin
  cat > $T/bin/nemc <<EOF
#!/bin/sh
echo "\$*" >> $T/nemc.log
case "\$1" in
  --version) echo "MnemoCetus ${1:-1.0.0}" ;;
  status) cat $T/answer 2>/dev/null ;;
esac
EOF
  chmod +x $T/bin/nemc
  path=($T/bin $path)
  rehash
}

_answer() { print -r -- "{\n  \"state\": \"$1\",\n  \"findings\": ${2:-0}\n}" > $T/answer }

test_axle_nemc_passes_through() {
  _fake_nemc
  load_tool
  axle nemc scan ~/x --json
  assert_eq "$(<$T/nemc.log)" "scan $HOME/x --json" "arguments reach nemc"
  : > $T/nemc.log
  axle nemc
  assert_eq "$(<$T/nemc.log)" "status" "no command: status"
}

test_axle_nemc_without_nemc_says_how() {
  path=(/usr/bin /bin); rehash
  load_tool
  local out=$(axle nemc scan 2>&1)
  assert_contains "$out" "install.sh --nemc" "says how to get it"
}

test_worker_reads_the_state() {
  _fake_nemc
  load_theme
  _answer security 3
  _axle_nemc_take "$(_axle_nemc_worker $T)"
  assert_eq "$_axle_nemc_state[$T]" "security:3" "state and findings"
  assert_contains "$(<$T/nemc.log)" "status --json --budget 1 $T" "a bounded check of that folder"
  print 'not json' > $T/answer
  _axle_nemc_take "$(_axle_nemc_worker $T)"
  assert_eq "$_axle_nemc_state[$T]" ":0" "garbage: no state, no error"
}

test_segment_per_state() {
  load_theme
  cd $T
  _axle_nemc_state[$PWD]=security:3
  _axle_alarm=0; _axle_nemc_seg
  plain "$REPLY"; assert_eq "$REPLY" "nemc ● 3" "security shows the count"
  assert_eq "$_axle_alarm" 1 "security is an alarm"
  _axle_nemc_state[$PWD]=changed:0
  _axle_alarm=0; _axle_nemc_seg
  plain "$REPLY"; assert_eq "$REPLY" "nemc ●" "changed shows"
  assert_eq "$_axle_alarm" 0 "changed is not an alarm"
  _axle_nemc_state[$PWD]=clean:0
  _axle_detail=0; _axle_nemc_seg; assert_eq "$REPLY" "" "clean is quiet"
  _axle_detail=1; _axle_nemc_seg; plain "$REPLY"; assert_eq "$REPLY" "nemc ●" "clean shows when expanded"
  _axle_nemc_state[$PWD]=unscanned:0
  _axle_nemc_seg; assert_eq "$REPLY" "" "unscanned shows nothing"
  _axle_nemc_state[$PWD]=security:3 AXLE_NEMC=0
  _axle_nemc_seg; assert_eq "$REPLY" "" "AXLE_NEMC=0 shows nothing"
}

test_segment_survives_a_variant_switch() {
  load_theme
  (( ${AXLE_NOX_RIGHT[(Ie)nemc]} )) || fail "registered in NoxA"
  axle variant axon
  (( $+functions[_axle_axon_nemc] )) || fail "registered in AxoN"
  (( ${precmd_functions[(Ie)_axle_nemc_precmd]} )) || fail "hook still there"
  cd $T; _axle_nemc_state[$PWD]=changed:0
  _axle_alarm=0; _axle_axon_nemc; assert_eq "$REPLY" "" "AxoN: changed stays quiet"
  _axle_nemc_state[$PWD]=security:1
  _axle_alarm=0; _axle_axon_nemc; [[ -n $REPLY ]] || fail "AxoN: security shows"
}

test_nemc_light_stands_down() {
  _fake_nemc
  load_theme
  cd $T
  _axle_nemc_age[$PWD]=$EPOCHSECONDS             # (no worker in this test)
  __nemc_precmd() { : }
  add-zsh-hook precmd __nemc_precmd
  local before=$PROMPT
  PROMPT='${__NEMC_LIGHT}'"$PROMPT"
  _axle_nemc_precmd
  (( ! ${precmd_functions[(Ie)__nemc_precmd]} )) || fail "its hook is gone"
  assert_eq "$PROMPT" "$before" "its light is out of the prompt"
}

test_nemc_light_stays_when_off_or_absent() {
  load_theme
  __nemc_precmd() { : }
  add-zsh-hook precmd __nemc_precmd
  path=(/usr/bin /bin); rehash
  _axle_nemc_precmd
  (( ${precmd_functions[(Ie)__nemc_precmd]} )) || fail "without nemc: left alone"
  _fake_nemc
  AXLE_NEMC=0 _axle_nemc_precmd
  (( ${precmd_functions[(Ie)__nemc_precmd]} )) || fail "AXLE_NEMC=0: left alone"
}

test_commands_that_change_it_read_it_again() {
  load_theme
  cd $T
  _axle_nemc_age[$PWD]=$EPOCHSECONDS
  _axle_nemc_preexec 'ls -la'
  assert_eq "$_axle_nemc_age[$PWD]" "$EPOCHSECONDS" "ls changes nothing"
  local c
  for c in 'git commit -m x' 'nemc scan .' 'axle nemc rescan' 'git pull'; do
    _axle_nemc_age[$PWD]=$EPOCHSECONDS
    _axle_nemc_preexec "$c"
    assert_eq "$_axle_nemc_age[$PWD]" 0 "$c"
  done
  _axle_nemc_age[$PWD]=$EPOCHSECONDS
  _axle_nemc_preexec 'nemcfoo'
  assert_eq "$_axle_nemc_age[$PWD]" "$EPOCHSECONDS" "only the command itself"
}

test_doctor_reports_it() {
  load_tool; load_theme
  path=(/usr/bin /bin); rehash
  assert_contains "$(axle doctor)" "MnemoCetus not found" "missing"
  _fake_nemc
  assert_contains "$(axle doctor)" "(compat $AXLE_NEMC_COMPAT)" "found"
}

# --- install.sh --------------------------------------------------------------------

# A remote with main + nemc, and a clone of it on main.
_remote_and_clone() {
  mkdir -p $T/src $T/omz/custom
  (cd $ROOT && command git ls-files -co --exclude-standard) | while read -r f; do
    [[ -e $ROOT/$f ]] || continue
    mkdir -p $T/src/${f:h}; cp -p $ROOT/$f $T/src/$f
  done
  (cd $T/src && command git init -q -b main && command git add -A && command git commit -qm axle &&
    command git branch MnemoCetus)
  command git clone -q $T/src $T/c
}

_fake_uv() {
  mkdir -p $T/bin
  print -r -- $'#!/bin/sh\necho "$*" >> '"$T"$'/uv.log\nprintf \'#!/bin/sh\\n\' > '"$T"$'/bin/nemc\nchmod +x '"$T"$'/bin/nemc' > $T/bin/uv
  chmod +x $T/bin/uv
}

_install() {
  local d=$1; shift
  (cd $d && PATH=$T/bin:/usr/bin:/bin ZSH=$T/omz ZSH_CUSTOM=$T/omz/custom zsh -f ./install.sh "$@" --no-configure) 2>&1
}

test_install_nemc_installs_it_and_switches_branch() {
  _remote_and_clone
  _fake_uv
  local out=$(_install $T/c --nemc --both)
  assert_contains "$(<$T/uv.log)" "tool install git+https://github.com/hottahidit/MnemoCetus" "installed with uv"
  assert_eq "$(command git -C $T/c symbolic-ref --short HEAD)" MnemoCetus "on the MnemoCetus branch"
  assert_eq "$(command git -C $T/c rev-parse --abbrev-ref '@{u}')" origin/MnemoCetus "axle update follows it"
  assert_contains "$out" 'nemc init zsh --no-prompt' "with Benzene: only completion from nemc"
}

test_install_without_a_way_to_get_nemc_stays_put() {
  _remote_and_clone
  mkdir -p $T/bin
  local out=$(PATH=/usr/bin:/bin _install $T/c --nemc --both)
  [[ -x /usr/bin/uv || -x /usr/bin/pipx ]] && return 0     # (this machine has one)
  assert_contains "$out" "uv or pipx" "says what's needed"
  assert_eq "$(command git -C $T/c symbolic-ref --short HEAD)" main "still on main"
}

test_install_nemc_refuses_a_dirty_checkout() {
  _remote_and_clone
  _fake_uv
  print '# edit' >> $T/c/README.md
  local out=$(_install $T/c --nemc --both)
  assert_contains "$out" "uncommitted" "explains"
  assert_eq "$(command git -C $T/c symbolic-ref --short HEAD)" main "still on main"
}

test_install_no_nemc_touches_nothing() {
  _remote_and_clone
  _fake_uv
  _install $T/c --no-nemc --both >/dev/null
  [[ ! -e $T/uv.log ]] || fail "nothing installed"
  assert_eq "$(command git -C $T/c symbolic-ref --short HEAD)" main "still on main"
}
