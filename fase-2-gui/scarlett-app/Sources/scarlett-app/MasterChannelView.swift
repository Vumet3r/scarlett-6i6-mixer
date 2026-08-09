import SwiftUI

struct MasterChannelView: View {
    @EnvironmentObject var vm: ScarlettViewModel
    var onCopyMix: () -> Void

    var body: some View {
        VStack(spacing: 3) {
            Text("Master")
                .font(ScarlettUI.title(12))
                .padding(.bottom, 4)

            Color.clear.frame(height: 42)

            HStack(spacing: 3) {
                HStack(spacing: 2) {
                    MeterBar(level: masterMeterLeft, color: .orange, hold: vm.meterHoldLevel(vm.meters.count >= 2 ? vm.meters.count - 2 : 0)) {
                    vm.resetMeterHold(vm.meters.count >= 2 ? vm.meters.count - 2 : 0)
                }
                    MeterBar(level: masterMeterRight, color: .orange, hold: vm.meterHoldLevel(vm.meters.count > 0 ? vm.meters.count - 1 : 0)) {
                        vm.resetMeterHold(vm.meters.count > 0 ? vm.meters.count - 1 : 0)
                    }
                }
                .frame(height: 160)

                Fader(position: masterFaderPos, onChange: { position in
                    vm.setVolume(masterDB(for: position))
                }) {
                    vm.setVolume(0)
                }
                .frame(width: 34, height: 160)
            }

            Text(ScarlettViewModel.volumeDBString(vm.state.masterVolume))
                .font(ScarlettUI.mono(11))
                .foregroundColor(.secondary)

            Toggle(isOn: Binding(
                get: { vm.state.masterMute },
                set: { vm.setMute($0) }
            )) { Text("M").font(ScarlettUI.title(9, .bold)) }
            .toggleStyle(.button)
            .tint(vm.state.masterMute ? .red : ScarlettUI.off)
            .controlSize(.mini)

            Button("Copy Mix To...") { onCopyMix() }
                .font(ScarlettUI.title(10))
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .frame(height: 20)

            Text("Master")
                .font(ScarlettUI.title(10))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(ScarlettUI.panelFill)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(ScarlettUI.accent.opacity(0.65), lineWidth: 1.5))
        )
    }

    private var masterFaderPos: CGFloat {
        CGFloat(vm.state.masterVolume + 128) / 128 * 0.75
    }

    private func masterDB(for position: CGFloat) -> Int {
        let dB = position <= 0.75 ? -128 + (position / 0.75) * 128 : 0
        return Int(dB.rounded())
    }

    private var masterMeterLevel: CGFloat {
        guard !vm.meters.isEmpty else { return 0 }
        return min(1, CGFloat(vm.meters.max() ?? 0) / 65535)
    }

    private var masterMeterLeft: CGFloat {
        guard vm.meters.count >= 2 else { return masterMeterLevel }
        return CGFloat(vm.meters[vm.meters.count - 2]) / 65535
    }

    private var masterMeterRight: CGFloat {
        guard let value = vm.meters.last else { return masterMeterLevel }
        return CGFloat(value) / 65535
    }
}
