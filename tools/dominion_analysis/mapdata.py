"""One exported map (export_maps.gd's JSON) and the movement questions the model asks of it.

Positions are continuous CELL coordinates, (x, z), cell (x, z) spanning [x, x+1) x [z, z+1) —
the generator's frame. Ground units walk the walkable grid 8-connected (diagonal steps cost
sqrt 2); fliers go straight. Distances are shortest paths, computed by Dijkstra from a TARGET
cell and cached, so one field serves every unit heading there.
"""

from __future__ import annotations

import json
import math

import numpy as np
from scipy.sparse import csr_matrix
from scipy.sparse.csgraph import dijkstra

SQRT2 = math.sqrt(2.0)
_STEPS = [(-1, 0, 1.0), (1, 0, 1.0), (0, -1, 1.0), (0, 1, 1.0),
          (-1, -1, SQRT2), (1, -1, SQRT2), (-1, 1, SQRT2), (1, 1, SQRT2)]


class MapData:
    def __init__(self, path: str):
        d = json.load(open(path, encoding="utf-8"))
        self.name: str = d["name"]
        self.seed: int = d["seed"]
        self.w: int = d["grid_w"]
        self.d: int = d["grid_d"]
        self.walkable = np.array(
            [[c == "1" for c in row] for row in d["walkable"]], dtype=bool
        )  # [z, x]
        self.starts = [tuple(p) for p in d["starts"]]
        self.shelters = [tuple(p) for p in d["shelters"]]
        self.sites = [(tuple(s["pos"]), s["cluster"]) for s in d["sites"]]
        self.ponds = [
            {"center": tuple(p["center"]), "cells": p["cells"], "charge": p["charge"]}
            for p in d["ponds"]
        ]
        self._build_graph()
        self._fields: dict[int, np.ndarray] = {}

    # --- graph ------------------------------------------------------------------------------
    def _build_graph(self) -> None:
        idx = -np.ones((self.d, self.w), dtype=np.int64)
        zs, xs = np.nonzero(self.walkable)
        idx[zs, xs] = np.arange(zs.size)
        self._idx = idx
        self._cells = np.stack([xs, zs], axis=1)
        rows, cols, data = [], [], []
        for dx, dz, cost in _STEPS:
            nx, nz = xs + dx, zs + dz
            ok = (nx >= 0) & (nx < self.w) & (nz >= 0) & (nz < self.d)
            ok[ok] &= self.walkable[nz[ok], nx[ok]]
            if dx != 0 and dz != 0:  # no corner cutting past a blocked orthogonal cell
                ok[ok] &= self.walkable[zs[ok], nx[ok]] & self.walkable[nz[ok], xs[ok]]
            rows.append(idx[zs[ok], xs[ok]])
            cols.append(idx[nz[ok], nx[ok]])
            data.append(np.full(ok.sum(), cost))
        n = zs.size
        self._graph = csr_matrix(
            (np.concatenate(data), (np.concatenate(rows), np.concatenate(cols))), shape=(n, n)
        )

    def cell_of(self, p) -> tuple[int, int]:
        return (min(max(int(p[0]), 0), self.w - 1), min(max(int(p[1]), 0), self.d - 1))

    def nearest_walkable(self, p) -> tuple[int, int]:
        """The walkable cell nearest `p` (a structure's centre is usually inside its footprint)."""
        x, z = self.cell_of(p)
        if self.walkable[z, x]:
            return (x, z)
        for r in range(1, 12):
            best = None
            for dz in range(-r, r + 1):
                for dx in range(-r, r + 1):
                    if max(abs(dx), abs(dz)) != r:
                        continue
                    cx, cz = x + dx, z + dz
                    if 0 <= cx < self.w and 0 <= cz < self.d and self.walkable[cz, cx]:
                        dd = dx * dx + dz * dz
                        if best is None or dd < best[0]:
                            best = (dd, (cx, cz))
            if best:
                return best[1]
        return (x, z)

    def field(self, target) -> np.ndarray:
        """Walking distance from every walkable cell to `target`'s nearest walkable cell,
        as a [z, x] array (inf where unreachable or unwalkable). Cached."""
        cx, cz = self.nearest_walkable(target)
        key = cz * self.w + cx
        f = self._fields.get(key)
        if f is None:
            src = self._idx[cz, cx]
            dist = dijkstra(self._graph, directed=False, indices=src)
            f = np.full((self.d, self.w), np.inf, dtype=np.float32)
            f[self._cells[:, 1], self._cells[:, 0]] = dist
            self._fields[key] = f
        return f

    def walk_distance(self, a, b) -> float:
        ax, az = self.nearest_walkable(a)
        return float(self.field(b)[az, ax])

    def step_toward(self, pos, target, budget: float, flying: bool) -> tuple[tuple, float]:
        """Move from `pos` toward `target` spending `budget` cells of travel; returns the new
        position and what is left: > 0 means it arrived with travel to spare, < 0 is a step
        taken on credit, to be paid out of the next budget (a diagonal step outcosts a slow
        unit's second)."""
        if flying:
            dx, dz = target[0] - pos[0], target[1] - pos[1]
            dist = math.hypot(dx, dz)
            if dist <= budget:
                return (target[0], target[1]), budget - dist
            k = budget / dist
            return (pos[0] + dx * k, pos[1] + dz * k), 0.0
        f = self.field(target)
        x, z = self.nearest_walkable(pos)
        tx, tz = self.nearest_walkable(target)
        left = budget
        while left > 0:
            if (x, z) == (tx, tz):
                return (target[0], target[1]), left
            here = f[z, x]
            best = None
            for dx, dz, cost in _STEPS:
                nx, nz = x + dx, z + dz
                if 0 <= nx < self.w and 0 <= nz < self.d:
                    v = f[nz, nx] + cost
                    if v < here + 1e-4 and (best is None or v < best[0]):
                        best = (v, nx, nz, cost)
            if best is None or not math.isfinite(here):
                return (x + 0.5, z + 0.5), 0.0  # unreachable: stay put
            left -= best[3]  # may overdraw: the debt is returned and paid next second
            x, z = best[1], best[2]
        return (x + 0.5, z + 0.5), min(left, 0.0)

    # --- vision -----------------------------------------------------------------------------
    @staticmethod
    def disk(radius: float) -> np.ndarray:
        r = int(math.ceil(radius))
        yy, xx = np.mgrid[-r:r + 1, -r:r + 1]
        return (xx * xx + yy * yy) <= radius * radius

    def stamp(self, mask: np.ndarray, pos, disk: np.ndarray) -> None:
        r = disk.shape[0] // 2
        x, z = int(pos[0]), int(pos[1])
        x0, x1 = max(0, x - r), min(self.w, x + r + 1)
        z0, z1 = max(0, z - r), min(self.d, z + r + 1)
        if x0 >= x1 or z0 >= z1:
            return
        mask[z0:z1, x0:x1] |= disk[z0 - (z - r):z1 - (z - r), x0 - (x - r):x1 - (x - r)]
