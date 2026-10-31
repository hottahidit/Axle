# axle preview — see and test every state of the prompt, drawn in your own terminal
# (your font, palette and settings), using the real rendering code with faked situations.
#
#   axle preview                      interactive viewer (← → to step through scenarios)
#   axle preview --all                print every scenario, one after another
#   axle preview --list               list scenario names
#   axle preview <name>...            print just those scenarios
#
# Options for the printed forms: --axon  --expanded  --nerd  --plain  --classic  --width N
#
# Git states come from real throwaway repositories (created under $TMPDIR, deleted on exit),
# so they show exactly what the git worker produces. Everything else (exit codes, run time,
# sudo, RAM, battery, SSH, root, production contexts, AI status, vi mode) is faked.
# The `axle` command runs this in a subshell, so nothing here touches your live prompt.

setopt extendedglob

typeset -g  _pv_dir='' _pv_cmd='git status'
typeset -ga _pv_names=() _pv_titles=() _pv_jobs=()
typeset -gi _pv_expanded=0 _pv_width=0 _pv_ruler=0 _pv_altscreen=0

_pv_add() { _pv_names+=($1); _pv_titles+=("$2") }

# --- throwaway repositories ----------------------------------------------------

_pv_setup() {
  _pv_dir=$(mktemp -d "${TMPDIR:-/tmp}/axle-preview.XXXXXX") || return 1
  # Deterministic git: none of your config (signing, hooks, templates) applies here.
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_TERMINAL_PROMPT=0
  export GIT_AUTHOR_NAME=Axle GIT_AUTHOR_EMAIL=axle@example.com
  export GIT_COMMITTER_NAME=Axle GIT_COMMITTER_EMAIL=axle@example.com
  # A throwaway home, so paths read ~/repos/<scenario> and your own configs stay out of it (but caches still go to the real one).
  export XDG_CACHE_HOME=${XDG_CACHE_HOME:-$HOME/.cache} HOME=$_pv_dir/home
  mkdir -p $HOME/repos
  {
    cd $HOME/repos
    _pv_repo() { git init -q -b main $1 && git -C $1 commit -q --allow-empty -m init }

    _pv_repo clean
    _pv_repo dirty;  print a > dirty/notes.md; git -C dirty add notes.md
                     git -C dirty commit -qm notes; print b >> dirty/notes.md; print c > dirty/todo.txt
    _pv_repo staged; print a > staged/app.py; git -C staged add app.py; git -C staged commit -qm app
                     print b >> staged/app.py; git -C staged add app.py; print c > staged/new.py

    # ahead 2, behind 1, one stash
    git init -q --bare -b main origin.git
    git clone -q origin.git sync 2>/dev/null; git -C sync commit -q --allow-empty -m base
    git -C sync push -q origin main 2>/dev/null
    git clone -q origin.git other 2>/dev/null; git -C other commit -q --allow-empty -m theirs
    git -C other push -q origin main 2>/dev/null
    git -C sync fetch -q; git -C sync commit -q --allow-empty -m mine1; git -C sync commit -q --allow-empty -m mine2
    print x > sync/wip; git -C sync add wip; git -C sync stash -q

    # mid-rebase with a conflict
    _pv_repo rebase; print 1 > rebase/f; git -C rebase add f; git -C rebase commit -qm one
    git -C rebase checkout -q -b feature/login HEAD~1; print 2 > rebase/f; git -C rebase add f
    git -C rebase commit -qm two; git -C rebase rebase main >/dev/null 2>&1

    # detached at a tag
    _pv_repo detached; git -C detached tag v1.2.0; git -C detached checkout -q --detach

    # a Python + Node project with an active-looking venv
    _pv_repo project; print '{}' > project/package.json; : > project/pyproject.toml
    mkdir -p project/.venv/bin; ln -s ${commands[python3]:-/usr/bin/python3} project/.venv/bin/python
    print -l 'home = /usr/bin' "prompt = 'shop-api'" > project/.venv/pyvenv.cfg

    cd $_pv_dir
    ( cd $HOME/repos && _pv_repo pinned && print '{}' > pinned/package.json && print 20 > pinned/.nvmrc )
    mkdir -p kube power/BAT0 full/BAT0
    print -l 'contexts:' '- context:' '    cluster: c' '    namespace: payments' '  name: eks-prod' \
             'current-context: eks-prod' > kube/prod
    print -l 'contexts:' '- context:' '    cluster: c' '  name: dev-cluster' \
             'current-context: dev-cluster' > kube/dev
    print 12 > power/BAT0/capacity; print Discharging > power/BAT0/status
    print 100 > full/BAT0/capacity; print Full > full/BAT0/status
  } >/dev/null 2>&1
  cd $HOME/repos/clean
}

_pv_cleanup() {
  [[ -n $_pv_dir && -d $_pv_dir/tmux-$UID ]] && TMUX_TMPDIR=$_pv_dir command tmux kill-server 2>/dev/null
  (( _pv_altscreen )) && print -n '\e[?25h\e[?1049l'   # restore the screen and cursor
  _pv_altscreen=0
  (( ${#_pv_jobs} )) && kill $_pv_jobs 2>/dev/null
  [[ $_pv_dir == */axle-preview.* && -d $_pv_dir ]] && rm -rf -- $_pv_dir
}

# --- scenarios ------------------------------------------------------------------
# Each starts from _pv_reset (a clean repo, nothing wrong) and changes what it needs.

_pv_reset() {
  cd $HOME/repos/clean
  unset SSH_CONNECTION SSH_TTY VIRTUAL_ENV CONDA_DEFAULT_ENV AWS_PROFILE AWS_VAULT AWS_REGION \
        AWS_DEFAULT_REGION CLOUDSDK_CORE_PROJECT GOOGLE_CLOUD_PROJECT DOCKER_HOST TF_WORKSPACE IN_NIX_SHELL
  export KUBECONFIG=$_pv_dir/kube/none DOCKER_CONTEXT=default     # hide your real contexts
  export TMUX_TMPDIR=$_pv_dir/no-tmux; unset TMUX                  # ...and your real tmux
  (( ${#_pv_jobs} )) && { kill $_pv_jobs 2>/dev/null; wait 2>/dev/null; _pv_jobs=() }
  _axle_last_status=() _axle_elapsed=0 _axle_mem_used=40 _axle_sudo_until=0
  _axle_uid=1000 _axle_keymap=main _axle_vscode=0 _axle_detail=$_pv_expanded
  _axle_power_glob="$_pv_dir/full/BAT*"
  if (( ${+_axle_ai_state} )); then
    local entry; local -a reply
    for entry in $AXLE_AI_STATUS; do
      _axle_ai_resolve $entry && (( ${#reply} )) && _axle_ai_state[$reply[1]]=up
    done
  fi
}

_pv_add home        'Home directory, nothing to report'
_pv_s_home()        { cd ~ }
_pv_add clean       'Clean repository'
_pv_s_clean()       { : }
_pv_add dirty       'Uncommitted changes (modified + untracked)'
_pv_s_dirty()       { cd $HOME/repos/dirty }
_pv_add staged      'Staged and unstaged changes'
_pv_s_staged()      { cd $HOME/repos/staged }
_pv_add sync        'Ahead 2, behind 1, one stash'
_pv_s_sync()        { cd $HOME/repos/sync }
_pv_add rebase      'Mid-rebase with a conflict, last command failed'
_pv_s_rebase()      { cd $HOME/repos/rebase; _axle_last_status=(1); _axle_elapsed=0.2 }
_pv_add detached    'Detached HEAD at a tag'
_pv_s_detached()    { cd $HOME/repos/detached }
_pv_add slow        'Slow command (12.4 s), succeeded'
_pv_s_slow()        { _axle_last_status=(0); _axle_elapsed=12.4 }
_pv_add failed      'Failed command (exit 1)'
_pv_s_failed()      { _axle_last_status=(1); _axle_elapsed=0.03 }
_pv_add pipeline    'Failed pipeline stage (0|1|0)'
_pv_s_pipeline()    { _axle_last_status=(0 1 0); _axle_elapsed=1.2 }
_pv_add interrupt   'Slow command interrupted with Ctrl-C (130)'
_pv_s_interrupt()   { _axle_last_status=(130); _axle_elapsed=42 }
_pv_add sudo        'sudo credentials cached (14 minutes left)'
_pv_s_sudo()        { _axle_sudo_until=$(( EPOCHSECONDS + 840 )) }
_pv_add sudo-last   'sudo in its last minute (42 s left)'
_pv_s_sudo-last()   { _axle_sudo_until=$(( EPOCHSECONDS + 42 )) }
_pv_add ssh         'Over SSH'
_pv_s_ssh()         { export SSH_CONNECTION='10.0.0.2 52000 10.0.0.1 22' }
_pv_add root        'Running as root'
_pv_s_root()        { _axle_uid=0 }
_pv_add windows     'On a Windows drive (WSL /mnt/c)'
_pv_s_windows()     { if [[ -d /mnt/c ]]; then cd /mnt/c; else _axle_wsl=1; cd /; fi }
_pv_add project     'Python + Node project, venv active'
_pv_s_project()     { cd $HOME/repos/project; export VIRTUAL_ENV=$HOME/repos/project/.venv }
_pv_add prod        'Production kube context + AWS profile (alarms)'
_pv_s_prod()        { export KUBECONFIG=$_pv_dir/kube/prod AWS_PROFILE=production AWS_REGION=eu-west-1 }
_pv_add battery     'Battery at 12%, discharging'
_pv_s_battery()     { _axle_power_glob="$_pv_dir/power/BAT*" }
_pv_add ram         'Memory pressure (86% RAM)'
_pv_s_ram()         { _axle_mem_used=86 }
_pv_add vicmd       'vi command mode'
_pv_s_vicmd()       { _axle_keymap=vicmd }
_pv_add jobs        'Two background jobs'
_pv_s_jobs()        { sleep 600 & _pv_jobs+=($!); sleep 600 & _pv_jobs+=($!) }
_pv_add toolchain   'Project pins Node 20, a different version is active'
_pv_s_toolchain()   { cd $HOME/repos/pinned }
_pv_add venv-off    'Project venv not activated'
_pv_s_venv-off()    { cd $HOME/repos/project }
_pv_add venv-other  'A venv active outside its project'
_pv_s_venv-other()  { export VIRTUAL_ENV=$HOME/repos/project/.venv; cd $HOME/repos/clean }
_pv_add tmux        'Detached tmux sessions waiting (outside tmux)'
_pv_s_tmux()        {
  (( $+commands[tmux] )) || return
  export TMUX_TMPDIR=$_pv_dir
  if ! command tmux has-session 2>/dev/null; then
    command tmux new-session -d -s build 'sleep 3600'; command tmux new-session -d -s logs 'sleep 3600'
  fi
  _axle_cache[tmux.at]=0                          # ask now, not in 30 s
}
_pv_add ai-down     'AI service down (expanded view)'
_pv_s_ai-down()     {
  _axle_detail=1
  (( ${+_axle_ai_state} )) && _axle_ai_state[${${AXLE_AI_STATUS[1]%%=*}:-claude}]=down
}
_pv_add crowded     'Crowded: many contexts at once, trimmed to (+N)'
_pv_s_crowded()     {
  cd $HOME/repos/project; export VIRTUAL_ENV=$HOME/repos/project/.venv KUBECONFIG=$_pv_dir/kube/dev
  export AWS_PROFILE=staging CLOUDSDK_CORE_PROJECT=demo-project DOCKER_CONTEXT=remote-builder
  _axle_last_status=(1); _axle_elapsed=3.2
}
_pv_add vscode      'VS Code terminal layout'
_pv_s_vscode()      { cd $HOME/repos/dirty; _axle_vscode=1 }

# --- drawing --------------------------------------------------------------------

# Draw one scenario as zsh would: the prompt, a sample command, and its compact past form.
_pv_show() {
  local name=$1 title=$2
  _pv_reset
  _pv_s_$name
  local -i saved=$COLUMNS
  (( _pv_width )) && COLUMNS=$_pv_width
  _axle_scan_markers
  _axle_seg[git]=$(_axle_git_compute); _axle_git_pwd=$PWD
  _axle_render
  if (( _pv_ruler || _pv_width )); then
    _axle_printp "%F{${_axle_c[sep]:-238}}${(l:COLUMNS-1::┄:)}┤%f"
  fi
  _axle_printp -n "$_axle_ps1"; print -r -- "$_pv_cmd"
  _axle_compact_line
  _axle_printp -n "%F{${_axle_c[muted]:-244}}  past: %f$REPLY"; print -r -- "$_pv_cmd"
  COLUMNS=$saved
}

_pv_status() {
  local icons=plain; (( AXLE_NERD_FONT )) && icons='Nerd Font'
  print -r -- "${AXLE_VARIANT:-nox} · ${AXLE_PALETTE:-mocha} · $icons icons · $(( _pv_width ? _pv_width : COLUMNS )) cols${${_pv_expanded:#0}:+ · expanded}"
}

_pv_reload() { _axle_load_variant ${AXLE_VARIANT:-nox} >/dev/null }

_pv_print() {
  local -i i
  for i in {1..${#_pv_names}}; do
    (( ${#@} )) && (( ! ${@[(Ie)$_pv_names[i]]} )) && continue
    _axle_printp "%B${(l:2:)i}. ${_pv_titles[i]//\%/%%}%b  %F{${_axle_c[muted]:-244}}($_pv_names[i])%f"
    _pv_show $_pv_names[i] $_pv_titles[i]
    print
  done
}

_pv_interactive() {
  local -i i=1 n=${#_pv_names}
  local key k2 k3
  print -n '\e[?1049h\e[?25l'                         # alternate screen, hide cursor
  _pv_altscreen=1                                     # _pv_cleanup restores it
  while :; do
    print -n '\e[H\e[2J'
    _axle_printp "%B Axle preview%b  %F{${_axle_c[muted]:-244}}$(_pv_status)%f"
    _axle_printp "%F{${_axle_c[sep]:-238}}${(l:COLUMNS-1::─:)}%f"
    _axle_printp " %B$i/$n%b  ${_pv_titles[i]//\%/%%}  %F{${_axle_c[muted]:-244}}($_pv_names[i])%f"
    print
    _pv_show $_pv_names[i] $_pv_titles[i]
    print
    _axle_printp "%F{${_axle_c[sep]:-238}}${(l:COLUMNS-1::─:)}%f"
    _axle_printp "%F{${_axle_c[muted]:-244}} ←→ scenario  v variant  e expand  i icons  c palette  [ ] width  r ruler  q quit%f"
    read -rsk key || break
    if [[ $key == $'\e' ]]; then                       # arrow keys: ESC [ C / ESC [ D
      read -rsk -t 0.05 k2; read -rsk -t 0.05 k3; key+=$k2$k3
    fi
    case $key in
      $'\e[C'|l|n|' ') (( i = i % n + 1 )) ;;
      $'\e[D'|h|p)     (( i = (i + n - 2) % n + 1 )) ;;
      v) [[ ${AXLE_VARIANT:-nox} == nox ]] && AXLE_VARIANT=axon || AXLE_VARIANT=nox; _pv_reload ;;
      e) (( _pv_expanded ^= 1 )) ;;
      i) (( AXLE_NERD_FONT ^= 1 )); _pv_reload ;;
      c) [[ $AXLE_PALETTE == classic ]] && AXLE_PALETTE=mocha || AXLE_PALETTE=classic; _axle_load_palette ;;
      '[') (( _pv_width = (_pv_width ? _pv_width : COLUMNS) - 5, _pv_width < 30 && (_pv_width = 30) )) ;;
      ']') (( _pv_width = (_pv_width ? _pv_width : COLUMNS) + 5 )); (( _pv_width >= COLUMNS )) && _pv_width=0 ;;
      0) _pv_width=0 ;;
      r) (( _pv_ruler ^= 1 )) ;;
      q|$'\e'|$'\C-c') break ;;
    esac
  done
}

# --- main -----------------------------------------------------------------------

_pv_main() {
  local -a only
  local mode=interactive
  while (( $# )); do
    case $1 in
      --all)      mode=print ;;
      --list)     mode=list ;;
      --axon)     AXLE_VARIANT=axon ;;
      --nox)      AXLE_VARIANT=nox ;;
      --expanded) _pv_expanded=1 ;;
      --nerd)     AXLE_NERD_FONT=1 ;;
      --plain)    AXLE_NERD_FONT=0 ;;
      --classic)  AXLE_PALETTE=classic ;;
      --width)    _pv_width=$2; shift ;;
      -h|--help)  sed -n '2,13s/^# \{0,1\}//p' ${(%):-%x}; return ;;
      -*)         print -u2 "axle preview: unknown option $1"; return 1 ;;
      *)          only+=($1); mode=print ;;
    esac
    shift
  done
  if [[ $mode == list ]]; then
    local -i i
    for i in {1..${#_pv_names}}; do print -r -- "${(r:12:)_pv_names[i]} $_pv_titles[i]"; done
    return
  fi
  local name
  for name in $only; do
    (( ${_pv_names[(Ie)$name]} )) || { print -u2 "axle preview: no scenario '$name' (see --list)"; return 1 }
  done
  (( $+functions[_axle_render] )) || { print -u2 "axle preview: the Axle theme isn't loaded"; return 1 }
  trap _pv_cleanup EXIT
  trap '_pv_cleanup; exit 130' INT TERM HUP      # Ctrl-C or a closed window: clean up
  _pv_setup || { print -u2 "axle preview: couldn't create a temporary directory"; return 1 }
  _pv_reload
  if [[ $mode == print ]]; then
    _axle_printp "%B$(_pv_status)%b"; print
    _pv_print $only
  elif [[ -t 0 && -t 1 ]]; then
    _pv_interactive
  else
    print -u2 "axle preview: not a terminal; use --all"
    return 1
  fi
}


# `source preview.zsh --lib` loads the scenarios without running (axle configure uses them).
if [[ $1 != --lib ]]; then
  trap _pv_cleanup EXIT     # at the top level, so it runs however the subshell exits
  _pv_main "$@"
fi
