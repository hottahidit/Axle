# The Benzene prompt: segments, alarms, layout.

_setup() {
  load_theme
  _axle_read_mem() { _axle_mem_used=40 }
  _axle_mem_used=40 _axle_detail=0
  cd $T
}

test_exec_shows_time_and_code() {
  _setup
  local out=''
  _axle_last_status=(0) _axle_elapsed=0.4;  REPLY=''; _axle_seg_exec; plain "$REPLY"; out+="[$REPLY]"
  _axle_last_status=(0) _axle_elapsed=2.21; REPLY=''; _axle_seg_exec; plain "$REPLY"; out+="[$REPLY]"
  _axle_last_status=(1) _axle_elapsed=0.03; REPLY=''; _axle_seg_exec; plain "$REPLY"; out+="[$REPLY]"
  _axle_last_status=(0 1 0) _axle_elapsed=1.2; REPLY=''; _axle_seg_exec; plain "$REPLY"; out+="[$REPLY]"
  assert_eq "$out" "[][2.21s][0.03s[1]][1.20s[0|1|0]]"
}

test_failure_is_a_red_alarm() {
  _setup
  _axle_last_status=(1) _axle_elapsed=0.1
  _axle_join 5 100 exec
  assert_contains "$REPLY" '%K{#f38ba8}' "red bubble background"
}

test_root_is_an_amber_alarm() {
  _setup
  _axle_uid=0
  _axle_join 5 100 context
  assert_contains "$REPLY" '%K{#fab387}' "amber bubble background"
}

test_production_contexts_alarm() {
  _setup
  AWS_PROFILE=staging; REPLY='' _axle_alarm=0; _axle_seg_aws
  assert_eq $_axle_alarm 0 "staging isn't production"
  AWS_PROFILE=Production; REPLY='' _axle_alarm=0; _axle_seg_aws
  assert_eq $_axle_alarm 1 "Production is (any case)"
}

test_top_line_fills_width_exactly() {
  _setup
  cd ~                                     # a short path, so everything can fit
  COLUMNS=100 _axle_detail=1 _axle_last_status=(1) _axle_elapsed=3
  _axle_render
  local top=${_axle_ps1%%$'\n'*}
  plain "$top"
  # The no-wrap guard escapes are zero-width; the visible line is COLUMNS - 1 wide.
  assert_eq ${(m)#REPLY} 99 "visible width of the expanded top line"
}

# Another tool's text before Benzene in PROMPT (nemc's light, conda's "(base) ") is
# counted, so the right side still ends at the edge instead of being cut off.
test_top_line_counts_text_before_it() {
  _setup
  cd ~
  typeset -g LIGHT='%F{yellow}●%f ' X=0
  PROMPT='${LIGHT}(base) '$PROMPT
  COLUMNS=100 _axle_detail=1 _axle_last_status=(1) _axle_elapsed=3
  _axle_render
  plain "$_axle_ps1"
  local top=${REPLY%%$'\n'*}
  assert_eq ${(m)#top} 90 "visible width after the 9 columns before it"
  local bottom=${REPLY#*$'\n'}
  assert_eq "${bottom[1,10]}" "         ╰" "the bottom line moves over, so ╰─ is under ╭─"
  # Nothing in the text before runs while measuring it.
  PROMPT='$(( X = 1 ))'$PROMPT
  _axle_render
  assert_eq $X 0 "the text before wasn't run"
}

test_axon_layout() {
  AXLE_VARIANT=axon load_theme
  _axle_read_mem() { _axle_mem_used=40 }
  mkrepo $T/repo && cd $T/repo && print x > f
  _axle_scan_markers; _axle_seg[git]=$(_axle_git_compute); _axle_git_pwd=$PWD
  _axle_last_status=(1) _axle_elapsed=0.1
  _axle_render
  plain "$_axle_ps1"
  assert_eq "$REPLY" "repo(main)* ✗1 \$ "
}

test_compact_past_line_has_time_and_folder() {
  _setup
  _axle_compact_line
  plain "$REPLY"
  assert_match "$REPLY" '[0-9][0-9]:[0-9][0-9]:[0-9][0-9] *' "starts with the time"
}
