import SwiftUI

struct RoutingPanelView: View {
    @EnvironmentObject var vm: ScarlettViewModel
    var onPreset: () -> Void

    private static let outputNames = [
        ["Mon L", "Mon R"],
        ["HP L", "HP R"],
        ["S/PDIF L", "S/PDIF R"]
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                SectionTitle(text: "ROUTING & PREAMP")
                Spacer()
                Text(vm.routingPreset)
                    .font(ScarlettUI.title(10))
                    .foregroundStyle(ScarlettUI.accent)
                Button("Routing Preset...") { onPreset() }
                    .font(.system(size: 7)).buttonStyle(.bordered).controlSize(.mini)
            }

            Grid(alignment: .leading, horizontalSpacing: 4, verticalSpacing: 1) {
                ForEach(0..<3, id: \.self) { row in
                    GridRow {
                        Text("\(outputName(row, 0)) →")
                            .font(ScarlettUI.title(10)).foregroundStyle(.white)
                        outputPicker(bus: row * 2)
                        Text("\(outputName(row, 1)) →")
                            .font(ScarlettUI.title(10)).foregroundStyle(.white)
                        outputPicker(bus: row * 2 + 1)
                    }
                }
            }
        }
    }

    private func outputName(_ row: Int, _ col: Int) -> String {
        Self.outputNames[row][col]
    }

    private func outputPicker(bus: Int) -> some View {
        Menu {
            ForEach(0..<8, id: \.self) { i in
                Button("Mix \(i * 2 + 1)") { vm.setOutputMux(bus: bus, src: i) }
            }
        } label: {
            HStack(spacing: 4) {
                Text("Mix \(vm.routing.outputMux[bus] * 2 + 1)")
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .font(ScarlettUI.title(10))
            .foregroundColor(.white)
            .frame(width: 78, height: 24)
            .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.35)))
        }
        .menuStyle(.borderlessButton)
        .tint(.white)
    }
}
