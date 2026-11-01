# Shared pieces used by every Axle variant.

zmodload zsh/datetime zsh/parameter 2>/dev/null
zmodload -F zsh/stat b:zstat 2>/dev/null
autoload -Uz add-zsh-hook

# The colour table Benzene fills in. Declared here too, so code that looks colours up with
# a default (${_axle_c[ok]:-green}) works when only the axle tool is loaded: without it,
# zsh would read [ok] as an arithmetic index into a plain array.
(( ${+_axle_c} )) || typeset -gA _axle_c

# Separator glyph used between prompt segments. Box-drawing │ (U+2502), not a pipe.
typeset -g AXLE_SEP='│'

# Print text with prompt escapes (%F{…}, %B, …) expanded. Use this, never `print -P`:
# with PROMPT_SUBST on (oh-my-zsh sets it), `print -P` also runs $(…) and `…` found in
# the text, and the text here often comes from outside (history, status pages, files).
#   _axle_printp [-n] <text>
_axle_printp() {
  if [[ $1 == -n ]]; then print -rn -- "${(%)2}"; else print -r -- "${(%)1}"; fi
}

# Exit status of the previous command, shown only when it failed.
_axle_status() {
  print -r -- "%(?..%F{${AXLE_COLOR_ERROR:-red}}✘ %?%f )"
}

# Undo whatever the previous variant registered, so variants can be switched live.
_axle_unload() {
  # Only the theme's own pieces, by name: the axle tool's hooks and widgets stay put.
  local cleanup
  for cleanup in _axle_variant_cleanup _axle_cleanup_aistatus; do
    (( $+functions[$cleanup] )) && { $cleanup; unfunction $cleanup }
  done
  add-zsh-hook -d precmd  _axle_precmd
  add-zsh-hook -d precmd  _axle_aistatus_precmd
  add-zsh-hook -d preexec _axle_preexec
  add-zsh-hook -d preexec _axle_direnv_reorder
  add-zsh-hook -d chpwd   _axle_chpwd
  if (( $+builtins[zle] )); then
    autoload -Uz add-zle-hook-widget
    add-zle-hook-widget -d keymap-select _axle_keymap_select 2>/dev/null
    add-zle-hook-widget -d line-init     _axle_line_init 2>/dev/null
  fi
  PROMPT='%# ' RPROMPT=''
}

# Format a duration in seconds (may be fractional) as 2.21s, 32s, 3m07s, 2h05m, 1d03h.
_axle_fmt_duration() {
  local -F secs=$1
  local -i s=$secs
  if   (( s >= 86400 )); then REPLY="$(( s / 86400 ))d${(l:2::0:)$(( s % 86400 / 3600 ))}h"
  elif (( s >= 3600 ));  then REPLY="$(( s / 3600 ))h${(l:2::0:)$(( s % 3600 / 60 ))}m"
  elif (( s >= 60 ));    then REPLY="$(( s / 60 ))m${(l:2::0:)$(( s % 60 ))}s"
  elif (( s >= 10 ));    then REPLY="${s}s"
  else                        printf -v REPLY '%.2fs' $secs
  fi
}
