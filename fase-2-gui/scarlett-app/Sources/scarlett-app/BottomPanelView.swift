import SwiftUI

struct BottomPanelView: View {
    @EnvironmentObject var vm: ScarlettViewModel
    var totalWidth: CGFloat
    var onPreset: () -> Void
    var onSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoutingPanelView(onPreset: onPreset)
                .frame(width: totalWidth * 0.55)
            Divider()
            ClockPanelView(onSettings: onSettings)
                .frame(width: totalWidth * 0.25)
            Divider()
            MonitorPanelView()
                .frame(width: totalWidth * 0.20)
        }
        .foregroundStyle(.white)
        .background(ScarlettUI.panelBackground)
        .padding(6)
    }
}