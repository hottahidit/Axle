# Changelog

## nemc compat 0.1.3 (branch `MnemoCetus`)

- Tests: the wizard test sends one key per fully drawn screen, so a slow machine (macOS CI)
  no longer gets a key meant for one step on the next.

## nemc compat 0.1.2 (branch `MnemoCetus`)

- `axle configure` asks whether to show MnemoCetus in the prompt, with a live preview, when nemc
  is installed.
- `axle preview` has `nemc-security`, `nemc-changed` and `nemc-clean`.

## nemc compat 0.1.1 (branch `MnemoCetus`)

- A compat-only update now says so, instead of "axle 0.2.3 is out (you have 0.2.3)".
- The README opens with why this branch exists.

## nemc compat 0.1.0 (branch `MnemoCetus`)

Axle's long-lived branch for working with MnemoCetus (a separate project). It follows `main`
and adds (plan: `docs/nemc/ROADMAP.md`):

- `axle nemc [command]`: nemc as a tool of axle, with help and Tab completion.
- A Benzene segment with this folder's state: a red bubble with the number of findings (also
  in AxoN), an amber dot if it changed since the last scan, a green dot when expanded. It's
  read in the background, so the prompt never waits on nemc. nemc's own light stands down.
- `install.sh` asks about MnemoCetus first (`--nemc`, `--no-nemc`): it installs nemc with uv or
  pipx and moves the checkout to this branch, which `axle update` then follows.
- `axle doctor` reports it. `AXLE_NEMC=0` turns it off; `AXLE_NEMC_TTL` sets how often it reads.
## 0.2.4

- Experimental: `install.sh` asks about MnemoCetus first (`--nemc`, `--no-nemc`). Choosing it installs `nemc`
  with uv or pipx and moves the checkout to Axle's `MnemoCetus` branch, which adds `axle nemc`
  and the folder's state in the Benzene prompt. `axle update` then follows that branch.

## 0.2.3

- Tests: the `fix` test no longer expects a case correction on case-insensitive disks
  (macOS), where `readme.md` already opens `README.md`.

## 0.2.2

Three new modules, on by default and switchable in `axle configure`:
- **highlight**: syntax highlighting as you type (like zsh-syntax-highlighting): green
  commands, red ones that don't exist, coloured options, strings, variables, globs,
  operators and comments, underlined paths; about 0.3 ms a keystroke.
- **upsearch**: type part of a command, then ↑/↓ walks through the history lines containing
  it, with the match highlighted (like zsh-history-substring-search).
- **fix**: `fix` or Esc Esc puts the corrected last command on the line: command and git
  subcommand typos, misspelled files and folders, `git push` without an upstream, a script
  that isn't executable, and `sudo` for commands that need it (like thefuck and oh-my-zsh's
  sudo plugin). Esc Esc on a typed line adds or removes `sudo`.

If your module list was an earlier version's complete default, the new modules join it.

## 0.2.1

**Faster loading: about 3 ms instead of 10–15 ms** (both parts; in a real interactive shell,
Axle now adds about 10 ms instead of 40–80 ms before the first prompt)
- Compiled to zsh bytecode (`*.zwc`): by `install.sh` and `axle update`, and in the
  background when a shell finds a file missing or out of date (and after a zsh upgrade).
- Help pages, the settings table, Tab completion, the questions, `update`/`uninstall` and
  the tool's longer commands load on first use.
- No subprocesses at startup: key bindings, the variant and the CPU count were each read
  through one; `lib/command.zsh` is read once instead of by both parts.
- `axle doctor` says whether Axle is compiled.
- Fixed: `axle config get` returned an error status for settings not in the config file.

## 0.2.0

**The `axle` command**
- Tab completion for every command and what it takes: variants, palettes, modules, segments,
  preview scenarios, hook events, drops, settings and their values.
- `axle help <command>` / `axle <command> --help`: options and examples for each command.
- Typos get "did you mean": `axle statz` → `axle stats`.
- `axle config`: list, get, set, unset and edit settings, with values checked and applied at
  once; with no name, menus to pick a setting and a value.
- `axle update --check`, and a once-a-day background check that mentions a new version at
  the next prompt (`AXLE_UPDATE_CHECK=0` turns it off). `axle update` shows the changelog.
- `axle uninstall`: removes the links and, if you choose, settings, history and cache;
  never edits `~/.zshrc`.
- Arrow-key questions (like questionary, in plain zsh) in `axle configure`, `axle config`
  and `axle uninstall`; the wizard's preview follows the highlighted option.

## 0.1.5

- Tests: the live suggestion-list test keeps reading the shell's output, which otherwise
  fills macOS's small terminal buffer and stops the shell.

## 0.1.4

- Tests: the live suggestion-list test waits for each step instead of fixed delays (it
  failed on slower machines such as CI's macOS runners).

## 0.1.3

- macOS: the Haskell (stack) segment used a `sed` feature macOS doesn't have.
- macOS: the tests and `axle preview` now handle a temp folder ending in `/`, and the tests
  pick a UTF-8 locale that exists (macOS has no `C.UTF-8`).
- CI: failures are shown as annotations on the run's page; `actions/checkout@v5`.
- README: a broken table row, a duplicated setting, the preview scenario count.

## 0.1.2

**Tests and CI**
- A test suite (`zsh tests/run.zsh`), each test in a throwaway HOME, and CI on Linux and macOS.
- `axle version`.
- Fixed: with only the tool loaded, `axle history`, `stats`, `doctor`, the Ctrl-R picker and
  venv messages failed on colour lookups.
- Fixed: a tool's own pin file (`.nvmrc`) beats `.tool-versions` in the same folder, and a
  pin like `lts/iron` means "unknown" rather than a version from further up.

**Suggestions now work like zsh-autosuggestions**
- Only the inline grey suggestion shows as you type; Ctrl-N (or Shift-↓) opens the list of
  alternatives on demand, and typing closes it.
- Strategies, in order: `smart` (Axle's ranking), `history` (newest first), and `completion`
  (command names, then real file and folder paths): `AXLE_SUGGEST_STRATEGY`.
- New settings `AXLE_SUGGEST_STYLE`, `AXLE_SUGGEST_IGNORE`, `AXLE_SUGGEST_MAX_BUFFER`.
- Widgets for your own bindings: `axle-suggest-accept`, `-execute`, `-partial`, `-clear`,
  `-toggle`, `-next`, `-prev`.
- vi mode accepts with `l`, `$`, `A` (whole) and `w`, `e`, `W`, `E` (one word).
- No suggestion while moving through history, until you edit the line.

**More Benzene segments** (each shows only when it has something to say)
- `inside`: a shell started from ranger, yazi, nnn, lf, xplr, vim/neovim, mc or chezmoi.
- `direnv`: a loaded `.envrc`, and an amber bubble for one direnv hasn't been allowed to load.
- Ruby, Java, PHP, Lua, Perl, Scala, Flutter (fvm) and Haskell (stack), with pins from their
  version files and `.tool-versions`; versions a manager (rbenv, jenv, phpenv, luaenv, plenv,
  scalaenv, asdf, mise, fvm) hasn't installed are flagged.
- Azure subscription, Elastic Beanstalk environment, Google credentials (production = alarm).
- timewarrior, taskwarrior (overdue), todo.txt, NordVPN, vi mode (`NORMAL`), per-directory
  history mode; toolbox/distrobox containers by name.
- Fixed: language versions behind asdf/mise shims were cached across folders.

## 0.1.0 (first public beta)

The first release: **Axle**, a toolkit for zsh, and **Benzene**, its prompt theme. Either works
on its own; together they make each other better. Expect rough edges, and please report them.

**Benzene, the prompt**
- Two variants: NoxA (two lines, shows what's relevant, Alt-i expands to everything) and AxoN
  (one quiet line, only what needs attention).
- Background git status (branch, ahead/behind, staged/modified/untracked, stashes, rebase and
  merge progress, signature badge, push protocol), run time and exit codes, sudo countdown,
  battery, memory pressure, Windows-drive warning (WSL), venv and toolchain-version warnings.
- Alarm bubbles for what's genuinely wrong (failed command, root, production contexts, low
  battery, conflicts), never trimmed when space runs out.
- Compact past prompts, shell-integration marks, clickable path and branch, a VS Code layout,
  Catppuccin Mocha colours, AI service status dots.
- `axle preview` to see every state; your own segments and "drops" from any program.

**axle, the tool**
- One history log (command, folder, exit code, run time) powering:
  smart suggestions with a list of likely options, `j` to jump to folders, a Ctrl-R picker,
  and `axle stats`.
- Automatic project venvs (without running their activate scripts).
- `axle doctor`, `axle update`, `axle module`, hooks, and `axle configure` for both parts.
- `install.sh` installs the tool, the prompt or both, and removes what you don't use.
