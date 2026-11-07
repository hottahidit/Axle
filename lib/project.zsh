# Projects: where one starts, what it's made of, and its virtualenv. Shared by Benzene
# (its language segments read the markers), the env module (venv switching) and
# `axle run`. Loaded when first used (_axle_lazy in lib/command.zsh), so it works with
# either part alone.

(( ${+_axle_markers} )) || typeset -gA _axle_markers     # marker file -> directory it was found in
zmodload -F zsh/stat b:zstat 2>/dev/null

# The files that mark a project's root, for `_axle_project_root`, in order of preference
# when several are in the same folder (the first one found is given as the reason).
typeset -ga _axle_root_markers=(.git pyproject.toml package.json Cargo.toml go.mod
  manage.py setup.py requirements.txt Pipfile compose.yaml compose.yml docker-compose.yml
  docker-compose.yaml Procfile deno.json Gemfile pom.xml build.gradle build.gradle.kts
  composer.json mix.exs justfile Makefile)

# A project's own venv directly in <dir> (REPLY=its path). Never runs anything in it. The
# usual names first; then, in a folder that's a project, any folder holding a pyvenv.cfg (like
# .espresso). Only in a project: a venv kept in ~/Projects isn't the venv of everything under
# it. That looks inside every folder, so its answer is kept until <dir> changes: this runs at
# every prompt.
typeset -gA _axle_venv_seen
_axle_venv_in() {
  local -a hits=($1/(.venv|venv|env|.env)/pyvenv.cfg(N)) st
  if (( ! ${#hits} )); then
    zstat -A st +mtime -- $1 2>/dev/null || { REPLY=''; return 1 }
    if [[ ${_axle_venv_seen[$1]%%:*} != $st[1] ]]; then
      hits=()
      local -a marks=($1/(${(j:|:)~${(@b)_axle_root_markers}})(N) $1/*.py(N))
      (( ${#marks} )) && hits=($1/*/pyvenv.cfg(N) $1/.*/pyvenv.cfg(N))
      _axle_venv_seen[$1]=$st[1]:
      (( ${#hits} )) && _axle_venv_seen[$1]+=${hits[1]:h}
    fi
    REPLY=${_axle_venv_seen[$1]#*:}
    [[ -n $REPLY ]]
    return
  fi
  REPLY=${hits[1]:h}
}

# The nearest project venv from <dir> (default $PWD) up to, not including, $HOME or /.
# One directly in ~ or / is a general-purpose venv, not a project's.
_axle_venv_find() {
  local dir=${1:-$PWD}
  REPLY=''
  while [[ $dir != $HOME && $dir != / && -n $dir ]]; do
    _axle_venv_in $dir && return 0
    dir=${dir:h}
  done
  REPLY=''
  return 1
}

# Find project marker files from <dir> (default $PWD) up to $HOME (or /), nearest
# directory wins. One glob (a single readdir) per level keeps this cheap even on slow
# filesystems. Fills _axle_markers (file -> folder; `venv` -> the nearest venv).
_axle_scan_markers() {
  _axle_markers=()
  local dir=${1:-$PWD} f
  local pat='package.json|.nvmrc|.node-version|pyproject.toml|requirements.txt|setup.py|Pipfile|.python-version|go.mod|Cargo.toml|.terraform|flake.nix|shell.nix|.git|.tool-versions|rust-toolchain|rust-toolchain.toml'
  [[ -n ${_axle_more_markers:-} ]] && pat+="|$_axle_more_markers"
  local -a hits
  while :; do
    hits=($dir/(${~pat})(N))
    for f in ${hits:t}; do
      (( ${+_axle_markers[$f]} )) || _axle_markers[$f]=$dir
    done
    if (( ! ${+_axle_markers[venv]} )) && [[ $dir != $HOME && $dir != / ]]; then
      _axle_venv_in $dir && _axle_markers[venv]=$REPLY
    fi
    [[ $dir == / || $dir == $HOME || -z $dir ]] && break
    dir=${dir:h}
  done
}

# Return 0 if any of the given marker files was found by _axle_scan_markers.
_axle_has_marker() {
  local f
  for f; do (( ${+_axle_markers[$f]} )) && return 0; done
  return 1
}

# The root of the project <dir> (default $PWD) is in: the nearest folder, from <dir> up
# to (not including) $HOME and /, holding one of _axle_root_markers.
#   reply=(root marker); returns 1 outside any project.
_axle_project_root() {
  local dir=${${1:-$PWD}:a} m
  reply=()
  while [[ $dir != $HOME && $dir != / && -n $dir ]]; do
    # (Files only, except .git: a folder that happens to be named Makefile isn't one.)
    local -a hits=($dir/(${(j:|:)~${(@b)_axle_root_markers}})(N^/:t) ${dir}/.git(N:t))
    if (( ${#hits} )); then
      for m in $_axle_root_markers; do
        (( ${hits[(Ie)$m]} )) && { reply=($dir $m); return 0 }
      done
    fi
    dir=${dir:h}
  done
  return 1
}
