# Shared helpers: formatting, widths, safe printing.

test_duration_format() {
  source $ROOT/lib/common.zsh
  local d out=''
  for d in 0.03 2.21 32.4 75 3725 90000; do _axle_fmt_duration $d; out+="$REPLY "; done
  assert_eq "$out" "0.03s 2.21s 32s 1m15s 1h02m 1d01h " "durations"
}

test_printp_never_runs_substitutions() {
  source $ROOT/lib/common.zsh
  setopt prompt_subst                           # as oh-my-zsh sets it
  local out=$(_axle_printp "x \$(touch $T/ran) \`touch $T/ran2\` %F{red}y%f")
  [[ ! -e $T/ran && ! -e $T/ran2 ]] || fail "text was executed"
  assert_contains "$out" '$(touch' "the \$(…) text stays literal"
}

test_width_counts_clock_seconds() {
  # Regression: %S inside a time format was taken for a style code (wrapped the line).
  load_theme
  _axle_width "%F{#7f849c}12:44:38%f"
  assert_eq $REPLY 8 "clock width"
  _axle_width "%B%F{#a6e3a1}main%f%b %F{red}!1%f"
  assert_eq $REPLY 7 "styled text width"
}

test_width_counts_wide_icons() {
  load_theme
  _axle_icon_extra=1
  _axle_width $' main'
  assert_eq $REPLY 7 "a 2-column icon plus ' main'"
}
