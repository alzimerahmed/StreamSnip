//
//  AddJellyfinView.swift
//  StreamSnip
//
//  View for adding a Jellyfin server as a source, with optional sign-in.
//

import SwiftUI

struct AddJellyfinView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnvironment) private var appEnvironment

    // MARK: - State

    @State private var urlString = ""
    @State private var name = ""
    @State private var allowInvalidCertificates = false
    @State private var username = ""
    @State private var password = ""

    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var addedInstance: Instance?

    /// Closure to dismiss the parent sheet
    var dismissSheet: DismissAction?

    private var canAdd: Bool {
        !urlString.isEmpty
    }

    private var canSignIn: Bool {
        !username.isEmpty && !password.isEmpty
    }

    // MARK: - Body

    var body: some View {
        Form {
            urlSection
            nameSection
            securitySection
            signInSection
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            actionSection
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .navigationTitle(String(localized: "sources.addJellyfin", defaultValue: "Add Jellyfin"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Sections

    private var urlSection: some View {
        Section {
            #if os(macOS)
            LabeledContent(String(localized: "sources.field.url")) {
                TextField("", text: $urlString, prompt: Text(String(localized: "sources.placeholder.jellyfinUrl", defaultValue: "http://jellyfin.local:8096")))
                    .textContentType(.URL)
                    .autocorrectionDisabled()
            }
            #else
            TextField(String(localized: "sources.placeholder.jellyfinUrl", defaultValue: "http://jellyfin.local:8096"), text: $urlString)
                .textContentType(.URL)
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
            #endif
        } footer: {
            Text(String(localized: "sources.footer.jellyfin", defaultValue: "The base URL of your Jellyfin server, including the port."))
        }
    }

    private var nameSection: some View {
        Section {
            #if os(macOS)
            LabeledContent(String(localized: "sources.field.name")) {
                TextField("", text: $name, prompt: Text(String(localized: "sources.field.nameOptional")))
            }
            #else
            TextField(String(localized: "sources.field.nameOptional"), text: $name)
            #endif
        } header: {
            Text(String(localized: "sources.header.displayName"))
        }
    }

    private var securitySection: some View {
        Section {
            Toggle(String(localized: "sources.field.allowInvalidCertificates"), isOn: $allowInvalidCertificates)
        } header: {
            Text(String(localized: "sources.header.security"))
        } footer: {
            Text(String(localized: "sources.footer.allowInvalidCertificates"))
        }
    }

    private var signInSection: some View {
        Section {
            #if os(macOS)
            LabeledContent(String(localized: "sources.field.username")) {
                TextField("", text: $username)
                    .textContentType(.username)
                    .autocorrectionDisabled()
            }
            LabeledContent(String(localized: "sources.field.password")) {
                SecureField("", text: $password)
                    .textContentType(.password)
            }
            #else
            TextField(String(localized: "sources.field.username"), text: $username)
                .textContentType(.username)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
            SecureField(String(localized: "sources.field.password"), text: $password)
                .textContentType(.password)
            #endif
        } header: {
            Text(String(localized: "sources.header.jellyfinSignIn", defaultValue: "Sign In (Optional)"))
        } footer: {
            Text(String(localized: "sources.footer.jellyfinSignIn", defaultValue: "Sign in to browse your server's latest and continue-watching items. You can skip this and browse anonymously."))
        }
    }

    private var actionSection: some View {
        Section {
            Button {
                addSource()
            } label: {
                if isConnecting {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(String(localized: "sources.connecting", defaultValue: "Connecting…"))
                    }
                } else {
                    Text(String(localized: "sources.addSource"))
                }
            }
            .disabled(!canAdd || isConnecting)
        }
    }

    // MARK: - Actions

    private func addSource() {
        guard let appEnvironment else { return }
        guard let url = Instance.normalizeSourceURL(urlString) else {
            errorMessage = String(localized: "sources.error.invalidURL", defaultValue: "That doesn't look like a valid server address.")
            return
        }

        isConnecting = true
        errorMessage = nil

        let instance = Instance(
            type: .jellyfin,
            url: url,
            name: name.isEmpty ? nil : name,
            allowInvalidCertificates: allowInvalidCertificates
        )

        Task { @MainActor in
            defer { isConnecting = false }

            // When credentials were entered, validate them before the source
            // is added: a server that rejects the login should not end up in
            // the list looking signed in.
            if canSignIn {
                do {
                    let credential = try await appEnvironment.contentService.jellyfinLogin(
                        username: username,
                        password: password,
                        instance: instance
                    )
                    appEnvironment.instancesManager.add(instance)
                    appEnvironment.jellyfinCredentialsManager.setCredential(credential, for: instance)
                } catch {
                    errorMessage = String(localized: "sources.error.jellyfinSignIn", defaultValue: "Sign-in failed. Check the address and credentials, or add the server without signing in.")
                    return
                }
            } else {
                appEnvironment.instancesManager.add(instance)
            }

            addedInstance = instance
            (dismissSheet ?? dismiss)()
        }
    }
}
