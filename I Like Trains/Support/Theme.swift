import SwiftUI
import UIKit

enum RailTheme {
    static let signalOrange = Color(red: 0.94, green: 0.24, blue: 0.05)
    static let railInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.94, green: 0.92, blue: 0.86, alpha: 1)
            : UIColor(red: 0.08, green: 0.08, blue: 0.07, alpha: 1)
    })
    static let parchment = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.12, green: 0.115, blue: 0.10, alpha: 0.96)
            : UIColor(red: 0.98, green: 0.95, blue: 0.87, alpha: 0.96)
    })
    static let subduedParchment = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.17, green: 0.16, blue: 0.14, alpha: 1)
            : UIColor(red: 0.92, green: 0.88, blue: 0.79, alpha: 1)
    })

    /// Branch colours for passenger services, after the "all roads lead to" route-tree maps.
    static let routePalette: [Color] = [
        Color(red: 0.10, green: 0.66, blue: 0.56), // teal
        Color(red: 0.98, green: 0.71, blue: 0.13), // amber
        Color(red: 0.28, green: 0.42, blue: 0.68), // slate blue
        Color(red: 0.22, green: 0.66, blue: 0.93), // sky
        Color(red: 0.91, green: 0.33, blue: 0.29), // coral
        Color(red: 0.62, green: 0.40, blue: 0.80), // violet
        Color(red: 0.42, green: 0.70, blue: 0.24), // leaf
        Color(red: 0.89, green: 0.42, blue: 0.66)  // rose
    ]

    static let cardCornerRadius: CGFloat = 28
    static let controlCornerRadius: CGFloat = 18
}

extension RailOperator {
    var tint: Color {
        switch self {
        case .amtrak: Color(red: 0.06, green: 0.36, blue: 0.60)
        case .brightline: Color(red: 0.93, green: 0.72, blue: 0.08)
        case .metrolink: Color(red: 0.04, green: 0.55, blue: 0.63)
        case .bnsf: Color(red: 0.93, green: 0.35, blue: 0.05)
        case .unionPacific: Color(red: 0.96, green: 0.68, blue: 0.05)
        case .csx: Color(red: 0.04, green: 0.48, blue: 0.69)
        case .norfolkSouthern: Color(red: 0.18, green: 0.18, blue: 0.20)
        case .canadianNational: Color(red: 0.45, green: 0.30, blue: 0.68)
        case .canadianPacificKansasCity: Color(red: 0.75, green: 0.05, blue: 0.10)
        }
    }
}

extension TrafficLevel {
    /// A warm sequential ramp from sand to deep red, readable over the muted parchment map.
    var tint: Color {
        switch self {
        case .unmeasured: Color(red: 0.55, green: 0.53, blue: 0.50).opacity(0.55)
        case .light: Color(red: 0.84, green: 0.74, blue: 0.52)
        case .moderate: Color(red: 0.97, green: 0.71, blue: 0.16)
        case .busy: Color(red: 0.96, green: 0.52, blue: 0.10)
        case .heavy: Color(red: 0.91, green: 0.30, blue: 0.09)
        case .veryHeavy: Color(red: 0.74, green: 0.12, blue: 0.13)
        case .extreme: Color(red: 0.45, green: 0.04, blue: 0.20)
        }
    }

    var lineWidth: CGFloat {
        switch self {
        case .unmeasured: 1.4
        case .light: 1.8
        case .moderate: 2.4
        case .busy: 3.2
        case .heavy: 4.2
        case .veryHeavy: 5.2
        case .extreme: 6.2
        }
    }
}

enum DwellTheme {
    /// Under a day reads as fluid, over 30 hours as congested.
    static func tint(hours: Double) -> Color {
        switch hours {
        case ..<20: Color(red: 0.10, green: 0.62, blue: 0.52)
        case ..<30: Color(red: 0.93, green: 0.60, blue: 0.08)
        default: Color(red: 0.86, green: 0.26, blue: 0.20)
        }
    }

    static func label(hours: Double) -> String {
        switch hours {
        case ..<20: "Fluid"
        case ..<30: "Typical"
        default: "Congested"
        }
    }
}
