# The `axle` command, shared by the Benzene theme and the axle tool. Each registers its
# subcommands here, so the theme alone already has `axle preview`, `axle variant`, ...,
# and loading the tool adds `axle jump`, `axle stats`, ... to the same command.
#
#   axle_command <name> <function> <group: general|theme|tool> <usage> <description>

typeset -gA _axle_cmd_fn _axle_cmd_group _axle_cmd_usage _axle_cmd_desc
typeset -g  AXLE_REPO=${AXLE_REPO:-https://github.com/hottahidit/axle}
typeset -g  AXLE_VERSION=0.1.3

axle_command() {
  _axle_cmd_fn[$1]=$2 _axle_cmd_group[$1]=$3 _axle_cmd_usage[$1]=$4 _axle_cmd_desc[$1]=$5
}

axle() {
  local sub=${1:-help}
  if (( ${+_axle_cmd_fn[$sub]} )); then
    shift
    ${_axle_cmd_fn[$sub]} "$@"
    return
  fi
  _axle_help
  [[ $sub == (help|-h|--help) ]] && return 0
  print -u2 "axle: unknown command '$sub'"
  return 1
}

_axle_help() {
  local group name title
  local -A titles=(general 'axle' theme 'Benzene, the prompt' tool 'axle, the tool')
  for group in general theme tool; do
    local -a names=()
    for name in ${(ok)_axle_cmd_group}; do
      [[ $_axle_cmd_group[$name] == $group ]] && names+=($name)
    done
    (( ${#names} )) || continue
    [[ $group == general ]] || { print; _axle_printp "%B${titles[$group]}%b" }
    for name in $names; do
      print -r -- "  axle ${(r:26:)${_axle_cmd_usage[$name]:-$name}} $_axle_cmd_desc[$name]"
    done
  done
  if (( ! ${_axle_tool_loaded:-0} )); then
    print
    print -r -- "More with the axle tool: smart suggestions, jump, history search, automatic"
    if [[ -r $AXLE_ROOT/axle.plugin.zsh ]]; then
      print -r -- "venvs, stats, doctor. It's installed: add axle to plugins=(...), or source axle.plugin.zsh."
    elif [[ -e $AXLE_ROOT/.git ]]; then
      print -r -- "venvs, stats, doctor. Run $AXLE_ROOT/install.sh again and choose it."
    else
      print -r -- "venvs, stats, doctor. Get it with a fresh copy of Axle: $AXLE_REPO"
    fi
  fi
}

# Settings saved by `axle configure` (after ~/.zshrc, so they win). Both parts read it.
_axle_load_config() {
  typeset -g AXLE_CONFIG=${AXLE_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/axle/config.zsh}
  [[ -r $AXLE_CONFIG ]] && source "$AXLE_CONFIG"
}

# Re-read whatever is loaded (tool, theme or both), so changes and new commands appear.
_axle_cmd_reload() {
  (( ${_axle_tool_loaded:-0} ))  && source "$AXLE_ROOT/axle.plugin.zsh"
  (( ${_axle_theme_loaded:-0} )) && source "$AXLE_ROOT/benzene.zsh-theme"
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

# `axle update`: pull the latest version (if Axle is a git checkout), then reload.
_axle_cmd_update() {
  if ! command git -C $AXLE_ROOT rev-parse --git-dir >/dev/null 2>&1; then
    print -r -- "axle: $AXLE_ROOT isn't a git checkout; reinstall from $AXLE_REPO"
    return 1
  fi
  if ! command git -C $AXLE_ROOT rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    print -r -- "axle: this checkout has no upstream to update from (clone it from $AXLE_REPO)"
    return 1
  fi
  local before=$(command git -C $AXLE_ROOT rev-parse HEAD)
  command git -C $AXLE_ROOT pull --ff-only --quiet || {
    print -u2 "axle: update failed (local changes? see: git -C $AXLE_ROOT status)"; return 1 }
  local after=$(command git -C $AXLE_ROOT rev-parse HEAD)
  if [[ $before == $after ]]; then
    print -r -- "axle is up to date"
  else
    print -r -- "updated:"
    command git -C $AXLE_ROOT log --oneline --no-decorate $before..$after | sed 's/^/  /'
    _axle_cmd_reload
  fi
}

axle_command update _axle_cmd_update general 'update' 'update Axle (git pull) and reload'
