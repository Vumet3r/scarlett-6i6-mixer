import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: ScarlettViewModel
    @State private var showCopyMix = false
    @State private var showRoutingPreset = false
    @State private var showSettings = false
    @State private var showPresets = false
    /// Created once so meter-poll repaints of ContentView (10 Hz) don't
    /// recreate the popover content and steal keyboard focus / state.
    @State private var presetsPanel = PresetsPanel()

    var body: some View {
        VStack(spacing: 0) {
            if vm.isConnected {
                connectedLayout
            } else {
                DisconnectedView()
            }
        }
        .background(ScarlettUI.background)
        .popover(isPresented: $showPresets, arrowEdge: .top) {
            presetsPanel
                .environmentObject(vm)
        }
        .confirmationDialog("Copy Mix to...", isPresented: $showCopyMix) {
            ForEach(0..<8, id: \.self) { i in
                let mixNum = i * 2 + 1
                if i != vm.activeMix {
                    Button("Mix \(mixNum)") { vm.copyMixTo(i) }
                }
            }
            Button("Cancel", role: .cancel) { }
        }
        .confirmationDialog("Routing Preset", isPresented: $showRoutingPreset) {
            Button("DAW / GarageBand (Software Monitoring)") { vm.applyRoutingPreset("daw") }
            Button("Direct Guitar (Zero Latency)") { vm.applyRoutingPreset("direct") }
            Button("Mix 1 (DSP: Guitar + DAW)") { vm.applyRoutingPreset("mix1") }
            Button("Default (1-to-1 routing)") { vm.applyRoutingPreset("default") }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Scarlett 6i6 Mixer", isPresented: $showSettings) {
            Button("OK") { }
        } message: {
            Text("scarlett-app v0.2.1\nBuilt for Scarlett 6i6 1st Gen\n\nNative Mixer for macOS")
        }
    }

    private var connectedLayout: some View {
        GeometryReader { geo in
            let headerH: CGFloat = 36 + 32 // TopBar (36) + MixTabs (32)
            let remainH = max(200, geo.size.height - headerH)
            VStack(spacing: 0) {
                TopBarView(onPresets: { showPresets = true })
                MixTabsView()
                ChannelsAreaView(totalWidth: geo.size.width, onCopyMix: { showCopyMix = true })
                    .frame(height: remainH * 0.63)
                Divider()
                    .background(Color.white.opacity(0.08))
                BottomPanelView(totalWidth: geo.size.width, onPreset: { showRoutingPreset = true }, onSettings: { showSettings = true })
                    .frame(height: remainH * 0.37)
            }
        }
    }
}

struct DisconnectedView: View {
    @EnvironmentObject var vm: ScarlettViewModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.slash")
                .font(.system(size: 48)).foregroundColor(.red)
            Text("Scarlett 6i6 not connected")
                .font(.title2)
                .foregroundStyle(.white)
            if let lastError = vm.lastError, !lastError.isEmpty {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.55))
            }
            Text("Reconnecting automatically… keep scarlett-daemon running")
                .foregroundStyle(.white.opacity(0.8))
            Button("Retry") { Task { await vm.connect() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
