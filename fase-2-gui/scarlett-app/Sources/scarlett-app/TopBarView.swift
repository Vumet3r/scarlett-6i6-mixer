import SwiftUI

struct TopBarView: View {
    @EnvironmentObject var vm: ScarlettViewModel
    var onPresets: () -> Void
    @State private var flashBusy = false
    @State private var flashOK: Bool?

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(vm.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(vm.isConnected ? "Connected" : "Disconnected")
                    .font(ScarlettUI.title(10))
                    .foregroundStyle(.white)
            }
            .help(vm.lastError ?? "")

            Spacer()

            Button {
                onPresets()
            } label: {
                Label("Presets", systemImage: "bookmark")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                flashBusy = true
                Task { @MainActor in
                    flashOK = await vm.saveToHardware()
                    flashBusy = false
                    if flashOK == true {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        flashOK = nil
                    }
                }
            } label: {
                if flashBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Label(flashOK == true ? "Saved to hardware" : "Save to hardware",
                          systemImage: "memorychip")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(flashBusy)
            .help("Persist current mixer settings to the device flash")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(ScarlettUI.panelFill)
    }
}