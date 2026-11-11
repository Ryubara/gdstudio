class_name PlayerRig
extends Node
## Everything one local player brings into a map: the body (`Player`), the camera that follows it
## (`PlayerCamera` with its Phantom Camera, the `Camera3D` and its host), the look options, the
## touch layer and the pause button. A second local or networked player is a second instance of
## this scene; the rest of the game (the world, the HUD, the screen host) is not repeated.
##
## The scene wires its own parts. What reaches outside is wired by the scene that instances it:
## the HUD reads the `player`, and the screen host's `opened` and `closed` call the touch layer's
## `suspend` and `resume`.
##
## On the web, a page opened with `?probe` gets a `WebProbe` here at run time (and one opened with
## `?netprobe` a `NetProbe`, one opened with `?netplay` a `NetPlayProbe`, and `?steptrace` a
## `StepTraceProbe`), so no scene ships a probe node.

@export_group("Nodes")
## The body the rig follows.
@export var player: Player
## The camera rig that follows `player`.
@export var camera_rig: PlayerCamera
## The touch layer.
@export var touch: TouchControls


func _ready() -> void:
	if not Engine.is_editor_hint():
		WebProbe.attach(self, player, camera_rig, touch)
		NetProbe.attach(self)
		NetPlayProbe.attach(self, player)
		StepTraceProbe.attach(self)
