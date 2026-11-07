# Folder ranking: where you actually work, weighted by how often and how recently, from
# the history log. Used by `j` (jump) and `axle run <words>`; loaded when first used.

zmodload zsh/mathfunc 2>/dev/null

typeset -gA _axle_jump_count _axle_jump_last
typeset -g  _axle_jump_mtime=''

# Folder statistics from the history log, recomputed only when the log has changed.
_axle_jump_load() {
  local -a st
  zstat -A st +mtime -- $_axle_hist_file 2>/dev/null || return 1
  [[ $st[1] == $_axle_jump_mtime ]] && return 0
  _axle_jump_mtime=$st[1]
  _axle_jump_count=() _axle_jump_last=()
  local dir n last
  # (only well-formed records: the numbers are used in arithmetic, which would run code)
  command awk -F'\t' 'NF == 6 && $1 ~ /^[0-9]+$/ { n[$4]++; if ($1 > l[$4]) l[$4] = $1 }
                      END { for (d in n) print n[d] "\t" l[d] "\t" d }' $_axle_hist_file |
  while IFS=$'\t' read -r n last dir; do
    [[ $n == <-> && $last == <-> ]] || continue
    _axle_jump_count[$dir]=$n _axle_jump_last[$dir]=$last
  done
}

# Folders matching the words, best first (reply=()).
_axle_jump_rank() {
  setopt localoptions extendedglob
  _axle_jump_load
  local -a words=("$@") scored
  local dir pat='(#i)*' w
  for w in $words; do pat+="${(b)w}*"; done
  local last=${(b)words[-1]}
  local -i age
  local -F score
  for dir in ${(k)_axle_jump_count}; do
    [[ $dir != $PWD ]] || continue
    if (( ${#words} )); then
      [[ $dir == ${~pat} && ${dir:t} == (#i)*$~last* ]] || continue
    fi
    [[ -d $dir ]] || continue
    age=$(( EPOCHSECONDS - ${_axle_jump_last[$dir]} ))
    score=${_axle_jump_count[$dir]}
    if   (( age < 3600 ));   then (( score *= 4 ))
    elif (( age < 86400 ));  then (( score *= 2 ))
    elif (( age < 604800 )); then (( score *= 0.5 ))
    else                          (( score *= 0.25 ))
    fi
    scored+=("${(l:12::0:)$(( int(score * 100) ))}"$'\x1f'"$dir")
  done
  reply=("${(@)${(@O)scored}#*$'\x1f'}")
  (( ${#scored} )) || reply=()
}
