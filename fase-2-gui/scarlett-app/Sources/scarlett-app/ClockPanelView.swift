import SwiftUI

struct ClockPanelView: View {
    @EnvironmentObject var vm: ScarlettViewModel
    var onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionTitle(text: "CLOCK & DEVICE")

            HStack {
                Text("Rate")
                    .font(ScarlettUI.title(10))
                    .foregroundStyle(ScarlettUI.secondaryText)
                Spacer()
                Picker("", selection: Binding(
                    get: { "\(vm.state.rate)" },
                    set: { vm.setSampleRate(Int($0) ?? 44100) }
                )) {
                    Text("44.1 kHz").tag("44100")
                    Text("48 kHz").tag("48000")
                    Text("88.2 kHz").tag("88200")
                    Text("96 kHz").tag("96000")
                }
                .pickerStyle(.menu)
                .controlSize(.mini)
                .fixedSize()
                .chipStyle()
            }

            HStack {
                Text("Clock")
                    .font(ScarlettUI.title(10))
                    .foregroundStyle(ScarlettUI.secondaryText)
                Spacer()
                Picker("", selection: Binding(
                    get: { vm.state.clock },
                    set: { vm.setClockSource($0) }
                )) {
                    Text("Internal").tag("Internal")
                    Text("S/PDIF").tag("S/PDIF")
                    Text("ADAT").tag("ADAT")
                }
                .pickerStyle(.menu)
                .controlSize(.mini)
                .fixedSize()
                .chipStyle()
            }

            clockRow("Sync", vm.state.sync, dot: vm.state.sync == "Locked" ? .green : .red)
            clockRow("Driver", "USB 2.0", accent: .green)
            clockRow("Model", "Scarlett 6i6")

            Spacer()

            Button("Settings...") { onSettings() }
                .font(.system(size: 7)).buttonStyle(.bordered)
                .controlSize(.mini).frame(maxWidth: .infinity)
        }
    }

    private func clockRow(_ label: String, _ value: String, dot: Color? = nil, accent: Color? = nil) -> some View {
        HStack {
            Text(label)
                .font(ScarlettUI.title(10))
                .foregroundStyle(ScarlettUI.secondaryText)
            Spacer()
            if let d = dot {
                Circle().fill(d).frame(width: 5, height: 5)
            }
            Text(value)
                .font(ScarlettUI.mono(11))
                .foregroundStyle(accent ?? .white)
        }
    }
}
