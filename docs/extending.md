# Extending Hermes

Hermes has three types of capabilities. Understanding which to use is the key to building an effective system.

## Quick Decision Guide

| Question | If Yes |
|----------|--------|
| Does the user explicitly invoke it with a slash command? | **Command** |
| Should Hermes delegate a chunk of autonomous work? | **Agent** |
| Should it activate based on conversational context? | **Skill** |

## Commands

User-triggered workflows invoked with slash commands (e.g., `/start`, `/commit`, `/report`).

**When to create a command:**
- The user needs to explicitly trigger a workflow
- The workflow has a defined sequence of steps
- It maps to a verb: "start", "end", "commit", "report"

**Structure:** `.claude/commands/your-command.md`
```yaml
---
description: One-line description (shown in /help)
---
```

**Examples:** `/start` loads context and gives a briefing. `/commit` reviews changes and creates logical git commits. `/report` generates a weekly summary.

**Tips:**
- Keep commands focused on one workflow
- Include step-by-step instructions with bash examples
- Add the `description` frontmatter so it appears in `/help`

## Agents

Specialized subagents Hermes spawns via the Task tool for delegated, autonomous work.

**When to create an agent:**
- Work can be delegated without step-by-step user input
- The agent needs domain expertise (research, content, events)
- The task is substantial enough to warrant a separate context

**Structure:** `.claude/agents/your-agent.md`
```yaml
---
name: agent-name
description: What this agent does
model: sonnet
---
```

**Workflow pattern:** Most agents follow Discovery -> Execution -> Review:
1. **Discovery** - Gather inputs, ask clarifying questions
2. **Execution** - Do the work (research, draft, track)
3. **Review** - Present results, save outputs, report back

**Boundaries:** Every agent needs a "What You Do Not Do" section. Clear boundaries prevent scope creep and set expectations.

**Examples:**
- `research-agent` - Web research with quick and deep modes
- `content-agent` - Content creation, distribution, and pipeline tracking
- `events-agent` - Speaking engagements, CFPs, and event lifecycle

**Tips:**
- Agents should be autonomous. If the user needs to guide every step, it's probably a command.
- Include specific output formats so results are consistent.
- Add routing rules (see below) so Hermes spawns agents automatically.

## Skills

Contextual capabilities Claude Code invokes based on conversation patterns, not explicit commands.

**When to create a skill:**
- The capability should activate based on what's happening in conversation
- It's a detection + action pattern (detect "I shipped X", action: log it)
- It enhances other workflows rather than being a standalone workflow

**Structure:** `.claude/skills/your-skill.md`
```yaml
---
name: skill-name
description: What this skill does
---
```

**Proactive vs. on-demand:**
- **Proactive skills** activate when they detect patterns: "I shipped a blog post" triggers content-shipped
- **On-demand skills** activate when the user asks: "What's my status?" triggers the status skill

**Examples:**
- `daily-briefing` - Generates structured briefing (used by /start)
- `content-shipped` - Detects shipping language and logs content
- `status` - Checks integration health and workspace status
- `skill-creator` - Creates new commands, agents, or skills on request

**Tips:**
- Keep trigger conditions specific. Vague triggers cause false activations.
- Skills should be lightweight. Heavy work should be delegated to an agent.
- Symlink skills to `~/.claude/skills/` for Claude Code auto-discovery.

## Routing Rules

Routing rules are auto-spawn triggers you add to CLAUDE.md. They tell Hermes when to automatically delegate work to an agent without being asked.

**Format:** Add rules to the "Routing Rules" section in CLAUDE.md:

```
- User mentions a CFP or speaking event -> spawn events-agent
- User says "I shipped" / "just posted" -> spawn content-agent
- User asks to research a topic -> spawn research-agent
```

**Good routing rules are:**
- Specific enough to avoid false triggers
- Tied to clear user intent signals
- Mapped to a single agent

**Bad routing rules:**
- "User mentions anything about work" (too broad)
- "User seems interested in content" (too vague)

## Wrapping CLIs as Skills

If you use a CLI tool frequently, wrap it as a skill for better integration:

1. Create a skill file in `.claude/skills/`
2. Document the CLI's key commands and flags
3. Add triage rules (how to interpret and route CLI output)
4. Add trigger conditions (when should Hermes use this CLI?)

This pattern gives Hermes domain knowledge about the tool, not just access to it.

## Creating New Capabilities

The fastest way to extend Hermes:

1. Tell Hermes: "Give yourself the ability to X"
2. The `skill-creator` skill activates and determines the right type
3. It creates the file in the correct location
4. You can customize from there

Or create files manually using the templates in `.claude/agents/_template.md` and `.claude/skills/_template.md`.
