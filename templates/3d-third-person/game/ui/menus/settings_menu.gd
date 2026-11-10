class_name SettingsMenu
extends UIScreen
## The settings screen: tabs (video, audio, controls) of rows bound to the `Settings` autoload. A
## change applies at once and saves itself; this script only switches the tabs, wires the focus so
## that every control is reachable with a key or a pad, and handles Back and Reset.
##
## Push it from any menu with `UIRouter.push("res://ui/menus/settings_menu.tscn")`. The tabs are
## the children of `%Tabs`, the pages the children of `%Pages`, in the same order: add a tab by
## adding a button and a page. A page is a column of `SettingRow` nodes, or of its own controls.

## The card's width on a roomy screen, in units.
const CARD_WIDTH := 1100.0
## A canvas this high or lower (units) is a phone held sideways: the heading goes and the margins
## thin out so the rows keep their room.
const COMPACT_HEIGHT := 600.0
const EDGE := 48
const EDGE_COMPACT := 16

var _tabs: Array[Button] = []
var _pages: Array[Control] = []
var _current := -1

@onready var _scroll: UIFitScroll = %Scroll
@onready var _card: Control = %Card
@onready var _margin: MarginContainer = %Margin
@onready var _column: Control = %Column
@onready var _overline: Control = %Overline
@onready var _title: Control = %Title
@onready var _fit: Control = %Fit
@onready var _reset: Button = %ResetButton
@onready var _back: Button = %BackButton


func _ready() -> void:
	super._ready()
	for tab in %Tabs.get_children():
		_tabs.append(tab as Button)
	for page in %Pages.get_children():
		_pages.append(page as Control)
	for i in _tabs.size():
		_tabs[i].pressed.connect(select_tab.bind(i))
	_scroll.limit = _fit
	_scroll.card = _card
	_fit.resized.connect(fit_card)
	_reset.pressed.connect(_on_reset)
	_back.pressed.connect(_on_back)
	for page in _pages:
		if page is ControlsPage:
			(page as ControlsPage).listening_changed.connect(_on_listening_changed)
	initial_focus = _tabs[0].get_path()
	select_tab(0, false)
	fit_card()


## Sizes the card to the screen: as wide as it may be, and on a short screen without its heading and
## with thinner margins, so the rows keep the height.
func fit_card() -> void:
	if _fit.size.x <= 0.0:
		return
	var compact := _fit.size.y <= COMPACT_HEIGHT
	var edge := EDGE_COMPACT if compact else EDGE
	for side in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		_margin.add_theme_constant_override(side, edge)
	_overline.visible = not compact
	_title.visible = not compact
	var padding := _card.get_theme_stylebox(&"panel").get_minimum_size().x
	_column.custom_minimum_size.x = minf(CARD_WIDTH, _fit.size.x - 2.0 * edge - padding)
	_scroll.margin = float(edge)
	_scroll.fit()


## Shows tab `index`; its rows rise in one after another unless `animate` is off.
func select_tab(index: int, animate := true) -> void:
	var target := clampi(index, 0, _pages.size() - 1)
	if target == _current:
		return
	# Hiding a page drops the focus of a control on it, and nothing would give it back.
	var refocus := _has_focus_in_page(_current)
	_current = target
	for i in _pages.size():
		_pages[i].visible = i == target
		(_tabs[i] as UIButton).variant = (
			UIButton.Variant.PRIMARY if i == target else UIButton.Variant.GHOST
		)
	if animate:
		var rows: Array[Control] = []
		for row in _pages[target].get_children():
			if (row as Control).visible:
				rows.append(row as Control)
		UIMotion.stagger_in(rows)
	link_focus()
	if refocus:
		_tabs[target].grab_focus()


## The index of the tab shown.
func current_tab() -> int:
	return _current


## The controls of the shown page, a row of them for each row of the page, top to bottom.
func focus_rows() -> Array:
	var rows := []
	if _current < 0:
		return rows
	for row in _pages[_current].get_children():
		if not (row as Control).visible:
			continue
		if row is RebindRow:
			rows.append((row as RebindRow).buttons())
		elif row is SettingRow and (row as SettingRow).control != null:
			rows.append([(row as SettingRow).control])
	return rows


## Arrow keys and the d-pad choose the nearest control by position, and from a tab strip that is
## the footer, skipping the rows. So the column is linked by hand: tabs, each row, the footer, and
## back up; a row's controls link to the same place in the rows above and below.
func link_focus() -> void:
	var rows := focus_rows()
	var footer: Array[Control] = [_reset, _back]
	_link_row(_tabs, [], rows[0] if not rows.is_empty() else footer)
	for r in rows.size():
		var above: Array = _tabs if r == 0 else rows[r - 1]
		var below: Array = footer if r == rows.size() - 1 else rows[r + 1]
		_link_row(rows[r], above, below)
	_link_row(footer, rows[rows.size() - 1] if not rows.is_empty() else _tabs, [])


## Links a row of controls: left and right along it, up and down to the controls at the same place
## in the rows next to it (the last one when a row is shorter).
func _link_row(row: Array, above: Array, below: Array) -> void:
	for i in row.size():
		var control: Control = row[i]
		if not above.is_empty():
			control.focus_neighbor_top = control.get_path_to(above[mini(i, above.size() - 1)])
		if not below.is_empty():
			control.focus_neighbor_bottom = control.get_path_to(below[mini(i, below.size() - 1)])
		# A lone control keeps left and right: a slider or a selector uses them to change its value, a
		# switch must not hand the focus to whatever lies beside it.
		if row.size() > 1 or not (control is UISlider or control is UIOptionSelector):
			control.focus_neighbor_left = control.get_path_to(row[maxi(i - 1, 0)])
			control.focus_neighbor_right = control.get_path_to(row[mini(i + 1, row.size() - 1)])


func _has_focus_in_page(index: int) -> bool:
	if index < 0 or not is_inside_tree():
		return false
	var focused := get_viewport().gui_get_focus_owner()
	return focused != null and _pages[index].is_ancestor_of(focused)


func _on_back() -> void:
	UIRouter.pop()


func _on_reset() -> void:
	var settings := get_node_or_null("/root/Settings") as SettingsService
	if settings != null:
		settings.reset_defaults()


## While a row waits for a press, Esc cancels that and does not leave the screen.
func _on_listening_changed(listening: bool) -> void:
	allow_back = not listening
