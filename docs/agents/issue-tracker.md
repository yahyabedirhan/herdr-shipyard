# Issue tracker: GitHub

Issues and specs for this repo live as GitHub issues in `yahyabedirhan/herdr-shipyard`, so the repo has no `.efforts/` folder. Use the `gh` CLI for all operations.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --comments`, filtering comments by `jq` and also fetching labels.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close**: `gh issue close <number> --comment "..."`
- **Efforts**: every issue of an effort carries the label `effort:<effort>`; list an effort's tickets with `gh issue list --label effort:<effort>`. Create that label before the first issue that uses it, as the publish section says. `gh issue create --label` fails when the label does not exist yet.
- Refer to an issue by its title, never by its number alone.

Infer the repo from `git remote -v`; `gh` does this automatically when run inside a clone.

## Title prefixes

Start every issue title with one prefix, then `: ` and a capitalized title with no trailing period, for example `QA: Check the plugin on a new machine`. When more than one prefix fits, use the first one in this order:

1. `QA`: manual work for the maintainer.
2. A semantic prefix from the list below: one area of this project.
3. `Bug`, `Feature`, `Chore` or `Spec`: the kind of work.
4. `Research`: a question to answer before the work starts.

Write each prefix the way its maker writes it. Use a semantic prefix before a generic one when one fits.

### Semantic prefixes

- None yet.

Reuse a prefix from this list before you add a new one. Add a new one when no prefix fits and the issue belongs to one tool, product, skill or workflow. Add it to this list in the same change.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature requests; `/triage` reads this flag.)_

When set to `yes`, PRs run through the same labels and states as issues, using the `gh pr` equivalents:

- **Read a PR**: `gh pr view <number> --comments` and `gh pr diff <number>` for the diff.
- **List external PRs for triage**: `gh pr list --state open --json number,title,body,labels,author,authorAssociation,comments` then keep only `authorAssociation` of `CONTRIBUTOR`, `FIRST_TIME_CONTRIBUTOR`, or `NONE` (drop `OWNER`/`MEMBER`/`COLLABORATOR`).
- **Comment / label / close**: `gh pr comment`, `gh pr edit --add-label`/`--remove-label`, `gh pr close`.

GitHub shares one number space across issues and PRs, so a bare `#42` may be either: resolve with `gh pr view 42` and fall back to `gh issue view 42`.

## When a skill says "publish to the issue tracker"

Create a GitHub issue. When it belongs to an effort, make sure the `effort:<effort>` label exists before `gh issue create`, because `--label` fails on a label the repo does not have yet. List labels and create it only when that exact name is missing, so a later issue does not try to recreate it:

```bash
gh label list --limit 1000 --json name --jq '.[] | select(.name == "effort:<effort>") | .name'
gh label create "effort:<effort>"
gh issue create --title "..." --body "..." --label "effort:<effort>"
```

Run `gh label create` only when the list prints nothing. An issue that is not part of an effort is `gh issue create --title "..." --body "..."` with no label.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as tickets.

- **Map**: a single issue labelled `wayfinder:map`, holding the Notes / Decisions-so-far / Fog body. `gh issue create --label wayfinder:map`.
- **Child ticket**: an issue linked to the map as a GitHub sub-issue (`gh api` on the sub-issues endpoint). Where sub-issues aren't enabled, add the child to a task list in the map body and put `Part of #<map>` at the top of the child body. Labels: `wayfinder:<type>` (`research`/`prototype`/`grilling`/`task`). Once claimed, the ticket is assigned to the driving dev.
- **Blocking**: GitHub's **native issue dependencies**, the canonical, UI-visible representation. Add an edge with `gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`, where `<blocker-db-id>` is the blocker's numeric **database id** (`gh api repos/<owner>/<repo>/issues/<n> --jq .id`, _not_ the `#number` or `node_id`). GitHub reports `issue_dependencies_summary.blocked_by` (open blockers only, the live gate). Where dependencies aren't available, fall back to a `Blocked by: #<n>, #<n>` line at the top of the child body. A ticket is unblocked when every blocker is closed.
- **Frontier query**: list the map's open children (`gh issue list --state open`, scoped to the map's sub-issues / task list), drop any with an open blocker (`issue_dependencies_summary.blocked_by > 0`, or an open issue in the `Blocked by` line) or an assignee; first in map order wins.
- **Claim**: `gh issue edit <n> --add-assignee @me`, the session's first write.
- **Resolve**: `gh issue comment <n> --body "<answer>"`, then `gh issue close <n>`, then append a context pointer (gist + link) to the map's Decisions-so-far.
