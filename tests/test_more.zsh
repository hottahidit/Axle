# The extra segments (benzene/more.zsh): languages, cloud, direnv, time/tasks, markers.

_seg() { REPLY='' _axle_alarm=0; _axle_seg_$1; plain "$REPLY" }
_exe() { mkdir -p ${1:h}; print -l '#!/bin/sh' "$2" > $1; chmod +x $1 }

test_languages_with_version_managers() {
  load_theme
  _exe $HOME/.rbenv/shims/ruby 'echo ruby 0'
  _exe $HOME/.asdf/shims/php 'echo x'
  _exe $T/bin/java 'echo "openjdk version \"21.0.2\"" >&2'
  path=($HOME/.rbenv/shims $HOME/.asdf/shims $T/bin $path); rehash
  mkdir -p $HOME/.rbenv/versions/3.3.0 $HOME/.asdf/installs/php/8.3.1 $T/rb $T/rb2 $T/ph $T/jv
  print 3.3.0 > $T/rb/.ruby-version; print 3.4.1 > $T/rb2/.ruby-version
  print 'php 8.3.1' > $T/ph/.tool-versions; touch $T/ph/composer.json
  print 17 > $T/jv/.java-version; touch $T/jv/pom.xml
  cd $T/rb;  _axle_scan_markers; _seg ruby; assert_eq "$REPLY" "rb 3.3.0" "rbenv's version"
  cd $T/rb2; _axle_scan_markers; _seg ruby; assert_eq "$REPLY" "rb 3.4.1 (not installed)" "pinned, not installed"
  assert_eq $_axle_alarm 2 "amber"
  cd $T/ph;  _axle_scan_markers; _seg php;  assert_eq "$REPLY" "php 8.3.1" "asdf, from .tool-versions"
  cd $T/jv;  _axle_scan_markers; _seg java; assert_eq "$REPLY" "java 21.0.2 (wants 17)" "a mismatch"
  cd $T; _axle_scan_markers; _seg ruby; assert_eq "$REPLY" "" "not a Ruby project"
}

test_build_files_and_snapshots() {
  load_theme
  mkdir -p $T/sc $T/hs $T/fl $T/eb/.elasticbeanstalk $HOME/fvm/versions/3.19.0
  print 'scalaVersion := "3.3.1"' > $T/sc/build.sbt
  print 'resolver: lts-22.7' > $T/hs/stack.yaml
  print '{"flutter": "3.19.0"}' > $T/fl/.fvmrc
  print -l 'branch-defaults:' '  main:' '    environment: shop-prod' > $T/eb/.elasticbeanstalk/config.yml
  cd $T/sc; _axle_scan_markers; _seg scala;   assert_eq "$REPLY" "scala 3.3.1" "build.sbt"
  cd $T/hs; _axle_scan_markers; _seg haskell; assert_eq "$REPLY" "hs lts-22.7" "stack snapshot"
  cd $T/fl; _axle_scan_markers; _seg flutter; assert_eq "$REPLY" "flutter 3.19.0" "fvm"
  cd $T/eb; _axle_scan_markers; _seg ebenv;   assert_eq "$REPLY" "eb shop-prod" "Beanstalk environment"
  assert_eq $_axle_alarm 1 "production is an alarm"
}

test_cloud_credentials() {
  load_theme
  mkdir -p $HOME/.azure
  print -rn -- $'﻿''{"subscriptions": [{"id": "1", "name": "Dev", "user": {"name": "a@b"}, "isDefault": false}, {"id": "2", "name": "Team Sub", "user": {"name": "a@b"}, "isDefault": true}]}' > $HOME/.azure/azureProfile.json
  _seg azure; assert_eq "$REPLY" "" "azure only when expanded"
  _axle_detail=1; _seg azure; assert_eq "$REPLY" "az Team Sub" "the default subscription"; _axle_detail=0
  print '{"type": "service_account", "project_id": "shop-dev", "client_email": "deployer@shop-dev.iam.gserviceaccount.com"}' > $T/sa.json
  GOOGLE_APPLICATION_CREDENTIALS=$T/sa.json; _seg gcred
  assert_eq "$REPLY" "sa deployer@shop-dev" "service account and project"
}

test_time_and_tasks() {
  load_theme
  local m st
  mkdir -p $HOME/.timewarrior/data
  strftime -s m %Y-%m $EPOCHSECONDS
  TZ=UTC0 strftime -s st %Y%m%dT%H%M%S $(( EPOCHSECONDS - 3900 ))
  print -l 'inc 20260101T000000Z - 20260101T010000Z # old' "inc ${st}Z # client-x" > $HOME/.timewarrior/data/$m.data
  _seg timew; assert_eq "$REPLY" "⏱ client-x 1h05m" "tracking, for how long"
  print 'inc 20260101T000000Z - 20260101T010000Z # old' > $HOME/.timewarrior/data/$m.data
  _seg timew; assert_eq "$REPLY" "" "nothing when stopped"
  print -l '(A) call bob' 'x 2026-01-01 done' 'buy milk' > $HOME/todo.txt
  _axle_detail=1; _seg todo; assert_eq "$REPLY" "todo 2" "open items"
}

test_inside_programs_and_modes() {
  load_theme
  RANGER_LEVEL=1 _seg inside; assert_eq "$REPLY" "↳ ranger" "a shell from ranger"
  NVIM=/tmp/nvim.sock VIMRUNTIME=/x _seg inside; assert_eq "$REPLY" "↳ nvim" "neovim, not vim"
  _seg inside; assert_eq "$REPLY" "" "nothing in a plain shell"
  _per_directory_history_is_global=false; _seg pdhist; assert_eq "$REPLY" "" "the usual mode"
  _per_directory_history_is_global=true;  _seg pdhist; assert_eq "$REPLY" "hist global" "switched"
  _axle_keymap=vicmd; _seg vimode; assert_eq "$REPLY" "NORMAL" "vi command mode"
}

test_direnv_loaded_and_blocked() {
  load_theme
  _exe $T/bin/direnv ''; path=($T/bin $path); rehash
  mkdir -p $T/de; touch $T/de/.envrc; cd $T/de; _axle_scan_markers
  _seg direnv; assert_eq "$REPLY" "" "no hook: no claim"
  _direnv_hook() { : }
  _seg direnv; assert_eq "$REPLY" "direnv blocked" "hooked but not loaded"
  DIRENV_DIR=-$T/de _seg direnv; assert_eq "$REPLY" "direnv" "loaded"
  precmd_functions=(_axle_precmd _direnv_hook); _axle_direnv_reorder
  assert_eq "$precmd_functions" "_direnv_hook _axle_precmd" "direnv's hook moved first"
}

test_hidden_segments_leave_nothing_behind() {
  # Regression: a segment that read a cached value and then chose to hide left it in REPLY.
  load_theme
  _exe $T/bin/task 'echo 4'; path=($T/bin $path); rehash
  mkdir -p $HOME/.task $HOME/.azure; touch $HOME/.task/pending.data
  print '{"subscriptions": [{"id": "1", "name": "Dev", "isDefault": true}]}' > $HOME/.azure/azureProfile.json
  _seg azure; assert_eq "$REPLY" "" "azure hidden"
  _exe $T/bin/task 'case "$*" in *OVERDUE*) echo 0;; *) echo 4;; esac'
  _seg task;  assert_eq "$REPLY" "" "no overdue tasks: hidden"
  _axle_detail=1; _seg task; assert_eq "$REPLY" "task 4" "pending, expanded"
}
