# Projects with several runnable parts: a frontend and
# a backend, npm / pnpm workspaces, a Cargo workspace, apps/*, services/*. Which parts to
# start is asked the first time (or with --config) and saved per project; --verbose shows
# chosen parts' output: each in its own tmux session, or one in this shell.
# Loaded when first needed.

# Runnable parts of a project (reply): "." for the root itself, else folders relative to
# it (one level down, and inside apps/, packages/, services/, crates/), and a Procfile's
# other processes as <folder>:<process> (.:worker). Detection results of the last part
# checked are left behind; detect a part again before using it.
_axle_run_parts() {
  setopt localoptions extendedglob
  local root=$1 dir proc
  local -a found=() cands
  if _axle_run_detect $root; then
    found=(.)
    [[ $_axle_run_kind == compose ]] && { reply=($found); return 0 }   # compose runs it all
    [[ $_axle_run_what == Procfile* ]] && for proc in $_axle_run_procs; do found+=(.:$proc); done
  fi
  cands=($root/^(.*|node_modules|venv|env|dist|build|target|vendor|docs|doc|tests|test|examples|__pycache__|public|static|assets|src|lib|apps|packages|services|crates)(N/)
         $root/(apps|packages|services|crates)/^.*(N/))
  for dir in ${cands[1,40]}; do
    [[ $dir == *[[:cntrl:]]* ]] && continue        # (a name with a newline: never a part)
    _axle_venv_in ${dir:h} && [[ $REPLY == $dir ]] && continue
    [[ -e $dir/pyvenv.cfg ]] && continue           # a venv
    # A Python package of the project, with no project file of its own, isn't a part.
    [[ -e $dir/__init__.py && -z $dir/(pyproject.toml|requirements.txt|setup.py|Pipfile|package.json|manage.py)(#qN[1]) ]] && continue
    if _axle_run_detect $dir; then
      found+=(${dir#$root/})
      [[ $_axle_run_what == Procfile* ]] && for proc in $_axle_run_procs; do found+=(${dir#$root/}:$proc); done
    fi
  done
  reply=($found)
  (( ${#reply} ))
}

# The git checkout <dir> is in (reply: the project's main checkout, this checkout's top
# folder, its branch or ''), from the .git files alone (no git). A worktree's .git is a
# file: "gitdir: <main>/.git/worktrees/<w>" (or <main>.git/worktrees/<w>, a bare repo).
_axle_run_checkout() {
  setopt localoptions extendedglob
  # (:A, symlinks resolved: git writes the real path, and macOS's /var is /private/var)
  local d=${1:A} line gd head=''
  reply=()
  while [[ ! -e $d/.git ]]; do
    [[ $d == / || $d == ${HOME:A} ]] && return 1
    d=${d:h}
  done
  if [[ -d $d/.git ]]; then
    [[ -r $d/.git/HEAD ]] && IFS= read -r head < $d/.git/HEAD
    reply=($d $d ${${(M)head:#ref: refs/heads/*}#ref: refs/heads/})
    return 0
  fi
  IFS= read -r line < $d/.git 2>/dev/null && [[ $line == 'gitdir: '* ]] || return 1
  gd=${line#gitdir: }; [[ $gd == /* ]] || gd=${d}/$gd
  gd=${gd:A}
  [[ $gd == */worktrees/[^/]## ]] || { reply=($d $d ''); return 0 }   # (a submodule)
  [[ -r $gd/HEAD ]] && IFS= read -r head < $gd/HEAD
  local main=${gd:h:h}                             # <main>/.git, or <main>.git (bare)
  if [[ ${main:t} == .git ]]; then main=${main:h}; else main=${main%.git}; fi
  reply=($main $d ${${(M)head:#ref: refs/heads/*}#ref: refs/heads/})
}

# The name a project goes by (REPLY): its folder's. A second checkout of it (a git
# worktree): the main checkout's folder @ its branch (shop@feature-x; detached: @ its
# folder), so two checkouts of one project don't share names.
_axle_run_projname() {
  setopt localoptions extendedglob
  local root=${1:A}
  local -a reply
  REPLY=${root:t}
  _axle_run_checkout $root || return 0
  [[ $reply[1] == $reply[2] || $reply[2] != $root ]] && return 0   # (the main one, or inside)
  REPLY=${reply[1]:t}@${${reply[3]:-${root:t}}//\//-}
}

# A part's service name (REPLY): the project's name, then the part's (and its Procfile
# process: shop-worker, shop-api-worker).
_axle_run_partname() {
  local root=$1 part=${2%%:*} proc=${2#*:}
  [[ $2 == *:* ]] || proc=''
  _axle_run_projname $root
  [[ $part != . ]] && REPLY+=-${part:t}
  REPLY=${REPLY//[^A-Za-z0-9._@-]/-}${proc:+-${proc//[^A-Za-z0-9._-]/-}}
}

# A part's folder (REPLY), and its Procfile process for the next detection
# (_axle_run_proc: `_axle_run_detect` takes it and clears it).
_axle_run_part_dir() {
  local root=$1 part=${2%%:*}
  typeset -g _axle_run_proc=''
  [[ $2 == *:* ]] && _axle_run_proc=${2#*:}
  REPLY=$root${${part:#.}:+/$part}
}

# --- the saved choice -------------------------------------------------------------------
# $_axle_run_dir/projects/<hash of the root>: KEY=value lines, data only. part=<folder>,
# one line per part chosen.

_axle_run_project_file() {
  local REPLY
  # (its file is lines: a folder with a newline in its name could write one of its own,
  # command=..., so a name with control characters is refused)
  [[ $1 == *[[:cntrl:]]* ]] && { print -u2 -r -- "axle run: a folder name with control characters (a newline...): not saved"; return 1 }
  _axle_run_hash $1 || return 1
  typeset -g _axle_run_pfile=$_axle_run_dir/projects/$REPLY
}

_axle_run_choice_load() {
  reply=()
  _axle_run_project_file $1 || return 1
  [[ -r $_axle_run_pfile ]] || return 1
  local line
  while IFS= read -r line; do
    [[ $line == part=?* ]] && reply+=(${line#part=})
  done < $_axle_run_pfile
  (( ${#reply} ))
}

_axle_run_choice_save() {
  local root=$1; shift
  [[ "$*" == *[[:cntrl:]]* ]] && return 1
  _axle_run_state_init && _axle_run_project_file $root || return 1
  local -a other=()
  [[ -r $_axle_run_pfile ]] && other=(${(f)"$(<$_axle_run_pfile)"})
  other=(${${other:#part=*}:#root=*})              # (other settings stay)
  print -rl -- "root=$root" $other "${@/#/part=}" >| $_axle_run_pfile
}

# Ask which parts to start (reply), with the saved ones (or all) ticked. Without a
# terminal, the ticked ones.
_axle_run_choose() {
  local root=$1; shift
  local -a parts=("$@") on=() opts=() saved=()
  _axle_run_choice_load $root && saved=($reply)
  on=(${saved:*parts}); (( ${#on} )) || on=($parts)
  local p REPLY
  for p in $parts; do
    _axle_run_part_dir $root $p
    _axle_run_detect $REPLY
    _axle_run_partname $root $p
    local label="$REPLY  (${${p:#.}:-the root}) · $_axle_run_what"
    [[ $_axle_run_kind == service && -n $_axle_run_port ]] && label+=" :$_axle_run_port"
    opts+=("$label:$p")
  done
  axle_checkbox "Which parts of ${root:t} should axle run start?" "$on" $opts || return 1
  (( ${#reply} )) || { print -u2 -r -- "axle run: nothing chosen"; return 1 }
}

# --- tmux ---------------------------------------------------------------------------------

_axle_run_have_tmux() { whence -p tmux >/dev/null }

# Start the detected command of part <dir> as tmux session <name>: its venv, .env and
# port given as the session's environment (tmux -e), the command as words (no shell).
# The session stays open after the program ends, so its output can still be read.
_axle_run_tmux() {
  local dir=$1 name=$2 REPLY
  if command tmux has-session -t "=$name" 2>/dev/null; then
    _axle_printp "%F{${_axle_c[muted]:-244}}tmux session $name already exists (tmux attach -t $name)%f"
    return 0
  fi
  local -a envs=() reply
  local use=${_axle_run_use_venv:--}
  if [[ $use != - ]]; then
    local -a p=(${path:#$VIRTUAL_ENV/bin})
    envs+=(-e VIRTUAL_ENV=$use -e "PATH=$use/bin:${(j.:.)p}")
  fi
  [[ -n $_axle_run_port ]] && envs+=(-e PORT=$_axle_run_port)
  local e
  _axle_run_dotenv $dir && for e in $reply; do envs+=(-e $e); done
  for e in $_axle_run_env; do envs+=(-e $e); done
  # Through a small sh that holds the session open when the program ends, so its output
  # stays readable (remain-on-exit loses it). The words are arguments, never re-parsed.
  command tmux new-session -d -s $name -c $dir $envs -- sh -c \
    '"$@"; st=$?; printf "\n[%s exited with code %s; Enter closes this session]\n" "$1" "$st"; read _' \
    axle-run "${_axle_run_cmd[@]}" >/dev/null || {
      print -u2 -r -- "axle run: tmux couldn't start $name (tmux 3.2 or later is needed)"
      return 1
    }
}

# Show the first of the sessions just started (switch to it inside tmux, attach outside).
_axle_run_tmux_show() {
  _axle_ui_tty || return 0
  if [[ -n $TMUX ]]; then
    command tmux switch-client -t "=$1"
  else
    command tmux attach-session -t "=$1"
  fi
}
