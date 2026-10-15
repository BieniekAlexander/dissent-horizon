// DMath — maths that rounds the same on every platform, for simulation code.
//
// GDScript's sin, exp, atan2 and the rest call the platform's C library, and macOS's and
// Windows' return different bits for the same input (measured 2026-10-14), so a networked match
// between the two drifts apart. These are musl's implementations (musl/, vendored),
// compiled here without floating-point contraction, so the same double in gives the same double
// out wherever the game runs. The vector helpers stand in for engine methods that call the
// platform's maths internally (Vector2.angle_to, rotated, from_angle; Vector3.rotated, angle_to),
// and randfn for RandomNumberGenerator.randfn, whose Box-Muller draw uses log and cos.
// gdd/systems/commands/netplay.md §Decisions, platforms.
#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace dissent {

class DMath : public godot::Object {
	GDCLASS(DMath, godot::Object)

protected:
	static void _bind_methods();

public:
	static double sin(double p_x);
	static double cos(double p_x);
	static double tan(double p_x);
	static double asin(double p_x);
	static double acos(double p_x);
	static double atan(double p_x);
	static double atan2(double p_y, double p_x);
	static double exp(double p_x);
	static double log(double p_x);
	static double pow(double p_base, double p_exponent);
	static double tanh(double p_x);
	static double randfn(const godot::Ref<godot::RandomNumberGenerator> &p_rng, double p_mean, double p_deviation);

	static double angle(const godot::Vector2 &p_v);
	static double angle_to(const godot::Vector2 &p_from, const godot::Vector2 &p_to);
	static godot::Vector2 rotated(const godot::Vector2 &p_v, double p_angle);
	static godot::Vector2 from_angle(double p_angle);
	static godot::Vector2 slerp(const godot::Vector2 &p_from, const godot::Vector2 &p_to, double p_weight);
	static double angle_to_3d(const godot::Vector3 &p_from, const godot::Vector3 &p_to);
	static godot::Vector3 rotated_3d(const godot::Vector3 &p_v, const godot::Vector3 &p_axis, double p_angle);
};

} // namespace dissent
