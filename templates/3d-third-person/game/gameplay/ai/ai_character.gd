@tool
class_name AiCharacter
extends Character
## The base every AI character is made from (an enemy, a friendly, a civilian): the template's
## `Character` (its body, `Model` slot, animation, `Health` and ragdoll, as the player has them)
## driven by an `AiController` instead of the keys, and managed by the level's `AiDirector`.
##
## The director steps the body (the character's own physics processing is off while it is
## registered), runs its think at the profile's rate on a phase of its own, and gives it its
## `tier` (how near a player it is) and the shared `budget`; a character with no director in the
## tree steps itself and never thinks. A hit comes through `Health` like the player's, and a death
## goes into the same ragdoll.
##
## The parts that decide come as child nodes in the slots below, each found by its export: the
## senses, the navigator and the task runner. A think runs them in that order; with none, the
## character stands, takes hits, dies and is counted. `profile` is the only thing that makes one
## kind differ from another.

## The situation changed (`AiSituation.Situation`), with the one before.
signal situation_changed(situation: int, previous: int)
## The director moved the character to another tier (`AiDirector.Tier`).
signal tier_changed(tier: int)
## A think ran, `seconds` after the one before: the hook for a game's own logic.
signal thought(seconds: float)

## The group every AI character joins, which the director reads at its start.
const GROUP := &"ai_characters"

@export_group("AI")
## What kind of character it is: every number its senses, decisions and budget read, applied
## live. Empty: the defaults of `AiProfile`.
@export var profile: AiProfile:
	set(value):
		profile = value
		_show_debug()
## Shows the situation, the tier and the profile's name above the head. Off by default; it costs
## nothing while off.
@export var debug := false:
	set(value):
		debug = value
		_show_debug()
## The label the debug overlay writes (a `Label3D` of `ai_character.tscn`).
@export var debug_label: Label3D

@export_group("Slots")
## What it perceives with (sight, hearing, memory). Empty: it notices nothing.
@export var senses: Node
## How it gets somewhere (the path and the steering), writing the controller's movement channel.
@export var navigator: Node
## What it is doing (the task layers), deciding what the navigator and the action channel do.
@export var task_runner: Node

## How near a player it is (`AiDirector.Tier`), set by the director; Full without one.
var tier := 0
## The work all characters of the director share in a physics tick; null without a director.
var budget: AiBudget
## The director that manages it; null when it steps itself.
var director: AiDirector
## What it believes is going on.
var situation := AiSituation.new()
## How many thinks it has run.
var think_count := 0


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	if profile == null:
		profile = AiProfile.new()
	add_to_group(GROUP)
	situation.configure(profile)
	situation.changed.connect(_on_situation_changed)
	died.connect(situation.die)
	revived.connect(situation.revive)
	var found := AiDirector.find(get_tree())
	if found != null:
		found.register(self)
	_show_debug()


func _exit_tree() -> void:
	if director != null:
		director.unregister(self)


# With no director, the body steps itself: the navigator writes the controller first.
func _physics_process(delta: float) -> void:
	if not Engine.is_editor_hint():
		before_step(delta)
	super(delta)


## Called before every step of the body, `seconds` after the last (the director's missed ticks
## included): the navigator writes the controller's movement channel for the step.
func before_step(seconds: float) -> void:
	if navigator is AiNavigator:
		(navigator as AiNavigator).navigate(seconds)


## The controller the parts write to (`AiController`), or null when another kind drives it.
func ai_controller() -> AiController:
	return controller as AiController


## One think, called by the director at the profile's rate for the tier, `seconds` after the last
## one: the situation's clock moves, then the parts in the slots decide.
func think(seconds: float) -> void:
	think_count += 1
	situation.configure(profile)
	situation.advance(seconds)
	thought.emit(seconds)
	if debug:
		_show_debug()


## Called by the director when the tier changes.
func set_tier(value: int) -> void:
	if value == tier:
		return
	tier = value
	tier_changed.emit(tier)
	_show_debug()


func _on_situation_changed(now: AiSituation.Situation, previous: AiSituation.Situation) -> void:
	situation_changed.emit(now, previous)
	_show_debug()


func _show_debug() -> void:
	if debug_label == null:
		return
	debug_label.visible = debug
	if not debug:
		return
	var kind := profile.display_name if profile != null else "AI"
	debug_label.text = (
		"%s\n%s · %s" % [kind, AiSituation.name_of(situation.current), AiDirector.TIER_NAMES[tier]]
	)
