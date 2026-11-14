# Using things

<!-- new section: split out of the character page when it reached the size limit (gdstudio #1029) -->

How a 3D Third Person character uses a door, a lever or anything else with its interact button. Part of
[the 3D Third Person template](../third-person-template.md).

## The component {#interactable}

<!-- new section: a door joined a group and the character called `interact` and `interact_point` on it by name; nothing
     said how a lever or a chest becomes usable without a script of its own (gdstudio #925) -->

Anything a character uses with its interact button carries an `Interactable` (`addons/gds_game/interact/`, synced into
every game): an `Area3D` on the Sensors layer (7) with a shape, that makes its parent usable. The character's
`Interactor` (`gameplay/character/interactor.gd`) asks the physics space once per press for the areas on
`interact_mask` (Sensors) inside a cylinder of the tuning's `interact_reach` around it (`reach_height` up and down),
keeps the `Interactable`s that are `enabled`, measures each one's `reach_point()` on the ground plane and takes the
nearest within `half_angle` of where the character faces. `Character.interact()` calls its `interact(self)`, which says
`interacted(by)`; the character says `interacted(target)` with the `Interactable`'s parent and returns it. Nothing
joins a group and nothing is called by a method name, so a lever is a `Node3D` with an `Interactable` child and a
shape, its `interacted` signal connected in the scene to whatever it moves.

- **The inspector, on `Interactable`:** `prompt` ("Use"; the door says "Open"), `enabled` (off: passed over, and
  `interact()` does nothing) and `point` (a node that stays put to measure the reach to, for a parent that moves as it
  is used; empty: the area's own place). Its shape is a child `CollisionShape3D`; with none it warns.
- **On `Interactor`:** `half_angle` (75°), `reach_height` (1.5 m) and `interact_mask` (Sensors). Pickups and trigger
  zones share the layer and are skipped by type; one search looks at 32 areas at most.
- **The door** has an `Interactable` with a 0.5 m sphere at 1 m, its `interacted` connected to `Door.interact()` in
  `door.tscn`; `player_can_use` switches it on and off, and the door keeps it where the closed door stands as the panel
  moves, so an open gate is closed from where it was opened. A door with `player_can_use` on and no `Interactable`
  warns.
- **What it costs:** one shape query per press of the interact button, nothing a frame. An `Area3D` with `monitoring`
  off (it senses nothing) is still found by `PhysicsDirectSpaceState3D.intersect_shape()` with `collide_with_areas`
  on, a physics tick after it enters the tree (Jolt, 4.7; `test_interactable_alone.gd`).
- **Capture:** `tools/capture/components_tour.tscn` (two range targets shot down through their `Health`, one taking
  two shots, then a lever that is a `Node3D` with an `Interactable` and no script, pulled with the button):
  `gds capture frames --project game --scene res://tools/capture/components_tour.tscn --seconds 14`.
- **Tests:** `godot/tests/gds_game/test_interactable_alone.gd` (the signal, off, the fixed point, a query on its layer
  finds it, the warning, the pins); `tests/gameplay/test_hit_and_interact_components.gd` (a `Node3D` with no script
  and an `Interactable` is found and used by a character; a door without one warns and is not found); `test_door.gd`
  (the reach measured from the closed gate).
- **Approach:** When one part must drive another it does not know the class of (a world of networked map parts), have
  the driven part hand its functions over as `Callable`s in its `_ready` (`NetEntity.serve`), never look them up by
  name; a script made from a preloaded constant is typed as it (`var stance: STANCE_SCRIPT = STANCE_SCRIPT.new()`).
  **Watch out for:** `NetWorld` first called `has_method(&"net_place")` and `call(&"net_write", ...)` on each part;
  every suite of the change passed and only the full run's
  `test_no_part_in_gameplay_finds_another_by_a_method_name` named the nine lines. **Seen:** gdstudio #907,
  2026-11-11; gdstudio #1409, 2026-11-13 (the vault asked the hold `has_method(&"free_hand")`; now typed
  `TwoHandHold`); gdstudio #1347, 2026-11-13 (the rifle hold called the stance's `spine_poses` by name).

## Using something with a weapon in the hands {#interact-held}

<!-- new section: the page said how a thing becomes usable and nothing about what the character's hands do while it
     is used; with the rifle held the interact clip showed nothing (gdstudio #1336) -->

`Character.interact()` says `interacted`, and `CharacterAnimation` plays the interact clip (`ual1/Interact`, stretched
to the tuning's `interact_time`, 0.7 s) on the action layer, over the whole body. The clip reaches with the **left**
arm; its right arm hangs still. So whatever is held, the hand that reaches has to be free, and that is the hold's
job, never a list of weapons: each hold owns a `FreeHand` (`gameplay/weapon/hold/free_hand.gd`), starts it on its
character's `interacted` and reads its `amount()` every frame (0 on the weapon, 1 with the clip's arm). A new weapon
that uses either hold frees its hand with no line of its own, and a game frees the hand for another action that
reaches with it (a use animation, a pickup) by calling the hold's `free_hand(seconds)`, and gives it back early with
`take_hand_back()` (`FreeHand.finish()`: the hand returns its own way from where it is). Using a bandage does both
([A use that takes time](../inventory.md#hotbar)).

- **The amount has two halves**, so a hand never goes straight from the weapon to the clip's arm. Up to
  `FreeHand.LET_GO` (0.5) the hand is still the hold's: its fingers open and it comes off the weapon along the hold's
  own clear way (`FreeHand.off()`); past it the hold's arm fades and the clip's arm takes the opened hand
  (`gone()`), and the fingers go to the clip's own last (`relaxed()`, from 0.75). Coming back is the same way
  backwards, ending as the action ends. It is cosmetic: worked out on each machine from the time since `interacted`,
  never sent.
- **The rifle** (`TwoHandHold`, Free hand group). The left hand comes off the hand guard by the reload's own first
  steps (knuckles open, 6 mm down, then down and out to `reload_clearance`), goes on out to `free_clearance` (10 cm
  down and 14 cm to the left of its place), and from there the clip's arm has it; `free_release_time` 0.16 s,
  `free_return_time` 0.26 s. Meanwhile the right hand alone takes the gun down to `free_pitch` (50 degrees) and
  `free_yaw` (0), the butt still in the shoulder's pocket, an aim is dropped to the low ready, the chest's turn
  toward the hand guard is eased off (`chest_weight()`), and the left collarbone's reach with it. A reload keeps the
  hand: the magazine is in it, so `free_hand()` does nothing while one runs and a reload that starts ends it.
- **The pistol** (`WeaponHold`, `free_release_time`, `free_return_time`, `free_weight` for a figure posed by hand). An
  interact locks the action, which takes the aim down for its time, so the left hand already left along its way as
  the aim fell, and the reach showed. The hold takes the lesser of the aim and the free hand, so an interact looks
  as it did, and an action that leaves the aim up still lets the hand go.
- **One hold at a time.** `WeaponHold` is on every character and reads the weapon layer's weights
  (`pistol_weights()`), which the rifle's own clips weigh too (gdstudio #1082). It takes them only while the weapon
  in the hands is the one on its seat (`_holds_it()`: the definition's `view` is the seat, or it has none); with the
  rifle held its grip and left arm are off, so no second arm solve runs under the rifle's.
- **Empty hands** have no hold and the clip plays as it is.
- **Measured** (`tests/gameplay/test_interact_held.gd`). Before, with the rifle, the left hand was 294 mm from where
  the clip puts it; now it is within 15 mm of the empty-handed reach on every update from 0.18 s to 0.42 s, with
  every `WeaponDef` of `gameplay/weapon/` and a copy of the rifle under a name no list has, at rest and aiming. The
  right hand stays on its place on the rifle (under 5 mm) and within the hold's limits (2 mm in, a holding part 5 mm
  off) on every update; the left passes at most 1.2 mm (female) and 1.7 mm (male) through the rifle on its way off
  and back, posed at every tick on both bodies, and 1.2 mm live; the rifle stays under 10 mm in the torso and the
  left arm out of it.
- **Left as it was:** as the aimed pistol's arm goes down and comes up, the pistol is out of the left arm's reach
  for about nine updates each way (40 to 200 mm), and the hand, turned as on the gun, overlaps it; that is the aim's
  own blend (gdstudio #1078), as is the upper body's twist in it (#1318). The tests leave those updates out by the
  arm's `support_shortfall()` and count them.
- **Capture:** `tools/capture/interact_held_tour.tscn` (a lever used with the pistol carried and aimed, then with
  the rifle at the low ready and aimed; the game camera, or `INTERACT_VIEW=front|left|top` for a close-up, and
  `INTERACT_BODY=male` for the other body).

- **Approach:** When a clip shows nothing with a weapon held, look past the tree at the skeleton's modifiers: read
  the bone in `skeleton_updated` against the same clip with empty hands. Give the hold itself the rule that frees a
  hand (a share it reads each frame), and take the hand off by the hold's own clear way before the clip's arm gets
  it. **Watch out for:** the action layer played the interact clip at full weight and `is_acting()` was true, while
  the rifle's two `HoldArm`s, at influence 1, put both arms back on the gun; a straight fade of the arm's influence
  from the hand guard took the fingers 32 mm through the rifle, and so did the hold's chest turn, which swings the
  clip's reaching arm across the gun (ease it off with the hand). **Seen:** gdstudio #1336, 2026-11-12
  (`test_interact_held.gd`).
- **Approach:** Free a held weapon's hand for every action whose clip uses that hand, not only for the one it was built
  for: a vault calls the view's `free_hand(seconds)` as it starts (`VaultAnimation._free_hands()`, the view typed as its
  hold, never found by a method name), and a weapon hidden for the action (a high vault's `puts_weapon_away`) lets both
  arms go by the same amount and keeps its free running while hidden (only a switch, with the arms' reach down to 0,
  stops it). **Watch out for:** the vault turned off only the pistol's layer (`VaultAnimation.hands`), so with the rifle
  the low vault's left wrist stayed 0.3 m over the top on the hand guard and, with the rifle hidden for the high vault,
  both arms still went to where it would be (the left 0.3 m off); the hold also stopped any free once hidden. **Seen:**
  gdstudio #1409, 2026-11-13 (`test_vault_rifle.gd`).
- **Approach:** A hold weighs its modifiers by a shared layer's weights only while its own weapon is in the hands,
  and a test lists every skeleton modifier with its `active` and `influence` on the update that looks wrong.
  **Watch out for:** once the rifle had grip and aim clips, the pistol's hold ran its grip and its left arm with the
  rifle aimed; the rifle's arms, later in the order at influence 1, hid it, until the rifle's left arm faded for an
  interact and the hand went 24 cm across to the pistol's place by the right hand (16 mm through the rifle, the
  forearm 31 mm in the torso, two updates). Both changes were green alone; only the suite run on the merge showed it.
  **Seen:** gdstudio #1336 merged with #1267, 2026-11-12 (`test_the_pistols_hold_leaves_the_rifle_to_its_own_hold`).
- **Approach:** Pose a staged test of an action the way the action layer blends it (the pose under it, the clip over
  it by the layer's fade in and out), and measure a live one on every update. **Watch out for:** the interact clip
  posed whole from its first tick put the aimed pistol at the thigh with the left hand still reaching for it; and a
  live reader that measured every third update never saw the two updates in which the aimed pistol leaves the left
  arm's reach, nor that a `HoldArm` keeps its last `shortfall` once it is switched off (read it only while the
  hold's weight is above zero). **Seen:** gdstudio #1336, 2026-11-12.
