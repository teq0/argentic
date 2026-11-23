import ArgenticCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct ArgenticApp: App {
    @State private var model: FractalModel
    #if os(macOS)
    @NSApplicationDelegateAdaptor(ApplicationLifecycle.self) private var applicationLifecycle
    private let initialWindowSize: CGSize
    #endif

    init() {
        // A test host must not restore or overwrite the user's real app preferences.
        let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
        _model = State(initialValue: FractalModel(defaults: testing ? nil : .standard))
        #if os(macOS)
        NSWindow.allowsAutomaticWindowTabbing = false
        let available = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.size ?? CGSize(width: 1280, height: 900)
        initialWindowSize = StartupSizing.windowSize(availableSize: available)
        #endif
    }

    var body: some Scene {
        #if os(macOS)
        Window("Argentic", id: "main") {
            ContentView(model: model)
        }
        .defaultSize(width: initialWindowSize.width, height: initialWindowSize.height)
        .defaultPosition(.center)
        .commands { FractalCommands(model: model) }
        Window("Argentic Help", id: "help") {
            HelpView()
        }
        .defaultSize(width: 940, height: 680)
        #else
        WindowGroup {
            ContentView(model: model)
        }
        #endif
    }
}

#if os(macOS)
struct FractalCommands: Commands {
    var model: FractalModel

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { model.showingSavedSettings = true }
                .keyboardShortcut(",")
        }
        CommandGroup(replacing: .help) { HelpMenuContent(model: model) }
        CommandGroup(replacing: .undoRedo) {}
        CommandGroup(replacing: .pasteboard) { EditMenuContent(model: model) }
        CommandGroup(replacing: .textEditing) {}
        CommandGroup(after: .toolbar) { ViewMenuContent(model: model) }
        CommandGroup(replacing: .newItem) {
            FileMenuContent(model: model)
        }
        CommandMenu("Image") { ImageMenuContent(model: model) }
        CommandMenu("Formula") { FormulaMenuContent(model: model) }
        CommandMenu("Render") { RenderMenuContent(model: model) }
        CommandMenu("Colour") { ColorMenuContent(model: model) }
        CommandMenu("Dialogs") { DialogsMenuContent(model: model) }
        CommandMenu("Examples") { ExamplesMenuContent(model: model) }
    }
}
#endif
