import AppKit
import HAKit
import SwiftUI

/// First run: find Home Assistant, add a token, choose rooms from Areas.
struct SetupWizard: View {
    @Environment(AppModel.self) private var app
    /// Start at the server step even when a token is saved (Run Setup Again).
    var startAtServer = false
    let onClose: () -> Void

    enum Step: Int, CaseIterable { case server, token, rooms, done }

    @State private var step: Step = .server
    @State private var discovery = HADiscovery()
    @State private var urlString = SharedConfig.baseURLString
    @State private var token = ""
    @State private var connecting = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "house.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Set up HomePanel").font(.title2.bold())
                    Text("Step \(step.rawValue + 1) of \(Step.allCases.count)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if step != .done {
                    Button("Skip") { onClose() }
                        .buttonStyle(.borderless)
                        .help("Set things up later in Settings")
                }
            }
            Divider()
            Group {
                switch step {
                case .server: serverStep
                case .token: tokenStep
                case .rooms:
                    AreaPicker(addLabel: "Create Rooms") { step = .done }
                        .padding(-20)
                case .done: doneStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(24)
        .frame(width: 560, height: 520)
        .onAppear {
            // Already connected before (token saved) but no rooms yet: go straight to rooms.
            if TokenStore.hasToken && !startAtServer { step = .rooms } else { discovery.start() }
        }
        .onDisappear { discovery.stop() }
    }

    // MARK: Server

    private var serverStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where is your Home Assistant?").font(.headline)
            if discovery.servers.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking on your network…").foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 2) {
                    ForEach(discovery.servers) { server in
                        Button {
                            urlString = server.url
                        } label: {
                            HStack {
                                Image(systemName: "server.rack")
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(server.name)
                                    Text([server.url, server.version.map { "HA \($0)" }].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if urlString == server.url { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                            .padding(8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(urlString == server.url ? 0.08 : 0)))
                    }
                }
            }
            TextField("URL", text: $urlString, prompt: Text(SharedConfig.exampleBaseURL))
                .textFieldStyle(.roundedBorder)
            Text("Pick a server found on your network, or type its address.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            HStack {
                Spacer()
                Button("Continue") {
                    SharedConfig.baseURLString = urlString
                    step = .token
                }
                .keyboardShortcut(.defaultAction)
                .disabled(SharedConfig.validatedURL(urlString) == nil)
            }
        }
    }

    // MARK: Token

    private var tokenStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add an access token").font(.headline)
            Text("In Home Assistant, open your profile → Security → Long-lived access tokens → Create token, then paste it here. It's stored in your Keychain.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let url = SharedConfig.validatedURL(urlString) {
                Link("Open my Home Assistant profile", destination: url.appending(path: "profile/security"))
                    .font(.callout)
            }
            SecureField("Access token", text: $token)
                .textFieldStyle(.roundedBorder)
            if let error {
                Label(error, systemImage: "xmark.octagon.fill").foregroundStyle(.red).font(.callout)
            }
            Spacer()
            HStack {
                Button("Back") { step = .server }
                Spacer()
                if connecting { ProgressView().controlSize(.small) }
                if TokenStore.hasToken {
                    Button("Keep Current Token") {
                        SharedConfig.baseURLString = urlString
                        app.settingsChanged()
                        step = .rooms
                    }
                }
                Button("Connect", action: connect)
                    .keyboardShortcut(.defaultAction)
                    .disabled(token.isEmpty || connecting)
            }
        }
    }

    private func connect() {
        guard let url = SharedConfig.validatedURL(urlString) else { return }
        let candidate = token.trimmingCharacters(in: .whitespacesAndNewlines)
        connecting = true
        error = nil
        Task {
            do {
                _ = try await HARest(baseURL: url, token: candidate).serverInfo()
                try TokenStore.save(candidate)
                token = ""
                SharedConfig.baseURLString = urlString
                app.settingsChanged()
                step = .rooms
            } catch {
                self.error = HAErrorText.describe(error)
            }
            connecting = false
        }
    }

    // MARK: Done

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text("Your panel is ready").font(.headline)
            Text("Click the house in the menu bar to open it. Change rooms and devices any time in Settings → Rooms.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            HStack {
                Spacer()
                Button("Done", action: onClose).keyboardShortcut(.defaultAction)
            }
        }
    }
}
