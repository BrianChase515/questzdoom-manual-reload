// Direction helpers shared by the real VR layer and the desktop shim.
class RL_Math play
{
	// QuestZDoom 1.5.x's script AttackDir/OffhandDir return (yaw, pitch, 0) in degrees
	// instead of a direction vector; newer versions return the unit vector.
	static Vector3 ToDir(Vector3 r)
	{
		// The angle form always has z == 0 exactly; a tracked hand direction never does.
		if (r.z != 0) return r.Unit();
		double yaw = r.x, pitch = r.y;                        // angles (pitch + = down)
		return (cos(pitch) * cos(yaw), cos(pitch) * sin(yaw), -sin(pitch));
	}

	// Build a clean orthonormal frame from forward + a rough side vector.
	static Vector3, Vector3, Vector3 Frame(Vector3 fwd, Vector3 side)
	{
		fwd = fwd.Unit();
		Vector3 up = fwd cross side;
		if (up.Length() < 0.001) up = (0, 0, 1);
		up = up.Unit();
		side = (up cross fwd).Unit();
		return fwd, side, up;
	}
}
