# The `axle` command, shared by the Benzene theme and the axle tool. Each registers its
# subcommands here, so the theme alone already has `axle preview`, `axle variant`, ...,
# and loading the tool adds `axle jump`, `axle stats`, ... to the same command.
#
#   axle_command <name> <function> <group: general|theme|tool> <usage> <description>

# Both parts source this file; the second time it's already loaded (except on reload). A
# shell still running a version before lazy loading has no _axle_lazy, and its `axle reload`
# doesn't announce itself: that's a reload too, so its old functions get replaced as well.
(( ${+_axle_cmd_fn} && ! ${+functions[_axle_lazy]} )) && typeset -gi _axle_reloading=1
(( ${+_axle_cmd_fn} && ! ${_axle_reloading:-0} )) && return 0

typeset -gA _axle_cmd_fn _axle_cmd_group _axle_cmd_usage _axle_cmd_desc
typeset -g  AXLE_REPO=${AXLE_REPO:-https://github.com/hottahidit/axle}
typeset -g  AXLE_VERSION=0.2.3

axle_command() {
  _axle_cmd_fn[$1]=$2 _axle_cmd_group[$1]=$3 _axle_cmd_usage[$1]=$4 _axle_cmd_desc[$1]=$5
}

zmodload zsh/datetime 2>/dev/null
autoload -Uz add-zsh-hook

# The tool's module names (reply): the glob expands first, then the names are cut from it.
_axle_module_names() {
  local -a files=($AXLE_ROOT/modules/*.zsh(N))
  reply=(${files:t:r})
}

# Functions that load their file the first time they're called, so a shell only reads
# what it uses (help pages, settings, completion, prompts, update, ...).
#   _axle_lazy <file under AXLE_ROOT> <function>...
_axle_lazy() {
  local file=$1 fn; shift
  for fn; do
    # Already loaded for real: keep it (unless reloading, to pick up edits).
    [[ -n $functions[$fn] && $functions[$fn] != *_axle_lazy_load* ]] && (( ! ${_axle_reloading:-0} )) && continue
    functions[$fn]="_axle_lazy_load ${(q)file} $fn && $fn \"\$@\""
  done
}
_axle_lazy_load() {
  source "$AXLE_ROOT/$1" || return 1
  [[ $functions[$2] != *_axle_lazy_load* ]] || { print -u2 "axle: $1 didn't define $2"; return 1 }
}

axle() {
  # Axle's code needs these whatever your shell has set; yours come back afterwards.
  setopt localoptions noglobsubst extendedglob
  local sub=${1:-help}
  if [[ $sub == (help|-h|--help) ]]; then
    if [[ -n $2 ]]; then _axle_help_one $2; else _axle_help; fi
    return
  fi
  if (( ${+_axle_cmd_fn[$sub]} )); then
    shift
    # `axle <command> --help`: its help page (commands with their own -h keep it).
    if [[ $1 == (--help|-h) && $sub != (jump|preview) ]]; then
      _axle_help_one $sub; return
    fi
    ${_axle_cmd_fn[$sub]} "$@"
    return
  fi
  local -a reply
  _axle_did_you_mean $sub
  if (( ${#reply} )); then
    print -u2 -r -- "axle: no command '$sub' — did you mean: axle ${(j:, axle :)reply[1,3]}?"
  else
    print -u2 -r -- "axle: no command '$sub' (axle help lists them)"
  fi
  return 1
}

# Settings saved by `axle configure` (after ~/.zshrc, so they win). Both parts read it.
_axle_load_config() {
  (( ${_axle_config_loaded:-0} && ! ${_axle_reloading:-0} )) && return 0
  typeset -gi _axle_config_loaded=1
  typeset -g AXLE_CONFIG=${AXLE_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/axle/config.zsh}
  [[ -r $AXLE_CONFIG ]] && source "$AXLE_CONFIG"
  return 0
}

# Re-read whatever is loaded (tool, theme or both), so changes and new commands appear.
_axle_cmd_reload() {
  typeset -gi _axle_reloading=1
  (( ${_axle_tool_loaded:-0} ))  && source "$AXLE_ROOT/axle.plugin.zsh"
  (( ${_axle_theme_loaded:-0} )) && source "$AXLE_ROOT/benzene.zsh-theme"
  _axle_reloading=0
  return 0
}
_axle_cmd_version() {
  local loaded=()
  (( ${_axle_tool_loaded:-0} ))  && loaded+=('the axle tool')
  (( ${_axle_theme_loaded:-0} )) && loaded+=("Benzene (${AXLE_VARIANT:-nox})")
  print -r -- "Axle $AXLE_VERSION · ${(j: + :)loaded}"
}
axle_command version _axle_cmd_version general 'version' 'which version, and what is loaded'

axle_command reload _axle_cmd_reload general 'reload' 're-read Axle'\''s files (after an update or edit)'

# Step by step, for whichever parts are loaded, with a live prompt preview (in a subshell);
# reload if it saved.
_axle_cmd_configure() {
  ( source "$AXLE_ROOT/lib/configure.zsh" "$@" ) && _axle_cmd_reload
}
axle_command configure _axle_cmd_configure general 'configure' 'set Axle up step by step'

# --- update ---------------------------------------------------------------------

: ${AXLE_UPDATE_CHECK:=1}
typeset -g _axle_update_cache=${XDG_CACHE_HOME:-$HOME/.cache}/axle/update

axle_command update _axle_cmd_update general 'update [--check]' 'update Axle (git pull) and reload'

# Once a day, in the background: fetch, and remember whether a new version is out. The
# next prompt after that says so, once. Never waits on the network, never asks for a
# password (AXLE_UPDATE_CHECK=0 turns it off).
_axle_update_bg() {
  (( AXLE_UPDATE_CHECK )) && [[ -o interactive && -d $AXLE_ROOT/.git ]] || return 0
  local line=''
  [[ -r $_axle_update_cache ]] && read -r line < $_axle_update_cache
  (( EPOCHSECONDS - ${${line%% *}:-0} < 86400 )) && return 0
  command git -C $AXLE_ROOT rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1 || return 0
  mkdir -p ${_axle_update_cache:h} 2>/dev/null
  print -r -- "$EPOCHSECONDS" >| $_axle_update_cache 2>/dev/null     # other shells: already checking
  (
    GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND='ssh -o BatchMode=yes' \
      command git -C $AXLE_ROOT fetch --quiet </dev/null >/dev/null 2>&1 &&
      _axle_update_status && print -r -- "$EPOCHSECONDS $REPLY" >| $_axle_update_cache
  ) &!
}

typeset -gi _axle_update_looked=0
_axle_update_notice() {
  (( EPOCHSECONDS - _axle_update_looked >= 60 )) || return 0
  _axle_update_looked=$EPOCHSECONDS
  local line='' shown=''
  [[ -r $_axle_update_cache ]] && read -r line < $_axle_update_cache
  local version=${line#* }
  [[ $line == *' '* && -n $version && $version != $AXLE_VERSION ]] || return 0
  [[ -r $_axle_update_cache.shown ]] && read -r shown < $_axle_update_cache.shown
  if [[ $shown != $version ]]; then
    _axle_printp "%F{${_axle_c[muted]:-244}}axle $version is out (you have $AXLE_VERSION): axle update · what's new: axle update --check%f"
    print -r -- $version >| $_axle_update_cache.shown 2>/dev/null
  fi
  add-zsh-hook -d precmd _axle_update_notice
}

axle_command uninstall _axle_cmd_uninstall general 'uninstall [--yes|--purge]' 'remove Axle (asks first)'

axle_command config _axle_cmd_config general 'config [get|set|unset|edit]' 'see and change settings'

# Loaded when first used.
_axle_lazy lib/update.zsh   _axle_cmd_update _axle_cmd_uninstall _axle_update_status \
                            _axle_update_changes _axle_update_checkout_ok
_axle_lazy lib/ui.zsh       axle_select axle_checkbox axle_confirm axle_input _axle_ui_key \
                            _axle_ui_tty _axle_ui_draw _axle_ui_done _axle_ui_fit
_axle_lazy lib/help.zsh     _axle_help _axle_help_one _axle_did_you_mean _axle_distance
_axle_lazy lib/settings.zsh _axle_cmd_config _axle_setting _axle_config_value _axle_config_write
_axle_lazy lib/complete.zsh _axle_complete
_axle_lazy lib/project.zsh  _axle_scan_markers _axle_has_marker _axle_venv_in _axle_venv_find \
                            _axle_project_root

# --- compiled files ---------------------------------------------------------------

# zsh reads a file's precompiled bytecode (file.zwc) instead of the text when the .zwc is
# newer, which makes loading about twice as fast. Compile whatever is missing or older
# than its source: `_axle_compile` now, `_axle_compile bg` in the background (shell start).
_axle_compile() {
  local f built=''
  local -a stale=()
  # Bytecode only works with the zsh version that made it: after a zsh upgrade, redo all.
  [[ -r $AXLE_ROOT/.zwc-version ]] && read -r built < $AXLE_ROOT/.zwc-version
  [[ $built == $ZSH_VERSION ]] || rm -f -- $AXLE_ROOT/{*,{lib,core,modules,modules/*,benzene}/*}.zwc(N)
  for f in $AXLE_ROOT/{axle.plugin.zsh,benzene.zsh-theme,axle.zsh-theme} \
           $AXLE_ROOT/{lib,core,modules,modules/*,benzene}/*.zsh(N); do
    [[ -f $f && ! $f.zwc -nt $f ]] && stale+=($f)
  done
  # Bytecode whose source is gone (install.sh removed that part): zsh would still run it.
  for f in $AXLE_ROOT/{*,{lib,core,modules,modules/*,benzene}/*}.zwc(N); do
    [[ -e ${f%.zwc} ]] || rm -f -- $f
  done
  (( ${#stale} )) && [[ -w $AXLE_ROOT ]] || return 0
  _axle_compile_files() {
    local f
    for f; do rm -f -- $f.zwc; zcompile -R -- $f 2>/dev/null; done
    print -r -- $ZSH_VERSION >| $AXLE_ROOT/.zwc-version
  }
  if [[ $1 == bg ]]; then
    ( _axle_compile_files $stale ) &!
  else
    _axle_compile_files $stale
  fi
  return 0
}

# Tab completion. compinit may not have run yet (plugin managers, a hand-written ~/.zshrc):
# then register at the first prompt.
_axle_complete_register() {
  (( $+functions[compdef] )) || return 1
  compdef _axle_complete axle
  (( $+functions[_axle_jump_complete] )) && [[ -n $AXLE_JUMP_CMD ]] &&
    compdef _axle_jump_complete $AXLE_JUMP_CMD
  return 0
}
_axle_complete_later() {
  _axle_complete_register
  add-zsh-hook -d precmd _axle_complete_later
}
_axle_complete_register || { [[ -o interactive ]] && add-zsh-hook precmd _axle_complete_later }

# The daily update check (once per shell, whichever part loads first).
if [[ -o interactive ]] && (( ! ${+_axle_update_started} )); then
  typeset -g _axle_update_started=1
  _axle_compile bg
  _axle_update_bg
  add-zsh-hook precmd _axle_update_notice
fi
