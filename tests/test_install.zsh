# install.sh: choosing parts, removing the rest safely.

# A committed clone of the current tree: _clone <dir>
_clone() {
  mkdir -p $T/src
  (cd $ROOT && command git ls-files -co --exclude-standard) | while read -r f; do
    mkdir -p $T/src/${f:h}; cp -p $ROOT/$f $T/src/$f
  done
  (cd $T/src && command git init -q -b main && command git add -A && command git commit -qm axle)
  command git clone -q $T/src $1
}

_install() {   # _install <dir> <args...>
  local d=$1; shift
  (cd $d && ZSH=$T/omz ZSH_CUSTOM=$T/omz/custom zsh -f ./install.sh "$@" --no-configure) 2>&1
}

test_tool_only_then_both() {
  mkdir -p $T/omz/custom
  _clone $T/c
  _install $T/c --tool >/dev/null
  [[ ! -e $T/c/benzene && ! -e $T/c/benzene.zsh-theme ]] || fail "theme files removed"
  [[ -e $T/c/axle.plugin.zsh ]] || fail "tool kept"
  [[ -L $T/omz/custom/plugins/axle && ! -e $T/omz/custom/themes/benzene.zsh-theme ]] || fail "links"
  [[ -z $(command git -C $T/c status --porcelain) ]] || fail "git status stays clean"
  _install $T/c --both >/dev/null
  [[ -e $T/c/benzene.zsh-theme ]] || fail "--both brings the theme back"
}

test_refuses_to_remove_uncommitted_work() {
  mkdir -p $T/omz/custom
  _clone $T/c
  print '# edit' >> $T/c/benzene/nox.zsh
  local out=$(_install $T/c --tool)
  assert_match "$out" '*Not removing*uncommitted*' "explains"
  [[ -e $T/c/benzene/nox.zsh ]] || fail "the edited file is still there"
}

test_refuses_in_a_checkout_without_commits() {
  mkdir -p $T/omz/custom
  _clone $T/c
  rm -rf $T/c/.git && command git init -q $T/c
  local out=$(_install $T/c --theme)
  assert_match "$out" '*no commits yet*' "explains"
  [[ -e $T/c/core ]] || fail "nothing removed"
}

test_plain_copy_deletes_with_yes() {
  mkdir -p $T/omz/custom
  _clone $T/c
  rm -rf $T/c/.git
  _install $T/c --theme --yes >/dev/null
  [[ ! -e $T/c/core && -e $T/c/benzene.zsh-theme ]] || fail "tool files deleted, theme kept"
}

test_nemc_moves_to_its_branch() {
  mkdir -p $T/omz/custom $T/bin
  _clone $T/c
  command git -C $T/src branch MnemoCetus
  print -r -- $'#!/bin/sh\nprintf \'#!/bin/sh\\n\' > '"$T"$'/bin/nemc\nchmod +x '"$T"$'/bin/nemc' > $T/bin/uv
  chmod +x $T/bin/uv
  (cd $T/c && PATH=$T/bin:$PATH ZSH=$T/omz ZSH_CUSTOM=$T/omz/custom zsh -f ./install.sh --nemc --both --no-configure) >/dev/null 2>&1
  assert_eq "$(command git -C $T/c symbolic-ref --short HEAD)" MnemoCetus "on the MnemoCetus branch"
  assert_eq "$(command git -C $T/c rev-parse --abbrev-ref '@{u}')" origin/MnemoCetus "axle update follows it"
}

test_no_nemc_stays_on_this_branch() {
  mkdir -p $T/omz/custom
  _clone $T/c
  command git -C $T/src branch MnemoCetus
  _install $T/c --no-nemc --both >/dev/null
  assert_eq "$(command git -C $T/c symbolic-ref --short HEAD)" main "still on main"
}
