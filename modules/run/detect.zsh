# How to run a project: the detection table of docs/legionary/ROADMAP.md (M1: Python,
# Node, Rust, Go, static sites). Loaded by `axle run` when first needed.
#
# Files are only read, as text (never sourced or run), and only small ones.
#
#   _axle_run_detect <root>   status 0 when it found a way; sets:
#     _axle_run_cmd     the command, as words (run with exec, never eval)
#     _axle_run_kind    service (a server: background from M2) | task (foreground)
#     _axle_run_port    the port it listens on, when known
#     _axle_run_what    e.g. "python · FastAPI", "node · Vite (pnpm)"
#     _axle_run_reason  why, e.g. "app.py imports fastapi"
#     _axle_run_source  the text that decides what runs (e.g. the package.json script),
#                       part of what trust remembers: if it changes, `axle run` asks again
#     _axle_run_portway how its port can be changed (for a busy port): flag:<flag>,
#                       script:<flag> (a package.json script's), django, last (the last
#                       word), env:<VAR>, python (a file that starts its own server:
#                       its run() call is given the port), or empty (it can't be)
#     _axle_run_env     extra environment for it (NAME=value), e.g. a changed port
#     _axle_run_envfiles  the .env files it reads, in order (yours.zsh)
#     _axle_run_yours   which of your settings were used (yours.zsh)

# A file's text into REPLY, if it's a regular file under 256 KB. No subprocess.
_axle_run_read() {
  REPLY=''
  local -a st
  [[ -f $1 && -r $1 ]] || return 1
  zstat -A st +size -- $1 2>/dev/null && (( st[1] < 262144 )) || return 1
  IFS= read -rd '' REPLY < $1
  return 0
}

# A port written in code or config (REPLY): host:port in a string, or port=/port: N.
_axle_run_code_port() {
  setopt localoptions extendedglob
  local text=$1
  REPLY=''
  if [[ $text == (#b)*(localhost|127.0.0.1|0.0.0.0|\[::\]|\"|\')':'([0-9](#c4,5))([^0-9]*|) ]]; then
    REPLY=$match[2]
  elif [[ $text == (#b)*[^a-zA-Z_](port|PORT)[[:space:]]#[=:\(][[:space:]]#([0-9](#c4,5))([^0-9]*|) ]]; then
    REPLY=$match[2]
  fi
  [[ -n $REPLY ]]
}

# The Python to use (REPLY): the project venv's, else python3, else python.
_axle_run_python() {
  local root=$1
  if _axle_venv_find $root && [[ -x $REPLY/bin/python ]]; then
    REPLY=$REPLY/bin/python
  elif whence -p python3 >/dev/null; then REPLY=python3
  else REPLY=python
  fi
}

_axle_run_set() {
  _axle_run_kind=$1 _axle_run_port=$2 _axle_run_what=$3 _axle_run_reason=$4
}

_axle_run_detect() {
  typeset -ga _axle_run_cmd=() _axle_run_env=() _axle_run_cmd_detected=()
  typeset -g _axle_run_kind='' _axle_run_port='' _axle_run_what='' _axle_run_reason='' \
             _axle_run_source='' _axle_run_portway='' _axle_run_use_venv='' _axle_run_onfail='' \
             _axle_run_health=''
  typeset -gi _axle_run_self=0 _axle_run_worker=0
  typeset -ga _axle_run_needs_set=() _axle_run_procs=()
  local _axle_run_proc_cur=$_axle_run_proc           # (a Procfile process: _axle_run_part_dir)
  typeset -g _axle_run_proc=''
  _axle_run_yours_files $1                         # which .env files (yours.zsh)
  _axle_run_detect_any $1 && _axle_run_detect_port $1
  _axle_run_yours_apply $1                         # your settings over it
}

_axle_run_detect_any() {
  setopt localoptions extendedglob
  local root=$1 REPLY
  _axle_run_detect_compose $root  && return 0
  _axle_run_detect_procfile $root && return 0
  _axle_run_detect_node $root     && return 0
  _axle_run_detect_python $root   && return 0
  _axle_run_detect_rust $root     && return 0
  _axle_run_detect_go $root       && return 0
  _axle_run_detect_make $root     && return 0
  if [[ -f $root/index.html ]]; then
    _axle_run_python $root
    _axle_run_cmd=($REPLY -m http.server 8000)
    _axle_run_set service 8000 'static site' 'index.html'
    return 0
  fi
  return 1
}

# The port, and how to change it, for what was detected. The port already found comes
# from the command, the code or the framework's default; PORT in .env wins for programs
# that read PORT, and vite.config's server.port for Vite.
_axle_run_detect_port() {
  setopt localoptions extendedglob
  local root=$1 REPLY f
  [[ $_axle_run_kind == service ]] || return 0
  local fw=${_axle_run_what#* · }; fw=${fw% \(*\)}
  local body=$_axle_run_source
  case $_axle_run_what in
    'python · '(FastAPI|Starlette|Flask)) (( _axle_run_self )) || _axle_run_portway=flag:--port ;;
    'python · Django')                   _axle_run_portway=django ;;
    'python · Streamlit')                _axle_run_portway=flag:--server.port ;;
    'python · Gradio')                   _axle_run_portway=env:GRADIO_SERVER_PORT ;;
    'python · Dash')                     _axle_run_portway=env:PORT ;;
    'static site')                       _axle_run_portway=last ;;
    'node · '*)
      case $fw in
        Vite|Astro|Nuxt|Angular|Remix|Parcel|webpack|SvelteKit) _axle_run_portway=script:--port ;;
        Next.js|Gatsby)                                         _axle_run_portway=script:-p ;;
        *)                                                      _axle_run_portway=env:PORT ;;
      esac
      # A script that sets its own port: giving it a second one isn't safe.
      [[ $_axle_run_portway == script:* && $body == *(--port|-p)[=\ ][0-9]* ]] && _axle_run_portway=''
      if [[ $fw == Vite ]]; then
        for f in $root/vite.config.(ts|js|mjs|mts|cjs)(N.); do
          _axle_run_read $f && [[ $REPLY == *server* ]] && _axle_run_code_port "$REPLY" &&
            { _axle_run_port=$REPLY; break }
        done
      fi ;;
    'rust · '*)
      _axle_run_read $root/src/main.rs && [[ $REPLY == *env::var\(\"PORT\"\)* ]] && _axle_run_portway=env:PORT ;;
    'go · '*)
      for f in $root/*.go(N.) $root/cmd/*/*.go(N.); do
        _axle_run_read $f && [[ $REPLY == *Getenv\(\"PORT\"\)* ]] && { _axle_run_portway=env:PORT; break }
      done ;;
  esac
  if [[ $_axle_run_portway == env:PORT ]]; then
    local -a reply
    _axle_run_dotenv $root &&
      for f in $reply; do [[ $f == (#b)PORT=([0-9](#c2,5)) ]] && _axle_run_port=$match[1]; done
  fi
  return 0
}

# --- docker compose, Procfile, Makefile / justfile -------------------------------------

# docker compose: `up -d` (it runs its containers itself), `down` to stop, its logs.
_axle_run_detect_compose() {
  setopt localoptions extendedglob
  local root=$1 REPLY f line
  local -a files=($root/(compose.yaml|compose.yml|docker-compose.yml|docker-compose.yaml)(N.))
  (( ${#files} )) && _axle_run_read $files[1] || return 1
  local text=$REPLY port='' in=0
  local -i n=0
  for line in ${(f)text}; do
    [[ $line == '  '[A-Za-z0-9_.-]##:[[:space:]]# && $in == services ]] && (( n++ ))
    [[ $line == services:* ]] && in=services
    [[ $line == [A-Za-z]*:* && $line != services:* ]] && in=''
    # The first published port: "8080:80", 127.0.0.1:8080:80, - 8080:80
    [[ -z $port && $line == (#b)[[:space:]]#-[[:space:]]#[\"\']#([0-9.]##:|)([0-9](#c2,5)):[0-9]* ]] && port=$match[2]
  done
  _axle_run_cmd=(docker compose -f ${files[1]:t} up -d)
  _axle_run_source=$text
  _axle_run_set compose "$port" "docker compose ($n service${${n:#1}:+s})" ${files[1]:t}
  return 0
}

# A Procfile (Procfile.dev first: the local one, as Rails' bin/dev and overmind use): its
# web: line runs as the project; its other processes (worker:, css:, ...) are parts of it
# (_axle_run_procs), each a service of its own, up once it's been running 2 s. A line is a
# shell command line, so it runs through sh -c, like foreman. release: (a deploy step)
# isn't run.
_axle_run_detect_procfile() {
  setopt localoptions extendedglob
  local root=$1 REPLY line file want=$_axle_run_proc_cur
  local -A cmds=()
  local -a order=()
  for file in Procfile.dev Procfile; do _axle_run_read $root/$file && break; file=''; done
  [[ -n $file ]] || return 1
  for line in ${(f)REPLY}; do
    [[ $line == (#b)([A-Za-z0-9_-]##):[[:space:]]#(*) && -n ${match[2]// } ]] || continue
    [[ $match[1] == release ]] && continue
    (( ${+cmds[$match[1]]} )) || order+=($match[1])
    cmds[$match[1]]=${match[2]%%[[:space:]]#}
  done
  (( ${+cmds[web]} )) || return 1                  # (no web: not how this project runs)
  typeset -ga _axle_run_procs=(${order:#web})
  local proc=${want:-web}
  (( ${+cmds[$proc]} )) || return 1                # (a process that's gone)
  local cmd=$cmds[$proc]
  _axle_run_cmd=(sh -c $cmd)
  _axle_run_source=$cmd
  if [[ $proc == web ]]; then
    local port=5000
    if [[ $cmd == (#b)*(-p|--port|http.server)[=[:space:]]##([0-9](#c2,5))(|[^0-9]*) ]]; then port=$match[2]
    elif [[ $cmd == (#b)*[[:space:]]([0-9](#c4,5)) ]]; then port=$match[1]   # (serve.py 8080)
    elif [[ $cmd == *rails\ (s|server)* ]]; then port=3000
    fi
    _axle_run_set service $port $file "$file web: $cmd"
  else
    _axle_run_worker=1
    _axle_run_set service '' $file "$file $proc: $cmd"
  fi
  return 0
}

# A Makefile or justfile target: run, dev, serve or start (in that order).
_axle_run_detect_make() {
  setopt localoptions extendedglob
  local root=$1 REPLY t line
  local -a targets=()
  if _axle_run_read $root/justfile || _axle_run_read $root/Justfile; then
    for line in ${(f)REPLY}; do
      [[ $line == (#b)(run|dev|serve|start)([[:space:]]##[^:]#|):(|[^=]*) ]] && targets+=($match[1])
    done
    for t in run dev serve start; do
      (( ${targets[(Ie)$t]} )) || continue
      _axle_run_cmd=(just $t); _axle_run_source=$t
      _axle_run_set task '' just "justfile recipe $t"
      return 0
    done
  fi
  targets=()
  _axle_run_read $root/Makefile || _axle_run_read $root/makefile || return 1
  for line in ${(f)REPLY}; do
    [[ $line == (#b)(run|dev|serve|start)[[:space:]]#:([^=]*|) ]] && targets+=($match[1])
  done
  for t in run dev serve start; do
    (( ${targets[(Ie)$t]} )) || continue
    _axle_run_cmd=(make $t); _axle_run_source=$t
    _axle_run_set task '' make "Makefile target $t"
    return 0
  done
  return 1
}

# --- Node -------------------------------------------------------------------------

_axle_run_detect_node() {
  local root=$1 REPLY
  _axle_run_read $root/package.json || return 1
  local pkg=$REPLY pm=npm
  if   [[ -f $root/pnpm-lock.yaml ]]; then pm=pnpm
  elif [[ -f $root/yarn.lock ]]; then pm=yarn
  elif [[ -f $root/bun.lockb || -f $root/bun.lock ]]; then pm=bun
  fi
  local scripts='' name='' body=''
  [[ $pkg =~ '"scripts"[[:space:]]*:[[:space:]]*\{([^}]*)\}' ]] && scripts=$match[1]
  for name in dev start; do
    [[ $scripts =~ "\"$name\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"" ]] && { body=$match[1]; break }
  done
  local fw='' port=''
  if [[ -n $body ]]; then
    case $body in                                  # first match wins: specific ones first
      *remix*)                      fw=Remix port=3000 ;;
      *astro*)                      fw=Astro port=4321 ;;
      *nuxt*|*nuxi*)                fw=Nuxt port=3000 ;;
      *next\ *|next)                fw=Next.js port=3000 ;;
      *vite*)                       fw=Vite port=5173 ;;
      *ng\ serve*)                  fw=Angular port=4200 ;;
      *react-scripts\ start*)       fw='Create React App' port=3000 ;;
      *webpack\ serve*|*webpack-dev-server*) fw=webpack port=8080 ;;
      *nest\ start*)                fw=NestJS port=3000 ;;
      *gatsby\ develop*)            fw=Gatsby port=8000 ;;
      *parcel*)                     fw=Parcel port=1234 ;;
    esac
    # A plain node/nodemon script of a server framework.
    if [[ -z $fw && $body == *(node|nodemon|tsx|ts-node)\ * ]]; then
      _axle_run_node_server "$pkg" && fw=$REPLY port=3000
    fi
    [[ $body == (#b)*(--port|-p)[=\ ]([0-9](#c2,5))* ]] && port=$match[2]
    _axle_run_cmd=($pm run $name)
    _axle_run_source=$body
    if [[ -n $fw ]]; then
      _axle_run_set service $port "node · $fw ($pm)" "package.json script $name: $body"
    else
      _axle_run_set task '' "node ($pm)" "package.json script $name: $body"
    fi
    return 0
  fi
  # No script: the entry file.
  local main='' f
  [[ $pkg =~ '"main"[[:space:]]*:[[:space:]]*"([^"]*)"' ]] && main=$match[1]
  for f in $main server.js app.js index.js main.js; do
    [[ -n $f && $f != (/*|-*|*..*) && -f $root/$f ]] || continue
    _axle_run_cmd=(node $f)
    if _axle_run_node_server "$pkg"; then
      fw=$REPLY port=3000
      _axle_run_read $root/$f && _axle_run_code_port "$REPLY" && port=$REPLY
      _axle_run_set service $port "node · $fw" "$f, with $fw in package.json"
    else
      _axle_run_set task '' node "$f"
    fi
    return 0
  done
  return 1
}

# A server framework among a package.json's dependencies (REPLY = its name).
_axle_run_node_server() {
  local fw
  for fw in express fastify koa hono @hapi/hapi; do
    [[ $1 == *\"$fw\"[[:space:]]#:* ]] && { REPLY=$fw; return 0 }
  done
  return 1
}

# --- Python -----------------------------------------------------------------------

_axle_run_detect_python() {
  local root=$1 REPLY py
  _axle_run_python $root; py=$REPLY
  if [[ -f $root/manage.py ]]; then
    _axle_run_cmd=($py manage.py runserver)
    _axle_run_set service 8000 'python · Django' 'manage.py'
    return 0
  fi
  # Web apps: the likely entry files first, then the rest at the top and one level down.
  local -a files=($root/(main|app|server|api|asgi|wsgi|run|streamlit_app).py(N.)
                  $root/*.py(N.) $root/(app|api|src|server|backend)/*.py(N.))
  files=(${(u)files})
  # A subfolder that's a project of its own (in a monorepo) is a part, not this app.
  local sub
  for sub in $root/(app|api|src|server|backend)(N/); do
    [[ -n $sub/(pyproject.toml|requirements.txt|setup.py|Pipfile|package.json)(#qN[1]) ]] &&
      files=(${files:#$sub/*})
  done
  local f text line var='' fw='' rel
  for f in ${files[1,40]}; do
    [[ ${f:t} == -* ]] && continue                 # (would read as an option)
    _axle_run_read $f || continue
    text=$REPLY
    [[ $text == *(fastapi|starlette|flask|streamlit|gradio|dash)* ]] || continue
    fw=''
    # (The module itself, not one named after it: flask_sqlalchemy doesn't make a Flask app.)
    for line in ${(f)text}; do
      case $line in
        ([[:space:]]#(from|import)[[:space:]]##fastapi([[:space:].,]*|)) fw=FastAPI ;;
        ([[:space:]]#(from|import)[[:space:]]##starlette([[:space:].,]*|)) fw=${fw:-Starlette} ;;
        ([[:space:]]#(from|import)[[:space:]]##flask([[:space:].,]*|)) fw=${fw:-Flask} ;;
        ([[:space:]]#(from|import)[[:space:]]##streamlit([[:space:].,]*|)) fw=Streamlit ;;
        ([[:space:]]#(from|import)[[:space:]]##gradio([[:space:].,]*|)) fw=${fw:-Gradio} ;;
        ([[:space:]]#(from|import)[[:space:]]##dash([[:space:].,]*|)) fw=${fw:-Dash} ;;
      esac
    done
    [[ -n $fw ]] || continue
    rel=${f#$root/}
    local port=''
    # A file that starts the server itself under __main__ knows how it should run (it may
    # start other things first, set its host, ...): run it, not the framework's runner.
    if [[ $fw == (FastAPI|Starlette|Flask) && $text == *__name__*__main__* && $text == *(.run\(|serve\()* ]]; then
      _axle_run_self=1
      _axle_run_cmd=($py $rel)
      port=5000; [[ $fw == Flask ]] || port=8000
      local cfg envport=0
      for cfg in $f $root/(config|settings).py(N.); do
        _axle_run_read $cfg || continue
        if [[ $REPLY == (#b)*(environ.get|getenv)\([\"\']PORT[\"\'](,[[:space:]]#[\"\']#([0-9]##)|)* ]]; then
          envport=1 _axle_run_portway=env:PORT
          [[ -n $match[3] ]] && port=$match[3]
          break
        fi
      done
      # Otherwise its server's run() is given the port when it's called (python: see
      # modules/run/py/sitecustomize.py); the file itself is never changed.
      (( envport )) || { _axle_run_portway=python; _axle_run_code_port "$text" && port=$REPLY }
      # The same hook lets Flask-SocketIO's dev server start without a terminal (it
      # refuses when stdin isn't one, as in the background).
      _axle_run_env+=(PYTHONPATH=$AXLE_ROOT/modules/run/py${PYTHONPATH:+:$PYTHONPATH})
      _axle_run_set service $port "python · $fw" "$rel starts itself"
      return 0
    fi
    case $fw in
      FastAPI|Starlette)
        var=app
        for line in ${(f)text}; do
          [[ $line == (#b)([A-Za-z_][A-Za-z0-9_]#)[[:space:]]#=[[:space:]]#(fastapi.|starlette.applications.|)(FastAPI|Starlette)\(* ]] &&
            { var=$match[1]; break }
        done
        _axle_run_cmd=($py -m uvicorn ${${rel%.py}//\//.}:$var --reload)
        port=8000 ;;
      Flask)
        _axle_run_cmd=($py -m flask --app $rel run --debug)
        port=5000 ;;
      Streamlit) _axle_run_cmd=($py -m streamlit run $rel); port=8501 ;;
      Gradio)    _axle_run_cmd=($py $rel); port=7860 ;;
      Dash)      _axle_run_cmd=($py $rel); port=8050 ;;
    esac
    # A port in the code (uvicorn.run(port=…), app.run(port=…)) wins, except Streamlit's.
    if [[ $fw != Streamlit ]] && _axle_run_code_port "$text"; then
      port=$REPLY
      [[ $fw == (FastAPI|Starlette) ]] && _axle_run_cmd+=(--port $port)
      [[ $fw == Flask ]] && _axle_run_cmd+=(--port $port)
    fi
    _axle_run_set service $port "python · $fw" "$rel imports ${(L)fw}"
    return 0
  done
  # One [project.scripts] entry in pyproject.toml.
  if _axle_run_read $root/pyproject.toml; then
    local -a entries=()
    local in=0
    for line in ${(f)REPLY}; do
      if [[ $line == [[:space:]]#\[* ]]; then
        [[ $line == [[:space:]]#'[project.scripts]'* ]] && in=1 || in=0
        continue
      fi
      (( in )) && [[ $line == (#b)[[:space:]]#([A-Za-z0-9_.\"-]##)[[:space:]]#=* ]] && entries+=(${match[1]//\"/})
    done
    if (( ${#entries} == 1 )); then
      local bin=$entries[1]
      _axle_venv_find $root && [[ -x $REPLY/bin/$bin ]] && bin=$REPLY/bin/$bin
      _axle_run_cmd=($bin)
      _axle_run_source=$entries[1]
      _axle_run_set task '' python "pyproject.toml script ${entries[1]}"
      return 0
    fi
  fi
  for f in main.py app.py __main__.py; do
    [[ -f $root/$f ]] || continue
    _axle_run_cmd=($py $f)
    _axle_run_set task '' python $f
    return 0
  done
  return 1
}

# --- Rust ---------------------------------------------------------------------------

_axle_run_detect_rust() {
  local root=$1 REPLY
  _axle_run_read $root/Cargo.toml || return 1
  local toml=$REPLY line fw='' port=''
  [[ $toml == *'[package]'* ]] || return 1        # a bare workspace: its members are parts
  [[ -f $root/src/main.rs || $toml == *'[[bin]]'* || -n $root/src/bin/*.rs(#qN[1]) ]] ||
    return 1                                       # a library: nothing to run
  for line in ${(f)toml}; do
    case $line in
      ([[:space:]]#axum[[:space:]=.]*)      fw=axum port=3000 ;;
      ([[:space:]]#actix-web[[:space:]=.]*) fw=actix-web port=8080 ;;
      ([[:space:]]#rocket[[:space:]=.]*)    fw=Rocket port=8000 ;;
      ([[:space:]]#warp[[:space:]=.]*)      fw=warp port=3030 ;;
      ([[:space:]]#(#b)(poem|tide|salvo)[[:space:]=.]*) fw=$match[1] port=8080 ;;
    esac
    [[ -n $fw ]] && break
  done
  _axle_run_cmd=(cargo run)
  if [[ -n $fw ]]; then
    _axle_run_read $root/src/main.rs && _axle_run_code_port "$REPLY" && port=$REPLY
    _axle_run_set service $port "rust · $fw" "Cargo.toml depends on $fw"
  else
    _axle_run_set task '' rust 'Cargo.toml'
  fi
  return 0
}

# --- Go -----------------------------------------------------------------------------

_axle_run_detect_go() {
  local root=$1 REPLY
  _axle_run_read $root/go.mod || return 1
  local mod=$REPLY fw='' f port=''
  case $mod in
    *gin-gonic/gin*)  fw=gin ;;
    *labstack/echo*)  fw=echo ;;
    *gofiber/fiber*)  fw=fiber ;;
    *go-chi/chi*)     fw=chi ;;
    *gorilla/mux*)    fw=gorilla/mux ;;
  esac
  # The file that starts the server: its port, and (without a framework) proof it's one.
  for f in $root/*.go(N.) $root/cmd/*/*.go(N.); do
    _axle_run_read $f || continue
    if [[ $REPLY == *ListenAndServe* ]]; then
      fw=${fw:-net/http}
    elif [[ -z $fw || $REPLY != *(.Run\(|.Start\(|.Listen\()* ]]; then
      continue
    fi
    _axle_run_code_port "$REPLY" && port=$REPLY
    break
  done
  _axle_run_cmd=(go run .)
  if [[ -n $fw ]]; then
    _axle_run_set service ${port:-8080} "go · $fw" "${${fw:#net/http}:+go.mod requires $fw}${${(M)fw:#net/http}:+the code calls ListenAndServe}"
  else
    _axle_run_set task '' go 'go.mod'
  fi
  return 0
}
