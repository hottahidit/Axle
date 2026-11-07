# axle run sh / exec: a shell, or one command, with what a service gets: in its folder,
# its .env files' values (and its profile's), axle run's (PORT), and its venv. For
# migrations, a REPL, a one-off script: they see what the server sees.
#
#   axle run sh [name]               a shell (yours: $SHELL), here's or that service's
#   axle run exec [-s name] <cmd...> one command (its exit status)
#
# Here: the project (or part) you're in, as `axle run` detects it. With a name: a running
# service, as it was started. Your own command runs: nothing from the project does, so
# nothing is asked (.env files are read as data, never sourced).

# What a shell gets (reply: NAME=value..., REPLY: the venv or -; _axle_run_sh_dir,
# _axle_run_sh_name): of service <name>, else of here.
_axle_run_sh_env() {
  local name=$1 dir sdir e f
  local -a envs=() files=()
  if [[ -n $name ]]; then
    _axle_run_which $name || return 1
    name=$REPLY sdir=$_axle_run_dir/services/$REPLY
    _axle_run_get $sdir root; dir=$REPLY
    [[ -d $dir ]] || { print -u2 -r -- "axle run: $name's folder is gone"; return 1 }
    if [[ -r $sdir/envfiles ]]; then _axle_run_words $sdir/envfiles; files=($reply)
    else files=($dir/.env); fi
    for f in $files; do _axle_run_envfile $f && envs+=($reply); done
    [[ -r $sdir/env ]] && { _axle_run_words $sdir/env; envs+=($reply) }
    _axle_run_get $sdir port && envs+=(PORT=$REPLY)
    _axle_run_get $sdir venv; local venv=$REPLY
    [[ -z $venv ]] && _axle_venv_find $dir && venv=$REPLY
  else
    _axle_run_yours_here || return 1
    dir=$REPLY name=${REPLY:t}
    typeset -g _axle_run_profile=''
    _axle_run_yours_get $_axle_run_here_root profile && _axle_run_profile=$REPLY
    _axle_run_detect $dir 2>/dev/null
    _axle_run_dotenv $dir && envs=($reply)
    envs+=(${_axle_run_env:#PYTHONPATH=$AXLE_ROOT/modules/run/py*})   # (not the port hook)
    [[ $_axle_run_kind == service && -n $_axle_run_port ]] && envs+=(PORT=$_axle_run_port)
    local venv=-
    _axle_venv_find $dir && [[ -x $REPLY/bin/python ]] && venv=$REPLY
  fi
  typeset -g _axle_run_sh_dir=$dir _axle_run_sh_name=$name
  reply=($envs) REPLY=${venv:--}
}

# axle run sh [name]
_axle_run_sh_cmd() {
  [[ $1 == -* ]] && { print -u2 -r -- "axle run sh: $1? (axle run sh [name])"; return 1 }
  local REPLY
  local -a reply
  _axle_run_sh_env "$1" || return 1
  local -a envs=($reply)
  local venv=$REPLY sh=${SHELL:-zsh} muted=${_axle_c[muted]:-244}
  local -a keys=(${envs%%=*})
  _axle_run_quiet ||
    _axle_printp "%F{$muted}── a shell with what ${_axle_run_sh_name//\%/%%} gets${keys:+: ${(j:, :)${(u)keys}//\%/%%}}${${venv:#-}:+, its venv} (exit to leave)%f"
  ( cd -- $_axle_run_sh_dir || exit 1
    local e
    for e in $envs; do export "$e"; done
    _axle_run_enter_venv $venv
    export AXLE_RUN_SHELL=$_axle_run_sh_name       # (for your prompt: which one you're in)
    exec $sh -i )
}

# axle run exec [-s name] [--] <command...>
_axle_run_exec_cmd() {
  local name=''
  while (( $# )); do
    case $1 in
      -s) [[ -n $2 ]] || { print -u2 -r -- "axle run exec: -s needs a service's name"; return 1 }
          name=$2; shift 2 ;;
      --) shift; break ;;
      -*) print -u2 -r -- "axle run exec: $1? (axle run exec [-s name] <command...>)"; return 1 ;;
      *)  break ;;
    esac
  done
  (( $# )) || { print -u2 -r -- "axle run exec: which command? (axle run exec python manage.py migrate)"; return 1 }
  local REPLY
  local -a reply
  _axle_run_sh_env "$name" || return 1
  local -a envs=($reply)
  local venv=$REPLY
  ( cd -- $_axle_run_sh_dir || exit 1
    local e
    for e in $envs; do export "$e"; done
    _axle_run_enter_venv $venv
    exec "$@" )
}
