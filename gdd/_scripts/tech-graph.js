/* Renders a "Refresh tech tree" button that regenerates the current
 * faction's tech / production dependency graph and bakes it into this note
 * as a static ```mermaid block, bounded by the <!-- tech-graph:start -->
 * / <!-- tech-graph:end --> markers that should sit just above this block.
 *
 * The static block is the thing that actually gets read: it renders on
 * every platform (including mobile, which cannot run this script at all).
 * This script only offers a way to refresh it from desktop; it never
 * renders the graph itself.
 *
 * Used from a faction overview note (gdd/factions/<f>/<f>.md) as:
 *
 *     <!-- tech-graph:start -->
 *     ```mermaid
 *     ...last-baked graph...
 *     ```
 *     <!-- tech-graph:end -->
 *
 *     ```dataviewjs
 *     await dv.view("_scripts/tech-graph")
 *     ```
 *
 * All graph logic lives in tools/balance/dh_balance (graph.tech_graph /
 * graph.reachable_from) — the same code the CLI and the balance queries use.
 *
 * DESKTOP ONLY: needs Node's child_process, which Obsidian mobile does not
 * expose. On mobile this renders nothing, leaving the static block above as
 * whatever was last baked in from desktop.
 */
const START_MARKER = "<!-- tech-graph:start -->";
const END_MARKER = "<!-- tech-graph:end -->";

let execFileSync, nodePath;
try {
    ({ execFileSync } = require("child_process"));
    nodePath = require("path");
} catch (e) {
    execFileSync = null;
}

if (execFileSync) {
    const page = dv.current();
    const faction = page?.id ?? page.file.name;
    const file = app.vault.getAbstractFileByPath(page.file.path);

    const button = dv.el("button", "Refresh tech tree");
    const status = dv.el("span", "", {
        attr: { style: "margin-left: 0.6em; color: var(--text-muted);" },
    });

    button.onclick = async () => {
        button.disabled = true;
        status.textContent = "refreshing…";
        try {
            // This vault is rooted at gdd/, one level under the repo root.
            const REPO_ROOT = nodePath.join(app.vault.adapter.basePath, "..");
            const BALANCE_DIR = nodePath.join(REPO_ROOT, "tools", "balance");
            const PYTHON = nodePath.join(BALANCE_DIR, ".venv", "bin", "python3");

            // Refresh tools/balance/data/ from the current gdd/ docs first, so
            // the graph reflects what is on disk right now.
            execFileSync(PYTHON, [nodePath.join(BALANCE_DIR, "gdd_to_balance.py")], {
                cwd: BALANCE_DIR,
                encoding: "utf8",
            });
            const out = execFileSync(
                PYTHON,
                ["-m", "dh_balance", "mermaid", faction],
                { cwd: BALANCE_DIR, encoding: "utf8", env: { ...process.env, PYTHONPATH: BALANCE_DIR } },
            ).trim();

            await app.vault.process(file, (contents) => {
                const start = contents.indexOf(START_MARKER);
                const end = contents.indexOf(END_MARKER);
                if (start === -1 || end === -1 || end < start) {
                    throw new Error(
                        `${START_MARKER} / ${END_MARKER} markers not found in ${page.file.path}`,
                    );
                }
                const before = contents.slice(0, start + START_MARKER.length);
                const after = contents.slice(end);
                return `${before}\n${out}\n${after}`;
            });
            status.textContent = "refreshed.";
        } catch (e) {
            status.textContent = `error: ${e.stderr || e.stdout || e.message}`;
        } finally {
            button.disabled = false;
        }
    };
}
