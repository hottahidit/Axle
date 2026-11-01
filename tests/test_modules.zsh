# The highlight, upsearch and fix modules.

# What colour each word of a line gets: "[word]=kind ...".
_hl() {
  BUFFER=$1; region_highlight=(); _axle_hl_paint
  local e out='' kind st
  local -A names=()
  for kind st in ${(kv)_axle_hl_style}; do names[$st]=$kind; done
  for e in $region_highlight; do
    local -a f=(${=e})
    out+="[${BUFFER[f[1]+1,f[2]]}]=${names[${f[3]%%,memo*}]} "
  done
  REPLY=${out% }
}

test_highlight_kinds() {
  AXLE_MODULES=(highlight) load_tool
  zmodload zsh/parameter
  _axle_hl_styles
  touch $T/notes.txt; cd $T
  _hl 'git status -s | grep notes.txt'
  assert_eq "$REPLY" '[git]=command [-s]=option [|]=operator [grep]=command [notes.txt]=path' "a pipeline"
  _hl 'gti status'; assert_eq "$REPLY" '[gti]=unknown' "a command that doesn't exist"
  _hl 'FOO=1 sudo -E ls # done'
  assert_eq "$REPLY" '[FOO]=assign [sudo]=command [-E]=option [ls]=command [# done]=comment' "assignment, sudo, comment"
  _hl 'echo "hi $USER" *.txt'
  assert_contains "$REPLY" '["hi $USER"]=string' "a string"
  assert_contains "$REPLY" '[$USER]=variable' "a variable inside it"
  assert_contains "$REPLY" '[*.txt]=glob' "a glob"
  _hl 'if true; then ls; fi'
  assert_eq "$REPLY" '[if]=reserved [true]=command [;]=operator [then]=reserved [ls]=command [;]=operator [fi]=reserved' "keywords"
}

test_highlight_remembers_lookups() {
  AXLE_MODULES=(highlight) load_tool
  zmodload zsh/parameter
  _axle_hl_runnable no-such-cmd-xyz && fail "unknown"
  (( ${+_axle_hl_known[no-such-cmd-xyz]} )) || fail "the answer is remembered"
  mkdir -p $T/bin; print '#!/bin/sh' > $T/bin/no-such-cmd-xyz; chmod +x $T/bin/no-such-cmd-xyz
  path=($T/bin $path)
  _axle_hl_runnable no-such-cmd-xyz || fail "a PATH change forgets unknown answers"
}

test_fix_suggestions() {
  AXLE_MODULES=(fix) load_tool
  mkdir -p $T/Downloads; touch $T/README.md; print 'echo hi' > $T/deploy.sh; cd $T
  local -a cases=(
    'gti status|127|git status'
    'sl -la|127|ls -la'
    'git psuh|1|git push'
    'cd Donwloads|1|cd Downloads'
    'cat readme.md|1|cat README.md'
    './deploy.sh|126|chmod +x ./deploy.sh && ./deploy.sh'
    'apt install htop|100|sudo apt install htop'
    'systemctl restart nginx|1|sudo systemctl restart nginx'
  )
  local c
  for c in $cases; do
    local -a f=("${(@s:|:)c}")
    _axle_fix_suggest "$f[1]" $f[2] $T || fail "no fix for: $f[1]"
    assert_eq "$REPLY" "$f[3]" "$f[1]"
  done
  ! _axle_fix_suggest 'ls' 2 $T || fail "nothing to fix in: ls"
  ! _axle_fix_suggest 'frobnicate-xyz' 127 $T || fail "nothing close to: frobnicate-xyz"
}

test_fix_upstream() {
  AXLE_MODULES=(fix) load_tool
  mkrepo $T/r; cd $T/r
  git remote add origin https://example.invalid/r.git
  _axle_fix_suggest 'git push' 128 $T/r || fail "no fix"
  assert_eq "$REPLY" "git push -u origin $(git symbolic-ref --short HEAD)" "sets the upstream"
}

test_fix_command_puts_it_on_the_line() {
  AXLE_MODULES=(fix) load_tool
  _axle_ev_last_cmd='gti status' _axle_ev_last_exit=127 _axle_ev_last_dir=$T
  fix 2>/dev/null || fail "fix found nothing"
  local line; read -rz line
  assert_eq "$line" "git status" "on the line, not run"
  _axle_ev_last_exit=0
  fix 2>/dev/null && fail "nothing to fix after a success"
  return 0
}

# A live zsh in a pty: ↑/↓ search and Esc Esc.
_live() {
  zmodload zsh/zpty 2>/dev/null || return 1
  zpty sh "HOME=$HOME XDG_CONFIG_HOME=$XDG_CONFIG_HOME XDG_CACHE_HOME=$XDG_CACHE_HOME XDG_DATA_HOME=$XDG_DATA_HOME HISTFILE=$T/hist TERM=xterm AXLE_UPDATE_CHECK=0 zsh -f -i"
  # (Setup lines start with a space: kept out of the history being searched.)
  zpty -w sh "setopt hist_ignore_space; PS1='> '; HISTSIZE=100"
  zpty -w sh " AXLE_MODULES=(upsearch fix); source $ROOT/axle.plugin.zsh"
  zpty -w sh " print -s 'git push origin main'; print -s 'ls -la'; print -s 'git push --force'; print -s 'echo done'"
  zpty -w sh " _rec() { print -r -- \"[\$BUFFER]\" >> $T/rec }; zle -N _rec; bindkey '^Xr' _rec"
  zpty -w sh "true; : > $T/ready"     # (the last space-prefixed line stays reachable until a command)
  _wait $T/ready
}
_drain() { local c; while zpty -rt sh c 2>/dev/null; do :; done }
_wait() {
  local -i i; local -a l
  for i in {1..100}; do
    _drain
    [[ -e $1 ]] && l=(${(f)"$(<$1)"}) && (( ${#l} >= ${2:-0} )) && return 0
    sleep 0.1
  done
  fail "no answer from the shell ($1)"
}
_key() { _drain; zpty -n -w sh "$1"; sleep 0.15; zpty -n -w sh $'\x18r'; _wait $T/rec $(( ++_n )) }

test_upsearch_walks_matching_lines() {
  _live || return 0
  local -i _n=0
  _key 'push'                 # typed
  _key $'\e[A'                # ↑ newest line with "push"
  _key $'\e[A'                # ↑ the one before
  _key $'\e[A'                # ↑ no older: stays
  _key $'\e[B'                # ↓
  _key $'\e[B'                # ↓ past the newest: what was typed
  _key $'\x15\e[A'            # empty line, ↑: the usual previous line
  zpty -w sh $'\x15exit'; zpty -d sh 2>/dev/null
  local -a rec=("${(@f)$(<$T/rec)}")
  assert_eq "${(j:,:)rec}" "[push],[git push --force],[git push origin main],[git push origin main],[git push --force],[push],[true; : > $T/ready]" "the walk"
}

test_esc_esc_fixes_and_toggles_sudo() {
  _live || return 0
  local -i _n=0
  zpty -w sh 'gti status'      # fails: command not found
  _key $'\e\e'                # empty line: the fix
  _key $'\x15apt update\e\e'  # a typed line: sudo added
  _key $'\e\e'                # and removed
  zpty -w sh $'\x15exit'; zpty -d sh 2>/dev/null
  local -a rec=("${(@f)$(<$T/rec)}")
  assert_eq "$rec[1]" '[git status]' "the fix"
  assert_eq "$rec[2]" '[sudo apt update]' "sudo added"
  assert_eq "$rec[3]" '[apt update]' "sudo removed"
}
