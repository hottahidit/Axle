# Loading each part alone and together, and the config file.

test_theme_alone() {
  load_theme
  assert_eq "${_axle_theme_loaded:-0}${_axle_tool_loaded:-0}" 10 "theme loaded, tool not"
  local help=$(axle help)
  assert_match "$help" '*Benzene, the prompt*' "theme commands listed"
  assert_not_match "$help" '*axle, the tool*' "no tool commands"
  assert_match "$help" '*More with the axle tool*' "points to the tool"
}

test_tool_alone() {
  load_tool
  assert_eq "${_axle_theme_loaded:-0}${_axle_tool_loaded:-0}" 01 "tool loaded, theme not"
  assert_eq "$precmd_functions" _axt_precmd "only the tool's hook"
  assert_not_match "$(axle help)" '*Benzene*' "no theme commands"
}

test_both_and_hook_order() {
  load_tool; load_theme
  assert_eq "${precmd_functions[1,2]}" "_axt_precmd _axle_precmd" "tool hooks run first"
  axle variant axon >/dev/null
  assert_eq "${precmd_functions[1]}" _axt_precmd "a variant switch keeps the tool's hooks"
  (( ${_axle_hook_command_done[(Ie)_axle_sg_cmd_done]} )) || fail "suggest still learns"
}

test_old_name_loads_both() {
  source $ROOT/axle.zsh-theme >/dev/null 2>&1
  assert_eq "${_axle_theme_loaded:-0}${_axle_tool_loaded:-0}" 11
}

test_config_save_keeps_other_settings() {
  load_theme
  mkdir -p ${AXLE_CONFIG:h}
  print -l '# axle' 'AXLE_MODULES=(suggest jump)' 'AXLE_DROP_MAX=4   # mine' > $AXLE_CONFIG
  source $ROOT/lib/configure.zsh </dev/null >/dev/null 2>&1      # defines; stops (no terminal)
  _cf_theme=1 _cf_tool=0
  _cf=(variant axon nerd 1 palette mocha char '$' transient 1 slow 30)
  _cf_write
  local cfg=$(<$AXLE_CONFIG)
  assert_contains "$cfg" 'AXLE_MODULES=(suggest jump)' "tool settings kept"
  assert_contains "$cfg" 'AXLE_DROP_MAX=4   # mine' "hand edits kept"
  assert_contains "$cfg" '# axle' "the other part's section label kept"
  assert_contains "$cfg" 'AXLE_VARIANT=axon' "theme settings written"
  assert_contains "$cfg" 'AXLE_AXON_SLOW=30' "the variant's own setting written"
}

test_rarely_used_parts_load_on_first_use() {
  load_tool; load_theme
  (( ! ${+_axle_settings} && ! ${+_axle_cmd_help} )) || fail "settings and help pages not read at startup"
  [[ $functions[_axle_cmd_stats] == *_axle_lazy_load* ]] || fail "stats not loaded yet"
  assert_contains "$(axle help stats)" "--days 7" "help loads when asked"
  axle config get AXLE_PALETTE >/dev/null || fail "config loads when asked"
  (( ${+_axle_settings} )) || fail "and stays loaded"
}

test_lib_command_loads_once() {
  load_tool
  functions[_axle_cmd_version]='print marked'
  load_theme
  assert_eq "$(axle version)" marked "the theme doesn't re-read lib/command.zsh"
  axle reload >/dev/null 2>&1
  (( ${+_axle_cmd_fn[stats]} && ${+_axle_cmd_fn[variant]} )) || fail "reload re-reads everything"
}

test_compiles_to_bytecode() {
  local copy=$T/axle; mkdir -p $copy
  cp -R $ROOT/{axle.plugin.zsh,benzene.zsh-theme,axle.zsh-theme,lib,core,modules,benzene} $copy/
  rm -f $copy/**/*.zwc(N) $copy/*.zwc(N)
  touch $copy/modules/gone.zsh.zwc                                  # its source was removed
  zsh -fc "AXLE_ROOT=$copy; source $copy/lib/command.zsh; _axle_compile"
  [[ $copy/lib/command.zsh.zwc -nt $copy/lib/command.zsh && -f $copy/benzene/nox.zsh.zwc ]] || fail "compiled"
  [[ ! -e $copy/modules/gone.zsh.zwc ]] || fail "orphaned bytecode removed"
  assert_eq "$(<$copy/.zwc-version)" "$ZSH_VERSION" "records the zsh version"
  print 4.0 > $copy/.zwc-version
  local before=$(zstat +mtime $copy/lib/command.zsh.zwc 2>/dev/null || stat -c %Y $copy/lib/command.zsh.zwc)
  sleep 1.1
  zsh -fc "zmodload zsh/stat; AXLE_ROOT=$copy; source $copy/lib/command.zsh; _axle_compile"
  [[ $(<$copy/.zwc-version) == $ZSH_VERSION ]] || fail "another zsh version's bytecode is redone"
  out=$(cd $copy && HOME=$HOME zsh -fc 'source ./axle.plugin.zsh; source ./benzene.zsh-theme; axle version' 2>&1)
  assert_contains "$out" "the axle tool + Benzene" "loads from bytecode"
}

# A shell started before lazy loading existed reloads into this version: it has the command
# table but no _axle_lazy, and its reload doesn't set _axle_reloading.
test_reload_from_a_version_before_lazy_loading() {
  typeset -gA _axle_cmd_fn=(old old)
  axle_command() { _axle_cmd_fn[$1]=$2 }
  local out=$(source $ROOT/axle.plugin.zsh 2>&1; (( $+functions[_axle_lazy] )) && print lazy-ok; _axle_env_find; print done)
  assert_contains "$out" "lazy-ok" "the new code loads over the old"
  assert_not_match "$out" "*command not found*" "with nothing missing"
}
