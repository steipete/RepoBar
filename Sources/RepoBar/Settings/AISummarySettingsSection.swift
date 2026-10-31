import RepoBarCore
import SwiftUI

struct AISummarySettingsSection: View {
    @Bindable var session: Session
    let appState: AppState
    @State private var apiKey = ""
    @State private var keyStatus = OpenAIAPIKeySource.missing.label
    @State private var baseURLDraft = ""
    @State private var compatibleModelDraft = ""
    @State private var endpointStatus: String?
    @State private var isTesting = false
    @State private var testStatus: String?

    private var provider: AISummaryProvider {
        self.session.settings.aiSummaries.provider
    }

    var body: some View {
        Section {
            Toggle("Summarize Issue Navigator items", isOn: self.$session.settings.aiSummaries.enabled)
                .onChange(of: self.session.settings.aiSummaries.enabled) { _, _ in
                    self.appState.persistSettings()
                }

            Picker("Provider", selection: self.providerBinding) {
                ForEach(AISummaryProvider.allCases, id: \.self) { provider in
                    Text(provider.label).tag(provider)
                }
            }
            .pickerStyle(.menu)

            switch self.provider {
            case .openAI:
                self.openAIModelPicker
            case .openAICompatible:
                self.compatibleEndpointFields
            }

            self.apiKeyRow

            Text(self.keyStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let endpointStatus {
                Text(endpointStatus)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let testStatus {
                Text(testStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("AI Summaries")
        } footer: {
            Text(self.footerText)
        }
        .onAppear {
            self.baseURLDraft = self.session.settings.aiSummaries.compatibleBaseURL
            self.compatibleModelDraft = self.session.settings.aiSummaries.compatibleModel
            self.refreshKeyStatus()
        }
    }

    private var openAIModelPicker: some View {
        HStack {
            Text("Model")
            Spacer()
            Picker("", selection: self.openAIModelBinding) {
                ForEach(AISummarySettings.modelOptions) { option in
                    Text(option.label).tag(option.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    @ViewBuilder
    private var compatibleEndpointFields: some View {
        TextField("Base URL", text: self.$baseURLDraft, prompt: Text("https://gateway.example/v1"))
            .onSubmit { self.commitCompatibleEndpoint() }
        TextField("Model", text: self.$compatibleModelDraft, prompt: Text("model-id"))
            .onSubmit { self.commitCompatibleEndpoint() }
    }

    private var apiKeyRow: some View {
        HStack(spacing: 8) {
            Text(self.provider == .openAI ? "OpenAI API key" : "API key")
                .fixedSize()
            Spacer(minLength: 12)
            SecureField("API key", text: self.$apiKey)
                .frame(width: 240)
                .layoutPriority(1)
            Button {
                self.saveAPIKey()
            } label: {
                Image(systemName: "tray.and.arrow.down")
            }
            .buttonStyle(.borderless)
            .disabled(self.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Save API key")
            Button {
                Task { await self.testSummary() }
            } label: {
                if self.isTesting {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "play.fill")
                }
            }
            .buttonStyle(.borderless)
            .disabled(self.isTesting)
            .help("Test AI summaries")
            Button {
                self.clearAPIKey()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Clear stored API key")
        }
    }

    private var footerText: String {
        switch self.provider {
        case .openAI:
            "Uses the stored key first, then OPENAI_API_KEY or REPOBAR_OPENAI_API_KEY from the app environment."
        case .openAICompatible:
            "Sends summaries to a server that implements the OpenAI Responses API, such as a LiteLLM gateway. "
                + "Uses its own stored key; the OpenAI key is never sent to this endpoint. Press Return to apply edits."
        }
    }

    private var providerBinding: Binding<AISummaryProvider> {
        Binding(
            get: { self.session.settings.aiSummaries.provider },
            set: { newValue in
                self.session.settings.aiSummaries.provider = newValue
                self.appState.persistSettings()
                self.apiKey = ""
                self.testStatus = nil
                self.endpointStatus = nil
                self.refreshKeyStatus()
            }
        )
    }

    private var openAIModelBinding: Binding<String> {
        Binding(
            get: { AISummarySettings.normalizedModel(self.session.settings.aiSummaries.model) },
            set: { newValue in
                self.session.settings.aiSummaries.model = AISummarySettings.normalizedModel(newValue)
                self.appState.persistSettings()
            }
        )
    }

    @discardableResult
    private func commitCompatibleEndpoint() -> Bool {
        let model = self.compatibleModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let url = try AISummaryEndpoint.validatedBaseURL(self.baseURLDraft)
            self.session.settings.aiSummaries.compatibleBaseURL = url.absoluteString
            self.session.settings.aiSummaries.compatibleModel = model
            self.appState.persistSettings()
            self.baseURLDraft = url.absoluteString
            self.compatibleModelDraft = model
            self.endpointStatus = model.isEmpty ? AISummaryEndpointError.missingModel.localizedDescription : nil
            return model.isEmpty == false
        } catch {
            self.endpointStatus = error.localizedDescription
            return false
        }
    }

    private func refreshKeyStatus() {
        self.keyStatus = self.appState.aiSummaryAPIKeySource(for: self.provider).label
    }

    private func saveAPIKey() {
        do {
            try self.appState.saveAISummaryAPIKey(self.apiKey, for: self.provider)
            self.apiKey = ""
            self.refreshKeyStatus()
        } catch {
            self.keyStatus = "Save failed: \(error.localizedDescription)"
        }
    }

    private func clearAPIKey() {
        self.appState.clearAISummaryAPIKey(for: self.provider)
        self.apiKey = ""
        self.refreshKeyStatus()
    }

    private func testSummary() async {
        self.testStatus = nil
        if self.provider == .openAICompatible, self.commitCompatibleEndpoint() == false {
            return
        }

        self.isTesting = true
        defer { self.isTesting = false }

        do {
            let typedKey = self.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let keyOverride = typedKey.isEmpty ? nil : typedKey
            let summary = try await PullRequestAISummarizer().test(
                settings: self.session.settings.aiSummaries,
                apiKeyOverride: keyOverride
            )
            let suffix = typedKey.isEmpty ? "" : " Typed key was not saved."
            self.testStatus = "Test passed: \(summary)\(suffix)"
        } catch {
            self.testStatus = "Test failed: \(error.localizedDescription)"
        }
    }
}
