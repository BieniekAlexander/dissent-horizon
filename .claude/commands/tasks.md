---
description: Start or resume an unattended session against the project task file
---

<!-- PORTABLE: nothing here is repo-specific — it defers to the "AFK task sessions" section
     of CLAUDE.md. Copy this file into any repo that has that section. Must be COMMITTED:
     remote/cloud sessions only see what is in the repo, not ~/.claude/commands/. -->

Work the project task file according to the **AFK task sessions** protocol in this repo's `CLAUDE.md`. Read that section now if it is not already in context — it names the task file, the status tags, and the exact question/progress block formats. Follow it literally: I read the results in Obsidian, and the formatting *is* the interface between us.

If `CLAUDE.md` has no such section, stop and tell me — this repo has not been set up for the protocol yet. Offer to add the section, and don't touch any task file until I say yes.

`$ARGUMENTS` narrows the session. A task heading, or enough of one to match unambiguously, means work only that task. Empty means work the whole file.

Procedure:

1. Read the task file end to end. Build a worklist: answered questions, untagged tasks, `#wip` tasks, `#needs-input` tasks.
2. Report the worklist before starting — one line each — so the plan is on the record even if the session dies partway.
3. Work in the protocol's order: answered questions first, then untagged tasks, then `#wip`.
4. Append blocks to the task file **as you go**, not in a batch at the end. If the session is cut short, the file must still be accurate about what happened.
5. Assume I am away from the keyboard. Ask me nothing in chat — every open decision becomes a `[!question]` block in the file, and you move on to the next piece of work rather than guessing.
6. Be conservative about what my spec actually determined. Where it didn't determine something that changes behaviour, scope, or architecture, ask instead of picking — I'd rather answer a question than unpick code. Ordinary craft calls are still yours to make silently.
7. Close with a short summary: tasks touched, questions raised, what is waiting on me.
