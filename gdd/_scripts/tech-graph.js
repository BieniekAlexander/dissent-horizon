/* Renders the current faction's tech / production dependency graph.
 *
 * Used from a faction overview note (gdd/factions/<f>/<f>.md) as:
 *
 *     ```dataviewjs
 *     await dv.view("_scripts/tech-graph")
 *     ```
 *
 * All graph logic lives in tools/balance/dh_balance (graph.tech_graph /
 * graph.reachable_from) — the same code the CLI and the balance queries use.
 * This file only shells out and renders, so there is one source of truth.
 *
 * DESKTOP ONLY: this uses Node's child_process, which Obsidian mobile does not
 * expose. On mobile the block below reports the error instead of a graph.
 */
const { execFileSync } = require("child_process");
const path = require("path");

// This vault is rooted at gdd/, one level under the repo root.
const REPO_ROOT = path.join(app.vault.adapter.basePath, "..");
const BALANCE_DIR = path.join(REPO_ROOT, "tools", "balance");
const PYTHON = path.join(BALANCE_DIR, ".venv", "bin", "python3");

// Fleshed-out factions carry an `id` in frontmatter; the ones that don't are
// still named factions/<f>/<f>.md, so the filename is the fallback.
const page = dv.current();
const faction = page?.id ?? page.file.name;

try {
    // Refresh tools/balance/data/ from the current gdd/ docs first, so the
    // graph reflects what is on disk right now rather than the last export.
    execFileSync(PYTHON, [path.join(BALANCE_DIR, "gdd_to_balance.py")], {
        cwd: BALANCE_DIR,
        encoding: "utf8",
    });
    const out = execFileSync(PYTHON, ["-m", "dh_balance", "mermaid", faction], {
        cwd: BALANCE_DIR,
        encoding: "utf8",
    });
    dv.paragraph(out);
} catch (e) {
    dv.paragraph("```\n" + (e.stderr || e.stdout || e.message) + "\n```");
}
