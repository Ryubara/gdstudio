# Blender resolved a relative output path itself

2026-11-01

- **Saw:** a render script given a relative `--out` path wrote its files somewhere other than the folder the shell
  was in (Deadnight #438).
- **Cause:** the path is resolved by Blender, not by the shell that started it.
- **Fix:** pass absolute paths to Blender scripts, or make them absolute in the shell (`"$(pwd)/out"`) before the call.
- **Docs:** [Key art](../blender/key-art.md).
