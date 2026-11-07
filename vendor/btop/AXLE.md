# btop, in Axle

This folder is **btop 1.4.8** by Jakob P. Liljenberg (Aristocratos),
https://github.com/aristocratos/btop, tag `v1.4.8` (commit `cf1da59`), under the Apache
License 2.0 (`LICENSE`). Left out of the copy: `.github/`, `Img/` (screenshots), `snap/`.

Axle builds it with `tools/axle-build-btop` (from `install.sh`, or `axle top --build`) into
`bin/btop`, which `axle top` and `axle run top` run. It reads the usual btop settings.

## What Axle changed

An **Axle mode**: only the processes `axle run` started (its services, read from
`<dir>/<name>/pid`, and everything under them).

- `--axle-dir <dir>`: axle run's services folder; turns the mode on for key `A`.
- `--axle-only`: start in the mode (`axle run top`).
- Key `A` in the process box switches between the mode and all processes; the box is then
  labelled `axle` instead of `proc`. It's in the help menu (`h`).

Every changed file says so at the top ("Modified for Axle"):
`src/btop.cpp`, `src/btop_cli.{hpp,cpp}`, `src/btop_shared.{hpp,cpp}` (the mode's filter),
`src/btop_input.cpp` (key `A`), `src/btop_draw.cpp` (the label), `src/btop_menu.cpp` (help),
and the five `src/*/btop_collect.cpp` (the filter, once per update).

Also: `.gitignore` keeps btop's own `Makefile` (`!/Makefile`); its rule for CMake's generated
Makefiles would otherwise leave it out of Axle's repo.

To move to a newer btop: copy its release over this folder (keeping this file), then apply
the changes above again; `git log -- vendor/btop` shows them as Axle's own commits.
