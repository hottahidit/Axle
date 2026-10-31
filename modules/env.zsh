# env: when you cd into a project with its own virtualenv (.venv, venv, env), it's
# activated; when you leave (or enter a project with a different one), it's switched or
# deactivated. A venv you activated yourself is left alone.
#
# It never runs the venv's `activate` script (a cloned repository could ship one that does
# anything). It does what activation actually means: sets VIRTUAL_ENV and puts the venv's
# bin/ first on PATH, and undoes exactly that when you leave.
#
#   AXLE_ENV_QUIET=0    1 = don't print a line when it switches

: ${AXLE_ENV_QUIET:=0}
typeset -g _axle_env_auto=''               # the venv this module activated (if any)

# The nearest project venv from $PWD up to (not including) $HOME or /.
_axle_env_find() {
  local dir=$PWD
  local -a hits
  REPLY=''
  while [[ $dir != $HOME && $dir != / ]]; do
    hits=($dir/(.venv|venv|env|.env)/pyvenv.cfg(N))
    (( ${#hits} )) && { REPLY=${hits[1]:h}; return 0 }
    dir=${dir:h}
  done
  return 1
}

_axle_env_say() {
  (( AXLE_ENV_QUIET )) || _axle_printp "%F{${_axle_c[muted]:-244}}axle: ${1//\%/%%}%f"
}

_axle_env_activate() {
  typeset -gx VIRTUAL_ENV=$1
  path=($1/bin ${path:#$1/bin})
  unset PYTHONHOME
  _axle_env_auto=$1
  rehash
}

_axle_env_deactivate() {
  path=(${path:#$_axle_env_auto/bin})
  [[ $VIRTUAL_ENV == $_axle_env_auto ]] && unset VIRTUAL_ENV
  _axle_env_auto=''
  rehash
}

_axle_env_name() {
  setopt localoptions extendedglob
  local line
  REPLY=${1:t}
  [[ $REPLY == (.venv|venv|env|.env) ]] && REPLY=${1:h:t}
  [[ -r $1/pyvenv.cfg ]] && while IFS= read -r line; do
    [[ $line == prompt[[:space:]]#=* ]] && { REPLY=${${${line#*=}## #}//[\'\"]/}; break }
  done < $1/pyvenv.cfg
}

# On every directory change (and at startup): make the active venv match the folder.
_axle_env_sync() {
  # A venv activated by hand (not by us): yours to manage.
  [[ -n $VIRTUAL_ENV && $VIRTUAL_ENV != $_axle_env_auto ]] && return
  local want=''
  _axle_env_find && want=$REPLY
  [[ $want == $_axle_env_auto ]] && return
  if [[ -n $_axle_env_auto ]]; then
    _axle_env_name $_axle_env_auto; local old=$REPLY
    _axle_env_deactivate
    [[ -z $want ]] && _axle_env_say "left the $old venv"
  fi
  if [[ -n $want ]]; then
    _axle_env_activate $want
    _axle_env_name $want
    _axle_env_say "using the $REPLY venv"
  fi
}

_axle_hook_cmd dir _axle_env_sync
_axle_env_sync
