# The `axle` command, shared by the Benzene theme and the axle tool. Each registers its
# subcommands here, so the theme alone already has `axle preview`, `axle variant`, ...,
# and loading the tool adds `axle jump`, `axle stats`, ... to the same command.
#
#   axle_command <name> <function> <group: general|theme|tool> <usage> <description>

typeset -gA _axle_cmd_fn _axle_cmd_group _axle_cmd_usage _axle_cmd_desc
typeset -g  AXLE_REPO=${AXLE_REPO:-https://github.com/hottahidit/axle}
typeset -g  AXLE_VERSION=0.2.0

axle_command() {
  _axle_cmd_fn[$1]=$2 _axle_cmd_group[$1]=$3 _axle_cmd_usage[$1]=$4 _axle_cmd_desc[$1]=$5
}

zmodload zsh/datetime 2>/dev/null
autoload -Uz add-zsh-hook

axle() {
  local sub=${1:-help}
  if [[ $sub == (help|-h|--help) ]]; then
    if [[ -n $2 ]]; then _axle_help_one $2; else _axle_help; fi
    return
  fi
  if (( ${+_axle_cmd_fn[$sub]} )); then
    shift
    # `axle <command> --help`: its help page (commands with their own -h keep it).
    if [[ $1 == (--help|-h) && -n ${_axle_cmd_help[$sub]} && $sub != (jump|preview) ]]; then
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
      local usage=${_axle_cmd_usage[$name]:-$name}
      if (( ${COLUMNS:-80} < 72 )); then     # narrow: the description on its own line
        print -r -- "  axle $usage"
        _axle_printp "      %F{${_axle_c[muted]:-244}}${_axle_cmd_desc[$name]//\%/%%}%f"
      else
        print -r -- "  axle ${(r:30:)usage} $_axle_cmd_desc[$name]"
      fi
    done
  done
  print
  _axle_printp "%F{${_axle_c[muted]:-244}}axle help <command> for its options and examples; Tab completes everything.%f"
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

: ${AXLE_UPDATE_CHECK:=1}
typeset -g _axle_update_cache=${XDG_CACHE_HOME:-$HOME/.cache}/axle/update

# Is a newer version upstream (as last fetched)? REPLY = its version.
_axle_update_status() {
  local -a g=(command git -C $AXLE_ROOT)
  local -i behind=$($g rev-list --count 'HEAD..@{u}' 2>/dev/null)
  (( behind )) || return 1
  local line
  for line in "${(@f)$($g show '@{u}:lib/command.zsh' 2>/dev/null)}"; do
    [[ $line == 'typeset -g  AXLE_VERSION='* ]] && { REPLY=${line#*=}; return 0 }
  done
  REPLY="$behind new commits"
}

# The changelog sections newer than this version, from <rev> (printed, indented).
_axle_update_changes() {
  local line
  local -i on=0
  for line in "${(@f)$(command git -C $AXLE_ROOT show "$1:CHANGELOG.md" 2>/dev/null)}"; do
    if [[ $line == '## '* ]]; then
      [[ $line == "## $AXLE_VERSION"* ]] && break
      on=1
    fi
    (( on )) && print -r -- "  $line"
  done
}

_axle_update_checkout_ok() {
  if ! command git -C $AXLE_ROOT rev-parse --git-dir >/dev/null 2>&1; then
    print -r -- "axle: $AXLE_ROOT isn't a git checkout; reinstall from $AXLE_REPO"
    return 1
  fi
  if ! command git -C $AXLE_ROOT rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    print -r -- "axle: this checkout has no upstream to update from (clone it from $AXLE_REPO)"
    return 1
  fi
}

# `axle update [--check]`: pull the latest version (if Axle is a git checkout), then reload.
_axle_cmd_update() {
  _axle_update_checkout_ok || return 1
  if [[ $1 == --check ]]; then
    GIT_TERMINAL_PROMPT=0 command git -C $AXLE_ROOT fetch --quiet </dev/null ||
      { print -u2 "axle: couldn't reach the repository"; return 1 }
    if _axle_update_status; then
      print -r -- "axle $REPLY is out (you have $AXLE_VERSION). What's new:"
      _axle_update_changes '@{u}'
      print -r -- "axle update installs it."
      mkdir -p ${_axle_update_cache:h} 2>/dev/null
      print -r -- "$EPOCHSECONDS $REPLY" >| $_axle_update_cache 2>/dev/null
    else
      print -r -- "axle is up to date ($AXLE_VERSION)"
    fi
    return 0
  fi
  local before=$(command git -C $AXLE_ROOT rev-parse HEAD) was=$AXLE_VERSION
  command git -C $AXLE_ROOT pull --ff-only --quiet || {
    print -u2 "axle: update failed (local changes? see: git -C $AXLE_ROOT status)"; return 1 }
  local after=$(command git -C $AXLE_ROOT rev-parse HEAD)
  if [[ $before == $after ]]; then
    print -r -- "axle is up to date ($AXLE_VERSION)"
  else
    _axle_cmd_reload
    print -r -- "updated: $was → $AXLE_VERSION"
    local changes=$(AXLE_VERSION=$was _axle_update_changes HEAD)
    if [[ -n $changes ]]; then print -r -- $changes
    else command git -C $AXLE_ROOT log --oneline --no-decorate $before..$after | sed 's/^/  /'; fi
    print -r -- "$EPOCHSECONDS" >| $_axle_update_cache 2>/dev/null
  fi
}

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

# --- uninstall ------------------------------------------------------------------

_axle_cmd_uninstall() {
  local mode=ask
  case $1 in --yes|-y) mode=yes ;; --purge) mode=purge ;; '') ;; *)
    print -u2 "usage: axle uninstall [--yes | --purge]"; return 1 ;; esac
  local custom=${ZSH_CUSTOM:-${ZSH:+$ZSH/custom}} f
  local -a links=() reply
  for f in $custom/plugins/axle $custom/themes/benzene.zsh-theme $custom/themes/axle.zsh-theme; do
    [[ -n $custom && -L $f && ${f:A} == $AXLE_ROOT(|/*) ]] && links+=($f)
  done
  local data=${XDG_DATA_HOME:-$HOME/.local/share}/axle cache=${XDG_CACHE_HOME:-$HOME/.cache}/axle
  local -a remove=()
  if [[ $mode == ask ]]; then
    if (( ${#links} )); then
      print -r -- "Links install.sh made:"; print -rl -- "  "${^links/#$HOME/~}
      axle_confirm "Remove them?" y || links=()
    fi
    local -a opts=()
    [[ -e $AXLE_CONFIG ]] && opts+=("settings — ${AXLE_CONFIG/#$HOME/~}:config")
    [[ -d $data ]]        && opts+=("recorded history — ${data/#$HOME/~}:history")
    [[ -d $cache ]]       && opts+=("cache — ${cache/#$HOME/~}:cache")
    if (( ${#opts} )); then
      axle_checkbox "Also delete:" cache $opts || return 1
      remove=($reply)
    fi
  else
    remove=(cache)
    [[ $mode == purge ]] && remove+=(config history)
  fi
  (( ${#links} )) && rm -f -- $links && print -r -- "removed the links"
  if (( ${remove[(Ie)config]} )) && [[ -f $AXLE_CONFIG ]]; then
    rm -f -- $AXLE_CONFIG && print -r -- "deleted ${AXLE_CONFIG/#$HOME/~}"
    rmdir ${AXLE_CONFIG:h} 2>/dev/null
  fi
  (( ${remove[(Ie)history]} )) && [[ -d $data && $data == */axle ]] &&
    rm -rf -- $data && print -r -- "deleted ${data/#$HOME/~}"
  (( ${remove[(Ie)cache]} )) && [[ -d $cache && $cache == */axle ]] &&
    rm -rf -- $cache && print -r -- "deleted ${cache/#$HOME/~}"
  local -a rc=()
  [[ -r ~/.zshrc ]] && rc=(${(f)"$(command grep -n -E 'axle|benzene|AXLE_' ~/.zshrc 2>/dev/null)"})
  if (( ${#rc} )); then
    print; print -r -- "Remove these lines from ~/.zshrc yourself (Axle never edits it):"
    print -rl -- "  "${^rc}
  fi
  print
  print -r -- "Axle's own files are still in ${AXLE_ROOT/#$HOME/~} (delete the folder when you're done)."
  print -r -- "Open a new shell to finish."
}

axle_command uninstall _axle_cmd_uninstall general 'uninstall [--yes|--purge]' 'remove Axle (asks first)'

# Prompts, help pages, settings and Tab completion, shared by both parts.
source "$AXLE_ROOT/lib/ui.zsh"
source "$AXLE_ROOT/lib/help.zsh"
source "$AXLE_ROOT/lib/settings.zsh"
source "$AXLE_ROOT/lib/complete.zsh"

# The daily update check (once per shell, whichever part loads first).
if [[ -o interactive ]] && (( ! ${+_axle_update_started} )); then
  typeset -g _axle_update_started=1
  _axle_update_bg
  add-zsh-hook precmd _axle_update_notice
fi
