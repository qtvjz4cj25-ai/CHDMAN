import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var vm: AppViewModel
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {

            // ── Toolbar ───────────────────────────────────────────────────────
            toolbarView
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(toolbarBackground)

            Divider().overlay(Color.primary.opacity(0.08))

            // ── File list ─────────────────────────────────────────────────────
            ZStack {
                FileListView()
                    .frame(minHeight: 180)

                // Drop overlay
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.accentColor, lineWidth: 2.5)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.accentColor.opacity(0.07))
                        )
                        .overlay(
                            Label("Drop folder to set scan target", systemImage: "folder.badge.plus")
                                .font(.title3.weight(.medium))
                                .foregroundStyle(Color.accentColor)
                        )
                        .padding(6)
                        .allowsHitTesting(false)
                }
            }
            .onDrop(
                of: [UTType.folder, UTType.fileURL],
                isTargeted: $isDropTargeted,
                perform: handleDrop
            )

            Divider().overlay(Color.primary.opacity(0.08))

            // ── Conversion controls ───────────────────────────────────────────
            conversionControlsView
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(toolbarBackground)

            Divider().overlay(Color.primary.opacity(0.08))

            // ── Progress + counts ─────────────────────────────────────────────
            progressView
                .padding(.horizontal, 14)
                .padding(.vertical, 7)

            Divider().overlay(Color.primary.opacity(0.08))

            // ── Log panel ─────────────────────────────────────────────────────
            LogPanelView(
                log: vm.globalLog,
                autoScroll: $vm.autoScrollLog,
                onOpenFile: { vm.openLogFile() }
            )
            .frame(minHeight: 130, idealHeight: 170)
        }
        .alert("chdman not available", isPresented: $vm.showChdmanAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.chdmanAlertMessage)
        }
        .alert("chdman not found", isPresented: $vm.chdmanMissing) {
            Button("Copy Homebrew Command") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("brew install rom-tools", forType: .string)
            }
            Button("Download from MAME") {
                if let url = URL(string: "https://www.mamedev.org/release.html") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Open Settings") {
                // SettingsLink can't be used inside alerts; selector is the only option here
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            Button("Dismiss", role: .cancel) {}
        } message: {
            Text("chdman is required but was not found on this system.\n\nOption 1 — Homebrew (requires brew.sh):\nbrew install rom-tools\n\nOption 2 — Download MAME (includes chdman), then set the path in Settings.\n\nDon't have Homebrew? Visit brew.sh to install it first, or use Option 2.")
        }
        .task {
            await vm.checkChdmanAvailability()
        }
    }

    // MARK: - Toolbar background

    private var toolbarBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            Color.primary.opacity(0.018)
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbarView: some View {
        HStack(spacing: 8) {

            // Folder picker + drop hint
            Button {
                vm.selectFolder()
            } label: {
                Label("Choose Folder…", systemImage: "folder.badge.plus")
                    .fontWeight(.medium)
            }
            .help("Select a folder, or drag one from Finder onto the file list")

            // Folder path chip
            if let folder = vm.selectedFolder {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text(folder.lastPathComponent)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(Color.primary.opacity(0.06))
                )
                .help(folder.path)
                .lineLimit(1)
                .frame(maxWidth: 240, alignment: .leading)
                .truncationMode(.middle)
            } else {
                Text("Drop a folder here or use Choose Folder")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Recursive toggle
            Toggle(isOn: $vm.isRecursive) {
                Label("Recursive", systemImage: "arrow.trianglehead.2.counterclockwise.rotate.90")
                    .font(.caption)
            }
            .toggleStyle(.checkbox)
            .disabled(vm.isConverting)

            Divider().frame(height: 18)

            // Scan
            Button {
                Task { await vm.scan() }
            } label: {
                if vm.isScanning {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.mini)
                        Text("Scanning…")
                    }
                } else {
                    Label("Scan", systemImage: "magnifyingglass")
                }
            }
            .disabled(!vm.canScan)
            .help("Scan the selected folder for ISO, CUE, and GDI files")

            // Clear list
            Button {
                vm.clearList()
            } label: {
                Image(systemName: "trash")
            }
            .disabled(!vm.canClearList)
            .help("Remove all items from the list")
        }
    }

    // MARK: - Conversion controls

    @ViewBuilder
    private var conversionControlsView: some View {
        HStack(spacing: 10) {

            // Parallel jobs
            HStack(spacing: 5) {
                Image(systemName: "cpu")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Slider(value: Binding(
                    get: { Double(vm.parallelJobs) },
                    set: { vm.parallelJobs = Int($0) }
                ), in: 1...8, step: 1)
                .frame(width: 100)
                .disabled(vm.isConverting)
                Text("\(vm.parallelJobs) job\(vm.parallelJobs == 1 ? "" : "s")")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 40, alignment: .leading)
            }
            .help("Parallel conversion jobs (capped at active CPU count)")

            Divider().frame(height: 18)

            // Start
            Button {
                Task { await vm.startConversion() }
            } label: {
                Label("Start", systemImage: "play.fill")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(nsColor: .systemGreen).opacity(0.85))
            .disabled(!vm.canStart)
            .keyboardShortcut("s", modifiers: [.command])

            // Pause
            Button {
                vm.pauseConversion()
            } label: {
                Label("Pause", systemImage: "pause.fill")
            }
            .disabled(!vm.canPause)

            // Resume
            Button {
                vm.resumeConversion()
            } label: {
                Label("Resume", systemImage: "play.fill")
            }
            .disabled(!vm.canResume)

            // Cancel
            Button {
                vm.cancelConversion()
            } label: {
                Label("Cancel", systemImage: "stop.fill")
            }
            .tint(.red)
            .disabled(!vm.canCancel)
            .keyboardShortcut(".", modifiers: [.command])

            Spacer()

            // Capabilities badge
            if let caps = vm.chdmanCapabilities {
                HStack(spacing: 4) {
                    capBadge("createcd",  available: caps.hasCreateCD)
                    capBadge("createdvd", available: caps.hasCreateDVD)
                }
            }

            // Settings
            if #available(macOS 14.0, *) {
                SettingsLink {
                    Image(systemName: "gear")
                }
                .help("Settings — configure chdman path")
            } else {
                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Image(systemName: "gear")
                }
                .help("Settings — configure chdman path")
            }
        }
    }

    @ViewBuilder
    private func capBadge(_ label: String, available: Bool) -> some View {
        Text(label)
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(available ? Color.green : Color.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(available
                          ? Color.green.opacity(0.12)
                          : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(available
                                  ? Color.green.opacity(0.3)
                                  : Color.primary.opacity(0.1),
                                  lineWidth: 0.5)
            )
    }

    // MARK: - Progress and counts

    @ViewBuilder
    private var progressView: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                ProgressView(value: vm.progress)
                    .progressViewStyle(.linear)
                    .tint(progressTint)
                    .animation(.easeInOut(duration: 0.25), value: vm.progress)

                if let eta = vm.estimatedTimeRemaining {
                    Text("~\(eta) remaining")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 6) {
                countChip("\(vm.totalCount)",     icon: "tray.full",         tip: "Total",     color: .secondary)
                countChip("\(vm.doneCount)",      icon: "checkmark.circle",  tip: "Done",      color: .green)
                countChip("\(vm.failedCount)",    icon: "xmark.circle",      tip: "Failed",    color: .red)
                countChip("\(vm.skippedCount)",   icon: "forward.circle",    tip: "Skipped",   color: .orange)
                countChip("\(vm.cancelledCount)", icon: "stop.circle",       tip: "Cancelled", color: .purple)
            }
        }
    }

    private var progressTint: Color {
        if vm.failedCount > 0 && vm.doneCount == 0 { return .red }
        if vm.failedCount > 0 { return .orange }
        return .accentColor
    }

    @ViewBuilder
    private func countChip(_ value: String, icon: String, tip: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(color == .secondary ? Color.primary : color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(color == .secondary
                      ? Color.primary.opacity(0.05)
                      : color.opacity(0.08))
        )
        .help(tip)
    }

    // MARK: - Drop handler

    @MainActor
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        // Try folder UTType first (clean Finder drag)
        if provider.hasItemConformingToTypeIdentifier(UTType.folder.identifier) {
            _ = provider.loadInPlaceFileRepresentation(
                forTypeIdentifier: UTType.folder.identifier
            ) { url, _, _ in
                guard let url else { return }
                Task { @MainActor in vm.selectedFolder = url }
            }
            return true
        }

        // Fall back to generic fileURL (some drag sources)
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil, isAbsolute: true)
                else { return }
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                guard isDir.boolValue else { return }
                Task { @MainActor in vm.selectedFolder = url }
            }
            return true
        }

        return false
    }
}
