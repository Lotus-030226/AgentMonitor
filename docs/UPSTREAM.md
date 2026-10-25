# Upstream source

Repository: https://github.com/jazzenchen/agent-hud-native-open

Revision: `f1ebd1b7d609fe77e5f328974decdb800ddea995`

The source copy excludes Git history and build products.
The copy preserves the Apache 2.0 license and third-party notices.
Agent Monitor adds local monitoring and native host integration.

Local changes to inherited code:
- `HoverPanelView` measures full-width host content above the footer for the unified local summary.
- `ProviderFiles.lines` rejects completed wanted lines above its JSON size limit before decoding.
- `AdditionalProviderTests` covers this chunk-boundary regression.
- Localization adds Traditional Chinese detection, ICU conversion, formatting, and explicit language selection.
- The English quota-notice test scopes its language and restores the previous choice.
- The WorkBuddy quota test verifies canonical English labels under Traditional Chinese and restores its language.
- The host limits the initial viewport to two vendor groups. Other groups stay in the native scroll view.
- Session-only vendors receive status cards without inferred quota. Hidden vendors remain hidden.
- Session rows show client labels and support source filtering before the row limit.
- Known Codex CLI and Desktop source aliases share canonical client names.
- Local pages and Statistics use Settings navigation and shared window tokens.
- Host windows and optional panels share the inherited appearance refresh pipeline.
- A one-time host migration selects frosted HUD material and matching window appearance.
- Docker hover previews reuse HUD surfaces and hold only their own HUD open.
- Claude quota notices separate engine sign-in from Desktop session evidence.
- Production monitoring, statistics, and settings entries share one host window.
- Embedded adapters preserve original statistics and settings controls without duplicate sidebars.
- The host sidebar places branding above navigation and the supplied settings artwork below it.
- Local TCP listeners use bounded read-only sampling, independent of Docker.

- Replace the app icon with the original B1 Dual Orbits artwork, selected by the user.
- Keep editable SVG masters and a native icon generation script in the project.

- Remove the standalone local HUD and its menu commands. Keep the integrated Agent HUD summary.
- Constrain heatmap hover details to the visible window area.

- Remove the production status item. Keep the floating HUD and native app-menu routes.
- Reopening the app brings the shared overview window forward.
