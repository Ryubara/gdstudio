"""Signed distance to a surface built from closed pieces (a kitbashed weapon, a hand) on a grid (kit #1001)."""

import numpy as np
from scipy.spatial import cKDTree

# How many threads a nearest-sample query uses (a solver with a large grid sets it; 1 by default).
WORKERS = 1


def closest_on_triangles(p, a, b, c):
    """Closest points on triangles (a, b, c) to points p, row by row (Ericson 5.1.5), vectorised."""
    ab, ac, ap = b - a, c - a, p - a
    d1, d2 = np.einsum("ij,ij->i", ab, ap), np.einsum("ij,ij->i", ac, ap)
    bp = p - b
    d3, d4 = np.einsum("ij,ij->i", ab, bp), np.einsum("ij,ij->i", ac, bp)
    cp = p - c
    d5, d6 = np.einsum("ij,ij->i", ab, cp), np.einsum("ij,ij->i", ac, cp)
    vc = d1 * d4 - d3 * d2
    vb = d5 * d2 - d1 * d6
    va = d3 * d6 - d5 * d4
    out = np.empty_like(p)
    done = np.zeros(len(p), bool)

    def put(mask, value):
        m = mask & ~done
        out[m] = value[m]
        done[m] = True

    with np.errstate(divide="ignore", invalid="ignore"):
        put((d1 <= 0) & (d2 <= 0), a)
        put((d3 >= 0) & (d4 <= d3), b)
        put((vc <= 0) & (d1 >= 0) & (d3 <= 0), a + ab * (d1 / (d1 - d3))[:, None])
        put((d6 >= 0) & (d5 <= d6), c)
        put((vb <= 0) & (d2 >= 0) & (d6 <= 0), a + ac * (d2 / (d2 - d6))[:, None])
        w = (d4 - d3) / ((d4 - d3) + (d5 - d6))
        put((va <= 0) & ((d4 - d3) >= 0) & ((d5 - d6) >= 0), b + (c - b) * w[:, None])
        denom = 1.0 / (va + vb + vc)
        put(np.ones(len(p), bool), a + ab * (vb * denom)[:, None] + ac * (vc * denom)[:, None])
    return out


def sample_triangles(tris, spacing):
    """Points on every triangle about `spacing` apart, and the triangle of each."""
    pts, ids = [], []
    for i, (a, b, c) in enumerate(tris):
        nu = max(1, int(np.ceil(np.linalg.norm(b - a) / spacing)))
        nv = max(1, int(np.ceil(np.linalg.norm(c - a) / spacing)))
        u, v = np.meshgrid(np.arange(nu + 1) / nu, np.arange(nv + 1) / nv)
        keep = u + v <= 1.0 + 1e-9
        u, v = u[keep], v[keep]
        pts.append(a + u[:, None] * (b - a) + v[:, None] * (c - a))
        ids.append(np.full(len(u), i))
    return np.concatenate(pts), np.concatenate(ids)


def pieces(tris):
    """The closed piece of each triangle: triangles that share a welded vertex are one piece."""
    keys = np.round(tris.reshape(-1, 3) * 1e5).astype(np.int64)
    _, ids = np.unique(keys, axis=0, return_inverse=True)
    ids = ids.reshape(-1, 3)
    parent = np.arange(ids.max() + 1)

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for t in ids:
        r = find(t[0])
        for k in (1, 2):
            parent[find(t[k])] = r
    roots = np.array([find(t[0]) for t in ids])
    _, piece = np.unique(roots, return_inverse=True)
    return piece


def exact_distance(points, tris, tree, sample_tri):
    """The distance from each point to the triangle of its nearest sample."""
    out = np.empty(len(points))
    for start in range(0, len(points), 200000):
        chunk = points[start : start + 200000]
        _, near = tree.query(chunk, workers=WORKERS)
        t = tris[sample_tri[near]]
        closest = closest_on_triangles(chunk, t[:, 0], t[:, 1], t[:, 2])
        out[start : start + 200000] = np.linalg.norm(chunk - closest, axis=1)
    return out


def crossings(tris, low, step, shape, axis):
    """For each point of a grid, how many of `tris` a ray from it along +`axis` crosses: (shape) ints."""
    order = [k for k in range(3) if k != axis] + [axis]
    low, shape = np.asarray(low)[order], np.asarray(shape)[order]
    count = np.zeros(shape, np.int32)
    along = low[2] + step * np.arange(shape[2])
    for a, b, c in tris[:, :, order]:
        area = (b[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (b[1] - a[1])
        if abs(area) < 1e-16:
            continue
        first = np.floor((np.minimum(np.minimum(a, b), c)[:2] - low[:2]) / step).astype(int)
        last = np.ceil((np.maximum(np.maximum(a, b), c)[:2] - low[:2]) / step).astype(int)
        first, last = np.maximum(first, 0), np.minimum(last, shape[:2] - 1)
        if (first > last).any():
            continue
        # A hair off the grid's lines, so a ray never runs along an edge two triangles share.
        gx, gy = np.meshgrid(
            low[0] + step * np.arange(first[0], last[0] + 1) + 1.3e-7,
            low[1] + step * np.arange(first[1], last[1] + 1) + 0.7e-7,
            indexing="ij",
        )
        u = ((gx - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (gy - a[1])) / area
        v = ((b[0] - a[0]) * (gy - a[1]) - (gx - a[0]) * (b[1] - a[1])) / area
        hit = (u >= 0) & (v >= 0) & (u + v <= 1)
        if not hit.any():
            continue
        where = a[2] + u * (b[2] - a[2]) + v * (c[2] - a[2])
        count[first[0] : last[0] + 1, first[1] : last[1] + 1] += hit[:, :, None] & (
            where[:, :, None] > along[None, None, :]
        )
    return np.transpose(count, np.argsort(order))


class PiecesField:
    """The signed distance to a surface built from closed pieces that overlap (a kitbashed weapon, the
    mannequin's hand of finger capsules and joint balls), on a grid: negative inside a piece, by the
    distance to that piece's surface. A point is inside a piece when rays from it along most of
    `rays` (grid axes) cross the piece an odd number of times; three rays outvote the one that
    leaves through a piece's open end (the palm at the wrist)."""

    def __init__(self, tris, low, high, step=0.001, cache=None, rays=(2,)):
        self.low, self.step = np.array(low, float), step
        shape = np.ceil((np.array(high) - self.low) / step).astype(int) + 1
        if cache:
            try:
                saved = np.load(cache)
                if saved["grid"].shape == tuple(shape) and saved["count"] == len(tris):
                    self.grid = saved["grid"]
                    return
            except OSError:
                pass
        axes = [self.low[k] + step * np.arange(shape[k]) for k in range(3)]
        points = np.stack(np.meshgrid(*axes, indexing="ij"), axis=-1).reshape(-1, 3)
        samples, sample_tri = sample_triangles(tris, step)
        dist = exact_distance(points, tris, cKDTree(samples), sample_tri).reshape(shape)
        depth = np.zeros(shape)
        piece = pieces(tris)
        for p in range(piece.max() + 1):
            self._fill_piece(tris[piece == p], shape, depth, rays)
        self.grid = np.where(depth > 0, -depth, dist).astype(np.float32)
        if cache:
            np.savez_compressed(cache, grid=self.grid, count=len(tris))

    def _fill_piece(self, mine, shape, depth, rays):
        """Marks the grid points inside one piece with their distance to its surface."""
        step = self.step
        lo = np.floor((mine.reshape(-1, 3).min(0) - self.low) / step).astype(int)
        hi = np.ceil((mine.reshape(-1, 3).max(0) - self.low) / step).astype(int)
        lo, hi = np.clip(lo, 0, shape - 1), np.clip(hi, 0, shape - 1)
        if (lo >= hi).any():
            return
        low = self.low + step * lo
        size = hi - lo + 1
        votes = sum((crossings(mine, low, step, size, axis) % 2) for axis in rays)
        inside = votes * 2 > len(rays)
        if not inside.any():
            return
        index = np.argwhere(inside)
        s, st = sample_triangles(mine, step)
        d = exact_distance(low + step * index, mine, cKDTree(s), st)
        view = depth[lo[0] : hi[0] + 1, lo[1] : hi[1] + 1, lo[2] : hi[2] + 1]
        view[inside] = np.maximum(view[inside], d)

    def __call__(self, points):
        """Signed distance at points (..., 3), trilinear; outside the grid, the value at the grid's
        nearest point plus the way there (never less than the truth by more than that way)."""
        raw = (points - self.low) / self.step
        shape = np.array(self.grid.shape)
        g = np.clip(raw, 0, shape - 1.001)
        beyond = np.linalg.norm(raw - g, axis=-1) * self.step
        i = np.floor(g).astype(int)
        f = g - i
        x, y, z = i[..., 0], i[..., 1], i[..., 2]
        fx, fy, fz = f[..., 0], f[..., 1], f[..., 2]
        grid = self.grid
        c00 = grid[x, y, z] * (1 - fx) + grid[x + 1, y, z] * fx
        c10 = grid[x, y + 1, z] * (1 - fx) + grid[x + 1, y + 1, z] * fx
        c01 = grid[x, y, z + 1] * (1 - fx) + grid[x + 1, y, z + 1] * fx
        c11 = grid[x, y + 1, z + 1] * (1 - fx) + grid[x + 1, y + 1, z + 1] * fx
        out = (c00 * (1 - fy) + c10 * fy) * (1 - fz) + (c01 * (1 - fy) + c11 * fy) * fz
        return out + beyond
