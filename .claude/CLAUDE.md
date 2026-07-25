<!-- Thin Claude Code wrapper. Durable, agent-generic guidance is in AGENTS.md at
     the repo root; keep it there so any agent reads it. Paths below are relative
     to THIS file (.claude/CLAUDE.md): ../ reaches the repo root, skills/ is a sibling. -->

@../AGENTS.md

<!-- Auto-load the convention skills for Claude Code. AGENTS.md points other tools
     to the same files in prose, so they aren't tripped by the @-import syntax. -->

@skills/general-conventions/SKILL.md
@skills/elixir-conventions/SKILL.md
@skills/git-conventions/SKILL.md
