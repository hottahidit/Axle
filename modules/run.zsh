# run: `axle run` runs this project, the one you name, or the last one you worked in.
#
#   axle run                 this project; elsewhere, go back to the last one and run it
#   axle run <words>         the project j would pick for these words
#   axle run <path> | .      that folder's project
#   axle run --dry-run       say what would run, and why       --yes  don't ask
#   axle run ls · stop [name|all] · restart · logs [-f] · open     the background services
#   axle run set [key value] · forget · --profile <name>             your settings
#
# Its code (modules/run/main.zsh) loads the first time you use it: nothing at startup.

_axle_lazy modules/run/main.zsh _axle_cmd_run _axle_run_pick _axle_run_last _axle_run_recent \
                                _axle_run_state_init _axle_run_hash _axle_run_trust_key \
                                _axle_run_trusted _axle_run_show _axle_run_choose_venv
_axle_lazy modules/run/service.zsh _axle_run_get _axle_run_put _axle_run_drop _axle_run_start _axle_run_bg _axle_run_ls _axle_run_stop \
                                   _axle_run_restart _axle_run_logs _axle_run_open _axle_run_name \
                                   _axle_run_alive _axle_run_envfile _axle_run_services _axle_run_stop_one _axle_run_mine \
                                   _axle_run_port_up _axle_run_bounded _axle_run_enter_venv _axle_run_dotenv
_axle_lazy modules/run/ports.zsh _axle_run_port_holder _axle_run_port_service _axle_run_free_port \
                                 _axle_run_apply_port _axle_run_resolve_port
_axle_lazy modules/run/parts.zsh _axle_run_parts _axle_run_partname _axle_run_choice_load \
                                 _axle_run_choice_save _axle_run_choose _axle_run_tmux _axle_run_tmux_show \
                                 _axle_run_have_tmux
_axle_lazy modules/run/yours.zsh _axle_run_set_cmd _axle_run_forget_project _axle_run_profile_use \
                                 _axle_run_yours_files _axle_run_yours_apply _axle_run_yours_get \
                                 _axle_run_yours_load _axle_run_yours_put _axle_run_hooked \
                                 _axle_run_watch_add _axle_run_watch_check _axle_run_watch_stopped
_axle_lazy modules/run/detect.zsh _axle_run_detect _axle_run_read _axle_run_code_port
axle_command run _axle_cmd_run tool 'run [words|path] | ls | stop | logs | set' 'run this project, or go back to the last one'
