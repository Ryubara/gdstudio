"""Writes a `.import` beside every texture of the test project's asset folder, so a headless import compresses
them for the GPU (S3TC/BPTC), builds mipmaps and treats `*_normal.png` as normal maps. Without it a headless
import keeps every 4K map lossless and uncompressed in video memory.

    python write_imports.py <asset folder> [--lossless-normals]

`--lossless-normals` keeps the skin's 16-bit normal maps uncompressed, to compare against the compressed ones
(kit docs: tools/blender/realistic-characters.md#limb-lines); the build ships them compressed.
"""

import sys
from pathlib import Path

TEMPLATE = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode={mode}
compress/high_quality={hq}
compress/normal_map={normal}
mipmaps/generate=true
detect_3d/compress_to=0
"""

lossless = "--lossless-normals" in sys.argv
for png in sorted(Path(sys.argv[1]).glob("*.png")):
    normal = png.stem.endswith("_normal")
    keep = lossless and png.stem in ("head_normal", "body_normal")
    text = TEMPLATE.format(normal=1 if normal else 0, mode=0 if keep else 2,
                           hq="true" if png.stem in ("head_albedo", "hair_albedo") else "false")
    png.with_name(png.name + ".import").write_text(text, encoding="utf-8", newline="\n")
    print("import", png.name, "normal map" if normal else "", "lossless" if keep else "")
