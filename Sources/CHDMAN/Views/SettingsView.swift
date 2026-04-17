import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var vm: AppViewModel
    @State private var draftPath: String = ""

    var body: some View {
        Form {
            // ── chdman path ───────────────────────────────────────────────────
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Custom chdman path")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                        Text("Leave blank to auto-detect: Homebrew → /usr/local/bin → PATH")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        TextField("/opt/homebrew/bin/chdman", text: $draftPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        Button("Browse…") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = true
                            panel.canChooseDirectories = false
                            panel.allowsMultipleSelection = false
                            panel.message = "Select the chdman executable"
                            if panel.runModal() == .OK, let url = panel.url {
                                draftPath = url.path
                            }
                        }
                    }

                    HStack {
                        Button("Save") {
                            vm.customChdmanPath = draftPath
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Clear") {
                            draftPath = ""
                            vm.customChdmanPath = ""
                        }

                        Spacer()

                        if !vm.customChdmanPath.isEmpty {
                            Label("Saved", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        } else {
                            Label("Auto-detect active", systemImage: "magnifyingglass")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Label("chdman Executable", systemImage: "wrench.and.screwdriver")
            }

            // ── Conversion options ────────────────────────────────────────────
            Section {
                Toggle(isOn: $vm.deleteSourceAfterConversion) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Delete source files after conversion")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                        Text("Removes original ISO/CUE/BIN/GDI files after successful CHD creation")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $vm.notifyOnCompletion) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Notify when batch completes")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                        Text("Send a macOS notification when all jobs finish")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Label("Conversion Options", systemImage: "slider.horizontal.3")
            }

            // ── Detected capabilities ─────────────────────────────────────────
            Section {
                if let caps = vm.chdmanCapabilities {
                    VStack(alignment: .leading, spacing: 8) {
                        capRow("createcd",  available: caps.hasCreateCD,
                               note: "CUE/BIN, GDI, and ISO fallback")
                        capRow("createdvd", available: caps.hasCreateDVD,
                               note: "Preferred for ISO disc images")
                    }
                } else {
                    Text("Run a conversion to detect capabilities.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("Detected Capabilities", systemImage: "cpu")
            }

            // ── Install hint ──────────────────────────────────────────────────
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("If chdman is not installed, run in Terminal:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("brew install rom-tools")
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .textBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                        )
                        .textSelection(.enabled)
                }
            } header: {
                Label("Installation", systemImage: "terminal")
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 500, height: 520)
        .onAppear { draftPath = vm.customChdmanPath }
    }

    @ViewBuilder
    private func capRow(_ command: String, available: Bool, note: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(available ? Color.green : Color.red)
            Text(command)
                .font(.system(.body, design: .monospaced).weight(.semibold))
            Text("·")
                .foregroundStyle(.tertiary)
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
