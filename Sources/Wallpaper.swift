import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

struct MountainWallpaper: View {
    var desktop = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack {
                LinearGradient(colors: [Color(hex: 0x4b5d79), Color(hex: 0x9faec3)], startPoint: .top, endPoint: .bottom)
                Canvas { context, size in
                    let transform = CGAffineTransform(scaleX: size.width / 560, y: size.height / 350)
                    let mountains: [(String, UInt32)] = [
                        ("0,168 36,188 90,167 130,181 180,137 235,139 278,181 322,160 371,190 422,150 463,165 520,138 560,151", 0x7e8999),
                        ("0,200 45,180 85,195 156,159 215,199 256,171 302,205 338,184 385,207 447,166 479,185 522,169 560,193", 0x6c7788),
                        ("0,208 52,219 104,193 151,216 191,235 228,214 270,236 320,205 359,225 406,207 459,220 507,218 560,242", 0x5b6576),
                        ("0,234 55,242 104,270 155,244 213,232 261,255 315,227 371,256 421,232 470,245 514,264 560,251", 0x465364)
                    ]
                    for (points, color) in mountains {
                        let values = points.split(separator: " ").map { token -> CGPoint in
                            let xy = token.split(separator: ",").map { Double($0)! }
                            return CGPoint(x: xy[0], y: xy[1])
                        }
                        var path = Path()
                        path.move(to: values[0])
                        for index in 1..<values.count {
                            let a = values[index - 1]
                            let b = values[index]
                            path.addCurve(to: b, control1: CGPoint(x: (a.x + b.x) / 2, y: a.y), control2: CGPoint(x: (a.x + b.x) / 2, y: b.y))
                        }
                        path.addLine(to: CGPoint(x: 560, y: 350))
                        path.addLine(to: CGPoint(x: 0, y: 350))
                        path.closeSubpath()
                        context.fill(path.applying(transform), with: .color(Color(hex: color)))
                    }
                    var snow = Path()
                    snow.move(to: CGPoint(x: 0, y: 252))
                    snow.addCurve(to: CGPoint(x: 253, y: 283), control1: CGPoint(x: 108, y: 236), control2: CGPoint(x: 152, y: 261))
                    snow.addCurve(to: CGPoint(x: 560, y: 186), control1: CGPoint(x: 397, y: 268), control2: CGPoint(x: 473, y: 210))
                    snow.addLine(to: CGPoint(x: 560, y: 350))
                    snow.addLine(to: CGPoint(x: 0, y: 350))
                    snow.closeSubpath()
                    context.fill(snow.applying(transform), with: .linearGradient(Gradient(colors: [Color(hex: 0xe4edf7), Color(hex: 0xb2c6dd)]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
                    var drift = Path()
                    drift.move(to: CGPoint(x: 0, y: 270))
                    drift.addCurve(to: CGPoint(x: 560, y: 296), control1: CGPoint(x: 250, y: 239), control2: CGPoint(x: 352, y: 378))
                    drift.addLine(to: CGPoint(x: 560, y: 350))
                    drift.addLine(to: CGPoint(x: 0, y: 350))
                    drift.closeSubpath()
                    context.fill(drift.applying(transform), with: .linearGradient(Gradient(colors: [Color(hex: 0xd1dfed), Color(hex: 0x7c93af)]), startPoint: .zero, endPoint: CGPoint(x: size.width * 0.5, y: size.height)))
                }
                Circle().fill(Color(hex: 0xebf3ff).opacity(0.92))
                    .frame(width: width * 0.077, height: width * 0.077)
                    .position(x: width * 0.764, y: height * 0.276)
                VStack(spacing: height * 0.018) {
                    Text("Wednesday, September 9")
                        .font(.system(size: width * 0.025, weight: .semibold))
                    Text("9:41")
                        .font(.system(size: width * 0.142, weight: .medium, design: .rounded))
                        .tracking(-width * 0.006)
                }
                .foregroundStyle(.white.opacity(0.93))
                .position(x: width / 2, y: height * 0.255)
                if desktop {
                    DemoDesktop().padding(width * 0.045)
                } else {
                    Capsule().fill(.white.opacity(0.74))
                        .frame(width: width * 0.2, height: max(1, width * 0.003))
                        .position(x: width / 2, y: height * 0.978)
                }
            }
        }
        .clipped()
    }
}

struct DemoDesktop: View {
    var body: some View {
        GeometryReader { geometry in
            VStack {
                HStack(spacing: 12) {
                    Image(systemName: "apple.logo")
                    Text("Finder").bold()
                    Text("File    Edit    View    Go    Window    Help")
                    Spacer()
                    Image(systemName: "wifi")
                    Image(systemName: "battery.100percent")
                }
                .font(.system(size: max(8, geometry.size.width * 0.017)))
                .foregroundStyle(.white)
                Spacer()
                HStack(spacing: 10) {
                    ForEach(["face.smiling", "safari", "message.fill", "calendar", "photo", "music.note", "gearshape.fill"], id: \.self) { symbol in
                        Image(systemName: symbol)
                            .font(.system(size: geometry.size.width * 0.036))
                            .foregroundStyle(.white)
                            .frame(width: geometry.size.width * 0.066, height: geometry.size.width * 0.066)
                            .background(Color.blue.gradient, in: RoundedRectangle(cornerRadius: geometry.size.width * 0.013))
                    }
                }
                .padding(8)
                .background(.white.opacity(0.25), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}
