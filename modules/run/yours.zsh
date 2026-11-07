# Your settings for `axle run` (M5 of docs/legionary/ROADMAP.md): a project's overrides,
# profiles, and the run-* hook events. Loaded when first needed.
#
# Overrides are kept in axle run's state, never in the project: the file of the project
# (or part) folder, $_axle_run_dir/projects/<hash>, next to its saved parts. KEY=value
# lines: command, port, kind, env-file, and, for a project, profile. Data only: never
# sourced. A command is split into words as the shell would split them (quotes kept), but
# nothing in it is expanded or run through a shell.
#
# Hooks (axle hook <event> <function>) fire in the shell that started the service:
#   run-start  $1 = name, $2 = folder, $3 = kind (service, task, compose)
#   run-ready  $1 = name, $2 = URL, $3 = port         (a service answers)
#   run-crash  $1 = name, $2 = exit code              (a service or task failed)
#   run-stop   $1 = name                              (it stopped or finished)
# A service's ready, crash and stop are noticed at the next prompt (no subprocess: a few
# small files read), and only while one this shell started is being watched.

typeset -g  _axle_run_dir=${_axle_run_dir:-${XDG_STATE_HOME:-$HOME/.local/state}/axle/run}
typeset -ga _axle_run_set_keys=(command port kind env-file restart needs health)
typeset -gA _axle_run_yours_cache=()
typeset -gi _axle_run_yours_loaded=0
typeset -g  _axle_run_profile=${_axle_run_profile:-}

# --- reading and writing ----------------------------------------------------------------

# All folders' settings, read once (until one is changed): folder -> lines.
_axle_run_yours_all() {
  (( _axle_run_yours_loaded )) && return 0
  _axle_run_yours_cache=()
  _axle_run_yours_loaded=1
  local f line root
  local -a keep
  for f in $_axle_run_dir/projects/*(N.); do
    root='' keep=()
    while IFS= read -r line; do
      case $line in
        root=*) root=${line#root=} ;;
        (command|port|kind|env-file|restart|needs|health|profile)=*) keep+=("$line") ;;
      esac
    done < $f
    [[ -n $root ]] && (( ${#keep} )) && _axle_run_yours_cache[$root]=${(pj:\n:)keep}
  done
}

# A folder's settings (reply: KEY=value lines).
_axle_run_yours_load() {
  _axle_run_yours_all
  reply=(${(f)_axle_run_yours_cache[$1]})
  (( ${#reply} ))
}

# One setting of a folder (REPLY); status 1 when it isn't set.
_axle_run_yours_get() {
  local -a reply
  REPLY=''
  _axle_run_yours_load $1 || return 1
  local hit=${${(M)reply:#${(b)2}=*}[1]}
  [[ -n $hit ]] || return 1
  REPLY=${hit#*=}
}

# Set one (_axle_run_yours_put <folder> <key> [value]; no value removes it).
_axle_run_yours_put() {
  local dir=$1 key=$2
  _axle_run_state_init && _axle_run_project_file $dir || return 1
  local -a lines=()
  [[ -r $_axle_run_pfile ]] && lines=(${(f)"$(<$_axle_run_pfile)"})
  lines=(${lines:#root=*})
  lines=(${lines:#${(b)key}=*})
  (( $# > 2 )) && lines+=("$key=$3")
  print -rl -- "root=$dir" $lines >| $_axle_run_pfile
  _axle_run_yours_loaded=0
}

# --- applying them (called by _axle_run_detect) ----------------------------------------------

# Which .env files a folder's run reads, in order (_axle_run_envfiles): its own (.env, or
# the env-file setting), then the profile's .env.<profile> over it.
_axle_run_yours_files() {
  local dir=$1 REPLY envf=.env
  _axle_run_yours_get $dir env-file && envf=$REPLY
  [[ $envf == /* ]] || envf=$dir/$envf
  typeset -ga _axle_run_envfiles=($envf)
  [[ -n $_axle_run_profile ]] && _axle_run_envfiles+=($dir/.env.$_axle_run_profile)
  return 0
}

# Put a folder's settings over what was detected (or over nothing: your command runs where
# nothing was found). _axle_run_yours lists the ones used. Status 0 if there's a command.
_axle_run_yours_apply() {
  local dir=$1
  local -a reply
  local -A s=()
  local l
  typeset -ga _axle_run_yours=()
  _axle_run_yours_load $dir && for l in $reply; do s[${l%%=*}]=${l#*=}; done
  # (a Procfile's other process: the folder's command, kind, port and health are its web's)
  [[ -n $_axle_run_proc_cur ]] && unset 's[command]' 's[kind]' 's[port]' 's[health]'
  if [[ -n ${s[command]} ]]; then
    local -a words=(${(Q)${(z)s[command]}})
    if (( ${#words} )); then
      [[ -z $_axle_run_kind || $_axle_run_kind == compose ]] &&
        _axle_run_kind=${${s[port]:+service}:-task}
      typeset -ga _axle_run_cmd=($words) _axle_run_env=()
      typeset -g _axle_run_what='your command' _axle_run_reason='axle run set command' \
                 _axle_run_source='' _axle_run_portway=''
      typeset -gi _axle_run_self=0
      _axle_run_yours+=(command)
    fi
  fi
  (( ${#_axle_run_cmd} )) || return 1
  [[ -n ${s[kind]} ]] && { _axle_run_kind=${s[kind]}; _axle_run_yours+=(kind) }
  if [[ -n ${s[port]} ]]; then
    # Trust is for the command as detected, whatever port it's given.
    (( ${#_axle_run_cmd_detected} )) || typeset -ga _axle_run_cmd_detected=($_axle_run_cmd)
    if [[ -z $_axle_run_portway ]] || ! _axle_run_apply_port ${s[port]}; then
      _axle_run_port=${s[port]}
    fi
    _axle_run_yours+=(port)
  fi
  [[ -n ${s[env-file]} ]] && _axle_run_yours+=(env-file)
  [[ -n ${s[restart]} ]] && { typeset -g _axle_run_onfail=${s[restart]}; _axle_run_yours+=(restart) }
  [[ -n ${s[needs]} ]] && { typeset -ga _axle_run_needs_set=(${=s[needs]}); _axle_run_yours+=(needs) }
  [[ -n ${s[health]} ]] && { typeset -g _axle_run_health=${s[health]}; _axle_run_yours+=(health) }
  return 0
}

# --- axle run set / forget ---------------------------------------------------------------

# The project you're in (REPLY), as `axle run` finds it: one with a project file, or a
# folder it can run without one (a lone index.html).
_axle_run_root_here() {
  local -a reply
  if _axle_project_root; then
    REPLY=$reply[1]
  elif [[ $PWD != $HOME && $PWD != / ]] && _axle_run_detect $PWD; then
    REPLY=${PWD:a}
  else
    print -u2 -r -- "axle run: not in a project (settings are per project: cd into one first)"
    return 1
  fi
}

# The folder whose settings `set` means (REPLY): the part you're in, else the project.
_axle_run_yours_here() {
  local -a reply
  _axle_run_root_here || return 1
  local root=$REPLY here=${PWD:a} best='' p
  _axle_run_parts $root
  for p in ${${reply:#.}:#*:*}; do
    [[ $here == $root/$p || $here == $root/$p/* ]] && (( ${#p} > ${#best} )) && best=$p
  done
  REPLY=$root${best:+/$best}
  typeset -g _axle_run_here_root=$root
}

#   axle run set                    this project's settings
#   axle run set <key> <value...>   set one: command, port, kind, env-file
#   axle run set <key>              remove it (back to what's detected)
_axle_run_set_cmd() {
  setopt localoptions extendedglob
  local REPLY dir
  _axle_run_yours_here || return 1
  dir=$REPLY
  local name=${dir:t} muted=${_axle_c[muted]:-244}
  [[ $dir != $_axle_run_here_root ]] && name="${dir:t} (part of ${_axle_run_here_root:t})"
  if (( ! $# )); then
    _axle_run_set_show $dir "$name"
    return 0
  fi
  local key=$1; shift
  if (( ! ${_axle_run_set_keys[(Ie)$key]} )); then
    print -u2 -r -- "axle run set: no setting '$key' (${(j:, :)_axle_run_set_keys}; profile: axle run --profile)"
    return 1
  fi
  if (( ! $# )); then
    _axle_run_yours_put $dir $key || return 1
    print -r -- "$name: $key back to what's detected"
    return 0
  fi
  local value
  if (( $# == 1 )); then value=$1; else value=${(j: :)${(q-)@}}; fi   # several words: kept apart
  if [[ $value == *$'\n'* ]]; then
    print -u2 -r -- "axle run set: one line only"; return 1
  fi
  case $key in
    command)
      local -a words=(${(Q)${(z)value}})
      (( ${#words} )) || { print -u2 -r -- "axle run set: which command?"; return 1 } ;;
    port)
      [[ $value == <1-65535> ]] || { print -u2 -r -- "axle run set: a port is a number from 1 to 65535"; return 1 } ;;
    kind)
      [[ $value == (service|task) ]] || { print -u2 -r -- "axle run set: kind is service (in the background) or task (in the foreground)"; return 1 } ;;
    health)
      [[ $value == /[^[:space:][:cntrl:]]# ]] || { print -u2 -r -- "axle run set: health is a path it answers on, e.g. /healthz"; return 1 } ;;
    needs)
      [[ $value == [A-Za-z0-9_.\ -]## ]] || { print -u2 -r -- "axle run set: needs is the compose services it needs, e.g. db redis"; return 1 } ;;
    restart)
      [[ $value == (on-crash|no) ]] || { print -u2 -r -- "axle run set: restart is on-crash (start it again after a crash) or no"; return 1 } ;;
    env-file)
      local f=$value; [[ $f == /* ]] || f=$dir/$f
      [[ -f $f ]] || _axle_printp "%F{${_axle_c[warn]:-yellow}}!%f ${${f/#$HOME/~}//\%/%%} doesn't exist (yet)" ;;
  esac
  _axle_run_yours_put $dir $key $value || return 1
  print -r -- "$name: $key = $value"
  [[ $key == command ]] && _axle_printp "%F{$muted}(yours, so it runs without asking; words as the shell splits them, no shell features: for those, sh -c '…')%f"
  return 0
}

# `axle run set` alone: every setting, yours (in colour), else what's detected (dimmed), else
# what it's for.
_axle_run_set_show() {
  local dir=$1 name=$2 REPLY key value
  local muted=${_axle_c[muted]:-244} accent=${_axle_c[accent]:-magenta}
  local -a reply
  local -A mine=() detected=()
  _axle_run_yours_all
  if _axle_run_yours_load $dir; then
    local l
    for l in $reply; do mine[${l%%=*}]=${l#*=}; done
  fi
  # What runs here without them (detection, quietly; nothing runs).
  typeset -g _axle_run_profile=''
  _axle_run_yours_get $_axle_run_here_root profile && _axle_run_profile=$REPLY
  if _axle_run_detect $dir 2>/dev/null; then
    detected[command]=${(j: :)${(@q-)_axle_run_cmd}}
    detected[port]=$_axle_run_port detected[kind]=$_axle_run_kind
    local -a files=(${^${_axle_run_envfiles:-$dir/.env}}(N))   # (the ones that exist)
    (( ${#files} )) && detected[env-file]=${(j:, :)${(@)files#$dir/}}
  fi
  local -A origin=(restart '(AXLE_RUN_RESTART)')
  detected[restart]=${AXLE_RUN_RESTART:-no}
  [[ -n $AXLE_RUN_RESTART ]] || origin[restart]='(the default)'
  local -A about=(
    command 'what runs'                port 'the port it listens on'
    kind 'service or task'             env-file 'its .env file'
    restart 'start it again after a crash: on-crash'
    needs 'compose services started first'   health 'a path it answers on when well'
  )
  _axle_printp "%B${name//\%/%%}%b  %F{$muted}(axle run set <setting> <value>; the setting alone: back to what's detected)%f"
  local -i cols=${COLUMNS:-80}
  (( cols > 20 )) || cols=80
  for key in command port kind env-file restart needs health; do
    if [[ -n $mine[$key] ]]; then
      value=$mine[$key]
      (( ${#value} > cols - 14 )) && value="${value[1,cols-15]}…"
      _axle_printp "  ${(r:9:)key} %F{$accent}${value//\%/%%}%f"
    elif [[ -n $detected[$key] ]]; then
      value=$detected[$key]
      (( ${#value} > cols - 25 )) && value="${value[1,cols-26]}…"
      _axle_printp "  ${(r:9:)key} %F{$muted}${value//\%/%%} ${origin[$key]:-(detected)}%f"
    else
      _axle_printp "  ${(r:9:)key} %F{$muted}–  ${about[$key]}%f"
    fi
  done
  [[ -n $_axle_run_profile ]] && _axle_printp "  ${(r:9:)${:-profile}} %F{$accent}${_axle_run_profile//\%/%%}%f %F{$muted}(axle run --profile; the project's)%f"
  return 0
}

# Forget a project: its settings, saved parts and approved commands (its parts' too).
_axle_run_forget_project() {
  local REPLY
  _axle_run_root_here || return 1
  local root=$REPLY f line r
  local -i n=0
  for f in $_axle_run_dir/projects/*(N.); do
    r=''
    while IFS= read -r line; do [[ $line == root=* ]] && { r=${line#root=}; break }; done < $f
    [[ $r == $root || $r == $root/* ]] && { command rm -f -- $f; (( n++ )) }
  done
  local trust=$_axle_run_dir/trust
  if [[ -r $trust ]]; then
    local -a keep=() all=(${(f)"$(<$trust)"})
    for line in $all; do
      r=${line%%$'\t'*}
      [[ $r == $root || $r == $root/* ]] && { (( n++ )); continue }
      keep+=($line)
    done
    print -rl -- $keep >| $trust
  fi
  _axle_run_yours_loaded=0
  if (( n )); then
    print -r -- "${root:t}: forgot its settings, saved parts and approved commands (it asks again next time)"
  else
    print -r -- "${root:t}: nothing to forget"
  fi
}

# --profile <name>: check it (REPLY = the name, or '' for none) and remember it.
_axle_run_profile_use() {
  local root=$1 want=$2; shift 2
  local -a parts=("$@")
  if [[ $want == none ]]; then
    _axle_run_yours_put $root profile && print -r -- "${root:t}: no profile (just .env)"
    REPLY=''
    return 0
  fi
  if [[ $want != [A-Za-z0-9._-]## ]]; then
    print -u2 -r -- "axle run: a profile is a name like prod or staging (for .env.<name>)"
    return 1
  fi
  local p found=''
  for p in . $parts; do [[ -f $root${${p:#.}:+/$p}/.env.$want ]] && { found=1; break }; done
  if [[ -z $found ]]; then
    local -a have=($root/.env.*(N.:t))
    print -u2 -r -- "axle run: no .env.$want in ${root:t}${have:+ (there's ${(j:, :)have})}"
    return 1
  fi
  _axle_run_yours_put $root profile $want
  REPLY=$want
}

# --- hooks ----------------------------------------------------------------------------------

typeset -gA _axle_run_watch=()

# Are any run-* hooks set? (Nothing is watched otherwise.)
_axle_run_hooked() {
  (( ${#_axle_hook_run_ready} + ${#_axle_hook_run_crash} + ${#_axle_hook_run_stop} ))
}

# A service this shell started: watch it, to fire its ready / crash / stop hooks.
_axle_run_watch_add() {
  _axle_run_hooked || return 0
  _axle_run_watch[$1]=starting
  (( ${precmd_functions[(Ie)_axle_run_watch_check]} )) || precmd_functions+=(_axle_run_watch_check)
}

# At each prompt (and right after a start): what changed for the services watched.
_axle_run_watch_check() {
  local name dir REPLY state url port
  for name in ${(k)_axle_run_watch}; do
    dir=$_axle_run_dir/services/$name
    if [[ ! -d $dir ]]; then
      unset "_axle_run_watch[$name]"
      _axle_emit run-stop $name
      continue
    fi
    _axle_run_get $dir state; state=$REPLY
    case $state in
      up)
        [[ ${_axle_run_watch[$name]} == up ]] && continue
        _axle_run_watch[$name]=up
        _axle_run_get $dir url; url=$REPLY
        _axle_run_get $dir port; port=$REPLY
        _axle_emit run-ready $name "$url" "$port" ;;
      crashed)
        unset "_axle_run_watch[$name]"
        _axle_run_get $dir code
        _axle_emit run-crash $name "$REPLY" ;;
      restarting)                                  # (a crash it comes back from: once each)
        _axle_run_get $dir restarts
        [[ ${_axle_run_watch[$name]} == restart:$REPLY ]] && continue
        _axle_run_watch[$name]=restart:$REPLY
        _axle_run_get $dir code
        _axle_emit run-crash $name "$REPLY" ;;
    esac
  done
  (( ${#_axle_run_watch} )) || precmd_functions=(${precmd_functions:#_axle_run_watch_check})
  return 0
}

# `axle run stop` in this shell: a watched service's stop fires now.
_axle_run_watch_stopped() {
  (( ${+_axle_run_watch[$1]} )) || return 0
  unset "_axle_run_watch[$1]"
  _axle_emit run-stop $1
  (( ${#_axle_run_watch} )) || precmd_functions=(${precmd_functions:#_axle_run_watch_check})
  return 0
}

# --- axle run env ------------------------------------------------------------------------

# A value to show (REPLY): masked when its name says it's secret (key, secret, token,
# password, credential, private, auth, cookie, session), and a URL's password always.
_axle_run_env_mask() {
  setopt localoptions extendedglob
  local name=$1 v=$2
  if [[ $name == (#i)*(key|secret|token|pass|pwd|credential|private|auth|cookie|session)* ]]; then
    REPLY="•••••••• (${#v} characters)"
  elif [[ $v == (#b)([a-z][a-z0-9+.-]#://[^:/@]##:)([^@]##)(@*) ]]; then
    REPLY="$match[1]••••$match[3]"
  else
    REPLY=$v
  fi
}

# axle run env [--show]: what a service here gets: its .env files in order (a later one's
# value replaces an earlier one's), what axle run adds, and the venv. Secrets masked
# (--show: as they are).
_axle_run_env_cmd() {
  local REPLY show=0 a
  for a; do [[ $a == --show ]] && show=1; done
  _axle_run_yours_here || return 1
  local dir=$REPLY root=$_axle_run_here_root muted=${_axle_c[muted]:-244} accent=${_axle_c[accent]:-magenta}
  typeset -g _axle_run_profile=''
  _axle_run_yours_get $root profile && _axle_run_profile=$REPLY
  _axle_run_detect $dir
  local name=${dir:t}
  _axle_printp "%B${name//\%/%%}%b %F{$muted}gets (${_axle_run_kind:-nothing detected}${_axle_run_profile:+, profile $_axle_run_profile}; --show: secrets too)%f"
  local f e key
  local -A seen=()
  local -a reply files=(${_axle_run_envfiles:-$dir/.env})
  local -i width=0 any=0
  for f in $files; do
    _axle_run_envfile $f || continue
    for e in $reply; do key=${e%%=*}; (( ${#key} > width )) && width=${#key}; done
  done
  for e in $_axle_run_env PORT=; do key=${e%%=*}; (( ${#key} > width )) && width=${#key}; done
  for f in $files; do
    if ! _axle_run_envfile $f; then
      [[ -e $f ]] || continue
    fi
    any=1
    _axle_printp "  %F{${_axle_c[path]:-cyan}}${${f/#$dir\//}//\%/%%}%f"
    for e in $reply; do
      key=${e%%=*}
      if (( show )); then REPLY=${e#*=}; else _axle_run_env_mask $key "${e#*=}"; fi
      local note=''
      (( ${+seen[$key]} )) && note="  (over ${seen[$key]})"
      seen[$key]=${f:t}
      _axle_printp "    ${(r:width:)key//\%/%%}  ${REPLY//\%/%%}%F{$muted}${note//\%/%%}%f"
    done
  done
  (( any )) || _axle_printp "  %F{$muted}no .env file%f"
  # What axle run adds.
  local -a ours=()
  [[ $_axle_run_kind == service && -n $_axle_run_port ]] && ours+=(PORT=$_axle_run_port)
  for e in $_axle_run_env; do
    [[ $e == PYTHONPATH=$AXLE_ROOT/modules/run/py* ]] && e="PYTHONPATH=(axle run's port hook, first)"
    ours+=($e)
  done
  if (( ${#ours} )); then
    _axle_printp "  %F{$accent}axle run%f"
    for e in $ours; do
      key=${e%%=*}
      _axle_printp "    ${(r:width:)key//\%/%%}  ${${e#*=}//\%/%%}"
    done
  fi
  # The venv.
  if _axle_venv_find $dir && [[ -x $REPLY/bin/python ]]; then
    _axle_printp "  %F{$accent}venv%f ${${REPLY/#$HOME/~}//\%/%%} %F{$muted}(its bin/ first on PATH, VIRTUAL_ENV)%f"
  fi
  return 0
}
