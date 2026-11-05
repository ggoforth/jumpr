import JumprCore
import Testing

@Test func autoRegistersOnlyFromApplicationsOnce() {
    #expect(LoginItemPolicy.shouldAutoRegister(bundlePath: "/Applications/Jumpr.app", alreadySetUp: false))
    #expect(!LoginItemPolicy.shouldAutoRegister(bundlePath: "/Applications/Jumpr.app", alreadySetUp: true))
}

@Test func neverAutoRegistersOutsideApplications() {
    for path in ["/Users/greg/Projects/jumpr/build/Jumpr.app", "/Users/greg/Applications/Jumpr.app",
                 "/ApplicationsOld/Jumpr.app", "/Applications", "/Applications/Utilities/Jumpr.app", ""] {
        #expect(!LoginItemPolicy.shouldAutoRegister(bundlePath: path, alreadySetUp: false), "\(path)")
    }
}

@Test func trailingSlashStillCounts() {
    #expect(LoginItemPolicy.shouldAutoRegister(bundlePath: "/Applications/Jumpr.app/", alreadySetUp: false))
}
