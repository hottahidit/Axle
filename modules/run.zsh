# run: `axle run` runs this project, the one you name, or the last one you worked in.
#
#   axle run                 this project; elsewhere, go back to the last one and run it
#   axle run <words>         the project j would pick for these words
#   axle run <path> | .      that folder's project
#   axle run --dry-run       say what would run, and why       --yes  don't ask
#
# Its code (modules/run/main.zsh) loads the first time you use it: nothing at startup.

_axle_lazy modules/run/main.zsh _axle_cmd_run _axle_run_pick _axle_run_last _axle_run_recent \
                                _axle_run_state_init _axle_run_hash _axle_run_trust_key \
                                _axle_run_trusted _axle_run_show
_axle_lazy modules/run/detect.zsh _axle_run_detect _axle_run_read _axle_run_code_port
axle_command run _axle_cmd_run tool 'run [words|path] [-n] [-y]' 'run this project, or go back to the last one'
