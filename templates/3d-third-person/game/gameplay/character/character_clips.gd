class_name CharacterClips
extends RefCounted
## The names of every clip the character can play: the Universal Animation Library 1 and 2
## (Quaternius, CC0), added to the player's `AnimationPlayer` as the libraries `ual1` and
## `ual2`, so a clip is `ual1/Idle`, the template's own prone and crawl clips (gdstudio
## #1009, `assets/animation/prone/`), the library `prone`, and GDStudio's own clips that replace
## the library's one clip type at a time (gdstudio #1154, `assets/animation/own/`), the library
## `gds`. The looping clips lose their `_Loop` suffix on import (`Idle_Loop` is `Idle`) and loop.
##
## When a clip of our own replaces a library clip its constant moves (`IDLE` is `gds/Idle`) and
## `STAND_INS` names the library clip it replaced, which stays in the game: set a clip export
## of `CharacterAnimation` to `CharacterClips.stand_in(CharacterClips.IDLE)` to play it again.
##
## `CharacterAnimation` plays the ones a state needs; any other clip is one call away:
## `player_animation.play_clip(CharacterClips.SWORD_ATTACK)`. The constants below are the clips
## the template uses or suggests; `ALL` lists every one, and a test checks that each name
## resolves.

const LIBRARY_ONE := &"ual1"
const LIBRARY_TWO := &"ual2"
const LIBRARY_PRONE := &"prone"
const LIBRARY_OWN := &"gds"

# Locomotion and the clips the player's states use.
const IDLE := &"gds/Idle"
const WALK := &"ual1/Walk"
const RUN := &"ual1/Jog_Fwd"
const SPRINT := &"ual1/Sprint"
const JUMP_START := &"ual1/Jump_Start"
const AIR := &"ual1/Jump"
const LAND := &"ual1/Jump_Land"
const PUSH := &"ual1/Push"
const INTERACT := &"ual1/Interact"
const HIT := &"ual1/Hit_Chest"

# Other clips a game reaches for first (the rest are in `ALL`).
const DEATH := &"ual1/Death01"
const ROLL := &"ual1/Roll"
const CROUCH_IDLE := &"ual1/Crouch_Idle"
const CROUCH_WALK := &"ual1/Crouch_Fwd"
const PISTOL_IDLE := &"ual1/Pistol_Idle"
const PISTOL_AIM := &"ual1/Pistol_Aim_Neutral"
const PISTOL_AIM_UP := &"ual1/Pistol_Aim_Up"
const PISTOL_AIM_DOWN := &"ual1/Pistol_Aim_Down"
const PISTOL_SHOOT := &"ual1/Pistol_Shoot"
const PISTOL_RELOAD := &"ual1/Pistol_Reload"
const PICK_UP := &"ual1/PickUp_Table"
const PUNCH := &"ual1/Punch_Cross"
const SWORD_ATTACK := &"ual1/Sword_Attack"
const SWIM := &"ual1/Swim_Fwd"
const DANCE := &"ual1/Dance"
const OPEN_CHEST := &"ual2/Chest_Open"
const CLIMB_UP := &"ual2/ClimbUp_1m"
## Stands in for the vault until the template's own vault clips land (kit #1010): a jump take-off
## that tucks the legs, played warped to the vault's time.
const VAULT_PLACEHOLDER := &"ual2/NinjaJump_Start"
const KNOCKBACK := &"ual2/Hit_Knockback"
const SLIDE := &"ual2/Slide"
const SLIDE_START := &"ual2/Slide_Start"
const SLIDE_EXIT := &"ual2/Slide_Exit"
const CARRY_WALK := &"ual2/Walk_Carry"
const THROW := &"ual2/OverhandThrow"
# Lying down and crawling: the template's own clips.
const PRONE_IDLE := &"prone/Prone_Idle"
const CRAWL := &"prone/Crawl_Fwd"
const TO_PRONE := &"prone/Crouch_To_Prone"
const TO_CROUCH := &"prone/Prone_To_Crouch"

## The library clip each clip of our own replaced, kept as a stand-in.
const STAND_INS: Dictionary[StringName, StringName] = {
	&"gds/Idle": &"ual1/Idle",
}

## Every clip of the four libraries, with its library.
const ALL: Array[StringName] = [
	&"ual1/A_TPose",
	&"ual1/Crouch_Fwd",
	&"ual1/Crouch_Idle",
	&"ual1/Dance",
	&"ual1/Death01",
	&"ual1/Driving",
	&"ual1/Fixing_Kneeling",
	&"ual1/Hit_Chest",
	&"ual1/Hit_Head",
	&"ual1/Idle",
	&"ual1/Idle_Talking",
	&"ual1/Idle_Torch",
	&"ual1/Interact",
	&"ual1/Jog_Fwd",
	&"ual1/Jump",
	&"ual1/Jump_Land",
	&"ual1/Jump_Start",
	&"ual1/PickUp_Table",
	&"ual1/Pistol_Aim_Down",
	&"ual1/Pistol_Aim_Neutral",
	&"ual1/Pistol_Aim_Up",
	&"ual1/Pistol_Idle",
	&"ual1/Pistol_Reload",
	&"ual1/Pistol_Shoot",
	&"ual1/Punch_Cross",
	&"ual1/Punch_Jab",
	&"ual1/Push",
	&"ual1/Roll",
	&"ual1/Sitting_Enter",
	&"ual1/Sitting_Exit",
	&"ual1/Sitting_Idle",
	&"ual1/Sitting_Talking",
	&"ual1/Spell_Simple_Enter",
	&"ual1/Spell_Simple_Exit",
	&"ual1/Spell_Simple_Idle",
	&"ual1/Spell_Simple_Shoot",
	&"ual1/Sprint",
	&"ual1/Swim_Fwd",
	&"ual1/Swim_Idle",
	&"ual1/Sword_Attack",
	&"ual1/Sword_Idle",
	&"ual1/Walk",
	&"ual1/Walk_Formal",
	&"ual2/A_TPose",
	&"ual2/Chest_Open",
	&"ual2/ClimbUp_1m",
	&"ual2/Consume",
	&"ual2/Farm_Harvest",
	&"ual2/Farm_PlantSeed",
	&"ual2/Farm_Watering",
	&"ual2/Hit_Knockback",
	&"ual2/Idle_FoldArms",
	&"ual2/Idle_Lantern",
	&"ual2/Idle_No",
	&"ual2/Idle_Rail",
	&"ual2/Idle_Rail_Call",
	&"ual2/Idle_Shield",
	&"ual2/Idle_Shield_Break",
	&"ual2/Idle_TalkingPhone",
	&"ual2/LayToIdle",
	&"ual2/Melee_Hook",
	&"ual2/Melee_Hook_Rec",
	&"ual2/NinjaJump_Idle",
	&"ual2/NinjaJump_Land",
	&"ual2/NinjaJump_Start",
	&"ual2/OverhandThrow",
	&"ual2/Shield_Dash",
	&"ual2/Shield_OneShot",
	&"ual2/Slide",
	&"ual2/Slide_Exit",
	&"ual2/Slide_Start",
	&"ual2/Sword_Block",
	&"ual2/Sword_Dash",
	&"ual2/Sword_Heavy_Combo",
	&"ual2/Sword_Regular_A",
	&"ual2/Sword_Regular_A_Rec",
	&"ual2/Sword_Regular_B",
	&"ual2/Sword_Regular_B_Rec",
	&"ual2/Sword_Regular_C",
	&"ual2/Sword_Regular_Combo",
	&"ual2/TreeChopping",
	&"ual2/Walk_Carry",
	&"ual2/Yes",
	&"ual2/Zombie_Idle",
	&"ual2/Zombie_Scratch",
	&"ual2/Zombie_Walk_Fwd",
	&"prone/Crawl_Fwd",
	&"prone/Crouch_To_Prone",
	&"prone/Prone_Idle",
	&"prone/Prone_To_Crouch",
	&"gds/Idle",
]


## The library clip a clip of our own replaced, or the clip itself when it replaced none.
static func stand_in(clip: StringName) -> StringName:
	return STAND_INS.get(clip, clip)
