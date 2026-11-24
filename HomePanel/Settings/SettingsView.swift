import AppKit
import HAKit
import SwiftUI
import UniformTypeIdentifiers

/// General tab: the Home Assistant connection and layout import/export.
struct ConnectionSettings: View {
    @Environment(AppModel.self) private var app

    @State private var urlString = SharedConfig.baseURLString
    @State private var token = ""
    @State private var hasSavedToken = TokenStore.hasToken
    @State private var testing = false
    @State private var testResult: TestResult?
    @State private var saveError: String?

    @State private var exporting = false
    @State private var importing = false
    @State private var pendingImport: (name: String, config: PanelConfig)?
    @State private var layoutMessage: String?
    @State private var loginItem = LoginItem()

    private enum TestResult {
        case success(String)
        case failure(String)
    }

    var body: some View {
        Form {
            Section {
                TextField("URL", text: $urlString, prompt: Text(SharedConfig.exampleBaseURL))
                    .textContentType(.URL)
                SecureField(
                    "Access token", text: $token,
                    prompt: Text(hasSavedToken ? "Saved in Keychain. Paste to replace" : "Paste a long-lived access token"))
                Text("Create a token in Home Assistant → Profile → Security → Long-lived access tokens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Home Assistant")
            }

            Section {
                HStack(spacing: 10) {
                    Button("Test connection", action: test)
                        .disabled(testing || (token.isEmpty && !hasSavedToken))
                    if testing { ProgressView().controlSize(.small) }
                    testLabel
                    Spacer()
                    Button("Save", action: save)
                        .keyboardShortcut(.defaultAction)
                        .disabled(SharedConfig.validatedURL(urlString) == nil)
                }
                if let saveError {
                    Text(saveError).font(.caption).foregroundStyle(.red)
                }
                LabeledContent("Status", value: app.store.status.label)
            }

            Section {
                LabeledContent("Rooms") {
                    Text(app.config.config.rooms.map(\.name).joined(separator: ", ").nilIfEmpty ?? "None yet")
                        .lineLimit(2)
                }
                HStack {
                    Button("Import…") { importing = true }
                    Button("Export…") { exporting = true }
                        .disabled(app.config.config.rooms.isEmpty)
                    Spacer()
                    if let layoutMessage {
                        Text(layoutMessage).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Layout")
            } footer: {
                Text("Export saves your rooms and cards to a file you can back up or share. Import replaces them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Open HomePanel at login", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.set($0) }))
                if loginItem.needsApproval {
                    HStack {
                        Text("Allow HomePanel in Login Items to finish turning this on.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") { loginItem.openSystemSettings() }
                    }
                }
                if let error = loginItem.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Startup")
            }

            Section {
                HStack {
                    if hasSavedToken {
                        Button("Remove saved token", role: .destructive) {
                            TokenStore.delete()
                            hasSavedToken = false
                            app.settingsChanged()
                        }
                    }
                    Button("Run Setup Again…") { app.forceSetup = true }
                    Spacer()
                    Button("Quit HomePanel") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loginItem.refresh() }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .fileExporter(
            isPresented: $exporting, document: LayoutDocument(config: app.config.config),
            contentType: .json, defaultFilename: "HomePanel Layout.homepanel.json"
        ) { result in
            switch result {
            case .success(let url): layoutMessage = "Exported \(url.lastPathComponent)"
            case .failure(let error): layoutMessage = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            readImport(result)
        }
        .confirmationDialog(
            "Replace your layout?",
            isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
            presenting: pendingImport
        ) { pending in
            Button("Replace with \(pending.config.rooms.count) room\(pending.config.rooms.count == 1 ? "" : "s")", role: .destructive) {
                app.config.replace(with: pending.config)
                app.layoutReplaced()
                layoutMessage = "Imported \(pending.name)"
                pendingImport = nil
            }
        } message: { pending in
            Text("\(pending.name) has \(pending.config.rooms.map(\.name).joined(separator: ", ")). Your current rooms will be replaced. Export them first if you want to keep a copy.")
        }
    }

    private func readImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let config = try PanelConfig.decode(try Data(contentsOf: url))
            pendingImport = (url.lastPathComponent, config)
        } catch {
            layoutMessage = "Couldn't read that file: \(error.localizedDescription)"
        }
    }

    @ViewBuilder private var testLabel: some View {
        switch testResult {
        case .success(let text):
            Label(text, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .lineLimit(1)
        case .failure(let text):
            Label(text, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .lineLimit(2)
        case nil:
            EmptyView()
        }
    }

    private func test() {
        guard let url = SharedConfig.validatedURL(urlString) else {
            testResult = .failure(HARestError.invalidURL.localizedDescription)
            return
        }
        guard let tokenToTest = token.isEmpty ? TokenStore.load() : token.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return }
        testing = true
        testResult = nil
        Task {
            do {
                let info = try await HARest(baseURL: url, token: tokenToTest).serverInfo()
                testResult = .success("Connected · Home Assistant \(info.version)")
            } catch {
                testResult = .failure(HAErrorText.describe(error))
            }
            testing = false
        }
    }

    private func save() {
        saveError = nil
        SharedConfig.baseURLString = urlString
        if !token.isEmpty {
            do {
                try TokenStore.save(token)
                token = ""
                hasSavedToken = true
            } catch {
                saveError = error.localizedDescription
                return
            }
        }
        app.settingsChanged()
    }
}

/// The layout as a JSON file, for export.
private struct LayoutDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    let config: PanelConfig

    init(config: PanelConfig) { self.config = config }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        config = try PanelConfig.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try config.encoded())
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
