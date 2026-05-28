# DDEVUI QOL Feature Roadmap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the highest-impact DDEV quality-of-life features to DDEVUI while keeping each feature independently shippable and testable.

**Architecture:** Expand the current SwiftUI app by adding focused DDEV command adapters, typed models for command output where useful, and feature-specific inspector sections or sheets. Keep shell execution behind `DDEVServicing`/`DDEVCommandService`; views must call view-model methods, not construct CLI commands directly.

**Tech Stack:** Swift 6.3, SwiftUI, Foundation, AppKit, XCTest, DDEV CLI v1.25.x.

---

## Scope

Included features from the audit:

1. Database import/export UI
2. Snapshot manager
3. Logs viewer
4. Add-on browser/manager
5. Rich project configuration editor
6. Framework command launcher
9. Diagnostics/health panel
10. Broader project-type support

Intentionally skipped for now:

- Remote pull/push workflows
- Share/tunnel UI

Those two touch external providers, authentication, public URLs, and potentially production data. Thinking about them before building is the right call.

## Cross-Cutting File Structure

Keep existing files, but stop allowing them to balloon unchecked.

- `Sources/DDEVUIApp/Services/DDEVCommandService.swift`: Add low-level DDEV command methods only.
- `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift`: Keep shared project selection and refresh state; move feature-heavy state into focused view models when a feature needs more than a couple of published properties.
- `Sources/DDEVUIApp/Models/DDEVProject.swift`: Extend project type support and decoding only.
- `Sources/DDEVUIApp/Models/CommandResult.swift`: Keep generic command capture.
- `Sources/DDEVUIApp/Models/DDEVDatabaseOperation.swift`: Create for import/export options and file naming.
- `Sources/DDEVUIApp/Models/DDEVSnapshot.swift`: Create for snapshot list parsing and restore selections.
- `Sources/DDEVUIApp/Models/DDEVAddon.swift`: Create for add-on list/search/install state.
- `Sources/DDEVUIApp/Models/DDEVConfig.swift`: Create for editable config fields surfaced in the UI.
- `Sources/DDEVUIApp/Models/DDEVDiagnostic.swift`: Create for diagnostic checks and parsed command status.
- `Sources/DDEVUIApp/Models/DDEVFrameworkCommand.swift`: Create for type-aware command presets.
- `Sources/DDEVUIApp/Views/ProjectInspectorView.swift`: Keep as the selected-project shell; extract new feature sections into child views.
- `Sources/DDEVUIApp/Views/DatabaseOperationsView.swift`: Create for import/export.
- `Sources/DDEVUIApp/Views/SnapshotManagerView.swift`: Create for snapshots.
- `Sources/DDEVUIApp/Views/LogsViewerView.swift`: Create for logs.
- `Sources/DDEVUIApp/Views/AddonManagerView.swift`: Create for add-ons.
- `Sources/DDEVUIApp/Views/ProjectConfigEditorView.swift`: Create for config editing.
- `Sources/DDEVUIApp/Views/FrameworkCommandLauncherView.swift`: Create for framework commands.
- `Sources/DDEVUIApp/Views/DiagnosticsView.swift`: Create for diagnostics.
- `Tests/DDEVUIAppTests/*`: Add focused tests per feature.

## Build Order

### Phase 0: Command Infrastructure Hardening

**Status:** Implemented and locally verified. Not committed.

**Why first:** Several features need commands that can take longer, return text, fail partially, or require file paths. The current command surface is enough for simple actions, but too thin for this roadmap.

**Files:**
- Modify: `Sources/DDEVUIApp/Services/DDEVCommandService.swift`
- Modify: `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift`
- Modify: `Sources/DDEVUIApp/Views/CommandOutputView.swift`
- Test: `Tests/DDEVUIAppTests/DDEVCommandServiceTests.swift`
- Test: `Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift`

**Tasks:**

- [x] Add command-service methods for `import-db`, `export-db`, `import-files`, `snapshot`, `snapshot restore`, `snapshot --list`, `logs`, `add-on`, `config`, `utility diagnose`, `utility configyaml`, `mutagen`, and `xhgui`.
- [x] Add tests proving each method maps to the exact intended DDEV arguments and working directory.
- [x] Add a command-history model so the UI can show more than the last command when a feature runs multiple commands.
- [x] Keep destructive commands behind explicit view-model methods so confirmation logic cannot be bypassed from a view.
- [x] Run `swift test`.
- [ ] Commit as `refactor: Expand DDEV command surface`.

**Acceptance Criteria:**

- [x] Existing app behavior still works.
- [x] Every new DDEV command adapter has argument-mapping test coverage.
- [x] No new SwiftUI view constructs a raw DDEV command.

### Phase 1: Database Import/Export UI

**Status:** Implemented and locally verified. Not committed.

**Why this is first:** It is the biggest daily QOL improvement. It also builds the file-picker, confirmation, and progress patterns reused by snapshots and files import.

**Files:**
- Create: `Sources/DDEVUIApp/Models/DDEVDatabaseOperation.swift`
- Create: `Sources/DDEVUIApp/Views/DatabaseOperationsView.swift`
- Modify: `Sources/DDEVUIApp/Services/DDEVCommandService.swift`
- Modify: `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift`
- Modify: `Sources/DDEVUIApp/Views/ProjectInspectorView.swift`
- Test: `Tests/DDEVUIAppTests/DDEVCommandServiceTests.swift`
- Test: `Tests/DDEVUIAppTests/ProjectDashboardViewModelTests.swift`

**User-Facing Features:**

- Import database from `.sql`, `.sql.gz`, `.sql.bz2`, `.sql.xz`, `.zip`, `.tgz`, `.tar`, `.tar.gz`, `.tar.bz2`, or `.tar.xz`.
- Export database to a chosen path.
- Choose target/source database name, defaulting to `db`.
- Choose compression for export: gzip default, plain SQL, bzip2, or xz.
- Choose import behavior: drop database first by default, or use `--no-drop`.
- Show a scary but plain-English confirmation before any import that drops data.

**Tasks:**

- [x] Add `DDEVDatabaseImportOptions` with `filePath`, `database`, `extractPath`, and `dropExistingDatabase`.
- [x] Add `DDEVDatabaseExportOptions` with `outputPath`, `database`, and `compression`.
- [x] Add command-service tests for default import, named database import, archive extract path, no-drop import, gzip export, plain SQL export, bzip2 export, and xz export.
- [x] Build `DatabaseOperationsView` as an inspector section with Import and Export buttons opening sheets.
- [x] Use `NSOpenPanel` for import file selection and `NSSavePanel` for export destination.
- [x] Refresh project state after successful import/export only when DDEV state may have changed.
- [x] Run `swift test`.
- [ ] Commit as `feat: Add database import export UI`.

**Acceptance Criteria:**

- [x] A user can export a database without typing a command.
- [x] A user can import a database only after confirming whether existing data will be replaced.
- [x] Failed imports show stderr/stdout in command output.

### Phase 2: Snapshot Manager

**Status:** Implemented by subagent and under review. Subagent verification passed; parent review still in progress. Snapshot create now suggests an editable project/timestamp name. Not committed.

**Why second:** Snapshots are the safety net for risky local work. They pair naturally with database import/export.

**Files:**
- Create: `Sources/DDEVUIApp/Models/DDEVSnapshot.swift`
- Create: `Sources/DDEVUIApp/Views/SnapshotManagerView.swift`
- Modify: `Sources/DDEVUIApp/Services/DDEVCommandService.swift`
- Modify: `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift`
- Modify: `Sources/DDEVUIApp/Views/ProjectInspectorView.swift`
- Test: `Tests/DDEVUIAppTests/DDEVCommandServiceTests.swift`
- Test: `Tests/DDEVUIAppTests/DDEVSnapshotParsingTests.swift`

**User-Facing Features:**

- Create named snapshot.
- Suggest an editable default snapshot name from the project name and timestamp.
- List snapshots for selected project.
- Restore selected snapshot.
- Restore latest snapshot.
- Clean up all snapshots after confirmation.
- Delete/clean one named snapshot if supported by the installed DDEV command.

**Tasks:**

- [x] Add command mappings for `ddev snapshot --name`, `ddev snapshot --list`, `ddev snapshot restore <name>`, `ddev snapshot restore --latest`, and `ddev snapshot --cleanup -y`.
- [x] Parse snapshot list output into `DDEVSnapshot` with name, database type/version suffix, and display label.
- [x] Add `SnapshotManagerView` with list, create, restore, restore latest, and cleanup controls.
- [x] Default the create field to a sanitized project/timestamp snapshot name while preserving custom user edits.
- [x] Require confirmation before restore and cleanup.
- [x] After restore, run refresh and keep command output visible.
- [x] Run `swift test`.
- [ ] Commit as `feat: Add snapshot manager`.

**Acceptance Criteria:**

- [x] A user can create a named snapshot and see it in the UI.
- [x] A user cannot restore or clean snapshots without confirmation.
- [ ] Snapshot actions work for stopped projects if DDEV starts them automatically. Parent review pending.

### Phase 3: Logs Viewer

**Status:** Non-streaming logs viewer implemented and verified in the current workspace. Live follow intentionally deferred. Not committed.

**Why third:** Logs are a constant “drop to terminal” reason and a good place to improve command streaming. Do not overbuild a terminal emulator.

**Files:**
- Create: `Sources/DDEVUIApp/Views/LogsViewerView.swift`
- Create: `Sources/DDEVUIApp/Models/DDEVLogRequest.swift`
- Modify: `Sources/DDEVUIApp/Services/CommandRunning.swift`
- Modify: `Sources/DDEVUIApp/Services/DDEVCommandService.swift`
- Modify: `Sources/DDEVUIApp/Views/ProjectInspectorView.swift`
- Test: `Tests/DDEVUIAppTests/DDEVCommandServiceTests.swift`

**User-Facing Features:**

- Show logs for selected service, defaulting to `web`.
- Service picker with at least `web`, `db`, and `router`.
- Tail count picker: 50, 100, 250, 500.
- Toggle timestamps.
- Manual refresh in v1; live follow can be a second slice if streaming complicates the runner.

**Tasks:**

- [x] Add command mapping for `ddev logs <project> --service <service> --tail <count>` and optional `--time`.
- [x] Build a non-streaming logs view first using captured stdout.
- [x] Add copy-to-clipboard button for log output.
- [x] Add visual handling for empty logs and stopped projects.
- [ ] Add streaming `--follow` only after non-streaming logs are stable.
- [x] Run `swift test`.
- [x] Run `xcodebuild -project DDEVUI.xcodeproj -scheme DDEVUI -destination 'platform=macOS' build`.
- [ ] Commit as `feat: Add project logs viewer`.

**Acceptance Criteria:**

- [x] A user can inspect web and database logs without a terminal.
- [ ] Large logs do not freeze the UI. Manual review pending.
- [x] The first version is useful even without live tailing.

### Phase 4: Broader Project-Type Support

**Status:** Implemented, verified, and committed on `codex/phase-4-project-type-support`. PR pending.

**Why before config editor:** Project type drives defaults, framework commands, import-files behavior, and UI sections. The current enum is too narrow.

**Files:**
- Modify: `Sources/DDEVUIApp/Models/DDEVProject.swift`
- Modify: `Sources/DDEVUIApp/Views/ContentView.swift`
- Modify: `Sources/DDEVUIApp/Views/ProjectListView.swift`
- Test: `Tests/DDEVUIAppTests/DDEVProjectDecodingTests.swift`

**User-Facing Features:**

- Add supported DDEV project types: `asterios`, `backdrop`, `cakephp`, `codeigniter`, `craftcms`, `drupal`, `drupal6`, `drupal7`, `drupal8`, `drupal9`, `drupal10`, `drupal11`, `drupal12`, `joomla`, `magento`, `magento2`, `php`, `shopware6`, `silverstripe`, `symfony`, `typo3`, and `wp-bedrock`.
- Keep `other` for unknown future DDEV project types.
- Add sidebar filters only where they genuinely help; do not create twenty noisy filters.

**Tasks:**

- [x] Extend `DDEVProjectType` with all current DDEV-supported types.
- [x] Add `displayName`, `symbol`, and framework-family helpers for each type.
- [x] Update Add Project sheet project-type picker to include common types and an advanced disclosure for less common types.
- [x] Add decoding tests for Drupal, Craft, TYPO3, Magento, Symfony, PHP, Joomla, and unknown future type fallback.
- [x] Run `swift test`.
- [x] Run `xcodebuild -project DDEVUI.xcodeproj -scheme DDEVUI -destination 'platform=macOS' build`.
- [x] Commit as `feat: Expand DDEV project type support`.

**Acceptance Criteria:**

- [x] Existing projects no longer collapse into `other` when DDEV reports a supported type.
- [x] The Add Project flow supports more than WordPress, Laravel, and Generic.

### Phase 5: Rich Project Configuration Editor

**Why after project types:** This feature depends on having accurate project type and display helpers.

**Files:**
- Create: `Sources/DDEVUIApp/Models/DDEVConfig.swift`
- Create: `Sources/DDEVUIApp/Views/ProjectConfigEditorView.swift`
- Modify: `Sources/DDEVUIApp/Services/DDEVCommandService.swift`
- Modify: `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift`
- Modify: `Sources/DDEVUIApp/Views/ProjectInspectorView.swift`
- Test: `Tests/DDEVUIAppTests/DDEVCommandServiceTests.swift`
- Test: `Tests/DDEVUIAppTests/DDEVConfigParsingTests.swift`

**User-Facing Features:**

- Edit PHP version.
- Edit Node.js version.
- Edit database type/version.
- Edit webserver type: `nginx-fpm`, `apache-fpm`, `generic`.
- Edit performance mode: global, none, mutagen.
- Edit Xdebug enabled flag.
- Edit XHProf mode: global, prepend, xhgui.
- Edit upload dirs and additional hostnames.
- Show a restart-needed banner after config changes that require restart.

**Tasks:**

- [x] Read current config via `ddev utility configyaml <project> --full-yaml --omit-keys=web_environment`.
- [x] Decode the config fields the UI owns into `DDEVConfig`.
- [x] Add command mappings for each supported `ddev config` flag.
- [x] Build config editor as a sheet opened from the Environment section.
- [x] Apply one config change at a time and show the exact command result.
- [x] Prompt to restart if the selected project is running.
- [x] Keep raw YAML editing out of this feature; raw editing belongs in a separate advanced feature.
- [x] Run `swift test`.
- [x] Commit as `feat: Add project config editor`.

**Acceptance Criteria:**

- A user can safely change common config values without editing YAML.
- The app does not hide that many config changes require restart.
- The app does not expose sensitive `web_environment` values in UI output.

### Phase 6: Framework Command Launcher

**Why after project types and config:** The command list should be type-aware.

**Files:**
- Create: `Sources/DDEVUIApp/Models/DDEVFrameworkCommand.swift`
- Create: `Sources/DDEVUIApp/Views/FrameworkCommandLauncherView.swift`
- Modify: `Sources/DDEVUIApp/Services/DDEVCommandService.swift`
- Modify: `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift`
- Modify: `Sources/DDEVUIApp/Views/ProjectInspectorView.swift`
- Test: `Tests/DDEVUIAppTests/DDEVCommandServiceTests.swift`
- Test: `Tests/DDEVUIAppTests/DDEVFrameworkCommandTests.swift`

**User-Facing Features:**

- WordPress: update core/plugins/themes, cache flush, search-replace helper later only with strong guardrails.
- Laravel: `artisan migrate`, `artisan migrate:fresh --seed`, `artisan cache:clear`, `artisan route:list`.
- Drupal/Backdrop: `drush cr`, `drush updb`, `drush cim`, `drush cex`.
- Magento 2: `magento cache:flush`, `magento setup:upgrade`, `magento indexer:reindex`.
- Craft CMS: `craft clear-caches/all`, `craft migrate/all`.
- TYPO3: `typo3 cache:flush`, `typo3 database:updateschema`.
- Generic/PHP/Symfony: Composer install/update and Symfony cache clear where applicable.

**Tasks:**

- [x] Define command presets with title, icon, project-type family, DDEV arguments, destructive-risk level, and confirmation message.
- [x] Add generic `runProjectCommand(arguments:in:)` to the command service.
- [x] Add tests proving each preset maps to the correct DDEV arguments.
- [x] Build launcher as a compact inspector section with grouped command menus.
- [x] Require confirmation for destructive or high-impact commands such as fresh migrations and config imports.
- [x] Run `swift test`.
- [x] Commit as `feat: Add framework command launcher`.

**Acceptance Criteria:**

- The app offers relevant commands based on project type.
- High-risk commands are not one-click footguns.
- Command output is visible immediately after a framework command runs.

### Phase 7: Add-On Browser and Manager

**Status:** In progress on `codex/phase-7-addon-browser-manager`.

**Why later:** It is high-value, but add-ons involve network calls, GitHub rate limits, project file changes, and dependency installs.

**Files:**
- Create: `Sources/DDEVUIApp/Models/DDEVAddon.swift`
- Create: `Sources/DDEVUIApp/Views/AddonManagerView.swift`
- Modify: `Sources/DDEVUIApp/Services/DDEVCommandService.swift`
- Modify: `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift`
- Modify: `Sources/DDEVUIApp/Views/ProjectInspectorView.swift`
- Test: `Tests/DDEVUIAppTests/DDEVCommandServiceTests.swift`
- Test: `Tests/DDEVUIAppTests/DDEVAddonParsingTests.swift`

**User-Facing Features:**

- List installed add-ons for selected project.
- Search available add-ons.
- Install add-on by owner/repo.
- Remove installed add-on after confirmation.
- Recommend common official add-ons: Redis, Memcached, MongoDB, Adminer, phpMyAdmin, Redis Insight, BrowserSync, Solr, Elasticsearch, OpenSearch where available.

**Tasks:**

- [x] Add command mappings for `ddev add-on list --installed --project <name>`, `ddev add-on search <query>`, `ddev add-on get <owner/repo> --project <name>`, and `ddev add-on remove <name> --project <name>`.
- [x] Parse tabular add-on output conservatively; preserve raw output if parsing fails.
- [ ] Build installed add-ons list with remove controls.
- [ ] Build search/install sheet.
- [ ] Show a restart-needed banner after install/remove.
- [ ] Run `swift test`.
- [ ] Commit as `feat: Add DDEV add-on manager`.

**Acceptance Criteria:**

- A user can see what add-ons are installed.
- A user can install and remove common add-ons without typing command syntax.
- Network or GitHub rate-limit failures are shown clearly.

### Phase 8: Diagnostics and Health Panel

**Why near the end:** It benefits from the config, project type, logs, Mutagen, and add-on work already being present.

**Files:**
- Create: `Sources/DDEVUIApp/Models/DDEVDiagnostic.swift`
- Create: `Sources/DDEVUIApp/Views/DiagnosticsView.swift`
- Modify: `Sources/DDEVUIApp/Services/DDEVCommandService.swift`
- Modify: `Sources/DDEVUIApp/Views/ContentView.swift`
- Test: `Tests/DDEVUIAppTests/DDEVCommandServiceTests.swift`

**User-Facing Features:**

- Show DDEV version and component versions.
- Run DDEV diagnose.
- Show Docker/DDEV availability problems.
- Show Mutagen status, sync, reset, and logs for projects using Mutagen.
- Show custom config warnings via `ddev utility check-custom-config`.
- Show database match check via `ddev utility check-db-match`.
- Provide copyable diagnostic output for bug reports.

**Tasks:**

- [ ] Add command mappings for `ddev version`, `ddev utility diagnose`, `ddev utility check-custom-config`, `ddev utility check-db-match`, `ddev mutagen status`, `ddev mutagen sync`, `ddev mutagen reset`, and `ddev mutagen logs`.
- [ ] Build a Diagnostics sidebar item separate from Settings.
- [ ] Add global checks when no project is selected and project checks when one is selected.
- [ ] Require confirmation before Mutagen reset.
- [ ] Add copy-all diagnostic output.
- [ ] Run `swift test`.
- [ ] Commit as `feat: Add diagnostics health panel`.

**Acceptance Criteria:**

- A user can diagnose common DDEV/Docker/project problems without knowing diagnostic commands.
- Reset-style actions have confirmation.
- Diagnostic output can be copied for support/issues.

## Suggested Release Slices

### Release 1: Data Safety

- Phase 0: Command Infrastructure Hardening
- Phase 1: Database Import/Export UI
- Phase 2: Snapshot Manager

This should be the first public-facing QOL release. It makes the app meaningfully more useful than a pretty project list.

### Release 2: Visibility

- Phase 3: Logs Viewer
- Phase 8: Diagnostics and Health Panel

This turns DDEVUI into a troubleshooting surface, not just a launcher.

### Release 3: Project Breadth

- Phase 4: Broader Project-Type Support
- Phase 6: Framework Command Launcher

This prevents the app from feeling WordPress-biased and makes it useful across normal DDEV projects.

### Release 4: Power User Controls

- Phase 5: Rich Project Configuration Editor
- Phase 7: Add-On Browser and Manager

These are powerful and riskier because they write config and install services. They should land after the core workflows are solid.

## Testing Strategy

- Every DDEV command wrapper gets argument-mapping tests.
- Every parser gets fixture-based tests with realistic command output.
- Every destructive view-model action gets a test proving it is exposed through an explicit method and returns command output.
- UI snapshot tests are not required yet; SwiftUI view model and command mapping tests give better value for this project right now.
- Run `swift test` before every commit.
- Use manual testing against at least one WordPress project, one Laravel project, one Drupal or generic PHP project, and one stopped project.

## Risk Controls

- Database import, snapshot restore, add-on removal, delete, Mutagen reset, migration fresh, and config import must require confirmation.
- Prefer DDEV-native commands over direct file mutation.
- Do not edit `.ddev/config.yaml` by hand unless a DDEV command cannot express the setting.
- Do not parse terminal tables as a hard dependency where JSON or YAML output exists.
- Preserve raw command output whenever parsing fails.
- Avoid provider sync and public tunnel features until their security/product decisions are settled.

## Open Product Decisions Before Implementation

1. Should database import/export include files import in the same release, or should files import be a separate “Assets” feature?
2. Should add-on search hit only `ddev add-on search`, or also surface curated official add-ons when offline?
3. Should framework command presets be editable by users, or fixed in v1?
4. Should diagnostics be project-first in the inspector or app-wide in its own sidebar item?

My recommendation:

- Keep files import separate from database import/export.
- Ship curated official add-ons plus search.
- Keep framework presets fixed in v1.
- Make diagnostics its own sidebar item because troubleshooting often starts before a project is selected.
