import Testing
import Translation
@testable import TranslexApp

@Test func installedAvailabilityUsesInstalledTranslationPath() {
    #expect(TranslationAvailabilityPolicy.route(.installed) == .installed)
}

@Test func supportedAvailabilityUsesDownloadCapablePath() {
    #expect(TranslationAvailabilityPolicy.route(.supported) == .downloadCapable)
}

@Test func unsupportedAvailabilityIsRejected() {
    #expect(TranslationAvailabilityPolicy.route(.unsupported) == .unsupported)
}
