# Canvas Design Rework Plan

## Summary

This plan redesigns the canvas UI to match the approved mockup while preserving the recently restored textbox behavior, lasso behavior, and canvas pan/zoom behavior. The core direction is:

- keep a stable, always-visible left tool rail
- remove the large persistent properties panel from the main layout
- move tool controls into compact contextual popovers
- keep text formatting only in the top text bar
- use small contextual pills for lasso, selected objects, and empty-canvas actions

The implementation should prioritize interaction safety over visual speed. The highest-risk areas are textbox creation/editing, gesture routing on infinite canvas, keyboard visibility, and keeping infinite/fixed canvas behavior aligned.

## Current State Analysis

### Layout shell

- [Canvas container](computer:///sessions/6a2b8775181048857457251b/workspace/GirokIQ-ios/Features/Canvas/CanvasContainerView.swift) still renders three left-side regions at once:
  - `CanvasSidebar`
  - `PageStripView`
  - `PropertiesPanel`
- The current top text formatting bar is already in the right place for the target UX:
  - [Text tool bar mount point](computer:///sessions/6a2b8775181048857457251b/workspace/GirokIQ-ios/Features/Canvas/CanvasContainerView.swift)

### Tool controls

- [Canvas toolbar](computer:///sessions/6a2b8775181048857457251b/workspace/GirokIQ-ios/Features/Canvas/CanvasToolbar.swift) already has tool buttons and popover entry points, but the popovers are informational, not functional.
- [Properties panel](computer:///sessions/6a2b8775181048857457251b/workspace/GirokIQ-ios/Features/Canvas/PropertiesPanel.swift) still contains the real editing controls for pen, eraser, lasso, image, color, width, opacity, and assistants.

### Text interactions

- [Block overlay](computer:///sessions/6a2b8775181048857457251b/workspace/GirokIQ-ios/Features/Canvas/BlockOverlayView.swift) contains the fragile text editor, sizing, selection, drag, and resize logic.
- The working textbox state depends on:
  - geometry-based hit routing
  - `ScribbleFreeTextEditor`
  - `PassthroughTextView`
  - one-finger move/resize on selected text
  - two-finger pan for block tools
  - keyboard-safe viewport adjustments

### Canvas host behavior

- [Infinite canvas host](computer:///sessions/6a2b8775181048857457251b/workspace/GirokIQ-ios/Features/Canvas/PKCanvasRepresentable.swift) contains the most regression-sensitive routing logic.
- [Fixed canvas host](computer:///sessions/6a2b8775181048857457251b/workspace/GirokIQ-ios/Features/Canvas/FixedCanvasView.swift) must stay behaviorally aligned even though it uses a different scroll/zoom structure.

### Contextual overlays

- [Block overlay](computer:///sessions/6a2b8775181048857457251b/workspace/GirokIQ-ios/Features/Canvas/BlockOverlayView.swift) already contains:
  - `LassoSelectionOverlay`
  - `CanvasContextMenuOverlay`
  - text selection handles
- These are the right foundations for the redesign. The main missing piece is a compact selected-object pill for text and image elements.

## Assumptions & Decisions

### Assumptions

- The approved target is the “best UX” mockup discussed earlier:
  - left rail always visible
  - no large persistent inspector
  - compact tool popovers
  - text formatting only in the top bar
  - small contextual pills for object/lasso/empty-canvas actions
- The redesign should preserve the existing working textbox fixes instead of replacing them with a new interaction model.
- Both infinite and fixed canvases must remain supported, even if implementation focus starts with infinite canvas.

### Decisions

- `PropertiesPanel` will stop being a persistent layout surface and become a source of reusable compact controls.
- `TextToolKeyboardBar` remains the only text formatting surface.
- Undo/redo should move out of `PropertiesPanel` into persistent top chrome.
- Tool customization will be attached to the selected tool button via compact popovers.
- Lasso actions remain near the lasso selection, not in a tool popover.
- Selected object actions will appear in a small contextual pill near the selected object, not in the text formatting bar.
- Interaction logic should be centralized into `CanvasViewModel` helpers before the visual refactor expands, to reduce divergence between infinite and fixed canvas implementations.

## Proposed Changes

### Phase 1: Stabilize shared interaction helpers before moving UI

#### Files

- [Canvas view model](computer:///sessions/6a2b8775181048857457251b/workspace/GirokIQ-ios/Features/Canvas/CanvasViewModel.swift)
- [Infinite canvas host](computer:///sessions/6a2b8775181048857457251b/workspace/GirokIQ-ios/Features/Canvas/PKCanvasRepresentable.swift)
- [Fixed canvas host](computer:///sessions/6a2b8775181048857457251b/workspace/GirokIQ-ios/Features/Canvas/FixedCanvasView.swift)
- [Block overlay](computer:///sessions/6a2b8775181048857457251b/workspace/GirokIQ-ios/Features/Canvas/BlockOverlayView.swift)

#### What to change

- Add shared helper methods to `CanvasViewModel` for:
  - hit-testing text elements at a canvas point
  - handling a text-tool tap on canvas
  - computing selected object anchor geometry in canvas space
- Change `PKCanvasRepresentable` and `FixedCanvasView` to call the shared helpers instead of duplicating create/select logic.
- Keep the current overlay hit-routing and textbox-specific behavior intact.

#### Why

- This reduces the chance that the redesign breaks the restored textbox behavior.
- It removes the current duplication between infinite and fixed canvas handling.

#### How

- Extract the existing create/select logic from host views into view-model methods.
- Do not rewrite `ScribbleFreeTextEditor`, `PassthroughTextView`, text resize handles, or current selection geometry during this phase.

### Phase 2: Rebuild the layout shell around a stable left rail

#### Files

- [Canvas container](computer:///sessions/6a2b8775181048857457251b/workspace/GirokIQ-ios/Features/Canvas/CanvasContainerView.swift)
- [Canvas sidebar](computer:///sessions/6a2b8775181048857457251b/workspace/GirokIQ-ios/Features/Canvas/CanvasSidebar.swift)
- [Canvas toolbar](computer:///sessions/6a2b8775181048857457251b/workspace/GirokIQ-ios/Features/Canvas/CanvasToolbar.swift)
- [Page strip](computer:///sessions/6a2b8775181048857457251b/workspace/GirokIQ-ios/Features/Canvas/PageStripView.swift)

#### What to change

- Make the left rail always visible.
- Remove the large persistent `PropertiesPanel` from the main canvas stack.
- Keep `PageStripView` as a contextual flyout near the rail.
- Preserve top toolbar and text formatting bar structure.

#### Why

- This is the biggest structural difference between the current UI and the approved mockup.
- It removes the heavy “second attention zone” that the persistent panel creates.

#### How

- Remove `canvasVM.isToolbarVisible` as the gate for the left rail.
- Remove the `PropertiesPanel(viewModel:)` block from the main layout.
- Keep the overlay stack order stable:
  - region capture
  - lasso/object/empty-canvas pills
  - left rail and page strip

### Phase 3: Move persistent properties into compact tool popovers

#### Files

- [Canvas toolbar](computer:///sessions/6a2b8775181048857457251b/workspace/GirokIQ-ios/Features/Canvas/CanvasToolbar.swift)
- [Properties panel](computer:///sessions/6a2b8775181048857457251b/workspace/GirokIQ-ios/Features/Canvas/PropertiesPanel.swift)
- [Canvas view model](computer:///sessions/6a2b8775181048857457251b/workspace/GirokIQ-ios/Features/Canvas/CanvasViewModel.swift)

#### What to change

- Replace `ToolPopoverView` with real compact controls.
- Reuse controls already implemented in `PropertiesPanel`:
  - color grid
  - stroke width selector
  - opacity control
  - pen style selector
  - eraser type selector
  - assistant toggles where still appropriate
- Keep text formatting out of tool popovers.

#### Why

- This preserves working controls without keeping the large persistent panel.
- It matches the approved compact popover UX.

#### How

- Factor `PropertiesPanel` into smaller reusable subviews or helpers.
- Update `ToolbarToolButton` behavior:
  - tap unselected tool = select tool
  - tap selected tool again or long-press = open popover
- Keep tool memory behavior unchanged.

### Phase 4: Rework contextual action surfaces into one pill language

#### Files

- [Block overlay](computer:///sessions/6a2b8775181048857457251b/workspace/GirokIQ-ios/Features/Canvas/BlockOverlayView.swift)
- [Canvas container](computer:///sessions/6a2b8775181048857457251b/workspace/GirokIQ-ios/Features/Canvas/CanvasContainerView.swift)
- [Canvas view model](computer:///sessions/6a2b8775181048857457251b/workspace/GirokIQ-ios/Features/Canvas/CanvasViewModel.swift)

#### What to change

- Keep and visually refine the existing empty-canvas pill.
- Keep and visually refine the existing lasso pill.
- Add a new compact selected-object pill for text and image elements.

#### Why

- This fills the main UX gap between the current implementation and the approved design.
- It gives object actions a clear home without reopening the side inspector problem.

#### How

- Compute selected-object anchor points in canvas space in `CanvasViewModel`.
- Project them into screen space in `BlockOverlayView`.
- For text elements:
  - keep move/resize handles
  - keep formatting in the top bar
  - object pill should only contain object actions like duplicate/delete/copy if useful
- For image elements:
  - replace one-off overlay actions with the same pill style

### Phase 5: Keep text mode coherent and top-bar-only

#### Files

- [Text tool keyboard bar](computer:///sessions/6a2b8775181048857457251b/workspace/GirokIQ-ios/Features/Canvas/TextToolKeyboardBar.swift)
- [Canvas container](computer:///sessions/6a2b8775181048857457251b/workspace/GirokIQ-ios/Features/Canvas/CanvasContainerView.swift)
- [Canvas view model](computer:///sessions/6a2b8775181048857457251b/workspace/GirokIQ-ios/Features/Canvas/CanvasViewModel.swift)

#### What to change

- Keep `TextToolKeyboardBar` as the only text formatting surface.
- Update viewport/keyboard visibility protection to account for the final top chrome height.
- Ensure no duplicated text-formatting controls remain in popovers or panels.

#### Why

- Text mode should feel like one coherent mode, not split between top and side surfaces.

#### How

- Update `ensureSelectedTextVisible` to use the final occupied-top-space rather than assuming minimal toolbar height.
- Preserve the current textbox interaction behavior while adjusting only layout-dependent offsets.

### Phase 6: Clean up transitional UI/state after parity is confirmed

#### Files

- [Properties panel](computer:///sessions/6a2b8775181048857457251b/workspace/GirokIQ-ios/Features/Canvas/PropertiesPanel.swift)
- [Canvas container](computer:///sessions/6a2b8775181048857457251b/workspace/GirokIQ-ios/Features/Canvas/CanvasContainerView.swift)
- [Canvas view model](computer:///sessions/6a2b8775181048857457251b/workspace/GirokIQ-ios/Features/Canvas/CanvasViewModel.swift)
- [Text keyboard toolbar duplicate candidate](computer:///sessions/6a2b8775181048857457251b/workspace/GirokIQ-ios/Features/Canvas/TextKeyboardToolbar.swift)

#### What to change

- Remove or retire old panel-only state once compact popover parity is reached.
- Confirm whether `TextKeyboardToolbar.swift` is obsolete and remove or archive it only after the redesign is stable.

#### Why

- This prevents dead UI paths from reintroducing regressions later.

#### How

- Defer deletion until the redesign is fully working.
- Prefer cleanup after verification, not before.

## Verification Steps

### Core layout

- Left rail is always visible.
- No persistent large properties panel appears in normal canvas layout.
- Page strip still opens and closes correctly.
- Undo/redo remain visible and functional without the old panel.

### Tool popovers

- Pen, pencil, marker, eraser, and image popovers open and close correctly.
- Tool popovers update tool settings immediately.
- Tool memory still restores color/width/opacity per tool.
- Text tool does not expose formatting in a tool popover.

### Textbox non-regression

- Tap empty canvas in text mode creates a textbox in one tap.
- Tap existing textbox with finger keeps it selected/editable.
- One-finger move and resize still work.
- Two-finger pan still works in text mode.
- Pinch zoom still works.
- Keyboard stays up during finger editing.
- Text remains visible above keyboard.
- Unresized textboxes still auto-size.
- User-resized textboxes still keep width and auto-grow height.

### Contextual pills

- Empty-canvas long-press pill appears only on empty canvas.
- Lasso pill still supports cut/copy/paste/duplicate/delete/color/screenshot.
- Selected-object pill appears for text and image elements.
- Pills are positioned correctly while scrolled and zoomed.

### Canvas mode parity

- Infinite canvas behavior remains correct.
- Fixed canvas behavior matches functionally for create/select/pan/zoom and contextual overlays.

### Regression watchlist

- No reappearance of textbox offset bugs.
- No reappearance of disappearing textboxes after pan/zoom.
- No reappearance of lost finger tap editing.
- No reappearance of blocked move/resize gestures.
- No unexpected system edit menu over textboxes or empty canvas.
