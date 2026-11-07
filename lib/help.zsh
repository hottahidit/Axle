# Help for single commands (`axle help <command>`, `axle <command> --help`), and "did you
# mean" for typos. A page is a usage line, what it does, and examples; it's shown only for
# commands that are loaded.

typeset -gA _axle_cmd_help=(
  configure $'Set Axle up step by step: questions with a live preview of the prompt,\nfor whichever parts are installed. Saves to the config file.\n\n  axle configure'
  config $'See and change settings without the wizard or an editor. Saved to\n~/.config/axle/config.zsh (read after ~/.zshrc, so it wins) and applied at once.\n\n  axle config                          every setting and where its value comes from\n  axle config get AXLE_PALETTE         what it does, its value and default\n  axle config set AXLE_PALETTE classic\n  axle config set AXLE_MODULES suggest jump     (a list: several words)\n  axle config set                      pick from menus\n  axle config unset AXLE_PALETTE       back to the default\n  axle config edit                     open the file in $EDITOR'
  reload $'Re-read Axle\'s files, after an update or an edit.\n\n  axle reload'
  update $'Update Axle (git pull --ff-only in its folder), then reload.\n\n  axle update            update now\n  axle update --check    only say whether a new version is out, and what changed\n\nA new version is also announced once a day (AXLE_UPDATE_CHECK=0 turns that off).'
  version $'Which version is loaded, and which parts.\n\n  axle version'
  uninstall $'Remove Axle: the links install.sh made, and (if you choose) its settings,\nrecorded history and cache. It asks before each step, and never edits ~/.zshrc:\nit shows the lines to remove.\n\n  axle uninstall\n  axle uninstall --yes      links and cache only, no questions\n  axle uninstall --purge    also settings and history, no questions'
  help $'Help for Axle, or for one command.\n\n  axle help\n  axle help stats\n  axle stats --help'
  # the prompt
  variant $'Show or switch the prompt variant: nox (NoxA, two lines) or axon (AxoN,\none quiet line). Switches this shell only; to keep it: axle config set AXLE_VARIANT axon\n\n  axle variant\n  axle variant axon'
  preview $'Show the prompt in every state it handles, drawn in your terminal with your\nfont and settings. Keys switch variant, expanded view, icons, palette and width.\n\n  axle preview                     interactive\n  axle preview --all               print every state\n  axle preview --list              their names\n  axle preview failed prod         just these\n  axle preview --all --axon --expanded --nerd --width 80'
  palette $'Show or switch the colours: mocha (Catppuccin Mocha, 24-bit) or classic\n(256 colours). Switches this shell only; to keep it: axle config set AXLE_PALETTE classic\n\n  axle palette\n  axle palette classic'
  colors $'Every colour role, as a swatch with its value.\n\n  axle colors\n\nOverride one: typeset -A AXLE_COLORS=(path \'#74c7ec\')'
  segments $'Which segments are shown where, and every segment available.\n\n  axle segments'
  segment $'Your own prompt segments: a function that sets REPLY (empty = hidden).\n\n  weather() { axle_style sky "$(< ~/.cache/weather)" }\n  axle segment add weather weather right      left|right, optional priority\n  axle segment ls\n  axle segment rm weather'
  ai $'The AI services watched for the expanded view (AXLE_AI_STATUS), with their\nstate and when they were checked.\n\n  axle ai'
  tmux $'Prints Benzene\'s tmux settings (24-bit colour, links, a matching status bar).\n\n  axle tmux\n  echo "source-file $AXLE_ROOT/benzene/tmux.conf" >> ~/.tmux.conf'
  debug $'What the layout measured: widths, icon width, segments shown and hidden.\n\n  axle debug'
  refresh $'Forget cached tool versions and config lookups, and measure the icon\nwidth again (after changing font or terminal).\n\n  axle refresh'
  # the tool
  jump $'Go to the folder you most likely mean, ranked by where you actually work.\nThe last word matches the folder\'s own name; earlier words, its path, in order.\n\n  j api          the best folder matching "api"\n  j re ax        path matches "re", then folder "ax"\n  j              your top folders\n  j -l api       list matches without going\n  j -            back to the previous folder'
  history $'Recent commands: when they ran, how they ended, how long they took, where.\n\n  axle history       the last 20\n  axle history 100'
  stats $'What you run, what is slow, what fails, and where you work.\n\n  axle stats\n  axle stats --here         just this folder and below\n  axle stats --days 7'
  top $'The system live, with btop: CPU, memory, disks, network, processes.\nAxle\'s own btop (btop 1.4.8 from vendor/btop, with an Axle mode) is built by\ninstall.sh or axle top --build; it needs g++ 14+ or clang 19+. Without it, axle\ntop runs the btop you have installed. It reads your usual btop settings.\n\n  axle top           btop; key A: only the processes axle run started\n  axle top -p 1      btop\'s options (here: preset 1)\n  axle top --build   build Axle\'s btop\n  axle run top       Axle\'s btop in the Axle mode (A: all processes)'
  doctor $'Check the setup (zsh, git, what is loaded, conflicts, colours, fonts,\nhistory, config, prompt speed), with a fix for anything that is off.\n\n  axle doctor'
  run $'Run this project, the one you name, or the last one you worked in.\nWhich project: the words you give (ranked like j), a path, the one you\'re in,\nor else the last one in your history (it takes you there). How: detected from\nthe files (docker compose, a Procfile, package.json scripts, FastAPI / Flask /\nDjango / Streamlit apps, pyproject scripts, main.py, Cargo.toml, go.mod, a\nMakefile or justfile, index.html), in the project\'s venv (any folder with a\npyvenv.cfg). If another venv is active it asks which to use: AXLE_RUN_VENV=\nask, project or active. The first time a project\'s command runs, it shows it and asks.\n\n  axle run                 this project (elsewhere: back to the last one)\n  axle run shop            the project j would pick for "shop"\n  axle run ~/repos/api     that folder\'s project\n  axle run --dry-run       what would run, and why\n  axle run --yes           don\'t ask (you approve the command unseen)\n  axle run --fg / --bg     force foreground / background\n\nProjects with several parts (a frontend and a backend, workspaces, apps/*):\nthe first time it asks which to start, and saves that; it says when a saved\npart can\'t run any more, and starts the rest. A part that fails shows its log.\n\n  axle run --config        choose the parts again\n  axle run --verbose \'shop-web, shop-api\'\n                           show their output: each in a tmux session (with\n                           tmux), or one in this shell after the others start\n  axle run --verbose shop-api --only     just that one\n\nServers run in the background and show in the prompt: ⏳ while starting,\n⚡ name :port when up (Ctrl+click opens it), red if it exits with an error.\nThey keep running when the terminal closes. If its port is taken, it says by\nwhom and offers: the next free port, stopping the other (yours, or after\nasking, someone else\'s), or cancel.\n\n  axle run ls              what\'s running: state, port, uptime, memory, URL\n  axle run stop [name|all] this project\'s service, one by name, or all\n  axle run restart [name]\n  axle run logs [-f] [name]   its output (and clears a red tab)\n  axle run open [name]     open its URL in the browser\n  axle run top             all of them live: Axle\'s btop showing only them (when\n                           built: axle top --build), else a view of their CPU,\n                           memory and logs (↑↓, s stop, r restart, o open, l log)\n  axle run top --mini      a few lines under the prompt, for a quick look\n\nYour settings, per project (or the part you\'re in), kept in axle run\'s state,\nnot in the project. Your own command runs without asking.\n\n  axle run set             show them\n  axle run set command "npm run dev -- --host"\n  axle run set port 8080   (given to the server, as with a taken port)\n  axle run set kind task   service (background) or task (foreground)\n  axle run set env-file .env.local\n  axle run set restart on-crash   start it again after a crash (1, 2, 4... s)\n  axle run set needs db    compose services it needs, started first\n  axle run set health /healthz   up (and well) only when that answers\n  axle run set port        remove one: back to what\'s detected\n  axle run forget          drop its settings, saved parts and approvals\n  axle run --profile prod  .env.prod over .env, remembered (--profile none)\n\nIts other commands, the same words in every project (from package.json\nscripts, a justfile, a Makefile, pyproject scripts, cargo, go, pytest):\n\n  axle run :               list them\n  axle run :test -k api    run one (asked the first time)\n\n  axle run env             what a service here gets (.env files, axle run\'s,\n                           the venv); secrets masked (--show: not)\n  axle run group dev add   several projects together: add this one, then\n  axle run group dev       start them all (axle run group dev stop)\n\nA database its .env points at (DATABASE_URL=postgres://...@localhost) that isn\'t\nrunning is started first from the project\'s compose file (asked the first time).\n\nSettings: AXLE_RUN_ON_EXIT=stop (services end with their terminal),\nAXLE_RUN_OPEN=1 (open the browser when ready), AXLE_RUN_TRUST=always (never ask),\nAXLE_RUN_RESTART=on-crash (for all), AXLE_RUN_NOTIFY=crash|ready|all (desktop\nnotifications), AXLE_RUN_LOG_MAX=10M (a log past it moves to log.1).\n\nWhen a service crashes or a task fails, it says why if it\'s a known cause (a\nmissing package, no venv or node_modules, a taken port, a database not\nstarted) and its fix goes on the line with Esc Esc or fix: check it, then Enter.\n\nA shared venv: projects under a folder with a .venv use it when they have none\nof their own (AXLE_RUN_UNIVENV=~/Projects makes it there when needed).\n\n  axle run deps            install requirements.txt (or pyproject.toml\'s\n                           dependencies): into the shared venv, keeping the\n                           versions there; if they conflict, into its own .venv\n  axle run deps rich       and this package too'
  module $'List the tool\'s modules, or switch one on or off (saved).\n\n  axle module\n  axle module off env\n  axle module on env'
  hook $'Run your function on shell events.\n\n  slow() { (( $2 > 30 )) && notify-send "done: $3" }\n  axle hook command-done slow     gets: exit code, seconds, command\n  axle hook ls\n  axle hook rm command-done slow\n\nEvents: command-start, command-done, prompt, expand, dir; and from axle run,\nin the shell that started it: run-start (name, folder, kind), run-ready (name,\nURL, port), run-crash (name, exit code), run-stop (name).'
  drop $'Put a tab in every open prompt, from here or any program (tools/axle-drop).\n\n  axle drop build "build running" --while-pid $$\n  axle drop ci "tests failed" --level alarm --ttl 1h\n  axle drop --ls\n  axle drop --rm ci\n\nOptions: --level ok|info|warn|alarm, --ttl 30s|10m|2h|1d, --while-pid, --dir,\n--link, --icon, --expanded.'
)

# The edit distance between two words (REPLY), for "did you mean".
_axle_distance() {
  local a=$1 b=$2
  local -i i j la=${#1} lb=${#2} cost
  local -a prev cur
  for (( j = 0; j <= lb; j++ )); do prev[j+1]=$j; done
  for (( i = 1; i <= la; i++ )); do
    cur=($i)
    for (( j = 1; j <= lb; j++ )); do
      if [[ ${a[i]} == ${b[j]} ]]; then cost=0; else cost=1; fi
      local -i del=$(( prev[j+1] + 1 )) ins=$(( cur[j] + 1 )) sub=$(( prev[j] + cost ))
      (( cur[j+1] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub) ))
    done
    prev=($cur)
  done
  REPLY=${prev[lb+1]}
}

# Commands close to a mistyped one (reply=()), best first.
_axle_did_you_mean() {
  local typed=$1 name
  local -a scored=()
  for name in ${(k)_axle_cmd_fn} help; do
    if [[ $name == $typed* || $typed == $name* ]]; then
      scored+=("0 $name")
    else
      _axle_distance $typed $name
      (( REPLY <= ( ${#typed} >= 4 ? 2 : 1 ) )) && scored+=("$REPLY $name")
    fi
  done
  reply=(${${(on)scored}#* })
}

# --- how it looks ------------------------------------------------------------------
# Colours by role (the tool alone has no palette: plain terminal colours then).

_axle_help_colours() {
  typeset -g _axle_h_acc=${_axle_c[accent]:-magenta} _axle_h_cmd=${_axle_c[path]:-blue}
  typeset -g _axle_h_mut=${_axle_c[muted]:-244} _axle_h_arg=${_axle_c[python]:-cyan}
  typeset -g _axle_h_set=${_axle_c[changed]:-yellow} _axle_h_sep=${_axle_c[sep]:-240}
  typeset -gi _axle_h_w=$(( ${COLUMNS:-80} > 100 ? 100 : ${COLUMNS:-80} ))
  (( _axle_h_w > 20 )) || _axle_h_w=80
  # Colours only for a terminal (and not with NO_COLOR): piped, it's plain text.
  typeset -gi _axle_h_plain=0
  [[ -t 1 && -z ${NO_COLOR:-} ]] || _axle_h_plain=1
}

# Print a line of help: styled in a terminal, plain otherwise.
_axle_help_out() {
  if (( ! _axle_h_plain )); then _axle_printp "$1"; return; fi
  setopt localoptions extendedglob
  local s=${(S)1//\%\{*\%\}/}
  s=${(S)s//\%[FK]\{*\}/}
  s=${s//\%[BbFfKkUu]/}
  print -r -- "${s//\%\%/%}"
}

# A section rule: ── Title ─────────
_axle_help_rule() {
  local -i fill=$(( _axle_h_w - ${#1} - 6 ))
  (( fill > 0 )) || fill=1
  _axle_help_out "%F{$_axle_h_sep}──%f %B%F{$_axle_h_acc}${1//\%/%%}%f%b %F{$_axle_h_sep}${(pl:fill::─:)}%f"
}

# Words wrapped to <width> (reply = the lines).
_axle_help_wrap() {
  local text=$1 w line=''
  local -i width=$2
  reply=()
  for w in ${=text}; do
    if [[ -n $line ]] && (( ${#line} + 1 + ${#w} > width )); then
      reply+=("$line"); line=$w
    else
      line+=${line:+ }$w
    fi
  done
  [[ -n $line ]] && reply+=("$line")
}

# Usage words coloured: options and choices as arguments, the rest plain (REPLY).
_axle_help_args() {
  REPLY="%F{$_axle_h_arg}${1//\%/%%}%f"
}

# One line of a help page, coloured (REPLY). Examples (indented by two) get their command
# coloured and a trailing explanation (after a run of spaces) muted; text gets setting
# names picked out.
_axle_help_line() {
  setopt localoptions extendedglob
  local line=${1//\%/%%} code note w
  local -a out
  if [[ $line == '  '[^[:space:]]* ]]; then
    code=${line#  }
    note=''
    if [[ $code == (#b)(*[^[:space:]])(   ##)([^[:space:]]*) ]]; then
      code=$match[1]; note=$match[2]$match[3]
      [[ $code == *'   '* ]] && { note=${code#*   }$note; code=${code%%   *} }
    fi
    local -i first=1
    for w in "${(@s: :)code}"; do
      if (( first == 2 )) && [[ -n $w ]]; then     # axle's subcommand
        out+=("%B%F{$_axle_h_cmd}$w%f%b"); first=0
      elif (( first )) && [[ -n $w ]]; then
        out+=("%F{$_axle_h_cmd}$w%f"); first=0
        [[ $w == axle ]] && first=2
      elif [[ $w == -* ]]; then
        out+=("%F{$_axle_h_acc}$w%f")
      elif [[ $w == AXLE_[A-Z_]## ]]; then
        out+=("%F{$_axle_h_set}$w%f")
      else
        out+=("$w")
      fi
    done
    REPLY="  ${(j: :)out}"
    [[ -n $note ]] && REPLY+="%F{$_axle_h_mut}$note%f"
  elif [[ $line == '   '* ]]; then
    REPLY="%F{$_axle_h_mut}$line%f"                # an explanation carried over
  else
    REPLY=${line//(#b)(AXLE_[A-Z_]##)/%F{$_axle_h_set}$match[1]%f}
  fi
}

# `axle help`: every loaded command, by part.
_axle_help() {
  _axle_help_colours
  local group name usage args alias l al a desc head
  local -A titles=(general 'Setup' theme 'Benzene, the prompt' tool 'axle, the tool')
  local -A rows_name rows_alias rows_args
  local -i ncol=0 acol=0 narrow=$(( ${COLUMNS:-80} < 72 ))
  for name in ${(k)_axle_cmd_group}; do
    usage=${_axle_cmd_usage[$name]:-$name}
    args=${${usage#$name}## #}
    alias=''
    if [[ $args == *'('[^\)]#')' ]]; then
      alias=${${args##*\(}%\)}
      args=${${args%\(*}%% #}
      [[ $alias == $name ]] && alias=''
    fi
    rows_args[$name]=$args rows_alias[$name]=$alias
    local -i n=$(( ${#name} + ${#alias} + ${#alias:+1} ))
    (( n > ncol )) && ncol=n
    (( ${#args} > acol && ${#args} <= 26 )) && acol=${#args}   # (longer: on a line of its own)
  done
  _axle_help_out "%B%F{$_axle_h_acc}Axle%f%b %F{$_axle_h_mut}$AXLE_VERSION · a toolkit for zsh%f"
  for group in general theme tool; do
    local -a names=()
    for name in ${(ok)_axle_cmd_group}; do
      [[ $_axle_cmd_group[$name] == $group ]] && names+=($name)
    done
    (( ${#names} )) || continue
    print
    _axle_help_rule ${titles[$group]}
    for name in $names; do
      alias=$rows_alias[$name] args=$rows_args[$name]
      al='' a=''
      [[ -n $alias ]] && al=" %F{$_axle_h_acc}$alias%f"
      [[ -n $args ]] && a="%F{$_axle_h_arg}${args//\%/%%}%f"
      head="  %B%F{$_axle_h_cmd}$name%f%b$al"
      local -i pad=$(( ncol - ${#name} - ${#alias} - ${#alias:+1} ))
      desc=$_axle_cmd_desc[$name]
      if (( narrow )); then
        _axle_help_out "$head $a"
        _axle_help_wrap "$desc" $(( _axle_h_w - 6 ))
        for l in $reply; do _axle_help_out "      %F{$_axle_h_mut}${l//\%/%%}%f"; done
        continue
      fi
      local -i dcol=$(( 2 + ncol + 2 + acol + 2 ))
      _axle_help_wrap "$desc" $(( _axle_h_w - dcol ))
      local -a lines=($reply)
      if (( ${#args} > acol )); then             # long arguments: the text goes below
        _axle_help_out "$head${(l:pad:):-}  $a"
      else
        _axle_help_out "$head${(l:pad:):-}  $a${(l:acol-${#args}:):-}  ${lines[1]//\%/%%}"
        shift lines
      fi
      for l in $lines; do _axle_help_out "${(l:dcol:):-}${l//\%/%%}"; done
    done
  done
  print
  _axle_help_out "%F{$_axle_h_mut}More on one:%f %F{$_axle_h_cmd}axle help%f %F{$_axle_h_arg}<command>%f %F{$_axle_h_mut}(or%f %F{$_axle_h_cmd}axle%f %F{$_axle_h_arg}<command>%f %F{$_axle_h_acc}--help%f%F{$_axle_h_mut}) · Tab completes everything%f"
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

# `axle help <command>`.
_axle_help_one() {
  local name=$1
  if (( ! ${+_axle_cmd_fn[$name]} )) && [[ $name != help ]]; then
    local -a reply
    _axle_did_you_mean $name
    print -u2 -r -- "axle: no command '$name'${reply:+ — did you mean: axle ${(j:, axle :)reply[1,3]}?}"
    return 1
  fi
  _axle_help_colours
  local usage=${_axle_cmd_usage[$name]:-$name} REPLY line
  local args=${${usage#$name}## #} a=''
  [[ -n $args ]] && a=" %F{$_axle_h_arg}${args//\%/%%}%f"
  _axle_help_out "%B%F{$_axle_h_acc}axle%f %F{$_axle_h_cmd}$name%f%b$a"
  [[ -n $_axle_cmd_desc[$name] ]] &&
    _axle_help_out "%F{$_axle_h_mut}"$'%{\e[3m%}'"${_axle_cmd_desc[$name]//\%/%%}"$'%{\e[23m%}'"%f"
  [[ -n $_axle_cmd_help[$name] ]] || return 0
  print
  for line in "${(@f)_axle_cmd_help[$name]}"; do
    _axle_help_line "$line"
    _axle_help_out "$REPLY"
  done
}
