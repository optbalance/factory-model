# Sourced by bin/tracker. A task's fields (tracker contract, Step 5): lines of their own, each
# starting with its key (id:, story:, depends_on:, touches:), anywhere in the body.
# task_field <key>: reads a body on stdin and prints the first such line's value: Markdown escapes
# (a backslash before punctuation) dropped, a list's [ ] removed. Nothing if there's no such line.
task_field() {
  sed -n "/^$1:/{s/^$1:[[:space:]]*//;p;q;}" | sed 's/\\\([[:punct:]]\)/\1/g; s/[[:space:]]*$//; s/^\[\(.*\)\]$/\1/'
}
