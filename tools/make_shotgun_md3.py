#!/usr/bin/env python3
"""
Build the physical-reload shotgun models from the HDVR "Shotgun.md3".

Surfaces (found by tracking each part's motion relative to the body):
  0 hammer/top detail, 1 front bead, 2 shell, 3 trigger, 4 pump (forend), 5 bolt, 6 body
Source frames: 0-4 raise, 5-8 fire/recoil, 9-21 tilt + pump, 22-31 shell loading,
               32 idle, 33-35 pump back (no tilt).

Writes:
  RL_Shotgun.md3   original 36 frames + 36..44 pump steps 0/8..8/8 with a shell in the
                   chamber + 45..53 the same with the chamber empty (shell hidden)
  RL_ShotShell.md3 one shell, centred, resting on z = 0
and (if a posed-hand .npz from make_hand_md3.py is given)
  RL_PumpHandA.md3 / RL_PumpHandB.md3  9 frames: off hand wrapped round the pump at each
                   pump step (A = mirrored left hand, B = its mirror image)

Usage: make_shotgun_md3.py <Shotgun.md3> <outdir> [hand_poses.npz]
"""
import sys, os, struct, math
import numpy as np

SRC, OUTDIR = sys.argv[1], sys.argv[2]
HANDNPZ = sys.argv[3] if len(sys.argv) > 3 else None
SHELL, PUMP, BOLT, BODY = 2, 4, 5, 6
IDLE, BACK = 32, 35

d = open(SRC, 'rb').read()
name = d[8:72]
flags, nf, ntags, nsurf, nskins, ofs_frames, ofs_tags, ofs_surf, ofs_end = struct.unpack('<9i', d[72:108])
frames = []
for i in range(nf):
    o = ofs_frames + i * 56
    frames.append(dict(origin=struct.unpack('<3f', d[o+24:o+36]), name=d[o+40:o+56]))
surfs = []
o = ofs_surf
for s in range(nsurf):
    sflags, snf, nsh, nv, ntri, o_tri, o_sh, o_st, o_xyz, o_end = struct.unpack('<10i', d[o+68:o+108])
    raw = np.frombuffer(d[o+o_xyz:o+o_xyz+nf*nv*8], dtype=np.uint8).reshape(nf, nv, 8)
    surfs.append(dict(sid=d[o:o+4], name=d[o+4:o+68], flags=sflags, nsh=nsh, nv=nv, ntri=ntri,
                      tris=d[o+o_tri:o+o_tri+ntri*12], shaders=d[o+o_sh:o+o_sh+nsh*68], st=d[o+o_st:o+o_st+nv*8],
                      xyz=raw[:, :, :6].copy().view('<i2').reshape(nf, nv, 3).astype(np.float64) / 64.0,
                      nrm=raw[:, :, 6:8].copy()))
    o += o_end

delta = (surfs[PUMP]['xyz'][BACK] - surfs[PUMP]['xyz'][IDLE]).mean(0)
print("pump travel (model units):", np.round(delta, 2))

new = {s: [] for s in range(nsurf)}
newn = {s: [] for s in range(nsurf)}
names = []
for shell_in in (True, False):
    for step in range(9):
        k = step / 8.0
        for s in range(nsurf):
            v = surfs[s]['xyz'][IDLE].copy()
            if s in (PUMP, BOLT): v = v + delta * k
            if s == SHELL:
                v = v + delta * k
                if not shell_in: v = np.repeat(v.mean(0, keepdims=True), len(v), 0)
            new[s].append(v); newn[s].append(surfs[s]['nrm'][IDLE])
        names.append(('%s_p%d' % ('shell' if shell_in else 'empty', step)).encode().ljust(16, b'\0'))

def write_md3(path, mdl_name, surf_list, frame_names):
    """surf_list: list of dict(base surface, xyz [F,N,3], nrm [F,N,2])"""
    F = len(frame_names)
    blobs = []
    for S in surf_list:
        q = np.clip(np.round(S['xyz'] * 64.0), -32768, 32767).astype('<i2')
        verts = np.concatenate([q.view(np.uint8).reshape(F, S['nv'], 6), S['nrm']], -1).tobytes()
        o_sh = 108; o_tri = o_sh + len(S['shaders']); o_st = o_tri + len(S['tris']); o_xyz = o_st + len(S['st']); o_e = o_xyz + len(verts)
        h = S['sid'] + S['name'] + struct.pack('<10i', S['flags'], F, S['nsh'], S['nv'], S['ntri'], o_tri, o_sh, o_st, o_xyz, o_e)
        blobs.append(h + S['shaders'] + S['tris'] + S['st'] + verts)
    fb = b''
    for i in range(F):
        pts = np.concatenate([S['xyz'][i] for S in surf_list])
        mn, mx = pts.min(0), pts.max(0)
        fb += struct.pack('<3f3f3ff', *mn, *mx, 0, 0, 0, float(np.linalg.norm(np.abs(pts).max(0)))) + frame_names[i]
    o_su = 108 + len(fb); o_e = o_su + sum(len(b) for b in blobs)
    hdr = b'IDP3' + struct.pack('<i', 15) + mdl_name.ljust(64, b'\0') + struct.pack('<9i', 0, F, 0, len(surf_list), 0, 108, o_su, o_su, o_e)
    open(path, 'wb').write(hdr + fb + b''.join(blobs))

ONLY_HANDS = os.environ.get('RL_PUMPHANDS_ONLY') == '1'
all_names = [f['name'] for f in frames] + names
out_surfs = []
for s in range(nsurf):
    S = dict(surfs[s])
    S['xyz'] = np.concatenate([surfs[s]['xyz'], np.array(new[s])], 0)
    S['nrm'] = np.concatenate([surfs[s]['nrm'], np.array(newn[s])], 0)
    out_surfs.append(S)
if not ONLY_HANDS:
    write_md3(os.path.join(OUTDIR, 'RL_Shotgun.md3'), b'RL_Shotgun', out_surfs, all_names)
    print("wrote RL_Shotgun.md3", len(all_names), "frames")

# ---- loose shell
S = dict(surfs[SHELL])
v = S['xyz'][IDLE] - S['xyz'][IDLE].mean(0)
v[:, 2] -= v[:, 2].min()
S['xyz'] = v[None]; S['nrm'] = surfs[SHELL]['nrm'][IDLE][None]
if not ONLY_HANDS:
    write_md3(os.path.join(OUTDIR, 'RL_ShotShell.md3'), b'RL_ShotShell', [S], [b'shell'.ljust(16, b'\0')])
    print("wrote RL_ShotShell.md3 size", np.round(v.max(0) - v.min(0), 1))

# key positions (model units) for reference / zone defaults
pump_c = surfs[PUMP]['xyz'][IDLE].mean(0)
print("pump centre:", np.round(pump_c, 1), " shell (chamber):", np.round(surfs[SHELL]['xyz'][IDLE].mean(0), 1),
      " loading position:", np.round(surfs[SHELL]['xyz'][28].mean(0), 1))

# ---- hand wrapped round the pump, following the pump
if HANDNPZ:
    H = np.load(HANDNPZ)
    hx, hn, idx, uv = H['xyz'], H['nrm'], H['idx'], H['uv']
    grip = hx[1 + 4 * 1]; gripn = hn[1 + 4 * 1]          # grip pose, orientation A
    centre = H['grip_centre']
    # The grip pose wraps a vertical post (the pistol grip). Pitch it 90 degrees so it
    # wraps the horizontal forend instead: palm under the pump, forearm angled down/back.
    a = math.radians(float(os.environ.get('RL_PUMP_PITCH', '-90')))
    R = np.array([[math.cos(a), 0, math.sin(a)], [0, 1, 0], [-math.sin(a), 0, math.cos(a)]])
    mir = np.array([1, -1, 1])
    base = ((grip - centre) @ R.T) * mir
    basen = (gripn @ R.T) * mir
    off = np.array([float(x) for x in os.environ.get('RL_PUMP_OFFSET', '-7,0.5,-1.5').split(',')])
    target = pump_c + off
    nv = len(base)
    def hand_surf(xyz_frames, nrm, flip):
        t = idx[:, [0, 2, 1]] if flip else idx
        return dict(sid=b'IDP3', name=b'hand'.ljust(64, b'\0'), flags=0, nsh=1, nv=nv, ntri=len(t),
                    tris=t.astype('<i4').tobytes(), shaders=b'hand'.ljust(64, b'\0') + struct.pack('<i', 0),
                    st=uv.astype('<f4').tobytes(), xyz=xyz_frames, nrm=np.repeat(nrm[None], 9, 0))
    def enc(n):
        lat = np.arctan2(n[:, 1], n[:, 0]) * 255 / (2 * math.pi)
        lng = np.arccos(np.clip(n[:, 2], -1, 1)) * 255 / (2 * math.pi)
        return np.stack([np.round(lat).astype(int) & 255, np.round(lng).astype(int) & 255], 1).astype(np.uint8)
    fa = np.array([base + target + delta * (k / 8.0) for k in range(9)])
    fb_ = np.array([(base * mir) + (target * mir) + delta * mir * (k / 8.0) for k in range(9)])
    pnames = [('pump%d' % k).encode().ljust(16, b'\0') for k in range(9)]
    write_md3(os.path.join(OUTDIR, 'RL_PumpHandA.md3'), b'RL_PumpHand', [hand_surf(fa, enc(basen), True)], pnames)
    write_md3(os.path.join(OUTDIR, 'RL_PumpHandB.md3'), b'RL_PumpHand', [hand_surf(fb_, enc(basen * mir), False)], pnames)
    print("wrote RL_PumpHandA/B.md3")
