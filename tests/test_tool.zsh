# The axle tool: history, suggestions, jump, stats, drops, env.

# Run a command through the tool's events: _run <exit> <dir> <command>
_run() {
  cd $2
  _axt_preexec "$3"
  ( exit $1 )
  _axt_precmd
}

test_history_is_recorded() {
  load_tool
  mkdir -p $T/a
  _run 0 $T/a 'make build'
  _run 2 $T/a 'make test'
  _run 0 $T/a ' secret --token x'                 # a leading space: not recorded
  local -a lines=("${(@f)$(<$_axle_hist_file)}")
  assert_eq ${#lines} 2 "two commands recorded"
  local -a f=("${(@ps:\t:)lines[2]}")
  assert_eq "$f[2]|$f[4]|$f[5]|$f[6]" "2|$T/a|make build|make test" "exit, folder, previous, command"
}

test_suggestions_rank_by_folder_and_sequence() {
  AXLE_SUGGEST=1 load_tool
  local now=$EPOCHSECONDS
  _axle_sg_ready=1
  _axle_sg_learn $now 0 /w/api '' 'git commit -m "fix"'
  _axle_sg_learn $now 0 /w/web '' 'git checkout -b nav'
  _axle_sg_learn $now 0 /w/api '' 'git add .'
  _axle_sg_learn $now 0 /w/api 'git add .' 'git commit -m "fix"'
  _axle_sg_learn $now 1 /w/api '' 'npm run deploy'
  _axle_sg_learn $now 0 /w/api '' 'npm run dev'
  PWD=/w/api _axle_ev_prev=''; _axle_sg_find 'git c'; assert_eq "$REPLY" 'git commit -m "fix"' "in api"
  PWD=/w/web; _axle_sg_find 'git c'; assert_eq "$REPLY" 'git checkout -b nav' "in web"
  PWD=/w/api _axle_ev_prev='git add .'; _axle_sg_find 'git'; assert_eq "$REPLY" 'git commit -m "fix"' "after git add ."
  _axle_sg_find 'npm run d'; assert_eq "$REPLY" 'npm run dev' "never offers what only failed"
}

test_suggestion_history_fallback_is_one_line() {
  # Regression: (R) on $history returned every match, glued together.
  local out=$(zsh -fic "HISTSIZE=100
    print -s 'claude --continue'; print -s claude; print -s 'claude --continue'; print -s 'claude --resume x'
    print -s 'ls'      # (a one-shot shell hides the newest entry from \$history until another follows)
    source $ROOT/axle.plugin.zsh >/dev/null 2>&1
    _axle_sg_ready=1; _axle_sg_find cl; print -r -- \$REPLY" 2>/dev/null)
  assert_eq "${out##*$'\n'}" "claude --resume x" "the newest single match"
}

test_jump_ranks_where_you_work() {
  load_tool
  mkdir -p $T/repos/api $T/repos/web $T/notes/api-docs
  repeat 5 _run 0 $T/repos/api 'make'
  repeat 2 _run 0 $T/notes/api-docs 'ls'
  _run 0 $T/repos/web 'ls'
  cd $T
  local -a reply
  _axle_jump_rank api; assert_eq "$reply[1]" "$T/repos/api" "most used match first"
  _axle_jump_rank re we; assert_eq "$reply[1]" "$T/repos/web" "words in order"
  _axle_jump api >/dev/null; assert_eq $PWD "$T/repos/api" "j goes there"
}

test_stats_summarise() {
  load_tool
  mkdir -p $T/p
  repeat 3 _run 0 $T/p 'make build'
  repeat 3 _run 1 $T/p 'make test'
  local out=$(_axle_cmd_stats 2>&1)
  assert_match "$out" '*6 commands, 50% failed*' "totals"
  assert_match "$out" '*100%  make test*' "fails most often"
}

test_drops() {
  load_theme
  local D=$ROOT/tools/axle-drop
  $D build "build ok" --level ok
  $D ci "tests failed" --level alarm
  $D gone "x" --while-pid 999999
  $D old "x" --ttl 1s
  $D here "only in p" --dir $T/p 2>/dev/null || { mkdir -p $T/p; $D here "only in p" --dir $T/p }
  sleep 1.2
  cd $T
  REPLY='' _axle_pinned=0; _axle_seg_drops; plain "$REPLY"
  assert_match "$REPLY" '*tests failed*build ok*' "alarm first, then ok"
  assert_not_match "$REPLY" '*only in p*' "folder-scoped drop hidden elsewhere"
  assert_eq $_axle_pinned 1 "an alarm pins the segment"
  [[ ! -e $XDG_CACHE_HOME/axle/drops/gone && ! -e $XDG_CACHE_HOME/axle/drops/old ]] ||
    fail "dead-process and expired drops are cleaned up"
}

test_env_switches_venvs_without_running_activate() {
  load_tool
  mkdir -p $T/proj/.venv/bin $T/proj/src $T/out
  print -l 'home = /usr/bin' "prompt = 'shop'" > $T/proj/.venv/pyvenv.cfg
  print "touch $T/activate-ran" > $T/proj/.venv/bin/activate
  cd $T/proj/src; _axle_env_sync >/dev/null
  assert_eq "$VIRTUAL_ENV" "$T/proj/.venv" "activated"
  assert_eq "$path[1]" "$T/proj/.venv/bin" "its bin first on PATH"
  [[ ! -e $T/activate-ran ]] || fail "the activate script was run"
  cd $T/out; _axle_env_sync >/dev/null
  assert_eq "${VIRTUAL_ENV:-}" "" "deactivated"
  (( ! ${path[(Ie)$T/proj/.venv/bin]} )) || fail "removed from PATH"
}

test_suggest_strategies_and_settings() {
  AXLE_SUGGEST=1 load_tool
  _axle_sg_ready=1
  local now=$EPOCHSECONDS
  _axle_sg_learn $now 0 /w '' 'cd /somewhere/far'
  _axle_sg_learn $now 0 /w '' 'cd /somewhere/near'
  PWD=/w _axle_ev_prev=''
  local -a reply
  _axle_sg_rank 'cd /some' 5; assert_eq ${#reply} 2 "both learned options"
  AXLE_SUGGEST_IGNORE='cd /somewhere/f*'
  _axle_sg_rank 'cd /some' 5; assert_eq "$reply" 'cd /somewhere/near' "ignored lines left out"
  AXLE_SUGGEST_IGNORE=''
  # completion: commands for the first word, paths after it
  mkdir -p "$T/files/my dir" && touch $T/files/notes.txt $T/files/.hidden
  cd $T/files
  AXLE_SUGGEST_STRATEGY=(completion)
  _axle_sg_find 'cat no';  assert_eq "$REPLY" 'cat notes.txt' "a file"
  _axle_sg_find 'ls my';   assert_eq "$REPLY" 'ls my\ dir/' "a folder, escaped, with /"
  _axle_sg_find 'cat .h';  assert_eq "$REPLY" 'cat .hidden' "hidden files when asked"
  _axle_sg_rank 'cat ' 5;  assert_eq ${#reply} 0 "nothing for an empty word"
  _axle_sg_find 'printen'; assert_eq "$REPLY" 'printenv' "a command name"
  AXLE_SUGGEST_STRATEGY=(smart)
  _axle_sg_find 'cat no';  assert_eq "$REPLY" '' "strategies can be turned off"
}

test_suggest_list_opens_on_demand() {
  # Drive the widgets in a real zle (zpty). Ctrl-X t records what's drawn after the line.
  # Each step waits for its result rather than sleeping a fixed time (CI machines are slow),
  # and Ctrl-T is avoided: it's the "status" key in macOS terminals.
  zmodload zsh/zpty 2>/dev/null || return 0
  local -i n=0
  _await() {   # wait up to 10 s for the record file to have $1 lines
    local -i i
    local -a lines
    for i in {1..100}; do
      [[ -r $T/post ]] && lines=(${(f)"$(<$T/post)"}) && (( ${#lines} >= $1 )) && return 0
      sleep 0.1
    done
    fail "no answer from the shell (step $1)"
  }
  _k() { zpty -n -w sg "$1"; [[ $1 == *$'\x18t' ]] && _await $(( ++n )) }
  zpty sg "HOME=$HOME XDG_DATA_HOME=$XDG_DATA_HOME XDG_CACHE_HOME=$XDG_CACHE_HOME HISTFILE=$T/hist TERM=xterm zsh -f -i"
  zpty -w sg "PS1='> '; source $ROOT/axle.plugin.zsh; _axle_sg_ready=1; AXLE_SUGGEST_STRATEGY=(smart)"
  zpty -w sg "_axle_sg_learn \$EPOCHSECONDS 0 \$PWD '' 'echo alpha-one'; _axle_sg_learn \$EPOCHSECONDS 0 \$PWD '' 'echo alpha-two'"
  # (zle -R redraws first, as a person's pause between keys would: suggestions are made then.)
  zpty -w sg "_t() { zle -R; print -r -- \"[\${POSTDISPLAY//\$'\n'/|}]\" >> $T/post }; zle -N _t; bindkey '^Xt' _t"
  zpty -w sg ": > $T/post"            # ready: the shell has run everything above
  local -i i; for i in {1..100}; do [[ -e $T/post ]] && break; sleep 0.1; done
  _k $'echo al\x18t'                  # typed: only the ghost text
  _k $'\x0e\x18t'                     # Ctrl-N: the list opens
  _k $'p\x18t'                        # typing closes it
  _k $'\x15'; _k $'\x10\x18t'         # empty line, Ctrl-P: a history line, no suggestion
  zpty -w sg $'\x15exit'
  zpty -d sg 2>/dev/null
  local -a post=("${(@f)$(<$T/post)}")
  assert_eq "$post[1]" '[pha-two]' "only the inline suggestion at first"
  assert_eq "$post[2]" '[pha-one|    echo alpha-two|  ▸ echo alpha-one]' "Ctrl-N opens the list"
  assert_eq "$post[3]" '[ha-two]' "typing closes it"
  assert_eq "$post[4]" '[]' "nothing on a history line"
}
