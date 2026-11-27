import SwiftUI

/// Flighty's origin-to-destination bar: filled to the train's position, with a glowing marker.
struct ProgressRail: View {
    var progress: Double
    var color: Color

    var body: some View {
        GeometryReader { geo in
            let x = geo.size.width * min(1, max(0, progress))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12)).frame(height: 4)
                Capsule().fill(color).frame(width: x, height: 4)
                Circle().fill(.white).frame(width: 14, height: 14)
                    .shadow(color: color.opacity(0.9), radius: 6)
                    .overlay(Image(systemName: "tram.fill").font(.system(size: 7, weight: .bold)).foregroundStyle(.black))
                    .offset(x: x - 7)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 16)
    }
}

/// Small rounded tag ("Live GPS", "Trk 7").
struct Tag: View {
    var text: String
    var color: Color = Theme.dim
    var body: some View {
        Text(text).font(.caption2.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.5), lineWidth: 1))
    }
}
