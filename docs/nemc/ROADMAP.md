# The `MnemoCetus` branch: Axle × MnemoCetus

MnemoCetus stays a separate project. This long-lived branch is Axle's compat with it: `main`
plus whatever makes the two work together. It's never merged back into `main`.

The folder is `~/repos/axle-nemc`; the branch is `MnemoCetus`, locally and on GitHub.

## Rules

1. **Follows `main` by merging, never rebasing.** Users' `axle update` is `git pull --ff-only`,
   so a rewritten branch would break it. Merge `main` in after each `main` release.
2. **Inert without nemc.** Everything checks for nemc when it's used, so a user who removes it
   has a plain Axle.
3. **Small surface in shared files.** New code goes in `lib/nemc*.zsh`, which both the tool and
   the theme load, and which a one-part install keeps. Existing files get one-line calls, so
   merges from `main` stay clean. New `main` releases must not need nemc changes to pass tests.
4. **The prompt never waits on nemc.** It reads from memory; Python runs in the background.
5. **Axle adapts to nemc, through a small contract:** `status --json --budget` (`state`,
   `findings`), `--version`, and the hook name `__nemc_precmd`. Changing these in MnemoCetus
   means changing this branch. Doctor checks the version.

`main`'s `install.sh` carries the same MnemoCetus question, since that's where users start.
Port it with `git checkout MnemoCetus -- install.sh` when it changes.

## Versions

Commits are `(MnemoCetus)vX.Y.Z - Title`, numbered by the branch's own progress (`AXLE_NEMC_COMPAT`).
`AXLE_VERSION` stays `main`'s, so update notices keep making sense.

## Done

- **v0.3.0:** `git push` asks first where nemc has stored security findings; `j` finds the
  projects nemc has scanned.
- **v0.2.0:** `nemc` itself runs through Axle (prompt refresh, hook events `nemc-start` /
  `nemc-done`); never runs a `nemc` that came with a project (its `.venv`, or `.` on PATH).
- **v0.1.3:** the wizard test no longer races on slow machines (macOS CI).
- **v0.1.2:** the wizard offers the segment; `axle preview` shows its states.
- **v0.1.1:** tested with real uv and pipx installs; clearer installer and update messages.
- **v0.1:** `axle nemc`, the Benzene segment, stand-down of nemc's light, the install choice,
  doctor, settings.

## Ideas

- A drop while a scan runs, and on new findings after `nemc rescan`.
- `axle run` (once Legionary lands on `main`) using nemc's project list and categories.
- Alt-i shows nemc's `reason`; a stale-scan note from `scanned_at`.
- `fix` suggests `nemc reclaim` on "No space left on device".
- After `pip`/`npm install`: `nemc audit` in the background (opt-in: it uses the network).
- After `git clone`: suggest `nemc scan` of the new folder.
- `axle stats` beside nemc's project data: where you work against what's bloated or stale.
- A `nemc status --porcelain` in MnemoCetus, for a contract that isn't JSON by regex.
