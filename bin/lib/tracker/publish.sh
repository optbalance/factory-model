# Sourced by bin/tracker, which has checked the arguments and set PRODUCT, TRACKER_STATE and t().
# publish <story> <dir>: one task per file in <dir>. A task of the story with the same id: line is
# updated, other files become new tasks, and the story's tasks whose id isn't in <dir> are
# canceled. Canceled tasks are never matched, and tasks without an id: line (made by hand) are left
# alone. A task's title is its first "# " heading, else its id. Prints key, id and what was done.
story=$1; dir=$2
files=("$dir"/*.md); [ -f "${files[0]}" ] || die "no task files (*.md) in $dir"

declare -A file_of title_of
for f in "${files[@]}"; do                       # check every file before writing anything
  id=$(task_field id < "$f")
  [[ $id =~ ^[a-z0-9][a-z0-9._-]*$ ]] || die "$f: no id: line, or the id isn't lowercase letters, digits, . _ -"
  [ -z "${file_of[$id]:-}" ] || die "$f: id $id is also in ${file_of[$id]}"
  s=$(task_field story < "$f")
  [ -z "$s" ] || [ "${s,,}" = "${story,,}" ] || die "$f: story: $s, but publishing to $story"
  file_of[$id]=$f
  title_of[$id]=$(sed -n '/^# /{s/^# *//;p;q;}' "$f"); title_of[$id]=${title_of[$id]:-$id}
done

declare -A key_of
tasks=$(t items "$story")                        # an assignment, so a failed call stops here
while IFS=$'\t' read -r -u 3 key status _; do
  [ -n "$key" ] && [ "$status" != canceled ] || continue
  id=$(t read "$key" | task_field id)
  [ -n "$id" ] || { echo "tracker: $key has no id: line, left alone" >&2; continue; }
  [ -z "${key_of[$id]:-}" ] || die "tasks ${key_of[$id]} and $key of $story both have id $id: cancel one"
  key_of[$id]=$key
done 3<<<"$tasks"

for id in $(printf '%s\n' "${!file_of[@]}" | sort); do
  key=${key_of[$id]:--}
  new=$(t write "$key" "$story" "${title_of[$id]}" < "${file_of[$id]}")
  printf '%s\t%s\t%s\n' "$new" "$id" "$([ "$key" = - ] && echo created || echo updated)"
done
for id in $(printf '%s\n' "${!key_of[@]}" | sort); do
  [ -z "${file_of[$id]:-}" ] || continue
  t move "${key_of[$id]}" canceled
  printf '%s\t%s\tcanceled\n' "${key_of[$id]}" "$id"
done
