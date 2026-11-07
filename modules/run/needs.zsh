# axle run: what a service needs, started first. A database it talks to (from its .env:
# DATABASE_URL=postgres://...@localhost:5432/..., REDIS_URL=redis://localhost, ...) that
# isn't answering, and that the project's compose file has: `docker compose up -d <it>`,
# then a wait for its port (up to 30 s). Or say it: `axle run set needs db redis` (compose
# services, started each time; compose leaves running ones as they are).
#
# Starting it runs the project's compose file, so it's asked the first time (like any of the
# project's commands; --yes or AXLE_RUN_TRUST=always don't ask). Without docker, or a
# compose service for it, it's said, and the service runs anyway.

typeset -gA _axle_run_db_ports=(postgres 5432 mysql 3306 redis 6379 mongodb 27017 rabbitmq 5672)

# The databases <dir>'s .env points at on this machine (reply: kind:port ...).
_axle_run_needs_env() {
  local dir=$1 e v kind port
  local -a envs found=()
  _axle_run_dotenv $dir && envs=($reply)
  for e in $envs; do
    v=${e#*=}; v=${${v#[\"\']}%[\"\']}
    [[ $v =~ '^([a-z]+)(\+[a-z0-9]+)?://([^@/]*@)?(localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\])(:([0-9]+))?' ]] || continue
    case $match[1] in
      postgres|postgresql) kind=postgres ;;
      mysql|mariadb)       kind=mysql ;;
      redis|rediss)        kind=redis ;;
      mongodb)             kind=mongodb ;;
      amqp|amqps)          kind=rabbitmq ;;
      *) continue ;;
    esac
    port=${match[6]:-$_axle_run_db_ports[$kind]}
    (( ${found[(Ie)$kind:$port]} )) || found+=($kind:$port)
  done
  reply=($found)
  (( ${#reply} ))
}

# The compose file for <dir> (REPLY): in it, or a folder above up to its project's root.
_axle_run_needs_compose() {
  local d=$1 root=$1 f
  local -a reply
  _axle_project_root $1 && root=$reply[1]
  while :; do
    for f in $d/(compose.yaml|compose.yml|docker-compose.yml|docker-compose.yaml)(N.); do
      REPLY=$f; return 0
    done
    [[ $d == $root || $d == / || $d == $HOME ]] && break
    d=${d:h}
  done
  return 1
}

# Start what <dir>'s service needs (always status 0: the service runs anyway).
_axle_run_needs() {
  local dir=$1 name=$2 yes=$3 REPLY compose='' svc kind port
  local muted=${_axle_c[muted]:-244} warn=${_axle_c[warn]:-yellow}
  local -a start=() wait=() said=() reply
  _axle_run_needs_compose $dir && compose=$REPLY
  # Said: compose services, each time.
  for svc in $_axle_run_needs_set; do start+=($svc); done
  # From .env: the ones not answering.
  if _axle_run_needs_env $dir; then
    for kind in $reply; do
      port=${kind#*:} kind=${kind%%:*}
      _axle_run_port_up $port && continue
      if [[ -n $compose ]] && _axle_run_compose_db $compose $kind; then
        (( ${start[(Ie)$REPLY]} )) || start+=($REPLY)
        wait+=($port) said+=("$kind :$port ($REPLY)")
      else
        _axle_printp "%F{$warn}!%f ${name//\%/%%} uses $kind on :$port, which isn't answering${compose:+ (and ${compose:t} has no $kind)}"
      fi
    done
  fi
  (( ${#start} )) || return 0
  if [[ -z $compose ]]; then
    _axle_printp "%F{$warn}!%f ${name//\%/%%} needs ${(j:, :)start}, but there's no compose file to start it from"
    return 0
  fi
  if ! (( $+commands[docker] )); then
    _axle_printp "%F{$warn}!%f ${name//\%/%%} needs ${(j:, :)start} (${compose:t}), but docker isn't installed"
    return 0
  fi
  # The first time: asked (it's the project's compose file that runs).
  local text=''
  _axle_run_read $compose && text=$REPLY
  _axle_run_hash "needs"$'\0'"$compose"$'\0'"${(j:\0:)start}"$'\0'"$text"
  local key="$compose"$'\t'"needs:$REPLY"
  if ! _axle_run_trusted $key; then
    if (( ! yes )) && [[ $AXLE_RUN_TRUST != always ]]; then
      axle_confirm "Start ${(j:, :)start} first?  docker compose up -d ${(j: :)start} (${compose:t})" y || return 0
    fi
    _axle_run_trust $key
  fi
  _axle_printp "%F{$muted}▶ docker compose up -d ${(j: :)start}  (what ${name//\%/%%} needs${said:+: ${(j:, :)said}})%f"
  ( cd -- ${compose:h} && command docker compose -f ${compose:t} up -d $start ) 2>&1 | sed 's/^/  /'
  # Then its port, up to 30 s.
  local -i i
  for port in $wait; do
    for i in {1..120}; do _axle_run_port_up $port && break; zselect -t 25; done
    _axle_run_port_up $port || _axle_printp "%F{$warn}!%f :$port still isn't answering; starting ${name//\%/%%} anyway"
  done
  return 0
}
