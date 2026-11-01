# axle — tools for your zsh: smart suggestions, jump, history search, automatic venvs,
# stats, doctor and update, plus hooks and drops to build your own. It pairs with the
# Benzene prompt (benzene.zsh-theme) and works under any other prompt too.
#
#   oh-my-zsh   clone into $ZSH_CUSTOM/plugins/axle, then plugins=(... axle)
#   zinit       zinit light hottahidit/axle        antidote   hottahidit/axle
#   plain zsh   source /path/to/axle/axle.plugin.zsh
#
# Modules (all on by default; choose with AXLE_MODULES=(...) or `axle module`):
#   suggest    grey suggestions as you type (Ctrl-N lists the alternatives)
#   highlight  syntax highlighting as you type
#   upsearch   ↑/↓ search history for what you've typed
#   jump       `j <words>`: cd to the folder you most likely mean
#   search     Ctrl-R: a history picker (filter by this folder, by success)
#   env        activate a project's venv when you cd in, deactivate when you leave
#   fix        `fix` / Esc Esc: correct the last command (typos, sudo)
#   run        `axle run`: run this project, or go back to the last one (off by default)
#
# Without oh-my-zsh, AXLE_THEME=benzene loads the Benzene prompt as well.

typeset -g AXLE_ROOT="${${(%):-%x}:A:h}"

source "$AXLE_ROOT/lib/command.zsh"
source "$AXLE_ROOT/lib/common.zsh"
_axle_load_config
source "$AXLE_ROOT/core/events.zsh"
# The tool's commands; their code (core/commands.zsh) loads when first used.
_axle_lazy core/commands.zsh _axle_cmd_history _axle_cmd_stats _axle_cmd_doctor _axle_cmd_module _axle_cmd_drop
axle_command history _axle_cmd_history tool 'history [n]'          'recent commands: when, outcome, time, folder'
axle_command stats   _axle_cmd_stats   tool 'stats [--here] [--days N]' 'what you run, what is slow, what fails'
axle_command doctor  _axle_cmd_doctor  tool 'doctor'               'check the setup'
axle_command module  _axle_cmd_module  tool 'module [on|off <name>]'  'list modules, or switch one on or off'
axle_command hook    _axle_hook_cmd    tool 'hook <event> <fn>'    'run a function on shell events'
axle_command drop    _axle_cmd_drop    tool 'drop <name> <text>'   'a tab in every prompt, from any program'
# Folder ranking from the history log (j, axle run).
_axle_lazy lib/rank.zsh _axle_jump_load _axle_jump_rank

() {
  # Default modules. A list that's just an earlier version's default is upgraded, so
  # `axle reload` picks up new modules; a list you set yourself is left alone.
  local -a defaults=(suggest highlight upsearch jump search env fix)
  # (Earlier versions' complete lists count as "everything", so new modules join them.)
  if (( ! ${+AXLE_MODULES} )) ||
     [[ "$AXLE_MODULES" == (aistatus|aistatus suggest|suggest jump search env|$_axle_auto_modules) ]]; then
    typeset -ga AXLE_MODULES=($defaults)
    typeset -g _axle_auto_modules="$defaults"
  fi
  local module
  for module in $AXLE_MODULES; do
    [[ $module == aistatus ]] && continue        # (now part of the Benzene theme)
    if [[ -r $AXLE_ROOT/modules/$module.zsh ]]; then
      source "$AXLE_ROOT/modules/$module.zsh"
    else
      print -u2 "axle: no module '$module' (available: ${${(@)${:-$AXLE_ROOT/modules/*.zsh(N)}:t:r}})"
    fi
  done
}

# The tool's hooks run first, so a hook can feed a prompt segment before it's drawn.
precmd_functions=(_axt_precmd ${precmd_functions:#_axt_precmd})

typeset -gi _axle_tool_loaded=1

# Benzene as a plugin of axle (oh-my-zsh users set ZSH_THEME="benzene" instead).
if [[ ${AXLE_THEME:-} == benzene ]] && (( ! ${_axle_theme_loaded:-0} )); then
  source "$AXLE_ROOT/benzene.zsh-theme"
fi
