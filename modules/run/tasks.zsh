# axle run :<task>: a project's other commands, the same words in every project.
#
#   axle run :              the tasks here (and where each comes from)
#   axle run :test          run one, in the foreground, in the project's folder and venv
#   axle run :test -k api   with these words after it
#   axle run :test --yes    don't ask
#
# Read as text from (the first one with a name wins): package.json scripts (npm, pnpm,
# yarn, bun), a justfile, a Makefile, pyproject.toml's [project.scripts], and the standard
# ones of Cargo (build, test, check, clippy, fmt, run) and Go (build, test, vet, run), and
# pytest's (test) when the project uses it. Nothing in the project runs to find them.
# The first time a task's command runs here it's shown and asked, like `axle run` (and
# again when what it comes from changes: the script, or the justfile / Makefile).

# The tasks of <dir>: _axle_run_tasks (name → command words, shell-quoted),
# _axle_run_task_from (name → where from), _axle_run_task_src (name → its text, for trust),
# _axle_run_task_order (names, as found).
_axle_run_tasks_find() {
  setopt localoptions extendedglob
  local dir=$1 REPLY line name pm=npm body
  typeset -gA _axle_run_tasks=() _axle_run_task_from=() _axle_run_task_src=()
  typeset -ga _axle_run_task_order=()
  _axle_run_task_add() {                           # <name> <from> <source text> <words...>
    local n=$1 from=$2 src=$3; shift 3
    (( ${+_axle_run_tasks[$n]} )) && return
    _axle_run_tasks[$n]=${(j: :)${(q)@}} _axle_run_task_from[$n]=$from _axle_run_task_src[$n]=$src
    _axle_run_task_order+=($n)
  }
  # package.json scripts.
  if _axle_run_pkg_scripts $dir/package.json; then
    _axle_run_diag_pm $dir; pm=$REPLY              # (its package manager, from the lockfile)
    for name in $_axle_run_pkg_order; do
      # (prestart, postbuild: npm runs those around start and build itself)
      [[ $name == (pre|post)* ]] && (( ${+_axle_run_pkg[${name#(pre|post)}]} )) && continue
      _axle_run_pkg_text $name
      _axle_run_task_add $name "package.json ($pm)" "$REPLY" $pm run $name
    done
  fi
  # A justfile's recipes.
  local -a found=($dir/(#i)justfile(N[1]))
  local jf=$found[1]
  if [[ -n $jf ]] && _axle_run_read $jf; then
    local text=$REPLY
    for line in ${(f)text}; do
      [[ $line =~ '^@?([A-Za-z_][A-Za-z0-9_-]*)[^:]*:([^=]|$)' ]] || continue
      _axle_run_task_add $match[1] ${jf:t} "$text" just $match[1]
    done
  fi
  # A Makefile's targets (not .PHONY and the like, not pattern rules, not variables).
  found=($dir/(GNUmakefile|Makefile|makefile)(N[1]))
  local mf=$found[1]
  if [[ -n $mf ]] && _axle_run_read $mf; then
    local text=$REPLY
    for line in ${(f)text}; do
      [[ $line =~ '^([A-Za-z0-9][A-Za-z0-9_.-]*)[[:space:]]*:([^=]|$)' ]] || continue
      _axle_run_task_add $match[1] ${mf:t} "$text" make $match[1]
    done
  fi
  # pyproject.toml's [project.scripts]: the programs it installs (in its venv).
  if _axle_run_read $dir/pyproject.toml; then
    local in=0
    for line in ${(f)REPLY}; do
      if [[ $line == \[*\]* ]]; then [[ $line == '[project.scripts]'* ]] && in=1 || in=0; continue; fi
      (( in )) || continue
      [[ $line =~ '^[[:space:]]*"?([A-Za-z0-9_.-]+)"?[[:space:]]*=' ]] || continue
      _axle_run_task_add $match[1] 'pyproject.toml [project.scripts]' '' $match[1]
    done
  fi
  # Cargo and Go: their own commands.
  if [[ -f $dir/Cargo.toml ]]; then
    for name in build test check clippy fmt run; do _axle_run_task_add $name cargo '' cargo $name; done
  fi
  if [[ -f $dir/go.mod ]]; then
    for name in build test vet; do _axle_run_task_add $name go '' go $name ./...; done
    _axle_run_task_add run go '' go run .
  fi
  # pytest, when the project uses it.
  if [[ -f $dir/pytest.ini || -f $dir/conftest.py || -d $dir/tests ]] ||
     { _axle_run_read $dir/pyproject.toml && [[ $REPLY == *'[tool.pytest'* ]] }; then
    [[ -f $dir/pyproject.toml || -f $dir/setup.py || -f $dir/requirements.txt || -n $dir/*.py(#qN[1]) ]] &&
      _axle_run_task_add test pytest '' python -m pytest
  fi
  unfunction _axle_run_task_add
  (( ${#_axle_run_task_order} ))
}

# axle run : · axle run :<task> [words...] [--yes]
_axle_run_task_cmd() {
  local task=${1#:} REPLY; shift
  local -i yes=0
  local -a args=()
  local a
  for a; do
    case $a in
      --yes|-y)   yes=1 ;;
      --quiet|-q) local AXLE_RUN_QUIET=1 ;;
      *)          args+=($a) ;;
    esac
  done
  _axle_run_yours_here || return 1
  local dir=$REPLY name=${REPLY:t} muted=${_axle_c[muted]:-244}
  if ! _axle_run_tasks_find $dir; then
    print -u2 -r -- "axle run: no tasks in $name (package.json scripts, a justfile, a Makefile, pyproject scripts, cargo, go, pytest)"
    return 1
  fi
  if [[ -z $task ]]; then                          # the list, under where each comes from
    local n from=''
    _axle_printp "%B${name//\%/%%}%b  %F{$muted}(axle run :<task> [words...])%f"
    local -i width=0
    for n in $_axle_run_task_order; do (( ${#n} > width )) && width=${#n}; done
    for n in $_axle_run_task_order; do
      if [[ ${_axle_run_task_from[$n]} != $from ]]; then
        from=${_axle_run_task_from[$n]}
        _axle_printp "  %F{$muted}${from//\%/%%}%f"
      fi
      local -a words=(${(Q)${(z)_axle_run_tasks[$n]}})
      _axle_printp "    %F{${_axle_c[accent]:-magenta}}:${(r:width:)n//\%/%%}%f  ${${(j: :)${(@q-)words}}//\%/%%}"
    done
    return 0
  fi
  if (( ! ${+_axle_run_tasks[$task]} )); then
    local -a near=()
    for a in $_axle_run_task_order; do                # (a typo, or part of one)
      _axle_distance $task $a
      [[ $a == *$task* || $task == *$a* ]] || (( REPLY <= (${#task} > 4 ? 2 : 1) )) && near+=(:$a)
    done
    print -u2 -r -- "axle run: no task '$task' in $name${near:+ (did you mean ${(j:, :)near}?)} · axle run : lists them"
    return 1
  fi
  local -a words=(${(Q)${(z)_axle_run_tasks[$task]}})
  if (( ${#args} )); then
    [[ $words[1] == npm ]] && words+=(--)          # (npm passes words on after --)
    words+=($args)
  fi
  # As axle run would: what runs, asked the first time (the task's text in the trust key).
  typeset -ga _axle_run_cmd=($words) _axle_run_cmd_detected=(${(Q)${(z)_axle_run_tasks[$task]}}) _axle_run_env=() _axle_run_yours=()
  typeset -g _axle_run_kind=task _axle_run_port='' _axle_run_what=":$task" \
             _axle_run_reason="${_axle_run_task_from[$task]}" _axle_run_source="${_axle_run_task_src[$task]}" \
             _axle_run_use_venv=''
  typeset -ga _axle_run_envfiles=($dir/.env)
  _axle_run_state_init
  _axle_run_approve $dir $name $yes || return 1
  _axle_run_show $dir
  _axle_run_quiet || _axle_printp "%F{$muted}▶ ${REPLY//\%/%%}%f"
  _axle_run_exec $dir
  local -i code=$?
  (( code && code != 130 && code != 143 )) && _axle_run_explain $dir '' "axle run :$task"
  return code
}
