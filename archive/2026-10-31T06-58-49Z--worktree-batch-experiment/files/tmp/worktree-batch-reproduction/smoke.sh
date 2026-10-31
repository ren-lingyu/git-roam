#!/usr/bin/env bash
set -euo pipefail

: "${GIT_BIN:?Set GIT_BIN to the patched git binary}"
experiment_root="$(mktemp -d)"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null

for format in files reftable; do
  dir="$experiment_root/$format"
  mkdir -p "$dir"
  "$GIT_BIN" init --ref-format="$format" -q "$dir/repo"
  "$GIT_BIN" -C "$dir/repo" config user.name Test
  "$GIT_BIN" -C "$dir/repo" config user.email test@example.invalid
  "$GIT_BIN" -C "$dir/repo" -c commit.gpgSign=false commit --allow-empty -qm base
  for i in 1 2 3 4 5; do
    "$GIT_BIN" -C "$dir/repo" branch "node-$i"
  done

  for i in 1 2 3; do
    printf '%s\t%s\n' "$dir/node-$i" "node-$i"
  done > "$dir/valid.tsv"
  "$GIT_BIN" -C "$dir/repo" worktree add --batch --no-checkout < "$dir/valid.tsv"
  for i in 1 2 3; do
    test -f "$dir/node-$i/.git"
  done

  printf '%s\t%s\n' "$dir/node-4" node-4 > "$dir/rollback.tsv"
  printf '%s\t%s\n' "$dir/node-5" node-5 >> "$dir/rollback.tsv"
  if GIT_TEST_WORKTREE_BATCH_FAIL_AFTER=1 "$GIT_BIN" -C "$dir/repo" \
      worktree add --batch --no-checkout < "$dir/rollback.tsv"; then
    echo 'Expected injected failure did not occur' >&2
    exit 1
  fi
  test ! -e "$dir/node-4"
  test ! -e "$dir/node-5"
  echo "OK ($format): batch registration and injected rollback"
done
