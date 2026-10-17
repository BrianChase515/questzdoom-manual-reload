#!/usr/bin/env python3
"""
Build RL_Pistol.md3 from the HDVR "Pistol.md3".

The source model already contains an *empty* reload (slide locked back,
mag out, mag in, slide release) in frames 8-26.  For a *tactical* reload the
slide must stay forward, so this script appends 18 new frames (one for each
source frame 9..26) in which:
  * the body, hammer, trigger and magazine use the source frame as-is, and
  * the slide (surface 1) and top cartridge (surface 2) use their idle pose
    (frame 2), moved by the same rigid motion the body makes from frame 2 to
    that frame (so they follow the hand's cant during the reload).

Output frames: 0..37 = original, 38..55 = tactical versions of 9..26.

Also appends physical-reload frames:
  56..64 = mag seated, slide pulled back 0/8 .. 8/8 of lock travel
  65..73 = mag removed,  slide pulled back 0/8 .. 8/8
and (optional 3rd arg) writes RL_Mag.md3: the magazine + top round on its own.

Usage: make_tactical_md3.py <Pistol.md3 in> <RL_Pistol.md3 out> [RL_Mag.md3 out] [RL_Round.md3 out]
"""
import struct, sys, math
import numpy as np

SRC, DST = sys.argv[1], sys.argv[2]
BODY, SLIDE, ROUND = 4, 1, 2          # surface indices (verified by bounding boxes)
IDLE = 2
TACT_SRC = list(range(9, 27))         # source frames to make tactical copies of

d = open(SRC, 'rb').read()
ident, ver = struct.unpack('<4si', d[:8])
assert ident == b'IDP3' and ver == 15
name = d[8:72]
flags, nf, ntags, nsurf, nskins, ofs_frames, ofs_tags, ofs_surf, ofs_end = struct.unpack('<9i', d[72:108])
assert ntags == 0, "tags not handled"

# ---- frames headers
frames = []
for i in range(nf):
    o = ofs_frames + i * 56
    mins = struct.unpack('<3f', d[o:o+12]); maxs = struct.unpack('<3f', d[o+12:o+24])
    origin = struct.unpack('<3f', d[o+24:o+36]); radius = struct.unpack('<f', d[o+36:o+40])[0]
    fname = d[o+40:o+56]
    frames.append(dict(origin=origin, name=fname))

# ---- surfaces
surfs = []
o = ofs_surf
for s in range(nsurf):
    sid = d[o:o+4]; sname = d[o+4:o+68]
    sflags, snf, nsh, nv, ntri, o_tri, o_sh, o_st, o_xyz, o_end = struct.unpack('<10i', d[o+68:o+108])
    assert snf == nf
    tris = d[o+o_tri:o+o_tri+ntri*12]
    shaders = d[o+o_sh:o+o_sh+nsh*68]
    st = d[o+o_st:o+o_st+nv*8]
    raw = np.frombuffer(d[o+o_xyz:o+o_xyz+nf*nv*8], dtype=np.uint8).reshape(nf, nv, 8)
    xyz = raw[:, :, :6].copy().view('<i2').reshape(nf, nv, 3).astype(np.float64) / 64.0
    nrm = raw[:, :, 6:8].copy()
    surfs.append(dict(sid=sid, name=sname, flags=sflags, nsh=nsh, nv=nv, ntri=ntri,
                      tris=tris, shaders=shaders, st=st, xyz=xyz, nrm=nrm))
    o += o_end

def decode_n(b):
    lat = b[..., 0].astype(np.float64) * (2 * math.pi / 255.0)
    lng = b[..., 1].astype(np.float64) * (2 * math.pi / 255.0)
    return np.stack([np.cos(lat) * np.sin(lng), np.sin(lat) * np.sin(lng), np.cos(lng)], -1)

def encode_n(n):
    out = np.zeros(n.shape[:-1] + (2,), dtype=np.uint8)
    x, y, z = n[..., 0], n[..., 1], n[..., 2]
    lat = np.arctan2(y, x) * 255.0 / (2 * math.pi)
    lng = np.arccos(np.clip(z, -1, 1)) * 255.0 / (2 * math.pi)
    out[..., 0] = (np.round(lat).astype(int) & 0xFF)
    out[..., 1] = (np.round(lng).astype(int) & 0xFF)
    # poles
    up = z > 0.99999; dn = z < -0.99999
    out[up] = (0, 0); out[dn] = (128, 0)
    return out

def kabsch(P, Q):
    """R,t minimising |R P + t - Q|"""
    cp, cq = P.mean(0), Q.mean(0)
    H = (P - cp).T @ (Q - cq)
    U, S, Vt = np.linalg.svd(H)
    dsign = np.sign(np.linalg.det(Vt.T @ U.T))
    D = np.diag([1, 1, dsign])
    R = Vt.T @ D @ U.T
    return R, cq - R @ cp

# ---- build tactical frames
new_xyz = {s: [] for s in range(nsurf)}
new_nrm = {s: [] for s in range(nsurf)}
report = []
for f in TACT_SRC:
    R, t = kabsch(surfs[BODY]['xyz'][IDLE], surfs[BODY]['xyz'][f])
    resid = np.abs((surfs[BODY]['xyz'][IDLE] @ R.T + t) - surfs[BODY]['xyz'][f]).max()
    ang = math.degrees(math.acos(max(-1, min(1, (np.trace(R) - 1) / 2))))
    report.append((f, round(ang, 2), round(float(resid), 3)))
    for s in range(nsurf):
        if s in (SLIDE, ROUND):
            v = surfs[s]['xyz'][IDLE] @ R.T + t
            n = decode_n(surfs[s]['nrm'][IDLE]) @ R.T
            new_xyz[s].append(v); new_nrm[s].append(encode_n(n))
        else:
            new_xyz[s].append(surfs[s]['xyz'][f]); new_nrm[s].append(surfs[s]['nrm'][f])

# ---- physical-reload frames: slide position steps, with and without magazine
MAG = 3
R8, t8 = kabsch(surfs[SLIDE]['xyz'][IDLE], surfs[SLIDE]['xyz'][8])
print("slide idle->locked rotation (deg):", round(math.degrees(math.acos(max(-1, min(1, (np.trace(R8) - 1) / 2)))), 3))
slide_delta = (surfs[SLIDE]['xyz'][8] - surfs[SLIDE]['xyz'][IDLE]).mean(0)
PHYS = []
for mag_in in (True, False):
    for step in range(9):
        PHYS.append((mag_in, step))
        for s_ in range(nsurf):
            v = surfs[s_]['xyz'][IDLE].copy(); n = surfs[s_]['nrm'][IDLE]
            if s_ == SLIDE:
                v = v + slide_delta * (step / 8.0)
            if not mag_in and s_ in (MAG, ROUND):
                v = np.repeat(v.mean(0, keepdims=True), len(v), 0)   # collapse = invisible
            new_xyz[s_].append(v); new_nrm[s_].append(n)
TACT_SRC_ALL = TACT_SRC + [None] * len(PHYS)

print("frame, body rotation deg, rigid-fit max error (units)")
for r in report: print(" ", r)

total = nf + len(TACT_SRC) + len(PHYS)
all_frames = frames + [dict(origin=frames[f]['origin'], name=('tac%d' % f).encode().ljust(16, b'\0')) for f in TACT_SRC]
all_frames += [dict(origin=frames[IDLE]['origin'], name=('%s_s%d' % ('mag' if m else 'nomag', st)).encode().ljust(16, b'\0')) for m, st in PHYS]

# ---- write
def surf_bytes(s):
    S = surfs[s]
    xyz = np.concatenate([S['xyz'], np.array(new_xyz[s])], 0)
    nrm = np.concatenate([S['nrm'], np.array(new_nrm[s])], 0)
    q = np.clip(np.round(xyz * 64.0), -32768, 32767).astype('<i2')
    verts = np.concatenate([q.view(np.uint8).reshape(total, S['nv'], 6), nrm], -1).tobytes()
    hdr = 108
    o_sh = hdr; o_tri = o_sh + len(S['shaders']); o_st = o_tri + len(S['tris'])
    o_xyz = o_st + len(S['st']); o_end = o_xyz + len(verts)
    h = S['sid'] + S['name'] + struct.pack('<10i', S['flags'], total, S['nsh'], S['nv'], S['ntri'],
                                           o_tri, o_sh, o_st, o_xyz, o_end)
    return h + S['shaders'] + S['tris'] + S['st'] + verts, xyz

surf_blobs, all_xyz = [], []
for s in range(nsurf):
    b, x = surf_bytes(s); surf_blobs.append(b); all_xyz.append(x)

frame_blob = b''
for i, fr in enumerate(all_frames):
    pts = np.concatenate([x[i] for x in all_xyz], 0)
    mn, mx = pts.min(0), pts.max(0)
    rad = float(np.linalg.norm(np.maximum(np.abs(mn), np.abs(mx))))
    frame_blob += struct.pack('<3f3f3ff', *mn, *mx, *fr['origin'], rad) + fr['name']

o_frames = 108
o_tags = o_frames + len(frame_blob)
o_surf = o_tags
o_end = o_surf + sum(len(b) for b in surf_blobs)
header = b'IDP3' + struct.pack('<i', 15) + name + struct.pack('<9i', flags, total, 0, nsurf, nskins, o_frames, o_tags, o_surf, o_end)
open(DST, 'wb').write(header + frame_blob + b''.join(surf_blobs))
print("wrote", DST, total, "frames")

# ---- standalone magazine model (mag + top round), centred on the magazine
if len(sys.argv) > 3:
    parts = [MAG, ROUND]
    centre = surfs[MAG]['xyz'][IDLE].mean(0)
    blobs = []
    for s_ in parts:
        S = surfs[s_]
        q = np.clip(np.round((S['xyz'][IDLE] - centre) * 64.0), -32768, 32767).astype('<i2')
        verts = np.concatenate([q.view(np.uint8).reshape(S['nv'], 6), S['nrm'][IDLE]], -1).tobytes()
        o_sh = 108; o_tri = o_sh + len(S['shaders']); o_st = o_tri + len(S['tris']); o_xyz = o_st + len(S['st']); o_e = o_xyz + len(verts)
        h = S['sid'] + S['name'] + struct.pack('<10i', S['flags'], 1, S['nsh'], S['nv'], S['ntri'], o_tri, o_sh, o_st, o_xyz, o_e)
        blobs.append(h + S['shaders'] + S['tris'] + S['st'] + verts)
    pts = np.concatenate([surfs[s_]['xyz'][IDLE] - centre for s_ in parts])
    mn, mx = pts.min(0), pts.max(0)
    fr = struct.pack('<3f3f3ff', *mn, *mx, 0, 0, 0, float(np.abs(pts).max() * 1.8)) + b'mag'.ljust(16, b'\0')
    o_fr = 108; o_su = o_fr + len(fr); o_e = o_su + sum(len(b) for b in blobs)
    hdr = b'IDP3' + struct.pack('<i', 15) + b'RL_Mag'.ljust(64, b'\0') + struct.pack('<9i', 0, 1, 0, len(parts), 0, o_fr, o_su, o_su, o_e)
    open(sys.argv[3], 'wb').write(hdr + fr + b''.join(blobs))
    print("wrote", sys.argv[3], "mag size (units):", np.round(mx - mn, 1))

# ---- loose cartridge (ejected when racking with a round chambered), resting on z = 0
if len(sys.argv) > 4:
    S = surfs[ROUND]
    v = S['xyz'][IDLE] - S['xyz'][IDLE].mean(0)
    v[:, 2] -= v[:, 2].min()
    q = np.clip(np.round(v * 64.0), -32768, 32767).astype('<i2')
    verts = np.concatenate([q.view(np.uint8).reshape(S['nv'], 6), S['nrm'][IDLE]], -1).tobytes()
    o_sh = 108; o_tri = o_sh + len(S['shaders']); o_st = o_tri + len(S['tris']); o_xyz = o_st + len(S['st']); o_e = o_xyz + len(verts)
    h = S['sid'] + S['name'] + struct.pack('<10i', S['flags'], 1, S['nsh'], S['nv'], S['ntri'], o_tri, o_sh, o_st, o_xyz, o_e)
    blob = h + S['shaders'] + S['tris'] + S['st'] + verts
    mn, mx = v.min(0), v.max(0)
    fr = struct.pack('<3f3f3ff', *mn, *mx, 0, 0, 0, float(np.abs(v).max() * 1.8)) + b'round'.ljust(16, b'\0')
    o_su = 108 + len(fr); o_e2 = o_su + len(blob)
    hdr = b'IDP3' + struct.pack('<i', 15) + b'RL_Round'.ljust(64, b'\0') + struct.pack('<9i', 0, 1, 0, 1, 0, 108, o_su, o_su, o_e2)
    open(sys.argv[4], 'wb').write(hdr + fr + blob)
    print("wrote", sys.argv[4], "round size:", np.round(mx - mn, 1))
