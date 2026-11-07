#!/usr/bin/env bash
# Port new upstream Remielle commits onto this fork, one fork commit per
# upstream commit, then build and test. See UPDATING.md ("Automatic sync").
#
# Env:
#   UPSTREAM_URL     upstream repo   (default: GitHub mirror of remielle)
#   UPSTREAM_BRANCH  upstream branch (default: 0.1.x)
#   SKIP_BUILD=1     skip `zig build` / `zig build test`
#   FAILURE_FILE     where to write a markdown failure report (optional)
#
# Exit codes: 0 = synced or already up to date, 1 = blocked (report written).
# Never pushes; the workflow does that.
set -euo pipefail

UPSTREAM_URL=${UPSTREAM_URL:-https://github.com/thexeondev/remielle.git}
UPSTREAM_BRANCH=${UPSTREAM_BRANCH:-0.1.x}
STATE_FILE=.github/upstream-sync.sha
FAILURE_FILE=${FAILURE_FILE:-}

fail() {
    echo "::error::$1" >&2
    if [ -n "$FAILURE_FILE" ]; then
        printf '%s\n\n%s\n' "$1" "${2:-}" > "$FAILURE_FILE"
    fi
    exit 1
}

# Resolve conflicts the way UPDATING.md describes. Returns 1 and prints the
# paths it can't resolve (fork code that needs a human).
resolve_conflicts() {
    local f unresolved=()
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        case "$f" in
            assets/*|rmpb/*|dpsv/config.zon|gamesv/config.zon)
                # Data, generated code and configs: upstream wins.
                if git cat-file -e ":3:$f" 2>/dev/null; then
                    git checkout --theirs -- "$f" && git add -- "$f"
                else
                    git rm -q -- "$f"
                fi
                ;;
            README.md)
                # Keep the fork's README, take only the supported-version line.
                local line
                line=$(git show ":3:$f" | grep -m1 '^#### Currently supported client version' || true)
                git checkout --ours -- "$f"
                if [ -n "$line" ]; then
                    awk -v l="$line" '/^#### Currently supported client version/{print l; next} 1' "$f" > "$f.tmp"
                    mv "$f.tmp" "$f"
                fi
                git add -- "$f"
                ;;
            *)
                unresolved+=("$f")
                ;;
        esac
    done < <(git diff --name-only --diff-filter=U)

    if [ ${#unresolved[@]} -gt 0 ]; then
        printf '%s\n' "${unresolved[@]}"
        return 1
    fi
}

[ -f "$STATE_FILE" ] || fail "Missing $STATE_FILE (last synced upstream commit)."
last=$(tr -d '[:space:]' < "$STATE_FILE")

echo "Fetching $UPSTREAM_URL $UPSTREAM_BRANCH"
git fetch --quiet --no-tags "$UPSTREAM_URL" "$UPSTREAM_BRANCH"
upstream=$(git rev-parse FETCH_HEAD)

git cat-file -e "$last^{commit}" 2>/dev/null \
    || fail "Last synced commit $last is not in upstream $UPSTREAM_BRANCH." "Upstream may have been force-pushed. Set $STATE_FILE to the last upstream commit this fork contains."
git merge-base --is-ancestor "$last" "$upstream" \
    || fail "Upstream $UPSTREAM_BRANCH no longer contains $last (force-push?)." "Set $STATE_FILE to the last upstream commit this fork contains."

mapfile -t commits < <(git rev-list --reverse --first-parent "$last..$upstream")
if [ ${#commits[@]} -eq 0 ]; then
    echo "Up to date with upstream ${upstream:0:7}."
    exit 0
fi
echo "${#commits[@]} new upstream commit(s):"
git log --no-walk=unsorted --format='  %h %s' "${commits[@]}"

for c in "${commits[@]}"; do
    short=$(git rev-parse --short "$c")
    subject=$(git log -1 --format=%s "$c")
    echo "== Applying $short $subject"

    mainline=()
    [ "$(git rev-list --parents -n1 "$c" | wc -w)" -gt 2 ] && mainline=(-m 1)

    if ! git cherry-pick -n "${mainline[@]}" "$c" >/dev/null 2>&1; then
        if ! bad=$(resolve_conflicts); then
            fail "Upstream commit $c ($subject) conflicts with fork changes." \
"These files need a manual merge:

\`\`\`
$bad
\`\`\`

Follow UPDATING.md, starting from upstream commit \`$c\`, and set \`$STATE_FILE\` to the last upstream commit you ported."
        fi
    fi
    git cherry-pick --quit 2>/dev/null || true

    echo "$c" > "$STATE_FILE"
    git add -- "$STATE_FILE"

    GIT_AUTHOR_NAME=$(git log -1 --format=%an "$c") \
    GIT_AUTHOR_EMAIL=$(git log -1 --format=%ae "$c") \
    GIT_AUTHOR_DATE=$(git log -1 --format=%aI "$c") \
    git commit --quiet --no-verify -F - <<EOF
$(git log -1 --format=%B "$c")

Upstream: $c
EOF
done

if [ "${SKIP_BUILD:-0}" != 1 ]; then
    echo "== zig build"
    zig build || fail "zig build fails after syncing upstream up to ${upstream:0:7}." \
        "A protocol or data change probably broke fork code in gamesv. Run \`zig build\` locally after porting per UPDATING.md."
    echo "== zig build test"
    zig build test || fail "zig build test fails after syncing upstream up to ${upstream:0:7}." \
        "Run \`zig build test\` locally after porting per UPDATING.md."
fi

echo "Synced to upstream ${upstream:0:7}."
