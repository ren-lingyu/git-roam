---
name: git-roam-project
description: Read Git Roam project memory when implementing, reviewing, debugging, planning, or resuming work in the git-roam repository.
---

# Git Roam project memory

Use the `git-agent-workflow` skill and public GAW status to locate and validate
the formal GAW worktree for this repository.

Read `memory/current.md` relative to that worktree root for the project baseline,
current objective, verification limits, and next action. This is GAW workspace
data, not a resource bundled inside this skill directory.

Keep current project facts in memory rather than this navigation entry point.
Observe the user's active workspace and execution permissions when continuing
project work; memory does not extend those permissions.

## GAW checkpoint messages

Follow the existing `git-agent-workflow` skill's checkpoint-message classification.
For this project, use `docs` cautiously: Markdown format or recording memory,
findings, verification results, phase handoffs or pause state does not justify
that type. Such records normally use `chore`; choose another type only when the
checkpoint's actual purpose supports it.
