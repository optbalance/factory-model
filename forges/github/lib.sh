# Sourced by the GitHub forge scripts. gh works on the repository behind $FORGE_REMOTE, whatever the
# current directory: GH_REPO is [HOST/]OWNER/REPO, taken from the remote's URL.
command -v gh >/dev/null || die "gh (GitHub CLI) is not installed on the host"
url=$(git -C "$PRODUCT" config --get "remote.$FORGE_REMOTE.url") || die "$PRODUCT has no remote $FORGE_REMOTE"
[[ $url =~ ^(https://|ssh://)?([^@/]+@)?([^/:]+)[:/]([^/]+)/([^/]+)$ ]] \
  || die "can't read OWNER/REPO from the URL of $FORGE_REMOTE: $url"
GH_REPO="${BASH_REMATCH[3]}/${BASH_REMATCH[4]}/${BASH_REMATCH[5]%.git}"; export GH_REPO
pr=$(state_get pr)
# changes_requested [after-id]: ids of the "Request changes" reviews newer than after-id, oldest first
changes_requested() {
  gh api --paginate "repos/{owner}/{repo}/pulls/$pr/reviews" \
    --jq ".[] | select(.state == \"CHANGES_REQUESTED\" and .id > ${1:-0}) | .id" | sort -n
}
