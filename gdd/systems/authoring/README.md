---
title: Authoring
type: system-index
---

# Authoring

The pipeline that turns these docs into scenes and generated data, plus code-level audits.

| Note | Covers |
|---|---|
| [ability-module-fold.md](ability-module-fold.md) | the one ability system, and the three parallel mechanisms it replaced |
| [passive-ability-candidates.md](passive-ability-candidates.md) | **review list** — mechanics behaving like passives that are implemented as something else |
| [spec-importer.md](spec-importer.md) | `Tool` wiring, the doc schema, and what belongs in a doc vs. the editor |
| [calibration-rules.md](calibration-rules.md) | the importer's second pass: physics-facing numbers, the three verdicts, which exports earn a doc key |
| [get-node-or-null-audit.md](get-node-or-null-audit.md) | per-occurrence verdicts on optional-component lookups |
| [entity-scene-hierarchy.md](entity-scene-hierarchy.md) | which components a scene may assume; `index=` semantics for moving a node between bases |
| [composition-rework.md](composition-rework.md) | **plan** — the doc declares the component set; narrowing `kind:`, retiring the base scenes and the two-phase emission model |
| [piece-vocabulary.md](piece-vocabulary.md) | **proposal**: what a piece is called. Facet adjectives, the building / unit / feature / token / emission partition, and the roster classified |
| [linting.md](linting.md) | `gdlint` config and what each disabled rule contradicts; why `gdformat` is not run |

**Belongs here:** the importer, the doc schema, generated-data formats, and standing audits
of code-level conventions.

**Does not belong here:** the mechanics the data describes — those go in their own system.
Full importer usage docs live in `tools/spec_import/README.md`.
