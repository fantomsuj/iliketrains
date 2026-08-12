import SwiftUI

struct BrandBar: View {
    let activeFilterCount: Int
    let onSearch: () -> Void
    let onFilters: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("I LIKE\nTRAINS")
                .font(.system(.title2, design: .rounded, weight: .black))
                .tracking(-1.2)
                .lineSpacing(-6)
                .foregroundStyle(RailTheme.railInk)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 12)

            Button(action: onSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 48, height: 48)
                    .background(RailTheme.parchment, in: Circle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Search trains")

            Button(action: onFilters) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 48, height: 48)
                        .background(RailTheme.parchment, in: Circle())

                    if activeFilterCount > 0 {
                        Text("\(activeFilterCount)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(RailTheme.signalOrange, in: Circle())
                            .offset(x: 4, y: -3)
                    }
                }
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Map filters, \(activeFilterCount) active")
        }
        .foregroundStyle(RailTheme.railInk)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.13), radius: 18, y: 8)
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
        BrandBar(activeFilterCount: 2, onSearch: {}, onFilters: {})
            .padding()
    }
}
