# run: `axle run` runs this project, the one you name, or the last one you worked in.
#
#   axle run --dry-run       say which project, where its root is, and why
#   axle run <words>         the project j would pick for these words
#   axle run <path> | .      that folder's project
#
# Its code (modules/run/main.zsh) loads the first time you use it: nothing at startup.

_axle_lazy modules/run/main.zsh _axle_cmd_run _axle_run_pick _axle_run_last _axle_run_recent \
                                _axle_run_state_init _axle_run_hash
axle_command run _axle_cmd_run tool 'run [words|path] [--dry-run]' 'run this project, or go back to the last one'
