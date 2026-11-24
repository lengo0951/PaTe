# QuocNgoKit (QN) Codex Entry Point

This repository ships QuocNgoKit for both Claude Code and Codex. In Codex, use the Codex-native surfaces first:

- Skills live in `.agents/skills/`; invoke them with `$qn:<name>` or through `/skills`. Do not assume `/qn:<name>` custom slash commands are available in Codex.
- Codex subagents live in `.codex/agents/*.toml`. The Markdown agents in `claude/agents/`, `.claude/agents/`, and `.agents/agents/` are source/runtime mirrors for other harnesses.
- Codex hooks live in `.codex/hooks.json`. Project hooks require the project `.codex` layer to be trusted.
- QuocNgoKit config is resolved from `./.qn.json`, `./.ck.json`, `.claude/.ck.json`, `.agents/.ck.json`, then user-level config.
- Plans and reports live under `plans/`. If CLI flags drift, create or update plan files directly in `plans/`.
- Shared rules and scripts live under `.agents/rules/` and `.agents/scripts/` for Codex.
- When spawning or naming agent/team workers for this project, prefer Vietnamese-style names such as Quoc Ngo, The Duy, Nghi Khoa, Khanh Khoa, or Thai An.
- NEVER POLL A BACKGROUND JOB ('sleep'/'ps'/'pgrep'/'top'/) — do other work or end your reply and you will be woken with its input.

## PasteFlow Architectural Rules

1. **Dual-Platform Parity (macOS & Windows)**:
   - Every feature, fix, data model update, and UI change MUST be implemented and tested for BOTH macOS (Swift 6) and Windows (Rust 2024 / Win32).
   - Every release cycle MUST build and package both artifacts: `.dmg` for macOS and `.zip` (`pasteflow.exe` + `install.bat`) for Windows.
2. **Performance-First & Zero-Bloat Mandate (Top Priority)**:
   - Memory target: `< 35 MB RSS` on macOS, `< 25 MB RSS` on Windows.
   - Idle CPU must remain near `0.0%`.
   - STRICTLY PROHIBITED: Electron, WebViews, Chromium, or bloated runtime wrappers. Pure native compiled binaries only.
   - Sub-50ms hotkey response and buttery 60/120fps rendering.

## Core Mindset & Execution Guidelines

- **Unbounded Execution:** NEVER narrate or consider session limits, token/tool budgets, effort estimates, or possible completion boundaries. Start unbounded: execute or delegate. Do not shy away from complex tasks to save effort/tokens.
- **Verification Over Cost:** Verification and testing are authorized to spend tokens. The cost of running a real smoke test or deep validation is small against a bug that silently slips through. Tests alone are not proof; observe the actual changed surface.
- **Outcomes, Not Mechanics:** Talk in outcomes, consequence, and next decisions. Never relay raw tool outputs, internal supervision mechanics, or narrate step-by-step API calls to the captain.
- **Relentless Delivery:** NEVER yield before a complete deliverable or while actionable work remains. A phase boundary, a todo list flip, or a sub-step completion never stops a turn; finish the reachable work.
- **No Shortcuts:** Never substitute an easier or familiar problem. Do not infer extra scope, solve a symptom (like suppressing a warning), or build fake fallbacks ("MVP", "scaffold") unless explicitly asked.
- **One-owner Rule & Size Discipline:** Every contract or rule is stated in full exactly once. When updating knowledge, prefer rewriting or pruning existing entries over appending new ones.

When editing this kit, keep the source layout and generated runtime surfaces synchronized. After changing `claude/agents/*.md`, run `npm run sync:codex` to generate missing Codex TOML agents and normalize Codex runtime references. Use `npm run sync:codex-agents -- --overwrite` only when intentionally regenerating every Codex agent from the Claude Markdown source.


<claude-mem-context>
# Memory Context

# [quocngokit] recent context, 2026-07-01 6:32pm GMT+7

No previous sessions found.
</claude-mem-context>
