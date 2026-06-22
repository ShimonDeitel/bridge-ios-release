import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var appModel: AppModel
    @AppStorage("quickmath.theme") private var themeRaw = AppTheme.system.rawValue

    @State private var forceScreen: String?

    private var theme: AppTheme { AppTheme(rawValue: themeRaw) ?? .system }

    var body: some View {
        HomeView(forceScreen: forceScreen)
            .preferredColorScheme(theme.colorScheme)
            .onChange(of: store.isPro) { _, _ in appModel.refresh() }
            .onAppear {
                #if DEBUG
                forceScreen = ProcessInfo.processInfo.environment["QUICKMATH_SCREEN"]
                #endif
            }
    }
}
