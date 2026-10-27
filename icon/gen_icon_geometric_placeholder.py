#!/usr/bin/env python3
"""Bobcat-head silhouette as a menu-bar template icon (alpha-only)."""
import struct, zlib, os, math

def write_png(path, w, h, alpha):
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            raw += bytes((0, 0, 0, alpha[y * w + x]))
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        f.write(chunk(b"IEND", b""))


def fill_poly(buf, w, h, pts, val=255, ss=4):
    """Scanline polygon fill with ss x ss supersampling for smooth edges."""
    acc = [[0] * w for _ in range(h)]
    P = [(x * ss, y * ss) for x, y in pts]
    H = h * ss
    for sy in range(H):
        xs = []
        for i in range(len(P)):
            x1, y1 = P[i]
            x2, y2 = P[(i + 1) % len(P)]
            if (y1 <= sy < y2) or (y2 <= sy < y1):
                t = (sy - y1) / (y2 - y1)
                xs.append(x1 + t * (x2 - x1))
        xs.sort()
        for j in range(0, len(xs) - 1, 2):
            for sx in range(int(math.ceil(xs[j])), int(math.floor(xs[j + 1])) + 1):
                if 0 <= sx < w * ss:
                    acc[sy // ss][sx // ss] += 1
    for y in range(h):
        for x in range(w):
            a = min(255, int(acc[y][x] * 255 / (ss * ss)))
            if a:
                buf[y * w + x] = max(buf[y * w + x], a if val == 255 else 0) if val else 0
                if val:
                    buf[y * w + x] = max(buf[y * w + x], a)


def carve_ellipse(buf, w, h, cx, cy, rx, ry, angle=0.0):
    ca, sa = math.cos(-angle), math.sin(-angle)
    for y in range(h):
        for x in range(w):
            dx, dy = x + 0.5 - cx, y + 0.5 - cy
            rxx = dx * ca - dy * sa
            ryy = dx * sa + dy * ca
            if (rxx / rx) ** 2 + (ryy / ry) ** 2 <= 1.0:
                buf[y * w + x] = 0


def bobcat(size):
    w = h = size
    s = size / 36.0
    def P(x, y): return (x * s, y * s)
    head = [
        P(5, 3), P(12, 12), P(18, 9.5), P(24, 12), P(31, 3),      # ear line
        P(28, 15), P(32, 23),                                      # right ear base + cheek
        P(25, 32), P(18, 35), P(11, 32),                           # right jaw, chin, left jaw
        P(4, 23), P(8, 15),                                        # left cheek + ear base
    ]
    buf = [0] * (w * h)
    fill_poly(buf, w, h, head, ss=4 if size <= 40 else 3)
    # eyes: angled almond holes for that Texas State "attitude"
    carve_ellipse(buf, w, h, 13.5 * s, 19 * s, 3.1 * s, 1.7 * s, angle=math.radians(22))
    carve_ellipse(buf, w, h, 22.5 * s, 19 * s, 3.1 * s, 1.7 * s, angle=math.radians(-22))
    return w, h, buf


if __name__ == "__main__":
    out = os.path.dirname(os.path.abspath(__file__))
    for size, suffix in [(18, ""), (36, "@2x")]:
        w, h, buf = bobcat(size)
        write_png(os.path.join(out, f"BobcatTemplate{suffix}.png"), w, h, buf)
        print("wrote", f"BobcatTemplate{suffix}.png")
    # zoomed preview
    w, h, buf = bobcat(36)
    z = 8
    big = [buf[(y // z) * w + (x // z)] for y in range(h * z) for x in range(w * z)]
    write_png(os.path.join(out, "BIG_bobcat.png"), w * z, h * z, big)
    print("wrote BIG_bobcat.png")
