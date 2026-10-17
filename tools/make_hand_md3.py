#!/usr/bin/env python3
"""
Pose the WebXR generic hand (MIT, @webxr-input-profiles/assets) and write it as
an MD3 with one frame per pose, in the same axis convention as the HDVR pistol
(+x forward, +z up, model units ~ 110 per metre).

Usage: make_hand_md3.py <right.glb> <out.md3> <RL_Mag.md3 (appended to)> [preview.png]
Frames: pose + 4*orientation; poses 0 relaxed, 1 grip/fist, 2 holding magazine,
3 pinching slide; orientations 0 palm down, 1 palm rolled +90, 2 palm rolled -90.
RL_Mag.md3 gets frames 1..3 = the magazine sitting in the hand for each orientation,
4 = lying on the floor, 5 = upright resting on the floor (both for the dropped mag).
Also writes RL_SupportA.md3 / RL_SupportB.md3 next to <out.md3>: the support hand
wrapped round the pistol grip, and its mirror image.
"""
import sys, math, struct, os
import numpy as np
from pygltflib import GLTF2

GLB, OUT = sys.argv[1], sys.argv[2]
MAGFILE = sys.argv[3]
PREVIEW = sys.argv[4] if len(sys.argv) > 4 else None
UNITS_PER_M = 110.0

g = GLTF2().load(GLB)
blob = g.binary_blob()
def acc(i):
    a = g.accessors[i]; bv = g.bufferViews[a.bufferView]
    comp = {5126: np.float32, 5123: np.uint16, 5121: np.uint8, 5125: np.uint32}[a.componentType]
    n = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[a.type]
    off = (bv.byteOffset or 0) + (a.byteOffset or 0)
    return np.frombuffer(blob, dtype=comp, count=a.count * n, offset=off).reshape(a.count, n).astype(np.float64 if comp == np.float32 else np.int64)

prim = g.meshes[0].primitives[0]
P = acc(prim.attributes.POSITION); N = acc(prim.attributes.NORMAL)
UV = acc(prim.attributes.TEXCOORD_0) if prim.attributes.TEXCOORD_0 is not None else np.zeros((len(P), 2))
J = acc(prim.attributes.JOINTS_0); W = acc(prim.attributes.WEIGHTS_0)
IDX = acc(prim.indices).reshape(-1, 3)
skin = g.skins[0]
joint_nodes = skin.joints
names = [g.nodes[j].name for j in joint_nodes]
jpos = {g.nodes[j].name: np.array(g.nodes[j].translation) for j in joint_nodes}

# sanity: inverse bind * rest global == identity (bind pose == rest pose)
IBM = acc(skin.inverseBindMatrices).reshape(-1, 4, 4).transpose(0, 2, 1)
def trs(n):
    t = np.array(n.translation or [0, 0, 0]); q = n.rotation or [0, 0, 0, 1]
    x, y, z, w = q
    R = np.array([[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
                  [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
                  [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]])
    M = np.eye(4); M[:3, :3] = R; M[:3, 3] = t; return M
err = max(np.abs(trs(g.nodes[j]) @ IBM[k] - np.eye(4)).max() for k, j in enumerate(joint_nodes))
assert err < 1e-3, f"bind pose differs from rest pose ({err})"

PALM = np.array([-1.0, 0.0, 0.0])        # palm faces -x in the source mesh
FINGERS = ['index', 'middle', 'ring', 'pinky']
SEG = ['metacarpal', 'phalanx-proximal', 'phalanx-intermediate', 'phalanx-distal', 'tip']
THUMB = ['thumb-metacarpal', 'thumb-phalanx-proximal', 'thumb-phalanx-distal', 'thumb-tip']

def rot_about(p, axis, deg):
    axis = axis / np.linalg.norm(axis); a = math.radians(deg)
    K = np.array([[0, -axis[2], axis[1]], [axis[2], 0, -axis[0]], [-axis[1], axis[0], 0]])
    R = np.eye(3) + math.sin(a) * K + (1 - math.cos(a)) * K @ K
    M = np.eye(4); M[:3, :3] = R; M[:3, 3] = p - R @ p; return M

def pose(curl, thumb):
    """curl[finger] = (prox, inter, distal) degrees; thumb = (opposition, flex-axis tilt, meta, prox, distal)"""
    D = {n: np.eye(4) for n in names}
    for f in FINGERS:
        chain = [f'{f}-finger-{s}' for s in SEG]
        acc_ = np.eye(4)
        for i, jn in enumerate(chain):
            if 1 <= i <= 3:
                bone = jpos[chain[i + 1]] - jpos[jn]
                axis = np.cross(bone, PALM)
                acc_ = acc_ @ rot_about(jpos[jn], axis, curl[f][i - 1])
            D[jn] = acc_
    opp, tilt, *tc = thumb
    acc_ = rot_about(jpos['thumb-metacarpal'], jpos['middle-finger-phalanx-proximal'] - jpos['wrist'], -opp)
    for i, jn in enumerate(THUMB):
        if i <= 2:
            bone = jpos[THUMB[i + 1]] - jpos[jn]
            axis = np.cross(bone, PALM + np.array([0, tilt, 0]))
            acc_ = acc_ @ rot_about(jpos[jn], axis, tc[i])
        D[jn] = acc_
    global LAST_D; LAST_D = D
    Dm = np.stack([D[n] for n in names])
    Ph = np.concatenate([P, np.ones((len(P), 1))], 1)
    out = np.zeros_like(P); outn = np.zeros_like(N)
    for k in range(4):
        M = Dm[J[:, k]]
        out += W[:, k:k+1] * np.einsum('nij,nj->ni', M, Ph)[:, :3]
        outn += W[:, k:k+1] * np.einsum('nij,nj->ni', M[:, :3, :3], N)
    outn /= np.linalg.norm(outn, axis=1, keepdims=True) + 1e-9
    return out, outn

all4 = lambda a, b, c: {f: (a, b, c) for f in FINGERS}
# thumb angles found by searching for the thumb tip reaching the right spot
# (grip: over the index finger; pinch: touching the index fingertip)
POSES = [
    ("relaxed", all4(12, 14, 8), (10, 0, 0, 5, 5)),
    ("grip",    all4(80, 95, 55), (80, 0.5, -30, 15, 60)),
    ("mag",     all4(62, 70, 40), (80, 0.5, -30, 15, 40)),
    ("pinch",   {'index': (50, 60, 60), 'middle': (80, 95, 55), 'ring': (85, 95, 55), 'pinky': (88, 95, 55)}, (75, 0.5, -30, 30, 30)),
]
frames = [pose(c, t) for _, c, t in POSES]

# where the magazine sits in the "mag" pose (source coords): in the fist, between
# the palm and the curled fingers, poking out on the thumb side
def mag_pose_points():
    mc, mt = POSES[2][1], POSES[2][2]
    # posed joint positions = skin a single vertex at each joint by its own delta
    D = {n: np.eye(4) for n in names}
    for f in FINGERS:
        chain = [f'{f}-finger-{s_}' for s_ in SEG]; a = np.eye(4)
        for i, jn in enumerate(chain):
            if 1 <= i <= 3:
                a = a @ rot_about(jpos[jn], np.cross(jpos[chain[i + 1]] - jpos[jn], PALM), mc[f][i - 1])
            D[jn] = a
    pj = lambda n: (D[n] @ np.append(jpos[n], 1))[:3]
    knuckle = (pj('index-finger-phalanx-proximal') + pj('pinky-finger-phalanx-proximal')) / 2
    tips = (pj('index-finger-phalanx-distal') + pj('ring-finger-phalanx-distal')) / 2
    return (knuckle + tips) / 2 + PALM * 0.004
MAG_CENTRE_SRC = mag_pose_points()

# ---- source axes -> pistol model axes: fingers (-y) -> +x forward, back of hand (+x) -> +z up
def to_model(v):
    return np.stack([-v[:, 1], -v[:, 2], v[:, 0]], 1)
wrist = jpos['wrist']
palm_centre = (jpos['middle-finger-phalanx-proximal'] + wrist) / 2
xyz = [to_model(v - palm_centre) * UNITS_PER_M for v, _ in frames]
nrm = [to_model(n) for _, n in frames]
# place the palm where the pistol grip sits relative to the controller
GRIP = np.array([24.0, 0.0, -6.0])
xyz = [v + GRIP for v in xyz]

def roll(v, deg, about):
    a = math.radians(deg); c, s_ = math.cos(a), math.sin(a)
    R = np.array([[1, 0, 0], [0, c, -s_], [0, s_, c]])
    return (v - about) @ R.T + about, R
ORIENT = [0, 90, -90]
fx, fn = [], []
for o in ORIENT:
    for v, n in zip(xyz, nrm):
        rv, R = roll(v, o, GRIP); fx.append(rv); fn.append(n @ R.T)

# ---- magazine in hand (one frame per orientation), appended to RL_Mag.md3
md = bytearray(open(MAGFILE, 'rb').read())
_, mnf, _, mns, _, m_ofr, _, m_osu, _ = struct.unpack('<9i', md[72:108])
assert mnf == 1, "RL_Mag.md3 should have exactly one frame before this step"
msurf = []; o = m_osu
for k in range(mns):
    sf, snf, nsh, mnv, ntr, otr, osh, ost, oxyz, oe = struct.unpack('<10i', md[o+68:o+108])
    raw = np.frombuffer(bytes(md[o+oxyz:o+oxyz+mnv*8]), dtype=np.uint8).reshape(mnv, 8)
    mv = raw[:, :6].copy().view('<i2').reshape(mnv, 3) / 64.0
    msurf.append(dict(o=o, hdr=bytes(md[o:o+108]), mid=bytes(md[o+108:o+oxyz]), v=mv, n=raw[:, 6:8].copy(), nv=mnv))
    o += oe
mag_len = max(s_['v'][:, 2].max() for s_ in msurf) - min(s_['v'][:, 2].min() for s_ in msurf)
# mag axes (pistol coords) -> in-hand: mag up (+z) along the thumb side (-z src -> model -y),
# mag forward (+x) along the fingers (model +x); the thumb ends up on model +y
centre_model = to_model((MAG_CENTRE_SRC - palm_centre)[None])[0] * UNITS_PER_M + GRIP
Rm = np.array([[1, 0, 0], [0, 0, 1], [0, -1, 0]], float)     # mag +z -> model +y
mag_frames = []
for o_ in ORIENT:
    fr = []
    for s_ in msurf:
        v = s_['v'] @ Rm.T + centre_model + np.array([0, 0.3 * mag_len, 0])
        v, _ = roll(v, o_, GRIP)
        fr.append(v)
    mag_frames.append(fr)
# frames 4/5 for the dropped magazine: lying on its side, and upright, both resting on z = 0
allpts = np.concatenate([s_['v'] for s_ in msurf])
Rl = np.array([[1, 0, 0], [0, 0, -1], [0, 1, 0]], float)      # roll 90: long axis (z) -> lateral
lying = [s_['v'] @ Rl.T for s_ in msurf]; lmin = np.concatenate(lying)[:, 2].min()
lying = [v - np.array([0, 0, lmin]) for v in lying]
upright = [s_['v'] - np.array([0, 0, allpts[:, 2].min()]) for s_ in msurf]
mag_frames.append(lying); mag_frames.append(upright)
blobs = []
for k, s_ in enumerate(msurf):
    allv = [s_['v']] + [mf[k] for mf in mag_frames]
    verts = b''.join(np.concatenate([np.clip(np.round(v * 64), -32768, 32767).astype('<i2').view(np.uint8).reshape(s_['nv'], 6), s_['n']], 1).tobytes() for v in allv)
    h = bytearray(s_['hdr'])
    sf, snf, nsh, mnv, ntr, otr, osh, ost, oxyz, oe = struct.unpack('<10i', h[68:108])
    h[68:108] = struct.pack('<10i', sf, len(allv), nsh, mnv, ntr, otr, osh, ost, oxyz, oxyz + len(verts))
    blobs.append(bytes(h) + s_['mid'] + verts)
mfb = bytes(md[m_ofr:m_ofr+56])
for i, mf in enumerate(mag_frames):
    pts = np.concatenate(mf); mn_, mx_ = pts.min(0), pts.max(0)
    mfb += struct.pack('<3f3f3ff', *mn_, *mx_, 0, 0, 0, float(np.abs(pts).max() * 1.8)) + f'inhand{i}'.encode().ljust(16, b'\0')
o_su = 108 + len(mfb); o_e = o_su + sum(len(b) for b in blobs)
hdr = bytes(md[:72]) + struct.pack('<9i', 0, 1 + len(mag_frames), 0, mns, 0, 108, o_su, o_su, o_e)
open(MAGFILE, 'wb').write(hdr + mfb + b''.join(blobs))
print("RL_Mag.md3 now has", 1 + len(mag_frames), "frames")
xyz_by_pose = xyz
xyz, nrm = fx, fn

# ---- shotgun shell pinched between thumb and index (frames 1..3 of RL_ShotShell.md3)
SHELLFILE = os.environ.get('RL_SHELL_MD3')
if SHELLFILE and os.path.exists(SHELLFILE):
    jn = {n: i for i, n in enumerate(names)}
    def tipverts(joint):
        k = jn[joint]
        return np.where(((J == k) * W).sum(1) > 0.5)[0]
    # tips carry no skin weight; use the distal phalanges
    ti, ii = tipverts('thumb-phalanx-distal'), tipverts('index-finger-phalanx-distal')
    assert len(ti) and len(ii), "no fingertip vertices found"
    sd = bytearray(open(SHELLFILE, 'rb').read())
    _, snf, _, sns, _, s_ofr, _, s_osu, _ = struct.unpack('<9i', sd[72:108])
    assert snf == 1 and sns == 1, "RL_ShotShell.md3 should be fresh (1 frame, 1 surface)"
    o = s_osu
    sf, _, nsh, snv, ntr, otr, osh, ost, oxyz, oe = struct.unpack('<10i', sd[o+68:o+108])
    raw = np.frombuffer(bytes(sd[o+oxyz:o+oxyz+snv*8]), dtype=np.uint8).reshape(snv, 8)
    sv = raw[:, :6].copy().view('<i2').reshape(snv, 3) / 64.0
    sv = sv - sv.mean(0)
    frames_s = [sv + 0]
    for oi in range(3):
        f = xyz[3 + 4 * oi]
        pinch = (f[ti].mean(0) + f[ii].mean(0)) / 2
        frames_s.append(sv + pinch)
    verts = b''.join(np.concatenate([np.clip(np.round(v * 64), -32768, 32767).astype('<i2').view(np.uint8).reshape(snv, 6), raw[:, 6:8]], 1).tobytes() for v in frames_s)
    frames_s[0] = frames_s[0] - np.array([0, 0, frames_s[0][:, 2].min()])
    verts = b''.join(np.concatenate([np.clip(np.round(v * 64), -32768, 32767).astype('<i2').view(np.uint8).reshape(snv, 6), raw[:, 6:8]], 1).tobytes() for v in frames_s)
    h = bytearray(sd[o:o+108]); h[68:108] = struct.pack('<10i', sf, 4, nsh, snv, ntr, otr, osh, ost, oxyz, oxyz + len(verts))
    surf = bytes(h) + bytes(sd[o+108:o+oxyz]) + verts
    fb = b''
    for i, v in enumerate(frames_s):
        fb += struct.pack('<3f3f3ff', *v.min(0), *v.max(0), 0, 0, 0, float(np.abs(v).max() * 1.8)) + f'shell{i}'.encode().ljust(16, b'\0')
    o_su = 108 + len(fb)
    hdr = bytes(sd[:72]) + struct.pack('<9i', 0, 4, 0, 1, 0, 108, o_su, o_su, o_su + len(surf))
    open(SHELLFILE, 'wb').write(hdr + fb + surf)
    print("RL_ShotShell.md3: added 3 in-hand frames")

def enc_n(n):
    lat = np.arctan2(n[:, 1], n[:, 0]) * 255 / (2 * math.pi)
    lng = np.arccos(np.clip(n[:, 2], -1, 1)) * 255 / (2 * math.pi)
    return np.stack([np.round(lat).astype(int) & 255, np.round(lng).astype(int) & 255], 1).astype(np.uint8)

nv, nt, nf = len(P), len(IDX), len(xyz)
shader = b'hand'.ljust(64, b'\0') + struct.pack('<i', 0)
tris = IDX.astype('<i4').tobytes()
st = UV.astype('<f4').tobytes()
verts = b''.join(np.concatenate([np.clip(np.round(v * 64), -32768, 32767).astype('<i2').view(np.uint8).reshape(nv, 6), enc_n(n)], 1).tobytes() for v, n in zip(xyz, nrm))
o_sh = 108; o_tri = o_sh + len(shader); o_st = o_tri + len(tris); o_xyz = o_st + len(st); o_end = o_xyz + len(verts)
surf = b'IDP3' + b'hand'.ljust(64, b'\0') + struct.pack('<10i', 0, nf, 1, nv, nt, o_tri, o_sh, o_st, o_xyz, o_end) + shader + tris + st + verts
fb = b''
for i, v in enumerate(xyz):
    mn, mx = v.min(0), v.max(0)
    name = f'{POSES[i % 4][0]}{ORIENT[i // 4]}'
    fb += struct.pack('<3f3f3ff', *mn, *mx, 0, 0, 0, float(np.linalg.norm(np.abs(v).max(0)))) + name.encode()[:16].ljust(16, b'\0')
o_fr = 108; o_su = o_fr + len(fb); o_e = o_su + len(surf)
hdr = b'IDP3' + struct.pack('<i', 15) + b'RL_Hand'.ljust(64, b'\0') + struct.pack('<9i', 0, nf, 0, 1, 0, o_fr, o_su, o_su, o_e)
open(OUT, 'wb').write(hdr + fb + surf)
print("wrote", OUT, nf, "frames,", nv, "verts,", nt, "tris; size (units):", np.round(xyz[0].max(0) - xyz[0].min(0), 1))
print("has UVs:", prim.attributes.TEXCOORD_0 is not None)

# ---- support hand on the pistol (drawn in the gun's model block, not the off-hand slot).
# The "grip" pose in orientation A, mirrored into a left hand, wrapped round the grip.
# Because which side is the gun's left depends on the engine's axes, write both
# the left hand and its mirror image; the player picks whichever looks right.
SUPPORT_OFFSET = np.array([1.0, 2.5, -2.5])
grip_v = xyz[1 + 4 * 1]; grip_n = nrm[1 + 4 * 1]
mir = np.array([1, -1, 1])
def write_single(path, v, n, flip):
    t = IDX[:, [0, 2, 1]] if flip else IDX
    tb = t.astype('<i4').tobytes()
    vb = np.concatenate([np.clip(np.round(v * 64), -32768, 32767).astype('<i2').view(np.uint8).reshape(nv, 6), enc_n(n)], 1).tobytes()
    o_sh = 108; o_tri = o_sh + len(shader); o_st = o_tri + len(tb); o_xyz = o_st + len(st); o_end = o_xyz + len(vb)
    sf_ = b'IDP3' + b'hand'.ljust(64, b'\0') + struct.pack('<10i', 0, 1, 1, nv, nt, o_tri, o_sh, o_st, o_xyz, o_end) + shader + tb + st + vb
    mn, mx = v.min(0), v.max(0)
    fr = struct.pack('<3f3f3ff', *mn, *mx, 0, 0, 0, float(np.linalg.norm(np.abs(v).max(0)))) + b'support'.ljust(16, b'\0')
    o_su = 108 + len(fr); o_e = o_su + len(sf_)
    hdr_ = b'IDP3' + struct.pack('<i', 15) + b'RL_Support'.ljust(64, b'\0') + struct.pack('<9i', 0, 1, 0, 1, 0, 108, o_su, o_su, o_e)
    open(path, 'wb').write(hdr_ + fr + sf_)
import os
d = os.path.dirname(OUT)
left_v = grip_v * mir + SUPPORT_OFFSET
write_single(os.path.join(d, 'RL_SupportA.md3'), left_v, grip_n * mir, True)
write_single(os.path.join(d, 'RL_SupportB.md3'), left_v * mir, grip_n, False)
print("wrote RL_SupportA.md3 / RL_SupportB.md3")

# ---- hand wrapped round a horizontal cylinder (the shotgun pump).
# The cylinder lies across the palm at the base of the fingers; each finger joint
# (then the thumb's) is closed a little at a time until that part of the hand
# touches the cylinder (or the barrel above it), like a real grasp closing.
# Output frame: cylinder axis = +x through the origin, palm under it (palm faces +z),
# in model units; the barrel (ellipse PUMP_BARREL) is above.
PUMP_R = float(os.environ.get('RL_PUMP_R', '2.05'))
PUMP_BARREL = (3.33, 1.5, 1.08)            # centre height above the pump axis, half width, half height
def fit_pump():
    pj = lambda D, n: (D[n] @ np.append(jpos[n], 1))[:3]
    a = jpos['pinky-finger-phalanx-proximal'] - jpos['index-finger-phalanx-proximal']; a /= np.linalg.norm(a)
    up = PALM - a * (PALM @ a); up /= np.linalg.norm(up)
    # the pump runs at an angle across the palm (knuckles angled toward the muzzle),
    # so the forearm trails back from the gun instead of sticking out sideways
    beta = math.radians(float(os.environ.get('RL_PUMP_YAW', '-50')))
    a = a * math.cos(beta) + np.cross(up, a) * math.sin(beta)
    side = np.cross(up, a)
    R = np.stack([a, side, up])
    knuck = (jpos['index-finger-phalanx-proximal'] + jpos['pinky-finger-phalanx-proximal']) / 2
    wristward = jpos['wrist'] - knuck; wristward -= a * (wristward @ a) + up * (wristward @ up)
    wristward /= np.linalg.norm(wristward)
    rest, _ = pose(all4(0, 0, 0), (0, 0, 0, 0, 0))
    def to_out(v, c):
        return ((v - c) @ R.T) * UNITS_PER_M
    # axis position: over the palm just behind the knuckles, resting on the skin
    base = knuck + wristward * float(os.environ.get('RL_PUMP_BACK', '0.012'))
    jidx0 = {n: i for i, n in enumerate(names)}
    palm_ids = [jidx0[n] for n in names if 'metacarpal' in n and 'thumb' not in n] + [jidx0['wrist']]
    palm_v = rest[(np.isin(J, palm_ids) * W).sum(1) > 0.6]
    for d in np.arange(-0.03, 0.08, 0.0005):
        c = base + up * d
        q = to_out(palm_v, c)
        if np.hypot(q[:, 1], q[:, 2]).min() >= PUMP_R + 0.15: break
    def hits(v, mask):
        q = to_out(v[mask], c)
        if (np.hypot(q[:, 1], q[:, 2]) < PUMP_R + 0.1).any(): return True
        bz, bw, bh = PUMP_BARREL
        return ((((q[:, 1] / bw) ** 2 + ((q[:, 2] - bz) / bh) ** 2)) < 1.05).any()
    jidx = {n: i for i, n in enumerate(names)}
    def verts_of(joints):
        ids = [jidx[n] for n in joints]
        return (np.isin(J, ids) * W).sum(1) > 0.3
    curl = {f: [0.0, 0.0, 0.0] for f in FINGERS}
    thumb = [0.0, 0.5, 0.0, 0.0, 0.0]
    for f in FINGERS:
        for jn in range(3):
            moving = verts_of([f'{f}-finger-{SEG[k]}' for k in range(jn + 1, 5)])
            while curl[f][jn] < 100:
                curl[f][jn] += 2
                v, _ = pose({k: tuple(x) for k, x in curl.items()}, tuple(thumb))
                if hits(v, moving): curl[f][jn] -= 2; break
    tverts = verts_of(THUMB[1:])
    # thumb along the far side of the pump: the opposition angle that lays it
    # closest to the surface without going in
    bestopp = None
    for opp in range(-90, 91, 5):
        for tilt in (-1.0, -0.5, 0.0, 0.5, 1.0):
            v, _ = pose({k: tuple(x) for k, x in curl.items()}, (opp, tilt, 0, 0, 0))
            q = to_out(v[tverts], c)
            if hits(v, tverts) or q[:, 1].mean() < 0: continue
            gap = np.hypot(q[:, 1], q[:, 2]).min() - PUMP_R
            if bestopp is None or gap < bestopp[0]: bestopp = (gap, opp, tilt)
    if bestopp: thumb[0], thumb[1] = float(bestopp[1]), bestopp[2]
    for tj in (2, 3, 4):
        moving = verts_of(THUMB[max(1, tj - 2):])
        while thumb[tj] < 80:
            thumb[tj] += 2
            v, _ = pose({k: tuple(x) for k, x in curl.items()}, tuple(thumb))
            if hits(v, moving): thumb[tj] -= 2; break
    v, n = pose({k: tuple(x) for k, x in curl.items()}, tuple(thumb))
    out = to_out(v, c); out[:, 0] -= np.median(out[:, 0])
    wr = to_out(jpos['wrist'][None], c)[0]; wr[0] -= np.median(to_out(v, c)[:, 0])
    print("pump wrist at", wr.round(1))
    print("pump grip:", {f: [int(x) for x in curl[f]] for f in FINGERS}, "thumb", [int(x) for x in thumb])
    return out, n @ R.T

# posed frames for other tools (pump hand on the shotgun); path from RL_HAND_NPZ
if os.environ.get('RL_HAND_NPZ'):
    pump_xyz, pump_nrm = fit_pump()
    np.savez(os.environ['RL_HAND_NPZ'], xyz=np.array(xyz), nrm=np.array(nrm), idx=IDX, uv=UV, grip_centre=GRIP,
             pump_xyz=pump_xyz, pump_nrm=pump_nrm)

if PREVIEW:
    import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
    fig, ax = plt.subplots(2, 4, figsize=(16, 7))
    for i, ((name, _, _), v) in enumerate(zip(POSES, xyz[:4])):
        for r, (a, b, lab) in enumerate([(0, 2, 'side (x fwd, z up)'), (0, 1, 'top (x fwd, y)')]):
            ax[r, i].triplot(v[:, a], v[:, b], IDX, lw=0.15, color='k')
            if name == 'mag':
                for mv in mag_frames[0]: ax[r, i].scatter(mv[:, a], mv[:, b], s=2, c='r', alpha=0.4)
            ax[r, i].set_aspect('equal'); ax[r, i].set_title(f'{name} - {lab}', fontsize=8)
    plt.tight_layout(); plt.savefig(PREVIEW, dpi=80)
