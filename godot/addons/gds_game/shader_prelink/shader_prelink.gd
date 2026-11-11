class_name ShaderPrelink
extends RefCounted
## Has a browser build its GL programs linked before the game draws them, all at once and off the
## page's thread, from a list a browser run of the same build recorded.
##
## The Compatibility renderer links each GL program at its first draw and reads the result at once,
## so the page waits for every link in turn: 3D Third Person's 160 programs took 21 s on a fresh
## browser profile (ANGLE on Direct3D 11), in frames of up to 12 s. Linked all at once in a second
## WebGL context with `KHR_parallel_shader_compile`, the same programs took 2.6 s, and the GPU
## process keeps what it built: the game's own links then find them (0.7 s for all of them).
##
## `start(path)` reads the list (`tools/web_smoke/shader_programs.py` in the template writes it from
## a browser run) and hands it to the page; `is_done()` and `progress()` say how far it is, and
## `wait(tree)` waits for it, never longer than `timeout`. Off the web, with a list made by another
## Godot, without the extension or with `?noprelink` in the page's address it does nothing and is
## done at once. A program the list lacks is linked when first drawn, as before.

## The list's format; a list of another is not read.
const FORMAT := 1
## Seconds `wait` waits at most: a page whose links never end still starts the game.
const TIMEOUT := 30.0
## The page's side: decodes the list, compiles and links it in a context of its own and reports
## into `window.gdsPrelink` (`total`, `left`, `done`, `began`, `ms`, `skipped`). It never reads a
## program's `LINK_STATUS`, and a probe that wraps WebGL can tell its programs by their `__prelink`
## flag.
const PAGE_SCRIPT := """
(() => {
  if (window.gdsPrelink) { return; }
  const state = { total: 0, left: 0, done: false, ms: 0, skipped: '' };
  window.gdsPrelink = state;
  state.start = (data) => {
    const began = performance.now();
    state.began = Math.round(began);
    const finish = (why) => { state.skipped = why || ''; state.left = 0; state.done = true;
      state.ms = Math.round(performance.now() - began); };
    if (new URLSearchParams(window.location.search).has('noprelink')) { finish('off'); return; }
    // The engine's own context: the GPU process hands a linked program to a later link of the same
    // sources only in a context with the same extensions on (a second context, with others, found
    // none). Nothing here binds anything, so the engine's state is untouched.
    const canvas = document.querySelector('canvas#canvas') || document.querySelector('canvas');
    const gl = canvas && canvas.getContext('webgl2');
    const ext = gl && gl.getExtension('KHR_parallel_shader_compile');
    if (!ext) { finish('no parallel compile'); return; }
    const stream = [], shaders = [];
    for (const [type, items] of data.shaders) {
      const lines = [];
      for (const item of items) {
        if (typeof item === 'string') { lines.push(item); continue; }
        for (let i = item[0]; i < item[0] + item[1]; i++) { lines.push(stream[i]); }
      }
      for (const line of lines) { stream.push(line); }
      const shader = gl.createShader(type);
      gl.shaderSource(shader, lines.join('\\n'));
      gl.compileShader(shader);
      shaders.push(shader);
    }
    const programs = [];
    for (const [stages, attributes, feedback] of data.programs) {
      const program = gl.createProgram();
      program.__prelink = true;
      for (const index of stages) { gl.attachShader(program, shaders[index]); }
      for (const [at, name] of attributes) { gl.bindAttribLocation(program, at, name); }
      if (feedback) { gl.transformFeedbackVaryings(program, feedback[0], feedback[1]); }
      gl.linkProgram(program);
      programs.push(program);
    }
    const pending = programs.slice();
    gl.flush();
    state.total = pending.length;
    state.left = pending.length;
    const poll = () => {
      for (let i = pending.length - 1; i >= 0; i--) {
        if (gl.getProgramParameter(pending[i], ext.COMPLETION_STATUS_KHR)) { pending.splice(i, 1); }
      }
      state.left = pending.length;
      if (pending.length) { setTimeout(poll, 30); return; }
      for (const program of programs) { gl.deleteProgram(program); }
      for (const shader of shaders) { gl.deleteShader(shader); }
      finish('');
    };
    poll();
  };
})();
"""

## Runs page code and answers its value (`JavaScriptBridge.eval` on the web); a test gives its own.
static var page := Callable()
## Why the last `start` did nothing, empty when it handed the list to the page.
static var skipped := ""

static var _started := false
static var _done := true


## Reads the list at `path` and has the page link it. Answers whether it did; at most once a run.
static func start(path: String) -> bool:
	if _started:
		return not _done
	_started = true
	_done = true
	if not page.is_valid():
		if not OS.has_feature("web"):
			skipped = "not a browser"
			return false
		page = func(code: String) -> Variant: return JavaScriptBridge.eval(code, true)
	# The recorder (`shader_programs.py`) reads which Godot made the programs from here.
	page.call("window.gdsEngine = %s;" % JSON.stringify(engine_version()))
	var text := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var data: Variant = JSON.parse_string(text) if not text.is_empty() else null
	skipped = why_not(data)
	if not skipped.is_empty():
		return false
	page.call(PAGE_SCRIPT)
	page.call("window.gdsPrelink.start(%s);" % text)
	_done = false
	return true


## Why a parsed list cannot be used here, empty when it can.
static func why_not(data: Variant) -> String:
	if not data is Dictionary:
		return "no list"
	var list := data as Dictionary
	if int(list.get("format", 0)) != FORMAT:
		return "another format"
	if str(list.get("godot", "")) != engine_version():
		return "made by Godot %s" % str(list.get("godot", "?"))
	if not list.get("shaders") is Array or not list.get("programs") is Array:
		return "no programs"
	return ""


## The version string a list records and must match: the engine writes other shaders in another.
static func engine_version() -> String:
	return str(Engine.get_version_info().get("string", ""))


## Whether the page has linked everything (or nothing was started).
static func is_done() -> bool:
	if not _done and bool(page.call("window.gdsPrelink.done")):
		_done = true
	return _done


## How far the links are, 0 to 1 (1 when nothing was started).
static func progress() -> float:
	if is_done():
		return 1.0
	var total := int(page.call("window.gdsPrelink.total"))
	var left := int(page.call("window.gdsPrelink.left"))
	return 0.0 if total <= 0 else clampf(1.0 - float(left) / float(total), 0.0, 1.0)


## Waits frames of `tree` until the links are done or `timeout` seconds of real time have passed.
static func wait(tree: SceneTree, timeout: float = TIMEOUT) -> void:
	var until := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not is_done() and Time.get_ticks_msec() < until:
		await tree.process_frame


## Forgets the last start (for tests).
static func reset() -> void:
	page = Callable()
	skipped = ""
	_started = false
	_done = true
