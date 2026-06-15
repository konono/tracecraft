# tracecraft

> Record how AI got there, not just what it built.

A structured journaling skill for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that captures the full reasoning process — investigations, hypotheses, failures, and decisions — as reviewable, reproducible documents.

## Why

When AI agents complete a task, you get the final result. But you lose:

- What was investigated and why
- Which hypotheses were formed
- What was tried and failed
- Why the final approach was chosen

tracecraft treats **the work process itself as a deliverable**, making it possible to review, reproduce, learn from, and audit AI-assisted work.

## What It Records

Each session generates a structured journal under `.tracecraft/`:

| File | Purpose |
|---|---|
| `worklog.md` | Chronological work log with steps, expectations, and actual results |
| `findings.md` | Investigation results — what was discovered and its impact |
| `troubleshooting.md` | Problem isolation, root cause analysis, and resolution |
| `decisions.md` | Key decisions with alternatives considered and trade-offs |
| `final-guide.md` | Reproducible step-by-step guide distilled from the work |
| `retrospective.md` | Lessons learned and reusable patterns |

## Installation

Requires Python 3.6+ and [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

### Global (all projects)

```sh
sh install.sh --global
```

### Project-specific

```sh
sh install.sh --project
```

### Interactive

```sh
sh install.sh
```

The installer:
1. Copies the hook script to `.claude/hooks/`
2. Copies the skill definition to `.claude/skills/` (project scope only)
3. Registers the `UserPromptSubmit` hook in `.claude/settings.json`

## Usage

tracecraft works in two modes:

### Auto mode (with hook)

Once installed, the hook detects each new Claude Code session and automatically prompts journal initialization. Journals are updated in real-time as you work.

### Manual mode (without hook)

Run `/tracecraft` at the end of a session to generate all journal files at once from the conversation history.

### Commands

| Command | Description |
|---|---|
| `/tracecraft start [title]` | Start a new journal session |
| `/tracecraft step <name>` | Add a work step to the log |
| `/tracecraft finding <topic>` | Record an investigation result |
| `/tracecraft issue <name>` | Record a problem and its resolution |
| `/tracecraft decision <topic>` | Record a key decision |
| `/tracecraft finalize` | Generate the final guide and retrospective |
| `/tracecraft status` | Show current journal state |

## Uninstallation

```sh
sh uninstall.sh --global   # or --project
```

## License

[MIT](LICENSE)
