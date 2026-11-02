# A packed generated image lost its pixels

2026-11-01

- **Saw:** an image made with `bpy.data.images.new`, filled through `image.pixels` and then `pack()`ed came back
  empty in the saved `.blend` (Deadnight #438).
- **Cause:** packing right after writing `pixels` stored the image before the written pixels reached its buffer.
- **Fix:** write the pixels with `image.pixels.foreach_set(values)` and pack when saving the file.
- **Docs:** [Key art](../blender/key-art.md).
