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

# After "no" to the last project: the others you worked in lately, to pick one from
# (REPLY = its root). Returns 1 when there are none or you pick none.
_axle_run_other() {
  local here='' r                                  # (REPLY: the answer)
  local -a reply roots=() opts=()
  _axle_project_root && here=$reply[1]
  _axle_run_recent || return 1
  for r in $reply; do
    [[ $r == "$1" || $r == "$here" ]] || roots+=($r)
  done
  roots=(${roots[1,8]})
  (( ${#roots} )) || return 1
  local -i i w=8
  for r in $roots; do (( ${#r:t} > w )) && w=${#r:t}; done
  (( w > 24 )) && w=24
  for i in {1..${#roots}}; do
    r=$roots[i]
    _axle_run_ago ${_axle_run_when[$r]}
    opts+=("${(r:w:)${r:t}}  ${${r:h}/#$HOME/~} · $REPLY:$i")
  done
  opts+=("None, stay here:0")
  axle_select "Run another project?" 1 $opts || return 1
  (( REPLY )) || return 1
  REPLY=$roots[REPLY]
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
  # The command as detected: another port chosen for this run doesn't make it a new one.
  local -a cmd=(${_axle_run_cmd_detected:-$_axle_run_cmd})
  _axle_run_hash "$1"$'\0'"${(j:\0:)cmd}"$'\0'"$_axle_run_source" || return 1
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

# Is the detected command's program there (on PATH, in the project's venv or the active
# one, or a file in the project)? If not, say so and how to get it, before any question.
_axle_run_installed() {
  local dir=$1 name=$2 prog=$_axle_run_cmd[1] REPLY
  [[ -n $prog ]] || return 0
  if [[ $prog == */* ]]; then
    [[ -x $prog || -x $dir/$prog ]] && return 0
  else
    whence -p -- $prog >/dev/null && return 0
    [[ -n $VIRTUAL_ENV && -x $VIRTUAL_ENV/bin/$prog ]] && return 0
    _axle_venv_find $dir && [[ -x $REPLY/bin/$prog ]] && return 0
  fi
  local how
  case ${prog:t} in
    pnpm|yarn)                       # (Node 25 stopped bundling corepack)
      if [[ -n ${commands[node]} && -x ${commands[node]:h}/corepack ]]; then
        how="corepack enable ${prog:t}, or npm install -g ${prog:t}"
      else
        how="npm install -g ${prog:t}"
      fi ;;
    bun)       how="see https://bun.sh" ;;
    node|npm|npx) how="install Node.js (https://nodejs.org, or nvm / fnm)" ;;
    deno)      how="see https://deno.com" ;;
    cargo)     how="install Rust with rustup (https://rustup.rs)" ;;
    go)        how="install Go (https://go.dev/dl)" ;;
    just)      how="install just (https://just.systems)" ;;
    docker)    how="install Docker (https://docs.docker.com/get-docker)" ;;
    make)      how="install make (on Debian / Ubuntu: sudo apt install make)" ;;
    python*)   how="install Python, or create the project's venv" ;;
    *)         how="install it into the project's venv or onto your PATH" ;;
  esac
  print -u2 -r -- "axle run: ${name} runs with ${prog:t}, which isn't installed: $how"
  return 1
}

# Run the detected command in the foreground, in the project's root and its venv (set up
# the way the env module does it: VIRTUAL_ENV and bin/ on PATH, never `activate`).
_axle_run_exec() {
  local root=$1 REPLY
  (
    cd -- $root || exit 1
    _axle_run_enter_venv "$_axle_run_use_venv"
    # The same environment a background service gets: .env (data), PORT, what axle run set.
    local e
    local -a reply
    _axle_run_envfile $root/.env && for e in $reply; do export "$e"; done
    [[ $_axle_run_kind == service && -n $_axle_run_port ]] && export PORT=$_axle_run_port
    for e in $_axle_run_env; do export "$e"; done
    exec -- "${_axle_run_cmd[@]}"
  )
}

# Before a part runs: a missing program, then (a service) a taken port, then the first-run
# question. Returns 1 to skip it.
_axle_run_ready() {
  local dir=$1 name=$2 yes=$3
  _axle_run_installed $dir $name || return 1
  if [[ $_axle_run_kind == service ]]; then
    typeset -ga _axle_run_cmd_detected=($_axle_run_cmd)
    _axle_run_resolve_port $dir $name || return 1
  fi
  _axle_run_approve $dir $name $yes
  local -i st=$?
  typeset -ga _axle_run_cmd_detected=()
  return $st
}

# --- one part ------------------------------------------------------------------------------

# Show the detected command and ask, the first time this project (part) runs it.
#   _axle_run_approve <dir> <name> <yes>     returns 1 if you said no
_axle_run_approve() {
  local dir=$1 name=$2 yes=$3 REPLY
  _axle_run_installed $dir $name || return 1
  _axle_run_trust_key $dir
  local key=$REPLY
  if ! _axle_run_trusted $key; then
    if (( ! yes )); then
      _axle_run_show $dir
      _axle_printp "%F{${_axle_c[muted]:-244}}First run of this command in ${name//\%/%%} (${_axle_run_reason//\%/%%}).%f"
      axle_confirm "Run it?  $_axle_run_what · $REPLY" n || return 1
    fi
    _axle_run_trust $key
  fi
  _axle_run_choose_venv $dir $name $yes
}

# Which venv this run uses (_axle_run_use_venv: its path, or - to leave things as they are).
# The project's own, unless another is active: AXLE_RUN_VENV says what then (ask, project or
# active). Without a terminal to ask in, or with --yes, the project's.
_axle_run_choose_venv() {
  local dir=$1 name=$2 yes=$3 REPLY found='' active=$VIRTUAL_ENV use=project
  local warn=${_axle_c[warn]:-yellow} muted=${_axle_c[muted]:-244}
  typeset -g _axle_run_use_venv=-
  if _axle_venv_find $dir; then
    found=$REPLY
    if [[ ! -x $found/bin/python ]]; then
      _axle_printp "%F{$warn}!%f ${${found/#$HOME/~}//\%/%%} has no working Python, so it isn't used"
      found=''
    fi
  fi
  if [[ -z $found ]]; then
    [[ $_axle_run_what == python* ]] || return 0
    if [[ -n $active && $active != $dir && $active != $dir/* ]]; then
      _axle_printp "%F{$warn}!%f ${name//\%/%%} has no venv: using the active one, ${${active/#$HOME/~}//\%/%%}"
    elif [[ -z $active && -n $dir/(requirements.txt|pyproject.toml|Pipfile)(#qN[1]) ]]; then
      _axle_printp "%F{$muted}${name//\%/%%} has no venv: using ${$(whence -p $_axle_run_cmd[1])//\%/%%}%f"
    fi
    return 0
  fi
  if [[ -n $active && ${active:A} != ${found:A} ]]; then
    case ${AXLE_RUN_VENV:-ask} in
      active)  use=active ;;
      project) use=project ;;
      *)
        local rel=${found#$dir/} other=${active/#$HOME/~}
        if (( yes )) || ! _axle_ui_tty; then
          _axle_printp "%F{$muted}using ${name//\%/%%}'s venv ($rel), not the active one ($other)%f"
        else
          axle_confirm "${other} is active, and ${name} has its own venv ($rel). Use ${name}'s?" y || use=active
        fi ;;
    esac
  fi
  if [[ $use == active ]]; then
    _axle_run_cmd[1]=${_axle_run_cmd[1]/#$found\/bin/$active/bin}
    _axle_run_use_venv=$active
  else
    _axle_run_use_venv=$found
  fi
}

# The ▶ line: the command about to run (and what axle run adds to its environment).
_axle_run_say_cmd() {
  local REPLY
  local -a shown=(${_axle_run_env:#PYTHONPATH=$AXLE_ROOT/modules/run/py*})   # (our hook)
  _axle_run_show $1
  _axle_printp "%F{${_axle_c[muted]:-244}}▶ ${REPLY//\%/%%}${shown:+ (${(j:, :)shown})}%f"
}

# docker compose: `up -d` in the foreground (it detaches its containers), then remember
# it as a service so ls / stop / logs / restart work on it.
_axle_run_compose_up() {
  local dir=$1 name=$2 REPLY
  whence -p docker >/dev/null || { print -u2 -r -- "axle run: $name uses docker compose, and docker isn't installed"; return 1 }
  _axle_run_say_cmd $dir
  _axle_run_exec $dir || { print -u2 -r -- "axle run: docker compose couldn't start $name"; return 1 }
  _axle_run_state_init || return 1
  local sdir=$_axle_run_dir/services/$name
  mkdir -p -m 700 $sdir || return 1
  _axle_run_put $sdir root $dir
  print -rn -- "${(pj:\0:)_axle_run_cmd}" >| $sdir/cmd
  _axle_run_put $sdir kind compose
  _axle_run_put $sdir port "$_axle_run_port"
  [[ -n $_axle_run_port ]] && _axle_run_put $sdir url http://localhost:$_axle_run_port
  _axle_run_put $sdir started $EPOCHSECONDS
  _axle_run_put $sdir state up
  _axle_run_drop $name up "$_axle_run_port" "${_axle_run_port:+http://localhost:$_axle_run_port}" ''
  _axle_printp "%F{${_axle_c[ok]:-green}}⚡%f %B${name//\%/%%}%b up (docker compose)${_axle_run_port:+ on http://localhost:$_axle_run_port}  %F{${_axle_c[muted]:-244}}(axle run logs · stop)%f"
}

# --- axle run ------------------------------------------------------------------------------

_axle_cmd_run() {
  case $1 in
    ls|list)  shift; _axle_run_ls "$@"; return ;;
    stop)     shift; _axle_run_stop "$@"; return ;;
    restart)  shift; _axle_run_restart "$@"; return ;;
    logs|log) shift; _axle_run_logs "$@"; return ;;
    open)     shift; _axle_run_open "$@"; return ;;
  esac
  local dry=0 yes=0 mode='' config=0 only=0 vset=0
  local -a words=() vnames=()
  while (( $# )); do
    case $1 in
      -n|--dry-run) dry=1 ;;
      -y|--yes)     yes=1 ;;
      --fg)         mode=fg ;;
      --bg)         mode=bg ;;
      --config)     config=1 ;;
      --only)       only=1 ;;
      --verbose=*)  vset=1; vnames+=(${(s:,:)${${1#*=}// /,}}) ;;
      -v|--verbose)
        vset=1
        if [[ -n $2 && $2 != -* ]] && (( $# > 1 )); then vnames+=(${(s:,:)${2// /,}}); shift; fi ;;
      --) shift; words+=("$@"); break ;;
      -*) print -u2 -r -- "axle run: unknown option '$1' (axle help run)"; return 1 ;;
      *)  words+=("$1") ;;
    esac
    shift
  done
  vnames=(${vnames:#})
  _axle_run_pick "${words[@]}" || return 1
  local REPLY root=$_axle_run_root name=${_axle_run_root:t}
  local muted=${_axle_c[muted]:-244} accent=${_axle_c[accent]:-magenta} warn=${_axle_c[warn]:-yellow}
  local -a reply parts=()
  _axle_run_parts $root && parts=($reply)

  if (( dry )); then
    _axle_run_dry $root "${parts[@]}"
    return 0
  fi

  # Elsewhere, or a project you named: go there first.
  if [[ $_axle_run_from == last ]]; then
    # Said first when you're in a folder of your own: why it isn't the one that runs.
    if [[ $PWD != $HOME && $PWD != / ]]; then
      local -a inside=($PWD/*(DN[1,2]))
      local why='no project files'
      (( ${#inside} )) || why="it's empty"
      _axle_printp "%F{$muted}Nothing to run in ${${PWD/#$HOME/~}//\%/%%} (${why}).%f"
    fi
    _axle_run_ago ${_axle_run_when[$root]}
    _axle_printp "%F{$accent}↩%f %B${name//\%/%%}%b %F{$muted}(last worked on ${REPLY})%f"
  fi
  local from=$PWD
  [[ ${PWD:a} == $root || ${PWD:a} == $root/* ]] || cd -- $root || return 1

  if (( ! ${#parts} )); then
    print -u2 -r -- "axle run: no way to run ${name} found (looked for compose files, a Procfile, package.json"
    print -u2 -r -- "  scripts, Python apps, Cargo.toml, go.mod, a Makefile / justfile, index.html)."
    return 1
  fi

  # Which parts: the only one; else the saved choice (asked the first time, or --config).
  local -a chosen=()
  if (( ${#parts} == 1 )); then
    chosen=($parts)
    (( config )) && _axle_printp "%F{$muted}${name//\%/%%} has one runnable part: nothing to choose.%f"
  else
    local -a saved=()
    _axle_run_choice_load $root && saved=($reply)
    if (( config || ! ${#saved} )); then
      _axle_run_choose $root $parts || return 1
      chosen=($reply)
      _axle_run_choice_save $root $chosen
      (( config )) && _axle_printp "%F{$muted}Saved: axle run starts ${(j:, :)chosen} in ${name//\%/%%} (change with --config).%f"
    else
      chosen=(${saved:*parts})
      local gone
      for gone in ${saved:|parts}; do
        _axle_printp "%F{$warn}!%f saved part ${gone//\%/%%} has nothing to run any more: skipped %F{$muted}(axle run --config to choose again)%f"
      done
      if (( ! ${#chosen} )); then
        _axle_printp "%F{$warn}!%f none of the saved parts can run: choose again"
        _axle_run_choose $root $parts || return 1
        chosen=($reply)
        _axle_run_choice_save $root $chosen
      fi
    fi
  fi

  # Shown verbosely: the parts named (or, with no names, all chosen ones).
  local -a vparts=()
  local v p
  if (( vset )); then
    if (( ! ${#vnames} )); then
      vparts=($chosen)
    else
      for v in $vnames; do
        local hit=''
        for p in $parts; do
          _axle_run_partname $root $p
          [[ $v == ($REPLY|$p|${p:t}) || ( $p == . && $v == $name ) ]] && { hit=$p; break }
        done
        if [[ -z $hit ]]; then
          local -a known=()
          for p in $parts; do _axle_run_partname $root $p; known+=($REPLY); done
          print -u2 -r -- "axle run: no part '$v' in $name (parts: ${(j:, :)known})"
          return 1
        fi
        vparts+=($hit)
        (( ${chosen[(Ie)$hit]} )) || chosen+=($hit)        # named: run it even if not saved
      done
    fi
    vparts=(${(u)vparts})
  fi
  local tmux=0
  if (( ${#vparts} && ${#parts} > 1 )) && _axle_run_have_tmux; then
    tmux=1
  elif (( ${#vparts} > 1 )); then
    print -u2 -r -- "axle run: too many to show verbosely in one shell (${#vparts}): install tmux to get a session for each, or name one"
    return 1
  fi

  if [[ $_axle_run_from == last ]] && (( ! yes )); then
    local -a names=()
    for p in $chosen; do _axle_run_partname $root $p; names+=($REPLY); done
    axle_confirm "Run ${(j:, :)names}?" y
    local -i said=$?
    if (( said )); then
      cd -- $from                                  # no: you stay where you were,
      (( said == 1 )) || return 0                  # (Esc, Ctrl-C: that's all)
      _axle_run_other $root || return 0            # and may pick another project
      local -a again=()
      [[ -n $mode ]] && again+=(--$mode)
      (( config )) && again+=(--config)
      _axle_cmd_run $again -- $REPLY
      return
    fi
  fi

  # Start each part: services in the background, verbose ones in tmux; the one shown in
  # this shell (or a single task) runs last, in the foreground. A part that can't run is
  # reported, and the others still start.
  local -a failed=() sessions=() tasks=()
  local fg='' dir svc
  for p in $chosen; do
    dir=$root${${p:#.}:+/$p}
    _axle_run_partname $root $p
    _axle_run_name $dir $REPLY; svc=$REPLY
    if ! _axle_run_detect $dir; then
      _axle_printp "%F{$warn}!%f ${svc//\%/%%}: nothing to run there any more: skipped"
      failed+=($svc); continue
    fi
    if (( ${vparts[(Ie)$p]} )); then
      if (( tmux )); then
        _axle_run_ready $dir $svc $yes || { failed+=($svc); continue }
        _axle_run_say_cmd $dir
        if _axle_run_tmux $dir $svc; then sessions+=($svc); else failed+=($svc); fi
      else
        fg=$p
      fi
      continue
    fi
    (( only && ${#vparts} )) && continue
    # Already running: say so (with what you can do) rather than asking again.
    if [[ $_axle_run_kind == (service|compose) && $mode != fg ]] && _axle_run_alive $_axle_run_dir/services/$svc; then
      _axle_run_bg $dir $svc; continue
    fi
    local bg=0
    [[ $_axle_run_kind == service ]] && bg=1
    [[ $mode == fg ]] && bg=0
    [[ $mode == bg && $_axle_run_kind != compose ]] && bg=1
    if [[ $_axle_run_kind == compose ]]; then
      _axle_run_approve $dir $svc $yes || { failed+=($svc); continue }
      _axle_run_compose_up $dir $svc || failed+=($svc)
    elif (( bg )); then
      _axle_run_ready $dir $svc $yes || { failed+=($svc); continue }
      _axle_run_say_cmd $dir
      _axle_run_bg $dir $svc || failed+=($svc)
    else
      tasks+=($p)
    fi
  done
  # Foreground: the verbose part, else the one task. Several tasks can't share a shell.
  if [[ -z $fg ]] && (( ${#tasks} == 1 )); then
    fg=$tasks[1]
  elif (( ${#tasks} > 1 )); then
    for p in $tasks; do _axle_run_partname $root $p; failed+=($REPLY); done
    print -u2 -r -- "axle run: ${#tasks} parts run in the foreground (${(j:, :)tasks}); one shell holds one: use --verbose with tmux, or name one"
  fi
  if (( ${#sessions} )); then
    _axle_printp "%F{$muted}tmux sessions: ${(j:, :)sessions} (tmux attach -t <name>; Ctrl-b s to switch)%f"
  fi
  if (( ${#failed} )); then
    _axle_printp "%F{${_axle_c[error]:-red}}✘%f didn't start: ${(j:, :)failed}"
  fi
  if [[ -n $fg ]]; then
    dir=$root${${fg:#.}:+/$fg}
    _axle_run_partname $root $fg; svc=$REPLY
    _axle_run_detect $dir || return 1
    _axle_run_ready $dir $svc $yes || return 1
    _axle_run_say_cmd $dir
    _axle_run_exec $dir
    return
  fi
  (( ${#sessions} )) && _axle_run_tmux_show $sessions[1]
  (( ! ${#failed} ))
}

# --dry-run: the project, why, and for each part what would run.
_axle_run_dry() {
  local root=$1; shift
  local -a parts=("$@") saved=() reply
  local REPLY p dir name=${root:t} venv
  _axle_printp "%B${name//\%/%%}%b"
  print -r -- "  root   ${root/#$HOME/~}"
  print -r -- "  why    $_axle_run_why${_axle_run_marker:+ · marked by $_axle_run_marker}"
  if _axle_venv_find $root; then
    local found=$REPLY
    if [[ -n $VIRTUAL_ENV && ${VIRTUAL_ENV:A} != ${found:A} ]]; then
      print -r -- "  venv   ${found#$root/} (${VIRTUAL_ENV/#$HOME/~} is active: AXLE_RUN_VENV=${AXLE_RUN_VENV:-ask})"
    else
      print -r -- "  venv   ${found#$root/}"
    fi
  fi
  if (( ! ${#parts} )); then
    print -r -- "  run    ? (no way to run it found)"
    return 0
  fi
  if (( ${#parts} > 1 )); then
    _axle_run_choice_load $root && saved=($reply)
    local -a still=(${saved:*parts})               # (:* doesn't work nested)
    if (( ${#saved} )); then
      print -r -- "  parts  ${#parts}; saved choice: ${(j:, :)still} (axle run --config to change)"
    else
      print -r -- "  parts  ${#parts}; axle run asks which to start the first time"
    fi
  fi
  for p in $parts; do
    dir=$root${${p:#.}:+/$p}
    _axle_run_detect $dir || continue
    _axle_run_partname $root $p
    local svc=$REPLY ind='  '
    if (( ${#parts} > 1 )); then
      _axle_printp "  %B${svc//\%/%%}%b ${${p:#.}:+($p)}"
      ind='    '
    fi
    [[ $p != . ]] && _axle_venv_in $dir && print -r -- "${ind}venv   ${REPLY#$dir/}"
    _axle_run_show $dir
    print -r -- "${ind}run    $REPLY"
    print -r -- "${ind}how    $_axle_run_what ($_axle_run_reason)"
    case $_axle_run_kind in
      service) print -r -- "${ind}kind   service${_axle_run_port:+ on http://localhost:$_axle_run_port} (runs in the background)" ;;
      compose) print -r -- "${ind}kind   docker compose${_axle_run_port:+ (port $_axle_run_port)}: up -d, then down to stop" ;;
      *)       print -r -- "${ind}kind   task (runs in the foreground)" ;;
    esac
    _axle_run_name $dir $svc
    if _axle_run_alive $_axle_run_dir/services/$REPLY; then
      print -r -- "${ind}now    running as $REPLY (axle run ls)"
    elif [[ $_axle_run_kind == service && -n $_axle_run_port ]] && _axle_run_port_up $_axle_run_port; then
      local who='something else'
      if _axle_run_port_service $_axle_run_port; then who="your service $REPLY"
      elif _axle_run_port_holder $_axle_run_port; then who="$_axle_run_holder (pid $REPLY)"; fi
      print -r -- "${ind}port   $_axle_run_port is taken by $who: axle run would ${${_axle_run_portway:+offer the next free one}:-ask what to do}"
    fi
    _axle_run_trust_key $dir
    _axle_run_trusted $REPLY || print -r -- "${ind}trust  not run before: axle run asks first"
  done
}
