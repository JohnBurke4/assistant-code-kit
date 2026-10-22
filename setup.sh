#!/usr/bin/env bash
# Prepares one of your GitHub repositories for Code's workbench lane, as
# README.md describes. It reads first, lists what it will change, asks once,
# then writes; run it again at any time. Bash 3.2 (macOS) runs it, so no bash 4.
set -euo pipefail
umask 077

# The shared App, public: its slug and its bot's user id.
APP_SLUG=jb-assistant-app-code
APP_BOT_ID=342955731
GITHUB_ACTIONS_APP_ID=15368
# The bypass list and D2's checks are added after these literals, as the kit's rulesets hold them.
ADMIN_ALWAYS='{ "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always" }'
D2_LAST_RULE='{ "type": "non_fast_forward" }'
AUDIT_RE='workflow_dispatch|repository_dispatch|pull_request_target|workflow_run|id-token:[[:space:]]*write|write-all'
NAMES="bot tags d1 d2 d3"

KIT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

usage() {
  cat <<'EOF'
Usage: bash setup.sh <owner>/<name> --owner-id N --bot-id N --installation-id N --integration NAME
         [--check CONTEXT]... [--exempt LOGIN]...

  <owner>/<name>      your repository
  --owner-id          your GitHub account's id
  --bot-id            your session bot's GitHub account id
  --installation-id   your installation of the Code App
  --integration       the integration branch
  --check             a check D2 requires, from GitHub Actions (repeatable)
  --exempt            a collaborator the bot ruleset lets through (repeatable)

The Assistant app's Settings > Code > GitHub shows the line with your values.
EOF
}

usage_error() {
  printf 'setup: %s\n\n' "$1" >&2
  usage >&2
  exit 2
}

die() {
  printf '\nsetup: %s\n' "$1" >&2
  exit 1
}

say() { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
# What GitHub or the repository holds is printed as printable ASCII only.
clean() { LC_ALL=C tr -cd '\11\12\40-\176'; }

# Patterns live in variables: bash 3.2 and later read them alike only that way.
LOGIN_RE='^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?$'
ID_RE='^[1-9][0-9]{0,14}$'
SHA_RE='^[0-9a-f]{40}$'
BRANCH_RE='^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$'
CHECK_RE='^[A-Za-z0-9][A-Za-z0-9 ._/():-]{0,99}$'
FULL_NAME_RE='^[A-Za-z0-9-]+/[A-Za-z0-9_-][A-Za-z0-9._-]*$'
DEFAULT_BRANCH_RE='^[A-Za-z0-9._/-]{1,255}$'

valid_login() { [[ $1 =~ $LOGIN_RE ]] && [[ $1 != *--* ]]; }
valid_id() { [[ $1 =~ $ID_RE ]]; }
valid_sha() { [[ $1 =~ $SHA_RE ]]; }
# The app's rule for an integration branch name.
valid_integration() {
  local l
  l=$(lower "$1")
  [[ $1 =~ $BRANCH_RE ]] && [[ $l != workbench-issue-* ]] && [ "$l" != claude ] && [ "$l" != head ] &&
    [[ $1 != *..* ]] && [[ $1 != *. ]] && [[ $1 != *.lock ]]
}
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# ---- Arguments

REPO="" OWNER_ID="" BOT_ID="" INSTALLATION_ID="" INTEGRATION=""
CHECKS=()
EXEMPT=()
while [ $# -gt 0 ]; do
  if [[ $1 == --* && $1 != --help && $# -lt 2 ]]; then usage_error "$1 needs a value."; fi
  case $1 in
    -h | --help)
      usage
      exit 0
      ;;
    --owner-id) OWNER_ID=$2 ;;
    --bot-id) BOT_ID=$2 ;;
    --installation-id) INSTALLATION_ID=$2 ;;
    --integration) INTEGRATION=$2 ;;
    --check) CHECKS+=("$2") ;;
    --exempt) EXEMPT+=("$2") ;;
    -*) usage_error "Unknown option." ;;
    *)
      REPO=$1
      shift
      continue
      ;;
  esac
  shift 2
done

if [ "${#REPO}" -gt 140 ] || ! [[ $REPO =~ $FULL_NAME_RE ]] || ! valid_login "${REPO%%/*}"; then
  usage_error "The repository must be <owner>/<name>, as GitHub shows it."
fi
valid_id "$OWNER_ID" || usage_error "--owner-id must be your GitHub id, a whole number."
valid_id "$BOT_ID" || usage_error "--bot-id must be your session bot's GitHub id, a whole number."
valid_id "$INSTALLATION_ID" || usage_error "--installation-id must be a whole number."
[ "$OWNER_ID" != "$BOT_ID" ] || usage_error "--bot-id must be another account than yours."
valid_integration "$INTEGRATION" ||
  usage_error "--integration must be one branch name of letters, digits, '.', '_' and '-' (not claude, HEAD or workbench-issue-...)."
for c in ${CHECKS[@]+"${CHECKS[@]}"}; do
  [[ $c =~ $CHECK_RE ]] || usage_error "A --check must be a check's name: letters, digits, spaces and . _ / ( ) : -"
done
for l in ${EXEMPT[@]+"${EXEMPT[@]}"}; do
  valid_login "$l" || usage_error "An --exempt must be a GitHub login."
done

# ---- Before anything is read: a terminal, the tools and gh's own settings

if ! { : </dev/tty; } 2>/dev/null; then
  die "This script asks before it changes anything, so it needs a terminal. Run it in one; nothing was read or changed."
fi
for tool in gh git; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is needed. Install it, then run this again."
done
for var in GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN; do
  [ -z "${!var:-}" ] || die "$var is set, which stands in for gh's signed-in accounts. Unset it, then run this again."
done
[ -z "${GH_HOST:-}" ] || [ "$GH_HOST" = github.com ] || die "GH_HOST must be github.com or unset."

work=$(mktemp -d "${TMPDIR:-/tmp}/workbench-setup.XXXXXX")
me_login=""
may_switch=0
finish() {
  if [ "$may_switch" = 1 ] && [ -n "$me_login" ]; then
    gh auth switch -h github.com -u "$me_login" >/dev/null 2>&1 || true
  fi
  rm -rf "$work"
}
trap finish EXIT

# git with none of your own git settings, https only, credentials from gh's
# active account: `gh auth login -p ssh` sets every account's protocol to ssh.
g() {
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 \
    git -c credential.helper= -c 'credential.helper=!gh auth git-credential' \
    -c protocol.allow=never -c protocol.https.allow=always \
    -c core.hooksPath=/dev/null -c commit.gpgsign=false "$@"
}

# The active account's X-OAuth-Scopes, as ", a, b,".
scopes_of() {
  local s
  s=$(gh api -i user 2>/dev/null | tr -d '\r' | sed -n 's/^[Xx]-[Oo][Aa][Uu][Tt][Hh]-[Ss][Cc][Oo][Pp][Ee][Ss]: *//p' | awk 'NR == 1') || s=""
  printf ', %s,' "$s"
}
has_scope() { case $1 in *", $2,"*) return 0 ;; esac; return 1; }

as_bot() {
  local rc=0
  gh auth switch -h github.com -u "$bot_login" >/dev/null 2>&1 || return 1
  "$@" || rc=$?
  gh auth switch -h github.com -u "$me_login" >/dev/null 2>&1 ||
    die "gh couldn't switch back to $me_login. Run: gh auth switch -h github.com -u $me_login"
  return "$rc"
}

# Every value is checked above, so none holds a sed or JSON metacharacter.
fill() {
  sed -e "s/\"__OWNER_ID__\"/$OWNER_ID/g" -e "s/\"__APP_BOT_ID__\"/$APP_BOT_ID/g" \
    -e "s/\"__SESSION_BOT_ID__\"/$BOT_ID/g" \
    -e "s/__APP_BOT_ID__/$APP_BOT_ID/g" -e "s/__APP_SLUG__/$APP_SLUG/g" \
    -e "s/__INTEGRATION__/$INTEGRATION/g" -e "s/__OWNER_LOGIN__/$me_login/g" \
    -e "s/__SESSION_BOT_LOGIN__/$bot_login/g" "$1"
}

add_after() {
  awk -v m="$2" -v x="$3" '{
    i = index($0, m)
    if (i && !done) { $0 = substr($0, 1, i - 1 + length(m)) ", " x substr($0, i + length(m)); done = 1 }
    print
  }' "$1"
}

# The bot ruleset before the integration branch is held: its exclusion left out.
holding() {
  sed -e '/"refs\/heads\/__INTEGRATION__"/d' -e 's/"refs\/heads\/claude\/\*\*",$/"refs\/heads\/claude\/**"/' "$1"
}

urlenc() {
  local LC_ALL=C s=$1 out="" c i
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    case $c in
      [A-Za-z0-9._~-]) out="$out$c" ;;
      *) out="$out$(printf '%%%02X' "'$c")" ;;
    esac
  done
  printf '%s' "$out"
}

# A ruleset as read, projected onto the keys the kit sets, arrays matched by
# rule type, check context or actor, so GitHub's own additions don't count.
# GitHub reads an update rule's false update_allows_fetch_and_merge back as no parameters.
# shellcheck disable=SC2016 # the $ names are jq's own
JQ_FIT='def key: if type == "object" then (.type // .context // ((.actor_type // "") + ":" + ((.actor_id // "") | tostring))) else tojson end;
def fit($w):
  if ($w | type) == "object" then
    (if type == "object" then . else {} end) as $r
    | reduce ($w | keys[]) as $k ({}; .[$k] = ($r[$k] | fit($w[$k])))
  elif ($w | type) == "array" and type == "array" and length == ($w | length) then
    ($w | sort_by(key)) as $ws
    | sort_by(key) as $rs
    | [range(0; $ws | length) as $i | $rs[$i] | fit($ws[$i])]
  else . end;
def norm:
  if type == "object" and (.rules | type) == "array" then
    .rules |= map(if type == "object" and .type == "update"
      then .parameters = ({update_allows_fetch_and_merge: false} + (.parameters // {})) else . end)
  else . end;
def same($w): norm | fit($w) == ($w | fit($w));'
BRANCH_POLICIES='.branch_policies[] | [.id, (.type // "branch"), .name] | map(tostring) | @tsv'

compare_ruleset() {
  local want
  want=$(cat "$2")
  gh api "repos/$REPO/rulesets/$1" \
    --jq "$JQ_FIT if same($want) then \"same\" else \"differs\" end" ||
    die "Couldn't read ruleset $1."
}

plan_lines=()
plan() { plan_lines+=("$*"); }
left_lines=()
left() { left_lines+=("$*"); }

# ---- 1. gh and your two accounts

step "1. gh and your two accounts"
ver=$(gh --version | sed -n '1s/^gh version \([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1 \2/p')
major=${ver% *}
minor=${ver#* }
if [ -z "$ver" ] || [ "$major" -lt 2 ] || { [ "$major" -eq 2 ] && [ "$minor" -lt 40 ]; }; then
  die "gh 2.40 or later is needed; gh --version shows yours."
fi
me=$(gh api user --jq '[.id, .login, .type, .plan.name] | map(tostring) | @tsv') ||
  die "gh isn't signed in. Run: gh auth login -h github.com"
IFS=$'\t' read -r me_id me_login me_type my_plan <<<"$me"
if ! valid_id "$me_id" || ! valid_login "$me_login"; then
  die "GitHub's answer for your account didn't read as expected."
fi
[ "$me_id" = "$OWNER_ID" ] ||
  die "gh's active account is $me_login (id $me_id), not --owner-id: switch to your own account (id $OWNER_ID), not the bot. Run: gh auth switch -h github.com -u <your login>"
[ "$me_type" = User ] || die "Your account must be a personal account."
scopes=$(scopes_of)
if ! has_scope "$scopes" repo || ! has_scope "$scopes" workflow ||
  { ! has_scope "$scopes" read:user && ! has_scope "$scopes" user; }; then
  die "gh as $me_login needs the repo, workflow and read:user scopes. Run: gh auth refresh -h github.com -s workflow,read:user"
fi
say "You: $me_login (id $me_id), with the scopes this needs."

bot=$(gh api "user/$BOT_ID" --jq '[.id, .login, .type] | map(tostring) | @tsv') || die "GitHub has no account with id $BOT_ID (--bot-id)."
IFS=$'\t' read -r bot_id bot_login bot_type <<<"$bot"
[ "$bot_id" = "$BOT_ID" ] && valid_login "$bot_login" && [ "$bot_type" = User ] ||
  die "--bot-id must be a personal GitHub account."
bot_line="As $bot_login, in a browser signed in as $bot_login: gh auth login -h github.com -p ssh --skip-ssh-key --web, then gh auth switch -h github.com -u $me_login"
gh auth token -h github.com -u "$bot_login" >/dev/null 2>&1 || die "Your bot isn't signed in to gh. $bot_line"
bot_identity() {
  local id
  id=$(gh api user --jq .id) || return 1
  printf '%s\t%s\n' "$id" "$(scopes_of)"
}
may_switch=1
who=$(as_bot bot_identity) || die "gh couldn't act as $bot_login. $bot_line"
IFS=$'\t' read -r who_id who_scopes <<<"$who"
[ "$who_id" = "$BOT_ID" ] || die "gh's account $bot_login isn't --bot-id."
if ! has_scope "$who_scopes" repo || has_scope "$who_scopes" workflow || has_scope "$who_scopes" delete_repo ||
  [[ $who_scopes == *", admin:"* ]]; then
  die "Your bot's gh login must have repo and none of workflow, admin:* or delete_repo. Sign it in again: $bot_line"
fi
say "Your bot: $bot_login (id $bot_id), signed in to gh without workflow."

APP_ID=$(gh api "apps/$APP_SLUG" --jq .id) || die "Couldn't read the Code App."
valid_id "$APP_ID" || die "GitHub's answer for the Code App didn't read as expected."

exempt_extra=""
for l in ${EXEMPT[@]+"${EXEMPT[@]}"}; do
  u_id=$(gh api "users/$l" --jq .id) || die "GitHub has no account named in --exempt."
  valid_id "$u_id" || die "GitHub's answer for an --exempt didn't read as expected."
  [ "$u_id" != "$BOT_ID" ] || die "Your bot can't be exempt from the bot ruleset."
  exempt_extra="$exempt_extra${exempt_extra:+, }{ \"actor_id\": $u_id, \"actor_type\": \"User\", \"bypass_mode\": \"always\" }"
  say "Exempt from the bot ruleset: $l (id $u_id)."
done

# ---- 2. The repository

step "2. The repository"
info=$(gh api "repos/$REPO" --jq '[.id, .full_name, .owner.id, .owner.type, .archived, .private, .default_branch,
  .allow_merge_commit] | map(tostring) | @tsv') ||
  die "Couldn't read $REPO. Check its name, and that gh as $me_login can see it."
IFS=$'\t' read -r repo_id full_name repo_owner_id repo_owner_type archived private default_branch merge_commit <<<"$info"
valid_id "$repo_id" && [[ $full_name =~ $FULL_NAME_RE ]] && [ "$(lower "$full_name")" = "$(lower "$REPO")" ] ||
  die "GitHub's answer for $REPO didn't read as expected."
REPO=$full_name
[ "$repo_owner_id" = "$OWNER_ID" ] && [ "$repo_owner_type" = User ] ||
  die "$REPO isn't on your own account. The workbench lane is for your own repositories."
[ "$archived" = false ] || die "$REPO is archived."
[[ $default_branch =~ $DEFAULT_BRANCH_RE ]] && [[ $default_branch != *..* ]] ||
  die "$REPO's default branch has a name this script doesn't handle."
if [ "$private" = true ]; then
  [ "$my_plan" != free ] && [ "$my_plan" != null ] ||
    die "$REPO is private, and private repositories need a paid GitHub plan for rulesets and environments. Make it public, or upgrade."
  say "$REPO is private, on your $my_plan plan."
else
  say "$REPO is public. Its Actions logs, launch inputs included, are public to anyone signed in to GitHub."
fi
[ "$(lower "$INTEGRATION")" != "$(lower "$default_branch")" ] ||
  die "The integration branch can't be $REPO's default branch ($default_branch). Choose another name."
say "Default branch: $default_branch. Integration branch: $INTEGRATION."

# ---- 3. Secrets

step "3. Secrets"
n=$(gh api "repos/$REPO/actions/secrets" --jq .total_count) || die "Couldn't read $REPO's Actions secrets."
[ "$n" = 0 ] || die "$REPO has $n Actions repository secret(s). Any workflow run on a bot branch could read them: move each into an environment limited to the branch that needs it, or delete it, then run this again."
n=$(gh api "repos/$REPO/dependabot/secrets" --jq .total_count) || die "Couldn't read $REPO's Dependabot secrets."
[ "$n" = 0 ] || die "$REPO has $n Dependabot secret(s). Move or delete them, then run this again."
envs=$(gh api "repos/$REPO/environments?per_page=100" --paginate \
  --jq '.environments[] | [(.deployment_branch_policy.custom_branch_policies == true), .name] | map(tostring) | @tsv') ||
  die "Couldn't read $REPO's environments."
# A deployment rule the bot can't meet: a literal branch name, none of its own.
UNSAFE_POLICIES='[.branch_policies[] | select((.type // "branch") != "branch" or (.name | test("[*?\\[\\]{}\\\\]"))
  or (.name | startswith("claude/")) or (.name | startswith("workbench-issue-")))] | length'
has_routine_env=false
open_envs=""
while IFS=$'\t' read -r custom name; do
  [ -n "${name:-}" ] || continue
  if [ "$name" = routine-fire ]; then
    has_routine_env=true
    continue
  fi
  e=$(urlenc "$name")
  n=$(gh api "repos/$REPO/environments/$e/secrets" --jq .total_count) || die "Couldn't read an environment's secrets."
  [ "$n" != 0 ] || continue
  unsafe=1
  if [ "$custom" = true ]; then
    unsafe=$(gh api "repos/$REPO/environments/$e/deployment-branch-policies?per_page=100" --jq "$UNSAFE_POLICIES") ||
      die "Couldn't read an environment's deployment rules."
  fi
  [ "$unsafe" = 0 ] || open_envs="$open_envs $(printf '%s' "$name" | clean | cut -c1-60)"
done <<<"$envs"
[ -z "$open_envs" ] || die "These environments have secrets and a deployment rule a bot branch could meet:$open_envs. Limit each to literal branch names (no patterns, nothing under claude/ or workbench-issue-), then run this again."
say "No repository secrets, and every environment with secrets is limited to named branches."

# ---- 4. The workflow audit

step "4. Workflows the App or a stranger can start"
g clone --bare --quiet "https://github.com/$REPO.git" "$work/audit.git" || die "Couldn't clone $REPO over https."
hits=""
while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  h=$(g -C "$work/audit.git" grep -I -n -E "$AUDIT_RE" "$ref" -- .github/workflows \
    ':(exclude).github/workflows/workbench-launch.yml' 2>/dev/null) || h=""
  [ -z "$h" ] || hits="$hits$h"$'\n'
done <<<"$(g -C "$work/audit.git" for-each-ref --format='%(refname)' refs/heads refs/tags)"
hits=$(printf '%s' "$hits" | clean | cut -c1-200 | awk 'NR <= 200')
if [ -n "$hits" ]; then
  say "The App can dispatch any workflow_dispatch workflow, on any branch or tag. These lines, on every branch and tag, need a look:"
  printf '%s\n' "$hits" | sed 's/^/  /'
  if [ "$private" = false ] && printf '%s\n' "$hits" | grep -E 'pull_request_target|workflow_run' >/dev/null; then
    die "On a public repository, pull_request_target and workflow_run let a stranger's pull request run with your secrets. Remove them from every branch and tag, then run this again."
  fi
  left "Check the audit's lines above: each workflow_dispatch or repository_dispatch workflow guards on the actor or is harmless when the App starts it, and each write-all is needed."
else
  say "No workflow_dispatch, repository_dispatch, pull_request_target, workflow_run, id-token: write or write-all in any workflow."
fi

# ---- 5. What is set up already

step "5. What is set up already"
int_sha=$(gh api "repos/$REPO/git/matching-refs/heads/$INTEGRATION" \
  --jq ".[] | select(.ref == \"refs/heads/$INTEGRATION\") | .object.sha") || die "Couldn't read $REPO's branches."
[ -z "$int_sha" ] || valid_sha "$int_sha" || die "GitHub's answer for $INTEGRATION didn't read as expected."

for name in $NAMES; do
  fill "$KIT/rulesets/$name.json" >"$work/$name.json"
done
holding "$KIT/rulesets/bot.json" >"$work/bot-holding.tmp"
fill "$work/bot-holding.tmp" >"$work/bot-holding.json"
if [ -n "$exempt_extra" ]; then
  for f in bot bot-holding; do
    add_after "$work/$f.json" "$ADMIN_ALWAYS" "$exempt_extra" >"$work/$f.tmp" && mv "$work/$f.tmp" "$work/$f.json"
  done
fi
add_after "$work/d1.json" "$ADMIN_ALWAYS" "{ \"actor_id\": $APP_ID, \"actor_type\": \"Integration\", \"bypass_mode\": \"always\" }" >"$work/d1-app.json"
if [ "${#CHECKS[@]}" -gt 0 ]; then
  list=""
  for c in "${CHECKS[@]}"; do
    list="$list${list:+, }{ \"context\": \"$c\", \"integration_id\": $GITHUB_ACTIONS_APP_ID }"
  done
  add_after "$work/d2.json" "$D2_LAST_RULE" \
    "{ \"type\": \"required_status_checks\", \"parameters\": { \"strict_required_status_checks_policy\": false, \"required_status_checks\": [$list] } }" \
    >"$work/d2.tmp" && mv "$work/d2.tmp" "$work/d2.json"
fi

rulesets=$(gh api "repos/$REPO/rulesets?includes_parents=false&per_page=100" --paginate --jq '.[] | [.id, .name] | map(tostring) | @tsv') ||
  die "Couldn't read $REPO's rulesets."
# Sets rs_<name>_id (or none) and rs_<name>_action: create, keep, keep-app or replace.
for name in $NAMES; do
  id=$(printf '%s\n' "$rulesets" | awk -F '\t' -v n="workbench-$name" '$2 == n { print $1; exit }')
  [ -z "$id" ] || valid_id "$id" || die "GitHub's ruleset list didn't read as expected."
  action=create
  if [ -n "$id" ]; then
    action=replace
    [ "$(compare_ruleset "$id" "$work/$name.json")" = same ] && action=keep
    if [ "$name" = d1 ] && [ "$(compare_ruleset "$id" "$work/d1-app.json")" = same ]; then action=keep-app; fi
  fi
  case $name in
    bot) rs_bot_id=$id rs_bot_action=$action ;;
    tags) rs_tags_id=$id rs_tags_action=$action ;;
    d1) rs_d1_id=$id rs_d1_action=$action ;;
    d2) rs_d2_id=$id rs_d2_action=$action ;;
    d3) rs_d3_id=$id rs_d3_action=$action ;;
  esac
done
# The bot ruleset leaves the integration branch out only while D1 and D3 hold it.
if [ "$rs_bot_action" = keep ] && { [ "${rs_d1_action#keep}" = "$rs_d1_action" ] || [ "$rs_d3_action" != keep ]; }; then
  rs_bot_action=replace
fi

# A branch of that name that D3 doesn't hold yet is taken over only if it has
# nothing the default branch lacks, so no one's commits become the lane's base.
d3_holds=false
if [ -n "$rs_d3_id" ]; then
  d3_holds=$(gh api "repos/$REPO/rulesets/$rs_d3_id" \
    --jq "(.enforcement == \"active\") and ((.conditions.ref_name.include // []) | index(\"refs/heads/$INTEGRATION\") != null)") ||
    die "Couldn't read ruleset workbench-d3."
fi
unreviewed=false
if [ -n "$int_sha" ] && [ "$d3_holds" = true ]; then
  if [ "$rs_d1_action" = create ] || [ "$rs_d2_action" = create ]; then unreviewed=true; fi
elif [ -n "$int_sha" ]; then
  status=$(gh api "repos/$REPO/compare/$INTEGRATION...$default_branch" --jq .status) || die "Couldn't compare $INTEGRATION with $default_branch."
  case $status in
    identical | ahead) ;;
    *) die "$INTEGRATION already exists with commits $default_branch doesn't have. Choose another name, or delete that branch." ;;
  esac
fi

base=${int_sha:+$INTEGRATION}
base=${base:-$default_branch}
g clone --quiet --depth 1 --branch "$base" "https://github.com/$REPO.git" "$work/tree" ||
  die "Couldn't clone $REPO's $base over https. A repository needs one commit at least."
base_sha=$(g -C "$work/tree" rev-parse HEAD)
valid_sha "$base_sha" || die "The clone didn't read as expected."
[ -z "$int_sha" ] || [ "$base_sha" = "$int_sha" ] || die "$INTEGRATION moved while this ran. Run this again."
t=$work/tree
for p in .workbench .workbench/agents .workbench/launch.md .workbench/relay.md .workbench/steps.md \
  .workbench/authors.json .github .github/workflows .github/workflows/workbench-launch.yml .github/CODEOWNERS; do
  [ ! -L "$t/$p" ] || die "$p is a symlink on $base. Replace it with a real file or folder, then run this again."
done
if [ ! -e "$t/.github/CODEOWNERS" ] && { [ -e "$t/CODEOWNERS" ] || [ -e "$t/docs/CODEOWNERS" ]; }; then
  die "$REPO's CODEOWNERS isn't in .github/, and a new .github/CODEOWNERS would take its place. Move it to .github/CODEOWNERS, then run this again."
fi
mkdir -p "$t/.workbench" "$t/.github/workflows"
fill "$KIT/files/dot-workbench/launch.md" >"$t/.workbench/launch.md"
fill "$KIT/files/dot-workbench/relay.md" >"$t/.workbench/relay.md"
fill "$KIT/files/dot-workbench/authors.json" >"$t/.workbench/authors.json"
fill "$KIT/files/dot-github/workflows/workbench-launch.yml" >"$t/.github/workflows/workbench-launch.yml"
# steps.md and the agents are yours after the first run.
[ -e "$t/.workbench/steps.md" ] || cp "$KIT/files/dot-workbench/steps.md" "$t/.workbench/steps.md"
if [ ! -e "$t/.workbench/agents" ]; then
  mkdir "$t/.workbench/agents"
  cp "$KIT"/files/dot-workbench/agents/*.md "$t/.workbench/agents/"
fi
# Last, so no earlier line overrides them.
fill "$KIT/files/dot-github/CODEOWNERS" >"$work/owners"
if [ -f "$t/.github/CODEOWNERS" ]; then
  grep -v -x -F -f "$work/owners" "$t/.github/CODEOWNERS" >"$work/owners.new" || true
else
  : >"$work/owners.new"
fi
cat "$work/owners" >>"$work/owners.new"
mv "$work/owners.new" "$t/.github/CODEOWNERS"
g -C "$t" add -A .workbench .github
kit_action=none
if ! g -C "$t" diff --cached --quiet; then
  kit_files=$(g -C "$t" diff --cached --name-only | clean)
  g -C "$t" -c user.name="$me_login" -c user.email="$me_id+$me_login@users.noreply.github.com" \
    commit --quiet -m "Set up the workbench lane"
  # Once D2 holds the integration branch, the kit's changes need a pull request.
  kit_action="pr"
  if [ -z "$int_sha" ] || [ "$rs_d2_action" = create ]; then kit_action=push; fi
fi

routine_env=keep
if [ "$has_routine_env" = false ]; then
  routine_env=create
else
  policy=$(gh api "repos/$REPO/environments/routine-fire" \
    --jq '[.deployment_branch_policy.custom_branch_policies, .deployment_branch_policy.protected_branches] | map(tostring) | @tsv') ||
    die "Couldn't read routine-fire."
  branches=$(gh api "repos/$REPO/environments/routine-fire/deployment-branch-policies?per_page=100" \
    --jq "$BRANCH_POLICIES" 2>/dev/null) || branches=""
  [ "$policy" = $'true\tfalse' ] && [ "$(printf '%s\n' "$branches" | grep -c .)" = 1 ] &&
    [ "$(printf '%s' "$branches" | cut -f 2-)" = "branch"$'\t'"$INTEGRATION" ] || routine_env=fix
fi
secrets_missing=" ROUTINE_FIRE_TOKEN ROUTINE_FIRE_URL"
if [ "$has_routine_env" = true ]; then
  have=$(gh api "repos/$REPO/environments/routine-fire/secrets" --jq '.secrets[].name') || die "Couldn't read routine-fire's secrets."
  secrets_missing=""
  for s in ROUTINE_FIRE_TOKEN ROUTINE_FIRE_URL; do
    printf '%s\n' "$have" | grep -x "$s" >/dev/null || secrets_missing="$secrets_missing $s"
  done
fi

# The bot must hold write and no more: an admin passes every ruleset.
role=$(gh api "repos/$REPO/collaborators?affiliation=direct&per_page=100" --paginate \
  --jq ".[] | select(.id == $BOT_ID) | .role_name") || die "Couldn't read $REPO's collaborators."
collab_action=keep
if [ -n "$role" ]; then
  [ "$role" = write ] || die "$bot_login is a collaborator with the $(printf '%s' "$role" | clean) role; it must be write. Change it in Settings > Collaborators, then run this again."
else
  invited=$(gh api "repos/$REPO/invitations?per_page=100" --paginate --jq ".[] | select(.invitee.id == $BOT_ID) | .permissions") ||
    die "Couldn't read $REPO's invitations."
  collab_action=invite
  if [ -n "$invited" ]; then
    [ "$invited" = write ] || die "$bot_login's invitation isn't for write. Cancel it, then run this again."
    collab_action=accept
  fi
fi

settings_fix=false
[ "$merge_commit" = true ] || settings_fix=true
wf=$(gh api "repos/$REPO/actions/permissions/workflow" --jq '[.default_workflow_permissions, .can_approve_pull_request_reviews] | map(tostring) | @tsv') ||
  die "Couldn't read $REPO's Actions settings."
workflow_fix=false
[ "$wf" = $'read\tfalse' ] || workflow_fix=true
fork_fix=false
if [ "$private" = false ]; then
  fp=$(gh api "repos/$REPO/actions/permissions/fork-pr-contributor-approval" --jq .approval_policy 2>/dev/null) || fp=""
  [ "$fp" = all_external_contributors ] || fork_fix=true
fi

# ---- The plan

plan_ruleset() {
  case $1 in
    create) plan "Create ruleset workbench-$2: $3" ;;
    replace) plan "Replace ruleset workbench-$2, which differs from the kit's: $3" ;;
  esac
}

step "What this will change on $REPO"
plan_ruleset "$rs_bot_action" bot "your bot creates, updates and deletes only workbench-issue-* and claude/** (written first without $INTEGRATION, which is left out last)."
[ -n "$int_sha" ] || plan "Create $INTEGRATION from $default_branch."
[ "$unreviewed" = false ] || plan "Note: $INTEGRATION was held by workbench-d3 without D1 or D2, so it may hold commits no one reviewed: check https://github.com/$REPO/compare/$default_branch...$INTEGRATION"
plan_ruleset "$rs_d3_action" d3 "only repository admins create or delete $INTEGRATION."
plan_ruleset "$rs_d1_action" d1 "only repository admins (and, at the end, the App) update $INTEGRATION."
case $kit_action in
  push) plan "Commit .workbench/, workbench-launch.yml and the CODEOWNERS lines to $INTEGRATION as $me_login:" ;;
  pr) plan "Open a pull request into $INTEGRATION with the kit's changes (D2 needs one), for you to merge:" ;;
esac
if [ "$kit_action" != none ]; then
  while IFS= read -r f; do plan "    $f"; done <<<"$kit_files"
fi
plan_ruleset "$rs_d2_action" d2 "pull requests into $INTEGRATION need your Code Owners review on .workbench/ and the session's boot files."
plan_ruleset "$rs_tags_action" tags "only repository admins create, update or delete tags."
[ "$settings_fix" = false ] || plan "Allow merge commits (the app merges with one)."
[ "$workflow_fix" = false ] || plan "Make Actions' default token read-only, and stop Actions approving pull requests."
[ "$fork_fix" = false ] || plan "Require approval for every outside contributor's fork pull request runs."
case $routine_env in
  create) plan "Create the routine-fire environment, deployable from $INTEGRATION only." ;;
  fix) plan "Limit the routine-fire environment to $INTEGRATION only." ;;
esac
case $collab_action in
  invite) plan "Invite $bot_login with write, and accept as $bot_login (gh auth switch)." ;;
  accept) plan "Accept the pending invitation as $bot_login (gh auth switch)." ;;
esac
[ -z "$secrets_missing" ] || plan "Ask you for routine-fire's secrets:$secrets_missing (gh secret set prompts; nothing is shown)."
[ "$rs_d1_action" = keep-app ] || plan "Add the Code App to workbench-d1's bypass list, once you've added $REPO to its installation."

if [ "${#plan_lines[@]}" -eq 0 ]; then
  say "Nothing: $REPO is set up."
else
  for l in "${plan_lines[@]}"; do
    case $l in
      " "*) say "$l" ;;
      *) say "- $l" ;;
    esac
  done
  printf '\nContinue? [y/N] '
  answer=""
  read -r answer </dev/tty || answer=""
  case $answer in
    y | Y | yes | Yes | YES) ;;
    *) die "Nothing was changed." ;;
  esac

  # Arguments: the ruleset's id (or none), its action, name and file. Leaves its id in written_id.
  write_ruleset() {
    written_id=$1
    case $2 in
      create)
        written_id=$(gh api -X POST "repos/$REPO/rulesets" --input "$4" --jq .id) || die "GitHub refused ruleset $3."
        valid_id "$written_id" || die "GitHub's answer for ruleset $3 didn't read as expected."
        ;;
      replace) gh api -X PUT "repos/$REPO/rulesets/$1" --input "$4" --silent || die "GitHub refused ruleset $3." ;;
      *) return 0 ;;
    esac
    [ "$(compare_ruleset "$written_id" "$4")" = same ] || die "GitHub didn't keep ruleset $3 as written."
    say "Ruleset $3: done."
  }

  step "Writing"
  write_ruleset "$rs_bot_id" "$rs_bot_action" "workbench-bot (holding)" "$work/bot-holding.json"
  rs_bot_id=$written_id
  if [ -z "$int_sha" ]; then
    gh api -X POST "repos/$REPO/git/refs" -f ref="refs/heads/$INTEGRATION" -f sha="$base_sha" --silent ||
      die "Couldn't create $INTEGRATION."
    say "$INTEGRATION: created at $default_branch's head."
  fi
  write_ruleset "$rs_d3_id" "$rs_d3_action" workbench-d3 "$work/d3.json"
  write_ruleset "$rs_d1_id" "$rs_d1_action" workbench-d1 "$work/d1.json"
  rs_d1_id=$written_id
  case $kit_action in
    push)
      g -C "$t" push --quiet origin "HEAD:refs/heads/$INTEGRATION" ||
        die "Couldn't push the kit to $INTEGRATION. If it moved meanwhile, run this again."
      say "The kit: committed to $INTEGRATION."
      ;;
    pr)
      kit_branch="workbench-setup-$(g -C "$t" rev-parse --short=12 HEAD)"
      g -C "$t" push --quiet origin "HEAD:refs/heads/$kit_branch" || die "Couldn't push $kit_branch."
      pr=$(gh api "repos/$REPO/pulls?state=open&head=$me_login:$kit_branch&base=$INTEGRATION" --jq '.[0].number // empty') ||
        die "Couldn't read $REPO's pull requests."
      if [ -z "$pr" ]; then
        pr=$(gh api -X POST "repos/$REPO/pulls" -f head="$kit_branch" -f base="$INTEGRATION" \
          -f title="Update the workbench kit" \
          -f body="From the workbench setup script: the kit's launch core, relay, authors, launch workflow and CODEOWNERS lines." \
          --jq .number) || die "Couldn't open the kit's pull request."
      fi
      valid_id "$pr" || die "GitHub's answer for the kit's pull request didn't read as expected."
      say "The kit: pull request https://github.com/$REPO/pull/$pr."
      left "Review and merge https://github.com/$REPO/pull/$pr (the kit's update) into $INTEGRATION."
      ;;
  esac
  write_ruleset "$rs_d2_id" "$rs_d2_action" workbench-d2 "$work/d2.json"
  write_ruleset "$rs_tags_id" "$rs_tags_action" workbench-tags "$work/tags.json"

  if [ "$settings_fix" = true ]; then
    gh api -X PATCH "repos/$REPO" -F allow_merge_commit=true --silent || die "Couldn't allow merge commits."
    say "Merge commits: allowed."
  fi
  if [ "$workflow_fix" = true ]; then
    gh api -X PUT "repos/$REPO/actions/permissions/workflow" -f default_workflow_permissions=read \
      -F can_approve_pull_request_reviews=false --silent || die "Couldn't change $REPO's Actions settings."
    say "Actions' token: read-only."
  fi
  if [ "$fork_fix" = true ]; then
    gh api -X PUT "repos/$REPO/actions/permissions/fork-pr-contributor-approval" \
      -f approval_policy=all_external_contributors --silent || die "Couldn't set fork pull request approval."
    say "Fork pull requests: approval required for every outside contributor."
  fi

  if [ "$routine_env" != keep ]; then
    printf '{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}\n' >"$work/env.json"
    gh api -X PUT "repos/$REPO/environments/routine-fire" --input "$work/env.json" --silent ||
      die "Couldn't set up routine-fire."
    branches=$(gh api "repos/$REPO/environments/routine-fire/deployment-branch-policies?per_page=100" \
      --jq "$BRANCH_POLICIES") || die "Couldn't read routine-fire's branches."
    keep_policy=""
    while IFS=$'\t' read -r pid ptype pname; do
      [ -n "${pid:-}" ] || continue
      valid_id "$pid" || die "routine-fire's branch list didn't read as expected."
      if [ -z "$keep_policy" ] && [ "$ptype" = branch ] && [ "$pname" = "$INTEGRATION" ]; then
        keep_policy=$pid
      else
        gh api -X DELETE "repos/$REPO/environments/routine-fire/deployment-branch-policies/$pid" --silent ||
          die "Couldn't remove a routine-fire branch rule."
      fi
    done <<<"$branches"
    if [ -z "$keep_policy" ]; then
      gh api -X POST "repos/$REPO/environments/routine-fire/deployment-branch-policies" \
        -f name="$INTEGRATION" -f type=branch --silent || die "Couldn't limit routine-fire to $INTEGRATION."
    fi
    say "routine-fire: deployable from $INTEGRATION only."
  fi

  accept_invite() {
    local id
    id=$(gh api "user/repository_invitations?per_page=100" --paginate \
      --jq ".[] | select(.repository.id == $repo_id) | .id" | awk 'NR == 1') || return 1
    valid_id "$id" || return 1
    gh api -X PATCH "user/repository_invitations/$id" --silent
  }
  if [ "$collab_action" = invite ]; then
    gh api -X PUT "repos/$REPO/collaborators/$bot_login" -f permission=push --silent ||
      die "Couldn't invite $bot_login."
  fi
  if [ "$collab_action" != keep ]; then
    as_bot accept_invite || die "$bot_login couldn't accept the invitation. Accept it at https://github.com/$REPO/invitations as $bot_login."
    say "$bot_login: a collaborator."
  fi
fi

# ---- The scheduled task (claude.ai calls routines scheduled tasks)

step "The scheduled task (https://claude.ai/code/routines > New task)"
say "  Repository:  $REPO"
say "  Branch:      $default_branch"
say "  Environment: your cloud environment, with the ingest host in its allowed domains and your relay token as its Network secret"
say "  Model:       your choice; it is the coordinator's"
say "  Prompt:"
fill "$KIT/routine-prompt.txt" | sed 's/^/    /'
say "  Then add an API trigger: its token and URL are routine-fire's two secrets."

for s in $secrets_missing; do
  say ""
  case $s in
    ROUTINE_FIRE_TOKEN) say "Paste the API trigger's token (shown first) at gh's \"Paste your secret\" prompt. It is hidden as you type." ;;
    *) say "Now paste the API trigger's URL at gh's \"Paste your secret\" prompt." ;;
  esac
  gh secret set "$s" --env routine-fire --repo "$REPO" </dev/tty ||
    left "Set $s: gh secret set $s --env routine-fire --repo $REPO"
done

# ---- The App, then the bot ruleset's last exclusion

if [ "${#plan_lines[@]}" -gt 0 ]; then
  if [ "$rs_d1_action" != keep-app ]; then
    step "The Code App"
    say "Open https://github.com/settings/installations/$INSTALLATION_ID, add $REPO under Repository access (Only select repositories), and save."
    printf 'Press Enter once it is saved. '
    read -r _ </dev/tty || true
    if gh api -X PUT "repos/$REPO/rulesets/$rs_d1_id" --input "$work/d1-app.json" --silent &&
      [ "$(compare_ruleset "$rs_d1_id" "$work/d1-app.json")" = same ]; then
      say "workbench-d1: the App can now merge into $INTEGRATION."
    else
      left "Add the Code App to ruleset workbench-d1's bypass list (Always), then run this again to check it."
    fi
  fi
  if [ "$rs_bot_action" != keep ]; then
    gh api -X PUT "repos/$REPO/rulesets/$rs_bot_id" --input "$work/bot.json" --silent &&
      [ "$(compare_ruleset "$rs_bot_id" "$work/bot.json")" = same ] ||
      die "GitHub didn't take workbench-bot's exclusion of $INTEGRATION. Run this again."
    say "Ruleset workbench-bot: $INTEGRATION left out, now that D1 and D3 hold it."
  fi
fi

# ---- What is left

step "What is left"
for l in ${left_lines[@]+"${left_lines[@]}"}; do say "- $l"; done
say "- In the Assistant app (not GitHub or claude.ai), Settings > Code > GitHub: this repository's setup status should show every item done."
say "- Merge $INTEGRATION into $default_branch whenever you like; bring $default_branch into $INTEGRATION by a pull request you merge."
say "- Once every repository is set up, sign your bot out of gh: gh auth logout -h github.com -u $bot_login"
