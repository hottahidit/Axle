# search: Ctrl-R opens a history picker under the prompt. Type to filter (every word must
# match, in any order); ↑/↓ or Ctrl-R / Ctrl-P / Ctrl-N to move; Enter puts the command on
# the line (edit it, or press Enter again to run it); Esc or Ctrl-G cancels. Tab switches
# what's shown: all history → only this folder → only commands that worked. Each entry
# shows when it last ran, where, and ✗ if it last failed.
#
#   AXLE_SEARCH_KEY='^R'    the key that opens it ('' = no binding)
#   AXLE_SEARCH_ROWS=10     rows shown

: ${AXLE_SEARCH_ROWS:=10}
(( ${+AXLE_SEARCH_KEY} )) || typeset -g AXLE_SEARCH_KEY='^R'

typeset -ga _axle_sr_all _axle_sr_here _axle_sr_ok
typeset -gA _axle_sr_info                 # command -> "last<TAB>exit<TAB>dir"

# "5m", "3h", "2d", "4w" for an age in seconds.
_axle_ago() {
  local -i a=$1
  if   (( a < 60 ));     then REPLY=now
  elif (( a < 3600 ));   then REPLY="$(( a / 60 ))m"
  elif (( a < 86400 ));  then REPLY="$(( a / 3600 ))h"
  elif (( a < 604800 )); then REPLY="$(( a / 86400 ))d"
  else                        REPLY="$(( a / 604800 ))w"
  fi
}

# Everything to search, newest first: what axle recorded (with when/where/outcome), then
# the rest of the shell history.
_axle_sr_load() {
  _axle_sr_all=() _axle_sr_here=() _axle_sr_ok=() _axle_sr_info=()
  local last ex dir here cmd
  if [[ -r $_axle_hist_file ]]; then
    command awk -F'\t' -v pwd="$PWD" '
      NF == 6 && $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ { at[$6] = NR; t[$6] = $1; x[$6] = $2; d[$6] = $4; if ($4 == pwd) h[$6] = 1 }
      END { for (c in at) byline[at[c]] = c
            for (i = NR; i > 0; i--) if (i in byline) { c = byline[i]
              print t[c] "\t" x[c] "\t" d[c] "\t" (c in h) "\t" c } }' $_axle_hist_file |
    while IFS=$'\t' read -r last ex dir here cmd; do
      cmd=${cmd//\\n/$'\n'}
      _axle_sr_all+=("$cmd")
      _axle_sr_info[$cmd]="$last"$'\t'"$ex"$'\t'"$dir"
      (( here )) && _axle_sr_here+=("$cmd")
      [[ $ex == 0 ]] && _axle_sr_ok+=("$cmd")
    done
  fi
  local -A seen
  for cmd in $_axle_sr_all; do seen[$cmd]=1; done
  local event
  for event in ${(kOn)history}; do
    cmd=$history[$event]
    (( ${+seen[$cmd]} )) && continue
    seen[$cmd]=1
    _axle_sr_all+=("$cmd")
  done
}

axle-search() {
  setopt localoptions extendedglob
  (( $+functions[_axle_sg_clear] )) && _axle_sg_clear
  _axle_sr_load
  local orig=$BUFFER query=$BUFFER key k2 k3 w
  local -i sel=1 top=1 mode=1 rows=$AXLE_SEARCH_ROWS
  local -a modes=(all here ok) labels=('all history' 'this folder' 'worked') pool shown
  local accent=${_axle_c[accent]:-magenta} muted=${_axle_c[muted]:-244} bad=${_axle_c[error]:-red}
  # (Declared once here: `local x` again inside the loop would print x's value.)
  local post head c meta info mark
  local -a f
  local -i base i w2 failed room s e ms fs
  while :; do
    pool=("${(@P)${:-_axle_sr_${modes[mode]}}}")
    for w in ${(z)query}; do pool=(${(M)pool:#(#i)*${(b)w}*}); done
    (( sel > ${#pool} )) && sel=${#pool}
    (( sel < 1 )) && sel=1
    (( sel < top )) && top=$sel
    (( sel >= top + rows )) && top=$(( sel - rows + 1 ))
    shown=("${(@)pool[top,top+rows-1]}")

    # Draw: the query on the line, the picker below it.
    BUFFER=$query CURSOR=${#query}
    region_highlight=(${region_highlight:#*memo=axle-search*})
    head="  search · ${labels[mode]} · ${#pool} match${${${#pool}:#1}:+es}   Tab: filter  Enter: choose  Esc: cancel"
    base=${#BUFFER} w2=$(( ${COLUMNS:-80} - 4 ))
    post=$'\n'$head
    region_highlight+=("$(( base + 1 )) $(( base + ${#post} )) fg=$muted,memo=axle-search")
    for i in {1..${#shown}}; do
      c=${shown[i]//$'\n'/ ⏎ } meta='' info=${_axle_sr_info[${shown[i]}]} failed=0
      if [[ -n $info ]]; then
        f=("${(@ps:\t:)info}")
        _axle_ago $(( EPOCHSECONDS - f[1] ))
        meta="  $REPLY · ${${f[3]/#$HOME/~}[-24,-1]}"
        [[ $f[2] != 0 ]] && failed=1
      fi
      mark='    '; (( top + i - 1 == sel )) && mark='  ▸ '
      room=$(( w2 - ${#mark} - ${#meta} - 2 ))
      (( room < 10 )) && room=10
      (( ${#c} > room )) && c="${c[1,room-1]}…"
      s=$(( base + ${#post} + 1 ))
      post+=$'\n'"$mark$c"
      e=$(( base + ${#post} ))
      if (( top + i - 1 == sel )); then
        region_highlight+=("$s $e fg=$accent,bold,memo=axle-search")
      fi
      if [[ -n $meta ]]; then
        ms=$(( base + ${#post} ))
        post+=$meta
        region_highlight+=("$ms $(( base + ${#post} )) fg=$muted,memo=axle-search")
      fi
      if (( failed )); then
        fs=$(( base + ${#post} ))
        post+=' ✗'
        region_highlight+=("$fs $(( base + ${#post} )) fg=$bad,memo=axle-search")
      fi
    done
    (( ${#pool} )) || post+=$'\n'"    nothing matches"
    POSTDISPLAY=$post
    zle -R

    read -rsk key || break
    case $key in
      $'\r'|$'\n') [[ -n ${pool[sel]} ]] && BUFFER=${pool[sel]}; break ;;
      $'\e')
        k2='' k3=''
        read -rsk -t 0.03 k2 && read -rsk -t 0.03 k3
        case $k2$k3 in
          '[A'|OA) (( sel-- )) ;;
          '[B'|OB) (( sel++ )) ;;
          *) BUFFER=$orig; break ;;              # Esc alone: cancel
        esac ;;
      $'\t')            mode=$(( mode % ${#modes} + 1 )) sel=1 top=1 ;;
      $'\x12'|$'\x0e')  (( sel++ )) ;;             # Ctrl-R / Ctrl-N: next
      $'\x10')          (( sel-- )) ;;             # Ctrl-P: previous
      $'\x7f'|$'\b')    query=${query[1,-2]} sel=1 top=1 ;;
      $'\x15')          query='' sel=1 top=1 ;;    # Ctrl-U
      $'\x07'|$'\x03')  BUFFER=$orig; break ;;     # Ctrl-G / Ctrl-C
      *) [[ $key == [[:print:]] ]] && query+=$key sel=1 top=1 ;;
    esac
  done
  POSTDISPLAY=''
  region_highlight=(${region_highlight:#*memo=axle-search*})
  CURSOR=${#BUFFER}
  (( $+functions[_axle_sg_clear] )) && _axle_sg_buffer=$BUFFER _axle_sg_cursor=$CURSOR
  zle -R
}

if (( $+builtins[zle] )); then
  zle -N axle-search
  if [[ -n $AXLE_SEARCH_KEY ]]; then
    bindkey -M emacs $AXLE_SEARCH_KEY axle-search
    bindkey -M viins $AXLE_SEARCH_KEY axle-search
  fi
fi
