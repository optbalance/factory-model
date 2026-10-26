# Sourced by the GitHub forge scripts. gh works on the repository behind $FORGE_REMOTE, whatever the
# current directory: GH_REPO is [HOST/]OWNER/REPO, taken from the remote's URL.
command -v gh >/dev/null || die "gh (GitHub CLI) is not installed on the host"
url=$(git -C "$PRODUCT" config --get "remote.$FORGE_REMOTE.url") || die "$PRODUCT has no remote $FORGE_REMOTE"
[[ $url =~ ^(https://|ssh://)?([^@/]+@)?([^/:]+)[:/]([^/]+)/([^/]+)$ ]] \
  || die "can't read OWNER/REPO from the URL of $FORGE_REMOTE: $url"
GH_REPO="${BASH_REMATCH[3]}/${BASH_REMATCH[4]}/${BASH_REMATCH[5]%.git}"; export GH_REPO
pr=$(state_get pr)
# remark_reviews [after-id]: ids of the reviews that carry remarks, newer than after-id, oldest
# first: anyone's "Request changes", and the pull request author's "Comment" (the factory opens it
# as you, and GitHub doesn't let you request changes on your own pull request). Someone else's
# "Comment", approvals and conversation comments are discussion, never remarks.
remark_reviews() {
  local author; author=$(gh pr view "$pr" --json author --jq .author.login)
  [[ $author =~ ^[A-Za-z0-9-]+(\[bot\])?$ ]] || die "unexpected pull request author: $author"
  gh api --paginate "repos/{owner}/{repo}/pulls/$pr/reviews" \
    --jq ".[] | select((.state == \"CHANGES_REQUESTED\" or (.state == \"COMMENTED\" and .user.login == \"$author\")) and .id > ${1:-0}) | .id" | sort -n
}
