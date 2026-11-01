# Questionary-style prompts, in plain zsh (no Python, nothing to install). Shared by
# `axle configure`, `axle config` and `axle uninstall`.
#
#   axle_select   <question> <default value> <label:value>...   choice in REPLY
#   axle_checkbox <question> <values on> <label:value>...       choices in reply=()
#   axle_confirm  <question> [y|n]                               status 0 = yes
#   axle_input    <question> [default]                           text in REPLY
#
# ↑/↓ (or k/j, or a number) move, Space ticks a box, Enter answers, Esc / q / Ctrl-C
# cancels (status 1). The question then shrinks to one line with the answer, like
# questionary. Without a terminal (a script, a pipe) the default is taken.

_axle_ui_tty() { [[ -t 0 && -t 1 ]] }

# One key, with arrow keys decoded (REPLY = up|down|left|right|enter|space|esc|tab|<char>).
_axle_ui_key() {
  local k k2 k3
  read -rsk1 k || { REPLY=esc; return }
  case $k in
    $'\e')
      if read -rsk1 -t 0.05 k2 && [[ $k2 == ('['|O) ]] && read -rsk1 -t 0.05 k3; then
        case $k3 in A) REPLY=up ;; B) REPLY=down ;; C) REPLY=right ;; D) REPLY=left ;; *) REPLY=other ;; esac
      else
        REPLY=esc
      fi ;;
    $'\n'|$'\r') REPLY=enter ;;
    ' ')         REPLY=space ;;
    $'\t')       REPLY=tab ;;
    $'\x03')     REPLY=esc ;;
    $'\x10')     REPLY=up ;;      # Ctrl-P
    $'\x0e')     REPLY=down ;;    # Ctrl-N
    *)           REPLY=$k ;;
  esac
}

typeset -gi _axle_ui_drawn=0

# Redraw the block in place: move up over what was drawn last time and clear it.
_axle_ui_draw() {
  (( _axle_ui_drawn )) && print -n "\e[${_axle_ui_drawn}A\r\e[J"
  local line
  for line in "$@"; do _axle_printp "$line"; done
  _axle_ui_drawn=$#
}

# The question, shrunk to one line with its answer.
_axle_ui_done() {
  (( _axle_ui_drawn )) && print -n "\e[${_axle_ui_drawn}A\r\e[J"
  _axle_ui_drawn=0
  print -n '\e[?25h'
  local q=${1//\%/%%} a=${2//\%/%%}
  if [[ $3 == cancel ]]; then
    _axle_printp "%F{${_axle_c[muted]:-244}}✗ $q%f"
  else
    _axle_printp "%F{${_axle_c[ok]:-green}}✔%f %B$q%b %F{${_axle_c[accent]:-magenta}}$a%f"
  fi
}

# Fit a label on one line (a wrapped line would throw off the in-place redraw).
_axle_ui_fit() {
  local -i w=$(( ${COLUMNS:-80} - ${2:-6} ))
  (( w > 10 )) || w=10
  REPLY=$1
  (( ${#REPLY} > w )) && REPLY="${REPLY[1,w-1]}…"
  REPLY=${REPLY//\%/%%}
}

axle_select() {
  local q=$1 def=$2; shift 2
  local -a labels values
  local opt
  for opt; do labels+=("${opt%:*}"); values+=("${opt##*:}"); done   # label:value (last colon)
  local -i n=${#labels} cur=${values[(Ie)$def]}
  (( cur )) || cur=1
  if ! _axle_ui_tty; then REPLY=${values[cur]}; return 0; fi
  setopt localoptions localtraps
  trap '_axle_ui_done "$q" "" cancel; return 1' INT
  local hint="%F{${_axle_c[muted]:-244}}(↑↓ move · Enter choose · Esc cancel)%f" a=${_axle_c[accent]:-magenta}
  local -a block
  local -i i
  print -n '\e[?25l'
  _axle_ui_drawn=0
  while :; do
    block=("%F{$a}?%f %B${q//\%/%%}%b  $hint")
    for i in {1..$n}; do
      _axle_ui_fit "${labels[i]}"
      if (( i == cur )); then block+=("%F{$a}❯ $REPLY%f"); else block+=("  $REPLY"); fi
    done
    _axle_ui_draw "${block[@]}"
    _axle_ui_key
    case $REPLY in
      up|k)        (( cur = cur > 1 ? cur - 1 : n )) ;;
      down|j|tab)  (( cur = cur < n ? cur + 1 : 1 )) ;;
      [1-9])       (( REPLY <= n )) && cur=$REPLY ;;
      enter)       break ;;
      esc|q)       _axle_ui_done "$q" "" cancel; return 1 ;;
    esac
  done
  _axle_ui_done "$q" "${labels[cur]}"
  REPLY=${values[cur]}
}

axle_checkbox() {
  local q=$1; shift
  local -a on=(${=1}) labels values; shift
  local opt
  for opt; do labels+=("${opt%:*}"); values+=("${opt##*:}"); done
  local -i n=${#labels} cur=1
  if ! _axle_ui_tty; then reply=($on); return 0; fi
  setopt localoptions localtraps
  trap '_axle_ui_done "$q" "" cancel; return 1' INT
  local hint="%F{${_axle_c[muted]:-244}}(↑↓ move · Space tick · a all · Enter done)%f" a=${_axle_c[accent]:-magenta}
  local -a block
  local -i i
  local box
  print -n '\e[?25l'
  _axle_ui_drawn=0
  while :; do
    block=("%F{$a}?%f %B${q//\%/%%}%b  $hint")
    for i in {1..$n}; do
      _axle_ui_fit "${labels[i]}" 8
      box='○'; (( ${on[(Ie)${values[i]}]} )) && box="%F{${_axle_c[ok]:-green}}●%f"
      if (( i == cur )); then block+=("%F{$a}❯%f $box %F{$a}$REPLY%f"); else block+=("  $box $REPLY"); fi
    done
    _axle_ui_draw "${block[@]}"
    _axle_ui_key
    case $REPLY in
      up|k)       (( cur = cur > 1 ? cur - 1 : n )) ;;
      down|j|tab) (( cur = cur < n ? cur + 1 : 1 )) ;;
      [1-9])      (( REPLY <= n )) && cur=$REPLY ;;
      space|x)
        if (( ${on[(Ie)${values[cur]}]} )); then on=(${on:#${values[cur]}}); else on+=(${values[cur]}); fi ;;
      a)          if (( ${#on} == n )); then on=(); else on=($values); fi ;;
      enter)      break ;;
      esc|q)      _axle_ui_done "$q" "" cancel; return 1 ;;
    esac
  done
  reply=()
  local -a shown=()
  for i in {1..$n}; do
    (( ${on[(Ie)${values[i]}]} )) && reply+=(${values[i]}) && shown+=("${labels[i]%% — *}")
  done
  _axle_ui_done "$q" "${(j:, :)shown:-none}"
}

axle_confirm() {
  local q=$1 def=${2:-n}
  if ! _axle_ui_tty; then [[ $def == y ]]; return; fi
  setopt localoptions localtraps
  trap '_axle_ui_done "$q" "" cancel; return 1' INT
  local hint='(y/N)'; [[ $def == y ]] && hint='(Y/n)'
  _axle_ui_drawn=0
  _axle_ui_draw "%F{${_axle_c[accent]:-magenta}}?%f %B${q//\%/%%}%b %F{${_axle_c[muted]:-244}}$hint%f"
  local answer=$def
  while :; do
    _axle_ui_key
    case $REPLY in
      y|Y)   answer=y; break ;;
      n|N)   answer=n; break ;;
      enter) break ;;
      esc|q) _axle_ui_done "$q" "" cancel; return 1 ;;
    esac
  done
  _axle_ui_done "$q" "${${answer:#n}:+Yes}${${answer:#y}:+No}"
  [[ $answer == y ]]
}

axle_input() {
  local q=$1 def=$2
  REPLY=$def
  _axle_ui_tty || return 0
  setopt localoptions localtraps
  trap 'print; _axle_ui_drawn=1; _axle_ui_done "$q" "" cancel; return 1' INT
  _axle_printp "%F{${_axle_c[accent]:-magenta}}?%f %B${q//\%/%%}%b"
  local text=$def
  vared -p '  ' text || { _axle_ui_drawn=2; _axle_ui_done "$q" "" cancel; return 1 }
  _axle_ui_drawn=2
  _axle_ui_done "$q" "$text"
  REPLY=$text
}
