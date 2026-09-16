#!/usr/bin/env python3
"""Arrange unaltered simulator screenshots for Task 13 review (requires Pillow)."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / 'docs/device-evidence/product-v2'
SHOTS = EVIDENCE / 'task13'
SCENES = [
    ('languageSolo', 'Solo list'), ('languageMulti', 'Beach + Festival list'),
    ('languageSingle', 'Single reason'), ('languageCombined', 'Combined reason'),
    ('languageWeather', 'Weather'), ('languageActivity', 'Activity + city'),
    ('languageDevice', 'Owned device'), ('languageChild', 'Explicit child need'),
    ('languageShared', 'Shared quantity'), ('languageQuantity', 'Applied luggage cap'),
    ('languageGroup', 'Per-record family reasons'),
]

def sheet(entries, target):
    width, height, columns = 390, 900, 4
    canvas = Image.new('RGB', (width * columns, height * ((len(entries) + columns - 1) // columns)), '#e9edf2')
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', 18)
    for i, (screen, label, size) in enumerate(entries):
        x, y = (i % columns) * width, (i // columns) * height
        draw.text((x + 12, y + 12), label, fill='#172033', font=font)
        shot = Image.open(SHOTS / f'{screen}-{size}.png').convert('RGB')
        shot.thumbnail((width - 16, height - 48))
        canvas.paste(shot, (x + (width - shot.width) // 2, y + 42))
    canvas.save(target)

sheet([(s, label, 'large') for s, label in SCENES] +
      [('languageActivity', 'Accessibility-large', 'accessibility-large')],
      EVIDENCE / 'task13-reasons-language-sheet.png')
sheet([(s, label + ' / AX', 'accessibility-large') for s, label in SCENES],
      EVIDENCE / 'task13-reasons-accessibility-sheet.png')
