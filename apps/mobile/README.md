# Agent Box iOS client

Agent Box is a native SwiftUI client for iOS 17 and later.

Open `AgentBox.xcodeproj`, select an iPhone Simulator, and run the `AgentBox` scheme. The simulator
build does not need an Apple Developer account.

On first launch, a user can create an account or paste an existing account key. Account creation
shows the key one time. The client stores the key in Keychain and opens the card deck. It does not
require an agent or inbox during onboarding.

The Agents screen creates and manages named agents and named inboxes. Each agent page can view,
copy, replace, or revoke its key. Each inbox page shows its random address and can revoke it.

## Local-first behavior

- SQLite is the client source of truth.
- The client shows stored cards before synchronization starts.
- Clear and restore actions update local state before they upload.
- History and search use local data.
- Trusted agent cards can run complete HTML applications in a nonpersistent web view.
- Email cards use restricted mode. They can load HTTPS images, but they cannot run scripts or load
  other remote resources.
- Scheduled cards synchronize early and stay hidden until their due time.

## Background updates

The app registers with APNs at each launch. A visible new-card notification also requests a
cursor-based background synchronization. The app synchronizes once per minute while it is open. A
discretionary iOS background refresh runs as a backup and has a six-hour minimum delay. iOS selects
the actual start time. The app also synchronizes each time it becomes active.

For a signed device build, enable these capabilities for the `AgentBox` target:

- Push Notifications
- Background Modes: Background fetch
- Background Modes: Remote notifications

The App ID `cc.agentboxes` must have Push Notifications enabled in Certificates, Identifiers &
Profiles. Development builds use the APNs sandbox. TestFlight and App Store builds use production
APNs.

SwiftUI previews are in `AgentBox/Preview/PreviewCatalog.swift`. Preview and UI-test data do not
read Keychain, open the production database, or call the external service.

Run the iOS tests from the repository root:

```sh
npm run mobile:test
```
