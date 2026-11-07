# Tab completion for `axle`: every command, and what each takes (variants, palettes,
# modules, segments, preview scenarios, hook events, drops, settings and their values).

# Setting names and their values come from the settings table.
(( ${+_axle_settings} )) || source "$AXLE_ROOT/lib/settings.zsh"

_axle_complete() {
  setopt localoptions extendedglob
  local -a subs reply
  local name
  for name in ${(ok)_axle_cmd_fn}; do subs+=("$name:${_axle_cmd_desc[$name]//:/\\:}"); done
  subs+=('help:help for a command')
  if (( CURRENT == 2 )); then
    _describe -t commands 'axle command' subs
    return
  fi
  local sub=$words[2]
  case $sub in
    help)
      (( CURRENT == 3 )) && _describe -t commands 'command' subs ;;
    variant)
      (( CURRENT == 3 )) && _values variant 'nox[NoxA: two lines, shows what is relevant]' \
        'axon[AxoN: one quiet line]' ;;
    palette)
      (( CURRENT == 3 )) && _values palette 'mocha[Catppuccin Mocha, 24-bit]' 'classic[256 colours]' ;;
    module)
      if (( CURRENT == 3 )); then
        _values action 'ls[list modules]' 'on[switch one on]' 'off[switch one off]'
      elif (( CURRENT == 4 )); then
        _axle_module_names
        local -a mods=($reply)
        [[ $words[3] == (off|disable) ]] && mods=(${mods:*AXLE_MODULES})
        [[ $words[3] == (on|enable) ]]   && mods=(${mods:|AXLE_MODULES})
        _describe -t modules module mods
      fi ;;
    segment)
      case $CURRENT in
        3) _values action 'add[add your own segment]' 'rm[remove one you added]' 'ls[list yours]' ;;
        4) [[ $words[3] == rm ]] && { local -a mine=(${(k)_axle_ext_segments}); _describe -t segments segment mine } ;;
        5) [[ $words[3] == add ]] && { local -a fns=(${(k)functions:#_*}); _describe -t functions function fns } ;;
        6) [[ $words[3] == add ]] && _values side 'left[the first line]' 'right[the stats on the right]' ;;
      esac ;;
    preview)
      local -a scenes=() line
      for line in "${(@f)$(<$AXLE_ROOT/benzene/preview.zsh)}"; do
        [[ $line == (#b)_pv_add\ ([a-z0-9-]##)\ ##\'(*)\' ]] && scenes+=("$match[1]:${match[2]//:/\\:}")
      done
      if [[ $PREFIX == -* ]]; then
        compadd -- --all --list --nox --axon --expanded --nerd --width
      else
        _describe -t scenarios scenario scenes
      fi ;;
    hook)
      local -a events=('command-start:before a command runs' 'command-done:after it finishes'
                       'prompt:before each prompt' 'expand:Alt-i toggled' 'dir:the directory changed'
                       'run-start:axle run started something' 'run-ready:a service answers'
                       'run-crash:what axle run started failed' 'run-stop:it stopped or finished')
      case $CURRENT in
        3) _describe -t events event events; compadd -- ls rm ;;
        4) if [[ $words[3] == rm ]]; then _describe -t events event events
           else local -a fns=(${(k)functions:#_*}); _describe -t functions function fns; fi ;;
        5) [[ $words[3] == rm ]] && {
             local -a fns=(${(P)${:-_axle_hook_${words[4]//-/_}}}); _describe -t functions function fns } ;;
      esac ;;
    drop)
      local dir=${_axle_drop_dir:-${XDG_CACHE_HOME:-$HOME/.cache}/axle/drops}
      case $words[CURRENT-1] in
        --rm)    local -a drops=($dir/*(N:t)); _describe -t drops drop drops ;;
        --level) _values level 'ok[green]' 'info[accent]' 'warn[amber bubble]' 'alarm[red bubble]' ;;
        --ttl)   _message 'lifetime: 30s, 10m, 2h, 1d' ;;
        --while-pid) _pids 2>/dev/null ;;
        --dir)   _directories ;;
        *)       (( CURRENT > 3 )) && compadd -- --level --ttl --while-pid --dir --link --icon --expanded
                 (( CURRENT == 3 )) && compadd -- --ls --rm ;;
      esac ;;
    stats)
      [[ $words[CURRENT-1] == --days ]] && { _message 'number of days'; return }
      compadd -- --here --days ;;
    history)
      _message 'how many (default 20)' ;;
    update)
      (( CURRENT == 3 )) && _values option '--check[only say whether a new version is out]' ;;
    uninstall)
      (( CURRENT == 3 )) && _values option '--yes[links and cache, no questions]' \
        '--purge[also settings and history, no questions]' ;;
    run)
      local -a svcs=(${XDG_STATE_HOME:-$HOME/.local/state}/axle/run/services/*(N/:t))
      if (( CURRENT == 3 )) && [[ $PREFIX != -* ]]; then
        _values action 'ls[what is running]' 'stop[stop a service]' 'restart[restart a service]' \
          'logs[a service'"'"'s output]' 'open[open its URL]' 'set[this project'"'"'s settings]' \
          'forget[drop this project'"'"'s settings and approvals]' \
          'deps[install its Python packages (a shared venv if they fit)]'
        (( $+functions[_axle_jump_complete] )) && { shift words; (( CURRENT-- )); _axle_jump_complete }
      elif [[ $words[3] == set ]]; then
        case $CURRENT in
          4) _values setting 'command[what runs]' 'port[the port it listens on]' \
               'kind[service (background) or task (foreground)]' 'env-file[its .env file]' ;;
          5) case $words[4] in
               kind)     compadd -- service task ;;
               env-file) _files -g '.env*(D)' ;;
             esac ;;
        esac
      elif [[ $words[CURRENT-1] == --profile ]]; then
        local -a profs=(.env.*(DN.))
        profs=(${profs#.env.} none)
        compadd -a profs
      elif [[ $words[3] == (stop|restart|logs|open) ]]; then
        [[ $words[3] == stop ]] && svcs+=(all)
        [[ $words[3] == logs ]] && compadd -- -f
        compadd -a svcs
      elif [[ $PREFIX == -* ]]; then
        _values option '--dry-run[say what would run, and why]' '--yes[run without asking]' \
          '--fg[in the foreground]' '--bg[in the background]' '--config[choose the parts again]' \
          '--verbose[show these parts'"'"' output]' '--only[just the --verbose parts]' \
          '--profile[use .env.<name> over .env, remembered]'
      elif (( $+functions[_axle_jump_complete] )); then
        shift words; (( CURRENT-- ))
        _axle_jump_complete
      else
        _directories
      fi ;;
    jump)
      if (( $+functions[_axle_jump_complete] )); then
        shift words; (( CURRENT-- ))
        _axle_jump_complete
      fi ;;
    config)
      case $CURRENT in
        3) _values action 'list[every setting]' 'get[one setting]' 'set[change one]' \
             'unset[back to the default]' 'edit[open the file]' 'path[where the file is]' ;;
        4) [[ $words[3] == (get|set|unset|rm) ]] || return
           local -a names=()
           for name in ${(ok)_axle_settings}; do
             _axle_setting $name
             [[ $reply[1] == theme ]] && (( ! ${_axle_theme_loaded:-0} )) && continue
             [[ $reply[1] == tool ]]  && (( ! ${_axle_tool_loaded:-0} ))  && continue
             names+=("$name:${reply[4]//:/\\:}")
           done
           _describe -t settings setting names ;;
        *) [[ $words[3] == set ]] || return
           _axle_setting $words[4] || return
           case $reply[2] in
             bool)     _values value '1[on]' '0[off]' ;;
             int)      _message "a whole number (default ${reply[3]:-none})" ;;
             choice:*) local -a vals=(${(s:,:)reply[2]#choice:}); compadd -a vals ;;
             list)     case $words[4] in
                         AXLE_MODULES) _axle_module_names; local -a v=($reply); compadd -a v ;;
                         AXLE_SUGGEST_STRATEGY) compadd smart history completion ;;
                         AXLE_NOX_*|AXLE_AXON_SHOW)
                           local -a v=(${${(M)${(k)functions}:#_axle_seg_*}#_axle_seg_}); compadd -a v ;;
                         *) _message 'words' ;;
                       esac ;;
             *)        _message "${reply[4]}" ;;
           esac ;;
      esac ;;
  esac
}
