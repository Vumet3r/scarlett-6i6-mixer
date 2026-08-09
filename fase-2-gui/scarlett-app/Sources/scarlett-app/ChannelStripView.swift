import SwiftUI

struct ChannelStripView: View {
    @EnvironmentObject var vm: ScarlettViewModel
    let index: Int
    let color: Color
    var showPreamp: Bool = false
    var width: CGFloat = 70
    var label: String { ChannelCatalog.all[index].label }

    private var ch: ScarlettState.InputChannel? {
        vm.state.inputs.indices.contains(index) ? vm.state.inputs[index] : nil
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .font(ScarlettUI.title(12))
                .foregroundStyle(ScarlettUI.labelOnStrip)
                .frame(maxWidth: .infinity)

            if showPreamp {
                preampSection
            } else {
                Color.clear.frame(height: 42)
            }

            panKnob

            faderSection

            dBReadout

            pflButton

            muteAndSolo

            Text(label)
                .font(ScarlettUI.title(10))
                .foregroundStyle(ScarlettUI.labelOnStrip)
        }
        .frame(width: width)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(ScarlettUI.stripFill)
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(ch?.solo == true ? Color.yellow : ScarlettUI.border, lineWidth: 1))
        )
    }

    // MARK: - Preamp

    private var isLo: Bool { index < 2 ? ch?.impedance == "Line" : ch?.gain == "Lo" }
    private var isHi: Bool { index < 2 ? ch?.impedance == "Hi-Z" : ch?.gain == "Hi" }

    private var preampSection: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                ToggleButton(label: index < 2 ? "Line" : "Lo", isOn: isLo, offColor: ScarlettUI.labelOnStrip, height: 18) {
                    vm.setGain(ch: index + 1, "lo")
                }
                ToggleButton(label: index < 2 ? "Inst" : "Hi", isOn: isHi, offColor: ScarlettUI.labelOnStrip, height: 18) {
                    vm.setGain(ch: index + 1, "hi")
                }
            }
            ToggleButton(label: "Pad", isOn: ch?.pad == true, onColor: .orange, offColor: ScarlettUI.labelOnStrip, height: 18) {
                vm.setPad(ch: index + 1, !(ch?.pad ?? false))
            }
        }
    }

    // MARK: - Pan

    private var panKnob: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 1.5)
                .frame(width: 20, height: 20)
            Rectangle()
                .fill(Color.gray)
                .frame(width: 1.5, height: 8)
                .offset(y: -4)
                .rotationEffect(.degrees(panAngle))
        }
        .frame(width: 30, height: 30)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in
                let dx = v.location.x - 15
                let dy = v.location.y - 15
                let a = atan2(dx, -dy) / .pi * 180
                vm.setInputPan(ch: index, Float((min(90, max(-90, a)) + 90) / 180))
            }
        )
    }

    private var panAngle: Double {
        Double((ch?.pan ?? 0.5) * 180 - 90)
    }

    // MARK: - Fader + Meter

    private var faderSection: some View {
        HStack(spacing: 3) {
            MeterBar(level: channelLevel, color: ChannelCatalog.all[index].color, hold: vm.meterHoldLevel(index)) {
                vm.resetMeterHold(index)
            }
            Fader(position: faderPos, onChange: { vm.setMixLevel(ch: index, Float($0)) }) {
                vm.setMixLevel(ch: index, 0.75)
            }
        }
        .frame(height: 160)
    }

    private var channelLevel: CGFloat {
        guard vm.meters.indices.contains(index) else { return 0 }
        return CGFloat(vm.meters[index]) / 65535.0
    }

    private var faderPos: CGFloat { CGFloat(ch?.mixLevel ?? 0.75) }

    // MARK: - dB

    private var dBReadout: some View {
        Text(ScarlettViewModel.dBString(from: ch?.mixLevel ?? 0.75))
            .font(ScarlettUI.mono(11))
            .foregroundStyle(ScarlettUI.labelOnStrip)
    }

    // MARK: - PFL + Link

    private var pflButton: some View {
        HStack(spacing: 6) {
            ToggleButton(label: "PFL", isOn: ch?.pfl == true, onColor: .green, offColor: ScarlettUI.labelOnStrip, font: .system(size: 10, weight: .semibold), controlSize: .mini, height: 16) {
                vm.toggleInputPfl(index)
            }
            Image(systemName: ch?.stereoLink == true ? "link" : "link.slash")
                .font(.system(size: 9))
                .foregroundColor(ch?.stereoLink == true ? .cyan : .gray.opacity(0.3))
                .onTapGesture { vm.toggleInputStereoLink(index) }
        }
    }

    // MARK: - Mute + Solo

    private var muteAndSolo: some View {
        HStack(spacing: 6) {
            ToggleButton(label: "M", isOn: ch?.mute == true, onColor: .red, offColor: ScarlettUI.labelOnStrip, font: .system(size: 10, weight: .semibold), controlSize: .mini, minWidth: 22, height: 18) {
                vm.toggleInputMute(index)
            }
            ToggleButton(label: "S", isOn: ch?.solo == true, onColor: .yellow, offColor: ScarlettUI.labelOnStrip, font: .system(size: 10, weight: .semibold), controlSize: .mini, minWidth: 22, height: 18) {
                vm.toggleInputSolo(index)
            }
        }
    }
}