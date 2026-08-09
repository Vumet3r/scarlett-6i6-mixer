import SwiftUI

struct MixTabsView: View {
    @EnvironmentObject var vm: ScarlettViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { i in
                    let mixNum = i * 2 + 1
                    let isActive = vm.activeMix == i
                    Button("Mix \(mixNum)") { vm.activeMix = i }
                        .font(ScarlettUI.title(10, isActive ? .semibold : .regular))
                        .buttonStyle(.bordered)
                        .tint(isActive ? ScarlettUI.accent : .gray.opacity(0.5))
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 34)
        .padding(.vertical, 4)
        .background(ScarlettUI.panelFill)
    }
}
