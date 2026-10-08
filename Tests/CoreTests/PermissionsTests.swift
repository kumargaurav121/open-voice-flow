import Testing
@testable import Core

struct PermissionsTests {
    @Test func allGrantedShowsNoWarning() {
        let permissions = Permissions(microphone: true, accessibility: true, inputMonitoring: true)

        #expect(permissions.missing.isEmpty)
        #expect(permissions.warning == nil)
    }

    @Test func warningNamesEachMissingPermissionInSetupOrder() {
        let permissions = Permissions(microphone: false, accessibility: true, inputMonitoring: false)

        #expect(permissions.missing == [.microphone, .inputMonitoring])
        #expect(permissions.warning == "Missing permissions: Microphone, Input Monitoring")
    }
}
