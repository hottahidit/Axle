# The old name, kept so existing `ZSH_THEME="axle"` setups keep working: it loads whichever
# of the axle tool and the Benzene prompt are installed. For new setups use them directly:
#   plugins=(... axle)      the axle tool
#   ZSH_THEME="benzene"     the Benzene prompt
() {
  local root="${${(%):-%x}:A:h}"
  [[ -r $root/axle.plugin.zsh ]]   && source "$root/axle.plugin.zsh"
  [[ -r $root/benzene.zsh-theme ]] && source "$root/benzene.zsh-theme"
}
