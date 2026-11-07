# The wide nets: every command run for real from a folder of unrelated files, every help
# page, and reloading from earlier releases. These catch what a narrow test can't think of.

# What only ever appears when something is broken.
_clean() {   # <output> <what ran>
  local line
  for line in "${(@f)1}"; do
    case $line in
      *'command not found'*|*'no such file or directory'*|*'parse error'*|*'bad substitution'*|\
      *'bad math expression'*|*'bad pattern'*|*'no matches found'*|*'bad set of key/value'*|\
      *'character not in range'*|*'read-only variable'*|*'not an identifier'*)
        fail "$2 printed an error: $line" ;;
      ([_a-zA-Z]##:<->:\ *|\(eval\):<->:\ *|\(anon\):<->:\ *)      # zsh's own function:line: message
        fail "$2 printed an error: $line" ;;
    esac
  done
}

_load_all() {
  AXLE_MODULES=(suggest highlight upsearch jump search env fix run) load_tool
  load_theme
  mkdir -p $T/busy/notes; : > $T/busy/README.md; : > $T/busy/LICENSE; cd $T/busy
}

# Commands that aren't run here, and why. Anything else registered must be in the list below,
# so a new command can't go untested.
typeset -gA _not_run=(
  uninstall 'removes things (it has its own test)'
  update    'uses the network (it has its own test)'
  ai        'uses the network'
  top       'opens btop, full screen (it has its own test)'
)
typeset -ga _runs=(
  'colors' 'config' 'config get AXLE_PALETTE' 'configure' 'debug' 'doctor' 'drop --ls' 'fix'
  'history' 'history 5' 'hook ls' 'jump -l nothing' 'module' 'module ls' 'palette'
  'preview --list' 'refresh' 'reload' 'run -n' 'run ls' 'run logs' 'run stop' 'run open'
  'run restart' 'run nothing-like-this' 'segment ls' 'segments' 'stats' 'stats --here' 'tmux'
  'variant' 'version' 'help' 'run top'
)

test_every_command_runs_clean_from_any_folder() {
  _load_all
  local c opt out name
  for name in ${(k)_axle_cmd_fn}; do
    (( ${+_not_run[$name]} )) && continue
    [[ -n ${(M)_runs:#$name(| *)} ]] || fail "'axle $name' isn't covered: add it to _runs or _not_run"
  done
  for opt in noglobsubst globsubst; do
    setopt $opt
    for c in $_runs; do
      out=$(axle ${=c} </dev/null 2>&1)
      _clean "$out" "axle $c ($opt)"
      [[ $out == *README.md* ]] && fail "axle $c ($opt) listed this folder's files: $out"
    done
  done
  return 0
}

test_every_help_page_is_clean() {
  _load_all
  local name out
  for name in ${(k)_axle_cmd_fn}; do
    out=$(axle help $name </dev/null 2>&1); _clean "$out" "axle help $name"
    [[ -n $out ]] || fail "axle help $name says nothing"
    [[ $name == (jump|preview) ]] && continue        # (their own -h)
    out=$(axle $name --help </dev/null 2>&1); _clean "$out" "axle $name --help"
  done
}

# A shell left open across an update: the release it started on, then `axle reload` into
# this code. Needs the release tags (CI fetches them).
test_reload_from_earlier_releases() {
  [[ -e $ROOT/.git ]] || return 0
  local -a tags=(${(f)"$(command git -C $ROOT tag -l 'v0.2.*' 2>/dev/null)"})
  (( ${#tags} )) || return 0
  local v old out
  for v in $tags; do
    old=$T/old-$v; mkdir -p $old
    command git -C $ROOT archive $v | command tar -x -C $old || fail "can't unpack $v"
    print -l "source $old/axle.plugin.zsh" "source $old/benzene.zsh-theme" \
      "AXLE_ROOT=$ROOT" 'axle reload' 'print "lazy=$+functions[_axle_lazy] version=$AXLE_VERSION"' \
      'axle module; axle doctor >/dev/null; print ok' > $T/reload.zsh
    out=$(AXLE_UPDATE_CHECK=0 zsh -f -i $T/reload.zsh </dev/null 2>&1)
    _clean "$out" "reload from $v"
    assert_contains "$out" "lazy=1" "from $v: the new code is loaded"
    assert_contains "$out" "jump" "from $v: axle module works"
    assert_contains "$out" "ok" "from $v: to the end"
  done
}
