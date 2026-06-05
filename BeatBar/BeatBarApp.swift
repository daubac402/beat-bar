import SwiftUI

@main
struct BeatBarApp: App {
    @NSApplicationDelegateAdaptor(BeatBarAppDelegate.self) private var appDelegate
    @StateObject private var nowPlaying = NowPlayingViewModel()

    var body: some Scene {
        MenuBarExtra {
            PlayerPanelView()
                .environmentObject(nowPlaying)
        } label: {
            MenuBarCompactView()
                .environmentObject(nowPlaying)
        }
        .menuBarExtraStyle(.window)
    }
}
