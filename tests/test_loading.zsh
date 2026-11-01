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
