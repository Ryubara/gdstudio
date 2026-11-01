# Lessons

Problems that cost time once and should not again. Newest first; one short entry each.

## Movie Maker ignores `--resolution`

Capturing with `--write-movie` and `--resolution 1280x720` still wrote 1920x1080 frames (Godot 4.7.2, Windows): the
movie is the project's viewport size. To get smaller frames, scale them afterwards, which is what `gds capture sheet`
and `gds capture clip` do ([capture](capture.md)).
