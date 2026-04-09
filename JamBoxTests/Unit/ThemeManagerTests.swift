import XCTest
@testable import JamBox

/// `ThemeManager` persists the current theme via `@AppStorage("theme")`,
/// which writes to `UserDefaults.standard`. To avoid polluting the user's
/// real preference we snapshot the key in setUp and restore it in tearDown.
@MainActor
final class ThemeManagerTests: XCTestCase {

    private static let themeKey = "theme"
    private var originalValue: Any?

    override func setUp() {
        super.setUp()
        originalValue = UserDefaults.standard.object(forKey: Self.themeKey)
        UserDefaults.standard.removeObject(forKey: Self.themeKey)
    }

    override func tearDown() {
        if let v = originalValue {
            UserDefaults.standard.set(v, forKey: Self.themeKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.themeKey)
        }
        originalValue = nil
        super.tearDown()
    }

    func testDefaultIsLight() {
        let manager = ThemeManager()
        XCTAssertEqual(manager.current, .light)
    }

    func testPersistsDarkAcrossInstances() {
        let a = ThemeManager()
        a.current = .dark
        let b = ThemeManager()
        XCTAssertEqual(b.current, .dark)
    }

    func testPersistsCandyAcrossInstances() {
        let a = ThemeManager()
        a.current = .candy
        let b = ThemeManager()
        XCTAssertEqual(b.current, .candy)
    }

    func testRoundTripAllThemes() {
        for theme in Theme.allCases {
            let a = ThemeManager()
            a.current = theme
            let b = ThemeManager()
            XCTAssertEqual(b.current, theme, "Failed round-trip for \(theme)")
        }
    }

    func testUnknownStoredValueFallsBackToLight() {
        UserDefaults.standard.set("not-a-real-theme", forKey: Self.themeKey)
        let manager = ThemeManager()
        XCTAssertEqual(manager.current, .light, "Invalid stored theme must fall back to .light")
    }
}
