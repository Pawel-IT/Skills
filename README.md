# Skills

A collection of Claude Code skills.

## Index

| Skill | Description |
| --- | --- |
| [interface-first-design](interface-first-design/SKILL.md) | Design the contract/abstraction boundary (interface, protocol, trait, port) *before* writing the implementation behind it, whenever a feature or refactor introduces a clean seam — services, repositories, adapters, clients, factories, value objects, and the like. Grades every contract against a design rubric (single responsibility, intention-revealing names, testability, honest types/errors, minimal surface) and gates on sign-off before implementing. Also fires on code-review functions. Ships language references for PHP, TypeScript/JavaScript, and Livewire. |
| [naming](naming/SKILL.md) | The naming test for a file, a function, a type, an event, or an option. Use it each time you write a new name. Use it also when you review a name, when you change a name, or when you select one name from several. |
| [pk-issue-triage](pk-issue-triage/SKILL.md) | Triage every open issue in the current repo: Haiku summarizes each one, Sonnet checks whether it is still real and what a fix takes, then one report — and closes the stale ones on your word. Runs the two agents one at a time and watches their context. |

## Keeping a repo current

A repo that uses these skills declares which ones it takes, in
`.claude/shared-skills.txt` — one skill name per line.

```bash
~/code/Skills/sync-skills.sh ~/code/FreeGantt          # copy those skills in
~/code/Skills/sync-skills.sh --check ~/code/FreeGantt  # report only; exit 1 on drift
~/code/Skills/sync-skills.sh --global pk-issue-triage  # symlink into ~/.claude/skills
```

A project commits its skills, so every clone needs real files — the sync copies.
The global directory has one reader on one machine, so `--global` symlinks, and an
edit in this repo is live at once.

The sync stops when a copy holds text this repo never published: the project
improved it, and overwriting would throw that away. Push the better text here
first, then sync. `--force` overwrites when you are sure.
