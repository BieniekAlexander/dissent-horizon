#include "dmath.h"

#include "musl/libm.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

namespace dissent {

namespace m = dmath::musl;

void DMath::_bind_methods() {
	ClassDB::bind_static_method("DMath", D_METHOD("sin", "x"), &DMath::sin);
	ClassDB::bind_static_method("DMath", D_METHOD("cos", "x"), &DMath::cos);
	ClassDB::bind_static_method("DMath", D_METHOD("tan", "x"), &DMath::tan);
	ClassDB::bind_static_method("DMath", D_METHOD("asin", "x"), &DMath::asin);
	ClassDB::bind_static_method("DMath", D_METHOD("acos", "x"), &DMath::acos);
	ClassDB::bind_static_method("DMath", D_METHOD("atan", "x"), &DMath::atan);
	ClassDB::bind_static_method("DMath", D_METHOD("atan2", "y", "x"), &DMath::atan2);
	ClassDB::bind_static_method("DMath", D_METHOD("exp", "x"), &DMath::exp);
	ClassDB::bind_static_method("DMath", D_METHOD("log", "x"), &DMath::log);
	ClassDB::bind_static_method("DMath", D_METHOD("pow", "base", "exponent"), &DMath::pow);
	ClassDB::bind_static_method("DMath", D_METHOD("tanh", "x"), &DMath::tanh);
	ClassDB::bind_static_method("DMath", D_METHOD("randfn", "rng", "mean", "deviation"), &DMath::randfn);
	ClassDB::bind_static_method("DMath", D_METHOD("angle", "v"), &DMath::angle);
	ClassDB::bind_static_method("DMath", D_METHOD("angle_to", "from", "to"), &DMath::angle_to);
	ClassDB::bind_static_method("DMath", D_METHOD("rotated", "v", "angle"), &DMath::rotated);
	ClassDB::bind_static_method("DMath", D_METHOD("from_angle", "angle"), &DMath::from_angle);
	ClassDB::bind_static_method("DMath", D_METHOD("slerp", "from", "to", "weight"), &DMath::slerp);
	ClassDB::bind_static_method("DMath", D_METHOD("angle_to_3d", "from", "to"), &DMath::angle_to_3d);
	ClassDB::bind_static_method("DMath", D_METHOD("rotated_3d", "v", "axis", "angle"), &DMath::rotated_3d);
}

double DMath::sin(double p_x) {
	return m::sin(p_x);
}

double DMath::cos(double p_x) {
	return m::cos(p_x);
}

double DMath::tan(double p_x) {
	return m::tan(p_x);
}

double DMath::asin(double p_x) {
	return m::asin(p_x);
}

double DMath::acos(double p_x) {
	return m::acos(p_x);
}

double DMath::atan(double p_x) {
	return m::atan(p_x);
}

double DMath::atan2(double p_y, double p_x) {
	return m::atan2(p_y, p_x);
}

double DMath::exp(double p_x) {
	return m::exp(p_x);
}

double DMath::log(double p_x) {
	return m::log(p_x);
}

double DMath::pow(double p_base, double p_exponent) {
	return m::pow(p_base, p_exponent);
}

double DMath::tanh(double p_x) {
	return m::tanh(p_x);
}

// A normal draw, as RandomNumberGenerator.randfn makes it (core/math/random_pcg.h): the same two
// randf() draws in the same order, so the generator's stream stays where the engine's would leave
// it, and the same Box-Muller formula, in DMath.
double DMath::randfn(const Ref<RandomNumberGenerator> &p_rng, double p_mean, double p_deviation) {
	// The engine's CMP_EPSILON: keeps log() off zero.
	constexpr double SMALLEST_DRAW = 0.00001;
	double first = p_rng->randf();
	if (first < SMALLEST_DRAW) {
		first += SMALLEST_DRAW;
	}
	const double turn = 2.0 * 3.14159265358979323846 * p_rng->randf();
	return p_mean + p_deviation * (m::cos(turn) * std::sqrt(-2.0 * m::log(first)));
}

// The vector helpers follow the engine's own definitions (core/math/vector2.cpp, vector3.cpp),
// computed in double from the float components and rounded once on the way out.

double DMath::angle(const Vector2 &p_v) {
	return m::atan2(double(p_v.y), double(p_v.x));
}

double DMath::angle_to(const Vector2 &p_from, const Vector2 &p_to) {
	const double cross = double(p_from.x) * double(p_to.y) - double(p_from.y) * double(p_to.x);
	const double dot = double(p_from.x) * double(p_to.x) + double(p_from.y) * double(p_to.y);
	return m::atan2(cross, dot);
}

Vector2 DMath::rotated(const Vector2 &p_v, double p_angle) {
	const double s = m::sin(p_angle);
	const double c = m::cos(p_angle);
	return Vector2(double(p_v.x) * c - double(p_v.y) * s, double(p_v.x) * s + double(p_v.y) * c);
}

Vector2 DMath::from_angle(double p_angle) {
	return Vector2(m::cos(p_angle), m::sin(p_angle));
}

// Turns `p_from` toward `p_to` by `p_weight` of the angle between them, its length moving
// linearly from one length to the other; a zero vector at either end makes it a straight lerp.
Vector2 DMath::slerp(const Vector2 &p_from, const Vector2 &p_to, double p_weight) {
	const double from_length_sq = double(p_from.x) * p_from.x + double(p_from.y) * p_from.y;
	const double to_length_sq = double(p_to.x) * p_to.x + double(p_to.y) * p_to.y;
	if (from_length_sq == 0.0 || to_length_sq == 0.0) {
		return Vector2(double(p_from.x) + (double(p_to.x) - p_from.x) * p_weight,
				double(p_from.y) + (double(p_to.y) - p_from.y) * p_weight);
	}
	const double from_length = std::sqrt(from_length_sq);
	const double length = from_length + (std::sqrt(to_length_sq) - from_length) * p_weight;
	const double turn = angle_to(p_from, p_to) * p_weight;
	const double s = m::sin(turn);
	const double c = m::cos(turn);
	const double scale = length / from_length;
	return Vector2((double(p_from.x) * c - double(p_from.y) * s) * scale,
			(double(p_from.x) * s + double(p_from.y) * c) * scale);
}

double DMath::angle_to_3d(const Vector3 &p_from, const Vector3 &p_to) {
	const double ax = p_from.x, ay = p_from.y, az = p_from.z;
	const double bx = p_to.x, by = p_to.y, bz = p_to.z;
	const double cx = ay * bz - az * by;
	const double cy = az * bx - ax * bz;
	const double cz = ax * by - ay * bx;
	return m::atan2(std::sqrt(cx * cx + cy * cy + cz * cz), ax * bx + ay * by + az * bz);
}

// Rodrigues' rotation of `p_v` about the unit `p_axis`, as Basis(axis, angle).xform(v) does.
Vector3 DMath::rotated_3d(const Vector3 &p_v, const Vector3 &p_axis, double p_angle) {
	const double kx = p_axis.x, ky = p_axis.y, kz = p_axis.z;
	const double vx = p_v.x, vy = p_v.y, vz = p_v.z;
	const double s = m::sin(p_angle);
	const double c = m::cos(p_angle);
	const double along = (kx * vx + ky * vy + kz * vz) * (1.0 - c);
	return Vector3(vx * c + (ky * vz - kz * vy) * s + kx * along,
			vy * c + (kz * vx - kx * vz) * s + ky * along,
			vz * c + (kx * vy - ky * vx) * s + kz * along);
}

} // namespace dissent
