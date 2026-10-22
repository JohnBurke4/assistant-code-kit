# Relay

How a launched session sends its short structured updates to the app's run page: one `curl` POST per event to the relay ingest's MCP endpoint, by the script below. Only for a session started by the launch routine, after `.workbench/launch.md`'s step 1 passed. Nothing goes on GitHub: never post an event as a comment, by `gh api` or any other way.

The relay token is not in this session and never is: the cloud environment's Network secret, bound to the ingest host alone, adds it on the way out. Never add an `Authorization` header, and never look for the token.

## The event

Write the event with your Write tool to `/tmp/assistant-launch/event.json`, as a JSON object of `event`, `summary`, and `link` or `pr` where the table allows them, and nothing else:

- `event` is one of the events below;
- `link` only where the table allows it; `pr` as a number, only where the table allows it;
- `summary` as the rules below say.

The run's id and key are not in it: the script adds them from `/tmp/assistant-launch/run.json`, which `launch.md`'s step 1 wrote once the payload passed. They never go into a command, a file you write, a summary or the chat. Without `run.json`, send nothing.

## Events

| Event        | When                                                                   | `link`                     | `pr`                                           |
| ------------ | ---------------------------------------------------------------------- | -------------------------- | ---------------------------------------------- |
| `started`    | The launch checks passed, before any work                              | The session link           | No                                             |
| `question`   | You are waiting for the owner's answer in the session                  | Optional, the session link | No                                             |
| `plan_ready` | A plan is ready and you are waiting for the owner's approval           | Optional, the session link | No                                             |
| `artifact`   | After you publish an artifact (the plan's, before `plan_ready`)        | The published artifact     | No                                             |
| `stages`     | Right after the owner approves the plan (no plan: before first change) | No                         | No                                             |
| `stage`      | When a stage starts                                                    | No                         | No                                             |
| `stage_done` | When a stage is finished                                               | No                         | No                                             |
| `done`       | The work is finished                                                   | Optional, the session link | Your PR into the integration branch, once open |
| `failed`     | The launch checks failed, or the work stopped and can't go on          | Optional, the session link | Your PR into the integration branch, if open   |

## Rules

- `link` is only the session link, or `https://claude.ai/artifact/<id>` or `https://claude.ai/code/artifact/<uuid>` of an artifact you made in this session, shared or private. Never any other URL.
- `pr` is only the number of the PR you opened into the integration branch from `workbench-issue-<issue>`.
- The summary is plain text, 1 to 1,000 characters, in your own words: no Markdown, HTML or URLs, no `<`, no secrets, tokens or environment values, and no quoted issue or comment text.
- For `stages`, the summary is the stages in order, one per line: 2 to 10 lines, each 1 to 60 characters with something visible. For `stage`, it starts with the stage's number in that list and `. `, then what the stage is doing. Send `stages` again if the stages change (it clears the marks), then `stage_done` for each stage already finished and `stage` for the one in progress.
- For `stage_done`, the summary has the `stage` grammar: the stage's number in that list and `. `, then what was finished.

Examples of `event.json`:

```json
{ "event": "stages", "summary": "Plan the change\nWrite the code\nReview the diff\nOpen the PR" }
```

```json
{ "event": "stage", "summary": "2. Writing the parser and its tests." }
```

```json
{ "event": "stage_done", "summary": "2. Parser and its tests committed." }
```

```json
{
  "event": "done",
  "pr": 42,
  "summary": "The parser and its tests are in the PR into the integration branch."
}
```

The session link, for `started`, comes from `CLAUDE_CODE_REMOTE_SESSION_ID` (its `cse_` prefix becomes `session_`). Run this verbatim and use the URL it prints; on `FAIL`, leave `link` out:

```sh
node -e '
const s = (process.env.CLAUDE_CODE_REMOTE_SESSION_ID || "").replace(/^cse_/, "session_");
console.log(/^session_[0-9A-Za-z]{1,64}$/.test(s) ? "https://claude.ai/code/" + s : "FAIL");
'
```

## Send

Run this verbatim after each `event.json` you write. It builds one JSON-RPC call of the ingest's `relay` tool in a file readable by you alone, adds the run's id and key from `run.json`, posts the file with `curl --data @file`, deletes it, and prints one line: `Recorded.`, `Not recorded.`, or `Refused <field>`.

```sh
node -e '
const fs = require("fs"), cp = require("child_process");
const OUT = "/tmp/assistant-launch/";
const ENDPOINT = "https://taskmanager-ingest-972519281630.europe-west1.run.app/mcp";
const FIELDS = ["run_id", "run_key", "event", "link", "pr", "summary", "arguments"];
const say = (w) => { console.log(w); process.exit(0); };
let run, ev;
try {
  run = JSON.parse(fs.readFileSync(OUT + "run.json", "utf8"));
  ev = JSON.parse(fs.readFileSync(OUT + "event.json", "utf8"));
} catch { say("Not recorded."); }
if (ev === null || typeof ev !== "object" || Array.isArray(ev) || !Object.keys(ev).every((k) => ["event", "link", "pr", "summary"].includes(k))) say("Refused arguments");
const body = { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "relay", arguments: { ...ev, run_id: run.run_id, run_key: run.run_key } } };
fs.writeFileSync(OUT + "relay-body.json", JSON.stringify(body), { mode: 0o600 });
let answer = "";
try {
  answer = cp.execFileSync("curl", ["-q", "-sS", "--max-time", "20", "-X", "POST", "-H", "content-type: application/json", "--data", "@" + OUT + "relay-body.json", ENDPOINT], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], maxBuffer: 65536 });
} catch { answer = ""; }
fs.rmSync(OUT + "relay-body.json", { force: true });
let a = null;
try { a = JSON.parse(answer); } catch {}
const res = a && typeof a === "object" && a.result && typeof a.result === "object" ? a.result : null;
const first = res && Array.isArray(res.content) ? res.content[0] : null;
const text = first && first.type === "text" && typeof first.text === "string" ? first.text : "";
if (res && res.isError !== true && text === "Recorded.") say("Recorded.");
const field = res && res.isError === true ? FIELDS.find((f) => text.startsWith(f + " ")) : undefined;
say(field ? "Refused " + field : "Not recorded.");
'
```

1. Count your events, resends included. Send at most 50, keeping the last of them for `done` or `failed`; after the 50th, send no more.
2. `Recorded.` means the event landed.
3. `Refused <field>` names a field (`run_id`, `run_key`, `event`, `link`, `pr`, `summary` or `arguments`) whose rule the event broke, and nothing was recorded. Write that event once more, corrected: leave `link` or `pr` out rather than invent one, and rewrite the summary in your own words. If the resend is refused too, go on as in 4. `started` is the exception: it is never resent.
4. Anything else (`Not recorded.`, the host unreachable, a timeout): carry on with the work, silently. Never resend, since a resend can record an event twice, and never fall back to a GitHub comment or any other way of sending it. The one exception is `started`: `launch.md`'s step 4 stops the session unless it printed `Recorded.`.
