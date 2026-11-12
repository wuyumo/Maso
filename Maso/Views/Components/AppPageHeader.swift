import SwiftUI

/// Native navigation for both permanent pages and temporary sheets. The three
/// initializers mirror NavigationStack without changing ownership of its path.
struct AppNavigationStack<Data, Root: View>: View {
    private let stack: NavigationStack<Data, Root>

    init(@ViewBuilder root: () -> Root) where Data == NavigationPath {
        stack = NavigationStack(root: root)
    }

    init(path: Binding<NavigationPath>, @ViewBuilder root: () -> Root) where Data == NavigationPath {
        stack = NavigationStack(path: path, root: root)
    }

    init(path: Binding<Data>, @ViewBuilder root: () -> Root)
    where Data: MutableCollection & RandomAccessCollection & RangeReplaceableCollection, Data.Element: Hashable {
        stack = NavigationStack(path: path, root: root)
    }

    var body: some View { stack.appPageHeader() }
}

/// One shared system header; screens supply only titles and toolbar actions.
extension View {
    /// Full-bleed media keeps native navigation controls without a backdrop.
    @ViewBuilder
    func appUnobstructedMediaHeader() -> some View {
        if #available(iOS 26.0, *) {
            self
                .toolbarBackground(.hidden, for: .navigationBar)
                .scrollEdgeEffectHidden(true, for: .top)
        } else {
            self.toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder
    func appPageHeader() -> some View {
        if #available(iOS 26.0, *) {
            self
                .toolbarBackground(.automatic, for: .navigationBar)
                .scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            // Earlier iOS versions keep their native navigation-bar material.
            self.toolbarBackground(.automatic, for: .navigationBar)
        }
    }
}
