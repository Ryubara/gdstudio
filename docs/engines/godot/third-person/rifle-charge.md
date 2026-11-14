# The rifle's charging handle

<!-- new section: weapon-pickups.md reached its size limit with the rifle's reload; the charging handle's pull is
     its own step of the hold, with its own solve and captures (gdstudio #1266) -->

How the 3D Third Person rifle's left hand pulls the charging handle at the end of a reload. Part of
[the rifle in both hands](weapon-pickups.md#rifle-hands), whose reload brings the hand to the seated magazine first.

## The pull after the magazine {#rifle-charge}

- **The way** (kit #1266, `gameplay/weapon/hold/charge_pull.gd`, the hold's `charge`). After the new
  magazine is seated the left hand comes off it the way it came on with its fingers opening as one
  (`leave`, 0.63 to 0.69 of the reload), goes up the rifle's left side to 8 cm left of the handle (`reach`, to
  0.77), comes onto the `ChargeHand` marker as its fingers close on the latch (`grip`, to 0.80: the
  `HandPoseModifier`'s `third` pose, the hold's `charge_pose`), pulls the `Bolt` node back its `travel` of 6 cm
  (`pull`, to 0.86, the bolt's sound, moved there from 0.88), lets go out to the left while the bolt runs home in
  `slam` (`release`, to 0.88), goes forward beside the magazine and under the hand guard by `reload_return.x`
  (0.94) and onto it by 0.98, the hold's own last leg, its fingers following the hold's own way back from where
  they are open. The far level's `Bolt` moves with the near one (both a `ChargeBolt`), and a reload cut off puts
  the bolt home. A hold with no `charge`, `ChargeHand` or `charge_pose` keeps the straight way back.
- **How the handle is held.** The model's latch was a 1.4 cm bar within the stock's width with its rear face on
  the stock's front, so no finger fitted in front of it and a pull ran it into the stock: `build_rifle.py` now
  runs the handle 5 mm higher (`BOLT_Z`, 1 mm over the stock's top) and gives the latch an extended left side, the
  bar 2.2 cm past the stock and a tab dropping beside it (3.2 cm tall, 3 mm clear of the stock). The hand is left
  of the stock with the palm toward the shooter, the index finger hooked round the bar's front and the middle
  finger round the tab's, the ring and little fingers curled clear and the thumb bent in, tilted 25 degrees
  (fingers up, toward the forearm from the low elbow). `solve_rifle_hold.py` solves it on each body (`charge`)
  against the `Bolt` part for the touch and against the rest of the rifle at three shares of the pull, so the
  hand riding the handle stays off the stock; `write_hold.gd` writes `ChargeHand` and `rifle_charge_pose.tres`,
  or the male's `charge_hand` and `charge_pose` in his fit. While it holds (0.80 to 0.86, every half hundredth,
  against the rifle with the bolt where it is): female 0.8 to 0.9 mm in and the fingertips 0.9 mm off at most,
  male 1.1 mm in and 3.1 mm off; on the way the hand passes 1.2 mm (female) and 5.1 mm (male) through the rifle
  at most. Captures: `tools/capture/rifle_charge_closeups.tscn` (from the rifle's left, above, the front and
  left, and the player's camera, at the reach, the grip, the pull's end and the release, both bodies).

- **Approach:** Give a hooking finger a bend in the solver's cost, not only a touch, and look at the hand from
  the weapon's side before the numbers. **Watch out for:** with only the tips held on the latch the solver laid
  the index and middle fingers straight across its front, and the close-up read as a hand poking the handle
  with a thumb standing out like a spike, though every contact passed. **Seen:** gdstudio #1266, 2026-11-12
  (fix: `hook` and `thumb_rest` cost a straight joint).
- **Approach:** Put the place a hand ships at in the solver's `MOVES` for each body, so a solve with no option
  writes the shipped numbers again, and check it by solving once with no option and comparing with the files.
  **Watch out for:** a place found with `--charge=` and left out of `MOVES` is lost at the next merge: a fit
  file the solver writes is taken from main and solved again, and the plain solve put the charge hand 25 degrees
  off and 7 cm from where it shipped. **Seen:** gdstudio #1370, 2026-11-12 (the charge's 25-degree tilt moved
  into `MOVES` for every body; both bodies' solves then matched the shipped files exactly).
- **Approach:** Route a hand's way between two places on opposite ends of a long gun through a place beside it
  (the magazine's `beside`), and measure the way every half hundredth against the gun as it is then (the bolt
  back or home). **Watch out for:** the straight way from the handle's let-go to under the hand guard went 13 to
  29 mm through the receiver's left side, and the thumb 13.6 mm through the hand guard until the fingers' share
  of the hold's way matched the places the hand passed (`to_magazine` at `_WAY_BESIDE` beside the magazine).
  **Seen:** gdstudio #1266, 2026-11-12 (`home_beside`).
- **Approach:** When main moves a hold's finger weights behind a cache (`HoldWeights.hands()`, kit #1391), give
  a step of your own its weights through that call (`ChargePull.finger_weights()` returns the hold's own with its
  share over them), never by writing the modifier beside it; and count the merged script's lines against
  `gdlint`'s 1000 before the merge commit. **Watch out for:** a pull that set `second_weight`, `open_weight` and
  `open_together` itself left the cache believing its last values, so the fingers would have stayed as the pull
  left them after it; and both sides together made `two_hand_hold.gd` 1024 lines (the bolt nodes went to
  `hold/charge_bolt.gd`). **Seen:** gdstudio #1370, 2026-11-13 (merge of main after #1391).
