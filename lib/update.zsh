# `axle update` and `axle uninstall` (loaded the first time they're used).

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
    _axle_compile
    _axle_cmd_reload
    print -r -- "updated: $was → $AXLE_VERSION"
    local changes=$(AXLE_VERSION=$was _axle_update_changes HEAD)
    if [[ -n $changes ]]; then print -r -- $changes
    else command git -C $AXLE_ROOT log --oneline --no-decorate $before..$after | sed 's/^/  /'; fi
    mkdir -p ${_axle_update_cache:h} 2>/dev/null
    print -r -- "$EPOCHSECONDS" >| $_axle_update_cache 2>/dev/null
  fi
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
