# Launch steps

## new_branch
label: New branch, after merging the latest integration branch
templates: coordinator_full_review, quick_fix, plan_only

Start from the approved commit (step 7), and merge the newest `origin/$INTEGRATION` (from `checked.env`) into the branch again before you open or update the PR

## read_code_first
label: Read the code first
templates: coordinator_full_review, quick_fix, plan_only

Read the code the task touches, and the docs that cover it, before you change anything, to get a better understand of the codebase and application

## plan_first
label: Plan first and wait for my approval
templates: coordinator_full_review, plan_only

Write a plan that ends with a Stages list (2 to 10 short names, one per line, each at most 60 characters). Publish it as a Docs-type artifact (step 8's artifact rules); if `wireframe_for_ui` is ticked and the work has UI, the wireframe goes on the doc's Wireframe tab. Relay `artifact` with its link, then `plan_ready`, and wait for the owner's approval of the plan, its stages and any wireframe, together, before writing code. Then relay `stages` (step 8).

## ask_when_unsure
label: Ask me questions when unsure
templates: coordinator_full_review, plan_only

When something is ambiguous, ask the owner in the session and relay `question`; wait for the answer instead of guessing

## concise
label: Concise replies
templates: coordinator_full_review, quick_fix, plan_only

Keep your replies in the session short and concise

## open_pr_watch_ci
label: Open a PR and watch CI
templates: coordinator_full_review, quick_fix

Open the PR into the integration branch (step 7), watch its checks until they finish, and fix failures your change caused

## wireframe_for_ui
label: Wireframe tab in the plan for UI work
templates: coordinator_full_review

For UI work, put a wireframe on its own tab of the plan's doc, named Wireframe, after the main tab: a drawn mock-up of each screen the work touches, its layout and its states (empty, loading, error), with synthetic data. Never ASCII, never a section of the main tab, never a separate artifact (step 8's artifact rules). Add it before `plan_ready`. It is approved with the plan (or, without `plan_first`, with its short plan), never on its own: UI tasks need no further approval and are not held back or run after API tasks for it; web and API tasks run in parallel against the plan's written shared contract. If `plan_first` is not ticked, publish a Docs-type artifact with a short plan ending with its Stages list on the main tab and the wireframe on its Wireframe tab, relay `artifact`, then `plan_ready`, and wait for the owner's approval before any UI code.

## comments_only_when_needed
label: Comments in code only when needed
templates: coordinator_full_review, quick_fix

Write code comments only where they are absolutely needed. The code should generally be readable by itself. Keep any comments brief and concise.
