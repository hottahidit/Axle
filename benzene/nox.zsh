# NoxA (nox) — the default Axle variant: a quiet two-line prompt that only shows
# what is relevant right now, and expands to show everything on demand.
#
#   ╭─ ~/repos/axle │ main ⇡1 +2 !1 ?3 │ py 3.12.3 (venv) │ (+2)        2.21s[1]
#   ╰─➜
#
# Shown only when it applies: git (in a repo, with last-commit signature badge and
# push protocol ssh/https), user@host (root/SSH/container),
# language versions (in a project that uses them), kube/docker/cloud contexts,
# background jobs, run time + exit code (slow or failed command), sudo countdown
# (while sudo won't ask for a password), load (when saturated), a red battery icon
# (below 30%, discharging).
# Signals by colour: the frame and arrow (one piece) turn dark red at 80%+ RAM and red
# after a failure; the path turns amber on a Windows drive under WSL (/mnt/c/...).
#
# When more segments apply than fit (AXLE_NOX_MAX_* or the terminal width), the
# least important ones by AXLE_NOX_PRIORITY are hidden and counted as "(+N)".
# Alt-i expands the prompt to show every segment (seconds, memory, battery %, commit
# age, hidden ones, ...) until the next command. The path and branch are terminal
# hyperlinks: Ctrl+click (in most terminals) opens the folder (except a bare ~) or the
# branch's web page. In VS Code's terminal the prompt switches to a compact one-line layout.
#
# Git status is computed in the background, so the prompt never waits on a slow
# repo. Live segments (the sudo countdown) redraw the current prompt in place, only
# when their text changes. Everything else reads env vars or files.
#
# Settings (in ~/.zshrc, before oh-my-zsh is sourced; most also work live):
#   AXLE_NERD_FONT=0           1 = Nerd Font icons instead of plain Unicode/text
#   AXLE_PALETTE=mocha         mocha (Catppuccin Mocha, 24-bit) or classic (256-colour)
#   AXLE_COLORS=(role colour)  associative array overriding single colour roles
#   AXLE_NOX_LEFT=(...)        segments on the first line, in display order
#   AXLE_NOX_RIGHT=(...)       stats on the right of the top line, in display order
#   AXLE_NOX_PRIORITY=(...)    segments from most to least important (for trimming)
#   AXLE_NOX_MAX_LEFT=5        most segments shown on the first line before trimming
#   AXLE_NOX_MAX_RIGHT=3       most segments shown on the right before trimming
#   AXLE_VSCODE=auto           auto = compact layout in VS Code's terminal; 1 = always; 0 = never
#   AXLE_NOX_CODE=(...)        segments of the VS Code layout, in display order
#   AXLE_NOX_MAX_CODE=5        most segments in the VS Code layout before trimming
#   AXLE_PATH_DEPTH=4          path components kept before the middle is elided
#   AXLE_CMD_MIN_SECS=2        show run time at or above this many seconds
#   AXLE_MEM_WARN=80           RAM % at which the prompt turns dark red
#   AXLE_BATTERY_WARN=30       battery % below which the battery icon appears
#   AXLE_SUDO_TIMEOUT=         sudo credential lifetime in minutes (default: ask sudo)
#   AXLE_NOTIFY_SECS=0         ring the terminal bell after commands this long (0 = off)
#   AXLE_DETAIL_KEY='^[i'      key that expands the prompt ('' = no binding)
#   AXLE_LINKS=1               0 = no clickable path/branch hyperlinks
#   AXLE_ICON_WIDTH=           columns per Nerd Font icon (default: asked from the terminal)
#   AXLE_GIT_ASYNC=1           0 = compute git status synchronously
#   AXLE_GIT_UNTRACKED=1       0 = skip counting untracked files (faster in huge repos)
#   AXLE_PROMPT_CHAR=          the prompt character (default: powerline arrow U+E0B0 with a
#                              Nerd Font, ▶ without; AXLE_PROMPT_CHAR_VICMD in vi command mode)
#   AXLE_PROMPT_GAP=2          spaces between the arrow and what you type
#   AXLE_ALARMS=1              0 = never draw alarm bubbles (see "alarms" below)
#   AXLE_BUBBLES=1             0 = square alarm blocks instead of rounded Nerd Font bubbles
#   AXLE_PROD_PATTERN='(#i)*prod*'  contexts treated as production (zsh pattern)
#   AXLE_CLOCK=1               0 = clock only in the expanded view
#   AXLE_TRANSIENT=1           compact past prompts to "time dir ➜ command" (0 = keep full)
#   AXLE_MARKS=auto            shell-integration marks (OSC 133) for jumping between commands
#                              and selecting output; auto = on, except in VS Code (it has its own)
#
# Alarms: when something is genuinely wrong, that one segment is drawn as a solid red
# pill instead of coloured text, so it's the loudest thing on screen: a failed command,
# root, a production context (kube/docker/aws/gcp/terraform matching AXLE_PROD_PATTERN),
# low battery, git conflicts, a bad commit signature. Alarms are never trimmed to (+N).
#
# Run `axle segments` for the list of segment names.

# --- settings ----------------------------------------------------------------

(( ${+AXLE_NOX_LEFT} ))  || typeset -ga AXLE_NOX_LEFT=(
  context inside dir git direnv python node go rust ruby java php lua perl scala flutter
  haskell nix kube docker aws ebenv gcloud gcred azure terraform jobs tmux shlvl vimode
)
(( ${+AXLE_NOX_RIGHT} )) || typeset -ga AXLE_NOX_RIGHT=(
  exec sudo timew task todo load mem vpn pdhist clock battery aistatus
)
# Most important first. `dir` is never hidden; unlisted segments rank last.
(( ${+AXLE_NOX_PRIORITY} )) || typeset -ga AXLE_NOX_PRIORITY=(
  dir exec sudo git context inside vimode battery kube aws ebenv gcloud gcred azure docker
  direnv jobs tmux timew python node go rust ruby java php lua perl scala flutter haskell
  terraform nix task load mem vpn todo aistatus pdhist shlvl clock
)
: ${AXLE_NERD_FONT:=0} ${AXLE_PATH_DEPTH:=4} ${AXLE_CMD_MIN_SECS:=2} ${AXLE_NOTIFY_SECS:=0}
: ${AXLE_NOX_MAX_LEFT:=5} ${AXLE_NOX_MAX_RIGHT:=3}
: ${AXLE_MEM_WARN:=80} ${AXLE_BATTERY_WARN:=30} ${AXLE_LINKS:=1}
: ${AXLE_GIT_ASYNC:=1} ${AXLE_GIT_UNTRACKED:=1} ${AXLE_TRANSIENT:=1} ${AXLE_MARKS:=auto}
: ${AXLE_VSCODE:=auto} ${AXLE_NOX_MAX_CODE:=5}
# The prompt character: the powerline arrow pointing at what you type (U+E0B0, the shape
# oh-my-posh ends its segments with) when there's a Nerd Font, ▶ otherwise; outlined in
# vi command mode.
# A character you set yourself is kept; one we chose is re-chosen on reload (font change).
() {
  # Vi command mode keeps the same arrow, drawn in outline (U+E0B1).
  local char=▶ vicmd=:
  (( AXLE_NERD_FONT )) && char=$'\ue0b0' vicmd=$'\ue0b1'
  # Earlier versions' defaults count as ours too, so `axle reload` in a shell started on
  # an older version updates them rather than mistaking them for your own choice.
  local -a old_chars=(➜ $'\ue0b0' λ ◀ ▶ $'\ue0b2') old_vicmd=(◀ $'\ue0b2' $'\ue0b1' : $'\ue0b3')
  if [[ -z $AXLE_PROMPT_CHAR || $AXLE_PROMPT_CHAR == $_axle_auto_char ]] ||
     (( ${old_chars[(Ie)$AXLE_PROMPT_CHAR]} )); then
    typeset -g AXLE_PROMPT_CHAR=$char _axle_auto_char=$char
  fi
  if [[ -z $AXLE_PROMPT_CHAR_VICMD || $AXLE_PROMPT_CHAR_VICMD == $_axle_auto_vicmd ]] ||
     (( ${old_vicmd[(Ie)$AXLE_PROMPT_CHAR_VICMD]} )); then
    typeset -g AXLE_PROMPT_CHAR_VICMD=$vicmd _axle_auto_vicmd=$vicmd
  fi
}
: ${AXLE_PROMPT_GAP:=2} ${AXLE_ALARMS:=1}
: ${AXLE_BUBBLES:=1}
# Contexts that count as production (kube, docker, aws, gcp, terraform): a zsh pattern.
(( ${+AXLE_PROD_PATTERN} )) || typeset -g AXLE_PROD_PATTERN='(#i)*prod*'
# VS Code's status bar already shows the branch sync state, interpreter and language
# versions, so its layout keeps only what the terminal itself changes.
(( ${+AXLE_NOX_CODE} )) || typeset -ga AXLE_NOX_CODE=(
  context inside dir git direnv python kube docker aws ebenv gcloud gcred azure terraform
  jobs tmux vimode exec sudo timew battery aistatus
)
(( ${+AXLE_DETAIL_KEY} )) || typeset -g AXLE_DETAIL_KEY='^[i'

# Python's activate script would otherwise prepend "(venv)"; the python segment shows it.
export VIRTUAL_ENV_DISABLE_PROMPT=1

# --- colours -----------------------------------------------------------------
# Colours are assigned by meaning, so the same colour always says the same thing:
#   red      error / danger     failed exit code, conflicts, bad signature, root, http
#   peach    warning            Windows drive, sudo countdown, SSH session, gone upstream
#   yellow   change / cost      modified files, dirty branch, run time
#   green    good               clean branch, staged files, good signature
#   sky      sync               ahead/behind the upstream
#   blue     location           the path
#   mauve    accent             the frame + arrow, one piece (red/deep red on failure/RAM)
#   pink     remote infra       kube, docker, aws, gcp, terraform (where commands land)
#   teal/flamingo/sapphire/...  languages, each its own
#   overlay  quiet              separators, untracked, clock, protocol
#
# AXLE_PALETTE=mocha (default) is Catppuccin Mocha in 24-bit colour; AXLE_PALETTE=classic
# uses the 256-colour palette. Override single roles with an associative array:
#   typeset -A AXLE_COLORS=(path '#74c7ec' accent '#f5c2e7')
# Run `axle colors` to preview every role.

: ${AXLE_PALETTE:=mocha}

# Catppuccin Mocha, https://catppuccin.com/palette
typeset -gA _axle_mocha=(
  rosewater '#f5e0dc'  flamingo '#f2cdcd'  pink '#f5c2e7'  mauve '#cba6f7'
  red '#f38ba8'  maroon '#eba0ac'  peach '#fab387'  yellow '#f9e2af'  green '#a6e3a1'
  teal '#94e2d5'  sky '#89dceb'  sapphire '#74c7ec'  blue '#89b4fa'  lavender '#b4befe'
  overlay2 '#9399b2'  overlay1 '#7f849c'  overlay0 '#6c7086'  surface2 '#585b70'
  surface1 '#45475a'  crust '#11111b'
  deepred '#d20f39'       # Catppuccin Latte red: the "darker red" for memory pressure
)

_axle_load_palette() {
  typeset -gA _axle_c
  if [[ $AXLE_PALETTE == classic ]]; then
    _axle_c=(
      sep 238  accent 141  muted 244  path 75  error 203  ok 114  warn 214
      pressure 124  windows 214  user 183  host 146  root 203  ssh 214
      clean 114  dirty 214  ahead 117  staged 114  changed 214  untracked 244
      conflict 203  stash 180  action 203
      python 221  node 114  go 81  rust 209  nix 110
      ruby 204  java 215  php 147  lua 75  perl 110  scala 203  flutter 117  haskell 141
      kube 69  docker 39  aws 214  gcloud 75  terraform 141  azure 69
      direnv 180  inside 214  vimode 141  timew 180  task 180  todo 244  vpn 117  pdhist 244
      jobs 180  tmux 120  shlvl 244  duration 180  clock 244  sudo 214
      sig_good 114  sig_bad 203  sig_warn 214  proto 244
      alarm_bg 203  alarm_warn_bg 214  alarm_fg 16
    )
  else
    local -A m=("${(@kv)_axle_mocha}")
    _axle_c=(
      sep $m[surface2]  accent $m[mauve]  muted $m[overlay1]
      path $m[blue]  error $m[red]  ok $m[green]  warn $m[peach]
      pressure $m[deepred]  windows $m[peach]
      user $m[rosewater]  host $m[lavender]  root $m[red]  ssh $m[peach]
      clean $m[green]  dirty $m[yellow]  ahead $m[sky]  staged $m[green]
      changed $m[yellow]  untracked $m[overlay1]  conflict $m[red]  stash $m[lavender]
      action $m[red]
      python $m[teal]  node $m[flamingo]  go $m[sapphire]  rust $m[rosewater]  nix $m[lavender]
      ruby $m[maroon]  java $m[peach]  php $m[lavender]  lua $m[blue]  perl $m[sapphire]
      scala $m[red]  flutter $m[sky]  haskell $m[mauve]
      kube $m[pink]  docker $m[pink]  aws $m[pink]  gcloud $m[pink]  terraform $m[pink]
      azure $m[pink]  direnv $m[yellow]  inside $m[peach]  vimode $m[mauve]
      timew $m[yellow]  task $m[lavender]  todo $m[overlay1]  vpn $m[sky]  pdhist $m[overlay1]
      jobs $m[lavender]  tmux $m[green]  shlvl $m[overlay1]  duration $m[yellow]  clock $m[overlay1]
      sudo $m[peach]  sig_good $m[green]  sig_bad $m[red]  sig_warn $m[peach]
      proto $m[overlay1]  alarm_bg $m[red]  alarm_warn_bg $m[peach]  alarm_fg $m[crust]
    )
    # 24-bit colour where the terminal has it; otherwise zsh maps each hex value
    # to the nearest of the 256 colours. Windows Terminal doesn't set COLORTERM.
    if [[ $COLORTERM != (truecolor|24bit) && -z $WT_SESSION && -z $KITTY_WINDOW_ID &&
          $TERM_PROGRAM != (vscode|iTerm.app|WezTerm|ghostty) ]]; then
      zmodload zsh/nearcolor 2>/dev/null
    fi
  fi
  (( ${+AXLE_COLORS} )) && _axle_c+=("${(@kv)AXLE_COLORS}")

  # Shared helpers in lib/common.zsh read these.
  typeset -g AXLE_COLOR_ACCENT=$_axle_c[accent] AXLE_COLOR_MUTED=$_axle_c[muted]
  typeset -g AXLE_COLOR_PATH=$_axle_c[path] AXLE_COLOR_ERROR=$_axle_c[error]
}
_axle_load_palette

# Print every colour role as a swatch (`axle colors`).
_axle_show_colors() {
  local role
  for role in ${(ok)_axle_c}; do
    _axle_printp "  %F{$_axle_c[$role]}██ ${(r:10:)role}%f %F{$_axle_c[muted]}$_axle_c[$role]%f"
  done
}

typeset -gA _axle_i
if (( AXLE_NERD_FONT )); then
  _axle_i=(
    branch $'\ue0a0 '  python $'\ue73c '  node $'\ue718 '  go $'\ue626 '  rust $'\ue7a8 '
    nix $'\uf313 '  kube $'\U000f10fe '  docker $'\uf308 '  aws $'\ue7ad '
    gcloud $'\U000f11f6 '  terraform $'\U000f1062 '  jobs $'\uf013 '  shlvl '↳'
    lock $' \uf023'  remote $'\uf233 '  container $'\uf308 '  tmux $'\uebc8 '  load $'\uf0e4 '  mem $'\uf2db '
    battery $'\uf243 '  charging $'\U000f0084 '  clock $'\uf017 '  sudo $'\uf09c '
    sig_good $'\uf4a1'  sig_bad $'\uf4a3'  sig_unknown $'\uf4a3'  sig_none $'\uf4a3'
    proto $'\uf0ac '
    ruby $'\ue791 '  java $'\ue738 '  php $'\ue73d '  lua $'\ue620 '  perl $'\ue769 '
    scala $'\ue737 '  flutter $'\ue798 '  haskell $'\ue777 '  azure $'\uebd8 '
    ebenv $'\ue7ad eb '  gcred $'\uf084 '  direnv $'\uf07c '  inside $'\uf489 '
    toolbox $'\uf4b7 '  timew $'\uf254 '  task $'\uf4a0 '  todo $'\uf0ae '
    vpn $'\U000f0582 '  pdhist $'\uf1da '
  )
else
  _axle_i=(
    branch ''  python 'py '  node 'node '  go 'go '  rust 'rs '  nix 'nix '
    kube '⎈ '  docker 'docker '  aws 'aws '  gcloud 'gcp '  terraform 'tf '
    jobs '&'  shlvl '↳'  lock ' ro'  remote ''  container ''  tmux 'tmux '  load 'ld '  mem 'mem '
    battery '▯'  charging '▯+'  clock ''  sudo 'sudo '
    sig_good '✓sig'  sig_bad '✗sig'  sig_unknown '?sig'  sig_none '!sig'  proto '🌐'
    ruby 'rb '  java 'java '  php 'php '  lua 'lua '  perl 'pl '  scala 'scala '
    flutter 'flutter '  haskell 'hs '  azure 'az '  ebenv 'eb '  gcred 'sa '
    direnv 'direnv'  inside '↳ '  toolbox '⬢ '  timew '⏱ '  task 'task '  todo 'todo '
    vpn 'vpn '  pdhist 'hist '
  )
fi

# Nerd Font icons are private-use characters, which zsh counts as 1 column; a terminal
# that draws them 2 wide would push the right-aligned top line past the edge. So ask the
# terminal once: print an icon, request the cursor position (CSI 6n), and cache the
# answer per terminal. AXLE_ICON_WIDTH=1|2 overrides it; `axle refresh` measures again.
typeset -gi _axle_icon_extra=0
_axle_measure_icons() {
  _axle_icon_extra=0
  (( AXLE_NERD_FONT )) || return
  if [[ -n $AXLE_ICON_WIDTH ]]; then
    _axle_icon_extra=$(( AXLE_ICON_WIDTH - 1 )); return
  fi
  # VS Code started from a Windows Terminal tab inherits WT_SESSION, so check it first.
  local key=${TERM_PROGRAM:-${WT_SESSION:+windows-terminal}}
  key=${key:-$TERM}
  local cache=${XDG_CACHE_HOME:-$HOME/.cache}/axle/icon-width line
  if [[ $1 != force && -r $cache ]]; then
    for line in "${(@f)$(<$cache)}"; do
      [[ ${line% *} == $key ]] && { _axle_icon_extra=$(( ${line##* } - 1 )); return }
    done
  fi
  [[ -o interactive && -t 0 && -t 1 ]] || return
  local resp='' col
  print -n $'\r\uf017\e[6n'
  read -rs -t 0.5 -d R resp                # reply: ESC [ row ; col R
  print -n $'\r\e[K'
  col=${resp##*;}
  [[ $resp == $'\e['* && $col == <-> ]] || return
  local -i width=$(( col - 1 ))
  (( width >= 1 && width <= 2 )) || return
  _axle_icon_extra=$(( width - 1 ))
  local -a known=()
  [[ -r $cache ]] && known=(${(f)"$(<$cache)"})
  known=(${known:#"$key "*} "$key $width")
  mkdir -p ${cache:h} 2>/dev/null &&
    print -rl -- $known > $cache.$$ 2>/dev/null && mv -f $cache.$$ $cache
}
_axle_measure_icons

# --- state -------------------------------------------------------------------

typeset -gA _axle_seg _axle_vcache _axle_cache
typeset -gA _axle_markers           # marker file -> directory it was found in
typeset -ga _axle_last_status
typeset -gF _axle_cmd_start=0 _axle_elapsed=0
typeset -gi _axle_detail=0 _axle_mem_used=0 _axle_wsl=0
# Who and where, as the segments see it (`axle preview` overrides these to fake states).
typeset -gi _axle_uid=$EUID
typeset -g  _axle_power_glob='/sys/class/power_supply/BAT*'
typeset -gi _axle_sudo_ran=0 _axle_sudo_until=0    # epoch secs; -1 = never expires
typeset -g  _axle_keymap=main _axle_ps1='' _axle_rps1=''
typeset -g  _axle_top_l='' _axle_top_r='' _axle_bottom=''
typeset -gi _axle_top_lw=0 _axle_top_rw=0
typeset -g  _axle_git_pwd='' _axle_git_fd='' _axle_timer_fd='' _axle_sudo_timeout=''

[[ -n $WSL_DISTRO_NAME || -e /proc/sys/fs/binfmt_misc/WSLInterop ]] && _axle_wsl=1
typeset -gi _axle_vscode=0 _axle_marks=0
[[ $AXLE_MARKS == 1 || ( $AXLE_MARKS == auto && $TERM_PROGRAM != vscode ) ]] && _axle_marks=1
[[ $AXLE_VSCODE == 1 || ( $AXLE_VSCODE == auto && $TERM_PROGRAM == vscode ) ]] && _axle_vscode=1

# --- helpers -----------------------------------------------------------------

# Wrap text in a colour from the palette: _axle_paint <colour-key> <text>.
_axle_paint() { REPLY="%F{${_axle_c[$1]:-$1}}$2%f" }

# Wrap prompt text in an OSC 8 hyperlink: _axle_link <url> <text>.
# Terminals without hyperlink support ignore the escapes and show plain text.
_axle_link() {
  if (( ! AXLE_LINKS )) || [[ -z $1 ]]; then REPLY=$2; return; fi
  local enc='' ch
  for ch in ${(s::)1}; do                # percent-encode anything URL-unsafe
    if [[ $ch == [[:alnum:]/:._~@=?\&+-] ]]; then
      enc+=$ch
    else
      enc+="%${(l:2::0:)$(( [##16] #ch ))}"
    fi
  done
  REPLY="%{"$'\e]8;;'"${enc//\%/%%}"$'\e\\'"%}$2%{"$'\e]8;;\e\\'"%}"
}

# Segments set this while rendering to ask for an alarm pill.
typeset -gi _axle_alarm=0

# Is this context name a production one (AXLE_PROD_PATTERN)?
_axle_is_prod() {
  setopt localoptions extendedglob
  [[ -n $1 && $1 == ${~AXLE_PROD_PATTERN} ]]
}

# Redraw REPLY as an alarm bubble, its own styling stripped: dark text on solid red
# with rounded ends ( … ) like oh-my-posh's "diamond" segments. The caps are Nerd
# Font glyphs, so without one (or with AXLE_BUBBLES=0) it's a plain padded block.
# _axle_pill [level]: 1 = red (failed / dangerous), 2 = amber (be careful, e.g. root).
_axle_pill() {
  setopt localoptions extendedglob
  local text=${REPLY//(\%F\{[^\}]#\}|\%f|\%B|\%b)/}
  local bg=$_axle_c[alarm_bg] fg=$_axle_c[alarm_fg] pad=' '
  (( ${1:-1} == 2 )) && bg=$_axle_c[alarm_warn_bg]
  if (( ${_axle_plain:-0} )); then          # a layout without backgrounds (AxoN)
    REPLY="%F{$bg}$text%f"; return
  fi
  # A lone icon gets no left padding: Nerd Font icons spill into the cell on their right,
  # so " icon " looks lopsided and wide; "icon " reads as centred.
  _axle_width $text
  local left=$pad
  (( REPLY <= 1 + _axle_icon_extra )) && left=''
  if (( AXLE_NERD_FONT && AXLE_BUBBLES )); then
    REPLY="%F{$bg}"$'\ue0b6'"%K{$bg}%F{$fg}$left$text$pad%f%k%F{$bg}"$'\ue0b4'"%f"
  else
    REPLY="%K{$bg}%F{$fg}$left$text$pad%f%k"
  fi
}

# Display width of a prompt string (colours, links and other escapes excluded).
_axle_width() {
  setopt localoptions extendedglob
  local s=${(S)1//\%\{*\%\}/}
  s=${(S)s//\%([BSUbfksu]|[FK]\{*\})/}
  s=${(%)s}
  REPLY=${(m)#s}
  if (( _axle_icon_extra )); then          # icons wider than zsh thinks
    local icons=${s//[^$'\ue000'-$'\uf8ff'$'\U000f0000'-$'\U000ffffd']/}
    (( REPLY += ${#icons} * _axle_icon_extra ))
  fi
}

# Run a binary's --version once per path and cache the first x.y[.z] it prints.
_axle_version() {
  # A version manager's shim (asdf, mise, rbenv, ...) runs whichever version the folder
  # pins, so its answer is only good for this folder.
  local key="$*" out
  [[ $1 == */shims/* ]] && key+=" @$PWD"
  if (( ! ${+_axle_vcache[$key]} )); then
    out=$("$@" 2>&1)
    if [[ $out =~ '[0-9]+\.[0-9]+(\.[0-9]+)?' ]]; then
      _axle_vcache[$key]=$MATCH
    else
      _axle_vcache[$key]=''
    fi
  fi
  REPLY=${_axle_vcache[$key]}
}

# _axle_scan_markers and _axle_has_marker (project markers) are in lib/project.zsh.

# Read a file only when its mtime changed: _axle_cached <key> <file> <command...>.
# The command gets the file as its last argument; its stdout is cached.
_axle_cached() {
  local key=$1 file=$2; shift 2
  local -a st
  zstat -A st +mtime -- $file 2>/dev/null || { REPLY=''; return 1 }
  if [[ ${_axle_cache[$key.mtime]} != $st[1] ]]; then
    _axle_cache[$key.mtime]=$st[1]
    _axle_cache[$key]=$("$@" $file 2>/dev/null)
  fi
  REPLY=${_axle_cache[$key]}
}

# Percentage of RAM in use, from /proc/meminfo (no fork).
_axle_read_mem() {
  _axle_mem_used=0
  [[ -r /proc/meminfo ]] || return
  local key value unit; local -i total=0 avail=0
  while read -r key value unit; do
    case $key in
      MemTotal:)     total=$value ;;
      MemAvailable:) avail=$value; break ;;
    esac
  done < /proc/meminfo
  (( total )) && _axle_mem_used=$(( (total - avail) * 100 / total ))
}

# True when $PWD is on a Windows drive mounted into WSL (/mnt/c, /mnt/d, ...).
_axle_on_windows_drive() {
  (( _axle_wsl )) && [[ $PWD == /mnt/[[:alpha:]](|/*) ]]
}

# --- segments ----------------------------------------------------------------
# Each _axle_seg_<name> sets REPLY to its rendered text, or leaves it empty.
# $_axle_detail is 1 while the prompt is expanded (Alt-i): show everything.

# Which machine: shown when it isn't this one (an SSH session, where Axle is installed on
# the remote too, or a container), as root, and when expanded. On a remote it's the
# hostname that matters, so the user is left out unless root or expanded.
_axle_seg_context() {
  local icon='' hostc=$_axle_c[host]
  if [[ -n $SSH_CONNECTION || -n $SSH_TTY ]]; then
    icon=$_axle_i[remote] hostc=$_axle_c[ssh]
  elif [[ -f /.dockerenv || -f /run/.containerenv ]]; then
    icon=$_axle_i[container] hostc=$_axle_c[docker]
  fi
  (( _axle_uid == 0 || _axle_detail )) || [[ $hostc != $_axle_c[host] ]] || return
  local host="%F{$hostc}$icon%m%f"
  # A toolbox or distrobox container: by its name.
  _axle_container_name && host="%F{$_axle_c[docker]}$_axle_i[toolbox]${REPLY//\%/%%}%f"
  if (( _axle_uid == 0 )); then
    REPLY="%B%F{$_axle_c[root]}%n%f%b%F{$_axle_c[muted]}@%f$host"
    _axle_alarm=2                         # amber: a caution, not a failure
  elif (( _axle_detail )); then
    REPLY="%F{$_axle_c[user]}%n%f%F{$_axle_c[muted]}@%f$host"
  else
    REPLY=$host
  fi
}

_axle_seg_dir() {
  local -i d=$AXLE_PATH_DEPTH
  local colour=$_axle_c[path] url text="%($((d + 1))~|%-1~/…/%$((d - 1))~|%~)"
  _axle_on_windows_drive && colour=$_axle_c[windows]
  if (( _axle_vscode )); then
    # Inside a repo, show the path from the repo root (axle/lib), like VS Code's explorer.
    local root=$_axle_markers[.git]
    if [[ -n $root && $root != $HOME ]]; then
      local -a rel=(${(s:/:)PWD#$root})
      (( ${#rel} >= d )) && rel=(… $rel[-(d - 1),-1])
      local shown=${root:t}
      (( ${#rel} )) && shown+="/${(j:/:)rel}"
      text=${shown//\%/%%}
    fi
    url="file://$PWD"                                     # VS Code resolves it (also over Remote-WSL)
  elif _axle_on_windows_drive; then
    url="file:///${(U)PWD[6]}:${PWD[7,-1]:-/}"           # /mnt/c/x -> file:///C:/x
  elif (( _axle_wsl )); then
    url="file://wsl.localhost/$WSL_DISTRO_NAME$PWD"
  else
    url="file://$HOST$PWD"
  fi
  [[ $PWD == $HOME ]] && url=''                          # a bare ~ isn't worth a link
  _axle_link "$url" "%B$text%b"
  REPLY="%F{$colour}$REPLY%f"
  [[ -w $PWD ]] || REPLY+="%F{$_axle_c[error]}$_axle_i[lock]%f"
}

# Git is rendered by the async worker as "<summary>\x1f<details>"; details only
# show while expanded. Nothing is shown outside a repository.
_axle_seg_git() {
  [[ $_axle_git_pwd == $PWD && -n ${_axle_seg[git]} ]] || return
  local -a part=("${(@ps:\x1f:)_axle_seg[git]}")
  REPLY=$part[1]
  (( _axle_detail )) && REPLY+=$part[2]
  [[ " $part[3]" == *" conflicts="[1-9]* || " $part[3]" == *" sig="[BR]* ]] && _axle_alarm=1
}

# A venv's display name: its pyvenv.cfg "prompt", else its folder (the project's folder
# for the usual .venv / venv / env names).
_axle_venv_name() {
  setopt localoptions extendedglob
  local dir=$1 line
  REPLY=''
  if [[ -r $dir/pyvenv.cfg ]]; then
    while IFS= read -r line; do
      [[ $line == prompt[[:space:]]#=* ]] && { REPLY=${${${line#*=}## #}//[\'\"]/}; break }
    done < $dir/pyvenv.cfg
  fi
  [[ -z $REPLY ]] && REPLY=${dir:t}
  [[ $REPLY == (.venv|venv|env|.env) ]] && REPLY=${dir:h:t}
}

# Is the right venv active here? Sets reply=(state name venv-dir), state being
#   ok         the active venv belongs here (or no project venv is involved)
#   inactive   this project has a venv, and none is active
#   elsewhere  the active venv belongs to another project (you've left it, or this
#              project has its own); venvs kept centrally (~/.virtualenvs, poetry,
#              pyenv) belong to no folder, so they're never "elsewhere"
_axle_venv_state() {
  local here=$_axle_markers[venv] active=$VIRTUAL_ENV
  reply=(ok '' '')
  if [[ -n $active ]]; then
    _axle_venv_name $active
    reply=(ok $REPLY $active)
    if [[ -n $here && ${here:A} != ${active:A} ]]; then
      reply[1]=elsewhere
    elif [[ -z $here && ${active:t} == (.venv|venv|env|.env) && $PWD != ${active:h}(|/*) ]]; then
      reply[1]=elsewhere
    fi
  elif [[ -n $here && -z $CONDA_DEFAULT_ENV ]]; then
    _axle_venv_name $here
    reply=(inactive $REPLY $here)
  fi
}

_axle_seg_python() {
  local name='' bin=${commands[python3]:-$commands[python]}
  local -a reply
  _axle_venv_state
  if [[ $reply[1] != ok ]]; then
    # The wrong venv (or none) for this folder: an amber bubble naming the venv.
    local note='(inactive)'
    [[ $reply[1] == elsewhere ]] && note='(other project)'
    _axle_alarm=2
    _axle_paint python "$_axle_i[python]${reply[2]//\%/%%} $note"
    return
  fi
  if [[ -n $VIRTUAL_ENV ]]; then
    name=$reply[2]
    bin=$VIRTUAL_ENV/bin/python
  elif [[ -n $CONDA_DEFAULT_ENV ]]; then
    name=$CONDA_DEFAULT_ENV
    [[ -n $CONDA_PREFIX ]] && bin=$CONDA_PREFIX/bin/python
  elif ! _axle_has_marker pyproject.toml requirements.txt setup.py Pipfile .python-version; then
    return
  fi
  if (( _axle_vscode )); then                 # the status bar shows the interpreter
    [[ -n $name ]] && _axle_paint python "$_axle_i[python]${name//\%/%%}"
    return
  fi
  [[ -x $bin ]] && _axle_version $bin --version || REPLY=''
  local have=$REPLY; _axle_pin python
  local want=$REPLY text=${${:-$_axle_i[python]$have}% }
  _axle_pin_ok "$want" "$have" || { text+=" (wants $want)"; _axle_alarm=2 }
  [[ -n $name ]] && text+=" %F{$_axle_c[muted]}(${name//\%/%%})%f"
  _axle_paint python $text
}

# --- toolchain pins ---
# A project can pin a version: .nvmrc / .node-version, .python-version, rust-toolchain,
# or asdf/mise's .tool-versions. When the active one doesn't match, the language segment
# becomes an amber bubble: "node 25.6.0 (wants 20)".

# The version this folder pins for a tool (node python rust go): the nearest pin file
# decides (in the same folder, the tool's own file beats .tool-versions). Only plain
# versions count, "20", "3.12.1", "1.77"; a pin like "lts/*" or "stable" means "unknown",
# so nothing is flagged (just as nvm would use LTS and ignore pins further up).
_axle_pin() {
  setopt localoptions extendedglob
  local tool=$1 best='' bestdir='' bestfile='' file dir line want
  local -a names
  local -A asdf=(node 'node|nodejs' python python rust rust go 'go|golang')
  case $tool in
    node)   names=(.nvmrc .node-version) ;;
    python) names=(.python-version) ;;
    rust)   names=(rust-toolchain rust-toolchain.toml) ;;
  esac
  for file in $names .tool-versions; do
    dir=$_axle_markers[$file]
    [[ -n $dir ]] || continue
    if [[ $file == .tool-versions ]]; then
      (( ${#dir} > ${#bestdir} )) || continue
      want=''
      while read -r line; do
        [[ $line == (${~asdf[$tool]})[[:space:]]* ]] && { want=${${line#*[[:space:]]}%%[[:space:]]*}; break }
      done < $dir/$file
      [[ -n $want ]] || continue                  # doesn't mention this tool
    else
      (( ${#dir} >= ${#bestdir} )) || continue
      want=''
      if [[ $file == rust-toolchain.toml ]]; then
        while read -r line; do
          [[ $line == channel[[:space:]]#=* ]] && { want=${${line#*=}//[\"\' ]/}; break }
        done < $dir/$file
      else
        read -r want < $dir/$file
      fi
    fi
    best=$want bestdir=$dir bestfile=$file
  done
  best=${${best#v}%%[[:space:]]*}
  [[ $best == <->(.<->)# ]] || best=''
  REPLY=$best
}

# Does an installed version satisfy a pin? "20" matches 20.x.y, "3.12" matches 3.12.x.
_axle_pin_ok() {
  [[ -z $1 || -z $2 || $2 == $1 || $2 == $1.* ]]
}

# Render a language segment, flagging a version that doesn't match the pin.
#   _axle_lang <name> <version> [pin]
_axle_lang() {
  local name=$1 have=$2 want=$3
  if ! _axle_pin_ok "$want" "$have"; then
    _axle_alarm=2
    _axle_paint $name "$_axle_i[$name]$have (wants $want)"
  else
    _axle_paint $name "$_axle_i[$name]$have"
  fi
}

_axle_seg_node() {
  _axle_has_marker package.json .nvmrc .node-version .tool-versions || return
  REPLY=''
  [[ -n $commands[node] ]] && _axle_version $commands[node] --version
  local have=$REPLY; _axle_pin node
  [[ $REPLY == '' ]] && ! _axle_has_marker package.json .nvmrc .node-version && return
  _axle_lang node "$have" "$REPLY"
}

_axle_seg_go() {
  _axle_has_marker go.mod || return
  REPLY=''
  [[ -n $commands[go] ]] && _axle_version $commands[go] version
  local have=$REPLY; _axle_pin go
  _axle_lang go "$have" "$REPLY"
}

_axle_seg_rust() {
  _axle_has_marker Cargo.toml rust-toolchain rust-toolchain.toml || return
  REPLY=''
  [[ -n $commands[rustc] ]] && _axle_version $commands[rustc] --version
  local have=$REPLY; _axle_pin rust
  _axle_lang rust "$have" "$REPLY"
}

_axle_seg_nix() {
  if [[ -n $IN_NIX_SHELL ]]; then
    _axle_paint nix "$_axle_i[nix]${${name:-$IN_NIX_SHELL}//\%/%%}"
  elif _axle_has_marker flake.nix shell.nix; then
    _axle_paint nix "$_axle_i[nix]"
  fi
}

_axle_kube_parse() {
  command awk '
    function val(s) { sub(/^[^:]*:[ \t]*/, "", s); gsub(/^["\047]|["\047][ \t]*$/, "", s); return s }
    function flush() { if (name != "") ns_of[name] = ns; name = ""; ns = "" }
    /^current-context:/   { cur = val($0); next }
    /^contexts:/          { inctx = 1; next }
    /^[^ \t-]/            { if (inctx) flush(); inctx = 0 }
    inctx && /^[ \t]*- /  { flush() }
    inctx {
      s = $0; sub(/^[- \t]+/, "", s)
      if (s ~ /^name:/) name = val(s); else if (s ~ /^namespace:/) ns = val(s)
    }
    END {
      if (inctx) flush()
      if (cur != "") print cur ":" ((cur in ns_of) && ns_of[cur] != "" ? ns_of[cur] : "default")
    }' "$@"
}

_axle_seg_kube() {
  local cfg=${${KUBECONFIG:-$HOME/.kube/config}%%:*}
  [[ -r $cfg ]] || return
  _axle_cached "kube:$cfg" $cfg _axle_kube_parse || return
  [[ -n $REPLY ]] || return
  _axle_is_prod $REPLY && _axle_alarm=1
  _axle_paint kube "$_axle_i[kube]${REPLY//\%/%%}"
}

_axle_seg_docker() {
  local ctx=${DOCKER_CONTEXT:-$DOCKER_HOST}
  if [[ -z $ctx && -r $HOME/.docker/config.json ]]; then
    _axle_cached "docker:$HOME" $HOME/.docker/config.json command sed -n \
      's/.*"currentContext"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
    ctx=$REPLY
  fi
  REPLY=''
  [[ -n $ctx && $ctx != default ]] || return
  _axle_is_prod $ctx && _axle_alarm=1
  _axle_paint docker "$_axle_i[docker]${ctx//\%/%%}"
}

_axle_seg_aws() {
  local profile=${AWS_VAULT:-$AWS_PROFILE}
  [[ -n $profile ]] || return
  local region=${AWS_REGION:-$AWS_DEFAULT_REGION}
  _axle_is_prod $profile && _axle_alarm=1
  _axle_paint aws "$_axle_i[aws]${profile//\%/%%}${region:+@${region//\%/%%}}"
}

_axle_seg_gcloud() {
  local project=${CLOUDSDK_CORE_PROJECT:-$GOOGLE_CLOUD_PROJECT}
  [[ -n $project ]] || return
  _axle_is_prod $project && _axle_alarm=1
  _axle_paint gcloud "$_axle_i[gcloud]${project//\%/%%}"
}

_axle_seg_terraform() {
  _axle_has_marker .terraform || return
  local ws=${TF_WORKSPACE:-default} env=$_axle_markers[.terraform]/.terraform/environment
  [[ -z $TF_WORKSPACE && -r $env ]] && read -r ws < $env
  _axle_is_prod $ws && _axle_alarm=1
  _axle_paint terraform "$_axle_i[terraform]${ws//\%/%%}"
}

_axle_seg_jobs() {
  (( ${#jobstates} )) && _axle_paint jobs "$_axle_i[jobs]${#jobstates}"
}

# tmux. Outside it: detached sessions still running ("tmux 2"), so none is forgotten;
# only asked when a tmux server socket exists, and then at most every 30 s. Inside it:
# the session and window, while expanded.
_axle_seg_tmux() {
  if [[ -n $TMUX ]]; then
    (( _axle_detail )) || return
    local where; where=$(command tmux display-message -p '#S:#I' 2>/dev/null) || return
    _axle_paint tmux "$_axle_i[tmux]${where//\%/%%}"
    return
  fi
  [[ -S ${TMUX_TMPDIR:-/tmp}/tmux-$UID/default ]] && (( $+commands[tmux] )) || return
  if (( EPOCHSECONDS - ${_axle_cache[tmux.at]:-0} >= 30 )); then
    _axle_cache[tmux.at]=$EPOCHSECONDS
    _axle_cache[tmux]=${#${(M)${(f)"$(command tmux list-sessions -F '#{session_attached}' 2>/dev/null)"}:#0}}
  fi
  (( _axle_cache[tmux] )) && _axle_paint tmux "$_axle_i[tmux]$_axle_cache[tmux]"
}

_axle_seg_shlvl() {
  (( _axle_detail && SHLVL > 1 )) && _axle_paint shlvl "$_axle_i[shlvl]$SHLVL"
}

# Run time and exit code of the last command: "2.21s" when slow, "0.03s[1]" when it
# failed, "32s[147]" for both. A failed pipeline shows every stage: "1.2s[0|1|0]".
_axle_seg_exec() {
  local -a st=($_axle_last_status)
  (( ${#st} )) || return
  local code=''
  if [[ ${(j::)st} == *[1-9]* ]]; then
    (( ${#st} > 1 )) && code=${(j:|:)st} || code=$st[1]
  fi
  [[ -n $code ]] || (( _axle_elapsed >= AXLE_CMD_MIN_SECS )) || return
  _axle_fmt_duration $_axle_elapsed
  REPLY="%F{$_axle_c[duration]}$REPLY%f"
  [[ -n $code ]] && REPLY+="%F{$_axle_c[error]}[$code]%f" && _axle_alarm=1
}

# Time left before sudo asks for a password again: "sudo 14m", then "sudo 42s".
_axle_seg_sudo() {
  (( _axle_sudo_until )) || return
  if (( _axle_sudo_until < 0 )); then
    _axle_paint sudo "$_axle_i[sudo]∞"; return
  fi
  local -i left=$(( _axle_sudo_until - EPOCHSECONDS ))
  (( left > 0 )) || { _axle_sudo_until=0; return }
  if (( left >= 60 )); then
    _axle_paint sudo "$_axle_i[sudo]$(( (left + 59) / 60 ))m"
  else
    _axle_paint error "$_axle_i[sudo]${left}s"
  fi
}

# How many CPUs (once, when first needed): from "0-23" in sysfs, or /proc/cpuinfo.
_axle_count_cpus() {
  local online='' part
  local -i n=0
  if [[ -r /sys/devices/system/cpu/online ]] && read -r online < /sys/devices/system/cpu/online; then
    for part in ${(s:,:)online}; do
      if [[ $part == <->-<-> ]]; then (( n += ${part#*-} - ${part%-*} + 1 )); else (( n++ )); fi
    done
  elif [[ -r /proc/cpuinfo ]]; then
    n=${#${(M)${(f)"$(</proc/cpuinfo)"}:#processor*}}
  fi
  _axle_cache[cpus]=$(( n > 0 ? n : 1 ))
}

_axle_seg_load() {
  [[ -r /proc/loadavg ]] || return
  local load rest; read -r load rest < /proc/loadavg
  (( ${+_axle_cache[cpus]} )) || _axle_count_cpus
  local -i cpus=${_axle_cache[cpus]:-1}
  (( load >= cpus || _axle_detail )) || return     # only when the CPU is saturated
  local colour=muted
  (( load >= cpus )) && colour=error || { (( load >= cpus / 2.0 )) && colour=warn }
  _axle_paint $colour "$_axle_i[load]$load"
}

_axle_seg_mem() {
  (( _axle_detail && _axle_mem_used )) || return   # otherwise shown by colour only
  local colour=muted
  (( _axle_mem_used >= AXLE_MEM_WARN )) && colour=pressure
  _axle_paint $colour "$_axle_i[mem]$_axle_mem_used%%"
}

_axle_seg_battery() {
  local bat=( ${~_axle_power_glob}(N[1]) )
  [[ -n $bat ]] || return
  local -i cap; local state
  read -r cap < $bat/capacity 2>/dev/null || return
  read -r state < $bat/status 2>/dev/null
  local icon=$_axle_i[battery]
  [[ $state == Charging ]] && icon=$_axle_i[charging]
  if (( cap < AXLE_BATTERY_WARN )) && [[ $state != (Charging|Full) ]]; then
    if (( AXLE_NERD_FONT && ! _axle_detail )); then
      icon=${icon% }                    # icon alone
    else
      icon+="$cap%%"                    # a bare ▯ reads as nothing
    fi
    _axle_alarm=1
    _axle_paint error $icon
  elif (( _axle_detail )); then
    _axle_paint ok "$icon$cap%%"
  fi
}

# Hours and minutes; seconds too while expanded.
_axle_seg_clock() {
  (( ${AXLE_CLOCK:-1} || _axle_detail )) || return     # AXLE_CLOCK=0: only when expanded
  # Formatted here as plain text, not as a prompt %D{...}: its %S/%M look like prompt
  # style codes to the width calculation, which then miscounted the line. The redraw
  # timer re-renders on every tick, so it stays current.
  local fmt=%H:%M time
  (( _axle_detail )) && fmt=%H:%M:%S
  strftime -s time $fmt $EPOCHSECONDS
  _axle_paint clock "$_axle_i[clock]$time"
}

# More segments: direnv, Ruby/Java/PHP/Lua/Perl/Scala/Flutter/Haskell, Azure, Elastic
# Beanstalk, Google credentials, timewarrior, taskwarrior, todo.txt, NordVPN, vi mode,
# per-directory history, and "inside another program" (ranger, vim :sh, ...).
source "$AXLE_ROOT/benzene/more.zsh"

# --- git (async) -------------------------------------------------------------

# Turn a remote URL into a web URL for the branch (GitHub, GitLab, Gitea, ...).
_axle_git_web_url() {
  local url=$1 branch=$2 scheme=https host path
  case $url in
    http://*|https://*) scheme=${url%%://*}; url=${url#*://}; url=${url#*@}
                        host=${url%%/*}; path=${url#*/} ;;
    ssh://*)            url=${url#ssh://}; url=${url#*@}
                        host=${${url%%/*}%%:*}; path=${url#*/} ;;
    *@*:*)              url=${url#*@}; host=${url%%:*}; path=${url#*:} ;;
    *)                  return 1 ;;
  esac
  path=${path%.git}
  case $host in
    github.com) REPLY="$scheme://$host/$path/tree/$branch" ;;
    *gitlab*)   REPLY="$scheme://$host/$path/-/tree/$branch" ;;
    *)          REPLY="$scheme://$host/$path/src/branch/$branch" ;;   # Gitea, Forgejo, Bitbucket
  esac
}

# Prints the git segment for the current directory (runs in a subshell) as
# "<summary>\x1f<extra detail>\x1f<flags>", flags being raw "key=value" state.
_axle_git_compute() {
  emulate -L zsh
  export GIT_OPTIONAL_LOCKS=0           # never fight a foreground git for index.lock
  local gitdir
  gitdir=$(command git rev-parse --git-dir 2>/dev/null) || return 0

  local -a flags=(--porcelain=v2 --branch --show-stash)
  (( AXLE_GIT_UNTRACKED )) || flags+=(--untracked-files=no)
  local line oid='' head='' upstream='' ab=''
  local -i ahead=0 behind=0 staged=0 changed=0 untracked=0 conflicts=0 stash=0
  for line in "${(@f)$(command git status $flags 2>/dev/null)}"; do
    case $line in
      '# branch.oid '*)      oid=${line#\# branch.oid } ;;
      '# branch.head '*)     head=${line#\# branch.head } ;;
      '# branch.upstream '*) upstream=${line#\# branch.upstream } ;;
      '# branch.ab '*)       ab=${line#\# branch.ab }
                             ahead=${${ab%% *}#+}; behind=${${ab##* }#-} ;;
      '# stash '*)           stash=${line#\# stash } ;;
      [12]' '*)              [[ $line[3] != . ]] && (( staged++ ))
                             [[ $line[4] != . ]] && (( changed++ )) ;;
      'u '*)                 (( conflicts++ )) ;;
      '? '*)                 (( untracked++ )) ;;
    esac
  done

  # In-progress operation: rebase/merge/cherry-pick/revert/bisect.
  local action='' step='' total='' onto=''
  if [[ -d $gitdir/rebase-merge ]]; then
    action=REBASE; read -r step < $gitdir/rebase-merge/msgnum; read -r total < $gitdir/rebase-merge/end
    read -r onto < $gitdir/rebase-merge/head-name
  elif [[ -d $gitdir/rebase-apply ]]; then
    [[ -f $gitdir/rebase-apply/applying ]] && action=AM || action=REBASE
    read -r step < $gitdir/rebase-apply/next; read -r total < $gitdir/rebase-apply/last
    read -r onto < $gitdir/rebase-apply/head-name
  elif [[ -f $gitdir/MERGE_HEAD ]];       then action=MERGE
  elif [[ -f $gitdir/CHERRY_PICK_HEAD ]]; then action=CHERRY-PICK
  elif [[ -f $gitdir/REVERT_HEAD ]];      then action=REVERT
  elif [[ -f $gitdir/BISECT_LOG ]];       then action=BISECT
  fi 2>/dev/null

  # Branch name; mid-rebase HEAD is detached, so name the branch being rebased.
  local name=$head branch=$head
  if [[ -n $onto ]]; then
    branch=${onto#refs/heads/}; name=$branch
  elif [[ $head == '(detached)' ]]; then
    local tag; tag=$(command git describe --tags --exact-match HEAD 2>/dev/null)
    name="@${oid[1,7]}${tag:+ ($tag)}"; branch=''
  fi
  local colour=$_axle_c[clean]
  (( staged + changed + untracked + conflicts )) && colour=$_axle_c[dirty]

  # The URL a push would go to (after insteadOf rewrites): the upstream's remote,
  # else origin. Link the branch to its page on that remote's web UI.
  local remote
  remote=$(command git remote get-url --push "${${upstream%%/*}:-origin}" 2>/dev/null)
  REPLY=''
  if [[ -n $branch && -n $remote ]]; then
    _axle_git_web_url $remote $branch || REPLY=''
  fi
  _axle_link "$REPLY" "$_axle_i[branch]${name//\%/%%}"
  local out="%F{$colour}$REPLY%f" extra=''

  [[ -n $action ]] && out+=" %B%F{$_axle_c[action]}$action${step:+ $step/$total}%f%b"
  if [[ -n $upstream && -z $ab ]]; then
    out+=" %F{$_axle_c[error]}gone%f"               # upstream branch was deleted
  elif [[ -z $upstream && $oid != '(initial)' && -n $branch ]]; then
    extra+=" %F{$_axle_c[muted]}local%f"            # never pushed
  fi
  (( ahead ))     && out+=" %F{$_axle_c[ahead]}⇡$ahead%f"
  (( behind ))    && out+=" %F{$_axle_c[ahead]}⇣$behind%f"
  (( conflicts )) && out+=" %F{$_axle_c[conflict]}=$conflicts%f"
  (( staged ))    && out+=" %F{$_axle_c[staged]}+$staged%f"
  (( changed ))   && out+=" %F{$_axle_c[changed]}!$changed%f"
  (( untracked )) && out+=" %F{$_axle_c[untracked]}?$untracked%f"
  (( stash ))     && out+=" %F{$_axle_c[stash]}*$stash%f"

  # Last commit: signature check (%G?) and age, in one call. %G? runs gpg only
  # when the commit is actually signed.
  local info sig
  local -i ct=0
  if info=$(command git log -1 --format='%ct %G?' 2>/dev/null) && [[ -n $info ]]; then
    ct=${info%% *}; sig=${info##* }
  fi
  case $sig in
    G)     out+=" %F{$_axle_c[sig_good]}$_axle_i[sig_good]%f" ;;     # good, trusted key
    B|R)   out+=" %F{$_axle_c[sig_bad]}$_axle_i[sig_bad]%f" ;;       # bad signature / revoked key
    U|X|Y|E)                                                          # untrusted, expired, unverifiable
           out+=" %F{$_axle_c[sig_warn]}$_axle_i[sig_unknown]%f" ;;
    N)     # Unsigned: only a warning where signing is expected; otherwise detail only.
           local badge=" %F{$_axle_c[sig_warn]}$_axle_i[sig_none]%f"
           if [[ $(command git config --bool commit.gpgsign 2>/dev/null) == true ]]; then
             out+=$badge
           else
             extra+=$badge
           fi ;;
  esac

  # How a push authenticates: SSH key vs HTTPS credentials.
  case $remote in
    '')                         ;;
    https://*)                  out+=" %F{$_axle_c[proto]}$_axle_i[proto]https%f" ;;
    http://*)                   out+=" %F{$_axle_c[sig_bad]}$_axle_i[proto]http%f" ;;  # unencrypted
    ssh://*|git+ssh://*|*@*:*)  out+=" %F{$_axle_c[proto]}$_axle_i[proto]ssh%f" ;;
    git://*)                    out+=" %F{$_axle_c[proto]}$_axle_i[proto]git%f" ;;
    *)                          out+=" %F{$_axle_c[proto]}$_axle_i[proto]local%f" ;;
  esac

  # Age of the last commit (detail only).
  (( ct )) && {
    local -i age=$(( EPOCHSECONDS - ct ))
    local a
    if   (( age < 60 ));     then a=now
    elif (( age < 3600 ));   then a="$(( age / 60 ))m"
    elif (( age < 86400 ));  then a="$(( age / 3600 ))h"
    elif (( age < 604800 )); then a="$(( age / 86400 ))d"
    else                          a="$(( age / 604800 ))w"
    fi
    extra+=" %F{$_axle_c[muted]}· $a%f"
  }
  # Raw state for layouts that draw git their own way (AxoN).
  local raw="branch=$branch dirty=$(( staged + changed + untracked > 0 ))"
  raw+=" unstaged=$(( changed + untracked > 0 )) staged=$(( staged > 0 )) conflicts=$conflicts"
  raw+=" sig=${sig:-} action=${action:-}${step:+ $step/$total}"
  [[ $head == '(detached)' && -z $onto ]] && raw+=" detached=${oid[1,7]}"
  print -rn -- "$out"$'\x1f'"$extra"$'\x1f'"$raw"
}

_axle_git_stop() {
  [[ -n $_axle_git_fd ]] || return
  zle -F $_axle_git_fd 2>/dev/null
  exec {_axle_git_fd}<&-
  _axle_git_fd=''
}

_axle_git_start() {
  _axle_git_stop
  if (( ! AXLE_GIT_ASYNC )) || ! (( $+builtins[zle] )); then
    _axle_seg[git]=$(_axle_git_compute); _axle_git_pwd=$PWD
    return
  fi
  exec {_axle_git_fd}< <(_axle_git_compute)
  zle -F $_axle_git_fd _axle_git_done
}

# zle -F callback: the worker finished; take its output and redraw.
_axle_git_done() {
  local fd=$1 out=''
  [[ $fd == $_axle_git_fd ]] || { zle -F $fd; exec {fd}<&-; return }
  IFS= read -r -u $fd -d '' out
  _axle_git_stop
  if [[ $out != ${_axle_seg[git]} || $_axle_git_pwd != $PWD ]]; then
    _axle_seg[git]=$out; _axle_git_pwd=$PWD
    _axle_render
    zle reset-prompt
  fi
}

# --- sudo countdown ----------------------------------------------------------

# After a command that used sudo, see whether credentials are now cached and when
# they lapse. sudo keeps no readable timestamp, so probe with `sudo -n true`; it
# only succeeds without a password, and resets the timer just as the command did.
_axle_sudo_check() {
  _axle_sudo_ran=0
  if ! command sudo -n true 2>/dev/null; then
    _axle_sudo_until=0; return
  fi
  if [[ -z $_axle_sudo_timeout ]]; then
    local out
    out=$(command sudo -n sudo -V 2>/dev/null)
    if [[ $out =~ 'timestamp timeout: (-?[0-9.]+)' ]]; then
      _axle_sudo_timeout=$match[1]
    else
      _axle_sudo_timeout=15                  # sudo's compiled-in default
    fi
  fi
  local -F mins=${AXLE_SUDO_TIMEOUT:-$_axle_sudo_timeout}
  if (( mins < 0 )); then
    _axle_sudo_until=-1                      # timestamp_timeout < 0: never expires
  elif (( mins > 0 )); then
    local -i secs=$(( mins * 60 ))
    _axle_sudo_until=$(( EPOCHSECONDS + secs ))
  else
    _axle_sudo_until=0                       # 0: sudo always asks
  fi
}

# --- redraw timer ------------------------------------------------------------
# A one-shot background sleep whose fd zle watches; when it fires, the prompt is
# re-rendered in place (zle reset-prompt) instead of printing a new one. It is
# only armed while a live segment needs it, and wakes only when the text changes.

_axle_timer_stop() {
  _axle_timer_at=0
  [[ -n $_axle_timer_fd ]] || return
  zle -F $_axle_timer_fd 2>/dev/null
  exec {_axle_timer_fd}<&-
  _axle_timer_fd=''
}

typeset -gF _axle_timer_at=0                # when the running timer rings (0: none)

_axle_timer_arm() {
  (( $+builtins[zle] )) || { _axle_timer_stop; return }
  local -F delay=0
  local -i left=$(( _axle_sudo_until - EPOCHSECONDS ))
  if (( _axle_sudo_until > 0 && left > 0 )); then
    # Minutes count down until the last minute, then seconds.
    delay=1
    (( left >= 60 )) && delay=$(( left - ( (left + 59) / 60 - 1 ) * 60 ))
    (( left >= 60 && left - delay < 59 )) && delay=$(( left - 59 ))
  fi
  # The clock ticks on the next whole minute, or whole second while expanded.
  local -a reply
  _axle_visible_segments
  if (( ${reply[(Ie)clock]} )); then
    local -F period=60
    (( _axle_detail )) && period=1
    local -F tick=$(( period - EPOCHREALTIME % period + 0.01 ))
    (( delay == 0 || tick < delay )) && delay=$tick
  fi
  # Drops (benzene/segments.zsh): look for changes every few seconds.
  # (On whole multiples of the period, like the clock: prompts in a row agree on the time,
  # so the timer running already is kept.)
  if (( $+functions[_axle_drop_poll] )); then
    _axle_drop_poll
    if (( REPLY > 0 )); then
      local -F poll=$(( REPLY - EPOCHREALTIME % REPLY + 0.01 ))
      (( delay == 0 || poll < delay )) && delay=$poll
    fi
  fi
  (( delay > 0 )) || { _axle_timer_stop; return }
  # The timer running already rings then (the next minute, mostly): keep it. A new one is a
  # new process each prompt, and the old one's sleep would linger until its time anyway.
  local -F at=$(( EPOCHREALTIME + delay ))
  if [[ -n $_axle_timer_fd ]] && (( at - _axle_timer_at < 0.05 && _axle_timer_at - at < 0.05 )); then
    return
  fi
  _axle_timer_stop
  _axle_timer_at=$at
  exec {_axle_timer_fd}< <(command sleep $delay; print)
  zle -F -w $_axle_timer_fd _axle_timer_tick
}

_axle_timer_tick() {
  _axle_timer_stop
  # Don't redraw over a completion menu, search, or continuation prompt.
  # Only when something on screen actually changed.
  if [[ $CONTEXT == start && $KEYMAP != (menuselect|isearch) ]]; then
    local before=$_axle_ps1
    _axle_render
    [[ $_axle_ps1 != $before ]] && zle reset-prompt
  fi
  _axle_timer_arm
}

# --- render ------------------------------------------------------------------

# Segments the current layout can show (reply=()); used to decide what needs ticking.
# Other layouts built on this engine (AxoN) override it, with _axle_render and
# _axle_compact_line.
_axle_visible_segments() {
  reply=($AXLE_NOX_LEFT $AXLE_NOX_RIGHT)
  (( _axle_vscode )) && reply=($AXLE_NOX_CODE)
}

# What a past prompt shrinks to: the time it ran, where, and the arrow.
_axle_compact_line() {
  _axle_seg_dir
  REPLY="%F{$_axle_c[clock]}%D{%H:%M:%S}%f $REPLY %F{$_axle_c[muted]}$AXLE_PROMPT_CHAR%f${(l:AXLE_PROMPT_GAP:):-}"
}

# Join segments into one string, in display order, hiding the least important
# ones (by AXLE_NOX_PRIORITY) past <max> segments or <width> columns; hidden
# segments are counted in a trailing "(+N)". Expanded mode lifts the <max> limit.
#   _axle_join <max> <width> <names...>
_axle_join() {
  local -i max=$1 budget=$2; shift 2
  local name sep=" %F{$_axle_c[sep]}$AXLE_SEP%f "
  local -a names parts widths alarms
  for name; do
    REPLY='' _axle_alarm=0 _axle_pinned=0
    (( $+functions[_axle_seg_$name] )) && _axle_seg_$name
    [[ -n $REPLY ]] || continue
    (( _axle_alarm && AXLE_ALARMS )) && _axle_pill $_axle_alarm
    names+=($name); parts+=("$REPLY"); alarms+=($(( _axle_alarm || _axle_pinned )))
    _axle_width "$REPLY"; widths+=($REPLY)
  done
  (( ${#parts} )) || { REPLY=''; return }
  (( _axle_detail )) && max=${#parts}

  local -i i r shown total hidden=0 worst rank
  while :; do
    shown=0 total=0
    for i in {1..${#parts}}; do
      [[ -n $parts[i] ]] && (( shown++, total += widths[i] + 3 ))
    done
    (( hidden )) && (( total += ${#hidden} + 3 + 3 ))     # " │ (+N)"
    (( shown > max || total > budget )) || break
    # Drop the least important visible segment (never the path or an alarm).
    worst=0 rank=0
    for i in {1..${#parts}}; do
      [[ -n $parts[i] && $names[i] != dir ]] && (( ! alarms[i] )) || continue
      r=${AXLE_NOX_PRIORITY[(ie)$names[i]]}
      (( r >= rank )) && { worst=i; rank=r }
    done
    (( worst )) || break
    parts[worst]=''; (( hidden++ ))
  done
  parts=(${parts:#})
  (( hidden )) && parts+=("%F{$_axle_c[muted]}(+$hidden)%f")
  REPLY=${(pj:$sep:)parts}
}

_axle_render() {
  setopt localoptions noglobsubst extendedglob
  # The frame and arrow are one piece (╭─ … ╰─➜) in one colour: the accent, deep red
  # under memory pressure, red after a failure (a failure wins).
  local char=$AXLE_PROMPT_CHAR colour=$_axle_c[accent]
  (( _axle_mem_used >= AXLE_MEM_WARN )) && colour=$_axle_c[pressure]
  [[ ${(j::)_axle_last_status} == *[1-9]* ]] && colour=$_axle_c[error]
  (( _axle_uid == 0 )) && char='#'
  [[ $_axle_keymap == vicmd ]] && char=$AXLE_PROMPT_CHAR_VICMD
  local frame=$colour

  local -i cols=${COLUMNS:-80}
  (( cols > 0 )) || cols=80                # COLUMNS is 0 without a terminal
  if (( _axle_vscode )); then
    # One line, no right prompt: VS Code's panel is short and often resized, and its
    # gutter already marks each command's result.
    _axle_join $AXLE_NOX_MAX_CODE $(( cols * 3 / 5 )) $AXLE_NOX_CODE
    _axle_ps1="${REPLY:+$REPLY }%F{$colour}$char%f${(l:AXLE_PROMPT_GAP:):-}"
    _axle_rps1='' _axle_bottom=''
    return
  fi
  # Top line: context on the left, stats on the right; the input line stays clear.
  # The right side is laid out first (up to half the width) so a failure alarm there
  # can't be crowded out by the left; the left gets what remains.
  _axle_join $AXLE_NOX_MAX_RIGHT $(( cols / 2 )) $AXLE_NOX_RIGHT
  _axle_top_r=$REPLY
  _axle_width $_axle_top_r; _axle_top_rw=$REPLY
  _axle_join $AXLE_NOX_MAX_LEFT $(( cols - _axle_top_rw - 6 )) $AXLE_NOX_LEFT
  _axle_top_l="%F{$frame}╭─%f $REPLY"
  _axle_width $_axle_top_l; _axle_top_lw=$REPLY
  _axle_bottom="%F{$frame}╰─$char%f${(l:AXLE_PROMPT_GAP:):-}"
  _axle_rps1=''
  _axle_layout
}

# `axle debug`: what the layout measured, to compare against what the terminal shows.
_axle_debug() {
  local saved=$_axle_detail
  _axle_detail=1; _axle_read_mem; _axle_render
  local s=${(%)${_axle_top_r//\%\{[^%]#\%\}/}}
  local icons=${s//[^$'\ue000'-$'\uf8ff'$'\U000f0000'-$'\U000ffffd']/}
  print -r -- "terminal:   COLUMNS=$COLUMNS TERM=$TERM WT_SESSION=${WT_SESSION:+set} TERM_PROGRAM=$TERM_PROGRAM"
  print -r -- "icons:      AXLE_NERD_FONT=$AXLE_NERD_FONT, counted as $(( _axle_icon_extra + 1 )) column(s) each"
  print -r -- "expanded:   left $_axle_top_lw + right $_axle_top_rw columns (${#icons} icons on the right)"
  print -r -- "ruler (should end exactly at the right edge, on one line):"
  print -r -- "${(l:COLUMNS-1::-:)}|"
  _axle_printp "${(l:$(( COLUMNS - _axle_top_rw - 1 )):: :)}$_axle_top_r|"
  _axle_detail=$saved; _axle_render
}

# Assemble the two-line prompt for the current width. PROMPT calls this (as the math
# function axle_layout, so no subshell) every time zsh draws it, so the right-aligned
# stats follow terminal resizes; if they no longer fit, they're dropped.
_axle_layout() {
  [[ -n $_axle_bottom ]] || return 0    # one-line layouts set _axle_ps1 themselves
  local -i cols=${COLUMNS:-80}
  (( cols > 0 )) || cols=80
  # Something another tool put before Benzene in PROMPT (conda's "(base) ", nemc's light)
  # takes columns from the top line, and pushes ╭─ out of line with ╰─. It's measured as it is now: only its variables are
  # read, and nothing in it runs (one with $(…) or `…` isn't measured).
  local -i pre=0
  local before=${PROMPT%%'%{${_axle_mark_a}%}'*}
  if [[ -n $before && $before != $PROMPT && $before != *('$('|'`')* ]]; then
    before=${(e)before}
    _axle_width ${before##*$'\n'}; pre=$REPLY
  fi
  # -1: writing the last column would make some terminals wrap early.
  local -i gap=$(( cols - pre - _axle_top_lw - _axle_top_rw - 1 ))
  local top=$_axle_top_l
  if [[ -n $_axle_top_r ]]; then
    if (( gap >= 2 )); then
      top+="${(l:gap:):-}$_axle_top_r"
    elif [[ $_axle_top_r == *%K\{* ]]; then
      top+="  $_axle_top_r"                # too narrow, but an alarm is never dropped
    fi
  fi
  # The top line can never wrap: auto-wrap (DECAWM) is off while it's drawn, so if a
  # terminal draws some glyph wider than computed, the line is clipped at the edge
  # instead of spilling onto a new line. It's back on before the input line.
  # The bottom line moves over by as much, so ╰─ stays under ╭─.
  _axle_ps1="%{"$'\e[?7l'"%}$top%{"$'\e[?7h'"%}"$'\n'"${(l:pre:):-}$_axle_bottom"
  return 0
}
functions -M axle_layout 0 0 _axle_layout

# --- hooks -------------------------------------------------------------------

_axle_preexec() {
  (( _axle_marks )) && print -n '\e]133;C\a'      # command output starts here
  _axle_cmd_start=$EPOCHREALTIME
  typeset -g _axle_last_cmd=$1
  # $3 is the command with aliases expanded (e.g. oh-my-zsh's `_`).
  (( ${${(z)3}[(I)sudo]} )) && _axle_sudo_ran=1
}

_axle_precmd() {
  _axle_last_status=($pipestatus)   # must be the very first statement
  _axle_elapsed=0
  if (( _axle_cmd_start )); then
    (( _axle_marks )) && print -n "\e]133;D;$_axle_last_status[-1]\a"   # command finished
    _axle_elapsed=$(( EPOCHREALTIME - _axle_cmd_start ))
    (( AXLE_NOTIFY_SECS > 0 && _axle_elapsed >= AXLE_NOTIFY_SECS )) && print -n '\a'
    _axle_cmd_start=0
  else
    _axle_last_status=()            # empty Enter: don't repeat the previous result
  fi
  _axle_keymap=main
  _axle_detail=0
  (( _axle_sudo_ran )) && _axle_sudo_check
  _axle_read_mem
  _axle_direnv_first                # direnv's hook, if it would run after this one
  _axle_scan_markers
  _axle_git_start
  _axle_render
  _axle_timer_arm
}

_axle_chpwd() {
  _axle_seg[git]=''; _axle_git_pwd=''
}

_axle_keymap_select() {
  [[ $KEYMAP == $_axle_keymap ]] && return
  _axle_keymap=$KEYMAP
  _axle_render
  zle reset-prompt
}

# Alt-i: expand the prompt to every segment, or collapse it again.
_axle_toggle_detail() {
  (( _axle_detail ^= 1 ))
  (( $+functions[_axle_emit] )) && _axle_emit expand $_axle_detail
  _axle_render
  zle reset-prompt
  _axle_timer_arm                       # start or stop the clock's ticking
}

# Compact past prompts: once a line is accepted (or abandoned with Ctrl-C), its prompt
# shrinks to the time it was run and where, followed by the command itself. Git,
# battery, run time etc. are dropped: they described the moment before the command.
#
# This has to happen before zle lets go of the line (zle-line-finish is too late: the
# cursor has already moved on), so the line is edited in a nested recursive-edit and
# the compact prompt is drawn once it returns.
_axle_line_init() {
  (( AXLE_TRANSIENT )) && [[ $CONTEXT == start ]] || return 0
  local -i ret
  while :; do
    zle .recursive-edit
    ret=$?
    # Ctrl-D on an empty line: behave like zsh would (exit unless IGNORE_EOF).
    [[ $ret == 0 && $KEYS == $'\4' ]] || break
    [[ -o ignore_eof ]] || exit 0
  done
  POSTDISPLAY=''                        # no suggestion ghost text left in scrollback
  _axle_compact_line
  _axle_ps1=$REPLY
  _axle_rps1='' _axle_bottom=''
  zle .reset-prompt
  _axle_render                          # restore the full prompt for whatever comes next
  if (( ret )); then
    zle .send-break
  else
    zle .accept-line
  fi
  return ret
}

_axle_variant_cleanup() {
  _axle_git_stop
  _axle_timer_stop
  if [[ -n $AXLE_DETAIL_KEY ]] && (( $+builtins[zle] )); then
    local km
    for km in emacs viins vicmd; do
      [[ $(bindkey -M $km $AXLE_DETAIL_KEY) == *_axle_toggle_detail ]] &&
        bindkey -M $km -r $AXLE_DETAIL_KEY
    done
  fi
}

# --- install -----------------------------------------------------------------


setopt prompt_subst
add-zsh-hook preexec _axle_preexec
add-zsh-hook chpwd   _axle_chpwd
add-zsh-hook precmd  _axle_precmd
# Run our precmd first so $pipestatus still belongs to the user's command.
# (After the axle tool's hooks, if it's loaded: they run first so a hook can feed a
# segment before it's drawn. zsh gives every hook the real $? and $pipestatus.)
precmd_functions=(${(M)precmd_functions:#_axt_*} _axle_precmd ${precmd_functions:#(_axle_precmd|_axt_*)})

if (( $+builtins[zle] )); then
  autoload -Uz add-zle-hook-widget
  add-zle-hook-widget keymap-select _axle_keymap_select
  add-zle-hook-widget line-init     _axle_line_init
  zle -N _axle_toggle_detail
  zle -N _axle_timer_tick
  if [[ -n $AXLE_DETAIL_KEY ]]; then
    bindkey -M emacs  $AXLE_DETAIL_KEY _axle_toggle_detail
    bindkey -M viins  $AXLE_DETAIL_KEY _axle_toggle_detail
    bindkey -M vicmd  $AXLE_DETAIL_KEY _axle_toggle_detail
  fi
fi

# Indirection keeps branch names etc. from being re-expanded by prompt_subst.
# The marks around it tell the terminal where each prompt and command line starts.
typeset -g _axle_mark_a='' _axle_mark_b=''
(( _axle_marks )) && _axle_mark_a=$'\e]133;A\a' _axle_mark_b=$'\e]133;B\a'
PROMPT='%{${_axle_mark_a}%}${${:-$(( axle_layout() ))}:+}${_axle_ps1}%{${_axle_mark_b}%}'
RPROMPT='${_axle_rps1}'
