# axle top: the system live, with btop (https://github.com/aristocratos/btop).
#
#   axle top              Axle's btop: btop 1.4.8 with an Axle mode (key A shows only the
#                         processes `axle run` started); built from vendor/btop by install.sh
#                         or `axle top --build`. Not built: the btop you have installed (no
#                         Axle mode). Neither: how to get one.
#   axle top --build      build Axle's btop (needs make and g++ 14+ or clang 19+)
#   axle top <options>    btop's options (axle top -p 1)
#
# btop reads its usual settings (~/.config/btop); the Axle mode isn't saved in them.
# `axle run top` opens Axle's btop in the Axle mode.

# Axle's btop, if it's built (REPLY). (_axle_top_bin: another one, for the tests.)
_axle_top_btop() { REPLY=${_axle_top_bin:-$AXLE_ROOT/vendor/btop/bin/btop}; [[ -x $REPLY ]] }

# Where axle run keeps its services (REPLY): btop reads each one's pid there.
_axle_top_services() { REPLY=${XDG_STATE_HOME:-$HOME/.local/state}/axle/run/services }

_axle_cmd_top() {
  local REPLY
  [[ $1 == --load-only ]] && return 0             # (loads this file)
  if [[ $1 == --build ]]; then
    command zsh -f $AXLE_ROOT/tools/axle-build-btop
    return
  fi
  if _axle_top_btop; then
    local btop=$REPLY
    _axle_top_services
    command $btop --axle-dir $REPLY "$@"
    return
  fi
  if (( $+commands[btop] )); then
    command btop "$@"
    return
  fi
  local how
  if   [[ $OSTYPE == darwin* ]] && (( $+commands[brew] )); then how='brew install btop'
  elif (( $+commands[apt] ));    then how='sudo apt install btop'
  elif (( $+commands[dnf] ));    then how='sudo dnf install btop'
  elif (( $+commands[pacman] )); then how='sudo pacman -S btop'
  elif (( $+commands[zypper] )); then how='sudo zypper install btop'
  elif (( $+commands[apk] ));    then how='sudo apk add btop'
  elif (( $+commands[snap] ));   then how='sudo snap install btop'
  else how='see https://github.com/aristocratos/btop#installation'
  fi
  _axle_printp "%F{${_axle_c[error]:-red}}✘%f axle top runs %Bbtop%b, and there's none here." >&2
  _axle_printp "  Build Axle's (with the Axle mode): %Baxle top --build%b   %F{${_axle_c[muted]:-244}}(needs g++ 14+ or clang 19+)%f" >&2
  _axle_printp "  or install btop: %B${how//\%/%%}%b" >&2
  return 127
}
