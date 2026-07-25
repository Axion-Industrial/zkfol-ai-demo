---
name: code-review
description: Review code for architectural fit, dead code, and complexity. Use when asked to review a module, file, or PR.
---

# Code Review

Review the specified code against the project conventions.

## Instructions

1. Spawn a reviewer via the Task tool with subagent_type
   "general-purpose".
2. Tell it to read `.claude/skills/general-conventions/SKILL.md`
   (especially Review Principles and Implementation Anti-Patterns) and
   `.claude/skills/elixir-conventions/SKILL.md`, then review the target
   the user named: run its examples rather than reasoning from
   signatures, and verify every finding before reporting it.
3. When the agent returns, present its findings to the user concisely.
   Group by severity: architectural issues first, then complexity,
   then style.
4. If the agent ran examples or queries interactively, include
   those observations — they're the strongest evidence.
