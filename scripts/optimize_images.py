#!/usr/bin/env python3
"""
Batch Image Optimization and WebP Converter for tch-nginx-gui
- Resizes oversized PNGs (e.g. gateway_AGTHF.png) to high-DPI web standards (max 960x540)
- Converts PNGs to WebP for modern browser efficiency
- Validates compression ratios and reports total byte savings
"""

import argparse
import os
import sys
from pathlib import Path
from PIL import Image

MAX_GATEWAY_WIDTH = 960
MAX_GATEWAY_HEIGHT = 700
WEBP_QUALITY = 85


def format_bytes(b):
    if b < 1024:
        return f"{b} B"
    elif b < 1024 * 1024:
        return f"{b / 1024:.1f} KB"
    return f"{b / (1024 * 1024):.2f} MB"


def optimize_png(file_path: Path, dry_run=False):
    """Downsample and re-compress oversized PNGs."""
    orig_size = file_path.stat().st_size
    try:
        with Image.open(file_path) as img:
            w, h = img.size
            needs_resize = False

            # Check if this is an oversized gateway or diagram image (>960x540)
            if (w > MAX_GATEWAY_WIDTH or h > MAX_GATEWAY_HEIGHT) and "gateway_" in file_path.name:
                needs_resize = True
                ratio = min(MAX_GATEWAY_WIDTH / w, MAX_GATEWAY_HEIGHT / h)
                new_w = int(w * ratio)
                new_h = int(h * ratio)

            if needs_resize:
                print(f"[RESIZE] {file_path.name}: {w}x{h} -> {new_w}x{new_h}")
                if not dry_run:
                    resized = img.resize((new_w, new_h), Image.Resampling.LANCZOS)
                    resized.save(file_path, "PNG", optimize=True)
                    new_size = file_path.stat().st_size
                    saved = orig_size - new_size
                    pct = (saved / orig_size) * 100 if orig_size > 0 else 0
                    print(f"  {format_bytes(orig_size)} -> {format_bytes(new_size)} (-{pct:.1f}%)")
                    return orig_size, new_size
            else:
                # Still try to optimize standard PNG compression if size > 50KB
                if orig_size > 50 * 1024 and not dry_run:
                    temp_path = file_path.with_suffix(".tmp.png")
                    img.save(temp_path, "PNG", optimize=True)
                    temp_size = temp_path.stat().st_size
                    if temp_size < orig_size:
                        temp_path.replace(file_path)
                        return orig_size, temp_size
                    else:
                        temp_path.unlink()
    except Exception as e:
        print(f"[ERROR] Optimizing {file_path}: {e}", file=sys.stderr)

    return orig_size, orig_size


def convert_to_webp(file_path: Path, dry_run=False):
    """Convert PNG to WebP if missing or PNG is newer."""
    webp_path = file_path.with_suffix(".webp")
    png_size = file_path.stat().st_size

    # Skip if webp already exists and is up to date
    if webp_path.exists() and webp_path.stat().st_mtime >= file_path.stat().st_mtime:
        return 0, 0

    try:
        with Image.open(file_path) as img:
            # Handle RGBA / transparency
            if not dry_run:
                img.save(webp_path, "WEBP", quality=WEBP_QUALITY, method=6)
                webp_size = webp_path.stat().st_size
                if webp_size >= png_size:
                    # Keep PNG if WebP is larger (e.g. for tiny indexed sprites)
                    webp_path.unlink()
                    return 0, 0
                saved = png_size - webp_size
                pct = (saved / png_size) * 100 if png_size > 0 else 0
                print(f"[WEBP] Created {webp_path.name}: {format_bytes(png_size)} -> {format_bytes(webp_size)} (-{pct:.1f}%)")
                return png_size, webp_size
            else:
                print(f"[WEBP-PLAN] Would convert {file_path.name} to {webp_path.name}")
                return png_size, png_size
    except Exception as e:
        print(f"[ERROR] Converting {file_path} to WebP: {e}", file=sys.stderr)
        return 0, 0


def main():
    parser = argparse.ArgumentParser(description="Batch Image & WebP Optimizer for tch-nginx-gui")
    parser.add_argument("--dir", default="decompressed", help="Directory to process (default: decompressed)")
    parser.add_argument("--dry-run", action="store_true", help="Report planned changes without modifying files")
    args = parser.parse_args()

    root_dir = Path(args.dir)
    if not root_dir.exists():
        print(f"Error: Directory '{root_dir}' does not exist.", file=sys.stderr)
        sys.exit(1)

    print(f"Scanning '{root_dir}' for PNG images...")
    png_files = list(root_dir.glob("**/img/**/*.png"))
    print(f"Found {len(png_files)} PNG files.\n")

    total_png_orig = 0
    total_png_opt = 0
    total_webp_created = 0

    print("=== Step 1: Optimizing PNGs ===")
    for p in png_files:
        orig, opt = optimize_png(p, dry_run=args.dry_run)
        total_png_orig += orig
        total_png_opt += opt

    png_saved = total_png_orig - total_png_opt
    pct = (png_saved / total_png_orig) * 100 if total_png_orig > 0 else 0
    print(f"\nPNG Optimization Summary: {format_bytes(total_png_orig)} -> {format_bytes(total_png_opt)} (Saved {format_bytes(png_saved)}, -{pct:.1f}%)\n")

    print("=== Step 2: Generating WebP Counterparts ===")
    for p in png_files:
        orig, webp = convert_to_webp(p, dry_run=args.dry_run)
        if webp > 0:
            total_webp_created += 1

    print(f"\nWebP Generation Complete: {total_webp_created} new/updated WebP files.")


if __name__ == "__main__":
    main()
