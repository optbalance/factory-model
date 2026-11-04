# Sourced by bin/start and bin/sandbox. The factory's secrets: NAME=value lines in $factory_env, mode 600.
factory_env="${FACTORY_ENV:-$HOME/.config/factory/env}"
# factory_env_load <name>...: export each name that is unset or empty from $factory_env. Values
# already in the environment win. A sandbox can't rely on the environment alone: the orchestrator's
# harness (Claude Code) doesn't pass its own token, CLAUDE_CODE_OAUTH_TOKEN, to the shells it runs.
factory_env_load() {
  local n v
  [ -r "$factory_env" ] || return 0
  for n in "$@"; do
    [ -z "${!n:-}" ] || continue
    v=$(set -a; . "$factory_env" > /dev/null; printf '%s' "${!n:-}")
    [ -z "$v" ] || export "$n=$v"
  done
}
