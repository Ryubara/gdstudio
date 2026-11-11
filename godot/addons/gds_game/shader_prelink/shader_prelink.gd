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
##
## The page can start sooner: with the `gds_game` editor plugin on, a web export writes the list
## (`list_path()`) beside `index.html` and a script into its head that links it before the engine
## boots (`ShaderPrelinkExport`, `with_page_start`), so the engine's own boot programs and the list
## link while the wasm downloads; `start` then follows the page's links instead of reading the file.

## The list's format; a list of another is not read.
const FORMAT := 1
## Seconds `wait` waits at most: a page whose links never end still starts the game.
const TIMEOUT := 30.0
## The page's side: decodes the list, compiles and links it in the engine's WebGL context and
## reports into `window.gdsPrelink` (`total`, `left`, `done`, `asked`, `began`, `ms`, `skipped`,
## `from`, `mismatch`). `load(url, attributes)` is the page's own start, which the export writes
## into `index.html` (`with_page_start`): before the engine boots it fetches the list served
## beside the page and makes the canvas's context itself with the engine's attributes, so the
## engine's boot programs and the list link while the wasm downloads. `start(data)` is the
## engine's, in the context the engine made. It never reads a program's `LINK_STATUS`, and a probe
## that wraps WebGL can tell its programs by their `__prelink` flag.
const PAGE_SCRIPT := """
(() => {
  if (window.gdsPrelink) { return; }
  const state = { total: 0, left: 0, done: false, ms: 0, skipped: '', from: '', mismatch: '' };
  window.gdsPrelink = state;
  let began = performance.now();
  const finish = (why) => { state.skipped = why || ''; state.left = 0; state.done = true;
    state.ms = Math.round(performance.now() - began); };
  const off = () => new URLSearchParams(window.location.search).has('noprelink');
  const canvas = () => document.querySelector('canvas#canvas') || document.querySelector('canvas');
  // The engine's later getContext gets this context back whatever it asks for: say so when it
  // asks for other attributes than the ones the context was made with.
  const watch = (element, attributes) => {
    const own = element.getContext;
    element.getContext = function (kind, asked) {
      if (kind === 'webgl2' && asked) {
        const differs = Object.keys(attributes)
          .filter((key) => key in asked && String(asked[key]) !== String(attributes[key]));
        if (differs.length) { state.mismatch = differs.join(' '); }
      }
      return own.call(this, kind, asked);
    };
  };
  // Before the engine: a throwaway context says whether the browser links in parallel, so a page
  // without it (SwiftShader) is left as it was. With it, the canvas's context is made here with
  // every extension Emscripten turns on (it skips only lose_context and debug): the GPU process
  // hands a linked program to a later link of the same sources only with the same extensions on.
  const early = (attributes) => {
    const probe = document.createElement('canvas').getContext('webgl2');
    const offered = (probe && probe.getSupportedExtensions()) || [];
    const can = offered.includes('KHR_parallel_shader_compile');
    const lose = probe && probe.getExtension('WEBGL_lose_context');
    if (lose) { lose.loseContext(); }
    const element = canvas();
    if (!can || !element) { return null; }
    const gl = element.getContext('webgl2', attributes);
    if (!gl) { return null; }
    for (const name of gl.getSupportedExtensions() || []) {
      if (!name.includes('lose_context') && !name.includes('debug')) { gl.getExtension(name); }
    }
    watch(element, attributes);
    return gl;
  };
  const link = (data, attributes) => {
    began = performance.now();
    state.began = Math.round(began);
    if (off()) { finish('off'); return; }
    // The engine's own context: nothing here binds anything, so its state is untouched.
    const gl = attributes ? early(attributes) : (canvas() && canvas().getContext('webgl2'));
    const ext = gl && gl.getExtension('KHR_parallel_shader_compile');
    if (!ext) { finish('no parallel compile'); return; }
    // Each program's shaders are compiled just before its link, in the list's order (the engine's
    // boot programs first), so the GPU process's workers take the first programs first.
    const stream = [], texts = [];
    for (const [type, items] of data.shaders) {
      const lines = [];
      for (const item of items) {
        if (typeof item === 'string') { lines.push(item); continue; }
        for (let i = item[0]; i < item[0] + item[1]; i++) { lines.push(stream[i]); }
      }
      for (const line of lines) { stream.push(line); }
      texts.push([type, lines.join('\\n')]);
    }
    const shaders = [];
    const shader = (index) => {
      if (!shaders[index]) {
        shaders[index] = gl.createShader(texts[index][0]);
        gl.shaderSource(shaders[index], texts[index][1]);
        gl.compileShader(shaders[index]);
      }
      return shaders[index];
    };
    const programs = [];
    for (const [stages, bindings, feedback] of data.programs) {
      const program = gl.createProgram();
      program.__prelink = true;
      for (const index of stages) { gl.attachShader(program, shader(index)); }
      for (const [at, name] of bindings) { gl.bindAttribLocation(program, at, name); }
      if (feedback) { gl.transformFeedbackVaryings(program, feedback[0], feedback[1]); }
      gl.linkProgram(program);
      programs.push(program);
    }
    const pending = programs;
    gl.flush();
    state.total = pending.length;
    state.left = pending.length;
    // In the list's order, up to the first one not ready: each read is a round trip to the GPU
    // process, so a poll makes few of them.
    let next = 0;
    const status = ext.COMPLETION_STATUS_KHR;
    const poll = () => {
      while (next < pending.length && gl.getProgramParameter(pending[next], status)) { next += 1; }
      state.left = pending.length - next;
      if (next < pending.length) { setTimeout(poll, 30); return; }
      for (const program of programs) { gl.deleteProgram(program); }
      for (const made of shaders) { if (made) { gl.deleteShader(made); } }
      finish('');
    };
    poll();
  };
  // The engine's start, in the context it made.
  state.start = (data) => {
    if (state.from) { return; }
    state.from = 'engine';
    link(data, null);
  };
  // The page's own start, before the engine boots: the list served beside the page.
  state.load = (url, attributes) => {
    if (state.from) { return; }
    state.from = 'page';
    state.asked = Math.round(performance.now());
    if (off()) { finish('off'); return; }
    const list = fetch(url).then((answer) => (answer.ok ? answer.json() : null)).catch(() => null);
    const parsed = new Promise((ready) => {
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', ready, { once: true });
      } else { ready(); }
    });
    Promise.all([list, parsed]).then(([data]) => {
      if (data) { link(data, attributes); } else { began = performance.now(); finish('no list'); }
    });
  };
})();
"""
## The project setting naming the list the export serves beside `index.html` for the page's start.
const LIST_SETTING := "gds_game/shader_prelink/list"
## The list when the setting is not set (3D Third Person's).
const DEFAULT_LIST := "res://assets/shaders/web/shader_programs.json"
## What the page's start leaves in `index.html`, so a second pass does not add it twice.
const PAGE_MARK := "window.gdsPrelink.load("

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
	# The page started its own list before the engine booted (`with_page_start`): follow that one.
	if page.call("Boolean(window.gdsPrelink && window.gdsPrelink.from)") == true:
		skipped = ""
		_done = false
		return true
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


## The list the export serves beside `index.html` (`LIST_SETTING`, else `DEFAULT_LIST`).
static func list_path() -> String:
	return str(ProjectSettings.get_setting(LIST_SETTING, DEFAULT_LIST))


## The WebGL context attributes the engine asks for (Godot's web display server, with Emscripten's
## offscreen back buffer, which keeps the drawing buffer): the page's start makes the canvas's
## context with these, and the engine's later request gets that context back.
static func context_attributes() -> Dictionary:
	return {
		"alpha": bool(ProjectSettings.get_setting("display/window/per_pixel_transparency/allowed")),
		"depth": true,
		"stencil": false,
		"antialias": false,
		"premultipliedAlpha": true,
		"preserveDrawingBuffer": true,
		"powerPreference": "default",
		"failIfMajorPerformanceCaveat": false,
	}


## `html` with the page's own start in its head: the page script and a `load` of `list_url`
## (relative to the page). Unchanged when it has one already or has no head.
static func with_page_start(html: String, list_url: String) -> String:
	var head := html.find("</head>")
	if head < 0 or html.contains(PAGE_MARK):
		return html
	var attributes := JSON.stringify(context_attributes())
	var call := "%s%s, %s);" % [PAGE_MARK, JSON.stringify(list_url), attributes]
	return html.insert(head, "<script>%s%s</script>\n" % [PAGE_SCRIPT, call])


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
