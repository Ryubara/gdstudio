class_name CharacterClips
extends RefCounted
## The names of every clip the character can play: the Universal Animation Library 1 and 2
## (Quaternius, CC0), added to the player's `AnimationPlayer` as the libraries `ual1` and
## `ual2`, so a clip is `ual1/Idle`, the template's own prone and crawl clips (gdstudio
## #1009, `assets/animation/prone/`), the library `prone`, with its prone aim clips (gdstudio
## #1111), the library `prone_aim`, its prone reload (gdstudio #1185), the library
## `prone_reload`, its own melee blows (gdstudio #1254, `assets/animation/melee/`), the library
## `melee`, its own rifle clips (gdstudio #1082, `assets/animation/rifle/`), the library `rifle`,
## and GDStudio's own clips that replace
## the library's one clip type at a time (gdstudio #1154, `assets/animation/own/`), the library
## `gds`. The looping clips lose their `_Loop` suffix on import (`Idle_Loop` is `Idle`) and loop.
## The library `fixed` holds the few library clips that put a limb through another on the
## template's bodies, with that limb swung clear (gdstudio #1295 and #1320,
## `assets/animation/fixed/`).
##
## When a clip of our own or a fixed clip replaces a library clip its constant moves (`IDLE` is
## `gds/Idle`, `LAND` is `fixed/Jump_Land`) and `STAND_INS` names the library clip it replaced,
## which stays in the game: set a clip export of `CharacterAnimation` to
## `CharacterClips.stand_in(CharacterClips.IDLE)` to play it again.
##
## `CharacterAnimation` plays the ones a state needs; any other clip is one call away:
## `player_animation.play_clip(CharacterClips.SWORD_ATTACK)`. The constants below are the clips
## the template uses or suggests; `ALL` lists every one, and a test checks that each name
## resolves.

const LIBRARY_ONE := &"ual1"
const LIBRARY_TWO := &"ual2"
const LIBRARY_PRONE := &"prone"
const LIBRARY_PRONE_AIM := &"prone_aim"
const LIBRARY_PRONE_RELOAD := &"prone_reload"
const LIBRARY_OWN := &"gds"
const LIBRARY_VAULT := &"vault"
const LIBRARY_RIFLE := &"rifle"
const LIBRARY_FIXED := &"fixed"
const LIBRARY_MELEE := &"melee"

# Locomotion and the clips the player's states use.
const IDLE := &"gds/Idle"
const WALK := &"ual1/Walk"
const RUN := &"ual1/Jog_Fwd"
const SPRINT := &"ual1/Sprint"
const JUMP_START := &"ual1/Jump_Start"
const AIR := &"ual1/Jump"
# The library's landing with the left arm swung clear of the shin (gdstudio #1295,
# `assets/animation/fixed/`); `STAND_INS` names the library's own.
const LAND := &"fixed/Jump_Land"
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
const KNOCKBACK := &"ual2/Hit_Knockback"
const SLIDE := &"ual2/Slide"
const SLIDE_START := &"ual2/Slide_Start"
# The library's clip with the right arm swung clear of the shin (gdstudio #1295).
const SLIDE_EXIT := &"fixed/Slide_Exit"
const CARRY_WALK := &"ual2/Walk_Carry"
const THROW := &"ual2/OverhandThrow"
# Lying down and crawling: the template's own clips.
const PRONE_IDLE := &"prone/Prone_Idle"
const CRAWL := &"prone/Crawl_Fwd"
const TO_PRONE := &"prone/Crouch_To_Prone"
const TO_CROUCH := &"prone/Prone_To_Crouch"
const PRONE_AIM := &"prone_aim/Prone_Aim_Neutral"
const PRONE_AIM_UP := &"prone_aim/Prone_Aim_Up"
const PRONE_AIM_DOWN := &"prone_aim/Prone_Aim_Down"
const PRONE_RELOAD := &"prone_reload/Prone_Reload_Pistol"
# Vaulting: the template's own clips (gdstudio #1010, `assets/animation/vault/`), the library
# `vault`. What each was keyed on is a `VaultClip` (`gameplay/character/vault_low.tres`,
# `vault_high.tres`).
const VAULT_LOW := &"vault/Vault_Low"
const VAULT_HIGH := &"vault/Vault_High"
const VAULT_LAND := &"vault/Vault_Land"
# Melee blows: the template's own clips, three per weapon category (`WeaponCategory.melee_clips`).
const MELEE_UNARMED_JAB := &"melee/Melee_Unarmed_Jab"
const MELEE_UNARMED_CROSS := &"melee/Melee_Unarmed_Cross"
const MELEE_UNARMED_HOOK := &"melee/Melee_Unarmed_Hook"
const MELEE_PISTOL_WHIP := &"melee/Melee_Pistol_Whip"
const MELEE_PISTOL_BACKHAND := &"melee/Melee_Pistol_Backhand"
const MELEE_PISTOL_JAB := &"melee/Melee_Pistol_Jab"

## The library clip each clip of our own replaced, kept as a stand-in, and the library clip
## each fixed clip was made from: the same clip, as Quaternius keyed it. A game whose bodies it
## suits puts it back in the inspector (`CharacterAnimation.land_clip`).
const STAND_INS: Dictionary[StringName, StringName] = {
	&"gds/Idle": &"ual1/Idle",
	&"fixed/Jump_Land": &"ual1/Jump_Land",
	&"fixed/NinjaJump_Land": &"ual2/NinjaJump_Land",
	&"fixed/Slide_Exit": &"ual2/Slide_Exit",
	&"fixed/Sword_Dash": &"ual2/Sword_Dash",
	&"fixed/Sword_Heavy_Combo": &"ual2/Sword_Heavy_Combo",
}

# The rifle, held in both hands: the template's own clips.
const RIFLE_IDLE := &"rifle/Rifle_Idle"
const RIFLE_AIM := &"rifle/Rifle_Aim_Neutral"
const RIFLE_AIM_UP := &"rifle/Rifle_Aim_Up"
const RIFLE_AIM_DOWN := &"rifle/Rifle_Aim_Down"
const RIFLE_SHOOT := &"rifle/Rifle_Shoot"
const RIFLE_RELOAD := &"rifle/Rifle_Reload"

## Every clip of the ten libraries, with its library.
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
	&"prone_aim/Prone_Aim_Down",
	&"prone_aim/Prone_Aim_Neutral",
	&"prone_aim/Prone_Aim_Up",
	&"prone_reload/Prone_Reload_Pistol",
	&"gds/Idle",
	&"vault/Vault_High",
	&"vault/Vault_Land",
	&"vault/Vault_Low",
	&"rifle/Rifle_Aim_Down",
	&"rifle/Rifle_Aim_Neutral",
	&"rifle/Rifle_Aim_Up",
	&"rifle/Rifle_Idle",
	&"rifle/Rifle_Reload",
	&"rifle/Rifle_Shoot",
	&"fixed/Jump_Land",
	&"fixed/NinjaJump_Land",
	&"fixed/Slide_Exit",
	&"fixed/Sword_Dash",
	&"fixed/Sword_Heavy_Combo",
	&"melee/Melee_Pistol_Backhand",
	&"melee/Melee_Pistol_Jab",
	&"melee/Melee_Pistol_Whip",
	&"melee/Melee_Unarmed_Cross",
	&"melee/Melee_Unarmed_Hook",
	&"melee/Melee_Unarmed_Jab",
]


## The library clip a clip of our own replaced, or the clip itself when it replaced none.
static func stand_in(clip: StringName) -> StringName:
	return STAND_INS.get(clip, clip)
