# AI status module: one small dot per AI service, green when operational, amber when
# degraded, red when down, grey when unknown. Shown only in the expanded view (Alt-i).
#
#   AXLE_AI_STATUS=(claude)                 services to watch (default: claude)
#   AXLE_AI_STATUS=(claude openai ollama 'mybox=http://192.168.1.20:8080/health')
#   AXLE_AI_STATUS_INTERVAL=180             seconds between status-page checks
#   AXLE_AI_LOCAL_INTERVAL=30               seconds between local-server checks
#
# Built in:
#   status pages   claude openai gemini mistral cohere perplexity groq copilot huggingface
#   local servers  ollama lmstudio llamacpp jan vllm
#   custom         name=URL: a status page (Statuspage or Better Uptime JSON, or just the
#                  page's base URL) is read for its state; any other URL is "up" on HTTP 2xx
#
# Checks run in a background job, never at prompt time, and results are cached in
# ~/.cache/axle/aistatus/ and shared by every shell, so only one shell per interval
# actually asks. Each dot links to its status page (Ctrl+click). `axle ai` prints details.
#
# Module contract: defines _axle_seg_aistatus (a segment), registers _axle_* hooks, and
# _axle_cleanup_aistatus; reads _axle_c / _axle_link / _axle_render when the variant has them.

(( ${+AXLE_AI_STATUS} )) || typeset -ga AXLE_AI_STATUS=(claude)
: ${AXLE_AI_STATUS_INTERVAL:=180} ${AXLE_AI_LOCAL_INTERVAL:=30}

# name -> "kind  check-url  page-url"
typeset -gA _axle_ai_known=(
  claude      'statuspage https://status.claude.com'
  openai      'statuspage https://status.openai.com'
  mistral     'statuspage https://status.mistral.ai'
  cohere      'statuspage https://status.cohere.com'
  perplexity  'statuspage https://status.perplexity.com'
  groq        'statuspage https://groqstatus.com'
  copilot     'component https://www.githubstatus.com#Copilot'
  huggingface 'betteruptime https://status.huggingface.co'
  gemini      'gcloud https://status.cloud.google.com#Vertex Gemini API'
  ollama      'local http://localhost:11434/api/version'
  lmstudio    'local http://localhost:1234/v1/models'
  llamacpp    'local http://localhost:8080/health'
  jan         'local http://localhost:1337/v1/models'
  vllm        'local http://localhost:8000/health'
)

typeset -gA _axle_ai_state _axle_ai_desc _axle_ai_mtime
typeset -g  _axle_ai_fd=''
typeset -g  _axle_ai_dir=${XDG_CACHE_HOME:-$HOME/.cache}/axle/aistatus

# Resolve a configured entry to "name kind url" in reply=().
_axle_ai_resolve() {
  local entry=$1 name url
  if [[ $entry == *=* ]]; then
    name=${entry%%=*}; url=${entry#*=}
    reply=($name custom $url)
  elif (( ${+_axle_ai_known[$entry]} )); then
    url=${_axle_ai_known[$entry]}             # "kind url"; the url may contain spaces
    reply=($entry ${url%% *} ${url#* })
  else
    reply=()
  fi
}

# Colour for a state.
_axle_ai_colour() {
  case $1 in
    up)       REPLY=${_axle_c[ok]:-green} ;;
    degraded) REPLY=${_axle_c[warn]:-yellow} ;;
    down)     REPLY=${_axle_c[error]:-red} ;;
    *)        REPLY=${_axle_c[muted]:-244} ;;
  esac
}

# --- checking (runs in the background job) -----------------------------------

# Map a fetched body to up/degraded/down/unknown plus a description. Sets reply=(state desc).
_axle_ai_parse() {
  local kind=$1 body=$2 extra=$3
  case $kind in
    statuspage)
      if [[ $body =~ '"indicator":"([a-z]+)"(,"description":"([^"]*)")?' ]]; then
        local ind=$match[1] desc=$match[3]
        case $ind in
          none)                reply=(up "${desc:-Operational}") ;;
          minor|maintenance)   reply=(degraded "${desc:-$ind}") ;;
          *)                   reply=(down "${desc:-$ind}") ;;
        esac
        return 0
      fi ;;
    component)
      if [[ $body =~ "\"name\":\"$extra\",\"status\":\"([a-z_]+)\"" ]]; then
        case $match[1] in
          operational)                                       reply=(up "$extra: operational") ;;
          degraded_performance|partial_outage|under_maintenance) reply=(degraded "$extra: ${match[1]//_/ }") ;;
          *)                                                 reply=(down "$extra: ${match[1]//_/ }") ;;
        esac
        return 0
      fi ;;
    betteruptime)
      if [[ $body =~ '"aggregate_state":"([a-z]+)"' ]]; then
        case $match[1] in
          operational)          reply=(up Operational) ;;
          degraded|maintenance) reply=(degraded $match[1]) ;;
          *)                    reply=(down $match[1]) ;;
        esac
        return 0
      fi ;;
  esac
  reply=(unknown "unrecognised response")
  return 1
}

# Check one service and write its cache file: "state<TAB>description".
_axle_ai_check() {
  setopt localoptions extendedglob
  local name=$1 kind=$2 url=$3 body extra=${3#*\#} base=${3%%\#*}
  local -a reply
  case $kind in
    statuspage)
      body=$(command curl -fsSL -m 8 "$base/api/v2/status.json" 2>/dev/null) &&
        _axle_ai_parse statuspage "$body" || reply=(unknown "status page unreachable") ;;
    component)
      body=$(command curl -fsSL -m 8 "$base/api/v2/components.json" 2>/dev/null) &&
        _axle_ai_parse component "$body" "$extra" || reply=(unknown "status page unreachable") ;;
    betteruptime)
      body=$(command curl -fsSL -m 8 "$base/index.json" 2>/dev/null) &&
        _axle_ai_parse betteruptime "$body" || reply=(unknown "status page unreachable") ;;
    gcloud)
      # Ongoing Google Cloud incidents (no end time) that affect the product.
      body=$(command curl -fsSL -m 10 "$base/incidents.json" 2>/dev/null) && (( $+commands[python3] )) &&
        reply=("${(@f)$(print -r -- $body | command python3 -I -c '
import json, sys
product = sys.argv[1]
live = [i for i in json.load(sys.stdin) if not i.get("end")
        and any(p.get("title") == product for p in i.get("affected_products", []))]
if not live: print("up"); print(product + ": no incidents")
else:
    worst = "down" if any(i.get("severity") == "high" for i in live) else "degraded"
    print(worst); print(live[0].get("external_desc", "incident").splitlines()[0][:80])
' "$extra" 2>/dev/null)}") && (( ${#reply} == 2 )) || reply=(unknown "status feed unreachable") ;;
    local)
      local gw=''
      [[ -n $WSL_DISTRO_NAME ]] && gw=$(_axle_ai_wsl_host)
      if command curl -fsS -m 2 -o /dev/null "$base" 2>/dev/null; then
        reply=(up "answering at $base")
      elif [[ -n $gw ]] && command curl -fsS -m 2 -o /dev/null "${base/localhost/$gw}" 2>/dev/null; then
        reply=(up "answering on the Windows host ($gw)")   # server runs on the Windows side
      else
        reply=(down "not answering at $base")
      fi ;;
    custom)
      if [[ $base == (#i)http(s|)://[^/]##(/|) ]]; then    # bare status-page URL
        body=$(command curl -fsSL -m 8 "${base%/}/api/v2/status.json" 2>/dev/null) &&
          _axle_ai_parse statuspage "$body" ||
          { body=$(command curl -fsSL -m 8 "${base%/}/index.json" 2>/dev/null) &&
            _axle_ai_parse betteruptime "$body" } || reply=(unknown "status page unreachable")
      elif body=$(command curl -fsSL -m 8 "$base" 2>/dev/null); then
        _axle_ai_parse statuspage "$body" || _axle_ai_parse betteruptime "$body" ||
          reply=(up "HTTP OK")
      else
        reply=(down "not answering at $base")
      fi ;;
  esac
  print -r -- "$reply[1]"$'\t'"$reply[2]" > $_axle_ai_dir/$name.$$ && mv -f $_axle_ai_dir/$name.$$ $_axle_ai_dir/$name
}

# The Windows host's address as seen from WSL (NAT mode): the default gateway.
_axle_ai_wsl_host() {
  local iface dest gw rest
  while read -r iface dest gw rest; do
    [[ $dest == 00000000 ]] || continue
    REPLY="$(( 16#${gw[7,8]} )).$(( 16#${gw[5,6]} )).$(( 16#${gw[3,4]} )).$(( 16#${gw[1,2]} ))"
    print -r -- $REPLY; return 0
  done < /proc/net/route
  return 1
}

# Background job: check every stale service in parallel, then report "done".
_axle_ai_worker() {
  setopt localoptions extendedglob          # also covers _axle_ai_check, called from here
  local entry
  local -a reply
  for entry in $AXLE_AI_STATUS; do
    _axle_ai_resolve $entry; (( ${#reply} )) || continue
    local name=$reply[1] kind=$reply[2] url=$reply[3]
    _axle_ai_stale $name $kind || continue
    # One shell at a time per service; a lock older than a minute is abandoned.
    local lock=$_axle_ai_dir/$name.lock
    local -a abandoned=($lock(N/mm+1))
    (( ${#abandoned} )) && rmdir $lock 2>/dev/null
    mkdir $lock 2>/dev/null || continue
    { _axle_ai_check $name $kind $url; rmdir $lock 2>/dev/null } &
  done
  wait
  print done
}

# Is a service's cached result older than its interval?
_axle_ai_stale() {
  local -a st
  local -i every=$AXLE_AI_STATUS_INTERVAL
  [[ $2 == local ]] && every=$AXLE_AI_LOCAL_INTERVAL
  zstat -A st +mtime -- $_axle_ai_dir/$1 2>/dev/null || return 0
  (( EPOCHSECONDS - st[1] >= every ))
}

# --- shell side --------------------------------------------------------------

# Load cached results that changed (written by this or any other shell).
_axle_ai_load() {
  local entry line
  local -a reply st
  for entry in $AXLE_AI_STATUS; do
    _axle_ai_resolve $entry; (( ${#reply} )) || continue
    zstat -A st +mtime -- $_axle_ai_dir/$reply[1] 2>/dev/null || continue
    [[ ${_axle_ai_mtime[$reply[1]]} == $st[1] ]] && continue
    _axle_ai_mtime[$reply[1]]=$st[1]
    IFS= read -r line < $_axle_ai_dir/$reply[1] || continue
    _axle_ai_state[$reply[1]]=${line%%$'\t'*}
    _axle_ai_desc[$reply[1]]=${line#*$'\t'}
  done
}

_axle_ai_stop() {
  [[ -n $_axle_ai_fd ]] || return
  zle -F $_axle_ai_fd 2>/dev/null
  exec {_axle_ai_fd}<&-
  _axle_ai_fd=''
}

# precmd: pick up results, and start a check if anything is due.
_axle_aistatus_precmd() {
  (( ${#AXLE_AI_STATUS} )) || return
  _axle_ai_load
  [[ -n $_axle_ai_fd ]] && return            # a check is already running
  local entry due=0
  local -a reply
  for entry in $AXLE_AI_STATUS; do
    _axle_ai_resolve $entry; (( ${#reply} )) || continue
    _axle_ai_stale $reply[1] $reply[2] && { due=1; break }
  done
  (( due && $+commands[curl] )) || return
  mkdir -p $_axle_ai_dir 2>/dev/null
  if (( $+builtins[zle] )); then
    exec {_axle_ai_fd}< <(_axle_ai_worker 2>/dev/null)
    zle -F $_axle_ai_fd _axle_ai_done
  else
    _axle_ai_worker >/dev/null 2>&1 &!
  fi
}

# zle -F callback: the check finished; load it and redraw if the dots are on screen.
_axle_ai_done() {
  local fd=$1 line
  [[ $fd == $_axle_ai_fd ]] || { zle -F $fd; exec {fd}<&-; return }
  IFS= read -r -u $fd line
  _axle_ai_stop
  _axle_ai_load
  if (( ${_axle_detail:-0} )) && (( $+functions[_axle_render] )); then
    _axle_render
    zle reset-prompt
  fi
}

# The segment: a dot per service, only while the prompt is expanded.
_axle_seg_aistatus() {
  (( ${_axle_detail:-0} && ${#AXLE_AI_STATUS} )) || return
  local entry dot dots='' sep=''
  local -a reply
  for entry in $AXLE_AI_STATUS; do
    _axle_ai_resolve $entry; (( ${#reply} )) || continue
    _axle_ai_colour ${_axle_ai_state[$reply[1]]:-unknown}
    dot="%F{$REPLY}●%f"
    if (( $+functions[_axle_link] )); then
      _axle_link ${reply[3]%%\#*} $dot; dot=$REPLY      # Ctrl+click opens the status page
    fi
    dots+="$sep$dot"; sep=' '
  done
  REPLY=$dots
}

# `axle ai`: a table of every watched service.
_axle_aistatus_report() {
  _axle_ai_load
  local entry state age
  local -a reply st
  for entry in $AXLE_AI_STATUS; do
    _axle_ai_resolve $entry
    if (( ! ${#reply} )); then
      local -a known=(${(ok)_axle_ai_known})
      print -r -- "  ?  ${(r:12:)entry} unknown service (built in: $known)"; continue
    fi
    state=${_axle_ai_state[$reply[1]]:-unknown}
    age='never checked'
    zstat -A st +mtime -- $_axle_ai_dir/$reply[1] 2>/dev/null && age="checked $(( EPOCHSECONDS - st[1] ))s ago"
    _axle_ai_colour $state
    _axle_printp "  %F{$REPLY}●%f ${(r:12:)reply[1]} ${(r:9:)state} ${(r:46:)${_axle_ai_desc[$reply[1]]//\%/%%}} %F{${_axle_c[muted]:-244}}$age%f"
  done
}

_axle_cleanup_aistatus() {
  _axle_ai_stop
}

_axle_ai_load
add-zsh-hook precmd _axle_aistatus_precmd
