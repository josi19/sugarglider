import Testing
import Foundation
@testable import Sugarglider

// MARK: - Reading

extension SugargliderTests {
    @Test("Trend arrows map every Nightscout direction",
          arguments: [
            ("DoubleUp", "↑↑"), ("SingleUp", "↑"), ("FortyFiveUp", "↗"),
            ("Flat", "→"),
            ("FortyFiveDown", "↘"), ("SingleDown", "↓"), ("DoubleDown", "↓↓"),
            ("NONE", ""), ("NOT COMPUTABLE", ""), ("", ""),
          ])
    func trendArrow(direction: String, expected: String) {
        #expect(Reading(sgv: 100, direction: direction, date: Date()).trendArrow == expected)
    }

    @Test func readingValueInUnits() {
        let r = Reading(sgv: 90, direction: "Flat", date: Date())
        #expect(r.value(in: .mgdl) == 90)
        #expect(abs(r.value(in: .mmol) - 5.0) < 1e-9)   // 90 / 18
    }

    @Test func readingTextInUnits() {
        #expect(Reading(sgv: 90, direction: "Flat", date: Date()).text(in: .mgdl) == "90")
        #expect(Reading(sgv: 90, direction: "Flat", date: Date()).text(in: .mmol) == "5.0")
        // 100 / 18 = 5.555… rounds to one decimal
        #expect(Reading(sgv: 100, direction: "Flat", date: Date()).text(in: .mmol) == "5.6")
    }
}

// MARK: - NightscoutError

extension SugargliderTests {
    @Test func errorDescriptions() {
        #expect(NightscoutError.notConfigured.errorDescription == "Not configured")
        #expect(NightscoutError.badURL.errorDescription == "Invalid URL")
        #expect(NightscoutError.http(404).errorDescription == "HTTP 404")
        #expect(NightscoutError.http(500).errorDescription == "HTTP 500")
        #expect(NightscoutError.empty.errorDescription == "No readings")
        #expect(NightscoutError.decode.errorDescription == "Bad response")
    }
}

// MARK: - AppSettings.Units

extension SugargliderTests {
    @Test func unitLabels() {
        #expect(AppSettings.Units.mmol.label == "mmol/L")
        #expect(AppSettings.Units.mgdl.label == "mg/dL")
    }

    @Test func unitRawValuesRoundTrip() {
        #expect(AppSettings.Units(rawValue: "mmol") == .mmol)
        #expect(AppSettings.Units(rawValue: "mgdl") == .mgdl)
        #expect(AppSettings.Units(rawValue: "nonsense") == nil)
    }

    @Test func unitDisplayConversion() {
        #expect(AppSettings.Units.mgdl.display(180) == 180)
        #expect(abs(AppSettings.Units.mmol.display(180) - 10.0) < 1e-9)
    }

    @Test func unitValueFromMgdl() {
        #expect(AppSettings.Units.mgdl.value(fromMgdl: 90) == 90)
        #expect(abs(AppSettings.Units.mmol.value(fromMgdl: 90) - 5.0) < 1e-9)
    }

    @Test func unitTextFromMgdl() {
        #expect(AppSettings.Units.mgdl.text(fromMgdl: 90) == "90")
        #expect(AppSettings.Units.mmol.text(fromMgdl: 90) == "5.0")
        #expect(AppSettings.Units.mmol.text(fromMgdl: 100) == "5.6")
    }

    @Test func unitToMgdl() {
        #expect(AppSettings.Units.mgdl.toMgdl(180) == 180)
        #expect(abs(AppSettings.Units.mmol.toMgdl(10) - 180) < 1e-9)
    }
}

// MARK: - AppInfo

extension SugargliderTests {
    /// The About tab must never invent a version: a missing (or blank) key means
    /// the binary was built without `build.sh`'s Info.plist, which is exactly
    /// what the test suite itself runs as.
    @Test func versionTextFallsBackWhenBundleKeysAreMissing() {
        #expect(AppInfo.versionText(short: "0.2.0", build: "73") == "Version 0.2.0 (73)")
        #expect(AppInfo.versionText(short: "0.2.0", build: nil) == "Version 0.2.0")
        #expect(AppInfo.versionText(short: "0.2.0", build: "") == "Version 0.2.0")
        #expect(AppInfo.versionText(short: nil, build: "73") == "Development build")
        #expect(AppInfo.versionText(short: "", build: "73") == "Development build")
    }

    @Test func repositoryLinksPointAtTheProject() {
        #expect(AppInfo.issuesURL.absoluteString == "https://github.com/josi19/sugarglider/issues")
        #expect(AppInfo.licenseURL.absoluteString
                == "https://github.com/josi19/sugarglider/blob/main/LICENSE")
    }
}
