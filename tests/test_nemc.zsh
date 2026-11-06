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
  fail) exit 3 ;;
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
  out=$(nemc scan 2>&1)
  assert_eq "$?" 127 "typed nemc: not found"
  assert_contains "$out" "install.sh --nemc" "typed nemc: says how to get it"
}

test_typing_nemc_goes_through_axle() {
  _fake_nemc
  load_tool; load_theme
  (( $+functions[nemc] )) || fail "nemc is axle's"
  nemc scan ~/x --json
  assert_eq "$(<$T/nemc.log)" "scan $HOME/x --json" "arguments reach nemc untouched"
  : > $T/nemc.log
  nemc
  assert_eq "$(<$T/nemc.log)" "" "no command: nemc's own menu, not status"
  nemc fail
  assert_eq "$?" 3 "nemc's exit code"
  _axle_nemc_age=([$T]=$EPOCHSECONDS [/elsewhere]=$EPOCHSECONDS)
  nemc projects
  assert_eq "${#_axle_nemc_age}" 0 "the prompt reads every folder again"
}

test_nemc_hook_events() {
  _fake_nemc
  load_tool
  started() { print -r -- "start $*" >> $T/hooks }
  finished() { print -r -- "done $*" >> $T/hooks }
  axle hook nemc-start started || fail "nemc-start is an event"
  axle hook nemc-done finished || fail "nemc-done is an event"
  assert_contains "$(axle hook ls)" "nemc-done" "listed"
  nemc fail --json
  assert_eq "$(<$T/hooks)" $'start fail --json\ndone 3 fail --json' "arguments; exit code first when done"
  : > $T/hooks; _answer clean
  axle nemc >/dev/null
  assert_eq "$(<$T/hooks)" $'start status\ndone 0 status' "axle nemc fires them too"
}

test_nemc_off_skips_axle() {
  _fake_nemc
  load_tool
  finished() { print -r -- "done $*" >> $T/hooks }
  axle hook nemc-done finished
  AXLE_NEMC=0
  _axle_nemc_age=([$T]=$EPOCHSECONDS)
  nemc scan .
  assert_eq "$(<$T/nemc.log)" "scan ." "still nemc"
  [[ ! -e $T/hooks ]] || fail "no events"
  assert_eq "${#_axle_nemc_age}" 1 "the prompt isn't touched"
}

test_nemc_without_the_tool() {
  _fake_nemc
  load_theme                                     # Benzene alone: no hooks API
  nemc scan .
  assert_eq "$(<$T/nemc.log)" "scan ." "runs"
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

# A cloned project can ship .venv/bin/nemc; the env module puts that first on PATH when you
# cd in. The prompt (and axle nemc) must never run it.
_planted_project() {
  mkdir -p $T/evil/.venv/bin
  print 'home = /usr/bin' > $T/evil/.venv/pyvenv.cfg
  print -r -- "#!/bin/sh
touch $T/planted-ran" > $T/evil/.venv/bin/nemc
  chmod +x $T/evil/.venv/bin/nemc
}

test_a_projects_own_nemc_is_never_run() {
  _fake_nemc
  load_tool; load_theme
  _planted_project
  _answer changed
  cd $T/evil; _axle_env_sync >/dev/null
  assert_eq "$commands[nemc]" "$T/evil/.venv/bin/nemc" "(the planted one is first on PATH)"
  local REPLY
  _axle_nemc_bin || fail "the installed nemc is found past it"
  assert_eq "$REPLY" "$T/bin/nemc" "the installed one"
  _axle_nemc_take "$(_axle_nemc_worker $PWD)"
  assert_eq "$_axle_nemc_state[$PWD]" "changed:0" "the prompt reads the installed one"
  axle nemc >/dev/null 2>&1
  local said=$(nemc projects 2>&1)
  assert_contains "$said" "not this project's" "typed nemc: says which one it runs"
  assert_eq "${$(<$T/nemc.log)##*$'\n'}" "projects" "typed nemc: the installed one"
  assert_contains "$(axle doctor)" "(compat $AXLE_NEMC_COMPAT)" "doctor asks the installed one"
  [[ ! -e $T/planted-ran ]] || fail "the project's nemc was run"
  # Only the planted one: nothing runs, and axle nemc says why.
  path=($T/evil/.venv/bin /usr/bin /bin); rehash
  _axle_nemc_bin && fail "no trusted nemc: $REPLY"
  _axle_nemc_age=()
  _axle_nemc_precmd
  [[ -z $_axle_nemc_fd ]] || fail "no worker started"
  local out=$(axle nemc 2>&1)
  assert_contains "$out" "came with this project" "axle nemc says why"
  out=$(nemc 2>&1)
  assert_contains "$out" "came with this project" "typed nemc says why"
  assert_contains "$(axle doctor)" "came with this project" "doctor says why"
  [[ ! -e $T/planted-ran ]] || fail "the project's nemc was run"
  # Leaving the project: the installed one again.
  _fake_nemc
  cd $T; _axle_env_sync >/dev/null
  _axle_nemc_bin && assert_eq "$REPLY" "$T/bin/nemc" "outside it" || fail "outside it"
}

test_a_relative_path_entry_is_never_used() {
  mkdir -p $T/here
  print -r -- "#!/bin/sh
touch $T/planted-ran" > $T/here/nemc
  chmod +x $T/here/nemc
  load_theme
  cd $T/here
  path=(. /usr/bin /bin); rehash
  local REPLY
  _axle_nemc_bin && fail "a nemc from '.' isn't used: $REPLY"
  _fake_nemc; path=(. $path); rehash
  _axle_nemc_bin && assert_eq "$REPLY" "$T/bin/nemc" "the one past it" || fail "the one past it"
  _axle_nemc_worker $PWD >/dev/null
  [[ ! -e $T/planted-ran ]] || fail "./nemc was run"
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
  for c in 'git commit -m x' 'git pull'; do
    _axle_nemc_age[$PWD]=$EPOCHSECONDS
    _axle_nemc_preexec "$c"
    assert_eq "$_axle_nemc_age[$PWD]" 0 "$c: this folder"
  done
  for c in 'nemc scan ~/repos' 'command nemc rescan' 'nemc'; do
    _axle_nemc_age=([$PWD]=$EPOCHSECONDS [/elsewhere]=$EPOCHSECONDS)
    _axle_nemc_preexec "$c"
    assert_eq "${#_axle_nemc_age}" 0 "$c: every folder"
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
  alias nemc='nemc --db /tmp/x'
  assert_contains "$(axle doctor)" "skips axle's nemc" "an alias that skips it"
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

# With only these tools on PATH, so a real uv or pipx on this machine can't be found.
_install_only() {
  local d=$1 c; shift
  mkdir -p $T/bin
  for c in git zsh sed ln mkdir rm grep dirname basename uname cat chmod; do
    [[ -e $T/bin/$c ]] || ln -s ${commands[$c]} $T/bin/$c
  done
  (cd $d && PATH=$T/bin ZSH=$T/omz ZSH_CUSTOM=$T/omz/custom $T/bin/zsh -f ./install.sh "$@" --no-configure) 2>&1
}

# zpty's shell answers by writing to a file: _wait_for <file> [lines]
_wait_for() {
  local -i i; local -a l; local chunk
  for i in {1..100}; do
    while zpty -rt sh chunk 2>/dev/null; do :; done
    [[ -e $1 ]] && l=(${(f)"$(<$1)"}) && (( ${#l} >= ${2:-0} )) && return 0
    sleep 0.1
  done
  fail "no answer from the shell ($1)"
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

test_install_uses_pipx_without_uv() {
  _remote_and_clone
  _fake_uv
  mv $T/bin/uv $T/bin/pipx
  _install_only $T/c --nemc --both >/dev/null
  assert_contains "$(<$T/uv.log)" "install git+https://github.com/hottahidit/MnemoCetus" "installed with pipx"
  assert_eq "$(command git -C $T/c symbolic-ref --short HEAD)" MnemoCetus "on the MnemoCetus branch"
}

test_install_without_a_way_to_get_nemc_stays_put() {
  _remote_and_clone
  local out=$(_install_only $T/c --nemc --both)
  assert_contains "$out" "uv or pipx" "says what's needed"
  assert_eq "$(command git -C $T/c symbolic-ref --short HEAD)" main "still on main"
}

test_install_failed_nemc_install_stays_put() {
  _remote_and_clone
  mkdir -p $T/bin
  print -r -- $'#!/bin/sh\nexit 1' > $T/bin/uv; chmod +x $T/bin/uv
  local out=$(_install_only $T/c --nemc --both)
  assert_contains "$out" "wasn't installed" "says so"
  assert_eq "$(command git -C $T/c symbolic-ref --short HEAD)" main "still on main"
}

test_install_in_a_plain_copy_explains() {
  _remote_and_clone
  _fake_uv
  rm -rf $T/c/.git
  local out=$(_install $T/c --nemc --both --keep)
  assert_contains "$out" "isn't a git clone" "explains"
  assert_not_match "$out" "*fatal:*" "no raw git errors"
}

test_install_on_a_detached_head_explains() {
  _remote_and_clone
  _fake_uv
  command git -C $T/c switch -q --detach
  local out=$(_install $T/c --nemc --both)
  assert_contains "$out" "not on a branch" "explains"
  assert_not_match "$out" "*(fatal|error):*" "no raw git errors"
  [[ -z $(command git -C $T/c symbolic-ref --short -q HEAD) ]] || fail "still detached"
}

test_install_when_the_branch_cant_be_fetched_stays_put() {
  _remote_and_clone
  _fake_uv
  command git -C $T/src branch -qD MnemoCetus
  local out=$(_install $T/c --nemc --both)
  assert_contains "$out" "couldn't fetch" "explains"
  assert_eq "$(command git -C $T/c symbolic-ref --short HEAD)" main "still on main"
}

test_install_again_on_the_branch_doesnt_loop() {
  _remote_and_clone
  _fake_uv
  _install $T/c --nemc --both >/dev/null
  local out=$(_install $T/c --nemc --both)
  assert_not_match "$out" "*now on its MnemoCetus*" "already there"
  assert_eq "$(command git -C $T/c symbolic-ref --short HEAD)" MnemoCetus "still on it"
}

test_install_off_the_branch_keeps_nemcs_own_light() {
  _remote_and_clone
  _fake_uv
  print '# edit' >> $T/c/README.md                 # (dirty: it stays on main)
  rm $T/c/lib/nemc.zsh                             # (main has no compat)
  local out=$(_install $T/c --nemc --both)
  assert_contains "$out" 'eval "$(nemc init zsh)"' "keeps nemc's light"
  assert_not_match "$out" "*--no-prompt*" "doesn't turn it off"
}

test_axle_nemc_completion() {
  zmodload zsh/zpty 2>/dev/null || return 0
  zpty sh "HOME=$HOME XDG_CONFIG_HOME=$XDG_CONFIG_HOME XDG_CACHE_HOME=$XDG_CACHE_HOME XDG_DATA_HOME=$XDG_DATA_HOME HISTFILE=$T/hist TERM=xterm AXLE_UPDATE_CHECK=0 zsh -f -i"
  zpty -w sh "PS1='> '; autoload -Uz compinit; compinit -u -D; source $ROOT/axle.plugin.zsh; source $ROOT/benzene.zsh-theme; PS1='> '"
  zpty -w sh "_rec() { print -r -- \"[\$BUFFER]\" >> $T/rec }; zle -N _rec; bindkey '^Xr' _rec"
  zpty -w sh ": > $T/ready"
  _wait_for $T/ready
  print x > $T/afile
  zpty -n -w sh $'axle nem\t'; sleep 0.3; zpty -n -w sh $'\x18r'; _wait_for $T/rec 1
  zpty -n -w sh $'\x15axle nemc secr\t'; sleep 0.3; zpty -n -w sh $'\x18r'; _wait_for $T/rec 2
  zpty -n -w sh $'\x15'"axle nemc scan $T/afi"$'\t'; sleep 0.3; zpty -n -w sh $'\x18r'; _wait_for $T/rec 3
  zpty -w sh $'\x15exit'; zpty -d sh 2>/dev/null
  local -a rec=("${(@f)$(<$T/rec)}")
  assert_eq "$rec[1]" "[axle nemc ]" "the command"
  assert_eq "$rec[2]" "[axle nemc secrets ]" "a subcommand"
  assert_eq "$rec[3]" "[axle nemc scan $T/afile ]" "a path after it"
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

test_install_doesnt_install_twice_when_not_on_path() {
  _remote_and_clone
  mkdir -p $T/bin
  print -r -- $'#!/bin/sh\necho "$*" >> '"$T"$'/uv.log' > $T/bin/uv; chmod +x $T/bin/uv     # (nemc lands off PATH)
  local out=$(_install $T/c --nemc --both)
  local -a calls=("${(@f)$(<$T/uv.log)}")
  assert_eq "${#calls}" 1 "installed once"
  assert_contains "$out" "isn't on PATH yet" "says so"
  assert_eq "$(command git -C $T/c symbolic-ref --short HEAD)" MnemoCetus "on the branch"
}

test_update_with_the_same_version_says_so() {
  _remote_and_clone
  command git -C $T/src switch -q MnemoCetus
  print '# more' >> $T/src/README.md; command git -C $T/src commit -qam compat
  command git -C $T/c fetch -q origin
  command git -C $T/c switch -q --track -c MnemoCetus origin/MnemoCetus
  command git -C $T/c reset -q --hard HEAD~1
  AXLE_UPDATE_CHECK=0 source $T/c/axle.plugin.zsh >/dev/null 2>&1
  rm -rf $XDG_CACHE_HOME/axle
  local out=$(axle update 2>&1)
  assert_contains "$out" "updated (still $AXLE_VERSION)" "no 'x -> x'"
  assert_not_match "$out" "*no such file*" "a fresh cache folder is fine"
}

# --- axle preview and axle configure ----------------------------------------------

test_preview_shows_each_state() {
  load_theme
  local out=$(axle preview nemc-security 2>&1)
  assert_contains "$out" "nemc ● 3" "NoxA: findings"
  assert_contains "$(axle preview nemc-changed 2>&1)" "nemc ●" "NoxA: changed"
  assert_contains "$(axle preview nemc-clean 2>&1)" "nemc ●" "NoxA: clean, expanded"
  assert_contains "$(axle preview --axon nemc-security 2>&1)" "nemc ● 3" "AxoN: findings"
  assert_not_match "$(axle preview --axon nemc-changed 2>&1 | grep -v MnemoCetus)" "*nemc ●*" "AxoN: changed stays quiet"
}

test_preview_state_doesnt_leak_into_other_scenarios() {
  load_theme
  local out=$(axle preview nemc-security nemc-changed 2>&1)
  assert_contains "$out" "nemc ● 3" "shown in its own"
  assert_not_match "${out#*changed since the last scan}" "*nemc ● 3*" "not in the next one"
}

test_preview_works_without_nemc() {
  path=(/usr/bin /bin); rehash
  load_theme
  assert_contains "$(axle preview nemc-security 2>&1)" "nemc ● 3" "it's faked"
}

test_wizard_offers_it_only_with_nemc() {
  path=(/usr/bin /bin); rehash
  load_theme
  source $ROOT/lib/configure.zsh </dev/null >/dev/null 2>&1
  assert_eq "$_cf_nemc" 0 "no nemc: not offered"
  _cf_recount; local -i without=$_cf_total
  _fake_nemc
  source $ROOT/lib/configure.zsh </dev/null >/dev/null 2>&1
  assert_eq "$_cf_nemc" 1 "offered"
  _cf_recount; assert_eq "$_cf_total" $(( without + 1 )) "one more step"
}

test_wizard_offers_it_right_after_install_off_path() {
  path=(/usr/bin /bin); rehash
  load_theme
  AXLE_NEMC_INSTALLED=1
  source $ROOT/lib/configure.zsh </dev/null >/dev/null 2>&1
  assert_eq "$_cf_nemc" 1 "installed a moment ago"
}

test_wizard_not_offered_without_benzene() {
  _fake_nemc
  load_tool
  source $ROOT/lib/configure.zsh </dev/null >/dev/null 2>&1
  assert_eq "$_cf_nemc" 0 "the tool alone has no segment to offer"
}

test_wizard_save_keeps_a_setting_it_didnt_ask() {
  load_theme
  mkdir -p ${AXLE_CONFIG:h}
  print -l 'AXLE_NEMC=0' > $AXLE_CONFIG
  source $ROOT/lib/configure.zsh </dev/null >/dev/null 2>&1
  _cf_theme=1 _cf_tool=0
  _cf=(variant nox nerd 0 palette mocha char '>' transient 1 alarms 1 bubbles 1 clock 1 ai claude)
  _cf_write
  assert_contains "$(<$AXLE_CONFIG)" 'AXLE_NEMC=0' "not asked: kept"
  _cf[nemc]=1
  _cf_write
  assert_contains "$(<$AXLE_CONFIG)" 'AXLE_NEMC=1' "asked: replaced"
  assert_not_match "$(<$AXLE_CONFIG)" "*AXLE_NEMC=0*" "only one"
}

# The real wizard in a terminal: defaults everywhere, except "leave it out" at this step.
test_wizard_step_saves_the_choice() {
  zmodload zsh/zpty 2>/dev/null || return 0
  _fake_nemc
  zpty sh "HOME=$HOME XDG_CONFIG_HOME=$XDG_CONFIG_HOME XDG_CACHE_HOME=$XDG_CACHE_HOME XDG_DATA_HOME=$XDG_DATA_HOME HISTFILE=$T/hist TERM=xterm AXLE_UPDATE_CHECK=0 COLUMNS=100 LINES=50 zsh -f -i"
  zpty -w sh "PS1='> '; source $ROOT/axle.plugin.zsh; source $ROOT/benzene.zsh-theme; PS1='> '; axle configure; : > $T/done"
  local chunk key seen='' ; local -i i asked=0
  for i in {1..150}; do
    sleep 0.2
    chunk=''; while zpty -rt sh chunk 2>/dev/null; do seen+=$chunk; chunk=''; done
    [[ -e $T/done ]] && break
    # One key per screen, once it's fully drawn: "q cancels" is also in the header, so a slow
    # machine would get two keys for one screen, and the rest land on later steps.
    [[ $seen == *("Enter chooses"|"Enter when done"|"[Enter] save")* ]] || continue
    key=$'\r'
    [[ $seen == *"MnemoCetus in the prompt?"* ]] && { asked=1; key=2 }
    seen=''; zpty -n -w sh $key
  done
  zpty -w sh 'exit' 2>/dev/null; zpty -d sh 2>/dev/null
  (( asked )) || fail "the step never appeared; last seen: ${(q+)seen[-400,-1]}"
  [[ -e $T/done ]] || fail "the wizard didn't finish"
  assert_contains "$(<$XDG_CONFIG_HOME/axle/config.zsh)" "AXLE_NEMC=0" "saved"
  assert_contains "$(<$XDG_CONFIG_HOME/axle/config.zsh)" "AXLE_ENV_QUIET=0" "its key landed on this step"
}
