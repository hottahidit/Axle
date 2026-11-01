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

# Which project `axle run [args]` means. Sets _axle_run_root, _axle_run_marker and
# _axle_run_why; returns 1 (with a message) when there isn't one.
_axle_run_pick() {
  typeset -g _axle_run_root='' _axle_run_marker='' _axle_run_why=''
  local -a reply
  local REPLY
  if (( $# == 1 )) && [[ -d ${1/#\~/$HOME} ]]; then
    local dir=${${1/#\~/$HOME}:a}
    if _axle_project_root $dir; then
      _axle_run_root=$reply[1] _axle_run_marker=$reply[2] _axle_run_why='the folder you gave'
    else
      print -u2 -r -- "axle run: ${dir/#$HOME/~} isn't in a project (no .git, pyproject.toml, package.json, ...)"
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
    _axle_run_why="the best match for \"$*\" (by where you work, like j)"
  elif _axle_project_root; then
    _axle_run_root=$reply[1] _axle_run_marker=$reply[2] _axle_run_why="you're in it"
  elif _axle_run_last; then
    local root=$REPLY
    _axle_run_ago ${_axle_run_when[$root]}
    _axle_run_why="the last project you worked in ($REPLY)"
    _axle_project_root $root
    _axle_run_root=$root _axle_run_marker=$reply[2]
  else
    print -u2 -r -- "axle run: not in a project, and none in your history yet (work in one, or: axle run <path>)"
    return 1
  fi
}

_axle_cmd_run() {
  local dry=0
  local -a words=()
  while (( $# )); do
    case $1 in
      -n|--dry-run) dry=1 ;;
      --) shift; words+=("$@"); break ;;
      -*) print -u2 -r -- "axle run: unknown option '$1' (axle help run)"; return 1 ;;
      *)  words+=("$1") ;;
    esac
    shift
  done
  _axle_run_pick "${words[@]}" || return 1
  local REPLY root=$_axle_run_root muted=${_axle_c[muted]:-244}
  local venv=''
  _axle_venv_in $root && venv=${REPLY#$root/}
  _axle_printp "%B${${root:t}//\%/%%}%b"
  print -r -- "  root   ${root/#$HOME/~}"
  print -r -- "  why    $_axle_run_why · marked by $_axle_run_marker"
  [[ -n $venv ]] && print -r -- "  venv   $venv"
  if (( ! dry )); then
    _axle_printp "%F{$muted}axle run: detecting and running projects comes next (M1); this is what it would pick.%f"
  fi
  return 0
}
