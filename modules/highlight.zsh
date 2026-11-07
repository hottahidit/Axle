# Syntax highlighting as you type, in the spirit of zsh-syntax-highlighting: the command
# turns green when it exists and red when it doesn't, and options, strings, variables,
# globs, operators, comments and existing paths (underlined) each get their own colour,
# from the prompt's palette.
#
#   AXLE_HIGHLIGHT=1            0 = off
#   AXLE_HIGHLIGHT_MAX=2000     lines longer than this aren't highlighted (big pastes)
#   typeset -A AXLE_HIGHLIGHT_STYLES=(unknown 'fg=red,bold' path 'underline')   per kind:
#     command unknown reserved option string variable glob operator comment path assign
#
# Steps aside when zsh-syntax-highlighting or fast-syntax-highlighting is loaded.

: ${AXLE_HIGHLIGHT:=1} ${AXLE_HIGHLIGHT_MAX:=2000}

typeset -gA _axle_hl_style _axle_hl_known
typeset -g  _axle_hl_buf=$'\0' _axle_hl_path=''
typeset -gi _axle_hl_checked=0

_axle_hl_styles() {
  _axle_hl_style=(
    command  "fg=${_axle_c[ok]:-green}"
    unknown  "fg=${_axle_c[error]:-red}"
    reserved "fg=${_axle_c[accent]:-magenta},bold"
    option   "fg=${_axle_c[warn]:-208}"
    string   "fg=${_axle_c[dirty]:-yellow}"
    variable "fg=${_axle_c[ahead]:-cyan}"
    glob     "fg=${_axle_c[path]:-blue}"
    operator "fg=${_axle_c[accent]:-magenta}"
    comment  "fg=${_axle_c[muted]:-244}"
    assign   "fg=${_axle_c[stash]:-147}"
    path     "underline"
  )
  (( ${+AXLE_HIGHLIGHT_STYLES} )) && _axle_hl_style+=("${(@kv)AXLE_HIGHLIGHT_STYLES}")
}

# Does a command word name something runnable? Answers are remembered, since a lookup of
# an unknown name searches every PATH folder (slow when PATH has Windows folders, on WSL).
# Forgotten when PATH changes, and unknown names every 10 s (something new installed).
_axle_hl_runnable() {
  local w=$1
  if [[ $PATH != $_axle_hl_path ]] || (( EPOCHSECONDS - _axle_hl_checked > 10 )); then
    [[ $PATH != $_axle_hl_path ]] && _axle_hl_known=() || _axle_hl_known=(${(kv)_axle_hl_known[(R)1]})
    _axle_hl_path=$PATH _axle_hl_checked=$EPOCHSECONDS
  fi
  if (( ! ${+_axle_hl_known[$w]} )); then
    if (( ${+aliases[$w]} || ${+functions[$w]} || ${+builtins[$w]} || ${reswords[(Ie)$w]} )) ||
       [[ $w == */* && -x ${~w} && ! -d ${~w} ]] || whence -p -- $w >/dev/null 2>&1; then
      _axle_hl_known[$w]=1
    else
      _axle_hl_known[$w]=0
    fi
  fi
  (( ${_axle_hl_known[$w]} ))                      # (expanded first: a word like ] is no subscript)
}

_axle_hl_add() {   # _axle_hl_add <start> <end> <kind>
  local st=${_axle_hl_style[$3]}
  [[ -n $st ]] && _axle_hl_out+=("$1 $2 $st,memo=axle-hl")
}

# Colour the words of $BUFFER (region_highlight entries tagged memo=axle-hl).
_axle_hl_paint() {
  setopt localoptions extendedglob
  local -a _axle_hl_out=() words
  words=(${(Z+c+)BUFFER})
  local tok kind
  local -i pos=1 start end expect=1 redirect=0 incond=0 afterpre=0
  local -a seps=('|' '||' '&&' ';' '&' '|&' ';;' ';&' ';|' '&!' '&|' '(' ')' '{' '}' '()')
  local -a precmds=(sudo doas nocorrect noglob command builtin exec nohup time env nice)
  for tok in $words; do
    # Find the word in the line: skip spaces (and escaped newlines) before it.
    while [[ ${BUFFER[pos]} == [[:space:]] && ! ( $tok == ';' && ${BUFFER[pos]} == $'\n' ) ]] ||
          [[ ${BUFFER[pos,pos+1]} == $'\\\n' ]]; do
      [[ ${BUFFER[pos]} == '\' ]] && (( pos++ ))
      (( pos++ ))
    done
    start=$(( pos - 1 ))
    if [[ $tok == ';' && ${BUFFER[pos]} == $'\n' ]]; then
      end=$(( start + 1 ))                  # a newline, which (z) reports as ;
    elif [[ ${BUFFER[pos,pos+${#tok}-1]} == $tok ]]; then
      end=$(( start + ${#tok} ))
    else
      break                                 # lost track of the line: stop rather than guess
    fi
    pos=$(( end + 1 ))
    kind=''
    if [[ $tok == \#* ]]; then
      kind=comment
    elif (( ${seps[(Ie)$tok]} )); then
      kind=operator; expect=1 redirect=0
      [[ $tok == (')'|'}') ]] && expect=0
    elif [[ $tok == ([0-9]#|'&')(\>|\>\>|\<|\>\||\>\&|\<\&|\<\<|\<\<\<|\<\>)(|-) ]]; then
      kind=operator; redirect=1
    elif (( redirect )); then
      redirect=0
      [[ -e ${~${(Q)tok}} ]] 2>/dev/null && kind=path
    elif [[ $tok == ']]' ]]; then
      kind=reserved; incond=0
    elif (( expect && ! incond )); then
      if [[ $tok == [[:alpha:]_][[:alnum:]_]#(\[*\])#(+|)=* ]]; then
        _axle_hl_add $start $(( start + ${#${tok%%=*}} )) assign
        [[ ${tok#*=} == [\"\']* ]] && _axle_hl_add $(( start + ${#${tok%%=*}} + 1 )) $end string
        continue                            # still waiting for the command
      elif [[ $tok == '[[' ]]; then
        kind=reserved; incond=1 expect=0
      elif (( ${reswords[(Ie)$tok]} )); then
        kind=reserved
        [[ $tok == (for|foreach|select|case|function|repeat) ]] && expect=0
      elif [[ $tok == *[\$\`]* ]]; then
        kind=variable; expect=0
      elif [[ $tok == -* ]] && (( afterpre )); then
        kind=option                         # sudo -E ...: still before the command
      elif _axle_hl_runnable ${(Q)tok}; then
        kind=command; expect=0 afterpre=0
        (( ${precmds[(Ie)$tok]} )) && expect=1 afterpre=1     # sudo, time, ...: a command follows
      else
        kind=unknown; expect=0 afterpre=0
      fi
    else
      case $tok in
        -*)              kind=option ;;
        \$\'*|\'*)       kind=string ;;
        \"*)             kind=string
                         # $variables inside double quotes
                         local rest=$tok; local -i off=0 at
                         while [[ $rest == (#b)(*)(\$[[:alnum:]_]##|\$\{[^\}]#\}|\$\([^\)]#\))* ]]; do
                           at=$(( ${#match[1]} ))
                           _axle_hl_add $(( start + at )) $(( start + at + ${#match[2]} )) variable
                           rest=$match[1]
                         done ;;
        *[\$\`]*)        kind=variable ;;
        *[\*\?]*|*\[*\]*) kind=glob ;;
        *)               [[ -e ${~${(Q)tok}} ]] 2>/dev/null && kind=path ;;
      esac
    fi
    [[ $kind == string ]] && { _axle_hl_out=("$start $end ${_axle_hl_style[string]},memo=axle-hl" $_axle_hl_out); continue }
    [[ -n $kind ]] && _axle_hl_add $start $end $kind
  done
  region_highlight=(${region_highlight:#*memo=axle-hl*} $_axle_hl_out)
}

_axle_hl_redraw() {
  (( AXLE_HIGHLIGHT )) || return
  [[ $BUFFER == $_axle_hl_buf ]] && return
  _axle_hl_buf=$BUFFER
  if [[ -z $BUFFER ]] || (( ${#BUFFER} > AXLE_HIGHLIGHT_MAX )); then
    region_highlight=(${region_highlight:#*memo=axle-hl*})
    return
  fi
  (( ${#_axle_hl_style} )) || _axle_hl_styles
  _axle_hl_paint
}

# --- install -------------------------------------------------------------------------

if (( AXLE_HIGHLIGHT && $+builtins[zle] )) && (( ! $+functions[_zsh_highlight] )); then
  zmodload zsh/parameter 2>/dev/null
  autoload -Uz add-zle-hook-widget
  add-zle-hook-widget line-pre-redraw _axle_hl_redraw
  _axle_hl_style=()                       # re-read the palette (a reload or palette switch)
fi
