# The axle command: help, typos, config, completion, prompts, update check, uninstall.

test_typos_suggest_the_command() {
  load_tool; load_theme
  local out=$(axle statz 2>&1)
  assert_contains "$out" "did you mean: axle stats?" "a typo"
  out=$(axle colr 2>&1); assert_contains "$out" "axle colors" "a missing letter"
  out=$(axle zzzz 2>&1); assert_contains "$out" "axle help lists them" "nothing close"
  axle zzzz 2>/dev/null && fail "an unknown command fails"
  return 0
}

test_help_for_one_command() {
  load_tool; load_theme
  local out=$(axle help stats)
  assert_contains "$out" "axle stats --days 7" "examples"
  assert_eq "$(axle stats --help)" "$out" "--help shows the same page"
  assert_contains "$(axle help)" "axle help <command>" "the overview points to it"
}

test_config_set_get_unset() {
  load_tool; load_theme
  axle config set AXLE_PALETTE classic >/dev/null
  assert_eq "$AXLE_PALETTE" classic "applied now"
  assert_contains "$(<$AXLE_CONFIG)" "AXLE_PALETTE=classic" "saved"
  axle config set AXLE_PALETTE blue 2>/dev/null && fail "a value that isn't a choice is refused"
  axle config set AXLE_CLOCK maybe 2>/dev/null && fail "a bool must be 0 or 1"
  axle config set AXLE_MODULES suggest jump >/dev/null
  assert_contains "$(<$AXLE_CONFIG)" "AXLE_MODULES=(suggest jump)" "a list"
  assert_contains "$(axle config get AXLE_PALETTE)" "default: mocha" "get shows the default"
  axle config unset AXLE_PALETTE >/dev/null
  assert_not_match "$(<$AXLE_CONFIG)" "*AXLE_PALETTE*" "unset removes it"
  assert_contains "$(<$AXLE_CONFIG)" "AXLE_MODULES=(suggest jump)" "and keeps the rest"
}

test_config_values_stay_data() {
  load_tool
  axle config set AXLE_SUGGEST_IGNORE "x\$(touch $T/ran)\`touch $T/ran2\`" >/dev/null
  zsh -fc "source $AXLE_CONFIG"
  [[ ! -e $T/ran && ! -e $T/ran2 ]] || fail "a saved value was run when the config was read"
  source $AXLE_CONFIG
  assert_eq "$AXLE_SUGGEST_IGNORE" "x\$(touch $T/ran)\`touch $T/ran2\`" "read back exactly"
}

# A real interactive zsh in a pty, for completion and the arrow-key prompts.
_pty_start() {
  zmodload zsh/zpty 2>/dev/null || return 1
  zpty sh "HOME=$HOME XDG_CONFIG_HOME=$XDG_CONFIG_HOME XDG_CACHE_HOME=$XDG_CACHE_HOME XDG_DATA_HOME=$XDG_DATA_HOME HISTFILE=$T/hist TERM=xterm AXLE_UPDATE_CHECK=0 zsh -f -i"
  zpty -w sh "PS1='> '; autoload -Uz compinit; compinit -u -D; source $ROOT/axle.plugin.zsh; source $ROOT/benzene.zsh-theme; PS1='> '"
  zpty -w sh "_rec() { print -r -- \"[\$BUFFER]\" >> $T/rec }; zle -N _rec; bindkey '^Xr' _rec"
  zpty -w sh ": > $T/ready"
  _pty_wait_file $T/ready
}
_pty_drain() { local chunk; while zpty -rt sh chunk 2>/dev/null; do :; done }
_pty_wait_file() {   # <file> [lines]
  local -i i; local -a l
  for i in {1..100}; do
    _pty_drain
    [[ -e $1 ]] && l=(${(f)"$(<$1)"}) && (( ${#l} >= ${2:-0} )) && return 0
    sleep 0.1
  done
  fail "no answer from the shell ($1)"
}

test_tab_completion() {
  _pty_start || return 0
  zpty -n -w sh $'axle varia\t'; sleep 0.3; zpty -n -w sh $'\x18r'; _pty_wait_file $T/rec 1
  zpty -n -w sh $'\x15axle variant a\t'; sleep 0.3; zpty -n -w sh $'\x18r'; _pty_wait_file $T/rec 2
  zpty -n -w sh $'\x15axle config set AXLE_PALET\t'; sleep 0.3; zpty -n -w sh $'\x18r'; _pty_wait_file $T/rec 3
  zpty -n -w sh $'\x15axle config set AXLE_PALETTE cl\t'; sleep 0.3; zpty -n -w sh $'\x18r'; _pty_wait_file $T/rec 4
  zpty -w sh $'\x15exit'; zpty -d sh 2>/dev/null
  local -a rec=("${(@f)$(<$T/rec)}")
  assert_eq "$rec[1]" "[axle variant ]" "a command"
  assert_eq "$rec[2]" "[axle variant axon ]" "its argument"
  assert_eq "$rec[3]" "[axle config set AXLE_PALETTE ]" "a setting"
  assert_eq "$rec[4]" "[axle config set AXLE_PALETTE classic ]" "one of its values"
}

test_arrow_key_prompts() {
  _pty_start || return 0
  local cfg=$XDG_CONFIG_HOME/axle/config.zsh
  # Pick a value from a menu: ↓ then Enter (mocha → classic).
  zpty -w sh "axle config set AXLE_PALETTE; : > $T/done1"
  sleep 0.5; zpty -n -w sh $'\e[B'; sleep 0.2; zpty -n -w sh $'\r'
  _pty_wait_file $T/done1
  assert_contains "$(<$cfg)" "AXLE_PALETTE=classic" "chosen with the arrow keys"
  # Esc cancels without saving.
  zpty -w sh "axle config set AXLE_VARIANT; : > $T/done2"
  sleep 0.5; zpty -n -w sh $'\e'; _pty_wait_file $T/done2
  assert_not_match "$(<$cfg)" "*AXLE_VARIANT*" "Esc saves nothing"
  # So does Ctrl-C, at once (it once only printed ✗ and kept waiting).
  zpty -w sh "axle config set AXLE_VARIANT; : > $T/done3"
  local seen='' chunk; local -i i
  for i in {1..100}; do                          # (a Ctrl-C before the question would
    while zpty -rt sh chunk 2>/dev/null; do seen+=$chunk; done   # cancel the whole line)
    [[ $seen == *Esc\ cancel* ]] && break
    sleep 0.1
  done
  zpty -n -w sh $'\x03'; _pty_wait_file $T/done3
  assert_not_match "$(<$cfg)" "*AXLE_VARIANT*" "Ctrl-C saves nothing"
  zpty -w sh 'exit'; zpty -d sh 2>/dev/null
}

test_uninstall_removes_only_ours() {
  load_tool
  local custom=$T/omz/custom
  mkdir -p $custom/plugins $custom/themes $HOME/.cache/axle $HOME/.local/share/axle
  ln -s $ROOT $custom/plugins/axle
  ln -s $ROOT/benzene.zsh-theme $custom/themes/benzene.zsh-theme
  ln -s /elsewhere $custom/themes/axle.zsh-theme                     # not ours
  touch $custom/themes/mine.zsh-theme
  print 'plugins=(git axle)' > $HOME/.zshrc
  local out=$(ZSH_CUSTOM=$custom axle uninstall --yes 2>&1)
  [[ ! -e $custom/plugins/axle && ! -L $custom/themes/benzene.zsh-theme ]] || fail "our links removed"
  [[ -L $custom/themes/axle.zsh-theme && -e $custom/themes/mine.zsh-theme ]] || fail "others kept"
  [[ ! -d $HOME/.cache/axle && -d $HOME/.local/share/axle ]] || fail "--yes: cache only"
  assert_contains "$out" "1:plugins=(git axle)" "shows the ~/.zshrc lines to remove"
  assert_eq "$(<$HOME/.zshrc)" 'plugins=(git axle)' "~/.zshrc untouched"
}

test_update_check_reads_the_changelog() {
  # A copy of Axle tracking a "remote" that has a newer version.
  local up=$T/up.git work=$T/up-work copy=$T/copy
  git init -q --bare $up
  git clone -q $up $work 2>/dev/null
  cp -R $ROOT/lib $ROOT/axle.plugin.zsh $ROOT/core $ROOT/modules $work/
  print -l '# Changelog' '' "## $(zsh -fc "source $ROOT/lib/command.zsh 2>/dev/null; print \$AXLE_VERSION" 2>/dev/null)" '- old' > $work/CHANGELOG.md
  ( cd $work && git add -A && git -c user.name=t -c user.email=t@t commit -qm one && git push -q origin HEAD 2>/dev/null )
  git clone -q $up $copy 2>/dev/null
  ( cd $work && sed -i.bak 's/^typeset -g  AXLE_VERSION=.*/typeset -g  AXLE_VERSION=9.9.9/' lib/command.zsh &&
    print -l '# Changelog' '' '## 9.9.9' '- shiny new thing' '' "$(sed -n '3,$p' CHANGELOG.md)" > CHANGELOG.md.new &&
    mv CHANGELOG.md.new CHANGELOG.md && git add -A && git -c user.name=t -c user.email=t@t commit -qm two &&
    git push -q origin HEAD 2>/dev/null )
  source $copy/axle.plugin.zsh >/dev/null 2>&1
  local out=$(axle update --check 2>&1)
  assert_contains "$out" "axle 9.9.9 is out" "the new version"
  assert_contains "$out" "shiny new thing" "what changed"
  assert_not_match "$out" "*- old*" "only what's new"
}
