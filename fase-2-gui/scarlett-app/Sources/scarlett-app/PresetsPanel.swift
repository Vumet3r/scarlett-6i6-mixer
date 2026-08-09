import SwiftUI

struct PresetsPanel: View {
    @EnvironmentObject var vm: ScarlettViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var capturing = false
    @State private var confirmDelete: ScarlettPreset?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Presets").font(.title3.bold())
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 8) {
                NativeTextField(text: $newName,
                                placeholder: "Preset name",
                                autoFocus: true,
                                onSubmit: { save() })
                    .frame(maxWidth: 260)
                Button {
                    save()
                } label: {
                    Label("Save", systemImage: "bookmark.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || capturing)
                .help("Captures routing, matrix gains, preamps, faders and monitor state")

                Button {
                    exportPreset()
                } label: {
                    Label("Export…", systemImage: "square.and.arrow.up")
                }

                Button {
                    importPreset()
                } label: {
                    Label("Import…", systemImage: "square.and.arrow.down")
                }
            }

            Divider()

            if vm.presets.isEmpty {
                Text("No presets yet — save one above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(vm.presets.sorted(by: { $0.createdAt > $1.createdAt })) { preset in
                            presetRow(preset)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 460, height: 420)
        .background(ScarlettUI.panelBackground)
        .confirmationDialog(
            "Delete preset?",
            isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let p = confirmDelete {
                Button("Delete \"\(p.name)\"", role: .destructive) {
                    vm.deletePreset(p)
                    confirmDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        }
    }

    private func save() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        capturing = true
        Task { @MainActor in
            await vm.capturePreset(name: name)
            capturing = false
            newName = ""
        }
    }

    private func exportPreset() {
        guard !vm.presets.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "scarlett-\(newName.isEmpty ? "snapshot" : newName).6i6.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let preset = vm.presets.sorted(by: { $0.createdAt > $1.createdAt })[0]
        try? vm.exportPreset(preset, to: url)
    }

    private func importPreset() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        vm.importPreset(from: url)
        newName = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: ".6i6", with: "")
            .replacingOccurrences(of: ".scarlett", with: "")
    }

    private func presetRow(_ preset: ScarlettPreset) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(preset.name).font(.subheadline.bold())
                Text(Self.dateFormatter.string(from: preset.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Load") {
                vm.loadPreset(preset)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Push this preset to the device")
            Button {
                exportPreset(preset)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Export preset to file")
            Button {
                confirmDelete = preset
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Delete preset")
        }
        .padding(8)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func exportPreset(_ preset: ScarlettPreset) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(preset.name) 6i6.json".replacingOccurrences(of: " ", with: "-")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? vm.exportPreset(preset, to: url)
    }
}