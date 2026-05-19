@tool
class_name Anima
extends Commandable

## Technician unit. Its command set (pick up / drop off Stars, the
## command_ability → Build sub-context) lives in CommandContextRegistry keyed
## by Entity.Type.UNIT_TECHNICIAN, not as a get_command_context() override.
