# Axle

**Axle** is a toolkit for zsh: smart suggestions as you type, `j` to jump to the folder you mean,
a Ctrl-R history picker, automatic virtualenvs, command stats, a health check, and hooks and
"drops" to build your own. It comes with **Benzene**, a prompt theme whose two variants, NoxA and
AxoN, are the two halves of one ring (like the benzene molecule, it reads the same from both ends).

The two are separate: Benzene works on its own in any zsh, and the axle tool works under any
prompt. Together, each makes the other better.

## Contents

- [Install](#install)
- [The axle command](#the-axle-command)
  - [Settings: axle config](#settings-axle-config)
  - [Updates and uninstalling](#updates-and-uninstalling)
- [Benzene, the prompt](#benzene-the-prompt)
  - [NoxA (nox)](#noxa-nox)
  - [AxoN (axon)](#axon-axon)
  - [Setup wizard](#setup-wizard)
  - [Previewing every state](#previewing-every-state)
  - [tmux](#tmux)
  - [Switching variants at runtime](#switching-variants-at-runtime)
- [axle, the tool](#axle-the-tool)
  - [suggest: smart autosuggestions](#suggest-smart-autosuggestions)
  - [highlight](#highlight)
  - [upsearch](#upsearch)
  - [fix](#fix)
  - [jump](#jump)
  - [search](#search)
  - [env](#env)
  - [history, stats, doctor, update](#history-stats-doctor-update)
  - [Extending: segments, hooks, drops](#extending-segments-hooks-drops)
- [Project](#project)
  - [Development](#development)
  - [License](#license)
  - [Layout](#layout)

## Install

```zsh
git clone https://github.com/hottahidit/axle ~/repos/axle
~/repos/axle/install.sh
```

`install.sh` asks what you want: **both** (recommended), **only the axle tool** (it works under
any prompt), or **only the Benzene prompt**. Or say it up front: `--both`, `--tool`, `--theme`.

- **oh-my-zsh:** it links your choice into `$ZSH_CUSTOM` and shows the `~/.zshrc` lines
  (`plugins=(... axle)` for the tool, `ZSH_THEME="benzene"` for the prompt). Without oh-my-zsh
  (or with `--plain`) it prints the `source` line instead. It never edits `~/.zshrc` itself.
- **The part you didn't choose is removed.** In a git clone that's done with sparse checkout,
  so `axle update` keeps working and `./install.sh --both` brings it back later. In a downloaded
  copy it asks before deleting. It never removes files with uncommitted changes. `--keep` keeps
  everything.
- **If the tool is included, the setup wizard starts** (`--no-configure` skips it). It asks only
  about what you installed, and you can re-run it any time with `axle configure`.

Plugin managers: `zinit light hottahidit/axle` or antidote's `hottahidit/axle` load the tool. For
only the prompt, name its file: `zinit ice pick"benzene.zsh-theme"; zinit light hottahidit/axle`, or
antidote's `hottahidit/axle path:benzene.zsh-theme`.

**MnemoCetus** (experimental, optional, asked first; `--nemc`, `--no-nemc`): [MnemoCetus](https://github.com/hottahidit/MnemoCetus)
is a separate project that scans your projects. Choosing it installs `nemc` (with uv or pipx) and
moves this checkout to Axle's `MnemoCetus` branch, which `axle update` then follows. That adds
`axle nemc` and the folder's state in the Benzene prompt.

`ZSH_THEME="axle"` (the old name) still works and loads whatever is installed. `axle doctor`
checks the setup; `axle update` updates.

## The `axle` command

One command for both parts. With only Benzene loaded it has the prompt's subcommands; the tool
adds its own. `axle help` lists what's available, `axle help <command>` (or
`axle <command> --help`) shows a command's options with examples, and **Tab** completes
everything: commands, variants, modules, segments, preview scenarios, settings and their values.
A typo gets an answer instead of a wall of text: `axle statz` → *did you mean: axle stats?*

```zsh
axle configure      # set up whatever's installed, step by step (prompt with a live preview)
axle config         # see and change single settings
axle preview        # view and test every state of the prompt
axle variant axon   # switch variant (nox / axon)
axle jump api       # (or just `j api`) go to the folder you mean
axle history        # recent commands: when, outcome, run time, folder
axle stats          # what you run, what's slow, what fails, where you work
axle doctor         # check the setup
axle module         # list modules; `axle module off env` / `on env`
axle update         # git pull, then reload (--check: only say what's new)
axle version        # which version, and what's loaded
axle reload         # re-read Axle's files
axle uninstall      # remove Axle (asks first)
```

Questions (in `axle configure`, `axle config set`, `axle uninstall`) are answered with the
arrow keys: ↑/↓ to move, Space to tick a box, Enter to answer, Esc to cancel. The wizard's
preview follows the option you're on.

### Settings: axle config

```zsh
axle config                          # every setting, its value, and where it comes from
axle config get AXLE_PALETTE         # what it does, its value and default
axle config set AXLE_PALETTE classic # save it and apply it now
axle config set AXLE_MODULES suggest jump   # a list: several words
axle config set                      # pick a setting and a value from menus
axle config unset AXLE_PALETTE       # back to the default
axle config edit                     # open the file in $EDITOR
```

Settings are saved to `~/.config/axle/config.zsh`, which is read after `~/.zshrc`, so it wins.
Values are checked (a choice must be one of its options, a switch 0 or 1) and written quoted, so
the file stays plain data whatever a value contains.

### Updates and uninstalling

Once a day, in the background, Axle checks whether a new version is out, and if so the next
prompt says so, once: `axle 0.2.1 is out (you have 0.2.0): axle update`. It never waits on the
network or asks for a password. `axle update --check` asks right away and shows the changelog;
`AXLE_UPDATE_CHECK=0` turns the daily check off.

`axle uninstall` removes the links `install.sh` made in oh-my-zsh, then asks which of your
settings, recorded history and cache to delete. It never edits `~/.zshrc`: it lists the lines to
remove. (`--yes` removes the links and cache without asking; `--purge` everything.) Axle's own
folder is left for you to delete.

# Benzene, the prompt

| Variant | Short name | Description |
|---|---|---|
| **NoxA** | `nox` | Default. A quiet two-line prompt that shows information only when it is relevant, and expands on demand. |
| **AxoN** | `axon` | Focus variant: one quiet line (folder, branch, `$`); anything else appears only when it needs attention. |

Pick one with `AXLE_VARIANT=nox|axon` (all settings use the `AXLE_` prefix), or switch any time
with `axle variant`.

## NoxA (`nox`)

A quiet two-line prompt: each piece of information appears only when it is relevant. Context sits
on the left of the top line and stats (run time, sudo, battery, ...) on its right, so the line you
type on stays clear. The stats stay right-aligned as the window is resized, and are dropped if
they no longer fit. The top line can never wrap: line wrapping is switched off while it's drawn,
so if a terminal draws a character wider than expected, the line is cut at the edge instead
(run `axle debug` to see the measurements).

```
╭─ ~/repos/axle │ main ⇡1 +2 !1 ?3 │ py 3.12.3 (venv) │ (+2)        2.21s[1]
╰─➜
```

| Segment | Shown when |
|---|---|
| `dir` | Always. Turns **amber** on a Windows drive under WSL (`/mnt/c/...`); `ro` when not writable |
| `git` | Inside a repo: branch (green clean / orange dirty) or `@sha (tag)`; `REBASE 2/5`, `MERGE`, ...; `gone` upstream; `⇡ahead ⇣behind =conflicts +staged !modified ?untracked *stashes`; last-commit signature (see below); push protocol `🌐ssh` / `🌐https` (`🌐http` in red: unencrypted) |
| `context` | The machine, when it isn't this one: a server icon + hostname over SSH (if Axle is installed on the remote), the Docker icon + hostname in a container (a toolbox or distrobox container by its name); `user@host` as root or expanded |
| `inside` | You're in a shell started from another program, so `exit` goes back to it: `↳ ranger`, `yazi`, `nnn`, `lf`, `xplr`, `vim` / `nvim` (`:sh`, `:terminal`), `mc`, `chezmoi` |
| `direnv` | An `.envrc` is loaded; an amber `direnv blocked` bubble when there's one direnv hasn't been allowed to load (`direnv allow`) |
| `python` `node` `go` `rust` `nix` | A venv/conda env is active, or the project (this dir or a parent) uses that language. Python also checks you're in the right venv: an amber bubble names it when this project's venv isn't activated (`shop-api (inactive)`), or when the active venv belongs to another project (`shop-api (other project)`) |
| `ruby` `java` `php` `lua` `perl` `scala` `flutter` `haskell` | The project uses that language (`Gemfile`, `pom.xml`/`build.gradle`, `composer.json`, `.luarc.json`, `cpanfile`, `build.sbt`, fvm's `.fvmrc`, `stack.yaml`, or a version pin). Through a version manager (rbenv, jenv, phpenv, luaenv, plenv, scalaenv, asdf, mise, fvm) it shows the version the folder selects, never running the program |
| toolchain pins | A project pins a version (`.nvmrc`, `.node-version`, `.python-version`, `rust-toolchain`, `.ruby-version`, `.java-version`, `.php-version`, `.lua-version`, `.perl-version`, `.scala-version`, `.fvmrc`, `.tool-versions`) and the active one differs, or the version manager hasn't installed it: an amber bubble, `node 25.6.0 (wants 20)`, `rb 3.4.1 (not installed)` |
| `kube` `docker` `aws` `gcloud` `terraform` | A context/profile/workspace is set (Docker only when not `default`) |
| `ebenv` `gcred` `azure` | This folder's Elastic Beanstalk environment; the service account in `$GOOGLE_APPLICATION_CREDENTIALS` (`sa deployer@shop-dev`); Azure's default subscription (it applies everywhere, so only when expanded, or when it's production) |
| `vimode` | `NORMAL` while in vi command mode |
| `jobs` | Background jobs exist |
| `tmux` | Outside tmux: detached sessions are still running (`tmux 2`); inside it: session and window when expanded |
| `exec` (top right) | The last command took ≥ 2 s or failed: `2.21s`, `0.03s[1]`, `32s[147]`, `1.2s[0\|1\|0]` for a failed pipeline |
| `sudo` (top right) | After a `sudo` command, time left before sudo asks for a password again: `sudo 14m`, then `sudo 42s` in red during the last minute. Updates in place |
| `load` (top right) | Load average ≥ CPU count |
| `clock` (top right) | Always: `22:46`; with seconds (`22:46:42`) while expanded. Ticks in place |
| `timew` (top right) | timewarrior is tracking: the tags and how long, `⏱ client-x 1h05m` |
| `task` (top right) | Overdue taskwarrior tasks, as an amber bubble; pending ones when expanded |
| `todo` (top right) | Open todo.txt items, when expanded |
| `vpn` (top right) | Connected to NordVPN |
| `pdhist` (top right) | The per-directory-history plugin is in the mode you don't start in (Ctrl-G switches) |
| `battery` (far top right) | Below 30% and discharging: a red battery icon |

Colour carries the rest: the frame and arrow are one piece (`╭─ … ╰─➜`) in a single colour: mauve
normally, **dark red at 80%+ RAM use**, red after a failure.

**Alarms.** When something is genuinely wrong, that one item is drawn as a red bubble (rounded
ends, like oh-my-posh's diamond segments; a square block without a Nerd Font) instead of coloured text, the loudest thing on the screen because nothing else uses a background:

```
╭─ ~/repos/app │ main │ ▌⎈ eks-prod:payments▐                ▌0.40s[1]▐ │ 12:00
```

| Alarm | When |
|---|---|
| run time + exit code | the last command failed |
| `user@host` | you're root (amber: a caution rather than a failure) |
| kube / docker / aws / gcp / terraform / Beanstalk / Azure / Google credentials | the context, profile, project or workspace matches `AXLE_PROD_PATTERN` (default `(#i)*prod*`, any case) |
| battery | below 30% and discharging |
| git | merge conflicts, or the last commit has a bad or revoked signature |

Alarms are never trimmed into `(+N)`. `AXLE_ALARMS=0` turns pills off (the colours stay).
AxoN stays plain.

**Importance.** When more segments apply than fit (5 on the left, 3 on the right, or the
terminal width), the least important ones are hidden and counted as `(+N)`. The ranking is
`AXLE_NOX_PRIORITY`, most important first:
`dir exec sudo git context inside vimode battery kube aws ebenv gcloud gcred azure docker direnv jobs tmux timew python node go rust ruby java php lua perl scala flutter haskell terraform nix task load mem vpn todo aistatus pdhist shlvl clock`.
Run `axle segments` for every name.

**Expanding.** Press **Alt-i** to show everything, including hidden segments, `user@host`, seconds on the clock, memory %,
battery %, load, shell depth, commit age and never-pushed branches. Press it again, or run a
command, to collapse. (Clicking can't expand the prompt: zsh only receives mouse clicks if it
captures the mouse, which breaks normal text selection and scrolling.)

**Links.** The path and branch are terminal hyperlinks (OSC 8). **Ctrl+click** in Windows Terminal,
VS Code, iTerm2, WezTerm, kitty, etc. opens the folder in Explorer/your file manager (not at a bare `~`), or the branch
on GitHub / GitLab / Gitea. Terminals without hyperlink support just show the text.

**Commit signatures.** The last commit's signature (`git log --format=%G?`) shows as a badge:
`✓sig` green for a good signature from a trusted key; `✗sig` red for a bad signature or revoked key;
`?sig` amber when it's signed but the key is untrusted, expired, or not in your keyring; `!sig` amber
when unsigned. To keep it quiet, the unsigned badge only appears in repos with `commit.gpgsign=true`
(where unsigned means something went wrong), and otherwise under Alt-i.
The push protocol comes from `git remote get-url --push` on the branch's upstream remote (else
`origin`), so `pushInsteadOf` rewrites are taken into account.

**Live updates.** The sudo countdown redraws the *current* prompt in place (no new prompt lines,
and whatever you've typed is kept). A background timer wakes only when the text would change:
once a minute, then every second in the last minute. Nothing runs while no countdown is shown.
It never redraws over a completion menu or search.

How the countdown works: sudo's timestamp is only readable by root, so after any command line
containing `sudo` (aliases included), NoxA runs `sudo -n true`. That succeeds only if no password
is needed, and resets the timer just as your command did. The lifetime comes from
`sudo -V` (your `timestamp_timeout`, 15 min by default) or `AXLE_SUDO_TIMEOUT`. `sudo -k` clears it.
Only sudo used in this shell is counted; with sudo's default per-terminal timestamps, that's exactly
what applies here.

Git status is computed in a background process, so slow repos (e.g. under `/mnt/c`) never block
the prompt. Drawing a prompt takes about 2 ms.

### Past commands

Once you press Enter (or abandon a line with Ctrl-C), its prompt shrinks to the time it was run,
where, and the command. Everything else (git, battery, run time, ...) described the moment before the
command, so it's dropped. Output is never touched:

```
22:04:31 ~/repos/axle ➜ echo hello
hello
22:04:33 ~/repos/axle ➜ false
╭─ ~/repos/axle │ main ?5
╰─➜                                   0.00s[1]
```

Set `AXLE_TRANSIENT=0` to keep full prompts in scrollback.

Past output can't be collapsed and re-expanded from the shell (zsh never sees it, and scrollback
can't be rewritten). What NoxA does instead is mark every prompt, command and output with
shell-integration sequences (OSC 133), so the **terminal** can navigate by command. In Windows
Terminal (1.21+), add to `settings.json`:

```jsonc
// in your Ubuntu profile:
"showMarksOnScrollbar": true,
// in "actions":
{ "command": { "action": "scrollToMark", "direction": "previous" }, "keys": "ctrl+up" },
{ "command": { "action": "scrollToMark", "direction": "next" }, "keys": "ctrl+down" },
{ "command": { "action": "selectOutput", "direction": "prev" }, "keys": "ctrl+shift+up" },
{ "command": { "action": "selectCommand", "direction": "prev" }, "keys": "ctrl+alt+up" }
```

Ctrl+Up/Down jumps between commands; Ctrl+Shift+Up selects the previous command's whole output
(then Ctrl+C copies it). Failed commands get a red mark on the scrollbar. VS Code has the same
built in (Ctrl+Up/Down; "Terminal: Select To Previous Command"), so NoxA leaves marks to VS Code
there. `AXLE_MARKS=0` turns them off.

### In VS Code

In VS Code's integrated terminal (detected via `TERM_PROGRAM=vscode`), NoxA switches to a
one-line layout that leaves out what VS Code already shows:

```
axle/lib │ main ?5 │ py proj │ 0.03s[1] ➜
```

- **One line, no right prompt.** The terminal panel is short and often resized, and a right
  prompt gets rewrapped badly on resize.
- **Repo-relative path** (`axle/lib`, like the explorer sidebar) inside a repository; `~`-paths
  elsewhere. The link opens the folder in VS Code's own context, so it works over Remote-WSL.
- **No language versions.** The status bar shows the interpreter; only an *active* venv/conda env
  is shown, since the terminal's env can differ from the selected interpreter.
- Run time and exit code, sudo countdown, low battery, git, cloud contexts and `(+N)` trimming work
  as usual (`AXLE_NOX_CODE`, at most `AXLE_NOX_MAX_CODE=5` segments).
- VS Code's shell integration (the pass/fail markers in the gutter, command navigation) keeps
  working: each hook still sees the command's real exit code.

`AXLE_VSCODE=0` keeps the normal layout in VS Code; `AXLE_VSCODE=1` forces the compact one anywhere.

Two VS Code settings make it match the terminal:
```jsonc
"terminal.integrated.fontFamily": "'Cascadia Code NF'",   // for AXLE_NERD_FONT=1 icons
"terminal.integrated.minimumContrastRatio": 1              // keep the dim Mocha greys dim
```
VS Code otherwise brightens low-contrast text, which washes out the quiet separator
colours. With the Catppuccin Mocha VS Code theme, the terminal background matches too.

### Colours

NoxA uses [Catppuccin Mocha](https://catppuccin.com/palette) by default, and each colour has one meaning:

| Colour | Meaning | Used for |
|---|---|---|
| red | error / danger | failed exit code, conflicts, bad signature, root, `http` remote, rebase/merge in progress |
| peach | warning | Windows drive path, sudo countdown, SSH session, unverified/unsigned commit |
| yellow | change / cost | modified files, dirty branch, run time |
| green | good | clean branch, staged files, good signature |
| sky | sync | ahead/behind upstream |
| blue | location | the path |
| mauve | accent | the frame + arrow, one piece (red after a failure, deep red at 80%+ RAM) |
| pink | remote infra | kube, docker, aws, gcp, terraform, Azure, Beanstalk (where your commands land) |
| teal, flamingo, sapphire, rosewater, lavender, maroon, ... | languages | python, node, go, rust, nix, ruby, java, ... (each its own) |
| overlay | quiet | separators, untracked, clock, push protocol |
| red pill | alarm | failure, root, production context, low battery, conflicts, bad signature |
| deep red | memory pressure | frame + arrow at 80%+ RAM (Catppuccin Latte red, darker than Mocha's) |

Colours are 24-bit, so they match Mocha exactly whatever your terminal's scheme is; set your
terminal to Catppuccin Mocha too for the matching background. Terminals without 24-bit colour
get the nearest 256-colour match automatically (Windows Terminal, VS Code, kitty, iTerm2,
WezTerm and Ghostty are detected as 24-bit).

```zsh
axle colors                       # preview every colour role
axle palette classic              # switch live to the 256-colour palette (or back: mocha)
AXLE_PALETTE=classic              # ...or set it in ~/.zshrc
typeset -A AXLE_COLORS=(path '#74c7ec' accent '#f5c2e7')   # override single roles
```

### AI status

The `aistatus` module (in `modules/`, separate from the prompt itself) watches AI services and
shows one small dot per service at the far right of the **expanded** view (Alt-i): green when
operational, amber when degraded, red when down, grey when unknown. Each dot links to its status
page (Ctrl+click), and `axle ai` prints the details:

```
  ● claude       up        All Systems Operational                        checked 6s ago
  ● ollama       up        answering at http://localhost:11434/api/version checked 2s ago
  ● lmstudio     down      not answering at http://localhost:1234/v1/models checked 0s ago
```

Claude is watched by default. Pick any mix in `~/.zshrc`:

```zsh
AXLE_AI_STATUS=(claude openai ollama)
AXLE_AI_STATUS=(claude 'homelab=http://192.168.1.20:8080/health')   # custom
```

| Built in | Checked via |
|---|---|
| `claude` `openai` `mistral` `cohere` `perplexity` `groq` | their status page (Statuspage API) |
| `copilot` | GitHub's status page, the Copilot component |
| `huggingface` | its status page (Better Uptime) |
| `gemini` | Google Cloud incidents affecting "Vertex Gemini API" (needs `python3`; AI Studio has no public feed) |
| `ollama` `lmstudio` `llamacpp` `jan` `vllm` | the local server's API answering on its default port |
| `name=URL` | a status page URL is read for its state (Statuspage or Better Uptime); any other URL is up on HTTP 2xx |

xAI, DeepSeek and Together don't publish a machine-readable status feed, so they can't be
built in.

Checks run in a background job, never while a prompt is drawn: every 3 minutes for status pages
(`AXLE_AI_STATUS_INTERVAL`) and every 30 s for local servers (`AXLE_AI_LOCAL_INTERVAL`). Results
are cached in `~/.cache/axle/aistatus/` and shared, so with several shells open only one of them
checks. If you're offline, remote services show grey (unknown), not red.

Under WSL, a local server running on the **Windows** side is tried on the Windows host's
address too. For that to answer, it must listen beyond localhost (LM Studio: "Serve on Local
Network"; Ollama: `OLLAMA_HOST=0.0.0.0`), or WSL must use mirrored networking.

To turn the module off: `AXLE_MODULES=()`.

### Settings

Set these in `~/.zshrc` before `source $ZSH/oh-my-zsh.sh`:

```zsh
AXLE_NERD_FONT=1                  # Nerd Font icons (default 0: plain Unicode/text)
AXLE_NOX_LEFT=(dir git python kube jobs)     # which segments, in display order
AXLE_NOX_RIGHT=(exec battery)
AXLE_NOX_PRIORITY=(dir exec git kube ...)    # most to least important
AXLE_NOX_MAX_LEFT=5               # segments on line 1 before trimming to (+N)
AXLE_NOX_MAX_RIGHT=3              # segments on the right before trimming
AXLE_CMD_MIN_SECS=2               # run time worth showing
AXLE_MEM_WARN=80                  # RAM % that turns the prompt dark red
AXLE_BATTERY_WARN=30              # battery % that shows the battery icon
AXLE_SUDO_TIMEOUT=15              # sudo lifetime in minutes (default: read from sudo)
AXLE_PATH_DEPTH=4                 # path components kept before eliding the middle
AXLE_DETAIL_KEY='^[i'             # expand key (Alt-i); '' to disable
AXLE_LINKS=1                      # 0 = no clickable path/branch
AXLE_ICON_WIDTH=2                 # columns per Nerd Font icon (default: asked from the terminal)
AXLE_NOTIFY_SECS=30               # ring the terminal bell after long commands (default 0 = off)
AXLE_GIT_ASYNC=1                  # 0 = compute git status synchronously
AXLE_GIT_UNTRACKED=1              # 0 = skip untracked files (much faster in huge repos)
AXLE_PROMPT_GAP=2                 # spaces between the arrow and what you type
AXLE_ALARMS=0                     # no red alarm bubbles (default 1)
AXLE_BUBBLES=0                    # square alarm blocks instead of rounded bubbles
AXLE_PROD_PATTERN='(#i)*prod*|*live*'   # contexts that count as production
AXLE_PROMPT_CHAR='λ'              # the prompt character (default: the powerline arrow U+E0B0 with a
                                  # Nerd Font, ▶ without; AXLE_PROMPT_CHAR_VICMD in vi command mode)
AXLE_CLOCK=0                      # clock only in the expanded view
AXLE_TRANSIENT=0                  # keep full prompts in scrollback (default 1: `22:04:31 dir ➜ cmd`)
AXLE_MARKS=0                      # no shell-integration marks (default: on, except in VS Code)
```

For conda, run `conda config --set changeps1 False` so conda doesn't add its own prefix.
NoxA sets `VIRTUAL_ENV_DISABLE_PROMPT=1` for the same reason.

## AxoN (`axon`)

The focus variant, for heads-down work, screen sharing and recordings: one line with the folder,
the branch and `$`. Anything else appears only when it needs your attention:

```
axle $                              outside a repo
axle(main) $                        on a branch, nothing to commit
axle(main)*+ $                      unstaged (*) and staged (+) changes
axle(other) REBASE 1/1 =1 ✗1 $      mid-rebase, a conflict, last command failed
axle(@368f5f1) $                    detached HEAD
nas stacks(main) &1 sudo 42s ✗130 $ over SSH (server icon + host), a background job, sudo still active,
                                    a slow (≥ 10 s) command that was interrupted
↳ ranger dl $                       in a shell started from ranger (exit goes back)
```

Colour carries the state: the `$` is mauve, **red after a failure** and **deep red at 80%+ RAM**
(`#` as root, `:` in vi command mode); the branch is green when clean and yellow with changes;
the folder turns amber on a Windows drive; a low battery shows its red icon. Past prompts compact
to a dim `axle $ command`.

AxoN runs on NoxA's engine, so background git, the sudo countdown, AI status, Nerd Font icons,
palettes and shell-integration marks all work the same, and **Alt-i** shows NoxA's full
two-line prompt until the next command.

```zsh
AXLE_VARIANT=axon
AXLE_AXON_SHOW=(host inside dir git venv direnv toolchain jobs tmux sudo battery exec)   # in order
AXLE_AXON_SLOW=10                                      # run time shown from this many seconds (0 = never)
AXLE_AXON_CHAR='$'                                     # prompt character (AXLE_AXON_CHAR_VICMD=':')
```

## Setup wizard

`axle configure` asks about whatever is installed. For Benzene: icons, variant, colours, prompt
character, past commands, and the variant's own options (alarms, clock and AI dots for NoxA;
the run-time threshold for AxoN), each drawn as a live preview with the real prompt code. For the
tool: which modules to switch on, how many options the Ctrl-N list shows, and whether venv switches are
announced. It saves to `~/.config/axle/config.zsh` (loaded after `~/.zshrc`, so it wins),
replacing only the settings it asked about, and tells you which `AXLE_*` lines in `~/.zshrc`
it now overrides. `install.sh` starts it for you when the tool is installed.

## Previewing every state

`axle preview` shows the prompt in every situation it handles (30 scenarios), drawn in your own
terminal with your font, palette and settings, so you can see exactly how each one looks:

```
 Axle preview  nox · mocha · Nerd Font icons · 100 cols
 ──────────────────────────────────────────────────────
 18/30  Production kube context + AWS profile (alarms)  (prod)
 ╭─ ~/repos/clean │ main │ ⎈ eks-prod:payments │ aws production@eu-west-1    12:43
 ╰─➜  git status
   past: 12:43:07 ~/repos/clean ➜  git status
 ──────────────────────────────────────────────────────
 ←→ scenario  v variant  e expand  i icons  c palette  [ ] width  r ruler  q quit (or Ctrl-C)
```

Keys toggle NoxA/AxoN, the expanded view, Nerd Font icons and the palette, shrink the simulated
width (to test trimming), and show a ruler at the right edge (to check alignment).

```zsh
axle preview                        # interactive viewer
axle preview --all                  # print every scenario (scrollable, easy to paste)
axle preview --list                 # scenario names
axle preview failed prod battery    # just these
axle preview --all --axon --expanded --nerd --width 80
```

Git states come from real throwaway repositories (deleted on exit); everything else is faked.
It runs in a subshell, so your live prompt is never touched.

## tmux

Inside tmux, the prompt's 24-bit colours and clickable links need a few tmux settings. Axle
ships them, with a Catppuccin Mocha status bar to match, in `benzene/tmux.conf`:

```tmux
# ~/.tmux.conf
source-file ~/repos/axle/benzene/tmux.conf
```

`axle tmux` prints the file. Outside tmux, the prompt reminds you of detached sessions that are
still running (`tmux 2`); inside, Alt-i shows the session and window.

## Switching variants at runtime

```zsh
axle variant        # print the current variant
axle variant axon   # switch to AxoN
axle variant nox    # switch back to NoxA
```

# axle, the tool

Modules (all on by default; switch them in `axle configure`, or with `axle module off <name>`):

| Module | Does | Like |
|---|---|---|
| `suggest` | grey suggestions as you type (Ctrl-N lists the alternatives) | zsh-autosuggestions |
| `highlight` | syntax highlighting as you type: green commands, red typos | zsh-syntax-highlighting |
| `upsearch` | type part of a command, then ↑/↓ walks through history lines with it | zsh-history-substring-search |
| `jump` | `j <words>`: cd to the folder you most likely mean | zoxide, z |
| `search` | Ctrl-R: a history picker with filters | atuin, fzf's Ctrl-R |
| `env` | activates a project's venv when you enter it, deactivates when you leave | direnv, autoenv |
| `fix` | `fix` / Esc Esc: corrects the last command (typos, missing sudo) | thefuck, oh-my-zsh's sudo |

All of them learn from one history log the tool keeps: every command with where it ran, its
exit code, run time and the command before it (`~/.local/share/axle/history`; lines typed with a
leading space aren't recorded).

## suggest: smart autosuggestions

Works like [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions): as you type,
the likeliest completion of the line appears in grey after the cursor. When you want to see the
alternatives, Ctrl-N opens a short list of them below the line:

```
╰─▶  axle c[onfigure]          Ctrl-N →   ╰─▶  axle c[olors]
                                                axle configure
                                              ▸ axle colors
```

| Key | Does |
|---|---|
| **→** or **End** | accept the suggestion (also `vi`'s `l`, `$` and `A`) |
| **Ctrl-→** or **Alt-f** | accept its next word (also `vi`'s `w`, `e`, `W`, `E`) |
| **Ctrl-N** or **Shift-↓** | open the list of other options, then move down it |
| **Ctrl-P** or **Shift-↑** | move up the list (with no list open, these keys keep their usual job: history) |
| **Enter** | run what you typed (nothing is left in scrollback) |
| typing | closes the list; **Tab** completion steps over it; moving through history shows no suggestion until you edit |

Suggestions come from strategies, tried in order until there are enough:

- **smart**: Axle records each command with where it ran, how it ended and what came before it
  (`~/.local/share/axle/history`), and ranks by runs in **this directory**, runs **right after
  the previous command** (`git add .` → `git commit …`), and how often and how recently you ran
  them. Commands that have only ever failed are never offered.
- **history**: your shell history, newest first (what zsh-autosuggestions does).
- **completion**: for the first word a command name, after it a real file or folder path.

| Setting | Default | |
|---|---|---|
| `AXLE_SUGGEST` | `1` | `0` turns it off |
| `AXLE_SUGGEST_STRATEGY` | `(smart history completion)` | which strategies, in order |
| `AXLE_SUGGEST_STYLE` | muted grey | how it looks, e.g. `'fg=#6c7086,underline'` |
| `AXLE_SUGGEST_IGNORE` | | a zsh pattern of lines never suggested, e.g. `'(cd\|rm) *'` |
| `AXLE_SUGGEST_MAX_BUFFER` | `0` | no suggestions past this many characters (0 = any) |
| `AXLE_SUGGEST_LIST` | `5` | options in the Ctrl-N list (1 = no list) |

Widgets for your own bindings, named like zsh-autosuggestions': `axle-suggest-accept`,
`axle-suggest-execute` (accept and run), `axle-suggest-partial`, `axle-suggest-clear`,
`axle-suggest-toggle`, `axle-suggest-next`, `axle-suggest-prev`. For example
`bindkey '^ ' axle-suggest-accept`. Lines typed with a leading space aren't recorded.

`axle history [n]` lists recent commands with when they ran, their outcome, run time and folder.

It costs nothing at shell startup (the learned data loads on your first keystroke, from a cache
rebuilt in the background) and well under 2 ms per keystroke. `AXLE_SUGGEST=0` turns it off; it
also steps aside if you use zsh-autosuggestions.

## highlight

As you type, the command turns **green** when it exists and **red** when it doesn't (so a typo
shows before you press Enter); options, strings, variables (also inside double quotes), globs,
operators and comments each get their own colour, existing paths are underlined, and keywords
(`if`, `for`, `[[`) are bold. Colours come from the prompt's palette.

```zsh
typeset -A AXLE_HIGHLIGHT_STYLES=(unknown 'fg=red,bold' path 'underline' string 'fg=#a6e3a1')
#   kinds: command unknown reserved option string variable glob operator comment path assign
AXLE_HIGHLIGHT_MAX=2000        # longer lines (big pastes) aren't highlighted
```

It takes about 0.3 ms a keystroke. Whether a command exists is remembered (on WSL, looking up an
unknown name means searching every Windows folder on your PATH), and forgotten when PATH
changes. It steps aside if zsh-syntax-highlighting is loaded.

## upsearch

Type part of a command, then **↑**: only history lines containing it come up, newest first, with
the match highlighted; ↑ again goes further back, ↓ comes forward, and past the newest you get
back what you typed. On an empty line, ↑ and ↓ work as usual.

```
push ↑   →   git push --force        ↑   →   git push origin main
```

`AXLE_UPSEARCH_PREFIX=1` matches only lines that start with what you typed (like zsh's own
history-beginning-search), `AXLE_UPSEARCH_CASE=1` makes it case-sensitive. The widgets are
`axle-history-search-up` / `-down`, for your own keys.

## fix

When a command fails, `fix` puts the corrected one on the line for you to check, and Enter runs
it. Esc Esc does the same on an empty line (or adds `sudo` to the last command when there's
nothing to correct), and on a line you're typing it adds or removes `sudo`.

| You ran | `fix` gives |
|---|---|
| `gti status` | `git status` (the closest command, preferring ones you use) |
| `git psuh` | `git push` |
| `git push` (a new branch) | `git push -u origin my-branch` |
| `cd Donwloads`, `cat readme.md` | `cd Downloads`, `cat README.md` (the closest name that exists) |
| `./deploy.sh` (not executable) | `chmod +x ./deploy.sh && ./deploy.sh` |
| `apt install htop`, `systemctl restart nginx` | the same with `sudo` |

It never runs anything itself. `AXLE_FIX_CMD` renames the command (`''` for none), `AXLE_FIX_KEY`
changes the key. (It does what the tool *thefuck* does, without the name.)

## jump

`j <words>` goes to the folder you most likely mean, ranked by where you actually work: the
folders you run commands in, weighted by how often and how recently.

```
j api          the best folder whose name matches "api"
j re ax        words match the path in order; the last one matches the folder's own name
j              your top folders            j -l <words>   list matches without going
j -            back to the previous folder
```

Tab after `j <words>` offers the matches, best first. `AXLE_JUMP_CMD` renames the command.

## search

**Ctrl-R** opens a history picker under the prompt:

```
╰─▶  git
  search · all history · 3 matches   Tab: filter  Enter: choose  Esc: cancel
  ▸ git push origin main          2h · ~/repos/api
    git status                    now · ~/repos/axle
    git rebase main               3d · ~/repos/web ✗
```

Type to filter (every word must match, in any order); ↑/↓ or Ctrl-R/Ctrl-P/Ctrl-N move; Enter puts
the command on the line to edit or run; Esc cancels. **Tab** switches between all history, only
this folder, and only commands that worked. `AXLE_SEARCH_KEY` / `AXLE_SEARCH_ROWS` change the key
and the size.

## env

When you `cd` into a project with its own virtualenv (`.venv`, `venv`, `env`), it's activated; when
you leave, or enter a project with a different one, it's switched or deactivated, with one quiet
line saying so (`AXLE_ENV_QUIET=1` silences it). A venv you activated yourself is left alone.

It never runs the venv's `activate` script, which a cloned repository could ship with anything in
it: it sets `VIRTUAL_ENV` and puts the venv's `bin/` first on `PATH`, and undoes exactly that.

## history, stats, doctor, update

- `axle history [n]`: recent commands with when they ran, ✓/✗ and exit code, run time and folder.
- `axle stats [--here] [--days N]`: most-used programs, slowest commands, what fails most often,
  busiest folders; `--here` for just this project.
- `axle doctor`: checks zsh and git versions, what's loaded, plugin conflicts, 24-bit colour,
  Nerd Font, tmux, the history file, config overrides and how fast the prompt draws, with a fix
  for anything that's off.
- `axle update`: `git pull` in the Axle checkout, then reload.

## Extending: segments, hooks, drops

Three ways to put your own information in the prompt, from zsh code to any program.

### Your own segments (Benzene)

```zsh
# in ~/.zshrc, after `source $ZSH/oh-my-zsh.sh`
weather() { axle_style sky "$(< ~/.cache/weather)" }    # set REPLY; empty = hidden
axle segment add weather weather right                   # left|right, optional priority
```

The function runs on every prompt, so keep it fast (read a cached value; do slow work in a
hook or a background job). Axle handles colour, alignment, trimming to `(+N)` and the
expanded view. Helpers for segment functions:

| Helper | Does |
|---|---|
| `axle_style <colour\|role> <text>` | coloured text in `REPLY` (a palette role like `ok`, `warn`, `sky`, or a hex colour) |
| `axle_alarm [1\|2]` | draw it as a red (1) or amber (2) bubble, never trimmed |
| `axle_expanded` | true while expanded (Alt-i), for detail-only segments |
| `axle_link <url> <styled text>` | make it Ctrl+clickable |

`axle segment ls` / `axle segment rm <name>`. In AxoN a segment shows only while it raises an alarm.

### Hooks

```zsh
notify_slow_failure() { (( $1 != 0 && $2 > 30 )) && notify-send "failed: $3" }
axle hook command-done notify_slow_failure
```

| Event | When | Arguments |
|---|---|---|
| `command-start` | before a command runs | the command line |
| `command-done` | after it finishes | exit code, seconds, command line |
| `prompt` | before each prompt is drawn | |
| `expand` | Alt-i toggled | `1` expanded / `0` collapsed |
| `dir` | the directory changed | the new directory |

`axle hook ls` / `axle hook rm <event> <function>`.

### Drops: from any program

Any program, in any language, can put a tab in every open prompt by writing a small file. The
helper does it for you (and `axle drop …` is the same thing from zsh):

```sh
~/repos/axle/tools/axle-drop backup "backup running" --while-pid $$
~/repos/axle/tools/axle-drop ci "main: tests failed" --level alarm --ttl 1h --link "$RUN_URL"
~/repos/axle/tools/axle-drop deploy "deploying api" --level warn --dir ~/repos/api
~/repos/axle/tools/axle-drop --rm deploy        # or: --ls
```

| Option | Effect |
|---|---|
| `--level ok\|info\|warn\|alarm` | green / accent text, amber / red bubble (warn and alarm always show) |
| `--ttl 30s\|10m\|2h\|1d` | disappears after this long |
| `--while-pid <pid>` | disappears when that process exits |
| `--dir <path>` | only shows inside that directory |
| `--link <url>`, `--icon <text>` | Ctrl+click target, leading icon |
| `--expanded` | only in the expanded view |

Open prompts notice changes within 5 s (`AXLE_DROP_POLL`) and redraw in place; at most 2 ok/info
drops show at once while collapsed (`AXLE_DROP_MAX`). A drop is just a file in
`~/.cache/axle/drops/<name>` with `key=value` lines (`text=`, `level=`, `expires=` epoch seconds,
`pid=`, `dir=`, `link=`, `icon=`, `expanded=1`), or plain text. Write it yourself if you prefer
(write a temp file, then rename it into place). Drops are only ever read, never run, so nothing
a program or a cloned repository writes can execute code in your shell.

# Project

## Development

```zsh
zsh tests/run.zsh            # the whole suite
zsh tests/run.zsh git venv   # just tests/test_git.zsh and tests/test_venv.zsh
```

Every test runs in a fresh zsh with its own throwaway home folder, so nothing touches your real
files. GitHub Actions runs the suite on Linux and macOS for every push and pull request.
`axle version` shows which version is loaded; changes are listed in [CHANGELOG.md](CHANGELOG.md).

### Speed

Loading both parts takes about 3 ms, and drawing a prompt about 2 ms. Three things keep it there:

- **Bytecode.** Axle's files are compiled to zsh bytecode (`*.zwc`, next to each file and
  ignored by git), which zsh reads instead of the text. `install.sh` and `axle update` compile
  them; a shell that finds one missing or out of date recompiles it in the background (and
  after a zsh upgrade, all of them). `axle doctor` says whether they're compiled.
- **Loading on first use.** Help pages, the settings table, Tab completion, the questions,
  `update`/`uninstall` and the tool's longer commands are read the first time they're used.
- **No subprocesses at startup or per prompt** beyond the background git status.

zsh itself is the rest: on WSL a bare interactive zsh takes far longer to start than Axle adds.

## License

[MIT](LICENSE): use, modify, fork and share Axle and Benzene freely, including in commercial
projects, as long as the copyright and licence notice come along.

## Layout

```
axle.plugin.zsh        the axle tool (oh-my-zsh plugin / plugin managers / source)
benzene.zsh-theme      the Benzene prompt (oh-my-zsh theme / source)
axle.zsh-theme         the old name: loads both
install.sh             choose tool / prompt / both; links it in, removes the rest, runs the wizard
lib/                   shared by both: the `axle` command, help, settings, Tab completion,
                       prompts (ui.zsh), the setup wizard, helpers
benzene/               the prompt: nox.zsh, axon.zsh, more.zsh (more segments),
                       segments.zsh (yours + drops), aistatus.zsh, preview.zsh, tmux.conf
core/                  the tool's core: events.zsh (events, hooks, history log), commands.zsh
modules/               the tool's modules: suggest, highlight, upsearch, jump, search, env, fix
tools/axle-drop        put a tab in the prompt from any program
tests/                 the test suite (zsh tests/run.zsh)
.github/workflows/     CI: the tests on Linux and macOS
CHANGELOG.md           what changed in each version
LICENSE                MIT
```
