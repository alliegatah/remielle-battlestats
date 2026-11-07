# Updating to a new upstream client version

This fork (Battle Stats) tracks upstream Remielle's GitHub mirror at
`https://github.com/thexeondev/remielle` (branch `0.1.x`). The mirror has the
same history as `https://git.xeondev.com/remielle/remielle`, plus the
`zzz-bot-remi` data-revision bumps, so use the mirror as the source.

> **This is automated.** The `Upstream sync` GitHub Action applies new upstream
> commits for you. See [Automatic sync](#automatic-sync). The manual procedure
> below is what to do when the bot opens an "Upstream sync blocked" issue.

Upstream ships
each client version as a commit, often also published as a `.patch` file, such as
`1913eba675.patch` = "Update all of the appropriate resources for CNBetaWin3.4.3".

The fork's history was **not** merged from upstream. Every upstream commit was
ported by hand. Upstream patches are diffs against upstream's exact previous
state, so a `.patch` only applies cleanly if the fork already contains **every**
upstream commit before it. That includes the small ones between client versions:

- `Assets: bump data revision to NNNNNNNN`: touches `dpsv/config.zon` **and**
  the binary `assets/bincfg/main_city_object_template_tb.remi` (and sometimes
  `assets/filecfg/*.zon`)
- `fix(rmpb): ...`: hand fixes to the generated `rmpb/src/pb.main.desc.zig`

If one of these was skipped, `git apply` fails on `pb.main.desc.zig`,
`dpsv/config.zon` or the `.remi` binary (`patch does not apply` /
`does not match the current contents`). That is what happened with 3.4.3: the
fork was missing `a7352ff` and `7491865`.

**Rule of thumb:** don't apply the downloaded `.patch` on its own. Pull every
missing upstream commit from the upstream repo, in order.

---

## Procedure

Run these from the repo root in Git Bash, or adapt them to PowerShell.

### 1. One-time setup: add upstream as a remote

```bash
git remote add upstream https://github.com/thexeondev/remielle.git
```

### 2. Fetch and find what's missing

```bash
git fetch upstream 0.1.x
git log --oneline --reverse <LAST_SYNCED>..upstream/0.1.x
```

`<LAST_SYNCED>` is the last upstream commit already ported. It's stored in
`.github/upstream-sync.sha`:

```bash
git log --oneline --reverse $(cat .github/upstream-sync.sha)..upstream/0.1.x
```

Commits made by the bot also carry an `Upstream: <sha>` trailer.

For the 3.4.3 sync, `<LAST_SYNCED>` was `2f528f6`.

### 3. Apply each missing commit, oldest first, without committing

```bash
git cherry-pick -n <commit1>
git cherry-pick -n <commit2>
# ...last one is the version update itself
```

`-n` stages the changes without committing, so the whole sync becomes one fork commit.

### 4. Resolve conflicts

| File | Resolution |
|---|---|
| `assets/bincfg/*.remi` (binary) | Always take upstream: `git checkout --theirs -- <file>` |
| `rmpb/src/pb.main.desc.zig` (generated) | Take upstream. Fork code must adapt to it, not the other way round |
| `dpsv/config.zon` | Take upstream, unless you added your own entries (e.g. extra servers). The CDN block (`base_url`, `data_revision`, `md5_files`, `res_revision`, `silence_revision`) always comes from upstream |
| `gamesv/config.zon`, `assets/filecfg/*.zon` | Take upstream, unless you deliberately changed a value in the fork |
| `README.md` | Keep the fork's header; take only the "Currently supported client version" line |
| `gamesv/src/**` | Merge by hand. This is where fork features live (see below) |

After resolving, `git add <file>`. If a cherry-pick stopped on a conflict, run
`git cherry-pick --quit` before the next `git cherry-pick -n` (this keeps your
staged changes).

### 5. Verify

Check that the generated and data files now match upstream exactly:

```bash
git diff --stat upstream/0.1.x -- assets rmpb dpsv gamesv/config.zon
```

Anything listed is a fork-only difference. Make sure each one is intentional.
Then build and test:

```bash
zig build
zig build test
```

If `zig build` fails in `gamesv`, a protocol field the fork uses was renamed or
renumbered in `pb.main.desc.zig`. Update the fork code to the new name. Fork
code most likely to be affected:

- `gamesv/src/messaging/endbattle_loadout_dump.zig`: the loadout / combat log dump
- `gamesv/src/messaging/handlers.zig`, `packers.zig`
- `gamesv/src/logic/Properties.zig`, `Properties/Buddy.zig`
- `gamesv/src/messaging/Xorpad.zig`, `gamesv/src/kcp/MultiConversation.zig`

Finally, run `zig build serve-all`, connect with the new client and
finish one battle. Check that `logs/endbattle_N.pb` and
`logs/endbattle_N_loadout.json` are written.

### 6. Commit

Record the last upstream commit you ported in the state file, so the bot
continues from there, then commit:

```bash
echo <LAST_PORTED_FULL_SHA> > .github/upstream-sync.sha
git add .github/upstream-sync.sha
git commit -m "Update to v3.4.3" -m "Synced upstream a7352ff, 7491865, 1913eba." -m "Upstream: 1913eba67589a34b6d495fce39acf79552b6b238"
git push origin 0.1.x
```

If the bot had opened an "Upstream sync blocked" issue, its next run closes the
issue automatically. You can also trigger a run right away from
**Actions → Upstream sync → Run workflow**.

---

## Data-revision-only bumps (no new client version)

Sometimes the client gets a new data revision with no version change, e.g. `Update to Rev. 20052336`.
Upstream publishes these as `Assets: bump data revision to N`; the
`zzz-bot-remi` ones appear only on the GitHub mirror. The bot ports them
automatically. Don't edit `dpsv/config.zon` revisions by hand. That puts the fork
out of step with upstream, and the next upstream commit then conflicts.

---

## Automatic sync

`.github/workflows/upstream-sync.yml` runs every 2 hours, and on demand from
**Actions → Upstream sync → Run workflow**. It runs
`.github/scripts/upstream-sync.sh`, which:

1. Fetches `thexeondev/remielle` `0.1.x` and lists the commits after the one in
   `.github/upstream-sync.sha`.
2. Cherry-picks each one, oldest first, as **one fork commit per upstream
   commit**. Each commit keeps the upstream author and message and gets an
   `Upstream: <sha>` trailer. The state file advances in the same commit.
3. Resolves conflicts with the table in [step 4](#4-resolve-conflicts):
   upstream wins for `assets/`, `rmpb/`, `dpsv/config.zon` and
   `gamesv/config.zon`, and for `README.md` the fork keeps its own text except the
   supported-version line. A conflict anywhere else (fork code) stops the sync.
4. Runs `zig build` and `zig build test` on Linux.
5. On success, pushes to `0.1.x` and closes any open "Upstream sync blocked"
   issue.

If any step fails, **nothing is pushed**. The bot opens one "Upstream sync blocked"
issue (or comments on the existing one if the reason changed) naming the upstream
commit and files involved. Fix it by following the manual procedure above. The
next run continues from the state file.

Run the script locally the same way (it commits but never pushes):

```bash
bash .github/scripts/upstream-sync.sh            # full: sync + build + test
SKIP_BUILD=1 bash .github/scripts/upstream-sync.sh
```

What the bot can't check: that the server works with the real client. Do a
quick in-game battle after a client version update.

GitHub disables scheduled workflows in a repo after 60 days with no activity.
If upstream is quiet for that long, re-enable the workflow under **Actions**.

---

## Known fork vs upstream data differences

None as of the 3.4.3 sync: `assets/`, `rmpb/`, `dpsv/` and
`gamesv/config.zon` are identical to upstream `1913eba`.

Earlier history: item `13022` (`Weapon_A_Common_22`) in
`assets/filecfg/WeaponTemplateTb.zon` had stale stats (`12101 / 40`) from
September until the 3.4.3 sync. Upstream had corrected it in `237cf3f` to
`13101 / 24` + `13102 / 1600`, and the fork had skipped that commit. The fix was
ported during the 3.4.3 sync. Battle logs recorded before then with that
W-Engine equipped used the stale stats.
