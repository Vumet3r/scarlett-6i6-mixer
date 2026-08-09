import SwiftUI

struct MonitorPanelView: View {
    @EnvironmentObject var vm: ScarlettViewModel

    var body: some View {
        VStack(spacing: 2) {
            SectionTitle(text: "MONITOR")

            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.25), lineWidth: 3)
                    .frame(width: 44, height: 44)
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(ScarlettUI.accent, lineWidth: 3)
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(135))
                Circle()
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 20, height: 20)
                Text("VOL").font(ScarlettUI.title(7, .bold))
            }

            HStack(spacing: 3) {
                monButton("Dim", .orange)
                monButton("0dB", .gray)
            }

            HStack(spacing: 3) {
                monButton("Mute", .red)
                monButton("L", .gray)
                monButton("R", .gray)
            }
        }
    }

    private func monButton(_ label: String, _ tint: Color) -> some View {
        Button(label) {
            switch label {
            case "Mute": vm.setMute(!vm.state.masterMute)
            case "Dim": vm.toggleDim()
            case "0dB": vm.setVolume(0)
            case "L": vm.monitorSoloLeft.toggle()
            case "R": vm.monitorSoloRight.toggle()
            default: break
            }
        }
        .font(ScarlettUI.title(10, .semibold))
        .buttonStyle(.bordered)
        .tint(
            label == "Mute" && vm.state.masterMute ? .red :
            label == "Dim" && vm.state.dim ? .orange :
            label == "L" && vm.monitorSoloLeft ? .cyan :
            label == "R" && vm.monitorSoloRight ? .cyan :
            tint
        )
        .controlSize(.mini)
    }
}
