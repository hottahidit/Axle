# Text from outside (history, files, status pages) must never be executed.

test_history_text_is_never_run() {
  setopt prompt_subst
  load_tool
  mkdir -p ${_axle_hist_file:h}
  printf '%s\t0\t0.10\t/tmp\t\techo $(touch %s/ran)\n' $EPOCHSECONDS $T > $_axle_hist_file
  _axle_cmd_history 5 >/dev/null
  _axle_cmd_stats >/dev/null
  [[ ! -e $T/ran ]] || fail "a recorded command was executed by axle history/stats"
}

test_venv_names_are_never_run() {
  setopt prompt_subst
  load_tool; load_theme
  mkdir -p $T/evil/.venv/bin
  print -l 'home = /usr/bin' "prompt = '\$(touch $T/ran)'" > $T/evil/.venv/pyvenv.cfg
  cd $T/evil; _axle_env_sync >/dev/null; _axle_scan_markers; _axle_render
  cd $T; _axle_env_sync >/dev/null
  [[ ! -e $T/ran ]] || fail "a venv's name was executed"
}

test_drop_text_is_never_run() {
  setopt prompt_subst
  load_theme
  $ROOT/tools/axle-drop evil "\$(touch $T/ran) \`touch $T/ran2\`"
  _axle_render
  print -rn -- "${(%)${(e)PROMPT}}" >/dev/null 2>&1      # what drawing the prompt does
  [[ ! -e $T/ran && ! -e $T/ran2 ]] || fail "drop text was executed"
}
