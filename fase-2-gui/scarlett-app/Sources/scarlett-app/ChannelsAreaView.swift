import SwiftUI

struct ChannelsAreaView: View {
    @EnvironmentObject var vm: ScarlettViewModel
    var totalWidth: CGFloat
    var onCopyMix: () -> Void

    private static let gap: CGFloat = 3
    private static let sidePad: CGFloat = 8

    var body: some View {
        let stripW = stripWidth
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: Self.gap) {
                channelStrips(width: stripW)
                MasterChannelView(onCopyMix: onCopyMix)
                    .frame(width: stripW)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, Self.sidePad)
            .padding(.vertical, 12)
        }
    }

    private var stripWidth: CGFloat {
        let auto = (totalWidth - Self.sidePad * 2 - Self.gap * 6) / 7
        return max(55, min(85, auto))
    }

    private func channelStrips(width: CGFloat) -> some View {
        HStack(spacing: 2) {
            ForEach(ChannelCatalog.all.indices, id: \.self) { i in
                ChannelStripView(
                    index: i,
                    color: ChannelCatalog.all[i].color,
                    showPreamp: ChannelCatalog.all[i].isAnalog,
                    width: width
                )
            }
        }
    }
}
