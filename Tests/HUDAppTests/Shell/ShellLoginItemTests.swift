import ServiceManagement
import Testing
@testable import HUDApp

@Suite struct ShellLoginItemTests {
    private struct Refusal: LocalizedError {
        var errorDescription: String? { "Operation not permitted" }
    }

    @MainActor private final class FakeService: ShellLoginItemService {
        var status: SMAppService.Status
        var failure: (any Error)?
        var calls: [String] = []

        init(status: SMAppService.Status) { self.status = status }

        func register() throws {
            calls.append("register")
            if let failure { throw failure }
            status = .enabled
        }

        func unregister() throws {
            calls.append("unregister")
            if let failure { throw failure }
            status = .notRegistered
        }
    }

    @Test func onlyEnabledCountsAsOn() {
        #expect(ShellLoginItem.isOn(.enabled))
        #expect(!ShellLoginItem.isOn(.notRegistered))
        #expect(!ShellLoginItem.isOn(.requiresApproval))
        #expect(!ShellLoginItem.isOn(.notFound))
    }

    @Test @MainActor func reflectsTheServiceStatus() {
        let service = FakeService(status: .enabled)
        let item = ShellLoginItem(service: service)
        #expect(item.isOn)
        service.status = .notRegistered
        #expect(!item.isOn)
    }

    @Test @MainActor func togglingWhenOffRegisters() {
        let service = FakeService(status: .notRegistered)
        let item = ShellLoginItem(service: service)
        item.toggle()
        #expect(service.calls == ["register"])
        #expect(item.isOn)
        #expect(item.error == nil)
    }

    @Test @MainActor func togglingWhenAwaitingApprovalRegisters() {
        let service = FakeService(status: .requiresApproval)
        ShellLoginItem(service: service).toggle()
        #expect(service.calls == ["register"])
    }

    @Test @MainActor func togglingWhenOnUnregisters() {
        let service = FakeService(status: .enabled)
        let item = ShellLoginItem(service: service)
        item.toggle()
        #expect(service.calls == ["unregister"])
        #expect(!item.isOn)
    }

    @Test @MainActor func failureIsKeptAsErrorTextUntilTheNextSuccess() {
        let service = FakeService(status: .notFound)
        service.failure = Refusal()
        let item = ShellLoginItem(service: service)

        item.toggle()
        #expect(item.error == "Launch at login failed: Operation not permitted")
        #expect(!item.isOn)

        service.failure = nil
        item.toggle()
        #expect(item.error == nil)
        #expect(item.isOn)
    }
}
