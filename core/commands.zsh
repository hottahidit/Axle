# The axle tool's own commands: history, stats, doctor, update, module, hook, drop.

# --- history --------------------------------------------------------------------

# `axle history [n]`: recent commands with when, outcome, run time and folder.
_axle_cmd_history() {
  local -i n=${1:-20}
  [[ -r $_axle_hist_file ]] || { print -r -- "axle: no commands recorded yet"; return }
  local line when muted=${_axle_c[muted]:-244}
  local -a f
  for line in "${(@f)$(command tail -n $n $_axle_hist_file)}"; do
    f=("${(@ps:\t:)line}")
    (( ${#f} == 6 )) || continue
    strftime -s when '%a %H:%M' $f[1]
    local mark="%F{${_axle_c[ok]:-green}}✓%f   "
    (( f[2] )) && mark="%F{${_axle_c[error]:-red}}✗${(r:3:)f[2]}%f"
    _axle_fmt_duration $f[3]
    _axle_printp "%F{$muted}$when%f $mark ${(l:6:)REPLY}  %F{${_axle_c[path]:-blue}}${(r:22:)${${f[4]/#$HOME/~}//\%/%%}[-22,-1]}%f ${${f[6]//\\n/ ⏎ }//\%/%%}"
  done
}

# --- stats ----------------------------------------------------------------------

# `axle stats [--here] [--days N]`: what you run, what's slow, what fails, where you work.
_axle_cmd_stats() {
  local here='' days=0
  while (( $# )); do
    case $1 in
      --here) here=$PWD ;;
      --days) days=${2:?--days needs a number}; shift ;;
      *) print -u2 "usage: axle stats [--here] [--days N]"; return 1 ;;
    esac
    shift
  done
  [[ -r $_axle_hist_file ]] || { print -r -- "axle: no commands recorded yet"; return }
  local -i since=0
  (( days > 0 )) && since=$(( EPOCHSECONDS - days * 86400 ))
  local h=${_axle_c[accent]:-magenta} m=${_axle_c[muted]:-244} bad=${_axle_c[error]:-red}
  local scope='all folders'; [[ -n $here ]] && scope=${here/#$HOME/~}
  _axle_printp "%B%F{$h}axle stats%f%b %F{$m}· $scope${${days:#0}:+ · last $days days}%f"
  command awk -F'\t' -v since=$since -v here="$here" -v home="$HOME" '
    function short(d) { return index(d, home) == 1 ? "~" substr(d, length(home) + 1) : d }
    function trim(s, w) { return length(s) > w ? substr(s, 1, w - 1) "…" : s }
    NF == 6 && $1 >= since && (here == "" || $4 == here || index($4, here "/") == 1) {
      n++; secs += $3; if ($2 != 0 && $2 != 130) fails++
      split($6, w, " "); prog[w[1]]++
      runs[$6]++; time[$6] += $3; if ($2 != 0 && $2 != 130) failed[$6]++
      dirs[$4]++
    }
    function top(arr, k,   i, j, best, bk, out) {
      for (i = 1; i <= k; i++) {
        best = -1; bk = ""
        for (j in arr) if (!(j in out) && arr[j] > best) { best = arr[j]; bk = j }
        if (bk == "") break
        out[bk] = 1; order[i] = bk
      }
      return i - 1
    }
    END {
      if (!n) { print "  nothing recorded in this range"; exit }
      printf "  %d commands, %.0f%% failed, %.1f h spent running them\n\n", n, 100 * fails / n, secs / 3600
      k = top(prog, 8); printf "  most used programs\n"
      for (i = 1; i <= k; i++) printf "    %6d  %s\n", prog[order[i]], order[i]
      for (c in runs) if (runs[c] >= 3) avg[c] = time[c] / runs[c]
      k = top(avg, 5); printf "\n  slowest (average, run 3+ times)\n"
      for (i = 1; i <= k; i++) printf "    %6.1fs  %s\n", avg[order[i]], trim(order[i], 60)
      for (c in failed) if (runs[c] >= 3) rate[c] = failed[c] / runs[c]
      k = top(rate, 5); printf "\n  fails most often (run 3+ times)\n"
      if (!k) print "    nothing fails repeatedly"
      for (i = 1; i <= k; i++) printf "    %5.0f%%  %s  (%d of %d)\n", 100 * rate[order[i]], trim(order[i], 50), failed[order[i]], runs[order[i]]
      if (here == "") {
        k = top(dirs, 5); printf "\n  busiest folders\n"
        for (i = 1; i <= k; i++) printf "    %6d  %s\n", dirs[order[i]], short(order[i])
      }
    }' $_axle_hist_file
}

# --- doctor ---------------------------------------------------------------------

# `axle doctor`: check the setup, with a fix for anything that's off.
_axle_cmd_doctor() {
  local ok=${_axle_c[ok]:-green} warn=${_axle_c[warn]:-yellow} bad=${_axle_c[error]:-red} m=${_axle_c[muted]:-244}
  local -i problems=0
  _dr() {  # _dr ok|warn|bad <what> [fix]
    local c=$ok mark=✓
    [[ $1 == warn ]] && c=$warn mark=! && (( problems++ ))
    [[ $1 == bad ]]  && c=$bad  mark=✗ && (( problems++ ))
    _axle_printp "  %F{$c}$mark%f ${2//\%/%%}"
    [[ -n $3 ]] && _axle_printp "      %F{$m}${3//\%/%%}%f"
    return 0
  }
  _axle_printp "%B axle doctor%b"
  # zsh and tools
  autoload -Uz is-at-least
  if is-at-least 5.8; then _dr ok "zsh $ZSH_VERSION"; else _dr bad "zsh $ZSH_VERSION is too old" "Axle needs zsh 5.8 or newer"; fi
  local gitv=${${(s: :)"$(command git --version 2>/dev/null)"}[3]}
  if [[ -z $gitv ]]; then _dr warn "git not found" "install git for the prompt's git status"
  elif is-at-least 2.35 $gitv; then _dr ok "git $gitv"
  else _dr warn "git $gitv: stash counts need 2.35+" "update git"; fi
  (( $+commands[curl] )) && _dr ok "curl (AI status checks)" || _dr warn "curl not found" "AI status dots need curl"
  # what's loaded
  (( ${_axle_theme_loaded:-0} )) && _dr ok "Benzene prompt loaded ($AXLE_VARIANT)" ||
    _dr warn "Benzene prompt not loaded" "oh-my-zsh: ZSH_THEME=\"benzene\"; otherwise AXLE_THEME=benzene"
  _dr ok "modules: ${AXLE_MODULES:-none}"
  (( $+functions[_zsh_autosuggest_start] )) &&
    _dr warn "zsh-autosuggestions is loaded" "axle's suggest module steps aside for it; remove one of them"
  [[ -n $POWERLEVEL9K_MODE$STARSHIP_SHELL ]] &&
    _dr warn "another prompt (powerlevel10k/starship) is active" "it may fight Benzene for the prompt"
  # terminal
  if [[ $COLORTERM == (truecolor|24bit) || -n $WT_SESSION || $TERM_PROGRAM == (vscode|iTerm.app|WezTerm|ghostty) ]]; then
    _dr ok "24-bit colour"
  else
    _dr warn "24-bit colour not detected (TERM=$TERM)" "colours are approximated; set COLORTERM=truecolor if your terminal supports it"
  fi
  if (( ${AXLE_NERD_FONT:-0} )); then
    _dr ok "Nerd Font icons on (each counted as $(( ${_axle_icon_extra:-0} + 1 )) column(s))"
  else
    _dr warn "Nerd Font icons off" "with a Nerd Font installed (e.g. Cascadia Code NF), set AXLE_NERD_FONT=1"
  fi
  if [[ -n $TMUX ]]; then
    if command tmux show -s terminal-features 2>/dev/null | grep -q RGB; then _dr ok "tmux passes 24-bit colour"
    else _dr warn "tmux isn't passing 24-bit colour" "add: source-file $AXLE_ROOT/benzene/tmux.conf"; fi
  fi
  # files
  local dir=${_axle_hist_file:h}
  if [[ -w $dir || ( ! -e $dir && -w ${dir:h} ) ]]; then
    local -i n=0; [[ -r $_axle_hist_file ]] && n=${#${(f)"$(<$_axle_hist_file)"}}
    _dr ok "history: $n commands recorded (${_axle_hist_file/#$HOME/~})"
  else
    _dr bad "can't write ${dir/#$HOME/~}" "fix its permissions"
  fi
  if [[ -r $AXLE_CONFIG ]]; then
    _dr ok "config: ${AXLE_CONFIG/#$HOME/~}"
    local -a over=(${(M)${(f)"$(<${ZDOTDIR:-$HOME}/.zshrc)"}:#[[:space:]]#AXLE_*})
    (( ${#over} )) && _dr warn "${#over} AXLE_* line(s) in ~/.zshrc are overridden by the config" "${(j:, :)over}"
  else
    _dr ok "no config file (defaults; \`axle configure\` writes one)"
  fi
  # compiled (zsh bytecode, *.zwc): loads about twice as fast
  local -a uncompiled=($AXLE_ROOT/{axle.plugin.zsh,benzene.zsh-theme,{lib,core,modules,benzene}/*.zsh}(N))
  local f; local -a old=()
  for f in $uncompiled; do [[ $f.zwc -nt $f ]] || old+=(${f#$AXLE_ROOT/}); done
  if (( ! ${#old} )); then _dr ok "compiled to zsh bytecode (fast loading)"
  elif [[ -w $AXLE_ROOT ]]; then _dr warn "${#old} file(s) not compiled yet" "they're compiled in the background when a shell starts; or now: _axle_compile"
  else _dr warn "not compiled ($AXLE_ROOT isn't writable)" "loading takes about twice as long"; fi
  # speed
  if (( ${_axle_theme_loaded:-0} )) && (( $+functions[_axle_render] )); then
    local -F t=$EPOCHREALTIME
    repeat 10 _axle_render
    local -F ms=$(( (EPOCHREALTIME - t) * 100 ))
    if (( ms < 10 )); then _dr ok "prompt draws in $(printf %.1f $ms) ms"
    else _dr warn "prompt takes $(printf %.0f $ms) ms to draw" "\`axle preview\` and segments you added are the usual suspects"; fi
  fi
  print
  (( problems )) && _axle_printp "  %F{$warn}$problems thing(s) to look at%f" || _axle_printp "  %F{$ok}all good%f"
  unfunction _dr
}

# --- module ---------------------------------------------------------------------

# `axle module [ls] | on <name> | off <name>` (also enable/disable), saved to the config.
_axle_cmd_module() {
  local -a all=(${${:-$AXLE_ROOT/modules/*.zsh(N)}:t:r})
  case ${1:-ls} in
    ls)
      local name
      for name in $all; do
        local state='off'; (( ${AXLE_MODULES[(Ie)$name]} )) && state='on '
        print -r -- "  $state  $name    ${${(M)${(f)"$(<$AXLE_ROOT/modules/$name.zsh)"}:#\#*}[1]#\# }"
      done ;;
    on|off|enable|disable)
      local verb=${${${1/on/enable}/off/disable}}
      [[ -n $2 ]] && (( ${all[(Ie)$2]} )) || { print -u2 "axle module: no module '$2' (${all})"; return 1 }
      local -a mods=(${AXLE_MODULES:#$2})
      [[ $verb == enable ]] && mods+=($2)
      mkdir -p ${AXLE_CONFIG:h}
      local -a lines=()
      [[ -r $AXLE_CONFIG ]] && lines=("${(@f)$(<$AXLE_CONFIG)}")
      lines=(${lines:#AXLE_MODULES=*} "AXLE_MODULES=($mods)")
      print -rl -- $lines > $AXLE_CONFIG
      typeset -ga AXLE_MODULES=($mods); _axle_auto_modules=''
      print -r -- "axle: $2 ${verb}d (saved to ${AXLE_CONFIG/#$HOME/~})"
      [[ $verb == enable ]] && _axle_cmd_reload
      [[ $verb == disable ]] && print -r -- "  open a new shell to unload it fully" ;;
    *) print -u2 "usage: axle module [ls] | on <name> | off <name>"; return 1 ;;
  esac
}

_axle_cmd_drop() { "$AXLE_ROOT/tools/axle-drop" "$@" }
