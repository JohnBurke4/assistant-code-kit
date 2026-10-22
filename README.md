# The workbench kit

How to bring one of your GitHub repositories onto Code's workbench lane. The setup script does each step below, in this order; each step also says how to do it by hand.

## How the lane works

- **The integration branch** (`workbench` unless you rename it in the Assistant app's Settings › Code › GitHub) is the lane's: sessions open pull requests into it, and the app merges them there with your passkey. It is never your default branch. You merge it into your own branches whenever you like.
- **`.workbench/` on the integration branch** holds what a launched session follows: `launch.md` (the launch core), `relay.md` (how it reports to the app), `steps.md` (the launch ticks), `agents/*.md` (the roles a launch can spawn: `planner`, `implementer`, `security-reviewer`, `validity-reviewer` and `simplicity-reviewer`) and `authors.json`. A session reads them at the integration branch's tip, which must be the commit your passkey approved. `steps.md` and the agents are yours to change, by a pull request with your review.
- **The scheduled task runs on your default branch,** so your own `.claude/` and `CLAUDE.md` load first, as always.
- **Your session bot** pushes only `workbench-issue-<n>` (a launch's branch) and `claude/**` (your ordinary cloud sessions). A ruleset holds it off every other branch and every tag.
- **Code Owners review:** a pull request into the integration branch that changes `.workbench/`, `.github/CODEOWNERS` or a session's boot files (`CLAUDE.md`, `CLAUDE.local.md`, `.claude/`, `.mcp.json`, at any depth) needs your review on GitHub, whoever opens it.

## What the bot costs you

- A second GitHub account, with its own email and two-factor authentication, signed in once with `gh`.
- **Every claude.ai cloud session you start then acts as the bot**: claude.ai has one GitHub connection per account, and the bot is it.
- The Claude Code CLI once, for `/web-setup` as the bot (on a Team or Enterprise plan, your Owner's Quick setup first).
- A paid GitHub plan for private repositories; public repositories work on any plan.
- A paid claude.ai plan, for scheduled tasks.
- About 20 minutes once, and 10 per repository.

## Before you start (once)

1. **Connect GitHub** in the Assistant app's Settings › Code › GitHub, add your first passkey, and save your session bot there.
2. **`gh` 2.40 or later, signed in as you** with the `workflow` and `read:user` scopes: `gh auth login -h github.com`, then `gh auth refresh -h github.com -s workflow,read:user`.
3. **`gh` signed in as your bot,** in a browser signed in as the bot: `gh auth login -h github.com -p ssh --skip-ssh-key --web`. The `ssh` protocol keeps `gh` from giving the bot `workflow`, which it must not have. It also switches every `gh` account's git protocol to `ssh`, so the script pushes only over `https://` addresses, with `gh` as the credential. Then `gh auth switch -h github.com -u <you>`.
4. **The cloud as the bot:** `gh auth switch -h github.com -u <bot>`, `claude`, `/web-setup`, then `gh auth switch -h github.com -u <you>`.
5. **A claude.ai cloud environment** for your scheduled tasks: the relay ingest host (`taskmanager-ingest-972519281630.europe-west1.run.app`) in its allowed domains, and a relay token from Settings › Code › Relay tokens as a Network secret bound to that host only, as the `Bearer …` value the app shows once. The token never enters a session: the proxy adds it.

## Run the script

From the Assistant app's Settings › Code › GitHub, copy the line it shows and run it in a terminal. It has this shape, with the kit repository and commit the app names:

```sh
git clone https://github.com/<kit>.git assistant-code-kit && git -C assistant-code-kit checkout <commit> && bash assistant-code-kit/setup.sh <owner>/<name> --owner-id … --bot-id … --installation-id … --integration <name>
```

Git checks every file against that commit; before running it, check the commit is in the kit repository's history on GitHub, reached by its known name rather than by a link. Run it from an empty folder, a new one for each repository. Optional flags: `--check <name>` for each check D2 requires (from GitHub Actions; with none, green means no failed or pending Actions run), and `--exempt <login>` for each collaborator of yours the bot ruleset should let through.

It says what it found at each step, lists every change it plans, and asks once, `Continue? [y/N]`, on your terminal. With no terminal it stops before reading anything. A step already done is skipped, and a ruleset of ours that differs from the kit's is replaced in place. Run it again whenever you like: after renaming the integration branch in the app, or to take a newer kit. It ends with what is left.

## The steps

Use your own values for `<owner>/<name>`, `<you>`, `<bot>`, `<default>` and `<integration>`.

### 1. Your accounts

The script checks `gh`: you, with `repo`, `workflow` and `read:user`; your bot, with `repo` and none of `workflow`, `admin:*` or `delete_repo`. By hand, `gh auth status` lists both.

### 2. The repository

The script refuses a repository that isn't on your own personal account, an archived one, a private one on a free or unknown plan, and an integration branch named as the default branch.

### 3. Secrets

The script stops on any Actions or Dependabot repository secret, and on any environment with secrets that a bot branch could deploy from. By hand: Settings › Secrets and variables › Actions and › Dependabot hold no repository secrets (move each into an environment, or delete it); every environment with secrets lists only literal branch names under **Deployment branches and tags** (no patterns, tags or protected-branches rule, and nothing under `claude/` or `workbench-issue-`).

### 4. The audit

The script lists every workflow, on every branch and tag, with `workflow_dispatch`, `repository_dispatch`, `pull_request_target`, `workflow_run`, `id-token: write` or `write-all`, and on a public repository stops on `pull_request_target` and `workflow_run`. By hand:

```sh
git clone --bare https://github.com/<owner>/<name>.git audit.git
git -C audit.git for-each-ref --format='%(refname)' refs/heads refs/tags |
  while IFS= read -r ref; do
    git -C audit.git grep -n -E 'workflow_dispatch|repository_dispatch|pull_request_target|workflow_run|id-token: *write|write-all' "$ref" -- .github/workflows
  done
```

The App can dispatch any `workflow_dispatch` workflow: each one guards its jobs on the actor (`if: github.triggering_actor == '<you>'`) or is harmless when the App starts it (no secrets, no deploy, no writes).

### 5. The bot ruleset, in its holding form

The script creates it first, leaving out only `workbench-issue-*` and `claude/**`; the integration branch is left out last (step 13). By hand: Settings › Rules › Rulesets › **New branch ruleset**, from `rulesets/bot.json`: `workbench-bot`, **Active**, all branches, excluding `refs/heads/workbench-issue-*` and `refs/heads/claude/**`; **Restrict creations**, **Restrict updates**, **Restrict deletions**; bypass **Repository admin**, **Always**, and each collaborator you exempt.

It holds everyone without a bypass, GitHub Actions' own token and Dependabot or Renovate branches included: a workflow or tool that pushes a branch or a tag needs another way.

### 6. The integration branch, D3 and D1

The script creates `<integration>` from `<default>` (an existing branch of that name only if it has nothing `<default>` lacks), then D3 and D1. On a rename, it creates the new branch before it moves the rulesets to it. By hand, create the branch, then from `rulesets/`:

| Ruleset        | Target                     | Rules                                         | Bypass                                            |
| -------------- | -------------------------- | --------------------------------------------- | ------------------------------------------------- |
| `workbench-d3` | `refs/heads/<integration>` | Restrict creations and deletions              | Repository admin, Always                          |
| `workbench-d1` | `refs/heads/<integration>` | Restrict updates (no "allow fetch and merge") | Repository admin, Always; the Code App at step 12 |

### 7. The files

The script commits them to `<integration>` as you; once D2 exists, it opens a pull request for you to merge instead. By hand, on `<integration>`:

- `files/dot-workbench/` becomes `.workbench/`. In `launch.md` replace `__INTEGRATION__` with `<integration>`. In `authors.json` put your id as `owner_id`, `342955731` (the App's bot) as `app_bot_id`, and your bot's id and login as `session_bot_id` and `session_bot_login`, ids as numbers.
- `files/dot-github/workflows/workbench-launch.yml` becomes `.github/workflows/workbench-launch.yml`, with `__INTEGRATION__` as `<integration>`, `__APP_BOT_ID__` as `342955731` and `__APP_SLUG__` as `jb-assistant-app-code`.
- `files/dot-github/CODEOWNERS`'s lines go last in `.github/CODEOWNERS` (created if absent), with `__OWNER_LOGIN__` as your login. If your CODEOWNERS is at the root or in `docs/`, move it to `.github/` first.

`steps.md` and the agents are added only when absent. A renamed integration branch starts from `<default>`, so edits you made to them on the old one don't carry over: bring them across by a pull request.

### 8. D2 and the tag ruleset

The script creates both. By hand, from `rulesets/`:

| Ruleset          | Target                     | Rules                                                                                                                                                                                                                        | Bypass                                                  |
| ---------------- | -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| `workbench-d2`   | `refs/heads/<integration>` | Require a pull request: 0 approvals, dismiss stale approvals, require review from Code Owners, approval of the most recent push off, merge and squash allowed; your required checks, from GitHub Actions; block force pushes | Repository admin, For pull requests only; never the App |
| `workbench-tags` | All tags                   | Restrict creations, updates and deletions                                                                                                                                                                                    | Repository admin, Always                                |

Approval of the most recent push stays off, since with 0 approvals GitHub refuses the App's merge of every session's pull request: your approval at the head still gates `.workbench/`, CODEOWNERS and the boot files in the app, and Code Owners review gates them on GitHub; leaving it off only stops GitHub requiring a non-pusher's approval on every pull request.

### 9. Settings

The script allows merge commits (the app merges with one), makes Actions' default token read-only and unable to approve pull requests, and on a public repository requires approval for every outside contributor's fork pull request runs. By hand: Settings › General › **Allow merge commits**; Settings › Actions › General › **Workflow permissions** and **Approval for running fork pull request workflows from contributors**.

### 10. The environment

The script creates `routine-fire`, deployable from `<integration>` only. By hand: Settings › Environments › **New environment** › `routine-fire` › **Selected branches and tags** › Ref type **Branch**, `<integration>`.

### 11. The bot and the scheduled task

The script invites your bot with write and accepts as it (`gh auth switch`, and back), prints the scheduled task's settings and saved prompt, then asks for `routine-fire`'s two secrets with `gh secret set`, which prompts and shows nothing. By hand:

1. Settings › Collaborators › **Add people** › `<bot>`, with write. Signed in as the bot, accept at `https://github.com/<owner>/<name>/invitations`.
2. A new **scheduled task** at https://claude.ai/code/routines › **New task** (from claude.ai/code: **Scheduled** › **New task**): repository `<owner>/<name>`, branch `<default>`, your cloud environment, the coordinator's model, and as its saved prompt `routine-prompt.txt` with `__INTEGRATION__` as `<integration>`. Add an **API trigger**.
3. `routine-fire`'s **Environment secrets:** `ROUTINE_FIRE_TOKEN` and `ROUTINE_FIRE_URL`, the trigger's token (shown first) and URL. Never as repository secrets. Note the token's renewal date.

### 12. The App

The script waits while you add the repository to your installation, then adds the App to D1's bypass list and reads it back. By hand: `https://github.com/settings/installations/<installation id>` › **Only select repositories** › add `<owner>/<name>` › **Save**; then `workbench-d1` › **Add bypass** › `jb-assistant-app-code`, **Always**.

### 13. The bot ruleset's last exclusion

The script adds `refs/heads/<integration>` to `workbench-bot`'s exclusions, now that D1 and D3 hold the branch. When every repository is set up, sign the bot out of `gh`: `gh auth logout -h github.com -u <bot>`.

### Check in the app

The repository shows in Code's sidebar, and its setup status in the Assistant app's Settings › Code › GitHub shows every item done. Create a throwaway issue, launch a Quick fix with your passkey, and check `started` arrives on the run page; once the bot's pull request into `<integration>` is green, merge it from the app.

## Known limits

- **Every cloud session you start acts as your bot,** not only launches.
- **On a public repository** the issue number and your launch options, free text included, show in the `workbench-launch` run's log; strangers' comments can reach a session, which treats them as data only; and the bot can approve strangers' fork runs, which get no secrets.
- **A stolen App key** meets Code Owners review only on `.workbench/`, CODEOWNERS and the boot files: it could still merge other pull requests into your integration branch with green checks.
- **The setup line's kit repository and commit come from the app,** so a compromised app could show another: compare the repository and commit with the kit repository's own history on GitHub.
- **Repository secrets added after setup** reach push-triggered workflows on bot branches. Run the script again after adding one.
- **Files `CLAUDE.md` imports, and scripts that `.claude/settings.json` hooks call,** aren't code-owned unless they sit under the listed paths: keep them there, or add their paths to CODEOWNERS.
- **Renaming your GitHub login** leaves CODEOWNERS naming no one until you run the script again.
- **The bot's claude.ai connection's own scopes** aren't visible to the script.
- **No deploy** should run from a push to your branches except from an environment limited to the branch it deploys, and a cloud deploy's credential trust should be pinned to a branch.
