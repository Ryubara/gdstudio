---
areas: [godot-ui, tests]
---
# A border over a plate shrank with its padded container and covered the plate's words

2026-11-05

- **Saw:** Deadnight #1071 put a frame (a border run inside the outline) over a roster row, a lobby seat and a card
  preview. Three things were wrong in the captures, none in the tests: the last numbers of a row ran into the border;
  after the row was given padding the border shrank with it and left a strip of the row outside the frame; and the
  frame covered the bottom half of the title printed on the card in the preview.
- **Cause:** a `PanelContainer` lays out every child, an overlay included, inside its stylebox's content margins, so
  padding meant for the words also insets the border; and a border drawn inside a picture covers whatever the picture
  keeps at its edge. A border is a thing with its own room, and it was given none.
- **Fix:** the overlay draws outside its rectangle when its container insets it (`FrameArt.grow`, the outline grown by
  the margin) and the room is taken from the content by a spacer or a narrower last cell, so the row is as wide as
  it was; a picture with words at its edge gets the border outside it. Check for next time: when something is drawn
  over a plate, capture it over the plate with the most at its edge (a title, numbers flush right, a seat number flush
  left) and read it at player size before writing the test; and read the stroke width off the smallest plate (a
  compact box of 32 units, not only the 66 of your own).
- **Docs:** Deadnight `docs/research/calling-cards.md#frames`, [UI controls](../godot/ui-controls.md).
