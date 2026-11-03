# Benzene — a zsh prompt theme, part of Axle. Two variants, the two halves of one ring:
#   NoxA (nox)   two lines; shows what's relevant, Alt-i for everything
#   AxoN (axon)  one quiet line; only what needs attention
#
# Works on its own: oh-my-zsh ZSH_THEME="benzene", or `source` this file in plain zsh.
# With the axle tool (axle.plugin.zsh) it gains smart suggestions, jump, history search,
# automatic venvs and more; see `axle help`.
#
# Pick a variant before it loads (or switch any time with `axle variant`):
#   AXLE_VARIANT=nox | axon

# The real directory, following the symlink oh-my-zsh's themes folder may hold.
typeset -g AXLE_ROOT="${${(%):-%x}:A:h}"

source "$AXLE_ROOT/lib/command.zsh"
source "$AXLE_ROOT/lib/common.zsh"
_axle_load_config

# Map any accepted spelling (nox, noxa, NoxA, axon, AxoN) to a variant file name.
_axle_resolve_variant() {
  case "${(L)1}" in
    ''|nox|noxa) REPLY=nox ;;
    axon)        REPLY=axon ;;
    *)           return 1 ;;
  esac
}

_axle_load_variant() {
  local variant REPLY
  if _axle_resolve_variant "$1"; then
    variant=$REPLY
  else
    print -u2 "axle: unknown variant '$1' (expected: nox, axon)"
    return 1
  fi
  source "$AXLE_ROOT/lib/common.zsh"
  _axle_unload                                   # the previous variant's hooks
  source "$AXLE_ROOT/benzene/$variant.zsh"
  source "$AXLE_ROOT/benzene/segments.zsh"       # your segments + drops
  source "$AXLE_ROOT/benzene/aistatus.zsh"       # AI status dots (expanded view)
  _axle_nemc_attach                              # MnemoCetus's state
  typeset -g AXLE_VARIANT="$variant"
}

# --- theme commands ---------------------------------------------------------------

_axle_cmd_variant() {
  if [[ -z $1 ]]; then print -r -- "$AXLE_VARIANT"; else _axle_load_variant "$1"; fi
}

_axle_cmd_refresh() {
  # Forget cached tool versions and config lookups, and re-measure icon width.
  (( ${+_axle_vcache} )) && _axle_vcache=()
  (( ${+_axle_cache} )) && _axle_cache=( cpus "${_axle_cache[cpus]}" )
  (( $+functions[_axle_measure_icons] )) && _axle_measure_icons force
  return 0
}

_axle_cmd_preview() {
  # In a subshell: the preview fakes state freely without touching this shell.
  ( source "$AXLE_ROOT/benzene/preview.zsh" "$@" )
}

_axle_cmd_tmux() {
  print -r -- "# Add to ~/.tmux.conf:  source-file $AXLE_ROOT/benzene/tmux.conf"
  print
  < "$AXLE_ROOT/benzene/tmux.conf"
}

_axle_cmd_debug()  { (( $+functions[_axle_debug] )) && _axle_debug }
_axle_cmd_ai()     { _axle_aistatus_report }
_axle_cmd_colors() { _axle_show_colors }

_axle_cmd_palette() {
  if [[ -z $1 ]]; then print -r -- "${AXLE_PALETTE:-mocha}"
  else AXLE_PALETTE=$1; _axle_load_palette; fi
}

_axle_cmd_segments() {
  local side
  for side in LEFT RIGHT; do
    local -a active=(${(P)${:-AXLE_NOX_$side}})
    (( ${#active} )) && print -r -- "${(L)side}: $active"
  done
  local -a names=(${(M)${(k)functions}:#_axle_seg_*})
  print -r -- available: ${(o)names#_axle_seg_}
}

axle_command variant   _axle_cmd_variant   theme 'variant [nox|axon]'   'show or switch the variant'
axle_command preview   _axle_cmd_preview   theme 'preview [--all]'      'view and test every state of the prompt'
axle_command palette   _axle_cmd_palette   theme 'palette [mocha|classic]' 'show or switch the colours'
axle_command colors    _axle_cmd_colors    theme 'colors'               'preview the colour roles'
axle_command segments  _axle_cmd_segments  theme 'segments'             'list active and available segments'
axle_command segment   _axle_segment_cmd   theme 'segment add|rm|ls'    'your own prompt segments'
axle_command ai        _axle_cmd_ai        theme 'ai'                   'status of the watched AI services'
axle_command tmux      _axle_cmd_tmux      theme 'tmux'                 'tmux settings for Benzene (+ a status bar)'
axle_command debug     _axle_cmd_debug     theme 'debug'                'what the layout measured'
axle_command refresh   _axle_cmd_refresh   theme 'refresh'              'clear cached versions; re-measure icons'

typeset -gi _axle_theme_loaded=1
_axle_load_variant "${AXLE_VARIANT:-nox}" || _axle_load_variant nox
