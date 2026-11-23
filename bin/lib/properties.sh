# Sourced by bin/forge (and bin/tracker). A product's factory.properties (product contract, Step 6),
# as committed on main, so a branch can't change it for itself. Parsed, never sourced: it is product
# content, and this runs on the host.
# This file only parses. Each reader asks for its own keys, with their defaults and value patterns,
# and ignores the rest, so a new module adds keys without changing this file or the other readers.
# A misspelled key is ignored too: its default applies.
declare -A PROPS=()

# props_load <product-dir>: reads key=value lines into PROPS; comments and blank lines are skipped.
props_load() {
  local line n=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1)); line=${line%%#*}
    line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
    [ -n "$line" ] || continue
    [[ $line =~ ^([A-Za-z0-9._-]+)[[:space:]]*=[[:space:]]*(.*)$ ]] \
      || { echo "factory.properties line $n: expected key=value" >&2; return 1; }
    PROPS[${BASH_REMATCH[1]}]=${BASH_REMATCH[2]}
  done < <(git -C "$1" show main:factory.properties 2>/dev/null || true)
}

# props_get <key> <default> <pattern>: prints the key's value, or the default, if it matches the
# reader's pattern (a bash regex, anchored by the caller).
props_get() {
  local v=${PROPS[$1]:-$2}
  [[ $v =~ $3 ]] || { echo "factory.properties: $1 doesn't match $3: '$v'" >&2; return 1; }
  printf '%s\n' "$v"
}
