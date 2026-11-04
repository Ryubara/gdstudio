# Menu and interface sounds

What makes a good match between an interface component and its sound, for any GDStudio game. A game writes its own
table from this page (Deadnight's is in its `docs/research/menu-sfx.md`). Written for Deadnight #894; the sources are
listed at the end with how far each can be trusted.

## 1. Which component takes a sound

Sound is feedback, and feedback should match the weight of what happened (Apple's feedback guideline says the same of
every channel: match the significance of the information to the way it is delivered). So a component gets a sound
when something **changes or commits**, and stays silent when nothing did.

| Event | Sound? | Why |
| --- | --- | --- |
| Pointer enters / focus moves onto a control | Yes, the quietest sound in the game | It confirms "I am on this", and is the one most heard. Hover and focus are one sound, never two (a hovering menu moves the focus) |
| Press of an ordinary button | Yes, short | The click is the touch of the thing |
| Press of the primary or committing button (start, buy, save, join) | Yes, heavier and richer than a press | It is the one moment the player decides; rare, so it can afford weight |
| Back, cancel, close | Yes, the press's pair, lower and shorter | Pairs teach the rules: up is forward, down is back |
| Tab or page switch | Yes, a movement sound (it is a motion) | Sound goes with motion: "if it moves, it makes a sound" |
| Screen push / pop, panel open / close | Yes, a whoosh sized to the motion | Only one per transition; the control that caused it stays at its press |
| Toggle on / off | Yes, a pair at two pitches | The pitch says the new state, so the sound carries information, not decoration |
| Slider or stepper step | Yes, a tick **per step crossed**, rate-limited | Never per frame; pitch can follow the value |
| Choice from a set (colour, option, card) | Yes, a select, lighter than a press | |
| Refused action, disabled control, placeholder | Yes, a short dull "no" | Errors need their own sound, lower and duller than any confirm |
| Reward, unlock, purchase, countdown, ready | Yes, a short motif, the richest sounds in the set | Rare moments are where character goes |
| Text typing, scrolling, dragging a view, a list that refreshes | **No** | Continuous or automatic events are noise; the text field's own focus sound is enough |
| Something the system did, not the player (a timer redraw, a poll) | **No** | The player did not act |
| Hover on a **touch** screen | **No** | A finger has no hover; the tap is the press (see 5) |
| Disabled control hovered | **No**, or the quietest hint | |

Sound never carries essential information alone (Material, Apple, Xbox guidelines all say this): every sound above has
a visible change beside it, and a player with the interface sound turned off loses nothing but character.

## 2. Weight: a sound matches its component

A ladder of weights, each about 4 to 6 dB louder and longer than the one below (Material's sound hierarchy ranks
brand/hero moments over alerts over primary and secondary cues, so the same kind of event is always at the same rank):

| Rank | Examples | Length | Character | Level (peak, under the loudest sound of the game) |
| --- | --- | --- | --- | --- |
| 1 hint | hover, focus, slider tick | 20 to 70 ms | one soft transient, mostly under 4 kHz | 18 to 24 dB under |
| 2 move | tab, select, toggle, step | 60 to 160 ms | a soft mechanism, a pitch that means something | 14 to 18 dB under |
| 3 press | ordinary button, back | 80 to 200 ms | a clear click with a short body | 10 to 14 dB under |
| 4 commit | the primary button, join, start | 150 to 450 ms | the press plus a second layer that resolves | 6 to 10 dB under |
| 5 moment | unlock, purchase, ready, deny with weight | 0.3 to 1.5 s | a motif | 6 to 12 dB under, and rare |

- **Duration:** micro-interactions are typically 100 to 300 ms; a hover is shorter. A sound longer than the animation
  it goes with is heard as lag.
- **Frequency content:** the commit sounds live low (200 to 500 Hz body), clarity in 1 to 5 kHz, alerts above 8 kHz;
  practitioners advise little above 1.5 to 3 kHz in a menu, because ear fatigue comes from repeated bright transients.
  Phone speakers lose the lows (the loss is large near 300 Hz and under, and the true cutoff varies by device), so a
  "thump" needs harmonics in the mids to be heard there.
- **Reuse:** one asset may serve many actions with a different pitch or layer; consistent families teach faster than
  many unrelated sounds (Audiokinetic, on reuse).

## 3. Repetition: the hundredth press

The test: **every sound a player hears every few seconds must still be pleasant at the hundredth time.**

- **Variants:** three to five files for a sound heard often, never the same file twice in a row, with a small random
  pitch (about +-0.3 to +-1 semitone; guides quote up to +-2) and level (+-1 to 2 dB). Engines have this built in
  (Godot's `AudioStreamRandomizer` has a "random, no repeats" mode).
- **Hover spam:** drag the pointer over a column of ten rows in half a second: ten hints are a machine gun. Cap them
  with a **minimum gap** (50 to 80 ms), **one voice** for the hint group, and **hover and focus as one sound**. The cap
  is a number in a test, not a feel.
- **Sliders:** one tick when the value crosses a step, with a minimum gap (MRTK's `SliderSounds` has
  `MinSecondsBetweenTicks`), never from a per-frame callback (one forum report: the restarted sound becomes a buzz of
  its first milliseconds at 60 a second; another: a tick that goes on after the pointer stops). A fast drag over 20
  steps makes 6 to 8 ticks, not 20.
- **Voices:** a `ui` group of 3 to 4 voices so a press is never lost to a tick; a press outranks a hint.

## 4. Level, the bus and the mix

- **A UI bus of its own** with its own volume in the settings (Xbox Accessibility Guideline 105 asks for independent
  controls per kind of audio; its own example is *Grounded*, with master, effects, music, UI, dialogue and voice-chat
  sliders). A player who finds the clicks tiring turns them down without losing the night.
- **Interface sounds sit under gameplay sounds.** Frequent micro sounds are quieter than confirms and errors, which are
  quieter than the game's loud events; a menu sound is never the loudest thing a player has heard from the game.
  Material says frequent sounds should rank below notifications and rare celebrations.
- **Numbers.** There is no standard for interface sounds. Platform and streaming levels are for whole mixes: AES
  TD1004 suggests -16 to -20 LUFS for streamed audio (not lower than -20, for mobile), Meta asks -16 LUFS for a Quest
  app. Vendor tables disagree on UI (-14 to -18 LUFS is quoted, as are -24 to -18 dB for subtle ones). So set the
  *relative* targets above and **measure** them: peak (dBFS) and momentary loudness (LUFS-M, 400 ms) of every sound
  through the bus at the default slider, on a recording of the real service, and pin them in a test. Leave 2 to 3 dB
  of headroom for the Ogg decode.
- **Read the ladder on loudness as well as on the peak.** A whoosh or a rip is noise: at the same peak as a click it
  is 8 to 10 LU louder (Deadnight's first set had a screen change louder than the press that caused it and the commit
  louder than a pistol shot, with the peaks in perfect order). Compare each weight's median in peak **and** in LUFS-M
  (K-weighted, loudest 400 ms; a sound shorter than the window is read zero-padded to it), at least 3 dB between the
  rungs for each, and keep the loudest menu sound under the quietest gun of the night.
- **Music and ambience:** if the menu has music, the interface sounds sit above it by their rank, not by loudness:
  hints 10 dB over the music's momentary loudness is already plain, commits 14 to 18. With no bed the room is silent,
  and the same ranks hold against the silence, so a hint at -26 dBFS is still plain on speakers and a commit at -8 is
  not startling.
- **A bed under the menu is measured, not guessed.** Record the bed alone and every hint alone on the real service at
  the default settings, put both through a laptop and a phone speaker model (the mix is linear, so a hint over the bed is
  the two added; see section 5) and gate two margins: the hint's **peak 10 dB or more over the bed's loudest 400 ms**
  (LUFS-M), and, **in the hints' own band** (1.5 to 8 kHz), the hint's loudest 50 ms **6 dB or more over the bed's loud
  50 ms** (its 95th percentile). The second exists because the first cannot tell a low motor from chirping insects: the
  motor is in no band the hints use and masks nothing there, while crickets sing at 3.7 to 5.3 kHz, where a bulb's tick
  rings, and decide how loud the whole bed may be. A first margin taken over the whole spectrum counted the motor and
  failed hints the bed did not bury. Deadnight's bed (a projector's motor and crickets, the night's own two files under
  quieter trims, no new file) sits at the edge of both gates on a flat speaker: that is the loudest bed the hints allow
  (`docs/research/menu-sfx.md`, "The ambience bed" in the game).

## 5. Touch, mouse, keyboard and pad

- **No hover on a touch screen** (the CSS `hover: none` media feature exists for this; it fails on devices with both).
  In a game, the last input device tells: a finger gets no hover or focus-move sound and its tap is the press. A
  pointer, keyboard or pad moving the focus does get the hint.
- The hint sound belongs to **moving the focus**, so the keyboard and the pad get the same hover feedback a mouse does.
- Press on release (the button's `pressed`) is accepted, because a click is 80 to 120 ms. A game that wants the
  latency lower plays the tick on button-down and the body on release.
- **Test on the worst speaker** the audience has: a laptop and a phone, not studio monitors. An agent has no ears, so
  the first pass is a **speaker model** on the recording: a laptop is two small drivers (a 4th-order high-pass at about
  280 Hz, a presence bump of 3 dB near 2.5 kHz, a low-pass near 13 kHz), a phone is one tiny driver (the channels
  summed, a 4th-order high-pass at about 500 Hz, a bump of 4 dB near 2 kHz, a low-pass near 9 kHz). These are **assumed
  curves, not measurements of a device**, and the true cutoff varies by device; they say whether the hints stay plain
  next to a bed on a small speaker (a low bed falls 3 to 7 dB on them, the hints do not), not whether the bed is
  pleasant, and a person's taste is the slider.

## 6. Accessibility

- A separate UI volume slider (above), and zero is mute.
- Nothing is sound-only: a sound repeats a visible change.
- Hearing-sensitive players: no sharp transients in the hint tier; short sounds; nothing loud that is not rare. Red Dead
  Redemption 2 lets a player switch interface sounds off, and a UI slider at zero does the same.
- Reduced motion is about motion, not sound: it cuts the slide, and the sound of the slide goes with it only if the
  game ties them (Deadnight does not: the whoosh stays a click-sized cue).
- Mono and sound-direction options matter for gameplay, not menus.

## 7. How to wire it: roles, cues and one table

What left Deadnight's menu silent was that sound lived in the *controls*: the addon's controls called the hook and the
game's own controls (drawn tickets, a tab bar) did not, and nothing noticed. The shape that fixes it, in any engine:

- A **cue** is what happened (`hover`, `focus`, `press`, `tick`, `select`, `on`, `off`, `tab`, `confirm`, `refuse`,
  `push`, `pop`), sent with its **source** (the control). The controls know *what happened*, never *which sound*.
- A **role** is what kind of control the source is (`ticket`, `tab`, `slider`, `button_ghost`): a method on the
  control, or a tag on a plain one; a word list can refine it (a button named Back is a back). One **table** maps role
  and cue to a sound, a trim and a weight, or to a written silence with its reason. A control with a role the table
  does not know, or a cue its role has no row for, is a bug a test finds.
- One **service** takes the cue and applies the rules (gaps, caps, touch, pointer or keys, pitch from the value). The
  controls of the game wire themselves with one call, so a new control is one line, not a new sound.
- The test walks every screen, finds every interactive control (a button, a range, a field, anything focusable), and
  checks its role and its rows; a second test sends each control its events and checks the cues; a third reads the
  code for a cue sent without a source.

## 8. A checklist for a new menu

1. List every interactive control and give it a **role** (ticket, tab, toggle, slider, ...). A role is the unit the
   table is written for, not the screen.
2. Write the table: role, event, sound, rank/level, variants. A silent event is written down as silent, with why.
3. Wire the sounds in **one place** (a service, or the controls' base classes), never per screen.
4. Test: every control found by walking the screens has a role in the table; the hint cap holds; the slider rate holds.
5. Record the real service walking the menu and read the **peaks and loudness per sound**, plot them.
6. Put the recording through a laptop and a phone speaker model and read the margins over any bed (section 4); listen
   on a laptop speaker and, when you can, a phone. Sound design needs a human's ear last.

## Sources and how far to trust them

Strong (primary, or a standards body): [Xbox Accessibility Guideline
105](https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/105) (separate volume per
audio kind, *Grounded*'s UI slider); [WCAG 1.4.2 Audio
Control](https://www.w3.org/WAI/WCAG21/Understanding/audio-control.html) (a volume control that works apart from the
system's, for audio that plays by itself); [Apple,
Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback) (match the channel to the
significance; do not depend on one channel); [Microsoft MRTK
`SliderSounds`](https://learn.microsoft.com/en-us/dotnet/api/mixedreality.toolkit.ux.slidersounds?view=mrtkuxcore-3.2)
(`MinSecondsBetweenTicks`, `TickEvery`); [Godot
`AudioStreamRandomizer`](https://docs.godotengine.org/en/latest/classes/class_audiostreamrandomizer.html) (random no
repeats, random pitch and volume); [AES
TD1004](https://www.production-expert.com/home-page/2015/11/17/aes-release-recommendations-for-loudness-of-audio-streaming-and-network-file-playback)
(-16 to -20 LUFS for streams; as reported by Production Expert); [Meta loudness meter
overview](https://developers.meta.com/horizon/documentation/unity/audio-loudness-meter-overview/) (-16 LUFS).

Practitioner (read through search summaries; the page could not be fetched in full): Material Design's sound pages,
[Applying sound to UI](https://m2.material.io/design/sound/applying-sound-to-ui.html) and [About
sound](https://m2.material.io/design/sound/about-sound.html) (hierarchy of hero, alert, primary and secondary sounds;
frequent below rare; sound never the only carrier); the Audiokinetic series [Approaching UI Audio from a UI Design
Perspective](https://www.audiokinetic.com/en/blog/approaching-ui-audio-ui-design-perspective-1) ([part
2](https://www.audiokinetic.com/en/approaching-ui-audio-ui-design-perspective-2): feedback, tolerance of long use,
reuse); the GDC 2025 talk "What Was That Noise" (Jonathan Bell) and the GDC session on *Civilization VII*'s UI sound
system ([schedule](https://schedule.gdconf.com/session/civilization-vii-impactful-ui-sound-design-at-scale/915690):
hierarchy, repetition, on-brand); Kenichi Tsuchiya's "if it moves it makes a sound", on *Persona 5*'s menus ([The
Sound Architect](https://www.thesoundarchitect.co.uk/persona-5-audio-review/)).

Weak (blogs and vendor pages; used only where several agree, numbers treated as starting points): [SFX Engine, Best
practices for game UI sounds](https://sfxengine.com/blog/best-practices-for-game-ui-sounds) (100 to 300 ms, error
dissonance, quieter micro sounds), [Wayline on muting UI
sounds](https://www.wayline.io/blog/muting-ui-sounds-transform-gaming) (RDR2's switch), game-audio forum advice on
hover frequency and the hundredth-repetition test, patent literature and blogs on phone speakers.

Games studied for design only, never copied: *Persona 5* (menu motion as sound), *Civilization VII* (hierarchy at
scale), *Grounded* (a UI volume slider), *Red Dead Redemption 2* (a switch for interface sounds).
