import SwiftUI

@main
struct PocketJevApp: App {
    @State private var viewModel = DecisionViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .preferredColorScheme(.dark)
        }
    }
}
