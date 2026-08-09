import SwiftUI

struct ChannelSpec {
    let label: String
    let color: Color
    let isAnalog: Bool
    let meterIndex: Int
}

enum ChannelCatalog {
    static let all: [ChannelSpec] = [
        ChannelSpec(label: "Input 1", color: .blue, isAnalog: true, meterIndex: 0),
        ChannelSpec(label: "Input 2", color: .cyan, isAnalog: true, meterIndex: 1),
        ChannelSpec(label: "Input 3", color: .green, isAnalog: true, meterIndex: 2),
        ChannelSpec(label: "Input 4", color: .mint, isAnalog: true, meterIndex: 3),
        ChannelSpec(label: "S/PDIF L", color: .purple, isAnalog: false, meterIndex: 4),
        ChannelSpec(label: "S/PDIF R", color: .purple, isAnalog: false, meterIndex: 5)
    ]
}
