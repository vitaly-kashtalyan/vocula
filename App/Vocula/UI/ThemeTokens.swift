// GENERATED from Design/tokens.json by Tools/GenerateTokens.swift. Do not edit.

import Foundation

extension Theme {
    enum Tokens {
        /// Brass as a FILL: a sidebar selection, a tinted control, a chip, the site's button.
        static let accentFillLight: UInt32 = 0xECA851
        static let accentFillDark: UInt32 = 0xF3AE58

        /// Brass as TEXT. On light it must be dark to be read at all; on dark the fill already reads, so the two are one value. Light leaves sRGB and is clipped — deliberately, once, here.
        static let accentInkLight: UInt32 = 0x8A4C00
        static let accentInkDark: UInt32 = 0xF3AE58

        /// What is written ON the fill. Needed because brass is LIGHT: white on it is 2.04, unreadable. Anything painting white on the accent is a bug.
        static let accentOnLight: UInt32 = 0x1C140C
        static let accentOnDark: UInt32 = 0x110F0D

        /// The MARK's orange — app icon and the indicator's ramp, nothing else. Hotter than accent.fill ON PURPOSE: both surfaces are drawn OUTSIDE our windows, among other people's icons and over other people's documents, where the mark competes for attention rather than sitting in an interface. Leaves sRGB, clipped to the gamut edge. Not drift. Do not 'correct' it to accent.fill.
        static let markHot: UInt32 = 0xFF8100  // clipped to sRGB

        /// The cool end of the mark's ramp, in the icon and in the indicator WHILE A SESSION RUNS. Not the resting line — see pane.resting.
        static let markCool: UInt32 = 0xFFFFFF

        /// The indicator's line when nothing is being said. Stays neutral on purpose: the line sits above the Dock all day over other people's windows, and colour belongs to the time the microphone is open.
        static let paneResting: UInt32 = 0x9E9E9E

        /// Hue 45, not the 60-65 it used to be: at 65 it was 5.4 degrees from brass and 'needs attention' read as 'selected'. At 45 the gap is 25 degrees in both appearances.
        static let warningTextLight: UInt32 = 0xA94608
        static let warningTextDark: UInt32 = 0xFD7933

        /// Light only. On dark the backing is warning.text at 8% — an alpha, not a colour, so it lives in Swift.
        static let warningBackingLight: UInt32 = 0xFAF4F0

        /// Light only, same reason as warning.backing.
        static let warningBorderLight: UInt32 = 0xE3C4B0

        /// Behind the detail column. Not derived from the accent, hence HEX.
        static let windowBgLight: UInt32 = 0xF4F3F1
        static let windowBgDark: UInt32 = 0x1C1C1E

        static let cardBgLight: UInt32 = 0xFFFFFF
        static let cardBgDark: UInt32 = 0x2C2C2E

        static let textPrimaryLight: UInt32 = 0x1A1A18
        static let textPrimaryDark: UInt32 = 0xF5F5F7

        /// Warm on light, cool on dark. The asymmetry is deliberate: a warm grey on warm white reads as paper, the same grey on near-black reads as dirt.
        static let textSecondaryLight: UInt32 = 0x6E6D68
        static let textSecondaryDark: UInt32 = 0x98989D

        static let textMutedLight: UInt32 = 0x8A8983
        static let textMutedDark: UInt32 = 0x8E8D88

    }
}
