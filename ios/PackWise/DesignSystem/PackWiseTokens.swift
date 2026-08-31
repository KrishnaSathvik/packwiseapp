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
    static let button: CGFloat = 14
    static let card: CGFloat = 16
}

enum PackWiseSize {
    /// Small colourful icon badge used in category and selection rows.
    static let badge: CGFloat = 34
    /// Full-width primary buttons.
    static let buttonHeight: CGFloat = 52
    /// Apple's minimum comfortable target. Never shrink below this.
    static let tapTarget: CGFloat = 44
    /// Compact destination thumbnail on a trip card.
    static let tripThumbnail: CGFloat = 56
    /// Photo band at the top of the hero trip card on Trips Home.
    static let tripCardPhotoHeight: CGFloat = 140
    /// Full-bleed destination hero on Trip Detail.
    static let heroHeight: CGFloat = 240
    /// Destination confirmation image in trip setup.
    static let previewHeight: CGFloat = 150
    static let progressBarHeight: CGFloat = 6
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

/// Presentation for the trip-setup enums.
///
/// The board leans on a small colourful glyph per option so a list of eleven
/// trip types stays scannable. `TripType` already carries an SF Symbol in
/// `Domain/`; the tints and the remaining glyphs belong here, where they
/// cannot leak into packing logic.
extension TripType {
    var tint: Color {
        switch self {
        case .vacation: .orange
        case .cityBreak: .blue
        case .beach: .cyan
        case .business: .indigo
        case .outdoor: .green
        case .roadTrip: .red
        case .weddingEvent: .pink
        case .skiSnow: .teal
        case .festival: .purple
        case .visitingFamily: .brown
        case .other: .gray
        }
    }
}

extension BagType {
    var symbol: String {
        switch self {
        case .personalItem: "bag"
        case .carryOn: "suitcase"
        case .checked: "suitcase.rolling"
        case .backpack: "backpack"
        case .roadTripLuggage: "car"
        case .notSure: "questionmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .personalItem: .teal
        case .carryOn: .blue
        case .checked: .indigo
        case .backpack: .green
        case .roadTripLuggage: .orange
        case .notSure: .gray
        }
    }
}

extension PackingStyle {
    var symbol: String {
        switch self {
        case .light: "leaf"
        case .balanced: "circle.lefthalf.filled"
        case .prepared: "shield"
        }
    }

    var tint: Color {
        switch self {
        case .light: .green
        case .balanced: .blue
        case .prepared: .purple
        }
    }
}

extension TravelMode {
    var symbol: String {
        switch self {
        case .solo: "person"
        case .couple: "person.2"
        case .family: "figure.2.and.child.holdinghands"
        case .group: "person.3"
        }
    }

    var subtitle: String {
        switch self {
        case .solo: "Solo trip"
        case .couple: "Traveling as a couple"
        case .family: "With kids"
        case .group: "Friends or colleagues"
        }
    }

    var tint: Color {
        switch self {
        case .solo: .blue
        case .couple: .pink
        case .family: .orange
        case .group: .purple
        }
    }
}


/// Presentation for the preference chips on the extras step.
///
/// Nine identical grey pills say nothing about which preference is which. The
/// glyph and the hue are what make the field scannable, and both are
/// presentation — `ContextChip` stays a plain value in `Domain/`.
extension ContextChip {
    var symbol: String {
        switch self {
        case .dailyMedication: "pills"
        case .wearContacts: "eyeglasses"
        case .bringingLaptop: "laptopcomputer"
        case .usuallyWorkOut: "dumbbell"
        case .runWhileTraveling: "figure.run"
        case .needFormalOutfit: "sparkles"
        case .travelingInternationally: "airplane"
        case .getColdEasily: "thermometer.snowflake"
        case .laundryAvailable: "washer"
        }
    }

    var tint: Color {
        switch self {
        case .dailyMedication: .red
        case .wearContacts: .indigo
        case .bringingLaptop: .orange
        case .usuallyWorkOut: .green
        case .runWhileTraveling: .mint
        case .needFormalOutfit: .pink
        case .travelingInternationally: .blue
        case .getColdEasily: .teal
        case .laundryAvailable: .purple
        }
    }

    /// The short label the chips use. `title` is written as a first-person
    /// sentence, which is right for a toggle list and far too long for a chip.
    var chipTitle: String {
        switch self {
        case .dailyMedication: "Daily medication"
        case .wearContacts: "Contacts"
        case .bringingLaptop: "Laptop"
        case .usuallyWorkOut: "Work out"
        case .runWhileTraveling: "Running"
        case .needFormalOutfit: "Formal outfit"
        case .travelingInternationally: "International"
        case .getColdEasily: "Get cold easily"
        case .laundryAvailable: "Laundry"
        }
    }
}

/// Presentation for the activity ids the engine uses.
///
/// The ids themselves are engine vocabulary; the glyph is not.
enum PackWiseActivityStyle {
    static func symbol(for id: String) -> String {
        switch id {
        case "swimming": "figure.pool.swim"
        case "beachDays": "beach.umbrella"
        case "snorkeling": "water.waves"
        case "niceDinner": "fork.knife"
        case "running": "figure.run"
        case "sightseeing": "camera"
        case "boatTrip": "sailboat"
        case "walking": "figure.walk"
        case "nightlife": "moon.stars"
        case "shopping": "bag"
        case "museums": "building.columns"
        case "work": "laptopcomputer"
        case "hiking": "figure.hiking"
        case "yoga": "figure.yoga"
        case "photography": "camera.aperture"
        case "wildlife": "binoculars"
        default: "sparkles"
        }
    }

    static func tint(for id: String) -> Color {
        switch id {
        case "swimming", "snorkeling", "boatTrip": .cyan
        case "beachDays": .orange
        case "niceDinner": .pink
        case "running", "hiking", "yoga": .green
        case "sightseeing", "photography": .blue
        case "nightlife": .indigo
        case "shopping": .purple
        case "museums": .brown
        case "work": .gray
        case "walking": .mint
        case "wildlife": .teal
        default: PackWiseColor.accent
        }
    }
}
