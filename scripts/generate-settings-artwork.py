#!/usr/bin/env python3
"""Convert the supplied circular SVG arcs to native cubic paths."""
import math
import re
from pathlib import Path
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
source = root / 'Sources/AgentHUDDesktop/Resources/Navigation/settings.svg'
target = root / 'Sources/AgentHUDDesktop/Windows/SettingsArtwork.swift'
svg = ET.parse(source).getroot()
path = svg.find('{http://www.w3.org/2000/svg}path')
tokens = re.findall(r'[MmAa]|-?\d*\.?\d+', path.attrib['d'])
i = 0
x = y = 0.0
lines = []

def point(a, b):
    return f'CGPoint(x: {a:.9f}, y: {b:.9f})'

while i < len(tokens):
    if tokens[i].isalpha():
        command = tokens[i]
        i += 1
    if command in 'Mm':
        nx, ny = map(float, tokens[i:i + 2])
        i += 2
        if command == 'm':
            nx, ny = x + nx, y + ny
        x, y = nx, ny
        lines.append(f'path.move(to: {point(x, y)})')
    else:
        rx, ry, rotation, large, sweep, nx, ny = map(float, tokens[i:i + 7])
        i += 7
        assert rx == ry and rotation == 0
        if command == 'a':
            nx, ny = x + nx, y + ny
        dx, dy = (x - nx) / 2, (y - ny) / 2
        r = max(rx, math.hypot(dx, dy))
        factor = math.sqrt(max(0, (r * r - dx * dx - dy * dy) / (dx * dx + dy * dy)))
        if large == sweep:
            factor = -factor
        cx, cy = (x + nx) / 2 + factor * dy, (y + ny) / 2 - factor * dx
        start, end = math.atan2(y - cy, x - cx), math.atan2(ny - cy, nx - cx)
        delta = (end - start) % (2 * math.pi)
        if not sweep:
            delta -= 2 * math.pi
        count = math.ceil(abs(delta) / (math.pi / 2))
        step = delta / count
        for n in range(count):
            a, b = start + n * step, start + (n + 1) * step
            k = 4 / 3 * math.tan(step / 4)
            p1 = (cx + r * (math.cos(a) - k * math.sin(a)), cy + r * (math.sin(a) + k * math.cos(a)))
            p2 = (cx + r * (math.cos(b) + k * math.sin(b)), cy + r * (math.sin(b) - k * math.cos(b)))
            endp = (cx + r * math.cos(b), cy + r * math.sin(b))
            lines.append(f'path.addCurve(to: {point(*endp)}, control1: {point(*p1)}, control2: {point(*p2)})')
        x, y = nx, ny
lines.append('path.addEllipse(in: CGRect(x: 9, y: 9, width: 6, height: 6))')
target.write_text('''import SwiftUI

// Generated from Resources/Navigation/settings.svg. Run scripts/generate-settings-artwork.py.
// Cubic segments preserve the supplied circular SVG arcs at subpixel precision.
struct SettingsArtwork: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
''' + '\n'.join('        ' + line for line in lines) + '''
        let scale = min(rect.width, rect.height) / 24
        return path.applying(CGAffineTransform(scaleX: scale, y: scale))
    }
}
''')
