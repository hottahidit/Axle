# env: when you cd into a project with its own virtualenv (.venv, venv, env), it's
# activated; when you leave (or enter a project with a different one), it's switched or
# deactivated. A venv you activated yourself is left alone.
#
# It never runs the venv's `activate` script (a cloned repository could ship one that does
# anything). It does what activation actually means: sets VIRTUAL_ENV and puts the venv's
# bin/ first on PATH, and undoes exactly that when you leave.
#
#   AXLE_ENV_QUIET=0    1 = don't print a line when it switches
#
# `deactivate` works as with a venv you activated: it leaves the venv, which stays off
# until you leave its project (entering it again turns it back on).

: ${AXLE_ENV_QUIET:=0}
typeset -g _axle_env_auto=''               # the venv this module activated (if any)
typeset -g _axle_env_off=''                # the venv you turned off with `deactivate`
# A shell started from one where this module had turned a venv on (`exec zsh`, a nested
# shell) inherits VIRTUAL_ENV: it's still ours to switch, not one you activated by hand.
if [[ -n $VIRTUAL_ENV && $VIRTUAL_ENV == ${AXLE_ENV_AUTO:-} ]]; then
  _axle_env_auto=$VIRTUAL_ENV
  (( $+functions[deactivate] )) || deactivate() { _axle_env_deactivate_cmd "$@" }
fi

# The nearest project venv from $PWD up to (not including) $HOME or / (lib/project.zsh).
_axle_env_find() { _axle_venv_find $PWD }

_axle_env_say() {
  (( AXLE_ENV_QUIET )) || _axle_printp "%F{${_axle_c[muted]:-244}}axle: ${1//\%/%%}%f"
}

_axle_env_activate() {
  typeset -gx VIRTUAL_ENV=$1
  path=($1/bin ${path:#$1/bin})
  unset PYTHONHOME
  _axle_env_auto=$1
  typeset -gx AXLE_ENV_AUTO=$1
  # `deactivate`, as `activate` would have given you (unless something else defines one).
  (( $+functions[deactivate] )) || deactivate() { _axle_env_deactivate_cmd "$@" }
  rehash
}

_axle_env_deactivate() {
  path=(${path:#$_axle_env_auto/bin})
  [[ $VIRTUAL_ENV == $_axle_env_auto ]] && unset VIRTUAL_ENV
  _axle_env_auto=''
  unset AXLE_ENV_AUTO
  [[ $functions[deactivate] == *_axle_env_deactivate_cmd* ]] && unfunction deactivate
  rehash
}

# `deactivate` for a venv this module turned on.
_axle_env_deactivate_cmd() {
  if [[ -z $_axle_env_auto || $VIRTUAL_ENV != $_axle_env_auto ]]; then
    unfunction deactivate
    print -u2 -r -- "deactivate: no venv is active"
    return 1
  fi
  # (A venv's own activate script starts with `deactivate nondestructive`: just make way.)
  [[ $1 == nondestructive ]] && { _axle_env_deactivate; return 0 }
  _axle_env_name $_axle_env_auto; local name=$REPLY
  _axle_env_off=$_axle_env_auto
  _axle_env_deactivate
  _axle_env_say "left the $name venv (it comes back when you enter the project again)"
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
  # Turned off with `deactivate`: stays off while you're in its project.
  if [[ -n $_axle_env_off ]]; then
    [[ $want == $_axle_env_off ]] && return
    _axle_env_off=''
  fi
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
