# The workbench kit

How to bring one of your GitHub repositories onto Code's workbench lane. The setup app does it for you and asks before every change; the appendix gives each of its steps by hand.

## How the lane works

- **The integration branch** (`workbench` unless you rename it in the Assistant app's Settings › Code › GitHub) is the lane's: sessions open pull requests into it, and the app merges them there with your passkey. It is never your default branch. You merge it into your own branches whenever you like.
- **`.workbench/` on the integration branch** holds what a launched session follows: `launch.md` (the launch core), `relay.md` (how it reports to the app), `price.md` (a price check, kept exactly as the kit holds it: the app checks it is that file), `steps.md` (the launch ticks), `agents/*.md` (the roles a launch can spawn: `planner`, `implementer`, `security-reviewer`, `validity-reviewer` and `simplicity-reviewer`) and `authors.json`. A session reads them at the integration branch's tip, which must be the commit your passkey approved. `steps.md` and the agents are yours to change, by a pull request with your review.
- **The scheduled task runs on your default branch,** so your own `.claude/` and `CLAUDE.md` load first, as always.
- **Your session bot** pushes only `workbench-issue-<n>` (a launch's branch) and `claude/**` (your ordinary cloud sessions). A ruleset holds it off every other branch and every tag.
- **Code Owners review:** a pull request into the integration branch that changes `.workbench/`, `.github/CODEOWNERS` or a session's boot files (`CLAUDE.md`, `CLAUDE.local.md`, `.claude/`, `.mcp.json`, at any depth) needs your review on GitHub, whoever opens it.

## The setup app

A small text app for macOS (Apple silicon), Windows (x64) and Linux (x64), downloaded from Settings › Code › GitHub. It runs in a terminal window, signs you and your bot in to GitHub for that run only, connects claude.ai's cloud sessions to your bot, and sets up each repository you pick. The app itself talks only to GitHub, and downloads only from GitHub (gh) and claude.ai (Claude Code's installer), each when you agree; Claude Code, which it starts for `/web-setup`, talks to claude.ai. Nothing is sent to the Assistant app. Run it again whenever you like: after renaming the integration branch, or to take a newer kit.

## What the bot costs you

- **A second GitHub account,** which you make yourself: GitHub's terms require a human to create each account. It needs its own email address. On a provider with plus addressing, such as Gmail, a plus address of your own works, for example `name+bot@gmail.com` (tested with Gmail; only some providers support it); otherwise use an alias or another address you control. Never a disposable-mail service: GitHub sends the account's sign-in and recovery mail there. Give it two-factor authentication and a passkey, and turn its notifications off (Settings › Notifications), since every repository it joins would mail it.
- **Claude Code once,** for `/web-setup` as the bot; the setup app offers to install it. On a claude.ai Team or Enterprise plan, your organization's Owner turns on Quick setup first.
- A paid GitHub plan for private repositories; public repositories work on any plan.
- A paid claude.ai plan, for scheduled tasks.
- About 20 minutes once, and 10 per repository.

**Every claude.ai cloud session you start then acts as the bot,** not only launches. A claude.ai cloud session pushes, comments and opens pull requests as whichever GitHub account is connected to your claude.ai account, and there is one connection per account. That is why the bot exists: connected as the bot, a session holds only the bot's access (write, no `workflow` scope, and the bot ruleset's branches), not your own admin rights.

## Before you start (once)

1. **Make the bot,** as above.
2. **In the Assistant app's Settings › Code › GitHub,** connect GitHub (the App on your own personal account, **Only select repositories**), add your first passkey within 15 minutes, and save your session bot.

## Run the setup app

### Download and check it

In Settings › Code › GitHub, under **Setup app**, download it for your computer. Settings shows each download's SHA-256 and the release it comes from. Before opening it:

- **macOS** (`assistant-setup-macos-arm64.zip`): Safari unpacks it to `Workbench Setup.app` (and may move the zip to the Bin: take it back to check its SHA-256); otherwise, double-click the zip. To check it (optional), in Terminal, in that folder:

  ```sh
  codesign -dv --verbose=2 "Workbench Setup.app"
  spctl -a -vv "Workbench Setup.app"
  ```

  `codesign` must show `Authority=Developer ID Application: … (BMXVW9JNQ9)` and `TeamIdentifier=BMXVW9JNQ9`, and `spctl` must show `source=Notarized Developer ID`.

- **Windows** (`assistant-setup-windows-x64.exe`): right-click it › **Properties** › **Digital Signatures**. The signer must be `__WINDOWS_PUBLISHER__`, with a timestamp. A tab that is missing means it is unsigned: don't run it.
- **The SHA-256** of the file you downloaded (the zip, the `.exe` or the `.tar.gz`) must match the one Settings shows: `shasum -a 256 <file>` on macOS, `sha256sum <file>` on Linux, `Get-FileHash <file>` in PowerShell. It must also match `SHA256SUMS.txt` on the kit repository's release that Settings names, on GitHub, reached by typing the kit repository's name rather than by a link. Its releases can't be changed once published.

### Open it

- **macOS:** double-click **Workbench Setup**. The first time, macOS asks whether to open an app downloaded from the internet: choose **Open**. The wizard opens in Terminal. If Terminal doesn't open, a dialog gives the command to run in Terminal instead, from the folder that holds Workbench Setup. Delete the app when you're done.
- **Windows:** double-click the `.exe`. SmartScreen may warn while the signing certificate is new and has no reputation yet: **More info** names the publisher; choose **Run anyway** only if it is `__WINDOWS_PUBLISHER__`.
- **Linux:** in a terminal, `tar -xzf assistant-setup-linux-x64.tar.gz`, then `./assistant-setup`.

Run it from an ordinary terminal session, not one with unusual environment variables set. With no terminal it stops before reading anything (the macOS app opens Terminal itself).

### What it does

In this order, saying what it found at each step:

1. **The setup code.** Paste the setup code from Settings › Code › GitHub (**Copy**). It holds your GitHub id, your bot's, your App installation's and your integration branch's name, nothing secret. The app shows them back.
2. **Tools.** It finds Claude Code, or offers to install it with Claude Code's official installer from claude.ai (no admin rights). It finds the GitHub CLI (`gh`) 2.40 or later, or offers to download gh for this run only, checked against the SHA-256 the app holds and deleted at the end. Your own `gh` and its sign-ins are never touched: the app uses a copy, with its own empty settings.
3. **Sign in as your bot.** Open a private window, sign in to GitHub there as the bot, go to `https://github.com/login/device` and enter the code the app shows. It checks the account is the bot the setup code names, with `repo` and none of `workflow`, `admin:*` or `delete_repo`.
4. **Connect the cloud as your bot.** Press Enter and Claude Code starts in the app's own empty folder, signed in to GitHub as the bot. If it asks whether to trust the folder, choose **Yes**. If it asks, type `/login` and sign in with your claude.ai account. Type `/web-setup` and choose **Replace connection**; it warns there is no `workflow` scope, which is intended. Check it says it is connected as your bot, type `/exit`, and answer `y`.
5. **Sign in as you.** Your browser opens `https://github.com/login/device`; enter the code the app shows, signed in as yourself. It checks the account is the setup code's owner, a personal account, with `repo`, `workflow` and `read:user`.
6. **Which repository?** It lists your own repositories that aren't archived; type a number. Then type the checks D2 should require, comma-separated, or press Enter for none (with none, green means no failed or pending GitHub Actions run).
7. **The repository.** It reads everything first: the repository, its secrets, the audit and what is set up already (appendix, steps 2 to 4), and stops there, before any change, on anything it refuses. Then it lists every change it plans and asks once, `Continue? [y/N]`. A step already done is skipped, and a ruleset of ours that differs from the kit's is replaced in place. If nothing is left, it says so and asks nothing.
8. **The writes,** in the appendix's order: the bot ruleset in its holding form, the integration branch, D3, D1, the files (or a pull request for you to merge, once D2 exists), D2, the tag ruleset, the settings, then the invitation, which it accepts as the bot.
9. **The scheduled task.** It prints the task's settings and its saved prompt, for [the claude.ai side](#the-claudeai-side).
10. **The Code App.** Your browser opens your App installation's page: **Only select repositories**, add the repository, **Save**, then press Enter. It adds the App to D1's bypass list and reads it back, then leaves the integration branch out of the bot ruleset.
11. **Check.** It reads every item again from GitHub and marks each ✓ or ✗, then lists what is left.
12. **Set up another repository?** `y` goes back to step 6. At the end it deletes the run's folder, its sign-ins and any download, and waits for Enter.

Press Ctrl-C, or close the window, to stop at any time (while Claude Code runs, Ctrl-C is Claude Code's). A stop says whether anything was changed; run it again and it picks up where it stopped.

### What it can't do

- Make your bot's account (GitHub's terms).
- Set up your claude.ai environment or scheduled task, or Add routine in the Assistant app: they have no API it can use. It prints what they need.

## The claude.ai side

1. **A claude.ai cloud environment** for your scheduled tasks: the relay ingest host (`taskmanager-ingest-972519281630.europe-west1.run.app`) in its allowed domains, and a relay token from Settings › Code › Relay tokens as a Network secret bound to that host only, pasted exactly as the app shows it once; claude.ai adds `Bearer` itself. One environment and its relay token serve every repository's routine. The token never enters a session: the proxy adds it.
2. **A scheduled task** per repository at https://claude.ai/code/routines › **New task** (from claude.ai/code: **Scheduled** › **New task**), with what the setup app printed: the repository, its default branch, your cloud environment, the coordinator's model, and the saved prompt. Add an **API trigger**. Nothing about the routine goes into GitHub.
3. **Add routine** in the Assistant app's Settings › Code › Routines, under the repository, with a name, the trigger's fire URL and its token, and your passkey. The app fires the routine itself when you launch, and never shows the token again. If the repository has several routines, **Make default** on the one a launch should preselect. Note the token's renewal date.

## Check in the app

The repository shows in Code's sidebar, and its setup status in the Assistant app's Settings › Code › GitHub shows every item done. Create a throwaway issue, launch a Quick fix with your passkey, and check `started` arrives on the run page; once the bot's pull request into `<integration>` is green, merge it from the app.

## Appendix: what the setup app does, and by hand

Each step says what the app does, then how to do it by hand. By hand you need `gh` 2.40 or later signed in as you, with the `workflow` and `read:user` scopes (`gh auth login -h github.com`, then `gh auth refresh -h github.com -s workflow,read:user`), and `git` for the audit. Use your own values for `<owner>/<name>`, `<you>`, `<bot>`, `<default>` and `<integration>`.

### 1. Your accounts

The app signs you and your bot in with `gh`, each into its own throwaway folder made for the run and deleted at the end, never into your own `gh` or the system keychain. It checks you: the setup code's owner, a personal account, with `repo`, `workflow` and `read:user`; and your bot: the setup code's bot, with `repo` and none of `workflow`, `admin:*` or `delete_repo`. It then runs Claude Code with the bot's folder for `/web-setup`.

By hand, for `/web-setup` as the bot without signing the bot in to your own `gh`:

```sh
export GH_CONFIG_DIR="$(mktemp -d)"
GH_BROWSER=echo gh auth login -h github.com -p ssh --skip-ssh-key --web --insecure-storage
claude    # /web-setup, Replace connection, then /exit
rm -rf "$GH_CONFIG_DIR"; unset GH_CONFIG_DIR
```

Paste the one-time code `gh` shows into `https://github.com/login/device` in a private window signed in as the bot; `GH_BROWSER=echo` keeps `gh` from opening your default browser, which is signed in as you.

The `ssh` protocol keeps `gh` from giving the bot `workflow`, which it must not have, and from setting up git credentials; `--insecure-storage` keeps the token in that folder, not the keychain.

### 2. The repository

The app refuses a repository that isn't on your own personal account, an archived one, a private one on a free or unknown plan, an integration branch named as the default branch, an existing integration branch with commits `<default>` lacks, and a bot that is already a collaborator with a role other than write.

### 3. Secrets

The app stops on any Actions or Dependabot repository secret, on any environment with secrets that a bot branch could deploy from, and on an earlier kit's `routine-fire` environment with secrets ([Coming from an earlier kit](#coming-from-an-earlier-kit)). By hand: Settings › Secrets and variables › Actions and › Dependabot hold no repository secrets (move each into an environment, or delete it); every environment with secrets lists only literal branch names under **Deployment branches and tags** (no patterns, tags or protected-branches rule, and nothing under `claude/` or `workbench-issue-`); and no `routine-fire` environment is left from an earlier kit.

### 4. The audit

The app reads every workflow, on every branch and tag, over GitHub's API, and lists each line with `workflow_dispatch`, `repository_dispatch`, `pull_request_target`, `workflow_run`, `id-token: write` or `write-all`. On a public repository it stops on `pull_request_target` and `workflow_run`, and on a workflow file it can't read. With more than 1,000 branches and tags, or more workflow files than it can list, it stops and asks you to do the audit by hand:

```sh
git clone --bare https://github.com/<owner>/<name>.git audit.git
git -C audit.git for-each-ref --format='%(refname)' refs/heads refs/tags |
  while IFS= read -r ref; do
    git -C audit.git grep -n -E 'workflow_dispatch|repository_dispatch|pull_request_target|workflow_run|id-token: *write|write-all' "$ref" -- .github/workflows
  done
```

The App can dispatch any `workflow_dispatch` workflow: each one guards its jobs on the actor (`if: github.triggering_actor == '<you>'`) or is harmless when the App starts it (no secrets, no deploy, no writes).

The app also names each branch or tag that still holds an earlier kit's `.github/workflows/workbench-launch.yml` ([Coming from an earlier kit](#coming-from-an-earlier-kit)).

### 5. The bot ruleset, in its holding form

The app creates it first, leaving out only `workbench-issue-*` and `claude/**`; the integration branch is left out last (step 12). By hand: Settings › Rules › Rulesets › **New branch ruleset**, from `rulesets/bot.json`: `workbench-bot`, **Active**, all branches, excluding `refs/heads/workbench-issue-*` and `refs/heads/claude/**`; **Restrict creations**, **Restrict updates**, **Restrict deletions**; bypass **Repository admin**, **Always**.

It holds everyone without a bypass, GitHub Actions' own token and Dependabot or Renovate branches included: a workflow or tool that pushes a branch or a tag needs another way. To let a collaborator of yours through, add them to `workbench-bot`'s bypass list by hand. The app never adds one, and a later run replaces the ruleset with the kit's form, which drops them: add them again after each run.

### 6. The integration branch, D3 and D1

The app creates `<integration>` from `<default>`, then D3 and D1. On a rename, it creates the new branch before it moves the rulesets to it. By hand, create the branch, then from `rulesets/`:

| Ruleset        | Target                     | Rules                                         | Bypass                                            |
| -------------- | -------------------------- | --------------------------------------------- | ------------------------------------------------- |
| `workbench-d3` | `refs/heads/<integration>` | Restrict creations and deletions              | Repository admin, Always                          |
| `workbench-d1` | `refs/heads/<integration>` | Restrict updates (no "allow fetch and merge") | Repository admin, Always; the Code App at step 11 |

### 7. The files

The app commits them to `<integration>` as you; once D2 exists, it opens a pull request for you to merge instead. It refuses a CODEOWNERS at the root or in `docs/`, and a symlink, submodule or file where `.workbench/`, `.github/` or a kit file goes. By hand, on `<integration>`:

- `files/dot-workbench/` becomes `.workbench/`. In `launch.md` replace `__INTEGRATION__` with `<integration>`. In `authors.json` put your id as `owner_id`, `342955731` (the App's bot) as `app_bot_id`, and your bot's id and login as `session_bot_id` and `session_bot_login`, ids as numbers.
- `files/dot-github/CODEOWNERS`'s lines go last in `.github/CODEOWNERS` (created if absent), with `__OWNER_LOGIN__` as your login. If your CODEOWNERS is at the root or in `docs/`, move it to `.github/` first.

`steps.md` and the agents are added only when absent. A renamed integration branch starts from `<default>`, so edits you made to them on the old one don't carry over: bring them across by a pull request.

### 8. D2 and the tag ruleset

The app creates both, D2 with the checks you named. By hand, from `rulesets/`:

| Ruleset          | Target                     | Rules                                                                                                                                                                                                                        | Bypass                                                  |
| ---------------- | -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| `workbench-d2`   | `refs/heads/<integration>` | Require a pull request: 0 approvals, dismiss stale approvals, require review from Code Owners, approval of the most recent push off, merge and squash allowed; your required checks, from GitHub Actions; block force pushes | Repository admin, For pull requests only; never the App |
| `workbench-tags` | All tags                   | Restrict creations, updates and deletions                                                                                                                                                                                    | Repository admin, Always                                |

Approval of the most recent push stays off, since with 0 approvals GitHub refuses the App's merge of every session's pull request: your approval at the head still gates `.workbench/`, CODEOWNERS and the boot files in the app, and Code Owners review gates them on GitHub; leaving it off only stops GitHub requiring a non-pusher's approval on every pull request.

### 9. Settings

The app allows merge commits (the app merges with one), makes Actions' default token read-only and unable to approve pull requests, and on a public repository requires approval for every outside contributor's fork pull request runs. By hand: Settings › General › **Allow merge commits**; Settings › Actions › General › **Workflow permissions** and **Approval for running fork pull request workflows from contributors**.

### 10. The bot and the scheduled task

The app invites your bot with write and accepts the invitation as the bot, with the bot's own sign-in; if that fails, it says so, and you accept by hand. Then it prints the scheduled task's settings and saved prompt. By hand:

1. Settings › Collaborators › **Add people** › `<bot>`, with write. In a private window signed in as the bot, accept at `https://github.com/<owner>/<name>/invitations`.
2. The scheduled task and Add routine: [the claude.ai side](#the-claudeai-side), steps 2 and 3. Its saved prompt is `routine-prompt.txt` with `__INTEGRATION__` as `<integration>`.

### 11. The App

The app opens your installation's page, waits while you add the repository to it, then adds the App to D1's bypass list and reads it back. By hand: `https://github.com/settings/installations/<installation id>` › **Only select repositories** › add `<owner>/<name>` › **Save**; then `workbench-d1` › **Add bypass** › `jb-assistant-app-code`, **Always**.

### 12. The bot ruleset's last exclusion

The app adds `refs/heads/<integration>` to `workbench-bot`'s exclusions, now that D1 and D3 hold the branch. By hand, edit `workbench-bot` and add it under **Exclude by pattern**.

## Coming from an earlier kit

- **`routine-fire`:** if the routine's trigger token was ever stored in GitHub (an earlier kit kept it in a `routine-fire` environment), **regenerate** it in the trigger's settings on claude.ai: regenerating revokes the old copy. Paste the new one into Settings › Code › Routines, then delete `routine-fire` in Settings › Environments.
- **`workbench-launch.yml`:** delete `.github/workflows/workbench-launch.yml` from each branch or tag the app names, on `<integration>` by a pull request you merge: the app fires your routine itself now.

## Known limits

- **On a public repository** strangers' comments can reach a session, which treats them as data only, and the bot can approve strangers' fork runs, which get no secrets.
- **A stolen App key** meets Code Owners review only on `.workbench/`, CODEOWNERS and the boot files: it could still merge other pull requests into your integration branch with green checks.
- **The download links and their SHA-256 come from the app,** so a compromised app could show others: compare them with `SHA256SUMS.txt` on the kit repository's release and with the signature's publisher.
- **During a run, both sign-ins' tokens are on disk** in plain text, in the run's own folder, which only your user can read (on Windows it sits in your profile, relying on its permissions). They are deleted at the end, on Ctrl-C and when the window closes; a hard kill leaves them until the app's next run sweeps them.
- **Your own token stays valid on GitHub** after the run. Revoking it is optional: Settings › Applications › Authorized OAuth Apps › **GitHub CLI** › **Revoke** revokes every `gh` token of yours, on every computer, so your own `gh` signs in again. Never revoke the bot's: `/web-setup` connected claude.ai with it.
- **The Claude Code installer comes from claude.ai** over HTTPS; the app doesn't check it further.
- **The app ignores `NODE_OPTIONS`,** but some environment variables still reach it (`OPENSSL_CONF`, `NODE_EXTRA_CA_CERTS`, `NODE_V8_COVERAGE`, and `LD_PRELOAD` on Linux); on macOS the hardened runtime blocks library injection.
- **Repository secrets added after setup** reach push-triggered workflows on bot branches. Run the app again after adding one.
- **Files `CLAUDE.md` imports, and scripts that `.claude/settings.json` hooks call,** aren't code-owned unless they sit under the listed paths: keep them there, or add their paths to CODEOWNERS.
- **Renaming your GitHub login** leaves CODEOWNERS naming no one until you run the app again.
- **The bot's claude.ai connection's own scopes** aren't visible to the app.
- **No deploy** should run from a push to your branches except from an environment limited to the branch it deploys, and a cloud deploy's credential trust should be pinned to a branch.
