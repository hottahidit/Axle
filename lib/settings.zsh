# `axle config`: see and change settings without the wizard or an editor.
#
#   axle config                     every setting: its value, and where that value comes from
#   axle config get <NAME>          one setting
#   axle config set <NAME> <value>  save it to the config file and apply it now
#                                   (a list takes several words: set AXLE_MODULES suggest jump)
#   axle config unset <NAME>        remove it from the config file (back to the default)
#   axle config edit                open the config file in $VISUAL / $EDITOR
#   axle config set                 with no name: pick a setting and a value from menus
#
# Settings live in ~/.config/axle/config.zsh, read after ~/.zshrc so they win. Values are
# written quoted, so the file stays plain data however odd a value is.

# name -> "part|kind|default|description". kind: bool, int, text, list, or choice:a,b,c
typeset -gA _axle_settings=(
  # both parts
  AXLE_UPDATE_CHECK     'general|bool|1|check for a new version once a day (in the background)'
  # the prompt
  AXLE_VARIANT          'theme|choice:nox,axon|nox|which prompt: NoxA (two lines) or AxoN (one line)'
  AXLE_NERD_FONT        'theme|bool|0|Nerd Font icons instead of plain text'
  AXLE_PALETTE          'theme|choice:mocha,classic|mocha|colours: Catppuccin Mocha (24-bit) or 256-colour'
  AXLE_ICON_WIDTH       'theme|choice:,1,2||columns per Nerd Font icon (empty: asked from the terminal)'
  AXLE_PROMPT_CHAR      'theme|text||the prompt character (empty: the powerline arrow, or ▶)'
  AXLE_PROMPT_CHAR_VICMD 'theme|text||the prompt character in vi command mode'
  AXLE_PROMPT_GAP       'theme|int|2|spaces between the arrow and what you type'
  AXLE_TRANSIENT        'theme|bool|1|shrink past prompts to "time dir ➜ command"'
  AXLE_MARKS            'theme|choice:auto,1,0|auto|shell-integration marks (jump between commands)'
  AXLE_LINKS            'theme|bool|1|clickable path and branch'
  AXLE_ALARMS           'theme|bool|1|red bubbles for what is genuinely wrong'
  AXLE_BUBBLES          'theme|bool|1|rounded bubbles (0: square blocks)'
  AXLE_CLOCK            'theme|bool|1|the clock (0: only when expanded)'
  AXLE_PROD_PATTERN     'theme|text|(#i)*prod*|contexts that count as production (zsh pattern)'
  AXLE_CMD_MIN_SECS     'theme|int|2|show run time from this many seconds'
  AXLE_NOTIFY_SECS      'theme|int|0|ring the bell after commands this long (0: off)'
  AXLE_MEM_WARN         'theme|int|80|RAM % that turns the prompt dark red'
  AXLE_BATTERY_WARN     'theme|int|30|battery % below which the battery shows'
  AXLE_SUDO_TIMEOUT     'theme|text||sudo lifetime in minutes (empty: ask sudo)'
  AXLE_PATH_DEPTH       'theme|int|4|path components kept before the middle is elided'
  AXLE_DETAIL_KEY       'theme|text|^[i|key that expands the prompt (empty: none)'
  AXLE_GIT_ASYNC        'theme|bool|1|git status in the background'
  AXLE_GIT_UNTRACKED    'theme|bool|1|count untracked files (0: faster in huge repos)'
  AXLE_VSCODE           'theme|choice:auto,1,0|auto|the compact layout in VS Code'
  AXLE_NOX_LEFT         'theme|list||NoxA: segments on the first line, in order'
  AXLE_NOX_RIGHT        'theme|list||NoxA: stats on the right, in order'
  AXLE_NOX_PRIORITY     'theme|list||NoxA: segments from most to least important'
  AXLE_NOX_CODE         'theme|list||NoxA: segments of the VS Code layout'
  AXLE_NOX_MAX_LEFT     'theme|int|5|NoxA: segments on the first line before trimming'
  AXLE_NOX_MAX_RIGHT    'theme|int|3|NoxA: segments on the right before trimming'
  AXLE_NOX_MAX_CODE     'theme|int|5|NoxA: segments in the VS Code layout before trimming'
  AXLE_AXON_SHOW        'theme|list||AxoN: attention markers, in order'
  AXLE_AXON_SLOW        'theme|int|10|AxoN: show run time from this many seconds (0: never)'
  AXLE_AXON_CHAR        'theme|text|$|AxoN: the prompt character'
  AXLE_AXON_CHAR_VICMD  'theme|text|:|AxoN: the prompt character in vi command mode'
  AXLE_AI_STATUS        'theme|list|claude|AI services whose status shows when expanded'
  AXLE_AI_STATUS_INTERVAL 'theme|int|180|seconds between status page checks'
  AXLE_AI_LOCAL_INTERVAL 'theme|int|30|seconds between local AI server checks'
  AXLE_DROP_POLL        'theme|int|5|seconds between looking for new drops'
  AXLE_DROP_MAX         'theme|int|2|ok/info drops shown at once'
  # the tool
  AXLE_THEME            'tool|choice:,benzene||load the Benzene prompt from the plugin'
  AXLE_MODULES          'tool|list|suggest highlight upsearch jump search env fix|modules to load'
  AXLE_HIGHLIGHT        'tool|bool|1|syntax highlighting as you type'
  AXLE_HIGHLIGHT_MAX    'tool|int|2000|no highlighting past this many characters'
  AXLE_UPSEARCH         'tool|bool|1|↑/↓ search history for what you have typed'
  AXLE_UPSEARCH_PREFIX  'tool|bool|0|↑/↓ match only lines starting with what you typed'
  AXLE_UPSEARCH_CASE    'tool|bool|0|↑/↓ search is case-sensitive'
  AXLE_UPSEARCH_STYLE   'tool|text||how the match looks (region_highlight)'
  AXLE_FIX_CMD          'tool|text|fix|the command that corrects the last one (empty: none)'
  AXLE_FIX_KEY          'tool|text|^[^[|key that corrects / toggles sudo (empty: none)'
  AXLE_SUGGEST          'tool|bool|1|suggestions as you type'
  AXLE_SUGGEST_STRATEGY 'tool|list|smart history completion|where suggestions come from, in order'
  AXLE_SUGGEST_STYLE    'tool|text||how a suggestion looks (region_highlight, e.g. fg=244)'
  AXLE_SUGGEST_IGNORE   'tool|text||zsh pattern of lines never suggested'
  AXLE_SUGGEST_MAX_BUFFER 'tool|int|0|no suggestions past this many characters (0: any)'
  AXLE_SUGGEST_LIST     'tool|int|5|options in the Ctrl-N list'
  AXLE_SUGGEST_LOAD     'tool|int|4000|recorded commands to learn from'
  AXLE_JUMP_CMD         'tool|text|j|the jump command'
  AXLE_SEARCH_KEY       'tool|text|^R|key for the history picker'
  AXLE_SEARCH_ROWS      'tool|int|10|rows in the history picker'
  AXLE_ENV_QUIET        'tool|bool|0|switch venvs without saying so'
)

# The setting's fields: reply=(part kind default description).
_axle_setting() {
  local spec=${_axle_settings[$1]}
  [[ -n $spec ]] || { reply=(); return 1 }
  reply=("${(@s:|:)spec}")
}

# The config file's lines (reply=()).
_axle_config_lines() {
  reply=()
  [[ -r $AXLE_CONFIG ]] && reply=("${(@f)$(<$AXLE_CONFIG)}")
}

# What's saved for a setting in the config file (REPLY = the line), or status 1.
_axle_config_saved() {
  local -a reply
  _axle_config_lines
  REPLY=${(M)reply:#$1=*}
  REPLY=${REPLY%%$'\n'*}
  [[ -n $REPLY ]]
}

# Replace (or add) a setting's line in the config file; an empty line removes it.
_axle_config_write() {
  local name=$1 line=$2
  local -a reply
  _axle_config_lines
  local -a lines=(${reply:#$name=*})
  [[ -n $line ]] && lines+=("$line")
  mkdir -p ${AXLE_CONFIG:h} || return 1
  [[ ${lines[1]} == '#'* ]] || lines=('# Axle settings (axle config, axle configure)' $lines)
  print -rl -- $lines > $AXLE_CONFIG.$$ && mv -f $AXLE_CONFIG.$$ $AXLE_CONFIG
}

# Shown value of a setting (REPLY): a list as words, unset as empty.
_axle_config_value() {
  if [[ ${(tP)1} == array* ]]; then REPLY=${(j: :)${(P)1}}; else REPLY=${(P)1}; fi
}

# Check a value against the setting's kind; REPLY = why not.
_axle_config_check() {
  local kind=$1 value=$2
  REPLY=''
  case $kind in
    bool)     [[ $value == (0|1) ]] || REPLY="0 or 1" ;;
    int)      [[ $value == <-> ]]   || REPLY="a whole number" ;;
    choice:*) local -a ok=("${(@s:,:)kind#choice:}") shown=()
              [[ $kind == choice:,* ]] && ok=('' $ok)      # a leading comma: empty allowed
              local c
              for c in "${ok[@]}"; do shown+=("${c:-(empty)}"); done
              (( ${ok[(Ie)$value]} )) || REPLY="one of: ${(j:, :)shown}" ;;
  esac
  [[ -z $REPLY ]]
}

_axle_config_list() {
  local m=${_axle_c[muted]:-244} a=${_axle_c[accent]:-magenta} name part kind def desc value src
  local -a reply
  local -A titles=(general 'Axle' theme 'Benzene, the prompt' tool 'axle, the tool')
  local -A saved
  _axle_config_lines
  local line
  for line in $reply; do [[ $line == (#b)(AXLE_[A-Z0-9_]##)=* ]] && saved[$match[1]]=1; done
  for part in general theme tool; do
    [[ $part == theme ]] && (( ! ${_axle_theme_loaded:-0} )) && continue
    [[ $part == tool ]]  && (( ! ${_axle_tool_loaded:-0} ))  && continue
    print; _axle_printp "%B${titles[$part]}%b"
    for name in ${(ok)_axle_settings}; do
      _axle_setting $name; [[ $reply[1] == $part ]] || continue
      kind=$reply[2] def=$reply[3] desc=$reply[4]
      _axle_config_value $name; value=$REPLY
      if (( ${+saved[$name]} )); then src="%F{$a}saved%f"
      elif [[ $kind != list && -n $value && $value != "$def" ]]; then src="%F{$m}~/.zshrc%f"
      else src="%F{$m}default%f"; fi
      (( ${#value} > 34 )) && value="${value[1,33]}…"
      [[ -n $value ]] || value='–'
      _axle_printp "  ${(r:24:)name} ${(r:35:)value//\%/%%} $src"
    done
  done
  print
  _axle_printp "%F{$m}axle config get <NAME> for what it does · set / unset to change · edit to open the file%f"
}

# Pick a setting, then a value, from menus.
_axle_config_pick() {
  local -a items reply
  local name
  for name in ${(ok)_axle_settings}; do
    _axle_setting $name
    [[ $reply[1] == theme ]] && (( ! ${_axle_theme_loaded:-0} )) && continue
    [[ $reply[1] == tool ]]  && (( ! ${_axle_tool_loaded:-0} ))  && continue
    items+=("${(r:24:)name} ${reply[4]//:/∶}:$name")
  done
  axle_select "Which setting?" '' $items || return 1
  _axle_config_set_interactive $REPLY
}

_axle_config_set_interactive() {
  local name=$1 kind def current
  local -a reply
  _axle_setting $name; kind=$reply[2] def=$reply[3]
  _axle_config_value $name; current=$REPLY
  case $kind in
    bool)
      axle_select "$name" "${current:-$def}" "on:1" "off:0" || return 1 ;;
    choice:*)
      local -a opts=() c
      local label
      local -a cs=("${(@s:,:)kind#choice:}")
      [[ $kind == choice:,* ]] && cs=('' $cs)
      for c in "${cs[@]}"; do
        label=${c:-(empty)}
        [[ $c == $def ]] && label+=' (default)'
        opts+=("$label:$c")
      done
      axle_select "$name" "$current" $opts || return 1 ;;
    *)
      axle_input "$name" "$current" || return 1 ;;
  esac
  if [[ $kind == list ]]; then
    _axle_cmd_config set $name ${=REPLY}
  else
    _axle_cmd_config set $name "$REPLY"
  fi
}

_axle_cmd_config() {
  setopt localoptions extendedglob
  local cmd=${1:-list} name=$2
  local -a reply
  case $cmd in
    list|ls) _axle_config_list ;;
    get)
      [[ -n $name ]] || { print -u2 "usage: axle config get <NAME>"; return 1 }
      _axle_config_value $name; local value=$REPLY
      if _axle_setting $name; then
        _axle_printp "%B$name%b  %F{${_axle_c[muted]:-244}}${reply[4]//\%/%%}%f"
        print -r -- "  value:   ${value:-(empty)}"
        print -r -- "  default: ${reply[3]:-(empty)}   type: ${${reply[2]/choice:/one of: }//,/, }"
      else
        print -r -- "$name=${value}"
      fi
      _axle_config_saved $name && print -r -- "  saved:   $REPLY  (${AXLE_CONFIG/#$HOME/~})"
      return 0 ;;
    set)
      if [[ -z $name ]]; then _axle_config_pick; return; fi
      [[ $name == AXLE_[A-Z0-9_]## ]] || { print -u2 "axle config: settings are named AXLE_..."; return 1 }
      shift 2
      if (( ! $# )); then
        _axle_ui_tty && { _axle_config_set_interactive $name; return }
        print -u2 "usage: axle config set $name <value>"; return 1
      fi
      local kind=text line
      if _axle_setting $name; then kind=$reply[2]
      else print -u2 "axle config: $name isn't a known setting; saving it anyway"; fi
      if [[ $kind == list || ${(tP)name} == array* ]]; then
        line="$name=(${(j: :)${(q-)@}})"
        typeset -ga $name; set -A $name "$@"
      else
        _axle_config_check $kind "$*" || { print -u2 "axle config: $name must be $REPLY"; return 1 }
        line="$name=${(q-)*}"
        typeset -g $name="$*"
      fi
      _axle_config_write $name "$line" || return 1
      print -r -- "axle: $line  (saved to ${AXLE_CONFIG/#$HOME/~})"
      _axle_cmd_reload ;;
    unset|rm)
      [[ -n $name ]] || { print -u2 "usage: axle config unset <NAME>"; return 1 }
      _axle_config_saved $name || { print -r -- "axle: $name isn't in ${AXLE_CONFIG/#$HOME/~}"; return 0 }
      _axle_config_write $name '' || return 1
      unset $name
      print -r -- "axle: $name removed (back to the default, or your ~/.zshrc value in a new shell)"
      _axle_cmd_reload ;;
    edit)
      mkdir -p ${AXLE_CONFIG:h}
      [[ -e $AXLE_CONFIG ]] || print -r -- '# Axle settings (axle config, axle configure)' > $AXLE_CONFIG
      ${=${VISUAL:-${EDITOR:-vi}}} $AXLE_CONFIG && _axle_cmd_reload ;;
    path) print -r -- $AXLE_CONFIG ;;
    *) print -u2 "usage: axle config [list | get <NAME> | set <NAME> <value> | unset <NAME> | edit | path]"; return 1 ;;
  esac
}
