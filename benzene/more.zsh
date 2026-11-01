# More segments for NoxA (and AxoN, which builds on it). Like the rest of Benzene, each one
# shows only when it has something to say, and none of them slows the prompt down: they
# read env vars and small files, and the few that must ask a program cache the answer
# until its data file changes.
#
#   inside    you're in a shell started from another program: ranger, yazi, nnn, lf, xplr,
#             vim/neovim (:sh, :terminal), Midnight Commander, chezmoi cd ("exit" returns)
#   direnv    an .envrc is loaded; an amber bubble when there's one direnv hasn't been
#             allowed to load (run `direnv allow`)
#   ruby java php lua perl scala flutter haskell
#             the version, when the folder is a project of that language. Pins are read
#             from .ruby-version, .java-version, .php-version, .lua-version, .perl-version,
#             .scala-version, .fvmrc, stack.yaml or .tool-versions; a version that doesn't
#             match, or one a version manager (rbenv, jenv, phpenv, luaenv, plenv,
#             scalaenv, asdf, mise, fvm) hasn't installed, is flagged in amber
#   azure     the default subscription (expanded, or when it's production)
#   ebenv     the Elastic Beanstalk environment of this folder
#   gcred     the Google service account in $GOOGLE_APPLICATION_CREDENTIALS
#   timew     what timewarrior is tracking right now, and for how long
#   task      overdue taskwarrior tasks (an amber bubble); pending ones when expanded
#   todo      open todo.txt items, when expanded
#   vpn       connected to NordVPN
#   pdhist    per-directory-history's mode, when it's not the one you start in
#   vimode    NORMAL while in vi command mode
# A toolbox or distrobox container is shown by name in the context segment.

typeset -g _axle_more_markers='Gemfile|.ruby-version|.java-version|pom.xml|build.gradle|build.gradle.kts|composer.json|.php-version|.lua-version|.luarc.json|cpanfile|Makefile.PL|.perl-version|build.sbt|.scala-version|.fvmrc|.fvm|stack.yaml|.envrc|.elasticbeanstalk'

# --- inside another program ----------------------------------------------------------

_axle_seg_inside() {
  local -a at=()
  [[ -n $RANGER_LEVEL ]]                     && at+=(ranger)
  [[ -n $YAZI_LEVEL ]]                       && at+=(yazi)
  [[ -n $NNNLVL && $NNNLVL != 0 ]]           && at+=(nnn)
  [[ -n $LF_LEVEL ]]                         && at+=(lf)
  [[ -n $XPLR_PID ]]                         && at+=(xplr)
  [[ -n $NVIM || -n $NVIM_LISTEN_ADDRESS ]]  && at+=(nvim)
  [[ -z $NVIM && -z $NVIM_LISTEN_ADDRESS && ( -n $VIM_TERMINAL || -n $VIMRUNTIME ) ]] && at+=(vim)
  [[ -n $MC_SID ]]                           && at+=(mc)
  [[ -n $CHEZMOI ]]                          && at+=(chezmoi)
  (( ${#at} )) && _axle_paint inside "$_axle_i[inside]${(j:/:)at}"
}

# --- containers: toolbox / distrobox --------------------------------------------------

# The container's name (REPLY), when it has one worth showing instead of the hostname.
_axle_container_name() {
  REPLY=''
  [[ -f /run/.toolboxenv || -n $CONTAINER_ID ]] || return 1
  REPLY=$CONTAINER_ID
  if [[ -z $REPLY && -r /run/.containerenv ]]; then
    local line
    while read -r line; do
      [[ $line == name=* ]] && { REPLY=${${line#name=}//\"/}; break }
    done < /run/.containerenv
  fi
  [[ -n $REPLY ]]
}

# --- direnv ----------------------------------------------------------------------------

# direnv's hook must run before the prompt is drawn, or the prompt sees the previous
# folder's state. When it's registered after Benzene's, move it ahead (between commands,
# not while the hooks are running), and catch up for the prompt being drawn now.
_axle_direnv_first() {
  (( $+functions[_direnv_hook] )) || return
  local -i d=${precmd_functions[(Ie)_direnv_hook]} a=${precmd_functions[(Ie)_axle_precmd]}
  (( d > a && a > 0 )) || return
  if [[ $1 == reorder ]]; then
    precmd_functions[d]=()
    precmd_functions[a,0]=(_direnv_hook)
  else
    _direnv_hook
  fi
}
_axle_direnv_reorder() { _axle_direnv_first reorder }

_axle_seg_direnv() {
  (( $+commands[direnv] )) || return
  local envrc=$_axle_markers[.envrc]
  if [[ -n $DIRENV_DIR && ( -z $envrc || ${DIRENV_DIR#-} == $envrc ) ]]; then
    _axle_paint direnv "${_axle_i[direnv]% }"
  elif [[ -n $envrc && $envrc != $HOME ]] && (( $+functions[_direnv_hook] )); then
    # The hook ran and didn't load it: direnv hasn't been allowed to.
    _axle_alarm=2
    _axle_paint warn "${_axle_i[direnv]% } blocked"
  fi
}

# --- languages -------------------------------------------------------------------------

# name -> project files | pin file | program | version flag | names in .tool-versions
typeset -gA _axle_langs=(
  ruby  'Gemfile|.ruby-version .ruby-version ruby --version ruby'
  java  'pom.xml|build.gradle|build.gradle.kts|.java-version .java-version java -version java'
  php   'composer.json|.php-version .php-version php --version php'
  lua   '.lua-version|.luarc.json .lua-version lua -v lua'
  perl  'cpanfile|Makefile.PL|.perl-version .perl-version perl --version perl'
  scala 'build.sbt|.scala-version .scala-version - - scala'
)

# The version pinned for a tool by its own file or .tool-versions, nearest first (REPLY,
# as written: "3.3.0", "openjdk64-17.0.9", "system", ...).
#   _axle_more_pin <pin file> <names in .tool-versions>
_axle_more_pin() {
  setopt localoptions extendedglob
  local pinfile=$1 names=$2 line dir=$_axle_markers[$1] tv=$_axle_markers[.tool-versions]
  REPLY=''
  if [[ -n $dir ]] && (( ${#dir} >= ${#tv} )); then
    read -r REPLY < $dir/$pinfile
  elif [[ -n $tv ]]; then
    while read -r line; do
      [[ $line == (${~names})[[:space:]]* ]] && { REPLY=${${line#*[[:space:]]}%%[[:space:]]*}; break }
    done < $tv/.tool-versions
  fi
  REPLY=${${REPLY%%[[:space:]]*}#v}
}

# Is <version> installed by the version manager whose shim <program path> is?
#   rbenv, jenv, phpenv, ...: <root>/versions/<v>; asdf, mise: <root>/installs/<tool>/<v>
_axle_shim_has() {
  local root=${1%/shims/*} tool=$2 want=$3
  [[ $want == (system|latest*|lts*|ref:*|path:*|*/*) ]] && return 0
  [[ -e $root/versions/$want || -e $root/installs/$tool/$want ]]
}

# A language segment: _axle_more_lang <name>
_axle_more_lang() {
  setopt localoptions extendedglob
  local name=$1
  local -a d=(${=_axle_langs[$name]})
  local -a files=(${(s:|:)d[1]})
  local pinfile=$d[2] prog=$d[3] flag=$d[4] tool=$d[5] want have bin
  _axle_has_marker $files .tool-versions || return
  _axle_more_pin $pinfile $tool; want=$REPLY
  [[ -z $want ]] && ! _axle_has_marker $files && return       # .tool-versions, not ours
  # The version manager's override for this shell (`rbenv shell 3.2`, ...).
  local -A mgr=(ruby RBENV_VERSION java JENV_VERSION php PHPENV_VERSION lua LUAENV_VERSION
                perl PLENV_VERSION scala SCALAENV_VERSION)
  [[ -n ${(P)mgr[$name]} ]] && want=${(P)mgr[$name]}
  [[ $prog == - ]] && prog=$name
  bin=$commands[$prog]
  if [[ $bin == */shims/* ]]; then
    # A version manager picks the version from the same pin: show it, and say when it
    # isn't installed (the command would fail).
    have=$want
    if [[ -z $have && -r ${bin%/shims/*}/version ]]; then
      read -r have < ${bin%/shims/*}/version                   # the manager's global one
    fi
    if [[ -n $want ]] && ! _axle_shim_has $bin $tool $want; then
      _axle_alarm=2
      _axle_paint $name "$_axle_i[$name]${want//\%/%%} (not installed)"
      return
    fi
    _axle_paint $name "$_axle_i[$name]${have//\%/%%}"
    return
  fi
  REPLY=''
  [[ -n $bin && $flag != - ]] && _axle_version $bin $flag
  have=$REPLY
  # Only plain version pins are checked ("3.3", "17.0.9", "openjdk-17" → 17).
  [[ $want =~ '[0-9]+(\.[0-9]+)*' ]] && want=$MATCH || want=''
  if [[ $name == java ]]; then have=${have#1.}; want=${want#1.}; fi     # 1.8 = 8
  _axle_lang $name "$have" "$want"
}

_axle_seg_ruby()  { _axle_more_lang ruby }
_axle_seg_java()  { _axle_more_lang java }
_axle_seg_php()   { _axle_more_lang php }
_axle_seg_lua()   { _axle_more_lang lua }
_axle_seg_perl()  { _axle_more_lang perl }

# Scala: running scala to ask takes a second, so without scalaenv show the version the
# build asks for (build.sbt's scalaVersion).
_axle_seg_scala() {
  local bin=$commands[scala]
  if [[ $bin == */shims/* ]] || _axle_has_marker .scala-version; then
    _axle_more_lang scala
    return
  fi
  _axle_has_marker build.sbt || return
  local f=$_axle_markers[build.sbt]/build.sbt
  _axle_cached "scala:$f" $f command sed -n \
    's/.*scalaVersion[[:space:]]*:=[[:space:]]*"\([^"]*\)".*/\1/p'
  local -a found=("${(@f)REPLY}"); local v=$found[1]; REPLY=''
  [[ -n $v ]] || return
  _axle_paint scala "$_axle_i[scala]${v//\%/%%}"
}

# Flutter, with fvm: the version this project uses (.fvmrc, .fvm/version or
# .fvm/fvm_config.json), flagged when fvm hasn't downloaded it.
_axle_seg_flutter() {
  setopt localoptions extendedglob
  local dir=${_axle_markers[.fvmrc]:-$_axle_markers[.fvm]} v='' line f
  [[ -n $dir ]] || return
  for f in $dir/.fvmrc $dir/.fvm/version $dir/.fvm/fvm_config.json; do
    [[ -r $f ]] || continue
    if [[ $f == */version ]]; then
      read -r v < $f
    else
      line=$(<$f)
      [[ $line =~ '"(flutter|flutterSdkVersion)"[[:space:]]*:[[:space:]]*"([^"]+)"' ]] && v=$match[2]
    fi
    [[ -n $v ]] && break
  done
  [[ -n $v ]] || return
  local cache=${FVM_CACHE_PATH:-${FVM_HOME:-$HOME/fvm}}
  if [[ -d $cache/versions && ! -e $cache/versions/$v ]]; then
    _axle_alarm=2
    _axle_paint flutter "$_axle_i[flutter]${v//\%/%%} (not installed)"
  else
    _axle_paint flutter "$_axle_i[flutter]${v//\%/%%}"
  fi
}

# Haskell, with stack: the snapshot (stack.yaml's resolver/snapshot).
_axle_seg_haskell() {
  _axle_has_marker stack.yaml || return
  local f=$_axle_markers[stack.yaml]/stack.yaml
  _axle_cached "stack:$f" $f command sed -n \
    's/^\(resolver\|snapshot\):[[:space:]]*\([^[:space:]#]*\).*/\2/p'
  local -a found=("${(@f)REPLY}"); local v=$found[1]; REPLY=''
  v=${${v:t}%.yaml}                       # a URL or file: its name
  [[ -n $v ]] || return
  _axle_paint haskell "$_axle_i[haskell]${v//\%/%%}"
}

# --- cloud -----------------------------------------------------------------------------

# The default subscription's name from azureProfile.json (stdout).
_axle_azure_parse() {
  setopt localoptions extendedglob
  local json chunk
  json=$(<$1) || return
  json=${json#$'\ufeff'}
  for chunk in "${(@s:"id":)json}"; do
    [[ $chunk == *'"isDefault":'[[:space:]]#true* ]] || continue
    [[ $chunk =~ '"name":[[:space:]]*"([^"]*)"' ]] && print -r -- $match[1]
    return
  done
}

# Azure's default subscription. It applies everywhere, so it shows only when expanded,
# or always when it's production.
_axle_seg_azure() {
  local f=${AZURE_CONFIG_DIR:-$HOME/.azure}/azureProfile.json
  [[ -r $f ]] || return
  _axle_cached "azure:$f" $f _axle_azure_parse || return
  local sub=$REPLY; REPLY=''
  [[ -n $sub ]] || return
  if _axle_is_prod $sub; then
    _axle_alarm=1
  else
    (( _axle_detail )) || return
  fi
  _axle_paint azure "$_axle_i[azure]${sub//\%/%%}"
}

# Elastic Beanstalk: the environment this folder deploys to (.elasticbeanstalk/config.yml).
_axle_seg_ebenv() {
  local dir=$_axle_markers[.elasticbeanstalk]
  local f=$dir/.elasticbeanstalk/config.yml
  [[ -n $dir && -r $f ]] || return
  _axle_cached "eb:$f" $f command sed -n \
    's/^[[:space:]]*environment:[[:space:]]*\([^[:space:]#]*\).*/\1/p'
  local -a found=("${(@f)REPLY}"); local env=$found[1]; REPLY=''
  [[ -n $env && $env != null ]] || return
  _axle_is_prod $env && _axle_alarm=1
  _axle_paint aws "$_axle_i[ebenv]${env//\%/%%}"
}

# The account and project of a Google credentials file (stdout: "account project").
_axle_gcred_parse() {
  local json type='' email='' project=''
  json=$(<$1) || return
  [[ $json =~ '"type":[[:space:]]*"([^"]*)"' ]]         && type=$match[1]
  [[ $json =~ '"client_email":[[:space:]]*"([^"]*)"' ]] && email=$match[1]
  [[ $json =~ '"project_id":[[:space:]]*"([^"]*)"' ]]   && project=$match[1]
  [[ -n $project ]] || project=${${email#*@}%%.*}
  print -r -- "${${email%%@*}:-${type:-?}} $project"
}

# Google application credentials: "sa deployer@shop-prod".
_axle_seg_gcred() {
  local f=$GOOGLE_APPLICATION_CREDENTIALS
  [[ -n $f && -r $f ]] || return
  _axle_cached "gcred:$f" $f _axle_gcred_parse || return
  local -a w=(${=REPLY}); REPLY=''
  (( ${#w} )) || return
  _axle_is_prod "$w[2]" && _axle_alarm=1
  _axle_paint gcloud "$_axle_i[gcred]${w[1]//\%/%%}${w[2]:+@${w[2]//\%/%%}}"
}

# --- time and tasks --------------------------------------------------------------------

# timewarrior: what's being tracked, and for how long ("⏱ client-x 1h05m").
_axle_seg_timew() {
  setopt localoptions extendedglob
  local db=${TIMEWARRIORDB:-$HOME/.timewarrior}
  [[ -d $db/data ]] || db=${XDG_DATA_HOME:-$HOME/.local/share}/timewarrior
  local -a files=($db/data/<->-<->.data(N.om[1]))
  (( ${#files} )) || return
  local -a lines=("${(@f)$(<$files[1])}")
  local line=${lines[-1]}
  # Open interval: "inc 20261031T090000Z # tag1 tag2" (a closed one has " - <end>").
  [[ $line == (#b)inc\ ([0-9](#c8)T[0-9](#c6))Z(|\ \#\ (*)) ]] || return
  local stamp=$match[1] tags=${match[3]//\"/}
  local -i start
  local -x TZ=UTC0
  strftime -r -s start %Y%m%dT%H%M%S $stamp 2>/dev/null || return
  (( ${#tags} > 24 )) && tags="${tags[1,23]}…"
  _axle_fmt_duration $(( EPOCHSECONDS - start ))
  local took=${REPLY%.*}
  [[ $took == <-> ]] && took=${took}s
  _axle_paint timew "$_axle_i[timew]${tags:+${tags//\%/%%} }$took"
}

# taskwarrior counts (stdout: "pending overdue"); asked again when its data changes.
_axle_task_counts() {
  local -a rc=(rc.verbose=nothing rc.hooks=off rc.gc=off rc.confirmation=off)
  local p o
  p=$(command task $rc +PENDING count 2>/dev/null </dev/null)
  o=$(command task $rc +OVERDUE count 2>/dev/null </dev/null)
  print -r -- "${p:-0} ${o:-0}"
}

# taskwarrior: overdue tasks always (amber); pending ones when expanded.
_axle_seg_task() {
  (( $+commands[task] )) || return
  local data=${TASKDATA:-$HOME/.task} f hour
  f=$data/pending.data
  [[ -r $f ]] || f=$data/taskchampion.sqlite3
  [[ -r $f ]] || return
  strftime -s hour %Y%m%d%H $EPOCHSECONDS      # tasks become overdue as time passes
  _axle_cached "task:$f:$hour" $f _axle_task_counts || return
  local -a n=(${=REPLY}); REPLY=''
  local -i pending=${n[1]:-0} overdue=${n[2]:-0}
  if (( overdue )); then
    _axle_alarm=2
    _axle_paint task "$_axle_i[task]$overdue overdue"
  elif (( _axle_detail && pending )); then
    _axle_paint task "$_axle_i[task]$pending"
  fi
}

# Open todo.txt items (lines not marked done with "x "), when expanded.
_axle_seg_todo() {
  (( _axle_detail )) || return
  local f
  for f in $TODO_FILE ${TODO_DIR:+$TODO_DIR/todo.txt} $HOME/.todo/todo.txt $HOME/todo.txt; do
    [[ -r $f ]] && break
    f=''
  done
  [[ -n $f ]] || return
  local -a items=(${(f)"$(<$f)"})
  items=(${items:#x *})
  items=(${items:#[[:space:]]#})
  (( ${#items} )) && _axle_paint todo "$_axle_i[todo]${#items}"
}

# --- network, history, keys -------------------------------------------------------------

# Connected to NordVPN (its NordLynx or OpenVPN interface is up).
_axle_seg_vpn() {
  [[ -e /sys/class/net/nordlynx || -e /sys/class/net/nordtun ]] || return
  _axle_paint vpn "${_axle_i[vpn]}nord"
}

# per-directory-history (oh-my-zsh plugin): which history Up searches, when it's not the
# one you start in (Ctrl-G switches); both when expanded.
_axle_seg_pdhist() {
  (( ${+_per_directory_history_is_global} )) || return
  local now=local start=local
  [[ $_per_directory_history_is_global == true ]] && now=global
  [[ ${HISTORY_START_WITH_GLOBAL:-false} == true ]] && start=global
  [[ $now != $start ]] || (( _axle_detail )) || return
  _axle_paint pdhist "$_axle_i[pdhist]$now"
}

# vi mode: NORMAL while in command mode (the arrow also turns to an outline).
_axle_seg_vimode() {
  [[ $_axle_keymap == vicmd ]] && REPLY="%B%F{$_axle_c[vimode]}NORMAL%f%b"
}

# --- hooks -----------------------------------------------------------------------------

autoload -Uz add-zsh-hook
add-zsh-hook preexec _axle_direnv_reorder
