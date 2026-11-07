# axle run deps: install the project's Python packages, into a venv shared by many
# projects when they fit it, else into its own.
#
# A shared venv ("uni-venv") is a folder's .venv used by the projects under it that have
# none of their own: ~/Projects/.venv for everything in ~/Projects. They pick it up
# already (a venv in a folder above counts, see lib/project.zsh); AXLE_RUN_UNIVENV names
# the folders where `axle run deps` makes one when there's none yet.
#
# Installing into it never changes what's there: pip gets the shared venv's installed
# versions as constraints, so a project that needs other versions fails to resolve
# instead of breaking the projects that use them. Then it gets its own .venv, installed
# there, which it uses from then on (a project's own venv comes first).
#
#   axle run deps              requirements.txt, else pyproject.toml's dependencies
#   axle run deps flask ...    and these
#
# What runs is said first: pip, in the project's folder (a package's own setup runs then,
# as with any pip install; it's what you asked for).

# The folder in AXLE_RUN_UNIVENV that holds <dir> (REPLY; the deepest one).
_axle_run_unifolder() {
  local dir=${1:a} f best=''
  for f in ${=AXLE_RUN_UNIVENV}; do
    f=${${f/#\~/$HOME}:a}
    [[ $f == $HOME || $f == / ]] && continue     # (not one for everything)
    [[ $dir == $f/* ]] && (( ${#f} > ${#best} )) && best=$f
  done
  REPLY=$best
  [[ -n $best ]]
}

# Is <venv> one that <dir>'s project shares with others: in a folder above its project,
# or a uni-venv folder's?
_axle_run_venv_shared() {
  local dir=$1 venv=$2 root=$1 REPLY
  local -a reply
  _axle_project_root $dir && root=$reply[1]
  _axle_run_unifolder $dir && [[ $venv == $REPLY/.venv ]] && return 0
  [[ $root == ${venv:h}/* ]]
}

# The packages a project lists (reply): -r requirements.txt, else pyproject.toml's
# [project] dependencies, read as text.
_axle_run_deps_list() {
  local dir=$1 line in=0 deps=''
  reply=()
  if [[ -f $dir/requirements.txt ]]; then reply=(-r requirements.txt); return 0; fi
  [[ -r $dir/pyproject.toml ]] || return 1
  while IFS= read -r line; do
    if [[ $line == \[*\]* ]]; then
      (( in == 2 )) && break
      [[ $line == '[project]'* ]] && in=1 || in=0
      continue
    fi
    if (( in == 1 )) && [[ $line =~ '^[[:space:]]*dependencies[[:space:]]*=[[:space:]]*\[(.*)' ]]; then
      deps=$match[1]; in=2
      [[ $deps == *\]* ]] && { deps=${deps%%\]*}; break }
    elif (( in == 2 )); then
      [[ $line == *\]* ]] && { deps+=" ${line%%\]*}"; break }
      deps+=" $line"
    fi
  done < $dir/pyproject.toml
  local q='["'"'"']([^"'"'"']+)["'"'"']'
  while [[ $deps =~ $q ]]; do reply+=($match[1]); deps=${deps[MEND+1,-1]}; done
  (( ${#reply} ))
}

# Make a venv at <path> (python3 -m venv).
_axle_run_mkvenv() {
  local py=python3
  (( $+commands[python3] )) || py=python
  _axle_printp "%F{${_axle_c[muted]:-244}}▶ $py -m venv ${${1/#$HOME/~}//\%/%%}%f"
  command $py -m venv -- $1 && return 0
  print -u2 -r -- "axle run: $py -m venv failed (on Debian / Ubuntu: sudo apt install python3-venv)"
  return 1
}

# The installed versions in <venv> as pip constraints, into file <out>.
_axle_run_venv_pins() {
  local f nv
  local -a pins=()
  for f in $1/lib/python*/site-packages/*.dist-info(N/); do
    nv=${${f:t}%.dist-info}
    pins+=("${nv%-*}==${nv##*-}")
  done
  print -rl -- $pins >| $2
}

# pip install <args> with <venv>'s pip, in <dir>; its output also to <log>.
_axle_run_pip() {
  local dir=$1 venv=$2 log=$3 a; shift 3
  local -a shown=()
  for a; do
    [[ $shown[-1] == -c ]] && { shown+=('<its versions>'); continue }
    shown+=(${(q-)a})
  done
  _axle_printp "%F{${_axle_c[muted]:-244}}▶ ${${venv/#$HOME/~}//\%/%%}/bin/pip install ${(j: :)shown//\%/%%}%f"
  ( cd -- $dir && command $venv/bin/pip install "$@" 2>&1 ) | command tee -- $log
  return ${pipestatus[1]}
}

_axle_run_deps() {
  setopt localoptions extendedglob
  local REPLY dir
  local -a reply
  _axle_run_yours_here || return 1
  dir=$REPLY
  local name=${dir:t} muted=${_axle_c[muted]:-244}
  if [[ -f $dir/uv.lock ]] && (( $+commands[uv] )) && (( ! $# )); then
    _axle_printp "%F{$muted}▶ uv sync%f  %F{$muted}(uv keeps the project's own venv)%f"
    ( cd -- $dir && command uv sync )
    return
  fi
  local -a spec=()
  _axle_run_deps_list $dir && spec=($reply)
  spec+=("$@")
  if (( ! ${#spec} )); then
    print -u2 -r -- "axle run: $name lists no packages (no requirements.txt or dependencies in pyproject.toml)"
    return 1
  fi
  _axle_run_state_init
  local log=$_axle_run_dir/deps.$$.log cons=$_axle_run_dir/deps.$$.pins venv='' shared=0
  local -i st
  if _axle_venv_find $dir && [[ -x $REPLY/bin/python ]]; then
    venv=$REPLY
    _axle_run_venv_shared $dir $venv && shared=1
  elif _axle_run_unifolder $dir; then
    venv=$REPLY/.venv shared=1
    if [[ ! -e $venv/pyvenv.cfg ]]; then
      _axle_printp "%F{$muted}the shared venv for ${${REPLY/#$HOME/~}//\%/%%} (AXLE_RUN_UNIVENV) doesn't exist yet:%f"
      _axle_run_mkvenv $venv || return 1
    fi
  fi
  if (( shared )); then
    # Keep what's installed as it is: a project that needs other versions gets its own.
    _axle_run_venv_pins $venv $cons
    _axle_printp "%F{$muted}into the shared venv ${${venv/#$HOME/~}//\%/%%}, keeping its versions%f"
    _axle_run_pip $dir $venv $log -c $cons $spec; st=$?
    command rm -f -- $cons
    if (( st )) && [[ $(<$log) == (#i)*(ResolutionImpossible|conflict is caused by|conflicting dependencies)* ]]; then
      _axle_printp "%F{${_axle_c[warn]:-yellow}}→%f its versions conflict with the shared venv's, so ${name//\%/%%} gets its own: .venv"
      venv=$dir/.venv
      [[ -e $venv/pyvenv.cfg ]] || _axle_run_mkvenv $venv || { command rm -f -- $log; return 1 }
      _axle_run_pip $dir $venv $log $spec; st=$?
    fi
  else
    if [[ -z $venv ]]; then
      venv=$dir/.venv
      _axle_run_mkvenv $venv || return 1
    fi
    _axle_run_pip $dir $venv $log $spec; st=$?
  fi
  command rm -f -- $log
  (( st )) && return st
  _axle_printp "%F{${_axle_c[ok]:-green}}✔%f installed into ${${venv/#$HOME/~}//\%/%%}"
}
