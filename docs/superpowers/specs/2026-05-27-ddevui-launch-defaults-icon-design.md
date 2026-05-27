# DDEVUI Launch Defaults And Icon Design

Date: 2026-05-27
Status: Approved for implementation planning

## Summary

This pass improves DDEVUI's first-run feel and daily-use friction without
changing DDEV's role as the source of truth.

The app should show the last known project list immediately on launch,
refresh DDEV in the background, remove settings that do not help users,
make common "open" actions one click, filter app choices to installed
apps, and add a distinct app icon.

## Goals

- Make launch feel fast by rendering cached projects immediately.
- Keep DDEV as the authoritative source after the background refresh.
- Remove the unusable PHP presets settings section.
- Add global default editor and database app preferences.
- Use those defaults for one-click inspector actions.
- Show only installed supported editor and database alternatives.
- Add a Terminal Beacon-style app icon with a unique developer utility
  presence.

## Non-Goals

- No per-project editor or database preferences.
- No direct database connection string management.
- No replacement for DDEV's project list or project state.
- No row-level stale/cached badges during normal startup.
- No arbitrary PHP version management in global settings.
- No attempt to mimic or reuse DDEV branding.

## Launch Cache

The view model should load a cached enriched project list from app support
storage before starting DDEV discovery. If cached projects exist, they are
assigned to `projects` immediately and the first filtered project remains
selectable just as it is after a normal refresh.

After cached data is rendered, the app starts a background refresh:

1. Run `ddev list -j`.
2. Enrich projects with details, currently via `ddev describe <name> -j`.
3. Replace the displayed projects with the fresh result.
4. Persist the fresh enriched result back to cache.

The UI should show only a subtle refresh/progress state while this work
runs. Project rows should not be labeled as cached during a successful
background refresh. If refresh fails and cached projects exist, the app
keeps showing cached projects and surfaces the error in the existing
command/error area. If no cache exists, current empty/error behavior is
preserved.

This keeps the app honest: cached data buys perceived startup speed, but
DDEV still wins as soon as it responds.

## Defaults And Installed Apps

The app should define two global preferences:

- Default editor.
- Default database app.

Preferences are app-wide, not per project. When no saved preference exists
or the saved app is no longer installed, the app picks a sensible fallback.

Default editor fallback order:

1. Cursor, if installed.
2. VS Code, if installed.
3. Finder.

Default database app fallback order:

1. TablePlus, if installed.
2. Sequel Ace, if installed.
3. Querious, if installed.
4. DBeaver, if installed.

If no supported database app is installed, the primary database action is
disabled and explains why via help text or an equivalent native affordance.

Installed-app detection should use macOS bundle identifier lookup through
`NSWorkspace`, not a simple `/Applications` filename check. macOS apps can
live outside `/Applications`, and bundle lookup is less brittle.

## Inspector Actions

The selected-project inspector should change both "Open In" and
"Database" from menu-only controls into default actions with an adjacent
menu.

For editor opening:

- Clicking `Open In` opens the selected project with the configured
  default editor.
- The dropdown shows installed alternatives.
- Finder remains available as a fallback option.

For database opening:

- Clicking `Database` launches the configured default database tool via
  the existing DDEV command wrapper.
- The dropdown shows only installed supported database apps.
- The action remains disabled when the project is not running.
- The action is also disabled when no supported database apps are
  installed.

This removes the avoidable two-click path for the action users take most
of the time, while keeping alternatives discoverable.

## Settings

The settings screen should keep useful status and remove fake utility.

Keep:

- Project count.
- Running count.
- WordPress count.

Remove:

- The PHP presets section.

Add:

- Default editor picker, filtered to installed editors plus Finder.
- Default database picker, filtered to installed supported database apps.
- A small unavailable state when no supported database apps are detected.

Project-level PHP version changing stays in the selected project
environment section because PHP version is a project configuration, not a
global app preference.

## App Icon

The app icon should follow the approved Terminal Beacon direction.

The icon should be a macOS-style rounded-square asset that reads as a
developer utility:

- Dark terminal panel or shell surface.
- Prompt mark or command glyph.
- Green active indicator.
- Enough contrast to be legible in the Dock and app switcher.
- No DDEV logo reuse and no styling that implies official DDEV
  affiliation.

The icon can be generated as a raster source, then exported into an Xcode
asset catalog at required app icon sizes. The implementation should keep
the source asset in the repo so the icon can be regenerated or adjusted.

## Data Flow

Launch flow:

1. App creates `ProjectDashboardViewModel`.
2. View model loads cached projects from a cache service.
3. Cached projects render immediately if available.
4. View model starts DDEV refresh in the background.
5. Fresh projects replace cached projects.
6. Cache service writes the fresh list to app support storage.

Settings flow:

1. App availability service detects installed supported apps.
2. Settings filters pickers to available choices.
3. Settings persistence stores the selected defaults.
4. Inspector resolves the effective default from saved value plus
   fallback rules.
5. Primary action buttons execute the effective defaults.

## Error Handling

- Cache read failures should not block launch; ignore the cache and run a
  normal refresh.
- Cache write failures should not block app use; surface only if a clear,
  non-noisy path already exists.
- DDEV refresh failure should keep cached projects visible when present
  and show the error through existing error state.
- Missing default editor should fall back through the editor order.
- Missing default database app should fall back through the database order.
- No installed database app should disable database launch instead of
  showing dead menu items.

## Testing

Add focused tests for:

- Cached projects are loaded before refresh results replace them.
- Fresh refresh results are persisted to cache.
- Refresh failure keeps cached projects visible.
- Editor fallback chooses Cursor, then VS Code, then Finder.
- Database fallback chooses TablePlus, then Sequel Ace, Querious, and
  DBeaver.
- Uninstalled database tools are not exposed as available choices.
- Saved defaults are ignored when the app is not installed.
- PHP presets are no longer exposed by settings/view model state.

Manual verification should cover:

- Cold launch with no cache.
- Launch with cache and slow or failing DDEV.
- One-click `Open In` behavior.
- One-click `Database` behavior.
- Settings picker contents on a machine with only TablePlus installed.
- App icon appears in the built app.
