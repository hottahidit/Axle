#!/usr/bin/env zsh
# Install Axle: the axle tool, the Benzene prompt, or both.
#
#   ./install.sh                 asks which
#   ./install.sh --both | --tool | --theme
#   options:  --plain           plain zsh / a plugin manager, even if oh-my-zsh is installed
#             --yes             don't ask before removing the unused part (non-git copies)
#             --keep            keep the unused part's files
#             --no-configure    don't start `axle configure` afterwards
#
# With oh-my-zsh it links what you chose into $ZSH_CUSTOM; otherwise it prints the lines for
# ~/.zshrc. It never edits ~/.zshrc. If you choose only one part, the other's files are
# removed: in a git clone through sparse checkout, so `axle update` keeps working and
# choosing "both" later brings them back. It won't remove files with uncommitted changes.
# If the tool is included, the setup wizard (`axle configure`) runs at the end.
emulate -L zsh
setopt no_nomatch

repo="${0:A:h}"
omz="${ZSH:-$HOME/.oh-my-zsh}"
custom="${ZSH_CUSTOM:-$omz/custom}"
choice='' plain=0 yes=0 keep=0 configure=1

for arg in "$@"; do
  case $arg in
    --both|--tool|--theme) choice=${arg#--} ;;
    --plain)        plain=1 ;;
    --yes)          yes=1 ;;
    --keep)         keep=1 ;;
    --no-configure) configure=0 ;;
    -h|--help)      sed -n '2,17s/^# \{0,1\}//p' $0; exit 0 ;;
    *)              print -u2 "install.sh: unknown option $arg (see --help)"; exit 2 ;;
  esac
done

# --- what to install ---------------------------------------------------------------

if [[ -z $choice ]]; then
  if [[ ! -t 0 ]]; then
    print -u2 "install.sh: not a terminal; pass --both, --tool or --theme"; exit 2
  fi
  print "What would you like to install?"
  print "  1) Both: the axle tool and the Benzene prompt (recommended)"
  print "  2) Only the axle tool (keep your current prompt)"
  print "  3) Only the Benzene prompt"
  print -n "Choose 1-3 [1]: "
  read -r answer || exit 1
  case ${answer:-1} in
    1) choice=both ;; 2) choice=tool ;; 3) choice=theme ;;
    *) print -u2 "install.sh: choose 1, 2 or 3"; exit 2 ;;
  esac
fi
want_tool=0 want_theme=0
[[ $choice == (both|tool) ]]  && want_tool=1
[[ $choice == (both|theme) ]] && want_theme=1

# --- the other part's files ------------------------------------------------------------

tool_paths=(axle.plugin.zsh core modules tools)
theme_paths=(benzene.zsh-theme benzene)
unused=()
(( want_tool ))  || unused+=($tool_paths)
(( want_theme )) || unused+=($theme_paths)

is_git=0 has_head=0
if command git -C $repo rev-parse --git-dir >/dev/null 2>&1; then
  is_git=1
  command git -C $repo rev-parse --verify -q HEAD >/dev/null && has_head=1
fi

if (( is_git && has_head )) && [[ $(command git -C $repo sparse-checkout list 2>/dev/null) == *'!/'* ]] &&
   (( ${#unused} == 0 || keep )); then
  # Everything (again): bring back whatever an earlier install removed.
  command git -C $repo sparse-checkout disable && print "Restored all of Axle's files."
fi

if (( ${#unused} && ! keep )); then
  present=()
  for p in $unused; do [[ -e $repo/$p ]] && present+=($p); done
  if (( ${#present} )); then
    if (( is_git && ! has_head )); then
      print "Not removing ${(j:, :)present}: this checkout has no commits yet, so they may be your only copy."
    elif (( is_git )); then
      dirty=$(command git -C $repo status --porcelain -- $present)
      if [[ -n $dirty ]]; then
        print "Not removing ${(j:, :)present}: they have uncommitted changes:"
        print -r -- "${dirty//$'\n'/$'\n'  }" | sed 's/^/  /'
      else
        patterns=('/*')
        for p in $unused; do [[ -d $repo/$p || $p != *.* ]] && patterns+=("!/$p/") || patterns+=("!/$p"); done
        command git -C $repo sparse-checkout set --no-cone $patterns
        print "Removed the unused files (${(j:, :)present}) through git sparse checkout;"
        print "  \`axle update\` still works, and \`./install.sh --both\` brings them back."
      fi
    else
      ok=$yes
      if (( ! ok )) && [[ -t 0 ]]; then
        print -n "Delete the unused files (${(j:, :)present}) from $repo? [y/N] "
        read -r answer && [[ $answer == [yY]* ]] && ok=1
      fi
      if (( ok )); then
        for p in $present; do rm -rf -- $repo/$p; done
        print "Deleted ${(j:, :)present}. (To add them later, download Axle again.)"
      else
        print "Kept ${(j:, :)present}."
      fi
    fi
  fi
fi

# --- hooking it into zsh ---------------------------------------------------------------

link() {   # link <target> <link name>, replacing only links we own
  if [[ -e $2 && ! -L $2 ]]; then
    print -u2 "  $2 exists and isn't a link; leaving it alone"
    return 0
  fi
  ln -sfn $1 $2
}
unlink_ours() { [[ -L $1 && ${1:A} == $repo* ]] && rm -f -- $1 }

print
if (( ! plain )) && [[ -d $omz ]]; then
  mkdir -p $custom/plugins $custom/themes
  if (( want_tool )); then link $repo $custom/plugins/axle; else unlink_ours $custom/plugins/axle; fi
  if (( want_theme )); then link $repo/benzene.zsh-theme $custom/themes/benzene.zsh-theme
  else unlink_ours $custom/themes/benzene.zsh-theme; fi
  link $repo/axle.zsh-theme $custom/themes/axle.zsh-theme     # the old name; loads what's installed
  print "Linked into ${custom/#$HOME/~}. In ~/.zshrc, before \`source \$ZSH/oh-my-zsh.sh\`:"
  (( want_tool ))  && print '  plugins=(... axle)          # the axle tool'
  (( want_theme )) && print '  ZSH_THEME="benzene"         # the Benzene prompt'
else
  print "Add to ~/.zshrc:"
  if (( want_tool )); then
    (( want_theme )) && print "  AXLE_THEME=benzene                 # also load the Benzene prompt"
    print "  source ${repo/#$HOME/~}/axle.plugin.zsh"
  else
    print "  source ${repo/#$HOME/~}/benzene.zsh-theme"
  fi
fi

# Precompile to zsh bytecode, so shells load it about twice as fast (*.zwc, ignored by git).
zsh -f -c "AXLE_ROOT=${(q)repo}; source ${(q)repo}/lib/command.zsh; _axle_compile" 2>/dev/null

# --- set it up -------------------------------------------------------------------------

if (( want_tool && configure )); then
  if [[ -t 0 && -t 1 ]]; then
    print
    print -n "Press Enter to start the setup wizard (or Ctrl-C to skip it)... "
    read -r _ || exit 0
    # A clean zsh with just Axle loaded, so the wizard previews and saves your choices.
    AXLE_THEME=${${want_theme:#0}:+benzene} zsh -f -c "
      setopt prompt_subst
      source ${(q)repo}/axle.plugin.zsh
      axle configure" || print "Nothing saved; run \`axle configure\` any time."
  else
    print "Run \`axle configure\` in a new shell to set it up."
  fi
elif (( want_theme )); then
  print
  print 'Open a new shell, then try `axle configure` and `axle preview`.'
fi
print
print 'Then open a new shell. `axle doctor` checks the setup.'
