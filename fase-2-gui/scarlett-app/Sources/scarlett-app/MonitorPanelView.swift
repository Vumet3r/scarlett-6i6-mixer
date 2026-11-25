import SwiftUI

struct MonitorPanelView: View {
    @EnvironmentObject var vm: ScarlettViewModel
    @State private var dragStartVolume: Float?
    @State private var isDragging = false

    var body: some View {
        let norm = max(0, min(1, CGFloat(vm.state.masterVolume + 128) / 128.0))

        VStack(spacing: 6) {
            SectionTitle(text: "MONITOR CONTROL")

            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color(red: 0.10, green: 0.11, blue: 0.13), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .frame(width: 42, height: 42)
                    .rotationEffect(.degrees(135))

                Circle()
                    .trim(from: 0, to: norm * 0.75)
                    .stroke(
                        isDragging ? Color(red: 1.0, green: 0.22, blue: 0.28) : ScarlettUI.scarlettRed,
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                    )
                    .frame(width: 42, height: 42)
                    .rotationEffect(.degrees(135))
                    .shadow(color: isDragging ? ScarlettUI.scarlettRed.opacity(0.6) : .clear, radius: 4)

                VStack(spacing: 1) {
                    Text("MON")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(ScarlettUI.textMuted)
                    Text(ScarlettViewModel.volumeDBString(vm.state.masterVolume))
                        .font(ScarlettUI.mono(8, .bold))
                        .foregroundStyle(ScarlettUI.textPrimary)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Circle())
            .onTapGesture(count: 2) {
                vm.setVolume(0)
            }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { v in
                        if dragStartVolume == nil {
                            dragStartVolume = vm.state.masterVolume
                            isDragging = true
                        }
                        let start = dragStartVolume ?? vm.state.masterVolume
                        let deltaDB = Float(-v.translation.height + v.translation.width * 0.5) * 0.8
                        let targetDB = max(-128, min(0, Int((start + deltaDB).rounded())))
                        if targetDB != Int(vm.state.masterVolume.rounded()) {
                            vm.setVolume(targetDB)
                        }
                    }
                    .onEnded { _ in
                        dragStartVolume = nil
                        isDragging = false
                    }
            )
            .help("Drag up/down to adjust Monitor volume · Double-click for 0 dB")

            HStack(spacing: 4) {
                ToggleButton(label: "Dim", isOn: vm.state.dim, onColor: .orange, offColor: ScarlettUI.textMuted, minWidth: 40, height: 18) {
                    vm.toggleDim()
                }
                ToggleButton(label: "0dB", isOn: vm.state.masterVolume == 0, onColor: ScarlettUI.amber, offColor: ScarlettUI.textMuted, minWidth: 40, height: 18) {
                    vm.setVolume(0)
                }
            }

            HStack(spacing: 4) {
                ToggleButton(label: "Mute", isOn: vm.state.masterMute, onColor: ScarlettUI.scarlettRed, offColor: ScarlettUI.textMuted, minWidth: 36, height: 18) {
                    vm.setMute(!vm.state.masterMute)
                }
                ToggleButton(label: "L", isOn: vm.monitorSoloLeft, onColor: .cyan, offColor: ScarlettUI.textMuted, minWidth: 20, height: 18) {
                    vm.toggleMonitorSoloLeft()
                }
                ToggleButton(label: "R", isOn: vm.monitorSoloRight, onColor: .cyan, offColor: ScarlettUI.textMuted, minWidth: 20, height: 18) {
                    vm.toggleMonitorSoloRight()
                }
            }
        }
        .padding(10)
        .cardStyle(radius: 6)
    }
}
