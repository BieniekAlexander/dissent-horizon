@tool
class_name StaggeredGrid
extends RefCounted

## Screen-aligned ("staggered") coordinates for the terrain grid — a pure, stateless helper.
##
## The world terrain grid is axis-aligned in (x, z) and the game camera yaws 45°
## (RTSCamera3D.CAMERA_YAW_DEGREES), so the grid's rows/columns run DIAGONALLY across the
## screen and a screen-aligned square play area is a 45°-rotated diamond in (x, z). Authoring
## a "square-bounded playspace" therefore means hand-chopping the four (x, z) corners that
## poke outside it. These helpers re-express a cell in the screen-aligned frame so the play
## area can be bounded as a plain RECTANGLE instead.
##
## Screen-aligned axes are the two grid diagonals (this IS the staggered coordinate system):
##   s = x + z   — constant along one on-screen diagonal (a "/" line).
##   t = x - z   — constant along the other ("\" line).
## Integer (x, z) cells map to (s, t) pairs that always share PARITY (s + t = 2x). The inverse
## x = (s + t) / 2, z = (s - t) / 2 is integral only when s and t have equal parity — that
## parity gap is the "stagger" (every other (s, t) slot is empty, like an isometric tile map).
##
## Because |x| + |z| == max(|s|, |t|), a screen-aligned rectangle
##   |s - center.s| <= half.s  AND  |t - center.t| <= half.t
## is an L1 (diamond) region in (x, z): precisely the play-area shape, with the grid corners
## excluded for free. `screen_rect_contains` is that test.

## Cell (x, z) -> screen-aligned (s, t) = (x + z, x - z). `cell` follows the project's
## Vector2i(x, z) convention (x = .x, z = .y).
static func to_screen(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x + cell.y, cell.x - cell.y)

## Screen-aligned (s, t) -> cell (x, z). Only meaningful when `is_valid_screen(screen)`;
## otherwise the /2 truncates and the result is one of the two nearest cells.
static func to_grid(screen: Vector2i) -> Vector2i:
	return Vector2i((screen.x + screen.y) / 2, (screen.x - screen.y) / 2)

## True when an (s, t) pair lands on a real cell (equal parity, s + t even).
static func is_valid_screen(screen: Vector2i) -> bool:
	return ((screen.x + screen.y) & 1) == 0

## Whether `cell` falls inside the screen-aligned rectangle centred at `center` (in (s, t)
## space) with the given half-extents — i.e. inside the corresponding (x, z) play diamond.
## `center` / `half` are floats so a rectangle can sit between cells (even map dimensions).
static func screen_rect_contains(cell: Vector2i, center: Vector2, half: Vector2) -> bool:
	var st: Vector2i = to_screen(cell)
	return absf(float(st.x) - center.x) <= half.x and absf(float(st.y) - center.y) <= half.y
