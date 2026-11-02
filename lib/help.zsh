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
  doctor $'Check the setup (zsh, git, what is loaded, conflicts, colours, fonts,\nhistory, config, prompt speed), with a fix for anything that is off.\n\n  axle doctor'
  run $'Run this project, the one you name, or the last one you worked in.\nWhich project: the words you give (ranked like j), a path, the one you\'re in,\nor else the last one in your history (it takes you there). How: detected from\nthe files (docker compose, a Procfile, package.json scripts, FastAPI / Flask /\nDjango / Streamlit apps, pyproject scripts, main.py, Cargo.toml, go.mod, a\nMakefile or justfile, index.html), in the project\'s venv. The first time a project\'s command runs, it shows it and asks.\n\n  axle run                 this project (elsewhere: back to the last one)\n  axle run shop            the project j would pick for "shop"\n  axle run ~/repos/api     that folder\'s project\n  axle run --dry-run       what would run, and why\n  axle run --yes           don\'t ask (you approve the command unseen)\n  axle run --fg / --bg     force foreground / background\n\nProjects with several parts (a frontend and a backend, workspaces, apps/*):\nthe first time it asks which to start, and saves that; it says when a saved\npart can\'t run any more, and starts the rest. A part that fails shows its log.\n\n  axle run --config        choose the parts again\n  axle run --verbose \'shop-web, shop-api\'\n                           show their output: each in a tmux session (with\n                           tmux), or one in this shell after the others start\n  axle run --verbose shop-api --only     just that one\n\nServers run in the background and show in the prompt: ⏳ while starting,\n⚡ name :port when up (Ctrl+click opens it), red if it exits with an error.\nThey keep running when the terminal closes. If its port is taken, it says by\nwhom and offers: the next free port, stopping the other (yours, or after\nasking, someone else\'s), or cancel.\n\n  axle run ls              what\'s running: state, port, uptime, memory, URL\n  axle run stop [name|all] this project\'s service, one by name, or all\n  axle run restart [name]\n  axle run logs [-f] [name]   its output (and clears a red tab)\n  axle run open [name]     open its URL in the browser'
  module $'List the tool\'s modules, or switch one on or off (saved).\n\n  axle module\n  axle module off env\n  axle module on env'
  hook $'Run your function on shell events.\n\n  slow() { (( $2 > 30 )) && notify-send "done: $3" }\n  axle hook command-done slow     gets: exit code, seconds, command\n  axle hook ls\n  axle hook rm command-done slow\n\nEvents: command-start, command-done, prompt, expand, dir.'
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

# `axle help <command>`.
_axle_help_one() {
  local name=$1
  if (( ! ${+_axle_cmd_fn[$name]} )) && [[ $name != help ]]; then
    local -a reply
    _axle_did_you_mean $name
    print -u2 -r -- "axle: no command '$name'${reply:+ — did you mean: axle ${(j:, axle :)reply[1,3]}?}"
    return 1
  fi
  local usage=${_axle_cmd_usage[$name]:-$name}
  _axle_printp "%Baxle ${usage//\%/%%}%b"
  [[ -n $_axle_cmd_desc[$name] ]] && _axle_printp "%F{${_axle_c[muted]:-244}}${_axle_cmd_desc[$name]//\%/%%}%f"
  print
  if [[ -n $_axle_cmd_help[$name] ]]; then
    print -r -- "${_axle_cmd_help[$name]}"
  fi
}
