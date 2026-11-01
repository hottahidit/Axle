# Changelog

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
