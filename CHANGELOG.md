# Changelog

## 0.3.0 - axle run (in progress, branch `legionary`)

`axle run`: run this project, or go back to the last one (plan: `docs/legionary/ROADMAP.md`).

Fixed for everyone:
- Drops only worked with `extendedglob` on: under zsh's defaults the prompt showed their raw
  `text=...` line, with no icon, colour or link, and they never expired.
- `axle module` listed the current folder's files, and could refuse real modules.
- ↑ from an empty line became a search for what it had just recalled.
- `axle config` and others failed with `setopt globsubst`.
- `axle reload` left a shell broken when it started on a version before lazy loading.
- Text another tool puts before the prompt (nemc's light, conda's `(base) `) pushed
  Benzene's top line past the edge, cutting off the clock, and put `╭─` out of line with
  `╰─`; it's now counted, and the bottom line moves over to match.
- Ctrl-C at a question (`axle configure`, `axle config`, `axle run`, ...) printed ✗ but kept
  waiting, so each Enter or Ctrl-C printed another; now it cancels at once.
- `env`: `deactivate` didn't exist for a venv it turned on (it never runs `activate`, which
  defines it); now it does, and the venv stays off until you leave the project. After
  `exec zsh` (or in a nested shell), its venv counted as one you'd activated by hand, so it
  was never switched off again.
- `highlight`: typing a word with a `]` in it (`]` alone, `a]b`) printed
  `_axle_hl_runnable:14: invalid subscript` over the line.

Also for everyone:
- Benzene: the timer behind the clock and drops is kept from one prompt to the next when it
  rings at the same time (now on whole multiples of the drop interval too). Before, each
  prompt started a new `sleep` process, and the old ones lingered until their time: twenty
  quick prompts left twenty sleeping; now one. Enter to the next prompt: about 4–5 ms
  (it was 4.6–9.8).
- `axle top`: the system live, with btop. Axle carries btop 1.4.8 (`vendor/btop`,
  Apache-2.0, by Aristocratos) with an **Axle mode** added: key `A` shows only the processes
  `axle run` started (its services and everything under them), and `axle run top` opens it
  that way. `install.sh` offers to build it (`--btop` / `--no-btop`), `axle top --build`
  builds it later (`tools/axle-build-btop`; needs GNU make and g++ 14+ or clang 19+, and
  says what to install). Not built: `axle top` runs an installed btop; neither: it says how
  to get one. btop reads its usual settings; the Axle mode isn't saved in them.
- `fix`: a command that doesn't exist is said in Axle's style instead of zsh's
  `command not found`, with the closest one you could have meant (`✘ gti: no such command`,
  `did you mean git? (Esc Esc puts it on the line)`). `AXLE_FIX_NOTFOUND=0` turns it off; a
  handler another tool set up is left alone.
- `fix`: a line zsh can't read (it would only say `parse error near ...`) is caught on Enter
  and said plainly (`✘ zsh can't read this line: something is missing after <>`,
  `unexpected }`), and the line stays to fix; Enter again runs it as it is. An unfinished
  line (an open quote, `if`, `for`, `{`, `$(`, a `|` at the end) goes on to the next line
  as before. It's parsed in the shell, nothing runs. `AXLE_FIX_PARSE=0` turns it off.
- `axle help` and each command's help are styled: sections with rules, commands, aliases
  and arguments in colour, examples with their command picked out and notes dimmed, long
  descriptions wrapped. Plain when piped or with `NO_COLOR`. The `run` line no longer runs
  into its description.

New:
- New module **run** (off by default while in progress; `axle module on run`):
  - Which project: the one you name (`axle run shop`, ranked by where you work, like `j`),
    a path you give, the one you're in, or else the last one you worked in (from the
    history log); `axle run` from anywhere takes you back there.
  - How to run it, detected from the files: package.json `dev` / `start` scripts (npm,
    pnpm, yarn or bun by lockfile; Vite, Next.js, Nuxt, Astro, Remix, Angular, express, ...
    known as servers, with their ports), FastAPI / Starlette (uvicorn), Flask, Django,
    Streamlit, Gradio, Dash, a single `[project.scripts]` entry, `main.py`, Rust (axum,
    actix-web, Rocket, warp as servers), Go (gin, echo, fiber, chi, `ListenAndServe`), and
    a lone `index.html`. Ports from the code when written there.
  - Scripts and CLIs run in the foreground, in the project's root and its venv (never
    `activate`). A venv can have any name (a folder with a `pyvenv.cfg`), and a part uses
    the project's if it has none. If another venv is active, it asks which to use
    (`AXLE_RUN_VENV`: `ask`, `project`, `active`), and says so when it's using one from
    outside the project or a venv is broken.
  - A Python file that starts its own server under `__main__` runs as it is, not through
    `flask run` or uvicorn, so whatever it starts first still starts. On a taken port it
    can still move to the next free one, without changing the file: a small startup hook
    (`modules/run/py/sitecustomize.py`, only for what axle run starts) gives the port to
    `app.run`, `socketio.run` or `uvicorn.run`. The hook also lets Flask-SocketIO's
    development server start in the background, which it otherwise refuses without a
    terminal.
  - Servers run in the background, supervised (no daemon): their output goes to a log,
    `.env` is read as data (never sourced) and given to the process, and the prompt shows
    a tab: `⏳ name` while starting, `⚡ name :port` once the port answers (Ctrl+click
    opens it; the port a dev server prints, if it picked another), red if it exits with
    an error. They keep running when the terminal closes. Killing one by hand works too:
    its supervisor (the process with the project's name) stops it, a service ended with
    TERM or Ctrl-C gets no red tab, and the tab follows the service, not its supervisor.
  - Ports: read from the command, the code, `vite.config`, `PORT` in `.env`, or the
    framework's default. A taken port says who has it (one of your services, or which
    program: `/proc` on Linux, `lsof` on macOS) and offers the next free port (passed the
    way the framework takes it: `--port`, `-p`, `-- --port` for npm, `PORT`, ...),
    stopping the other, or cancel; without a terminal, the next free port.
  - More projects: docker compose (`up -d`; `stop` is `down`, `logs` its logs), a
    Procfile's `web:` line, Makefile / justfile `run` / `dev` / `serve` / `start`.
  - Projects with several parts (a frontend and a backend, npm / pnpm workspaces, a Cargo
    workspace, `apps/*`, `services/*`): the first time (or with `--config`) it asks which
    to start and saves the choice. A saved part that can't run any more is reported and
    the rest start; a part that fails shows its whole log. `axle run stop` in the
    project stops all its parts.
  - `--verbose 'shop-web, shop-api'` shows those parts' output: each in its own tmux
    session (with tmux), or, without tmux, one part in this shell after the others start
    in the background (`--only` to start just that one).
  - `axle run ls` (state, port, uptime, memory, URL), `stop [name|all]`, `restart`,
    `logs [-f]` (which also clears a red tab) and `open`; `--fg` / `--bg` to choose.
  - Asks before a project's command runs the first time, and remembers per project and
    command; a changed package.json script asks again. A taken port is sorted out before
    that question, and another port doesn't make it a new command. `--yes` skips the question.
  - `axle run --dry-run` says which project, why, what would run and how.
  - Your settings, per project or part, kept in axle run's state (never in the project):
    `axle run set command "…"` (yours, so it runs without asking; split into words like
    the shell does, never run through one), `set port 8080` (given to the server the way a
    taken port's replacement is), `set kind service|task`, `set env-file .env.local`;
    `axle run set` shows them, `set <key>` alone removes one, `axle run forget` drops the
    project's settings, saved parts and approvals.
  - Profiles: `axle run --profile prod` reads `.env.prod` over `.env`, and is remembered
    for the project (`--profile none` drops it).
  - Hook events `run-start`, `run-ready`, `run-crash`, `run-stop` (`axle hook`), once each,
    in the shell that started it; a service's are noticed at the next prompt, only while
    there's one to watch.
  - Settings: `AXLE_RUN_ON_EXIT=stop` (services end with the terminal that started them),
    `AXLE_RUN_OPEN=1` (open the browser once a service answers; not on a restart),
    `AXLE_RUN_TRUST=always` (never ask before a project's command runs).
  - When it goes wrong, it says why and how to fix it: a crashed service (under its log,
    and again with `axle run logs`) or a failed task is looked at for known causes, and the
    fix goes on the line with Esc Esc or `fix`, until your next command; nothing runs by
    itself. A missing Python module → `pip install` into the project's venv
    (`-r requirements.txt` if it's listed there, `uv sync` with uv; a venv is created if
    there's none or it's broken); `Cannot find module`, `vite: not found` or no
    `node_modules` → `npm` / `pnpm` / `yarn` / `bun install` (or `add` one that's not in
    package.json); a taken port → `axle run set port <free one>`; a database that isn't
    reachable → `docker compose up -d <its service>` from the project's compose file, else
    starting it (`sudo service …`, `brew services start …`). Each fix is followed by the
    command that runs it again.
  - A venv shared by many projects ("uni-venv"): a folder's `.venv` (e.g. `~/Projects/.venv`)
    is used by the Python projects under it that have none of their own, and
    `AXLE_RUN_UNIVENV=~/Projects` makes it the first time it's needed. `axle run deps
    [pkg...]` installs a project's requirements.txt (or pyproject.toml's dependencies) into
    it without changing a version already there (pip gets them as constraints); a project
    whose versions conflict gets its own `.venv` instead, used from then on. Without a
    shared venv it installs into the project's own (making it if needed). Crash fixes for a
    missing module use `axle run deps` there.
  - Upkeep: a service's log is cut past `AXLE_RUN_LOG_MAX` (10M; what came before goes to
    `log.1`), checked every 2 s while it runs. `axle run set restart on-crash` (or
    `AXLE_RUN_RESTART=on-crash`) starts a service again after a crash, waiting 1, 2, 4... s
    (at most 30), and leaves it down after 5 crashes in a row each within 30 s of starting;
    its tab shows ↻ while it waits, and the count after (`⚡ web :8000 ↻2`); each crash
    fires `run-crash`.
  - Project tasks: `axle run :test`, `:build`, `:lint`... the same words in every project,
    read as text from package.json scripts (npm, pnpm, yarn, bun), a justfile, a Makefile,
    pyproject's `[project.scripts]`, and Cargo's, Go's and pytest's own; `axle run :` lists
    them, Tab completes them, words after the name go along (after `--` for npm). Asked the
    first time, like any of the project's commands (again when what it comes from changes).
  - What a service needs, started first: a database its `.env` points at on this machine
    (`DATABASE_URL=postgres://...@localhost:5432`, `REDIS_URL`, MySQL, MongoDB, RabbitMQ)
    that isn't answering and that the project's compose file has is started with
    `docker compose up -d <it>` (asked the first time) and waited for; or say them:
    `axle run set needs db redis`.
  - Health checks: `axle run set health /healthz` makes a service up only once that path
    answers (2xx or 3xx; asked through zsh's own TCP, no curl), and checks it every 10 s:
    3 failures in a row show it `unhealthy` (tab, `ls`, `top`), until it answers again.
  - `AXLE_RUN_NOTIFY=crash|ready|all`: a desktop notification when a service crashes,
    becomes ready, or turns unhealthy, from its supervisor (no shell needs to be open): a
    Windows toast on WSL, `osascript` on macOS, `notify-send` on Linux. Only plain
    characters of a name reach them.
  - `axle run env`: what a service here gets, in order: each `.env` file (a later one's value
    noted over an earlier one's), what axle run adds (PORT, the port hook), the venv.
    Secrets are masked (names like *KEY*, *SECRET*, *TOKEN*, *PASSWORD*, and a URL's
    password); `--show` shows them.
  - Groups: `axle run group dev add` (this project, or paths), `axle run group dev` starts
    them all in the background (each asked as axle run asks), `axle run group dev stop`
    stops their services, `axle run group` lists them.
  - Clearer screens: `axle run set` alone shows every setting, yours in colour, else
    what's detected (dimmed), else what it's for; `axle run :` groups the tasks under the
    file they come from; `axle run ls` colours the states (up, exited, restarting,
    unhealthy) in a terminal and shows no port for an exited service; `axle run logs`
    says which log in a terminal, and piped (`| head`, `| grep`) gives just the log;
    "didn't start" is only said after several parts (one part's failure was just shown).
  - `axle run top`: Axle's btop showing only the services (above), when it's built;
    otherwise (and with `--mini` / `--full`) the services live, in the shell. The full view fills the terminal:
    their total CPU over time, each service with its state, port, uptime, CPU and memory
    (bars when there's room), and the selected one's folder, command, CPU and memory graphs
    and last log lines. `--mini` is a few lines under the prompt, one per service with a CPU
    sparkline. Keys: ↑↓ select, `s` stop (asks), `r` restart, `o` open, `l` follow its log
    (Ctrl-C comes back), `m` the other view, `q` quit; it opens in the view you left it in.
    It samples once a second from /proc on Linux (one `ps` elsewhere), redraws over the
    last frame without clearing (no flicker), and uses well under 1% CPU (0.2–0.4% here).
  - A missing program (pnpm, cargo, ...) is said before anything is asked, with how to
    install it; answering no to "Run <last project>?" leaves you where you were and lists the
    other projects you worked in lately, to run one of them instead (Esc: none), and
    from a folder with nothing to run it says so before offering that project.
- Shared helpers, so each works without the other part: project markers and venv finding
  (`lib/project.zsh`, used by Benzene, `env` and `run`), and `j`'s folder ranking
  (`lib/rank.zsh`, used by `j` and `run`). Both load on first use.
- Bytecode compilation also covers files in subfolders of `modules/`.

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
