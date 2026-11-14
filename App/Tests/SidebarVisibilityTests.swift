import AppKit
import SwiftUI
import Testing

@MainActor
struct SidebarVisibilityTests {
    /// Recovery rows precede every source header. A later header's height must
    /// not clip them before that header has reached the top of the viewport.
    @Test func recoveryRowsRemainVisibleBeforeTheFirstPinnedHeader() throws {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: RecoverySidebar())
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 320, height: 280),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 280)
        host.layoutSubtreeIfNeeded()
        // Allow the actual SwiftUI anchor and height preferences to settle.
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        host.layoutSubtreeIfNeeded()

        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        var recoveryPixels = 0
        var headerPixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                // Compare channel dominance to tolerate snapshot color conversion.
                if color.redComponent > color.greenComponent + 0.4,
                   color.redComponent > color.blueComponent + 0.4 {
                    recoveryPixels += 1
                }
                if color.blueComponent > color.redComponent + 0.4,
                   color.blueComponent > color.greenComponent + 0.4 {
                    headerPixels += 1
                }
            }
        }
        // A blank or unrealized fixture cannot pass. The recovery row occupies
        // about 12% of this viewport; the broken mask hides almost all of it.
        #expect(headerPixels > 0, "The later source header must actually render")
        #expect(recoveryPixels > bitmap.pixelsWide * bitmap.pixelsHigh / 10,
                "The recovery row must remain fully visible (\(recoveryPixels) recovery pixels in \(bitmap.pixelsWide)x\(bitmap.pixelsHigh))")
    }
}

private struct RecoverySidebar: View {
    @State private var selection: String?
    @FocusState private var focus: Int?

    var body: some View {
        SidebarList(selection: $selection, order: ["recovery", "normal"],
                    label: "Recovery sidebar", focus: $focus, focusValue: 1) {
            Section {
                Text("Interrupted install — Restore")
                    .frame(height: 34)
                    .frame(maxWidth: .infinity)
                    .background(Color(.sRGB, red: 1, green: 0, blue: 0))
                    .sidebarRow("recovery", selection: $selection)
            }
            Section {
                ForEach(0..<5) { index in
                    Text("Normal row \(index)")
                        .frame(height: 34)
                        .frame(maxWidth: .infinity)
                        .sidebarRow("normal:\(index)", selection: $selection)
                }
            } header: {
                Text("Source")
                    .background(Color(.sRGB, red: 0, green: 0, blue: 1))
                    .sidebarSectionHeader(id: "source")
            }
        }
        .frame(width: 320, height: 280)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}
