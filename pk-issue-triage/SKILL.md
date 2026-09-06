---
name: pk-issue-triage
description: "Triage every open issue in the current repo: Haiku summarizes each one, Sonnet checks whether it is still real and what a fix takes, then one report — and closes the stale ones on your word."
disable-model-invocation: true
---

# Issue triage

Two agents, one after the other, over the open issues of the repository you invoke this from.

1. **Summarize** — a Haiku agent reads each issue and states what it asks for. No verdicts.
2. **Validate** — a Sonnet agent checks each summary against the code and says: still valid, or stale, and what a fix takes.
3. **Report and close** — one report to you. Stale issues close after you say so.

**You are the orchestrator** — the chat session the user invoked this from. You ask the questions, you watch the agents, you write the report, and you close the issues. Never hand this to a `work-coordinator`.

**One agent at a time.** A short issue does not pay for a parallel wave. Each agent works its list in order and its context, not a batch size, decides when the next agent starts. See [Run one agent](#run-one-agent) for the loop that does this.

## 1. Ask for the bounds

Ask the user two questions in one message, and wait for the answer:

- **Count cap** — how many open issues at most this run? Offer `30` as the default.
- **Age** — how old, at least? Offer "issues with no update for 30 days" as the default, and "no age filter — every open issue" as the other common answer.

State that age filters on **last update**, not on creation date. An issue commented on yesterday is not stale, whatever its birthday.

This step blocks. The cap decides how much you spend, and the age decides what you look at, so neither is yours to assume.

## 2. Build the work list

```bash
gh repo view --json nameWithOwner -q .nameWithOwner
gh issue list --state open --limit <cap> --json number,title,labels,createdAt,updatedAt,author,url
```

Add `--search "updated:<YYYY-MM-DD"` when the user set an age. Compute the date with `date -d "<N> days ago" +%F`.

`gh issue list` excludes pull requests already. Sort oldest-update first, so the cap cuts the freshest issues rather than the most likely stale ones.

Create a run folder. Use the session scratchpad directory when the harness gave you one; otherwise `mktemp -d -t issue-triage-XXXXXX`. Both agents write there, and report back only a path and one line per issue — that is what keeps your own context small.

Report the repo name and the issue count before you dispatch.

## 3. Summarize

One agent, `subagent_type: "Explore"`, `model: "haiku"`, the whole work list. Run it with [the loop below](#run-one-agent) at `WIND_DOWN=120000` — a Haiku window is 200k, so it needs the earlier mark to land inside it.

> Summarize GitHub issues <numbers> in `<owner/repo>`, in the order listed. Read each
> one with `gh issue view <n> --comments`.
>
> Append one entry per issue to `<run-dir>/summaries.md` in this exact shape, and
> write it **before you read the next issue**:
>
> ```
> ## #<n> — <title>
> - **Asks for:** <one sentence — the change the issue wants>
> - **Claims broken:** <what the issue says is wrong now, or "nothing — it is a request">
> - **Names:** <files, symbols, commands, issue or PR numbers the issue cites; "none" when it cites none>
> - **Done when:** <the concrete test that would satisfy the author>
> - **Last activity:** <date, and who — author, maintainer, or bot>
> - **Labels:** <current labels>
> ```
>
> Summarize only. Do not judge whether the issue is still valid, do not read the
> codebase, and do not propose a fix — a later pass does that.
> Quote the issue; never fill a gap from your own guess. Write "the issue does not
> say" when the issue does not say.
>
> `<run-dir>/summaries.md` may already hold entries from an earlier agent. Start at
> the first issue in your list that has no entry there.
>
> Report the issue numbers you wrote and your context usage. Nothing else.

The pass is done when every issue in the work list has an entry in `summaries.md`. Check that yourself — `grep '^## #' <run-dir>/summaries.md` and compare against the work list.

## 4. Validate

One agent, `subagent_type: "general-purpose"`, `model: "sonnet"`. Run it with [the loop below](#run-one-agent) at the default `WIND_DOWN`.

> Read `<run-dir>/summaries.md`. For each issue in it, in order, decide whether the
> issue is still valid in this repository at its current HEAD. Append your finding to
> `<run-dir>/verdicts.md` before you move to the next issue.
>
> Check the code. For each issue: look for the files and symbols the summary names,
> search for the behaviour it describes, and search the git history for a commit that
> already changed it (`git log --oneline -S"<symbol>"`, `git log --grep="#<n>"`).
>
> Give each issue one verdict:
> - `valid` — the problem is still there, or the request is still unbuilt.
> - `fixed` — the code already does what the issue asks.
> - `obsolete` — the code, file, or feature the issue is about is gone or replaced.
> - `duplicate of #<n>` — another open issue covers the same thing.
> - `unclear` — you cannot tell from the repository. Say what a person must decide.
>
> Every verdict carries **evidence**: a `file:line`, a commit hash, or the command you
> ran and its output. A verdict with no evidence is not a verdict — mark it `unclear`
> instead.
>
> For each `valid` issue add:
> - **Fix:** the approach, in two or three sentences.
> - **Touches:** the files a fix changes.
> - **Size:** small (under an hour), medium (under a day), or large.
> - **Blocked by:** an issue, a decision, or a missing answer — or "nothing".
>
> Follow the repository's own standards documents (CLAUDE.md, AGENTS.md, and anything
> they point at) when you judge what a fix takes.
>
> Change nothing. This pass reads, it does not edit.
>
> `<run-dir>/verdicts.md` may already hold findings from an earlier agent. Start at the
> first issue that has none.
>
> Report one line per issue — number and verdict — and your context usage. Nothing else.

## Run one agent

Each pass runs one agent and a watcher. Dispatch and watcher go out in **one turn**, the watcher first, because the watcher only sees agents that start after it:

```
Bash(run_in_background: true):
  WIND_DOWN=<mark> ~/.claude/skills/pk-issue-triage/watch-agent-context.sh
Agent(subagent_type: ..., model: ..., prompt: ...)
```

The watcher reads transcripts and wakes you when it exits. Read the line it prints:

- **The agent finished under the mark** — the pass is done. Go on.
- **The agent passed the mark** — send it a message with `SendMessage`: finish the issue it is on, write its entry, and report. Then start the watcher again at `WIND_DOWN=<mark + 50000>`, in case it spends the landing window on new work.

An agent that lands, or one that stops early for any reason, leaves its output file as the record of where it got to. Dispatch a fresh agent with the same prompt — the "start at the first issue with no entry" line makes it resume. No handoff document is needed here, because the file **is** the handoff.

The watcher never stops an agent. You do that, by message, so the agent lands on a clean point.

## 5. Report

Read `verdicts.md` and write one report to `<run-dir>/triage-report.md`. Show the user the table and the detail of the valid issues.

```
# Issue triage — <owner/repo> — <date>
Scope: <n> open issues, <age filter or "no age filter">, cap <cap>.

| # | Title | Verdict | Size | Next step |
|---|-------|---------|------|-----------|
```

Then three sections, in this order:

- **Still valid** — each issue with its fix, files, size, and blocker.
- **Stale — propose to close** — each issue with its verdict and the evidence line. This is the close list.
- **Unclear — needs you** — each issue with the one question that settles it.

Say plainly how many issues you read, and how many the cap cut from the list.

## 6. Close the stale ones

Closing an issue is outward-facing, so **propose first, close on the user's word**. Ask: "Close these <n>? Reply with the numbers, or `all`." Skip this ask only when the user invoked the skill with `--close`, which is their standing permission for this run.

Two issues never close on your judgment: an `unclear` one, and one whose evidence you could not produce.

For each issue the user names:

1. Comment the reason. Write the body to a file and pass `--body-file` — a quoted heredoc, `<<'EOF'`, since the evidence holds backticks. The comment carries the verdict, the evidence, and the fact that a triage pass closed it.
2. Close it. `gh issue close <n> --reason completed` for `fixed`; `--reason "not planned"` for `obsolete` and `duplicate`.
3. Fix the labels. Use the **label-issues** skill. A closed issue keeps only the labels that stay true after the close.

You do the commenting, closing, and labelling in your own session. A subagent never closes an issue and never invokes label-issues — the duty stays with the session that talked to the user.

## When a pass misbehaves

- **The agent reports entries but the file is short** — read its report, write the missing entries yourself, and go on. Do not re-run the pass.
- **The verdicts carry no evidence** — send the agent a message naming those issues and asking for the evidence. Its context is still warm; a fresh dispatch is not.
- **The watcher prints nothing and the agent is done** — it started too late to see the agent. The pass still counts; check the output file.
- **The repo has no issues, or `gh` is not authenticated** — say so and stop. `gh auth status` names the problem.
