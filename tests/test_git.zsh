# The background git worker.

_git_state() {   # REPLY = the summary as shown
  local -a part=("${(@ps:\x1f:)$(_axle_git_compute)}")
  plain "$part[1]"
}

test_clean_dirty_staged() {
  load_theme
  mkrepo $T/r && cd $T/r
  _git_state; assert_eq "$REPLY" "main" "clean"
  print a > f; _git_state; assert_eq "$REPLY" "main ?1" "untracked"
  command git add f; _git_state; assert_eq "$REPLY" "main +1" "staged"
  print b > g; _git_state; assert_eq "$REPLY" "main +1 ?1" "staged and untracked"
}

test_ahead_behind_stash() {
  load_theme
  command git init -q --bare -b main $T/origin.git
  command git clone -q $T/origin.git $T/a 2>/dev/null
  command git -C $T/a commit -q --allow-empty -m base && command git -C $T/a push -q origin main 2>/dev/null
  command git clone -q $T/origin.git $T/b 2>/dev/null
  command git -C $T/b commit -q --allow-empty -m theirs && command git -C $T/b push -q origin main 2>/dev/null
  cd $T/a && command git fetch -q
  command git commit -q --allow-empty -m mine1 && command git commit -q --allow-empty -m mine2
  print x > s && command git add s && command git stash -q
  _git_state
  assert_eq "$REPLY" "main ⇡2 ⇣1 *1 🌐local"
}

test_rebase_conflict_and_detached() {
  load_theme
  mkrepo $T/r && cd $T/r
  print 1 > f && command git add f && command git commit -qm one
  command git checkout -q -b feature/x HEAD~1 && print 2 > f && command git add f && command git commit -qm two
  command git rebase main >/dev/null 2>&1
  _git_state
  assert_match "$REPLY" 'feature/x REBASE 1/1 =1*' "mid-rebase on the branch being rebased"
  command git rebase --abort
  command git tag v1.0 && command git checkout -q --detach
  _git_state
  assert_match "$REPLY" '@[0-9a-f]## \(v1.0\)' "detached at a tag"
}

test_raw_flags_for_axon() {
  load_theme
  mkrepo $T/r && cd $T/r && print a > f && command git add f && print b > g
  local -a part=("${(@ps:\x1f:)$(_axle_git_compute)}")
  assert_match "$part[3]" 'branch=main *unstaged=1 staged=1 *' "raw flags"
}
