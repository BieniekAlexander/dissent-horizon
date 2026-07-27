/* Renders a "Refresh tech tree" button that regenerates the current
 * faction's tech / production dependency graph and bakes it into this note
 * as a static ```mermaid block. The generated region is bounded by mermaid
 * comments INSIDE the fence, so the markers stay invisible in the rendered
 * diagram and the fence itself is never rewritten.
 *
 * The static block is the thing that actually gets read: it renders on
 * every platform (including mobile, which cannot run this script at all).
 * This script only offers a way to refresh it from desktop; it never
 * renders the graph itself.
 *
 * Used from a faction overview note (gdd/factions/<f>/<f>.md) as:
 *
 *     ```mermaid
 *     %% tech-graph:start
 *     ...last-baked graph...
 *     %% tech-graph:end
 *     ```
 *
 *     ```dataviewjs
 *     await dv.view("_scripts/tech-graph")
 *     ```
 *
 * `dh_balance mermaid` emits the same two markers around its output, so the
 * note and the freshly generated graph are sliced with identical logic and
 * neither side has to parse the code fence.
 *
 * All graph logic lives in tools/balance/dh_balance (graph.tech_graph /
 * graph.reachable_from) — the same code the CLI and the balance queries use.
 *
 * DESKTOP ONLY: needs Node's child_process, which Obsidian mobile does not
 * expose. On mobile this renders nothing, leaving the static block above as
 * whatever was last baked in from desktop.
 */
const START_MARKER = "%% tech-graph:start";
const END_MARKER = "%% tech-graph:end";

/* The text strictly between the markers, or null when they are absent or
 * inverted. Used against both the note and the generator's output. */
function betweenMarkers(text) {
    const start = text.indexOf(START_MARKER);
    const end = text.indexOf(END_MARKER);
    if (start === -1 || end === -1 || end < start) return null;
    return {
        before: text.slice(0, start + START_MARKER.length),
        body: text.slice(start + START_MARKER.length, end),
        after: text.slice(end),
    };
}

let execFileSync, nodePath;
try {
    ({ execFileSync } = require("child_process"));
    nodePath = require("path");
} catch (e) {
    execFileSync = null;
}

if (execFileSync) {
    const page = dv.current();
    // A spec's id is its file name, so the note's own name is the faction id.
    const faction = page.file.name;
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

            // The generator wraps its output in the same markers, so take the
            // graph from between them rather than stripping the fence.
            const generated = betweenMarkers(out);
            if (generated === null) {
                throw new Error(
                    `${START_MARKER} / ${END_MARKER} markers missing from the generated graph`,
                );
            }

            await app.vault.process(file, (contents) => {
                const target = betweenMarkers(contents);
                if (target === null) {
                    throw new Error(
                        `${START_MARKER} / ${END_MARKER} markers not found in ${page.file.path}`,
                    );
                }
                return `${target.before}${generated.body}${target.after}`;
            });
            status.textContent = "refreshed.";
        } catch (e) {
            status.textContent = `error: ${e.stderr || e.stdout || e.message}`;
        } finally {
            button.disabled = false;
        }
    };
}
