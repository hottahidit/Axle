# axle configure — set Axle up step by step: the Benzene prompt (with a live preview drawn
# by the real prompt code) and/or the axle tool, whichever is loaded. Saves to
# ${XDG_CONFIG_HOME:-~/.config}/axle/config.zsh, replacing only the settings it asked
# about. Runs in a subshell (the `axle` command and install.sh do that); q or Ctrl-C cancels.

typeset -gi _cf_theme=${_axle_theme_loaded:-0} _cf_tool=${_axle_tool_loaded:-0}
if (( _cf_theme )); then
  source "$AXLE_ROOT/benzene/preview.zsh" --lib
else
  _pv_cleanup() { : }
fi

typeset -g  _cf_file=${AXLE_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/axle/config.zsh}
typeset -g  _cf_zshrc=${ZDOTDIR:-$HOME}/.zshrc     # (before the preview swaps HOME)
typeset -gA _cf                                   # the choices so far
typeset -g  _cf_note='' _cf_scenes=''
typeset -gi _cf_step=0 _cf_total=0

_cf_muted() { _axle_printp "%F{${_axle_c[muted]:-244}}$1%f" }

# How many steps, from what's loaded and what's been chosen so far.
_cf_recount() {
  _cf_total=0
  if (( _cf_theme )); then
    [[ ${_cf[variant]:-${AXLE_VARIANT:-nox}} == axon ]] && (( _cf_total += 6 )) || (( _cf_total += 8 ))
  fi
  if (( _cf_tool )); then
    local -a mods=(${=_cf[modules]:-$AXLE_MODULES})
    (( _cf_total += 1 ))                          # which modules
    (( ${mods[(Ie)suggest]} )) && (( _cf_total += 1 ))
    (( ${mods[(Ie)env]} )) && (( _cf_total += 1 ))
    (( ${mods[(Ie)run]} )) && (( _cf_total += 2 ))
  fi
}

_cf_header() {
  print -n '\e[H\e[2J'
  _axle_printp "%B Axle setup%b  %F{${_axle_c[muted]:-244}}step $_cf_step of $_cf_total · q cancels%f"
  print
  _axle_printp "%B $1%b"
  [[ -n $_cf_note ]] && _cf_muted "   $_cf_note"
  print
}

# Apply the theme choices so far, so the preview shows them.
_cf_apply() {
  AXLE_VARIANT=${_cf[variant]:-${AXLE_VARIANT:-nox}}
  AXLE_NERD_FONT=${_cf[nerd]:-${AXLE_NERD_FONT:-0}}
  AXLE_PALETTE=${_cf[palette]:-${AXLE_PALETTE:-mocha}}
  [[ -n $_cf[char] ]] && { AXLE_PROMPT_CHAR=$_cf[char]; AXLE_AXON_CHAR=$_cf[char] }
  AXLE_TRANSIENT=${_cf[transient]:-${AXLE_TRANSIENT:-1}}
  AXLE_ALARMS=${_cf[alarms]:-${AXLE_ALARMS:-1}} AXLE_BUBBLES=${_cf[bubbles]:-${AXLE_BUBBLES:-1}}
  AXLE_CLOCK=${_cf[clock]:-${AXLE_CLOCK:-1}}
  AXLE_AXON_SLOW=${_cf[slow]:-${AXLE_AXON_SLOW:-10}}
  _axle_load_variant $AXLE_VARIANT >/dev/null
}

# A few prompt scenarios, drawn with the current choices (theme steps only).
_cf_preview() {
  (( _cf_theme && $# )) || return 0
  _cf_apply
  print
  local name
  for name; do
    _cf_muted "  ${_pv_titles[${_pv_names[(Ie)$name]}]}"
    _pv_show $name 2>/dev/null | grep -v 'past:'
  done
}

# One choice: _cf_ask <title> <key> <default> <label:value>...  (sets _cf[key])
# ↑/↓ move (the preview follows), Enter or a number chooses, q / Esc cancels.
_cf_ask() {
  local title=$1 key=$2 def=$3; shift 3
  local -a labels values
  local opt mark a=${_axle_c[accent]:-magenta}
  for opt; do labels+=("${opt%:*}"); values+=("${opt##*:}"); done   # label:value (last colon)
  local -i i n=${#labels} cur=${values[(Ie)$def]}
  (( cur )) || cur=1
  (( _cf_step++ ))
  print -n '\e[?25l'
  while :; do
    _cf_header $title
    for i in {1..$n}; do
      mark=' '; [[ ${values[i]} == $def ]] && mark='•'
      if (( i == cur )); then
        _axle_printp "  %F{$a}❯ $mark $i) ${labels[i]//\%/%%}%f"
      else
        print -r -- "    $mark $i) ${labels[i]}"
      fi
    done
    _cf[$key]=${values[cur]}                      # the preview shows the highlighted one
    _cf_preview ${=_cf_scenes}
    print
    _cf_muted " ↑↓ move · Enter chooses · 1-$n · • = current · q cancels"
    _axle_ui_key
    case $REPLY in
      up|k)       (( cur = cur > 1 ? cur - 1 : n )) ;;
      down|j|tab) (( cur = cur < n ? cur + 1 : 1 )) ;;
      [1-9])      (( REPLY <= n )) && { cur=$REPLY; break } ;;
      enter)      break ;;
      q|esc)      print -n '\e[?25h'; exit 1 ;;
    esac
  done
  print -n '\e[?25h'
  _cf[$key]=${values[cur]}
  _cf_note='' _cf_scenes=''
}

# Several on/off choices: _cf_toggle <title> <key> <"on names"> <name:description>...
# ↑/↓ move, Space (or a number) switches one, Enter when done.
_cf_toggle() {
  local title=$1 key=$2; shift 2
  local -a on=(${=1}) names descs; shift
  local opt box a=${_axle_c[accent]:-magenta} ok=${_axle_c[ok]:-green}
  for opt; do names+=("${opt%%:*}"); descs+=("${opt#*:}"); done
  local -i i n=${#names} cur=1
  (( _cf_step++ ))
  print -n '\e[?25l'
  while :; do
    _cf_header $title
    for i in {1..$n}; do
      box='○'; (( ${on[(Ie)${names[i]}]} )) && box="%F{$ok}●%f"
      if (( i == cur )); then
        _axle_printp "  %F{$a}❯%f $box %F{$a}${(r:8:)names[i]}%f ${descs[i]//\%/%%}"
      else
        _axle_printp "    $box ${(r:8:)names[i]} ${descs[i]//\%/%%}"
      fi
    done
    print
    _cf_muted " ↑↓ move · Space switches · Enter when done · q cancels"
    _axle_ui_key
    case $REPLY in
      up|k)       (( cur = cur > 1 ? cur - 1 : n )) ;;
      down|j|tab) (( cur = cur < n ? cur + 1 : 1 )) ;;
      space|x|[1-9])
        [[ $REPLY == [1-9] ]] && { (( REPLY <= n )) || continue; cur=$REPLY }
        if (( ${on[(Ie)${names[cur]}]} )); then on=(${on:#${names[cur]}}); else on+=(${names[cur]}); fi ;;
      enter)      break ;;
      q|esc)      print -n '\e[?25h'; exit 1 ;;
    esac
  done
  print -n '\e[?25h'
  local -a ordered=()
  for opt in $names; do (( ${on[(Ie)$opt]} )) && ordered+=($opt); done
  _cf[$key]="$ordered"
  _cf_note=''
}

# --- steps ------------------------------------------------------------------------

_cf_theme_steps() {
  _cf_scenes='clean'
  _cf_note="Do these look like an arrow, a branch, a server, a clock and the Python logo? "$'        '
  _cf_ask "Can your font draw Nerd Font icons?" nerd ${AXLE_NERD_FONT:-0} \
    "Yes, I see five icons:1" "No, I see boxes or blanks:0"

  _cf_scenes='dirty failed'
  _cf_ask "Which Benzene variant?" variant ${AXLE_VARIANT:-nox} \
    "NoxA: two lines, shows what's relevant, Alt-i for everything:nox" \
    "AxoN: one quiet line, only what needs attention:axon"
  _cf_recount
  local -i axon=0; [[ $_cf[variant] == axon ]] && axon=1

  _cf_scenes='dirty prod'
  _cf_ask "Colours?" palette ${AXLE_PALETTE:-mocha} \
    "Catppuccin Mocha (24-bit):mocha" "Classic 256-colour:classic"

  _cf_scenes='clean failed'
  local -a chars=("❯ chevron:❯" "λ lambda:λ" "➜ arrow:➜" "\$ classic:\$")
  (( _cf[nerd] )) && chars=($' powerline arrow:' $chars)
  local defchar=${AXLE_PROMPT_CHAR:-$''}
  (( axon )) && defchar=${AXLE_AXON_CHAR:-\$}
  _cf_ask "Prompt character?" char $defchar $chars

  _cf_scenes='failed'
  local compact="Compact: time, folder, command:1"
  (( axon )) && compact="Compact: folder and command:1"
  _cf_ask "Past commands in scrollback?" transient ${AXLE_TRANSIENT:-1} $compact "Keep the full prompt:0"

  if (( axon )); then
    _cf_scenes='slow interrupt'
    _cf_note="AxoN stays quiet about commands that finish quickly; failures always show."
    _cf_ask "Show a command's run time when it took…" slow ${AXLE_AXON_SLOW:-10} \
      "5 seconds or more:5" "10 seconds or more:10" "30 seconds or more:30" "Never:0"
  else
    _cf_scenes='prod root'
    local -a bubbles=("Square blocks:1 0" "Off (coloured text only):0 0")
    (( _cf[nerd] )) && bubbles=("Rounded bubbles:1 1" $bubbles)
    _cf_ask "Alarms (failed command, root, production contexts, low battery)?" alarm \
      "${AXLE_ALARMS:-1} ${AXLE_BUBBLES:-1}" $bubbles
    _cf[alarms]=${_cf[alarm]% *} _cf[bubbles]=${_cf[alarm]#* }

    _cf_scenes='clean'
    _cf_ask "Clock?" clock ${AXLE_CLOCK:-1} \
      "Always (HH:MM; seconds when expanded):1" "Only in the expanded view:0"

    _cf_scenes='ai-down'
    _cf_ask "AI status dots (expanded view)?" ai "${AXLE_AI_STATUS:-claude}" \
      "Claude:claude" "Claude and OpenAI:claude openai" "Claude and your local Ollama:claude ollama" "None:"
  fi
}

_cf_tool_steps() {
  _cf_toggle "Which axle modules?" modules "${AXLE_MODULES:-suggest highlight upsearch jump search env fix run}" \
    "suggest:grey suggestions as you type (Ctrl-N lists the alternatives)" \
    "highlight:syntax highlighting: green commands, red typos, coloured strings and options" \
    "upsearch:type part of a command, then ↑/↓ walks through history lines with it" \
    "jump:j <words> goes to the folder you most likely mean" \
    "search:Ctrl-R opens a history picker with filters" \
    "env:switches a project's venv on and off as you cd in and out" \
    "fix:fix (or Esc Esc) corrects the last command: typos, missing sudo" \
    "run:axle run runs this project (servers in the background, in the prompt), or the last one"
  _cf_recount
  local -a mods=(${=_cf[modules]})

  if (( ${mods[(Ie)suggest]} )); then
    _cf_note="The best one shows in grey after the cursor; Ctrl-N lists the others below the line."
    _cf_ask "How many options in the Ctrl-N list?" suggest_list ${AXLE_SUGGEST_LIST:-5} \
      "None, just the inline one:1" "Up to 3:3" "Up to 5:5" "Up to 8:8"
  fi
  if (( ${mods[(Ie)env]} )); then
    _cf_note='For example: "axle: using the shop-api venv".'
    _cf_ask "When a venv is switched automatically…" env_quiet ${AXLE_ENV_QUIET:-0} \
      "Say so in one line:0" "Stay silent:1"
  fi
  if (( ${mods[(Ie)run]} )); then
    _cf_note='Servers run in the background and show in the prompt: ⚡ shop :8000.'
    _cf_ask "When their terminal closes, axle run's servers…" run_on_exit ${AXLE_RUN_ON_EXIT:-keep} \
      "Keep running (axle run stop ends them):keep" "Stop with it:stop"
    _cf_note='From the server itself, so it works with no terminal open.'
    _cf_ask "A desktop notification when a server…" run_notify ${AXLE_RUN_NOTIFY:-off} \
      "Never:off" "Crashes:crash" "Crashes, or is ready:all"
  fi
}

# --- saving -----------------------------------------------------------------------

_cf_write() {
  local -a ours keys
  if (( _cf_theme )); then
    keys+=(AXLE_VARIANT AXLE_NERD_FONT AXLE_PALETTE AXLE_PROMPT_CHAR AXLE_AXON_CHAR AXLE_TRANSIENT
           AXLE_AXON_SLOW AXLE_ALARMS AXLE_BUBBLES AXLE_CLOCK AXLE_AI_STATUS)
    ours+=("# Benzene" "AXLE_VARIANT=$_cf[variant]" "AXLE_NERD_FONT=$_cf[nerd]" "AXLE_PALETTE=$_cf[palette]")
    if [[ $_cf[variant] == axon ]]; then
      ours+=("AXLE_AXON_CHAR=${(q+)_cf[char]}" "AXLE_TRANSIENT=$_cf[transient]"
             "AXLE_AXON_SLOW=$_cf[slow]          # run time shown from this many seconds (0 = never)")
    else
      ours+=("AXLE_PROMPT_CHAR=${(q+)_cf[char]}" "AXLE_TRANSIENT=$_cf[transient]"
             "AXLE_ALARMS=$_cf[alarms] AXLE_BUBBLES=$_cf[bubbles]"
             "AXLE_CLOCK=$_cf[clock]              # 0 = clock only when expanded"
             "AXLE_AI_STATUS=($_cf[ai])")
    fi
  fi
  if (( _cf_tool )); then
    keys+=(AXLE_MODULES AXLE_SUGGEST AXLE_SUGGEST_LIST AXLE_ENV_QUIET AXLE_RUN_ON_EXIT AXLE_RUN_NOTIFY)
    ours+=("# axle" "AXLE_MODULES=($_cf[modules])")
    [[ -n $_cf[suggest_list] ]] && ours+=("AXLE_SUGGEST_LIST=$_cf[suggest_list]")
    [[ -n $_cf[env_quiet] ]] && ours+=("AXLE_ENV_QUIET=$_cf[env_quiet]")
    [[ -n $_cf[run_on_exit] ]] && ours+=("AXLE_RUN_ON_EXIT=$_cf[run_on_exit]")
    [[ -n $_cf[run_notify] ]] && ours+=("AXLE_RUN_NOTIFY=$_cf[run_notify]")
  fi
  # Keep everything else already in the file (settings for the other part, your edits).
  local -a kept=() line
  local -a old=()
  [[ -r $_cf_file ]] && old=("${(@f)$(<$_cf_file)}")
  local l k skip
  for l in $old; do
    skip=0
    [[ $l == ('# Axle settings'*|'# Re-run it any time'*|'# This file is loaded'*) ]] && skip=1
    (( _cf_theme )) && [[ $l == '# Benzene' ]] && skip=1      # section labels: only for what we write
    (( _cf_tool ))  && [[ $l == '# axle' ]] && skip=1
    for k in $keys; do [[ $l == [[:space:]]#$k=* ]] && skip=1; done
    (( skip )) || kept+=("$l")
  done
  while (( ${#kept} )) && [[ -z ${kept[1]//[[:space:]]/} ]]; do kept=("${(@)kept[2,-1]}"); done
  mkdir -p ${_cf_file:h}
  {
    print -r -- "# Axle settings, written by \`axle configure\` on $(strftime '%Y-%m-%d %H:%M' $EPOCHSECONDS)."
    print -r -- "# Re-run it any time, or edit by hand; every AXLE_* setting from the README works here."
    print -r -- "# This file is loaded after ~/.zshrc, so values here win."
    (( ${#kept} )) && { print; print -rl -- $kept }
    print
    print -rl -- $ours
  } > $_cf_file.$$ && mv -f $_cf_file.$$ $_cf_file
}

_cf_main() {
  emulate -L zsh
  setopt extendedglob
  [[ -t 0 && -t 1 ]] || { print -u2 "axle configure: needs a terminal"; return 1 }
  (( _cf_theme || _cf_tool )) || { print -u2 "axle configure: neither Benzene nor the axle tool is loaded"; return 1 }
  trap '_pv_cleanup; print; exit 1' INT TERM HUP
  if (( _cf_theme )); then _pv_setup || return 1; fi
  _cf_recount

  (( _cf_theme )) && _cf_theme_steps
  (( _cf_tool ))  && _cf_tool_steps

  # Review and save.
  print -n '\e[H\e[2J'
  _axle_printp "%B Axle setup%b  %F{${_axle_c[muted]:-244}}review%f"
  if (( _cf_theme )); then
    if [[ $_cf[variant] == axon ]]; then _cf_preview dirty failed interrupt sudo
    else _cf_preview dirty failed prod sudo; fi
  fi
  if (( _cf_tool )); then
    print
    print -r -- "  axle modules: ${_cf[modules]:-none}"
    [[ -n $_cf[suggest_list] ]] && print -r -- "  Ctrl-N list:  up to $_cf[suggest_list]"
    [[ -n $_cf[env_quiet] ]] && print -r -- "  venv switch:  ${${_cf[env_quiet]:#1}:+announced}${${(M)_cf[env_quiet]:#1}:+silent}"
  fi
  print
  print -rn -- " Save to ${_cf_file/#$HOME/~}? [Enter] save  [q] cancel: "
  local press; read -rsk press
  [[ $press == ($'\n'|$'\r'|y) ]] || { print; print "Nothing saved."; return 1 }
  _cf_write
  print; print -r -- "Saved ${_cf_file/#$HOME/~}."
  # Settings in ~/.zshrc that this file now overrides.
  local -a over=()
  [[ -r $_cf_zshrc ]] && over=(${(M)${(f)"$(<$_cf_zshrc)"}:#[[:space:]]#AXLE_*})
  if (( ${#over} )); then
    print -r -- "These lines in ${_cf_zshrc/#$HOME/~} are now overridden by it, so you can delete them:"
    print -rl -- "  "${^over}
  fi
  return 0
}

# Clean up however this subshell ends. (Set here, not inside a function: zsh skips a
# function's EXIT trap when `exit` runs deeper down, e.g. when the window is closed.)
trap _pv_cleanup EXIT
_cf_main "$@"
