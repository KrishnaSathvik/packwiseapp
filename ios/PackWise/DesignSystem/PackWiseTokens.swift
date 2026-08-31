import SwiftUI

/// Layout constants for the conformance pass.
///
/// These exist so density is a decision made once rather than re-guessed per
/// screen. Colour is deliberately absent: PackWise uses semantic system
/// colours so Dark Mode stays native, and the only fixed hue is
/// `PackWiseColor.accent`.
enum PackWiseSpacing {
    static let hairline: CGFloat = 2
    static let tight: CGFloat = 4
    static let snug: CGFloat = 8
    static let regular: CGFloat = 12
    static let comfortable: CGFloat = 16
    static let loose: CGFloat = 20
    static let section: CGFloat = 28
}

enum PackWiseRadius {
    static let badge: CGFloat = 8
    static let control: CGFloat = 12
    static let card: CGFloat = 16
}

enum PackWiseSize {
    /// Small colourful icon badge used in category and selection rows.
    static let badge: CGFloat = 30
    /// Apple's minimum comfortable target. Never shrink below this.
    static let tapTarget: CGFloat = 44
    /// Compact destination thumbnail on a trip card.
    static let tripThumbnail: CGFloat = 76
    /// Full-bleed destination hero on Trip Detail.
    static let heroHeight: CGFloat = 240
    /// Destination confirmation image in trip setup.
    static let previewHeight: CGFloat = 150
    static let progressBarHeight: CGFloat = 8
}

/// How a packing category presents itself.
///
/// This is presentation, not domain: `PackingCategory` stays a pure value in
/// `Domain/` and never learns about SF Symbols or colour. The tints are
/// system semantic colours, so they adapt to Dark Mode and high-contrast on
/// their own.
struct PackWiseCategoryStyle {
    var symbol: String
    var tint: Color
}

extension PackingCategory {
    var style: PackWiseCategoryStyle {
        switch self {
        case .essentials: PackWiseCategoryStyle(symbol: "star", tint: .blue)
        case .documents: PackWiseCategoryStyle(symbol: "doc.text", tint: .indigo)
        case .clothing: PackWiseCategoryStyle(symbol: "tshirt", tint: .purple)
        case .kids: PackWiseCategoryStyle(symbol: "figure.and.child.holdinghands", tint: .pink)
        case .footwear: PackWiseCategoryStyle(symbol: "shoe", tint: .brown)
        case .toiletries: PackWiseCategoryStyle(symbol: "drop", tint: .teal)
        case .electronics: PackWiseCategoryStyle(symbol: "powerplug", tint: .orange)
        case .health: PackWiseCategoryStyle(symbol: "cross.case", tint: .red)
        case .activities: PackWiseCategoryStyle(symbol: "figure.hiking", tint: .green)
        case .travelComfort: PackWiseCategoryStyle(symbol: "bed.double", tint: .mint)
        case .miscellaneous: PackWiseCategoryStyle(symbol: "shippingbox", tint: .gray)
        }
    }
}
