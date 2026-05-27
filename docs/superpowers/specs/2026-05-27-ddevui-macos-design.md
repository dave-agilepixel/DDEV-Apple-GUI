# DDEVUI macOS App Design

Date: 2026-05-27
Status: Draft for user review

## Summary

DDEVUI is a true native macOS application for managing local DDEV
projects. It is not an Electron, Tauri, or web-wrapper app. The first
version targets macOS Tahoe 26.x and later, Apple silicon only, and is
buildable in Xcode.

The app's purpose is to make DDEV feel like a native Mac utility without
replacing DDEV. DDEV remains the source of truth for project state,
container lifecycle, database launch commands, WordPress commands, and
project configuration. DDEVUI provides a faster, safer, and more visible
interface over the installed `ddev` CLI.

The first version is local/developer build only. The codebase should keep
the path open for a future signed and notarized direct-download `.app` or
`.dmg`, but that is not required for v1.

## Goals

- Build a native SwiftUI macOS app that is Xcode-buildable.
- List available DDEV projects from `ddev list -j`.
- Let users start, stop, restart, unlink, delete DDEV data, and delete
  source folders through explicit workflows.
- Let users add a folder, either by registering an existing DDEV project
  or configuring a new DDEV project.
- Provide day-to-day actions: open site, open in editor, open in Finder,
  open database tools, and run safe WordPress maintenance presets.
- Keep all DDEV behavior delegated to DDEV commands.
- Show command progress and failures clearly, including stdout and stderr.

## Non-Goals

- No Electron, Tauri, React, web views, or cross-platform wrapper.
- No direct Docker container or volume management.
- No custom database connection string generation for DB apps.
- No arbitrary terminal command runner in v1.
- No arbitrary WP-CLI command field in v1.
- No cloud sync, team accounts, or remote project management.
- No Mac App Store distribution in v1.
- No Intel Mac support.

## Platform

- Language: Swift.
- UI: SwiftUI.
- IDE/build: Xcode.
- Minimum OS: macOS Tahoe 26.x.
- Architecture: arm64 only.
- Distribution v1: local Xcode build/run.
- Distribution later: direct signed/notarized macOS app or DMG.

## Architecture

The app is a SwiftUI app with a thin command service boundary.

SwiftUI owns:

- Navigation and selected-project state.
- The Finder-style project list and selected-project inspector.
- Confirmation dialogs and sheets.
- Settings views.
- Command progress state.
- Rendering command output and errors.

`DDEVCommandService` owns:

- Locating and invoking the installed `ddev` executable.
- Running commands with the correct working directory.
- Capturing stdout, stderr, exit status, start time, and finish time.
- Parsing JSON output from DDEV where available.
- Returning typed results or typed command failures.
- Publishing live output for long-running commands.

No other layer should shell out to DDEV. This keeps the app testable and
prevents command behavior from leaking into view code.

The app must not inspect Docker directly for normal behavior. Docker
errors may be displayed when DDEV reports them, but the app should not
infer lifecycle state from Docker containers, volumes, or compose files.

## Main Layout

The main window uses a Finder-style layout:

- Left sidebar:
  - Projects.
  - Running filter.
  - WordPress filter.
  - Settings.
- Main project list:
  - Project name.
  - Status.
  - Type.
  - Location.
  - Search/filter controls.
- Right inspector for the selected project:
  - Lifecycle actions.
  - Daily tools.
  - WordPress actions when applicable.
  - Danger actions grouped separately.
  - Last command output/status.

This layout was chosen over a dense table or card dashboard because it
feels native on macOS, keeps the list scannable, and gives enough space
for grouped project actions without cramming destructive controls into
each row.

## Project Discovery

The project list is loaded from:

```text
ddev list -j
```

The app parses the JSON payload and maps each raw project into a
`DDEVProject` model. The model should include:

- `name`
- `appRoot`
- `shortRoot`
- `status`
- `statusDescription`
- `projectType`
- `docroot`
- `primaryURL`
- `httpURL`
- `httpsURL`
- `mailpitURL`
- `mailpitHTTPSURL`
- `xhguiURL`
- `xhguiHTTPSURL`
- `mutagenEnabled`
- `mutagenStatus`
- raw JSON fallback for fields not yet modeled

The app refreshes the list:

- On launch.
- After mutating DDEV commands.
- When the user presses refresh.
- Optionally on a user-configurable interval.

## Add Folder Workflow

`Add Folder` opens a native folder picker.

If the selected folder contains `.ddev/config.yaml`, the app treats it as
an existing DDEV project. It offers to start/register it by running:

```text
ddev start
```

with the selected folder as the working directory. After completion, the
app refreshes `ddev list -j` and selects the project if found.

If the selected folder does not contain `.ddev/config.yaml`, the app opens
a setup sheet for a new DDEV configuration. The sheet should include:

- Project name, defaulting to the folder basename.
- Project type, with common options including `wordpress`, `wp-bedrock`,
  `laravel`, and `generic`.
- Docroot.
- PHP version, defaulting to DDEV's current default unless overridden.
- Database type/version, defaulting to DDEV's current default unless
  overridden.

The app then runs:

```text
ddev config --project-name=<name> --project-type=<type> --docroot=<docroot>
```

with extra flags only when the user changed defaults. After config, the
app offers to start the project.

## Lifecycle Actions

The selected-project inspector includes:

- Start:

```text
ddev start <project>
```

- Stop:

```text
ddev stop <project>
```

- Restart:

```text
ddev restart <project>
```

- Open site:
  - Prefer the `primary_url` from `ddev list -j`.
  - Open with macOS `NSWorkspace`.

- Power off all:

```text
ddev poweroff
```

Power off all should live in a global toolbar/menu area, not inside a
single project's danger actions.

## Removal And Delete Actions

Removal actions must be explicit because DDEV and the source filesystem
have different meanings.

### Unlink From DDEV List

Unlink removes the project from DDEV's global project list without
removing source files or database data:

```text
ddev stop --unlist <project>
```

The app must explain that the project can reappear when started from its
folder.

### Delete DDEV Data

Delete DDEV data removes DDEV project information and database data:

```text
ddev delete <project>
```

Local DDEV help states that `ddev delete` removes project information,
including the database, but does not touch the source codebase or the
project's `.ddev` folder. The app must present this distinction clearly.

This action requires confirmation. The confirmation must name the project
and state that database data is affected.

### Delete Source Folder

Delete source folder is a separate danger action. It is not part of
`ddev delete`, because DDEV does not remove the source codebase.

The app should only offer source-folder deletion after a strong
confirmation. The user must type the project name or folder basename. The
first implementation should prefer moving the folder to Trash through
macOS APIs rather than permanent deletion.

If both DDEV data deletion and source-folder deletion are requested, the
app should run the DDEV deletion first, then move the folder to Trash only
after DDEV deletion succeeds or after the user explicitly confirms they
want to continue despite a DDEV deletion failure.

## Editor And Finder Actions

The app includes a preferred editor setting. Initial supported options:

- Cursor.
- Visual Studio Code.
- Finder.
- System default where appropriate.

The app should detect whether supported editor apps are installed and
disable unavailable choices with clear guidance. Opening a project folder
should use native macOS app launching, not shell aliases that may not
exist in GUI app environments.

Finder is always available and should remain the fallback.

## Database Tool Actions

Database tool actions must delegate to DDEV commands. The app should not
construct its own connection strings for TablePlus, Sequel Ace, Querious,
or DBeaver.

Supported DB actions:

```text
ddev sequelace
ddev tableplus
ddev querious
ddev dbeaver
```

These run from the selected project's folder. Each command depends on the
matching macOS app and DDEV command availability. If unavailable or if the
command fails, the app shows the captured output and suggests installing
or enabling the matching tool.

The app may also expose browser-based DDEV service links from project
metadata, such as Mailpit or XHGui, when present in the DDEV JSON.

## WordPress Presets

WordPress actions are shown only for projects whose DDEV project type is
`wordpress` or `wp-bedrock`.

V1 exposes safe presets only:

- Update WordPress core.
- Update all plugins.
- Update all themes.

Commands run through DDEV from the project directory:

```text
ddev wp core update
ddev wp plugin update --all
ddev wp theme update --all
```

Each WordPress preset requires confirmation and displays command output.
The app should not include an arbitrary WP-CLI command field in v1.

If `ddev wp` fails because the project is not running, not WordPress, or
WP-CLI is unavailable, the app shows the raw command failure and a concise
message explaining the likely cause.

## Settings

V1 settings:

- Preferred editor.
- Preferred database tool.
- Refresh interval or manual-only refresh.
- Confirm danger actions, always on for source-folder deletion.
- DDEV executable path override, defaulting to discovered `ddev`.

Settings should be stored locally using a simple macOS-appropriate
persistence mechanism such as `UserDefaults`, unless implementation
reveals a stronger reason for a file-backed settings store.

## Command Result Model

Every command execution returns a `CommandResult`:

- command executable
- arguments
- working directory
- exit code
- stdout
- stderr
- started at
- finished at
- whether the command was cancelled

Views should not parse raw command output directly. Parsing belongs in
services or model mappers.

## Error Handling

The app must handle:

- DDEV not installed or not discoverable.
- Docker unavailable or stopped, as reported by DDEV.
- `ddev list -j` returning invalid or unexpected JSON.
- Project folder missing.
- Permission denied when opening or deleting folders.
- DB tool commands missing or failing.
- Editor app missing.
- WordPress preset failure.
- Long-running command cancellation.

Errors should include:

- A short user-facing summary.
- The command that ran.
- stdout and stderr, copyable.
- A retry action when appropriate.

## Testing Strategy

Unit tests:

- Parse representative `ddev list -j` output.
- Map project statuses and project types.
- Build command specifications for lifecycle, DB tool, and WP actions.
- Enforce destructive-action confirmation rules.
- Validate settings defaults.

Service tests:

- Use an injected fake command runner.
- Verify commands are run with the correct executable, arguments, and
  working directory.
- Verify successful and failed command results.
- Verify refresh behavior after mutating commands.

Manual integration checks:

- Run against one local WordPress DDEV project.
- Run against one local non-WordPress DDEV project.
- Start, stop, restart, unlink, and refresh.
- Open editor and Finder.
- Run one DB tool command if the corresponding app/command exists.
- Run WP preset commands only on a disposable or backed-up WordPress
  project.

## Sources And Verified Local Facts

- Local DDEV version checked during design: `v1.25.2`.
- Local `ddev list -j` returns project metadata suitable for project
  discovery.
- Local `ddev delete --help` says delete removes DDEV project
  information, including database data, but not the source codebase or
  `.ddev` folder.
- Local `ddev stop --help` says `--unlist` removes a project from the
  global list and `--remove-data` removes stored project data.
- DDEV database management docs describe macOS database launch commands
  including Sequel Ace, TablePlus, Querious, and DBeaver:
  https://docs.ddev.com/en/stable/users/basics/database_management/
- DDEV command docs describe available DDEV CLI behavior:
  https://docs.ddev.com/en/stable/users/usage/commands/

## Open Decisions Before Implementation

No product-blocking decisions remain for the first implementation plan.
Implementation may still need tactical choices such as the exact Xcode
project structure, test target layout, and whether the initial UI uses
SwiftData or simpler observable models. Those belong in the implementation
plan, not this design spec.
