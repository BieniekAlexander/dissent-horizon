class_name RenderPriority

#region Constants
## Objective / tutorial highlights sit above waypoints: they are instructions, and must not
## be hidden behind a waypoint marker that happens to land on the same spot.
const HIGHLIGHT_PRIORITY: int = 20
const WAYPOINT_PRIORITY: int = 15
const FOG_PRIORITY: int = 10
#endregion
