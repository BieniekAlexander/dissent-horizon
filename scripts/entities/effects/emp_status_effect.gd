@tool
class_name EmpStatusEffect
extends StunStatusEffect

## An electromagnetic pulse: a stun that only takes MECH frames (authored on emp.tscn). Its own
## class, with no behaviour of its own, because one thing asks for an EMP by name rather than for
## any stun: the Anarchical Overcharge, which hits only units an EMP has disabled. A Freeze or a
## bio stun disables a unit just as completely and does not qualify.


## Whether an EMP is disabling `a_unit` right now.
static func is_emped(a_unit: Commandable) -> bool:
	for child: Node in a_unit.get_children():
		if child is EmpStatusEffect and (child as EmpStatusEffect).is_active():
			return true
	return false
