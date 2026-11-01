# `axle run`, loaded when first used (registered by modules/run.zsh). The plan is
# docs/legionary/ROADMAP.md; this is M0: finding the project, and saying why.
#
# State, under ${XDG_STATE_HOME:-~/.local/state}/axle/run:
#   services/<name>/   a background service: pid, started, port, url, command, kind, root, log
#   trust              project root <TAB> command hash (commands you approved)
#   projects/<hash>    a project's override and profile (KEY=value data, never sourced)

typeset -g _axle_run_dir=${XDG_STATE_HOME:-$HOME/.local/state}/axle/run

# Create the state folders (only when something is about to be written there).
_axle_run_state_init() {
  mkdir -p -m 700 $_axle_run_dir/{services,projects} 2>/dev/null || return 1
  [[ -e $_axle_run_dir/trust ]] || : >> $_axle_run_dir/trust
}

# A short stable hash of a text (REPLY), to name per-project files: cksum is POSIX, so
# it's on Linux and macOS alike.
_axle_run_hash() {
  local out
  out=$(print -rn -- "$1" | command cksum) || return 1
  REPLY=${out%% *}
}

# Project roots from the history log, most recently worked in first (reply), with the
# epoch of the last command in each (_axle_run_when). Folders that are gone, and $HOME
# itself, don't count.
_axle_run_recent() {
  typeset -gA _axle_run_when=()
  reply=()
  [[ -r $_axle_hist_file ]] || return 1
  local epoch dir root
  local -A seen=()
  local -a found=()
  command awk -F'\t' 'NF == 6 { l[$4] = $1 } END { for (d in l) print l[d] "\t" d }' \
      $_axle_hist_file 2>/dev/null | command sort -rn | command head -n 500 |
  while IFS=$'\t' read -r epoch dir; do
    [[ -d $dir ]] || continue
    _axle_project_root $dir || continue
    root=$reply[1]
    (( ${+seen[$root]} )) && continue
    seen[$root]=1
    _axle_run_when[$root]=$epoch
    found+=($root)
  done
  reply=($found)
  (( ${#reply} ))
}

# The project you last worked in, other than the one you're in (REPLY = its root).
_axle_run_last() {
  local here=''
  _axle_project_root && here=$reply[1]
  _axle_run_recent || { REPLY=''; return 1 }
  REPLY=${${reply:#$here}[1]}
  [[ -n $REPLY ]]
}

# How long ago an epoch was, in words (REPLY): "just now", "5m ago", "2h ago", "3d ago".
_axle_run_ago() {
  local -i s=$(( EPOCHSECONDS - $1 ))
  if   (( s < 60 ));    then REPLY='just now'
  elif (( s < 3600 ));  then REPLY="$(( s / 60 ))m ago"
  elif (( s < 86400 )); then REPLY="$(( s / 3600 ))h ago"
  else                       REPLY="$(( s / 86400 ))d ago"
  fi
}

# Which project `axle run [args]` means. Sets _axle_run_root, _axle_run_marker (the file
# that marks its root; empty for a folder that's runnable without one, like a lone
# index.html), _axle_run_why and _axle_run_from (path|words|here|last); returns 1 (with a
# message) when there isn't one.
_axle_run_pick() {
  typeset -g _axle_run_root='' _axle_run_marker='' _axle_run_why='' _axle_run_from=''
  local -a reply
  local REPLY
  if (( $# == 1 )) && [[ -d ${1/#\~/$HOME} ]]; then
    local dir=${${1/#\~/$HOME}:a}
    _axle_run_from=path _axle_run_why='the folder you gave'
    if _axle_project_root $dir; then
      _axle_run_root=$reply[1] _axle_run_marker=$reply[2]
    elif [[ $dir != $HOME && $dir != / ]] && _axle_run_detect $dir; then
      _axle_run_root=$dir
    else
      print -u2 -r -- "axle run: ${dir/#$HOME/~} isn't a project (no .git, pyproject.toml, package.json, ...)"
      return 1
    fi
  elif (( $# )); then
    # Projects ranked by where you work (j's frecency over all folders, each counted for
    # its project), matched like j: words in order along the path, the last one in the
    # project's own name. Failing that, j's own pick for the words, if it's in a project.
    setopt localoptions extendedglob
    local pat='(#i)*' w m root last=${(b)@[-1]}
    for w; do pat+="${(b)w}*"; done
    local -A seen=()
    _axle_jump_rank
    local -a ranked=($reply)
    for m in $ranked $PWD; do
      _axle_project_root $m || continue
      root=$reply[1]
      (( ${+seen[$root]} )) && continue
      seen[$root]=1
      [[ ${root/#$HOME/~} == ${~pat} && ${root:t} == (#i)*${~last}* ]] || continue
      _axle_run_root=$root _axle_run_marker=$reply[2]
      break
    done
    if [[ -z $_axle_run_root ]]; then
      _axle_jump_rank "$@"
      for m in $reply; do
        _axle_project_root $m || continue
        _axle_run_root=$reply[1] _axle_run_marker=$reply[2]
        break
      done
    fi
    if [[ -z $_axle_run_root ]]; then
      print -u2 -r -- "axle run: no project matches '$*'"
      return 1
    fi
    _axle_run_why="the best match for \"$*\" (by where you work, like j)" _axle_run_from=words
  elif _axle_project_root; then
    _axle_run_root=$reply[1] _axle_run_marker=$reply[2] _axle_run_why="you're in it" _axle_run_from=here
  elif [[ $PWD != $HOME && $PWD != / ]] && _axle_run_detect $PWD; then
    _axle_run_root=$PWD _axle_run_why="you're in it" _axle_run_from=here
  elif _axle_run_last; then
    local root=$REPLY
    _axle_run_ago ${_axle_run_when[$root]}
    _axle_run_why="the last project you worked in ($REPLY)"
    _axle_project_root $root
    _axle_run_root=$root _axle_run_marker=$reply[2] _axle_run_from=last
  else
    print -u2 -r -- "axle run: not in a project, and none in your history yet (work in one, or: axle run <path>)"
    return 1
  fi
}

# --- trust ---------------------------------------------------------------------------
# A project's command runs only once you've seen and approved it; the answer is kept per
# project root and per command (with the text it comes from, so a changed package.json
# script asks again), like `direnv allow`.

# The trust key of the detected command (REPLY).
_axle_run_trust_key() {
  _axle_run_hash "$1"$'\0'"${(j:\0:)_axle_run_cmd}"$'\0'"$_axle_run_source" || return 1
  REPLY="$1"$'\t'"$REPLY"
}

_axle_run_trusted() {
  local key=$1 line
  [[ -r $_axle_run_dir/trust ]] || return 1
  while IFS= read -r line; do [[ $line == $key ]] && return 0; done < $_axle_run_dir/trust
  return 1
}

_axle_run_trust() {
  _axle_run_state_init || return 1
  _axle_run_trusted $1 || print -r -- $1 >> $_axle_run_dir/trust
}

# --- the command ----------------------------------------------------------------------

# The detected command as you'd type it (REPLY): quoted, paths inside the project relative.
_axle_run_show() {
  local root=$1 w
  local -a out=()
  for w in $_axle_run_cmd; do out+=("${(q-)${w#$root/}}"); done
  REPLY=${(j: :)out}
}

# Run the detected command in the foreground, in the project's root and its venv (set up
# the way the env module does it: VIRTUAL_ENV and bin/ on PATH, never `activate`).
_axle_run_exec() {
  local root=$1 REPLY
  (
    cd -- $root || exit 1
    if _axle_venv_in $root; then
      export VIRTUAL_ENV=$REPLY
      path=($REPLY/bin ${path:#$REPLY/bin})
      unset PYTHONHOME
    fi
    exec -- "${_axle_run_cmd[@]}"
  )
}

_axle_cmd_run() {
  local dry=0 yes=0
  local -a words=()
  while (( $# )); do
    case $1 in
      -n|--dry-run) dry=1 ;;
      -y|--yes)     yes=1 ;;
      --) shift; words+=("$@"); break ;;
      -*) print -u2 -r -- "axle run: unknown option '$1' (axle help run)"; return 1 ;;
      *)  words+=("$1") ;;
    esac
    shift
  done
  _axle_run_pick "${words[@]}" || return 1
  local REPLY root=$_axle_run_root name=${_axle_run_root:t}
  local muted=${_axle_c[muted]:-244} accent=${_axle_c[accent]:-magenta}
  local found=0 show=''
  _axle_run_detect $root && { found=1; _axle_run_show $root; show=$REPLY }

  if (( dry )); then
    local venv=''
    _axle_venv_in $root && venv=${REPLY#$root/}
    _axle_printp "%B${name//\%/%%}%b"
    print -r -- "  root   ${root/#$HOME/~}"
    print -r -- "  why    $_axle_run_why${_axle_run_marker:+ · marked by $_axle_run_marker}"
    [[ -n $venv ]] && print -r -- "  venv   $venv"
    if (( found )); then
      print -r -- "  run    $show"
      print -r -- "  how    $_axle_run_what ($_axle_run_reason)"
      if [[ $_axle_run_kind == service ]]; then
        print -r -- "  kind   service${_axle_run_port:+ on http://localhost:$_axle_run_port}"
      else
        print -r -- "  kind   task (runs in the foreground)"
      fi
      _axle_run_trust_key $root
      _axle_run_trusted $REPLY || print -r -- "  trust  not run before: axle run asks first"
    else
      print -r -- "  run    ? (no way to run it found)"
    fi
    return 0
  fi

  # Elsewhere, or a project you named: go there first.
  if [[ $_axle_run_from == last ]]; then
    _axle_run_ago ${_axle_run_when[$root]}
    _axle_printp "%F{$accent}↩%f %B${name//\%/%%}%b %F{$muted}(last worked on ${REPLY})%f"
  fi
  [[ ${PWD:a} == $root || ${PWD:a} == $root/* ]] || cd -- $root || return 1

  if (( ! found )); then
    print -u2 -r -- "axle run: no way to run ${name} found (looked for package.json scripts, Python apps,"
    print -u2 -r -- "  Cargo.toml, go.mod, index.html). Setting a command per project comes later (M5)."
    return 1
  fi

  _axle_run_trust_key $root
  local key=$REPLY trusted=0
  _axle_run_trusted $key && trusted=1
  local summary="$_axle_run_what · $show"
  if (( ! trusted && ! yes )); then
    _axle_printp "%F{$muted}First run of this command in ${name//\%/%%} (${_axle_run_reason//\%/%%}).%f"
    axle_confirm "Run it?  $summary" n || return 1
  elif [[ $_axle_run_from == last ]] && (( ! yes )); then
    axle_confirm "Run it?  $summary" y || return 0
  fi
  (( trusted )) || _axle_run_trust $key

  if [[ $_axle_run_kind == service ]]; then
    _axle_printp "%F{${_axle_c[ok]:-green}}⚡%f %B${name//\%/%%}%b${_axle_run_port:+ on http://localhost:$_axle_run_port} %F{$muted}(in the foreground for now: Ctrl-C stops it)%f"
  fi
  _axle_printp "%F{$muted}▶ ${show//\%/%%}%f"
  _axle_run_exec $root
}
