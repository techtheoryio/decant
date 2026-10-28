import Sparkle

/// Sparkle reads `appcast.xml` from the latest GitHub release (SUFeedURL in the Info.plist written by build-app.sh).
/// Bare SwiftPM builds have no Info.plist, so the updater only starts inside the bundled .app.
@MainActor let updater = SPUStandardUpdaterController(
    startingUpdater: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil, updaterDelegate: nil, userDriverDelegate: nil)

@MainActor var canUpdate: Bool { Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil }
