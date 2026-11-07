# axle run top: the background services, live. Two views of the same numbers:
#
#   axle run top           the full view (the whole terminal): every service with CPU and
#                          memory bars, graphs of both over time, the selected one's details
#                          and its last log lines
#   axle run top --mini    a few lines under the prompt, one per service, for a quick look
#
#   ↑↓ / k j  select       s  stop (asks)     r  restart     o  open its URL
#   l  follow its log (Ctrl-C comes back)    m  the other view     q / Esc  quit
#
# With Axle's btop built (install.sh, or `axle top --build`), `axle run top` opens it in the
# Axle mode instead: only the processes axle run started (key A: all of them). --mini and
# --full are always these views here; so is everything when it isn't built.
#
# It samples once a second. On Linux everything comes from /proc (no process is started
# per second; the list of a service's child processes is rebuilt every 5 s), elsewhere from
# one `ps`. A frame is written in one go over the last one (no clearing), so it doesn't
# flicker. Without a terminal it prints the mini view once. The view you leave it in is
# the one it opens with next time.

typeset -gA _axle_top                # <name>:<field> → value (state, port, cpu, mem, ...)
typeset -gA _axle_top_c              # colour escapes
typeset -ga _axle_top_names _axle_top_hcpu
typeset -gF _axle_top_at=0
typeset -gi _axle_top_ticks=0

_axle_top_init() {
  local k
  local -A def=(muted 244 accent magenta ok green error red warn yellow sep 240 path cyan)
  for k in ${(k)def}; do _axle_top_c[$k]=${(%):-"%F{${_axle_c[$k]:-$def[$k]}}"}; done
  _axle_top_c[off]=$'\e[0m' _axle_top_c[b]=$'\e[1m'
  _axle_top=() _axle_top_names=() _axle_top_hcpu=() _axle_top_at=0 _axle_top_ticks=0
}

# --- Sampling ---------------------------------------------------------------------------

# The service list and what's in their state folders (every 5 s, or when asked).
_axle_top_list() {
  local -a reply
  local n d REPLY f
  _axle_run_services
  _axle_top_names=(${(o)reply})
  for n in $_axle_top_names; do
    d=$_axle_run_dir/services/$n
    for f in state port url pid started kind root code; do
      _axle_run_get $d $f; _axle_top[${n}:$f]=$REPLY
    done
  done
}

# The process tree under each service's pid (Linux: from /proc; "<name>:tree").
_axle_top_trees_proc() {
  local f line pid n p
  local -A kids
  local -a rest
  for f in /proc/<->/stat(N); do
    IFS= read -r line 2>/dev/null < $f || continue  # (gone since: the error first)
    rest=(${=${line##*\) }})
    pid=${${f#/proc/}%/stat}
    kids[$rest[2]]+=" $pid"
  done
  for n in $_axle_top_names; do
    p=$_axle_top[${n}:pid]
    [[ -n $p ]] || { _axle_top[${n}:tree]=''; continue }
    local -a tree=($p); local -i i=1
    while (( i <= ${#tree} )); do tree+=(${=kids[$tree[i]]}); (( i++ )); done
    _axle_top[${n}:tree]=${(j: :)tree}
  done
}

_axle_top_sample() {
  local -F now=$EPOCHREALTIME
  _axle_top_at=$now
  local n pid line f REPLY
  if (( _axle_top_ticks++ % 5 == 0 )); then
    _axle_top_list
    [[ -d /proc/self ]] && _axle_top_trees_proc
  else
    for n in $_axle_top_names; do
      for f in state port url code; do _axle_run_get $_axle_run_dir/services/$n $f; _axle_top[${n}:$f]=$REPLY; done
    done
  fi
  local -F cpu total=0
  local -i ticks kb
  local -a rest
  local -A pcpu prss pkids
  if [[ ! -d /proc/self ]]; then                   # (macOS, BSD: one ps)
    local -a w
    for line in ${(f)"$(command ps -A -o pid= -o ppid= -o rss= -o %cpu= 2>/dev/null)"}; do
      w=(${=line}); prss[$w[1]]=$w[3] pcpu[$w[1]]=$w[4]; pkids[$w[2]]+=" $w[1]"
    done
  fi
  for n in $_axle_top_names; do
    _axle_top[${n}:cpu]='' _axle_top[${n}:mem]=''
    pid=$_axle_top[${n}:pid]
    [[ -n $pid && $_axle_top[${n}:state] != crashed && $_axle_top[${n}:kind] != compose ]] || continue
    if ! kill -0 $pid 2>/dev/null; then
      _axle_top[${n}:state]=gone; continue
    fi
    ticks=0 kb=0 cpu=0
    if [[ -d /proc/self ]]; then
      for pid in ${=_axle_top[${n}:tree]}; do
        IFS= read -r line 2>/dev/null < /proc/$pid/stat || continue
        rest=(${=${line##*\) }})
        (( ticks += rest[12] + rest[13], kb += rest[22] * 4 ))
      done
      # CPU: clock ticks (100 a second) over the last two samples (the kernel can count a
      # busy process late, then all at once: one second alone would jump).
      local -a was=(${=_axle_top[${n}:ticks]})
      if (( ${#was} >= 2 )); then
        local -F span=$(( now - was[1] ))
        (( span > 0 )) && (( cpu = (ticks - was[2]) / span ))
        (( cpu < 0 )) && cpu=0
      fi
      local -a keep=(${=_axle_top[${n}:ticks]} $now $ticks)
      (( ${#keep} > 4 )) && keep=($keep[-4,-1])
      _axle_top[${n}:ticks]=${(j: :)keep}
    else
      local -a tree=($pid); local -i i=1
      while (( i <= ${#tree} )); do tree+=(${=pkids[$tree[i]]}); (( i++ )); done
      for pid in $tree; do (( cpu += ${pcpu[$pid]:-0}, kb += ${prss[$pid]:-0} )); done
    fi
    local -i icpu=$(( cpu + 0.5 ))
    _axle_top[${n}:cpu]=$icpu _axle_top[${n}:mem]=$kb
    (( total += cpu ))
    # The last 300 samples of each.
    local -a h=(${=_axle_top[${n}:hcpu]} $icpu) m=(${=_axle_top[${n}:hmem]} $kb)
    (( ${#h} > 300 )) && h=($h[-300,-1]) m=($m[-300,-1])   # (a slice from before the start is empty)
    _axle_top[${n}:hcpu]=${(j: :)h} _axle_top[${n}:hmem]=${(j: :)m}
  done
  local -i itotal=$(( total + 0.5 ))
  _axle_top_hcpu+=($itotal)
  (( ${#_axle_top_hcpu} > 300 )) && _axle_top_hcpu=($_axle_top_hcpu[-300,-1])
}

# --- Drawing pieces ---------------------------------------------------------------------

# <text> cut or padded to <width> columns (REPLY); control characters and colours removed.
_axle_top_fit() {
  local s=$1
  if [[ $s == *[[:cntrl:]]* ]]; then              # (most text has none: no work then)
    setopt localoptions extendedglob
    s=${s//$'\e'\[[0-9;?]#[a-zA-Z]/}
    s=${${s//$'\t'/ }//[[:cntrl:]]/}
  fi
  local -i w=$2
  (( w > 0 )) || { REPLY=''; return }
  if (( ${(m)#s} > w )); then REPLY="${(mr:w-1:: :)s}…"; else REPLY=${(mr:w:: :)s}; fi
}

_axle_top_mb() {                                   # kB → "120M" / "1.4G" (REPLY)
  local -i kb=$1
  if (( kb >= 1048576 )); then printf -v REPLY '%.1fG' $(( kb / 1048576.0 ))
  elif (( kb >= 1024 )); then REPLY="$(( kb / 1024 ))M"
  else REPLY="${kb}K"; fi
}

_axle_top_up() {                                   # seconds → "2h 3m" (REPLY)
  local -i s=$1
  if (( s >= 86400 )); then REPLY="$(( s / 86400 ))d $(( s % 86400 / 3600 ))h"
  elif (( s >= 3600 )); then REPLY="$(( s / 3600 ))h $(( s % 3600 / 60 ))m"
  elif (( s >= 60 )); then REPLY="$(( s / 60 ))m $(( s % 60 ))s"
  else REPLY="${s}s"; fi
}

# A bar <width> long, <value> of <max> filled (REPLY, coloured).
_axle_top_bar() {
  local -i w=$3 f=$(( $2 > 0 ? $1 * $3 / $2 : 0 ))
  (( f > w )) && f=w; (( f < 0 )) && f=0
  (( $1 > 0 && f == 0 )) && f=1
  local c=$_axle_top_c[ok]
  (( $1 * 100 >= $2 * 85 )) && c=$_axle_top_c[error] || { (( $1 * 100 >= $2 * 60 )) && c=$_axle_top_c[warn] }
  REPLY="$c${(pl:f::█:)}$_axle_top_c[sep]${(pl:w-f::░:)}$_axle_top_c[off]"
}

# One line of the last <width> values as ▁▂▃▄▅▆▇█ (REPLY), scaled to <max> (default: theirs).
_axle_top_spark() {
  local -a v=(${=1}); local -i w=$2 max=${3:-0} x i
  local blocks=' ▁▂▃▄▅▆▇█'
  (( ${#v} > w )) && v=($v[-w,-1])
  for x in $v; do (( x > max )) && max=x; done
  (( max )) || max=1
  REPLY=''
  for x in $v; do i=$(( x * 8 / max )); (( x > 0 && i == 0 )) && i=1; REPLY+=${blocks[i+1]}; done
  REPLY=${(l:w:: :)REPLY}
}

# A graph <height> rows tall of the last <width> values (reply, top row first), scaled to
# <max> (default: the highest shown).
_axle_top_graph() {
  local -a v=(${=1}); local -i w=$2 h=$3 max=${4:-0} x r c
  local blocks=' ▁▂▃▄▅▆▇█' row
  (( ${#v} > w )) && v=($v[-w,-1])
  local -i pad=$(( w - ${#v} ))
  for x in $v; do (( x > max )) && max=x; done
  (( max )) || max=1
  reply=()
  for (( r = h - 1; r >= 0; r-- )); do
    row=${(l:pad:: :)}
    for x in $v; do
      (( c = x * h * 8 / max - r * 8 ))
      (( c > 8 )) && c=8; (( c < 0 )) && c=0
      (( r == 0 && x > 0 && c == 0 )) && c=1
      row+=${blocks[c+1]}
    done
    reply+=($row)
  done
}

# A box <width> wide (reply): its title and right-hand note in the top border, then the
# lines given (each exactly width-4 columns, colours allowed).
_axle_top_box() {
  local -i w=$1; local title=$2 note=$3; shift 3
  local s=$_axle_top_c[sep] o=$_axle_top_c[off] a=$_axle_top_c[accent] m=$_axle_top_c[muted] l
  local -i extra=0
  [[ -n $note ]] && extra=$(( ${(m)#note} + 3 ))
  local -i fill=$(( w - 6 - ${(m)#title} - extra ))
  (( fill < 0 )) && fill=0
  reply=("$s╭─ $o$_axle_top_c[b]$a$title$o $s${(pl:fill::─:)}${note:+─ $o$m$note$o $s}─╮$o")
  for l; do reply+=("$s│$o $l $s│$o"); done
  reply+=("$s╰${(pl:w-2::─:)}╯$o")
}

# A service's state as an icon and word: (icon colour icon word).
_axle_top_state() {
  local n=$1
  case $_axle_top[${n}:state] in
    up)       reply=(ok ⚡ up) ;;
    starting) reply=(muted ⏳ starting) ;;
    restarting) reply=(warn ↻ restarting) ;;
    unhealthy) reply=(warn ⚡ unhealthy) ;;
    crashed)  reply=(error ✘ "exit $_axle_top[${n}:code]") ;;
    gone)     reply=(muted · gone) ;;
    *)        reply=(muted · ${_axle_top[${n}:state]:--}) ;;
  esac
  [[ $_axle_top[${n}:kind] == compose ]] && reply=(ok ⚡ compose)
}

# --- The mini view -------------------------------------------------------------------------

_axle_top_mini() {
  local -i W=$1
  local -a lines
  local name REPLY mem total_mem=0 o=$_axle_top_c[off] m=$_axle_top_c[muted]
  for name in $_axle_top_names; do (( total_mem += ${_axle_top[${name}:mem]:-0} )); done
  _axle_top_mb $total_mem; mem=$REPLY
  local head="axle run top · ${#_axle_top_names} service${${#_axle_top_names:#1}:+s} · cpu ${_axle_top_hcpu[-1]:-0}% · mem $mem"
  (( ${(m)#head} > W - 26 )) && { _axle_top_fit "$head" $(( W - 26 )); head=$REPLY }
  lines=("$_axle_top_c[b]$head$o $m(m more · q quit)$o")
  (( ${#_axle_top_names} )) || lines+=("$m  nothing running (axle run starts one)$o")
  local -a st
  for name in $_axle_top_names; do
    _axle_top_state $name; st=($reply)
    _axle_top_fit $name 16; local nm=$REPLY
    local port=${_axle_top[${name}:port]:+:$_axle_top[${name}:port]}
    _axle_top_fit "$port" 6; port=$REPLY
    _axle_top_fit $st[2] 2; local icon=$REPLY
    local line="$_axle_top_c[$st[1]]$icon$o $_axle_top_c[b]$nm$o $port "
    if [[ $_axle_top[${name}:state] == crashed ]]; then
      line+="$_axle_top_c[error]$st[3]$o $m(axle run logs $name)$o"
    elif [[ -n $_axle_top[${name}:cpu] ]]; then
      _axle_top_up $(( EPOCHSECONDS - ${_axle_top[${name}:started]:-$EPOCHSECONDS} )); local up=${(r:7:)REPLY}
      _axle_top_mb $_axle_top[${name}:mem]; mem=${(l:5:)REPLY}
      _axle_top_spark "$_axle_top[${name}:hcpu]" 10 100; local sp=$REPLY
      line+="$m$up$o cpu ${(l:3:)_axle_top[${name}:cpu]}% $_axle_top_c[accent]$sp$o mem $mem"
    else
      line+="$m$st[3]$o"
    fi
    lines+=("$line")
  done
  reply=($lines)
}

# --- The full view -------------------------------------------------------------------------

# reply: exactly <height> lines of <width> columns. <sel>: the selected service.
_axle_top_full() {
  local -i W=$1 H=$2 iw=$(( $1 - 4 )) i
  local sel=$3 msg=$4 REPLY name
  local o=$_axle_top_c[off] m=$_axle_top_c[muted] a=$_axle_top_c[accent] b=$_axle_top_c[b]
  local -a frame st box g
  local -i total_mem=0 nsvc=${#_axle_top_names}
  for name in $_axle_top_names; do (( total_mem += ${_axle_top[${name}:mem]:-0} )); done
  _axle_top_mb $total_mem; local mem=$REPLY
  local clock; strftime -s clock '%H:%M:%S' $EPOCHSECONDS

  # The top: all services' CPU over time.
  local -i gh=$(( H >= 30 ? 4 : H >= 22 ? 3 : 2 ))
  _axle_top_graph "$_axle_top_hcpu" $(( iw - 9 )) $gh
  g=($reply); box=()
  for (( i = 1; i <= gh; i++ )); do
    local lbl='        '; (( i == 1 )) && lbl="cpu ${(l:3:)_axle_top_hcpu[-1]:-0}%"
    box+=("$m${(r:8:)lbl}$o $a$g[i]$o")
  done
  _axle_top_box $W "axle run top" "$nsvc service${${nsvc:#1}:+s} · mem $mem · $clock" $box
  frame+=($reply)

  # The services.
  local -i bars=$(( iw >= 110 )) nw=$(( iw >= 80 ? 18 : 12 ))
  local hdr="     ${(r:nw+1:)${:-NAME}}${(r:10:)${:-STATE}}${(r:7:)${:-PORT}}${(r:9:)${:-UPTIME}}"
  if (( bars )); then hdr+="${(r:17:)${:-CPU}}${(r:17:)${:-MEMORY}}"; else hdr+="${(r:6:)${:-CPU}}${(r:6:)${:-MEM}}"; fi
  local -i used=${#hdr}
  hdr+=URL
  _axle_top_fit "$hdr" $iw
  box=("$m$REPLY$o")
  (( nsvc )) || { _axle_top_fit "nothing running (axle run starts one)" $iw; box+=("$m$REPLY$o") }
  local -i maxrows=$(( H - ${#frame} - 2 - 1 - 1 - 6 ))   # (border, header, footer, details)
  (( maxrows < 1 )) && maxrows=1
  local -i first=1 si=${_axle_top_names[(Ie)$sel]}
  (( si > maxrows )) && first=$(( si - maxrows + 1 ))
  for name in $_axle_top_names[first,first+maxrows-1]; do
    _axle_top_state $name; st=($reply)
    local row=''
    local mark='  '; [[ $name == $sel ]] && mark="$a❯$o "
    _axle_top_fit $name $nw; local nm=$REPLY
    [[ $name == $sel ]] && nm="$a$b$nm$o" || nm="$b$nm$o"
    _axle_top_fit "$st[3]" 9; local sw=$REPLY
    _axle_top_fit "${_axle_top[${name}:port]:--}" 6; local pt=$REPLY
    local up='-'
    [[ $_axle_top[${name}:state] == (up|starting) ]] &&
      { _axle_top_up $(( EPOCHSECONDS - ${_axle_top[${name}:started]:-$EPOCHSECONDS} )); up=$REPLY }
    _axle_top_fit "$up" 8; up=$REPLY
    _axle_top_fit $st[2] 2; local icon=$REPLY
    row="$mark$_axle_top_c[$st[1]]$icon$o $nm $_axle_top_c[$st[1]]$sw$o $pt $m$up$o "
    local cpu=$_axle_top[${name}:cpu] kb=$_axle_top[${name}:mem] cm=''
    if [[ -n $cpu ]]; then
      _axle_top_mb $kb; local mb=$REPLY
      if (( bars )); then
        _axle_top_bar $cpu 100 10; cm="$REPLY ${(l:4:)cpu}% "
        _axle_top_bar $kb $(( total_mem > 0 ? total_mem : 1 )) 10; cm+="$REPLY ${(l:5:)mb} "
      else
        cm="${(l:4:)cpu}% ${(l:5:)mb} "
      fi
    else
      local -i cw=$(( bars ? 34 : 12 ))
      cm=${(l:cw:: :)}
    fi
    row+=$cm
    _axle_top_fit "$_axle_top[${name}:url]" $(( iw - used )); row+="$_axle_top_c[path]$REPLY$o"
    box+=("$row")
  done
  _axle_top_box $W services "${nsvc:+↑↓ select}" $box
  frame+=($reply)

  # The selected one: details and graphs, and its log.
  local -i rest=$(( H - ${#frame} - 1 ))
  if [[ -n $sel ]] && (( rest >= 5 )); then
    local d=$_axle_run_dir/services/$sel cmd=''
    if [[ -r $d/cmd ]]; then                       # (the program by its name, ~ for home)
      _axle_run_words $d/cmd
      reply[1]=${reply[1]:t}
      cmd=${(j: :)${(q-)reply}//$HOME\//\~/}
    fi
    local root=${_axle_top[${sel}:root]/#$HOME/~}
    local -i dw=$(( W >= 110 ? W * 2 / 5 : W ))     # (each its own line: values are
    local -i lw=$(( W - dw )) dh=$rest lh=0          # expanded before any is set)
    if (( lw == 0 )); then dh=$(( rest >= 10 ? 7 : rest )); lh=$(( rest - dh )); else lh=$rest; fi
    local -i diw=$(( dw - 4 ))
    box=()
    _axle_top_fit "$root" $diw; box+=("$_axle_top_c[path]$REPLY$o")
    _axle_top_fit "pid ${_axle_top[${sel}:pid]:--} · ${_axle_top[${sel}:kind]:-service}" $diw; box+=("$m$REPLY$o")
    _axle_top_fit "▶ $cmd" $diw; box+=("$REPLY")
    local -i grows=$(( dh - 2 - 3 ))
    if [[ -n $_axle_top[${sel}:cpu] ]] && (( grows >= 2 )); then
      local -i ch=$(( grows / 2 > 4 ? 4 : grows / 2 ))
      local -i mh=$(( grows - ch > 3 ? 3 : grows - ch ))
      _axle_top_graph "$_axle_top[${sel}:hcpu]" $(( diw - 9 )) $ch
      g=($reply)
      for (( i = 1; i <= ch; i++ )); do
        local lbl='        '; (( i == 1 )) && lbl="cpu ${(l:3:)_axle_top[${sel}:cpu]}%"
        box+=("$m${(r:8:)lbl}$o $a$g[i]$o")
      done
      _axle_top_mb $_axle_top[${sel}:mem]; local smb=$REPLY
      _axle_top_graph "$_axle_top[${sel}:hmem]" $(( diw - 9 )) $mh
      g=($reply)
      for (( i = 1; i <= mh; i++ )); do
        local lbl='        '; (( i == 1 )) && lbl="mem ${(l:4:)smb}"
        box+=("$m${(r:8:)lbl}$o $_axle_top_c[ok]$g[i]$o")
      done
    fi
    while (( ${#box} < dh - 2 )); do box+=("${(l:diw:: :)}"); done
    box=($box[1,dh-2])
    _axle_top_box $dw $sel "${_axle_top[${sel}:url]:+${_axle_top[${sel}:url]#http://}}" $box
    local -a detail=($reply) logbox=()
    if (( lh >= 3 )); then
      local -i lw2=$(( lw ? lw : W )) liw=$(( (lw ? lw : W) - 4 )) nl=$(( lh - 2 ))
      local -a lines=() size=()
      # Read again only when it has grown (tail is the one program run here).
      if [[ -r $d/log ]] && zstat -A size +size -- $d/log 2>/dev/null; then
        if [[ $_axle_top[${sel}:logkey] != $size[1]:$nl ]]; then
          _axle_top[${sel}:log]=$(command tail -n $nl -- $d/log 2>/dev/null)
          _axle_top[${sel}:logkey]=$size[1]:$nl
        fi
        lines=("${(@f)_axle_top[${sel}:log]}")
      fi
      [[ $_axle_top[${sel}:kind] == compose ]] && lines=("(docker compose: axle run logs $sel)")
      local l; box=()
      for l in $lines; do _axle_top_fit "$l" $liw; box+=("$REPLY"); done
      while (( ${#box} < nl )); do box+=("${(l:liw:: :)}"); done
      _axle_top_box $lw2 log "l follow" $box[-nl,-1]
      logbox=($reply)
    fi
    if (( lw )); then
      for (( i = 1; i <= ${#detail}; i++ )); do frame+=("$detail[i]$logbox[i]"); done
    else
      frame+=($detail $logbox)
    fi
  fi
  while (( ${#frame} < H - 1 )); do frame+=(''); done
  frame=($frame[1,H-1])
  # The keys, or what just happened.
  local keys=' ↑↓ select · s stop · r restart · o open · l log · m mini · q quit'
  [[ -n $msg ]] && keys=" $msg"
  _axle_top_fit "$keys" $(( W - 1 ))
  frame+=("$m$REPLY$o")
  reply=($frame)
}

# --- The loop -----------------------------------------------------------------------------

# A key, waiting up to <seconds> (REPLY: up, down, esc or the character; status 1: none).
# The rest of an arrow key (ESC [ A) is waited for up to 0.1 s: through Windows Terminal
# and WSL its bytes can come apart.
# (Read from stdin, which _axle_top_raw has set to one key at a time with no echo.)
_axle_top_key() {
  local k k2 k3
  REPLY=''
  read -u0 -rk1 -t $1 k || return 1
  case $k in
    $'\e')
      if read -u0 -rk1 -t 0.1 k2 && [[ $k2 == ('['|O) ]] && read -u0 -rk1 -t 0.1 k3; then
        case $k3 in A) REPLY=up ;; B) REPLY=down ;; *) REPLY=other ;; esac
      else
        REPLY=esc
      fi ;;
    $'\x03') REPLY=esc ;;
    *) REPLY=$k ;;
  esac
}

typeset -gi _axle_top_drawn=0 _axle_top_resized=0

_axle_top_draw() {
  local mode=$1 sel=$2 msg=$3
  local -i W=${COLUMNS:-80} H=${LINES:-24}
  local -a reply
  if [[ $mode == full ]]; then
    _axle_top_full $W $H "$sel" "$msg"
    print -rn -- $'\e[H'"${(pj:\e[K\n:)reply}"$'\e[K\e[J'
  else
    _axle_top_mini $W
    local out=''
    (( _axle_top_drawn )) && out=$'\r'
    (( _axle_top_drawn > 1 )) && out+=$'\e['$(( _axle_top_drawn - 1 ))'A'
    print -rn -- "$out${(pj:\e[K\n:)reply}"$'\e[K\e[J'
    _axle_top_drawn=${#reply}
  fi
}

_axle_top_enter() {
  # (no wrapping: a line too long for the terminal is cut, so the redraw stays in place)
  if [[ $1 == full ]]; then print -n '\e[?1049h\e[?25l\e[?7l\e[H\e[2J'
  else print -n '\e[?25l\e[?7l'; _axle_top_drawn=0; fi
}
_axle_top_leave() {
  if [[ $1 == full ]]; then print -n '\e[?7h\e[?25h\e[?1049l'
  else print -n '\e[?7h\e[?25h'; (( _axle_top_drawn )) && print; _axle_top_drawn=0; fi
}

# The terminal while it runs: keys one at a time (no line editing), not shown, Ctrl-C a key.
_axle_top_raw() { command stty -echo -icanon min 1 time 0 -isig 2>/dev/null }

_axle_run_top() {
  local mode='' a REPLY
  # Axle's btop, in the Axle mode (not for --mini / --full, or without a terminal).
  local btop=${_axle_top_bin:-$AXLE_ROOT/vendor/btop/bin/btop}
  if (( ! $# )) && [[ -t 0 && -t 1 && -x $btop ]]; then
    _axle_run_state_init
    command $btop --axle-dir $_axle_run_dir/services --axle-only
    return
  fi
  for a; do
    case $a in
      --mini|-m) mode=mini ;;
      --full|-f) mode=full ;;
      *) print -u2 -r -- "axle run top: unknown option $a (--mini, --full)"; return 1 ;;
    esac
  done
  _axle_run_state_init
  [[ -n $mode ]] || { _axle_run_get $_axle_run_dir top-view; mode=${REPLY:-full} }
  _axle_top_init
  if ! [[ -t 0 && -t 1 ]]; then                    # (a pipe, a script: the mini view, once)
    _axle_top_sample; zselect -t 50; _axle_top_sample
    local -i W=${COLUMNS:-0}; (( W >= 40 )) || W=100
    local -a reply; _axle_top_mini $W
    setopt localoptions extendedglob
    local l
    for l in $reply; do print -r -- ${l//$'\e'\[[0-9;]#m/}; done
    return 0
  fi
  zmodload zsh/zselect 2>/dev/null
  setopt localoptions localtraps
  local saved; saved=$(command stty -g 2>/dev/null)
  _axle_top_raw
  typeset -gi _axle_top_quit=0
  trap '_axle_top_resized=1' WINCH
  trap '_axle_top_quit=1' INT TERM HUP
  local sel='' msg='' ask=''
  local -F next=$EPOCHREALTIME wait until=0
  local -i dirty=1
  _axle_top_enter $mode
  {                                                # (always: the terminal comes back, even
  while (( ! _axle_top_quit )); do                 #  after an error)
    if (( EPOCHREALTIME >= next )); then
      _axle_top_sample
      (( next += 1, next < EPOCHREALTIME )) && next=$(( EPOCHREALTIME + 1 ))
      dirty=1
      (( until && EPOCHREALTIME > until )) && { msg='' ; until=0 }
    fi
    # Keep a selection while there's something to select.
    (( ${_axle_top_names[(Ie)$sel]} )) || sel=${_axle_top_names[1]}
    if (( dirty || _axle_top_resized )); then
      (( _axle_top_resized )) && [[ $mode == full ]] && print -n '\e[2J'
      _axle_top_resized=0
      _axle_top_draw $mode "$sel" "$msg"
      dirty=0
    fi
    (( wait = next - EPOCHREALTIME, wait < 0.01 ? (wait = 0.01) : wait ))
    _axle_top_key $wait || continue
    dirty=1
    if [[ -n $ask ]]; then                         # "stop <name>? y/n"
      if [[ $REPLY == (y|Y) ]]; then
        _axle_run_stop $ask >/dev/null 2>&1 && msg="stopped $ask" || msg="couldn't stop $ask"
        _axle_top_ticks=0                          # (the list again, now)
        next=$EPOCHREALTIME
      else
        msg=''
      fi
      ask='' until=$(( EPOCHREALTIME + 3 ))
      continue
    fi
    local -i si=${_axle_top_names[(Ie)$sel]}
    case $REPLY in
      q|esc) break ;;
      up|k)   (( si > 1 )) && sel=$_axle_top_names[si-1] ;;
      down|j) (( si < ${#_axle_top_names} )) && sel=$_axle_top_names[si+1] ;;
      m)
        _axle_top_leave $mode
        [[ $mode == full ]] && mode=mini || mode=full
        _axle_top_enter $mode ;;
      s) [[ -n $sel ]] && { ask=$sel; msg="stop $sel? y/n" } ;;
      r)
        [[ -n $sel ]] || continue
        msg="restarting $sel…"; _axle_top_draw $mode "$sel" "$msg"
        _axle_run_restart $sel >/dev/null 2>&1 && msg="restarted $sel" || msg="couldn't restart $sel"
        until=$(( EPOCHREALTIME + 3 )) _axle_top_ticks=0 next=$EPOCHREALTIME ;;
      o)
        [[ -n $sel ]] || continue
        if _axle_run_open $sel >/dev/null 2>&1; then msg="opening $_axle_top[${sel}:url]"
        else msg="$sel has no URL (yet)"; fi
        until=$(( EPOCHREALTIME + 3 )) ;;
      l)
        [[ -n $sel ]] || continue
        _axle_top_leave $mode
        command stty $saved 2>/dev/null
        _axle_printp "%F{${_axle_c[muted]:-244}}following ${sel//\%/%%}'s log: Ctrl-C comes back%f"
        _axle_run_logs -f $sel
        _axle_top_quit=0
        _axle_top_raw
        _axle_top_enter $mode ;;
    esac
  done
  } always {
    _axle_top_leave $mode
    command stty $saved 2>/dev/null
  }
  _axle_run_put $_axle_run_dir top-view $mode
  return 0
}
