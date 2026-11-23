# Sourced by forges/state.sh and the tracker scripts. State kept between calls: name=value lines in
# one file, the newest line for a name wins.
# kv_get <file> <name>: the value, or nothing
kv_get() { [ -f "$1" ] && sed -n "s/^$2=//p" "$1" | tail -1 || true; }
# kv_set <file> <name> <value>
kv_set() {
  { grep -v "^$2=" "$1" 2>/dev/null || true; echo "$2=$3"; } > "$1.tmp" && mv "$1.tmp" "$1"
}
