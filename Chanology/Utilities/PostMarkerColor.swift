import UIKit

/// Single source of truth for "(OP)" vs "(You)" marker colors, so the two badges stay
/// visually distinct everywhere they appear (inline quote markers, header badges, reply pills).
enum PostMarkerColor {
    static let op = UIColor.systemPurple
    static let you = UIColor.systemOrange
}
