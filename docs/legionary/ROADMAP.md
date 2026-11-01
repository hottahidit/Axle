# Legionary → `axle run`: roadmap

Legionary (github.com/hottahidit/Legionary, January 2026) was planned as a project launcher:
go to a project, set up its environment, run it, and watch it. It never got past a README and a
mock-up (`demo.py`). This branch, `legionary`, brings that plan into Axle as **`axle run`**, built
on what Axle already has: frecency (`j`), project detection (Benzene), safe venv switching (`env`),
the history log, drops in the prompt, and the arrow-key questions.

The work stays on this branch until it meets the merge criteria at the end, then lands on `main`
as one release.

---

## The idea

> `axle run` gets you back to the last project you were developing, quickly. In a folder with a
> `main.py` / `app.py` that's detected as a website, it runs it as a background process, shown in
> the shell for easy running.

In practice:

```
~ $ axle run
  ↩ shop-api (last worked on 2h ago)            ← not in a project: back to the last one
  ✔ Run it?  python · FastAPI · uvicorn app:app --port 8000
  ⚡ shop-api running on http://localhost:8000  (background · axle run logs)

╭─ ~/repos/shop-api │ main │ ⚡ shop-api :8000 │ py 3.12 (venv)          ← it stays in the prompt
╰─▶
```

- **A website or service** (Flask, FastAPI, Django, Express, Vite, Next, an Axum server, ...) runs
  **in the background**: you keep your shell, and the prompt shows it (`⚡ shop-api :8000`,
  Ctrl+click opens it). If it crashes, the tab turns red until you look (`axle run logs`).
- **A script or CLI** (`main.py` with no server, `cargo run` of a CLI) runs **in the foreground**,
  like typing the command yourself.
- **Not in a project:** `axle run` goes back to the project you last worked in (from Axle's history
  log), and offers to run it.

---

## What carries over from Legionary

| Legionary planned | In Axle | Milestone |
|---|---|---|
| `legionary` (pick a project) | `axle run` with no project here: last project, or a picker of recent ones | M1 |
| `legionary <project>` | `axle run <words>`: the project ranked by `j`'s frecency, then run | M1 |
| `legionary goto <project>` | already exists: `j <words>` | done |
| `legionary add / remove` (a registry) | not needed: projects are found from where you work. Overrides per project in M5 | M5 |
| `legionary list` / `status` | `axle run ls` (what's running: port, uptime, memory) | M2 |
| auto-detect type, venv, entry point | detection table below; venvs through `env`'s logic (never `activate`) | M1 |
| `.env` files | read as data (`KEY=value`), into the process only, never sourced | M2 |
| port conflict resolution | detect the port, find who holds it, offer: stop it / next free port / cancel | M3 |
| process monitoring, stop / restart, logs | `axle run stop · restart · logs [-f]`, crash detection | M2 |
| multiple environment profiles | `axle run --profile prod` → `.env.prod` etc. | M5 |
| pre/post-launch hooks | Axle hook events: `run-start`, `run-ready`, `run-stop`, `run-crash` | M5 |
| service dependency checking | docker compose services, databases a project needs (port reachable?) | M6 |
| error log parsing, suggestions, auto-remediation | crash reasons → a fix on the line (missing module, port taken, no `node_modules`) via the `fix` module | M6 |
| btop-style monitor | `axle run top`: live table of services, CPU, memory, ports, last log lines | M7 |
| scheduled tasks | **dropped** (cron / systemd timers do this well); revisit after merge | — |
| Roman purple-and-gold theme | **dropped**: Axle's Catppuccin palette, one look. The name survives as the branch | — |

---

## How `axle run` decides

```
axle run [words]
 ├─ words given ─────────────► the project they name (j's ranking) ──┐
 ├─ in a project folder ─────► this project ─────────────────────────┤
 └─ elsewhere ───────────────► the last project you worked in ───────┤
                               (picker of recent ones if unsure)     │
                                                                      ▼
                     already running here? → say so (restart / logs / open)
                                                                      ▼
                     detect how to run it (table below)  ── none → ask, offer to remember
                                                                      ▼
                     first time for this project + command? → show it, confirm (trust)
                                                                      ▼
                     environment: venv, .env, port free? (conflict → choose)
                                                                      ▼
                     service → background, drop in the prompt, wait until it answers
                     script  → foreground, as if typed
```

"The project you worked in" = the root (`.git`, `pyproject.toml`, `package.json`, ...) of the
folders in Axle's history log, most recent first, skipping the one you're in.

---

## Detection

First match wins; each gives a command, whether it's a **service** (background) or a **task**
(foreground), and the port when known.

| Signals | Command | Kind | Default port |
|---|---|---|---|
| `docker-compose.yml` / `compose.yaml` | `docker compose up -d` (+ `logs -f` for `logs`) | service | from the file |
| `Procfile` (`web:` line) | that line | service | `$PORT` |
| `package.json` script `dev`, else `start` | `npm/pnpm/yarn/bun run dev` (lockfile decides) | service if it's a known dev server (vite, next, nuxt, astro, express, nest, remix, svelte-kit), else task | 5173 / 3000 / 4321 / ... |
| `manage.py` | `python manage.py runserver` | service | 8000 |
| Python file importing FastAPI / Starlette | `uvicorn <module>:<app> --reload` | service | 8000 |
| Python file importing Flask | `flask --app <file> run --debug` | service | 5000 |
| Python file importing Streamlit / Gradio / Dash | `streamlit run <file>` / `python <file>` | service | 8501 / 7860 / 8050 |
| `pyproject.toml` `[project.scripts]` (one) | that script | task | — |
| `main.py` / `app.py` / `__main__.py` (no server import) | `python <file>` | task | — |
| `Cargo.toml` with axum / actix-web / rocket / warp | `cargo run` | service | from code, else 3000 / 8080 / 8000 |
| `Cargo.toml` | `cargo run` | task | — |
| `go.mod` with `net/http` `ListenAndServe` / gin / echo / fiber | `go run .` | service | from code |
| `go.mod` | `go run .` | task | — |
| `Makefile` / `justfile` with `run` / `dev` / `serve` | `make run` / `just dev` | task (service if a port appears in the log) | — |
| `index.html` and nothing else | `python -m http.server` | service | 8000 |

The port is read from, in order: what's already set (`--port`, `PORT` in `.env`), the code or
config (`app.run(port=…)`, `vite.config`, `server.port`), the framework default. A service counts
as "up" when its port answers; until then the prompt shows `⏳ shop-api`.

---

## Principles

1. **Zero configuration.** It works from what's in the folder and what you've done before. A
   per-project override (M5) is for the cases detection gets wrong.
2. **Nothing from a repository runs without you seeing it first.** The first time a project's
   command runs, Axle shows it and asks; the answer is remembered per project and per command
   (a changed `package.json` script asks again), like `direnv allow`. Venvs are entered without
   their `activate` script; `.env` files are read as `KEY=value` data, never sourced. The override
   file is data too (command, port, kind), never zsh code.
3. **No cost when you're not using it.** `axle run` is lazy-loaded (0 ms at startup); running
   services reach the prompt through drops, which Benzene already polls; no daemon.
4. **Works under any prompt.** Without Benzene, the running services show in `axle run ls` and a
   one-line notice when one crashes; with Benzene, in the prompt.
5. **Leaves the system as it found it.** Background services belong to Axle's state folder, are
   listed by `axle run ls`, stopped by `axle run stop`, and cleaned up when their process is gone.
   Closing the terminal doesn't stop them (decided); `AXLE_RUN_ON_EXIT=stop` if you prefer.

---

## Milestones

Each milestone ends with its tests passing (Linux + macOS CI) and is usable on its own.

### M0 · Groundwork ✔
- Module `modules/run.zsh` (lazy), `axle run` registered, `run` in the wizard's module list
  (off by default on the branch).
- State layout (below); `_axle_run_project_root`, "last project" from the history log.
- Shared helpers moved out of their current homes so `run` can use them: Benzene's project
  markers (usable without the theme), `env`'s venv entering, `j`'s ranking.
- **Done when:** `axle run --dry-run` prints the project, root and why.

### M1 · Find and run ✔
- `axle run`, `axle run <words>`, `axle run .`: the decision flow above.
- Detection for Python, Node, Rust, Go, static sites; service vs task.
- Tasks run in the foreground in the project's venv.
- Trust on first run (confirm, remembered by project + command hash).
- **Done when:** in each sample project under `tests/fixtures/run/` the right command is chosen,
  and `axle run` from `~` returns to the last project.

### M2 · Background services
- Services start detached (`setsid`), output to a log, pid + start time recorded (no PID-reuse
  mistakes), `.env` loaded as data, venv on PATH.
- In the prompt: a drop `⚡ name :port` (link to the URL), `⏳` while starting, red if it exits
  with an error.
- `axle run ls`, `stop [name|all]`, `restart`, `logs [-f] [name]`, `open [name]` (browser:
  `wslview` / `xdg-open` / `open`).
- **Done when:** start → appears in the prompt → `ls` shows it → `stop` removes it → a crash
  turns the tab red; nothing left behind after `stop all`.

### M3 · Ports
- Port detection (code, config, `.env`, defaults); "up" check by connecting.
- Who holds a port: `/proc/net/tcp` on Linux (no subprocess), `lsof` on macOS.
- Conflict: one of yours → restart it; someone else's → stop it (asks) / next free port / cancel.
- **Done when:** two projects on the same default port both run, the second on the next port.

### M4 · More projects
- `docker compose` (up/down/logs, services in `ls`), `Procfile`, `Makefile` / `justfile`,
  pnpm / yarn / bun, Streamlit / Gradio / Dash, monorepos (several runnable folders → pick).
- **Done when:** fixtures for each pass; a monorepo asks which part.

### M5 · Your settings
- Per-project override in Axle's state, not the repo: `axle run set command "…"`, `port`,
  `kind`, `env-file` (data only).
- Profiles: `axle run --profile prod` → `.env.prod`, remembered per project.
- Hook events `run-start`, `run-ready`, `run-stop`, `run-crash` (your functions, in your config).
- Settings: `AXLE_RUN_ON_EXIT=keep|stop`, `AXLE_RUN_OPEN=0|1` (open the browser when ready),
  `AXLE_RUN_TRUST=ask|always`.
- **Done when:** an override survives a re-run and a new shell; hooks fire once each.

### M6 · When it goes wrong
- A crashed service's last lines are read for known causes: `ModuleNotFoundError: x` →
  `pip install x` (into the venv), `Cannot find module` / no `node_modules` → `npm install`,
  `address already in use` → M3's choice, missing venv → offer to create it,
  database not reachable (compose / port) → start it first.
- The suggestion goes on the line through the `fix` module (Esc Esc after a crash).
- **Done when:** each known cause in the fixtures yields the right suggestion.

### M7 · `axle run top`
- A live view (in the shell, no extra tools): each service's state, uptime, CPU, memory, port,
  and its last log lines; keys to stop / restart / open / follow logs.
- **Done when:** it redraws without flicker at 1 Hz and costs under 1% CPU.

### Merge (→ `main`)
- README section, CHANGELOG, help pages, Tab completion for every subcommand.
- Wizard: `run` offered (on by default), with its main settings.
- Security review of everything that executes or reads repository files.
- Startup cost unchanged (still ≈ 3 ms); all tests green on Linux and macOS.
- `docs/legionary/` folded into the README; the Legionary repository's README points here.

---

## Commands (planned)

```
axle run [words | path]        run this project, the one named, or the last one
axle run --dry-run             say what would run, and why
axle run --fg / --bg           force foreground / background
axle run --profile <name>      use .env.<name>
axle run ls                    running services: port, uptime, memory, URL
axle run stop [name | all]     stop one (default: this project's) or all
axle run restart [name]
axle run logs [-f] [name]
axle run open [name]           open its URL in the browser
axle run set <key> <value>     this project's override: command, port, kind, env-file
axle run forget                drop this project's override and trust
axle run top                   live monitor
```

## State

```
~/.local/state/axle/run/
  services/<name>/        pid, started (epoch + process start time), port, url, command, kind, root
  services/<name>/log     its output (rotated at 5 MB)
  trust                   project root <TAB> command hash   (approved commands)
  projects/<hash>         per-project override and profile (KEY=value data)
```

---

## Branch and versions

- Work happens on **`legionary`**, branched from `main` at v0.2.3. `main` keeps getting fixes;
  `legionary` takes them in now and then.
- Commits on the branch are named **`(legionary)vX.Y.Z - Title`**, numbered by the branch's own
  progress, independent of `main`: `(legionary)v0.1.0 - branch creation` is the first. Each
  milestone is a snapshot (M1 → v0.2.0, M2 → v0.3.0, ...), fixes within one are hotfixes.
- Merging is one release on `main`: **v0.3.0 - Legionary** (a new snapshot in `main`'s scheme).

## Open questions

1. **Name in the prompt:** `⚡ shop-api :8000`, or Legionary's ⚔ as the icon?
2. **The Legionary repository:** archive it with a pointer here once merged?

Decided: background services **keep running** when the terminal closes (`axle run stop` ends
them; `AXLE_RUN_ON_EXIT=stop` for those who prefer otherwise).
