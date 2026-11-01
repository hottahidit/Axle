#!/usr/bin/env zsh
# Axle's test suite.
#
#   zsh tests/run.zsh            run everything
#   zsh tests/run.zsh git venv   run tests/test_git.zsh and tests/test_venv.zsh
#
# Each tests/test_*.zsh defines functions named test_*. Every test runs in a fresh zsh
# with its own throwaway HOME (and XDG folders), so nothing touches your real files.
emulate -L zsh
setopt extendedglob no_nomatch

typeset ROOT=${0:A:h:h}
typeset TMPROOT=$(mktemp -d "${${TMPDIR:-/tmp}%/}/axle-tests.XXXXXX")
trap 'rm -rf -- $TMPROOT' EXIT INT TERM

# A UTF-8 locale that exists here (macOS has en_US.UTF-8 but no C.UTF-8), so zsh counts
# characters like … and ▶ as one column, as in a real terminal.
typeset utf8=${LC_ALL:-${LANG:-}}
if [[ $utf8 != *(UTF-8|utf8)* ]] || ! (( ${${(f)"$(locale -a 2>/dev/null)"}[(I)$utf8]} )); then
  local -a have=(${(f)"$(locale -a 2>/dev/null)"})
  utf8=${have[(r)(C.UTF-8|C.utf8)]:-${have[(r)(en_US.UTF-8|en_US.utf8)]:-${have[(r)*.(UTF-8|utf8)]:-C.UTF-8}}}
fi

typeset -i pass=0 fail=0
typeset -a failed
typeset file t out
for file in $ROOT/tests/test_*.zsh; do
  (( $# )) && (( ! ${@[(Ie)${${file:t:r}#test_}]} )) && continue
  print -r -- "${${file:t:r}#test_}"
  for t in ${(f)"$(zsh -fc "source ${(q)file}; print -l \${(M)\${(ok)functions}:#test_*}")"}; do
    [[ -n $t ]] || continue
    local box=$TMPROOT/${file:t:r}-$t
    mkdir -p $box/home $box/work
    out=$(cd $box/work && env -i PATH=$PATH TERM=xterm-256color LANG=$utf8 \
            HOME=$box/home XDG_CONFIG_HOME=$box/home/.config XDG_DATA_HOME=$box/home/.local/share \
            XDG_CACHE_HOME=$box/home/.cache AXLE_TEST_ROOT=$ROOT T=$box/work COLUMNS=100 \
            zsh -f -c "source ${(q)ROOT}/tests/lib.zsh; source ${(q)file}; $t" 2>&1)
    if (( $? == 0 )); then
      (( pass++ )); print -r -- "  ok    ${t#test_}"
    else
      (( fail++ )); failed+=("${${file:t:r}#test_}: ${t#test_}")
      print -r -- "  FAIL  ${t#test_}"
      print -r -- "${out//$'\n'/$'\n'        }" | sed 's/^/        /' | head -25
      # On GitHub Actions, also as an annotation: shown on the run's page, and readable
      # without signing in (the logs aren't).
      if [[ $GITHUB_ACTIONS == true ]]; then
        local msg=${out[1,1500]//\%/%25}
        msg=${${msg//$'\r'/%0D}//$'\n'/%0A}
        print -r -- "::error title=${${file:t:r}#test_}: ${t#test_}::$msg"
      fi
    fi
  done
done

print
if (( fail )); then
  print -r -- "$pass passed, $fail failed:"; print -rl -- "  "${^failed}
  exit 1
fi
print -r -- "all $pass tests passed"
