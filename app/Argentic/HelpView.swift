import Foundation
import SwiftUI

/// FEATURES.md is both the repository's guide and the bundled offline Help resource.
struct HelpDocument {
    struct Topic: Identifiable {
        let id: Int
        let title: String
        let markdown: String

        func matches(_ query: String) -> Bool {
            let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            return query.isEmpty || "\(title)\n\(markdown)".localizedStandardContains(query)
        }
    }

    let topics: [Topic]

    init(markdown: String) {
        var topics: [Topic] = []
        var title = "About Argentic"
        var lines: [String] = []
        func appendTopic() {
            let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { topics.append(Topic(id: topics.count, title: title, markdown: body)) }
        }
        for line in markdown.components(separatedBy: .newlines) {
            if line.hasPrefix("## ") {
                appendTopic()
                title = String(line.dropFirst(3))
                lines.removeAll()
            } else if !line.hasPrefix("# ") {
                lines.append(line)
            }
        }
        appendTopic()
        self.topics = topics
    }

    static func load(bundle: Bundle = .main) -> HelpDocument? {
        guard let url = bundle.url(forResource: "FEATURES", withExtension: "md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return HelpDocument(markdown: markdown)
    }
}

/// A small renderer for the guide's headings, paragraphs and bullet lists, with inline Markdown styling.
struct HelpBlock: Identifiable {
    enum Kind: Equatable { case paragraph, heading, bullet }
    let id: Int
    let kind: Kind
    let text: String

    static func parse(_ markdown: String) -> [HelpBlock] {
        var blocks: [HelpBlock] = []
        var paragraph: [String] = []
        func append(_ kind: Kind, _ text: String) {
            blocks.append(HelpBlock(id: blocks.count, kind: kind, text: text))
        }
        func flush() {
            if !paragraph.isEmpty { append(.paragraph, paragraph.joined(separator: " ")); paragraph.removeAll() }
        }
        for line in markdown.components(separatedBy: .newlines) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flush()
            } else if line.hasPrefix("### ") {
                flush()
                append(.heading, String(line.dropFirst(4)))
            } else if line.hasPrefix("- ") {
                flush()
                append(.bullet, String(line.dropFirst(2)))
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return blocks
    }
}

struct HelpView: View {
    private let document: HelpDocument?
    @State private var search = ""
    @State private var selectedID: Int?
    @Environment(\.dismiss) private var dismiss

    init(document: HelpDocument? = HelpDocument.load()) {
        self.document = document
        #if os(macOS)
        _selectedID = State(initialValue: document?.topics.first?.id)
        #else
        _selectedID = State(initialValue: nil)
        #endif
    }

    private var topics: [HelpDocument.Topic] {
        document?.topics.filter { $0.matches(search) } ?? []
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedID) {
                ForEach(topics) { topic in
                    NavigationLink(value: topic.id) { Text(topic.title) }
                }
            }
            .overlay {
                if document == nil {
                    ContentUnavailableView("Help Unavailable", systemImage: "questionmark.circle",
                        description: Text("The bundled FEATURES.md guide could not be loaded."))
                } else if topics.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .searchable(text: $search, prompt: "Search help topics and contents")
            .navigationTitle("Argentic Help")
            .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 320)
        } detail: {
            if let topic = topics.first(where: { $0.id == selectedID }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(topic.title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                        ForEach(HelpBlock.parse(topic.markdown)) { block in
                            switch block.kind {
                            case .heading:
                                Text(block.text).font(.title2.bold()).padding(.top, 8)
                                    .accessibilityAddTraits(.isHeader)
                            case .paragraph:
                                inlineText(block.text).fixedSize(horizontal: false, vertical: true)
                            case .bullet:
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text("•").accessibilityHidden(true)
                                    inlineText(block.text).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .id(topic.id)
                .textSelection(.enabled)
                .navigationTitle(topic.title)
            } else {
                ContentUnavailableView("Choose a Help Topic", systemImage: "book",
                    description: Text("Browse the topics or search for a control or feature."))
            }
        }
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        #else
        .frame(minWidth: 680, minHeight: 460)
        #endif
    }

    private func inlineText(_ markdown: String) -> Text {
        let text = (try? AttributedString(markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(markdown)
        return Text(text)
    }
}

struct HelpMenuContent: View {
    var model: FractalModel
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        Button {
            #if os(macOS)
            openWindow(id: "help")
            #else
            model.showingHelp = true
            #endif
        } label: {
            Label("Argentic Help", systemImage: "questionmark.circle")
        }
        #if os(macOS)
        .keyboardShortcut("?", modifiers: .command)
        #endif
    }
}
