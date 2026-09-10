import SwiftUI
import AppKit

@main
struct BendyPrototypeApp: App {
    @StateObject private var model = BendModel()

    var body: some Scene {
        WindowGroup("Bendy Prototype") {
            VStack {
                MacBookPreview(model: model)
                Slider(value: $model.angle, in: 0...135)
                Text("\(Int(model.angle))°")
            }
            .padding(40)
            .frame(width: 680, height: 540)
            .background(Color(hex: 0x5c5d60))
            .preferredColorScheme(.dark)
        }
        .windowResizability(.contentSize)
    }
}
