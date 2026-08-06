# Deck control design QA

## Evidence

- Source screenshot: `.build/dismiss-controls-reference.png`.
- Active-deck screenshot: `.build/dismiss-controls-active.png`.
- Empty-state screenshot: `.build/dismiss-controls-implementation.png`.
- Empty-state comparison: `.build/dismiss-controls-comparison.png`.
- Device: iPhone 17 Pro Simulator with iOS 26.2.

## Requested changes

- Put Dismiss on the left and Undo on the right.
- Replace Done with Dismiss.
- Keep Dismiss available while an animation runs.
- Let fast taps dismiss more than one card.
- Animate each Dismiss action to the right.
- Use Liquid Glass for both controls.
- Keep the empty-state photograph full bleed without a white control area.
- Hide Dismiss and Undo on the empty-state splash.
- Use a long press on Dismiss to open the Dismiss All confirmation directly.
- Send the visible stack away in one fast, staggered Dismiss All burst.
- Put the Snooze clock to the left of Dismiss and anchor its quick actions to the clock.
- Fold a snoozed card into the clock with a Metal shader.

## Visual comparison

The source screenshot has a white area below the full-bleed photograph. The old controls sit in this
area and look separate from the main interface. The new controls float above active cards as one
Liquid Glass control layer. They are not present on the empty-state splash. There is no white area
at the bottom.

Dismiss uses the selected primary color. Undo uses neutral glass. Both controls have the same size,
shape, and baseline.

The active-deck screenshot shows that the card ends above the controls. The controls do not cover
the card body.

## Interaction verification

- Fast Dismiss taps queue correctly and clear both preview cards.
- Dismiss stays enabled while the first card moves out.
- Dismiss uses the same spring motion as Undo, in the opposite direction.
- Both controls disappear when the final card leaves.
- A long press opens the Dismiss All confirmation alert with no intermediate menu.
- Dismiss All deals up to six visible cards through one tight rightward lane and clears the rest in
  one local batch.
- The Snooze menu opens from the clock. The card folds, shades, shrinks, and fades into the clock.

## Findings

There are no open P0, P1, or P2 findings.

final result: passed
