# GirokIQ: Must Fix Before TestFlight / App Review

This is the shortened audit I would use before external testing. It intentionally excludes lower-priority polish, dormant cloud-sync debt, and general cleanup. The focus here is only:

- data loss
- account safety and recovery
- misleading backup/delete behavior
- broken core interactions that can destroy user work
- issues likely to create App Review risk

## Release gate

I would not ship to TestFlight or submit for App Review until the items in the `Must fix now` section are resolved.

## Must fix now

### 1. Sign out deletes all local notebooks and content

**Why this is a blocker**

In the current launch mode, notebooks, pages, drawings, and chats are local-only. `signOut()` calls `resetAllData()`, which deletes local content. A normal sign-out should never silently wipe all user work.

**Risk**

- catastrophic user data loss
- immediate trust failure in TestFlight
- very hard to defend if discovered during review or QA

**What to change**

- Do not call `resetAllData()` on normal sign-out in local-only mode.
- Only clear auth/session state.
- If you ever want a device wipe option, make it a separate destructive action with explicit wording.

**Ship bar**

- Signing out preserves all notebooks and pages on device.
- Re-signing into the same account does not destroy local work.

---

### 2. No password reset flow

**Why this is a blocker**

There is no visible “Forgot password?” path and no reset call wired in. If a user forgets their password, they are effectively locked out.

**Risk**

- broken account recovery
- poor first impression in TestFlight
- App Review/account-management concern

**What to change**

- Add a `Forgot password?` entry in auth.
- Call `supabase.auth.resetPasswordForEmail(email)`.
- Show clear success/error messaging and support the return flow after email reset.

**Ship bar**

- A tester can request a reset from the app.
- The app clearly explains the next step after the reset email is sent.

---

### 3. Sign-up has no confirmation-state messaging

**Why this is a blocker**

If email confirmation is enabled, `response.session` can be `nil`. Right now the sign-up path appears to do nothing in that case.

**Risk**

- broken onboarding
- users think sign-up failed
- easy TestFlight feedback magnet

**What to change**

- Handle the no-session case explicitly.
- Show a message such as: “We sent a confirmation link to your email. Confirm it, then sign in.”

**Ship bar**

- Sign-up always ends in a clear next state: signed in, or told to confirm email.

---

### 4. “Export All Data” is not a reliable backup in the current build

**Why this is a blocker**

The current export path pulls notebooks from Supabase, but the app is currently local-first with content stored on device. That means export can be empty or incomplete while the UI suggests the user has made a backup.

**Risk**

- false sense of safety
- dangerous in combination with sign-out/account issues
- bad TestFlight outcome if users try backup/restore

**What to change**

- Export from `LocalDatabase`, not remote notebook metadata.
- Use the existing archive machinery so pages, drawings, elements, and images are actually included.

**Ship bar**

- Export contains the real local notebooks and assets.
- A tester can restore from the export and recover actual content.

---

### 5. Account deletion is incomplete

**Why this is a blocker**

The app offers account deletion, so deletion needs to be complete and honest. The audit identified two gaps:

- server-side image assets may survive deletion once cloud assets are in play
- local image files written by the app can remain on device after delete

Even if some cloud paths are dormant today, the local-device cleanup problem still matters because deletion should remove user-created data tied to the account action.

**Risk**

- App Review concern for incomplete account deletion
- user trust and privacy problem

**What to change**

- Make deletion remove app-created local image files as well as DB rows.
- Ensure the server-side delete flow also removes related storage assets before deleting the auth user.

**Ship bar**

- After account deletion, no account-linked notebook/chat/image data remains on device.
- Server-side deletion flow is complete for any stored user assets.

---

### 6. Ink can be lost when switching pages quickly

**Why this is a blocker**

The current save path appears to use shared debounced tasks across pages. The reported failure mode is: draw on one page, switch fast, draw on another, then lose the first page’s latest strokes if the app disappears or is killed before the right flush happens.

**Risk**

- silent data loss in core note-taking flow
- severe TestFlight trust issue

**What to change**

- Track debounce/save tasks per page instead of globally shared tasks.
- Make flush/save sweep all dirty pages, not just the current page.

**Ship bar**

- Rapid page switching does not lose recent strokes.
- Backgrounding or leaving the notebook does not drop pending page edits.

---

### 7. Lasso cut/copy/paste can destroy selected text/image blocks

**Why this is a blocker**

The audit describes a high-risk case where lasso-selected blocks are deleted by Cut even though they were never copied properly. That is a direct destructive workflow in a visible editing feature.

**Risk**

- silent content destruction
- broken editing behavior during external testing

**What to change**

- Do not allow `cut` to delete elements unless those elements were actually serialized to the clipboard.
- Ideally add real clipboard support for text/image elements alongside strokes.

**Ship bar**

- Lasso cut/copy/paste behaves safely for ink, text, and image selections.
- No selection can be deleted by a failed copy path.

---

### 8. Mandatory account for a local-only product is still an App Review risk

**Why this matters**

At launch, core notebook content is local-only, but the app requires sign-in before use. That can attract scrutiny because the account requirement is not obviously necessary for the primary note-taking function.

**Risk**

- App Review questioning why account creation is mandatory
- extra friction in TestFlight onboarding

**Recommendation**

This is the one item in this document that is slightly less binary than the others. I would treat it as a submission-risk item, not a product-quality nit.

You have two acceptable paths:

- **Preferred:** allow local use without account creation, then require sign-in only for AI or cloud-related features
- **Fallback:** keep required sign-in, but make sure password reset, sign-up messaging, and sign-out safety are fixed first, and be ready to justify that account auth is required for the AI assistant experience

**Ship bar**

- Either guest/local mode exists, or the account requirement is defensible and the auth flow is polished enough not to feel broken.

## Not required before first TestFlight

These are important, but I would not block the first external build on them unless testing proves otherwise:

- visual consistency issues
- page thumbnail rendering for text/image-only pages
- overlay positioning and fixed-canvas polish
- text tool refinement like select-vs-edit model
- lasso precision improvements, unless testers report it as unusable
- cloud-storage RLS issues that are dormant until full sync/assets are enabled
- general dead-code and repo cleanup

## Recommended implementation order

1. Sign-out safety
2. Password reset
3. Sign-up confirmation messaging
4. Real local export
5. Ink-loss save fix
6. Safe lasso cut/copy/paste
7. Account deletion completeness
8. Decide whether to keep mandatory account for submission

## Practical exit criteria

Before sending the build to TestFlight, I would manually verify these flows on-device:

1. Create notes, sign out, sign back in: content still exists.
2. Forgot password flow works end-to-end.
3. Sign-up with email confirmation enabled shows the correct message.
4. Export produces a recoverable backup of local content.
5. Rapid page switching does not drop recent strokes.
6. Lasso cut/copy/paste does not destroy text/image blocks.
7. Delete account removes all local account-linked content.

Once these are done, the rest can be handled in the next pass.
