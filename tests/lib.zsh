# Helpers for Axle's tests (sourced by tests/run.zsh into each test's own zsh).

# (No `setopt extendedglob` here: tests run under zsh's default options, like a real shell.
# Helpers that need it set it for themselves.)
zmodload zsh/datetime
typeset -g ROOT=$AXLE_TEST_ROOT
export AXLE_MARKS=0                       # no shell-integration escapes in captured output
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export TMUX_TMPDIR=$T TMUX=''              # a tmux server of the test's own, never yours
export AXLE_RUN_DEBUG=1                   # axle run's supervisors keep a trace (for failures)
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

fail() { print -r -- "  $*"; exit 1 }

# assert_eq <actual> <expected> [what]
assert_eq() {
  [[ $1 == "$2" ]] && return 0
  print -r -- "  ${3:-values differ}"
  print -r -- "    expected: ${(q+)2}"
  print -r -- "    got:      ${(q+)1}"
  exit 1
}

# assert_match <actual> <pattern> [what]
assert_match() {
  setopt localoptions extendedglob
  [[ $1 == ${~2} ]] && return 0
  print -r -- "  ${3:-no match}"
  print -r -- "    pattern: $2"
  print -r -- "    got:     ${(q+)1}"
  exit 1
}

# assert_contains <actual> <literal text> [what]
assert_contains() {
  [[ $1 == *"$2"* ]] && return 0
  print -r -- "  ${3:-text not found}"
  print -r -- "    looking for: ${(q+)2}"
  print -r -- "    in:          ${(q+)1}"
  exit 1
}

assert_not_match() {
  setopt localoptions extendedglob
  [[ $1 != ${~2} ]] && return 0
  print -r -- "  ${3:-unexpected match}"
  print -r -- "    pattern: $2"
  print -r -- "    got:     ${(q+)1}"
  exit 1
}

# Text without its colours (REPLY).
nocolor() {
  setopt localoptions extendedglob
  REPLY=${1//$'\e'\[[0-9;]#m/}
}

# Prompt text as it appears on screen: prompt escapes expanded, colours and links removed.
plain() {
  setopt localoptions extendedglob
  local o=${(S)1//\%\{*\%\}/}
  o=${(%)o}
  o=${o//$'\e'\[[0-9;]#m/}
  REPLY=$o
}

load_theme() { source $ROOT/benzene.zsh-theme >/dev/null 2>&1 }
load_tool()  { source $ROOT/axle.plugin.zsh >/dev/null 2>&1 }

# A git repository with one commit: mkrepo <dir>
mkrepo() {
  command git init -q -b main $1 && command git -C $1 commit -q --allow-empty -m init
}
