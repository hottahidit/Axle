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

# Words that aren't names (] alone, a]b) are looked up without an error.
test_highlight_brackets() {
  AXLE_MODULES=(highlight) load_tool
  local w out
  for w in ']' 'a]b' 'x[1]' '[' ']]'; do
    out=$( { _axle_hl_runnable "$w"; _axle_hl_runnable "$w" } 2>&1 )
    assert_eq "$out" "" "no error for $w"
  done
  _axle_hl_runnable '[' || fail "[ is a command"
  _axle_hl_runnable ']' && fail "] isn't"
  return 0
}

# A command that doesn't exist: said in Axle's style, with the closest one; 127.
test_fix_not_found_message() {
  setopt localoptions extendedglob
  AXLE_MODULES=(fix) load_tool
  local out
  out=$(command_not_found_handler ehco hi 2>&1); local -i st=$?
  assert_eq $st 127 "its status"
  out=${out//$'\e'\[[0-9;]##m/}
  assert_contains "$out" "✘ ehco: no such command"
  assert_contains "$out" "did you mean"
  assert_contains "$out" "did you mean echo?"
  out=$(command_not_found_handler ']' 2>&1); out=${out//$'\e'\[[0-9;]##m/}
  assert_contains "$out" "✘ ]: no such command"
  [[ $out == *"did you mean"* ]] && fail "nothing close to ]: $out"
  out=$(command_not_found_handler $'evil\e[2J' 2>&1)
  [[ $out == *$'\e[2J'* ]] && fail "control characters are not printed"
  return 0
}

# Enter on a line zsh can't read: said, kept (status 1); Enter again lets it through. An
# unfinished line goes on to the next line as zsh does.
test_fix_parse_check() {
  setopt localoptions extendedglob
  AXLE_MODULES=(fix) load_tool
  zle() { : }                                      # (outside a widget)
  local PREBUFFER='' BUFFER out
  local -a cases=(
    '<>|1|something is missing after <>'
    'echo >|1|something is missing after >'
    'echo }|1|unexpected }'
    'ls ;;|1|unexpected ;;'
    'fi|1|unexpected fi'
    'if true; then|0|'   'echo "open|0|'   'ls |0|'   'cat <<EOF|0|'   'x=(|0|'
    'for x in a; do echo|0|'   'echo $(|0|'   '{ echo|0|'   'echo ok|0|'   '   |0|'
  )
  local c text want msg
  for c in $cases; do
    text=${c%%\|*} want=${${c#*\|}%%\|*} msg=${c##*\|}
    BUFFER=$text _axle_fix_refused=''
    out=$(_axle_fix_parse_ok 2>&1; print "st=$?")
    out=${out//$'\e'\[[0-9;]##m/}
    [[ $out == *"st=$want" ]] || fail "[$text]: wanted $want: $out"
    [[ -z $msg || $out == *"zsh can't read this line: $msg"* ]] || fail "[$text]: $out"
  done
  # Enter again: through.
  BUFFER='echo }'
  _axle_fix_parse_ok >/dev/null && fail "refused"
  _axle_fix_parse_ok >/dev/null || fail "the second Enter runs it"
  # The lines before (a continued command) count.
  PREBUFFER=$'if true; then\n' BUFFER='fi'
  _axle_fix_parse_ok >/dev/null || fail "a finished if"
  PREBUFFER='' BUFFER='<>' AXLE_FIX_PARSE=0
  _axle_fix_parse_ok >/dev/null || fail "AXLE_FIX_PARSE=0"
  [[ -e $XDG_CACHE_HOME/axle/parse.$$ || -e $HOME/.cache/axle/parse.$$ ]] && fail "leaves its file"
  return 0
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
  # On a case-insensitive disk (macOS's default) readme.md *is* README.md: nothing to fix.
  [[ -e $T/readme.md ]] && cases=(${cases:#cat readme.md*})
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

# From an empty line ↑ is the usual history all the way: what it brings up isn't a search.
test_upsearch_from_an_empty_line_browses() {
  _live || return 0
  local -i _n=0
  _key $'\e[A'                # the newest command
  _key $'\e[A'                # and on, not a search for its text
  _key $'\e[A'
  _key $'\e[A'
  _key $'\e[B'                # ↓ back the same way
  _key $'\e[B'
  _key $'\e[B'
  _key $'\e[B'                # past the newest: empty again
  _key $'\e[A\e[A\x15ls'      # edited: now it's what you typed
  _key $'\e[A'                # so ↑ searches for it
  zpty -w sh $'\x15exit'; zpty -d sh 2>/dev/null
  local -a rec=("${(@f)$(<$T/rec)}")
  local newest="[true; : > $T/ready]"
  assert_eq "${(j:,:)rec[1,4]}" "$newest,[echo done],[git push --force],[ls -la]" "↑ walks the history"
  assert_eq "${(j:,:)rec[5,7]}" "[git push --force],[echo done],$newest" "↓ walks back"
  assert_eq "$rec[8]" "[]" "past the newest: empty"
  assert_eq "$rec[9]" "[ls]" "edited"
  assert_eq "$rec[10]" "[ls -la]" "a search for what was typed"
}

# Longer walks: where bugs hide is the second and third press, not the first.
test_upsearch_key_sequences() {
  _live || return 0
  local -i _n=0
  local newest="[true; : > $T/ready]"
  repeat 7 _key $'\e[A'            # ↑ to the oldest (the setup line), and once more: stays
  _key $'\x15'                     # cleared
  _key 'push'                      # a search, back and forth
  _key $'\e[A'; _key $'\e[A'; _key $'\e[B'; _key $'\e[A'
  zpty -w sh $'\x15exit'; zpty -d sh 2>/dev/null
  local -a rec=("${(@f)$(<$T/rec)}")
  assert_eq "${(j:,:)rec[1,5]}" "$newest,[echo done],[git push --force],[ls -la],[git push origin main]" "↑ walks back"
  assert_eq "$rec[7]" "$rec[6]" "at the oldest it stays"
  assert_eq "${(j:,:)rec[10,13]}" "[git push --force],[git push origin main],[git push --force],[git push origin main]" "a search, back and forth"
}

# A command run from the walk: the next prompt starts over.
test_upsearch_after_running_a_recalled_line() {
  _live || return 0
  local -i _n=0
  zpty -n -w sh $'\e[A'; sleep 0.15; zpty -n -w sh $'\e[A'; sleep 0.15; zpty -n -w sh $'\r'; sleep 0.3
  _key $'\e[A'                     # the command just run
  _key $'\e[A'                     # still browsing, not searching for it
  zpty -w sh $'\x15exit'; zpty -d sh 2>/dev/null
  local -a rec=("${(@f)$(<$T/rec)}")
  assert_eq "$rec[1]" "[echo done]" "what just ran"
  assert_eq "$rec[2]" "[true; : > $T/ready]" "and on through the history"
}

# A multi-line command on the way: ↑ moves inside it, then on to older ones.
test_upsearch_through_a_multi_line_command() {
  _live || return 0
  local -i _n=0
  zpty -w sh " print -s \$'first line\\nsecond line'"
  zpty -w sh "true; : > $T/ready2"; _wait $T/ready2
  _key $'\e[A'                     # true...
  _key $'\e[A'; (( _n++ ))          # the multi-line one, cursor at its end (two log lines)
  _key $'\e[A'; (( _n++ ))          # up inside it
  _key $'\e[A'                     # on to an older one
  zpty -w sh $'\x15exit'; zpty -d sh 2>/dev/null
  local -a rec=("${(@f)$(<$T/rec)}")
  assert_contains "${(j:,:)rec}" "first line" "reaches it"
  assert_contains "$rec[-1]" "true; : >" "and leaves it for an older command"
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

# The list is Axle's modules, wherever you are (it once listed the current folder's files).
test_module_list_is_the_modules() {
  load_tool
  mkdir -p $T/elsewhere/notes; : > $T/elsewhere/README.md; cd $T/elsewhere
  local opt out
  for opt in noglobsubst globsubst; do
    setopt $opt
    out=$(axle module 2>&1)
    assert_contains "$out" "jump" "$opt: a module"
    assert_match "$out" "*off  run * this project*" "$opt: and run, off, with what it does"
    [[ $out == *README* || $out == *notes* || $out == *"no such file"* ]] && fail "$opt: not this folder's files: $out"
  done
  setopt noglobsubst
  out=$(axle module on nosuch 2>&1) && fail "an unknown module"
  assert_contains "$out" "no module 'nosuch'"
  axle module on run > $T/out 2>&1 || fail "switching run on: $(<$T/out)"
  assert_contains "$(<$T/out)" "run enabled"
  assert_contains "$(<$AXLE_CONFIG)" "AXLE_MODULES=" "saved"
  (( ${AXLE_MODULES[(Ie)run]} )) || fail "on now"
  (( ${+_axle_cmd_fn[run]} )) || fail "axle run exists now"
  out=$(AXLE_MODULES=(nosuch); source $ROOT/axle.plugin.zsh 2>&1)
  assert_contains "$out" "no module 'nosuch' (available: " "the load-time message"
  assert_contains "$out" "jump" "names the real ones"
}
