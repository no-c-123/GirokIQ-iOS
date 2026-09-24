# AI Chat UX Redesign Proposal

## Goal

Make the AI chat feel like a natural part of GirokIQ rather than a generic side chatbot. The redesign should make the assistant feel more grounded in the notebook, easier to trust, and faster to use without adding visual clutter.

The current foundation is good:

- notebook-scoped chat history is the right product decision
- region capture and image attachment already fit the canvas workflow
- the visual style is restrained and compatible with the rest of the app

What is missing is stronger context, clearer state, and better interaction hierarchy.

## Product direction

The AI should feel like:

- a **notebook assistant**
- aware of the current page and selected context
- lightweight and fast
- visually secondary to the canvas, but still polished and intentional

It should not feel like:

- a generic ChatGPT-style panel
- a separate app inside the app
- an overloaded utility drawer

## Main problems now

### 1. Weak context visibility

The current chat does not strongly communicate what the AI is looking at.

From the user’s perspective, it is not obvious whether the assistant is answering from:

- the current notebook
- the current page
- an attached image
- a captured region

This makes the feature less trustworthy.

### 2. Header is too thin

The current header only shows:

- `AI Assistant`
- a history toggle

That is not enough for a feature with multiple conversation states. It should communicate where the user is, what chat is active, and offer the most important actions immediately.

### 3. Streaming state is underpowered

The current streaming bubble works technically, but there is not enough visible control when a response is generating.

Users should be able to instantly understand:

- that the assistant is generating
- what they can do while it is generating
- how to stop it

### 4. Input hierarchy is blurry

The current input area combines:

- `+`
- region capture
- text input
- send
- image preview

All the capabilities are useful, but the hierarchy is not as clear as it could be. Region capture is much more important to this product than a normal image attachment, yet both feel similar in weight.

### 5. History works but feels internal

The history screen is functional, but it feels more like a debug-friendly list than a designed notebook conversation browser.

It needs better prioritization and clearer “current chat” identity.

## Proposed redesign

## Layout

Keep the same overall structure:

1. header
2. conversation area
3. input composer

But refine each zone to communicate notebook-aware AI.

## Header

Replace the current minimal header with a more informative one.

### Proposed header structure

Left:

- `Notebook Assistant`
- small sublabel:
  - current notebook name, or
  - `This notebook`

Center or secondary line:

- current chat title

Right:

- `New Chat`
- `History`

### Behavior

- `New Chat` starts a fresh notebook-scoped chat immediately
- `History` opens the conversation list
- current chat title should update after the first user prompt if possible

### Why

This makes the AI feel tied to the notebook instead of floating above it as a generic assistant.

## Context bar

Add a compact context row directly above the input composer.

### Purpose

Show the user what the AI is currently using as context.

### Example chips

- `Notebook context`
- `Current page`
- `Captured region`
- `Attached image`

Only show the relevant ones.

### Behavior

- If the user captures a region, show `Captured region`
- If the user attaches an image, show `Attached image`
- If neither is active, show `Current page` or `Notebook context`

### Why

This is the highest-value trust improvement. The user should never wonder what the assistant is looking at.

## Conversation area

Keep the current message list structure, but improve tone and differentiation.

### Assistant message style

- keep the assistant bubble visually calm
- keep markdown support
- keep text selection

But add slightly stronger identity:

- small assistant sparkles icon or monogram
- subtle but clearer grouping of assistant responses

### User message style

- slightly tighter and more compact than assistant bubbles
- attached image should appear clearly grouped with the user message that used it

### Welcome state

Keep the current welcome prompts, but tune them to the product.

Recommended quick prompts:

- `Summarize this page`
- `Explain these notes`
- `Turn this into an outline`
- `What should I add next?`

These are more notebook-native than generic chat prompts.

## Streaming state

This should be more visible and more controllable.

### Proposed behavior

While generating:

- send button becomes `Stop`
- composer remains visible
- streaming bubble shows a subtle active state

### Optional refinement

Add a tiny label like:

- `Thinking about your notes…`

This is more product-specific than a generic typing indicator.

### Why

It reduces uncertainty and gives immediate control.

## Input composer

The composer should emphasize the actions that matter most for GirokIQ.

### Proposed order

1. region capture
2. attach
3. text field
4. send or stop

### Reason

Region capture is a native notebook action. It should feel first-class, not buried as a secondary utility.

### Composer behavior

- if no input and no attachment: send is disabled
- if attached context exists, show it clearly above the composer
- if streaming: send becomes stop

## Region capture treatment

This is one of the strongest unique features, so it should feel special.

### Current issue

It behaves like just another input action.

### Proposed treatment

When region capture is active:

- show a visible active chip above the composer:
  - `Captured region ready`
- allow remove/clear before sending
- once sent, visually associate that context with the resulting user message

### Why

This turns capture into a confident interaction rather than a temporary hidden state.

## History redesign

Keep history notebook-scoped, but make it feel more intentional.

### Proposed structure

Top:

- `New Chat` action

Below:

- recent conversations
- current chat visually highlighted

Each history item should show:

- title
- last updated time
- optional one-line preview later, if you add it

### Future-safe actions

Not required immediately, but the design should allow:

- rename chat
- delete chat

## Visual style

Keep the current restrained visual language. Do not turn the AI panel into a flashy product.

### Design principles

- fewer colors
- stronger spacing hierarchy
- better state communication
- more context chips, fewer generic icons

### Should stay

- warm gold accent
- soft surfaces
- clean typography
- low-noise bubbles

### Should improve

- header clarity
- active state clarity
- context visibility
- action hierarchy

## Proposed UI structure

### Default state

- header:
  - `Notebook Assistant`
  - notebook name
  - `New Chat`
  - `History`
- welcome state
- suggested prompts
- composer
- context chip: `Current page`

### With captured region

- same header
- conversation
- context chip: `Captured region`
- clear button on the chip
- composer

### While streaming

- assistant bubble in active state
- send button replaced by `Stop`
- context chip remains visible

### History mode

- compact list of notebook chats
- current chat highlighted
- `New Chat` pinned at top

## Interaction rules

### Chat start

- entering AI should reopen the most recent notebook chat
- `New Chat` always starts a fresh one

### Context precedence

If multiple contexts exist, priority should be:

1. captured region
2. attached image
3. current page
4. notebook summary context

### Send behavior

- plain prompt with no extra context uses notebook/page context
- captured region overrides generic page context
- attached image is explicit context

## Recommended implementation order

1. redesign header
2. add context chip system above composer
3. convert send to send/stop streaming control
4. improve captured-region state visibility
5. refine history presentation
6. polish message grouping and attachment display

## What not to change

- notebook-scoped history logic
- markdown rendering in assistant messages
- image attachment support
- region capture capability itself

Those are good foundations already.

## Success criteria

The redesign is successful if:

- users immediately understand what the AI is using as context
- the assistant feels notebook-aware, not generic
- region capture feels first-class
- streaming feels controllable
- history feels like part of the notebook, not a separate tool

## Short version

The AI chat should evolve from:

- a clean but generic side panel

into:

- a notebook-aware assistant with visible context, stronger state clarity, and better composer hierarchy

The most important improvement is not visual styling. It is making the AI’s context obvious and trustworthy.
