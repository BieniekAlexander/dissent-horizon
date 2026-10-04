---
title: Piece icons
type: system-note
---

# Piece icons

*Design note for [Dissent Horizon](../../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

## A piece is drawn as a picture, and its name moves to the tooltip

Every place the HUD shows a unit or structure as a card or button draws the piece's
**picture** instead of its name: the production and build buttons on the command card, the
debug spawner's piece cards, and every `CommandableCard` (the multi-selection cards, training
jobs, garrison occupants and the production rail's queued purchases). The name is not lost —
every piece's button tooltip opens with it ("Train Recruit — …"), so the picture is the
glance and the tooltip is the reading, the same two-tier split the rest of the HUD uses.

Verbs (Attack, Stop) and abilities keep their text: they are not pieces, and have no icon slot.

## Found by convention, never declared

A piece's icon is `assets/icons/pieces/<piece id>.png` (`PieceIcons`). There is no doc key:
every Actor has an icon by the same rule, so a key would only restate the id, and the import
pipeline is not involved in drawing one. A piece WITHOUT a file falls back to its text label
(on a `CommandableCard`, its first letter) — the HUD never shows a blank card.

That fallback is the runtime half of an asset slot ([UX §Asset slots](../README.md)). The
other half is the importer's report: `has_hud_icon` says `MISSING` for an Actor with no file,
and `hud_icon_is_final` says `PLACEHOLDER` for one wearing a stock photograph. Neither is ever
an error, and the game says nothing about a missing icon at runtime.

## The placeholders: an animal per unit, a tree per structure

Every icon today is a stock photograph from Wikimedia Commons, one distinct species per piece,
so that pieces are told apart at a glance before any art exists. The SUBJECT LIST is the
source (`tools/piece_icons/placeholder_subjects.json`: piece id → common and scientific name,
optionally a pinned Commons file); `tools/piece_icons/fetch_placeholder_icons.py` generates
the PNGs, `credits.json` and `CREDITS.md` from it. Do not edit the generated files by hand —
fix the subject, or pin a file title, and refetch that piece with `--only <id>`.

The fetcher puts the subject being right ahead of the licence: a Commons Quality Image filed
under the species, then the species' Wikidata image, then a plain search, and within whichever
source answers, the most permissive licence (public domain/CC0, then CC BY, then CC BY-SA).
Every image is credited whatever its licence.

Which icons are placeholders is exactly what `credits.json` lists. To replace one with real
art: remove the piece from the subject list, rerun the fetcher (which drops its credit), and
drop the new PNG over the old.

TODO: the stock photographs are crops of photos, not icons — at the rail's small chip size
several read as texture. Real icon art is the remedy; no style for it is decided.

TODO: an upgrade's build button (a `Tool` with no piece behind it) has no icon slot and keeps
its text. Whether research gets pictures too is undecided.
