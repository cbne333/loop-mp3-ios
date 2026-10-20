import SwiftUI

@main
struct LoopMP3App: App {
    @StateObject private var player = PlayerStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(player)
                .tint(.indigo)
        }
    }
}
