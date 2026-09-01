import Foundation
import ForgeLogKitOC
import Testing

private final class ObjectiveCHandleTeardownStress: @unchecked Sendable {
    private static let allPaths = 0b1111

    let handle: FLLogOCHandle
    private let condition = NSCondition()
    private var readyWorkers = 0
    private var completedPaths = 0
    private var didStart = false
    private var shouldRun = true

    init(handle: FLLogOCHandle) {
        self.handle = handle
    }

    func runWorker(index: Int) {
        condition.lock()
        readyWorkers += 1
        condition.broadcast()
        while !didStart {
            condition.wait()
        }
        condition.unlock()

        var path = index % 4
        while canRun() {
            exercise(path: path)

            condition.lock()
            completedPaths |= 1 << path
            condition.broadcast()
            condition.unlock()
            path = (path + 1) % 4
        }
    }

    func startThenStopAfterEveryPathRuns(workerCount: Int) {
        condition.lock()
        while readyWorkers < workerCount {
            condition.wait()
        }
        didStart = true
        condition.broadcast()
        while completedPaths != Self.allPaths {
            condition.wait()
        }
        shouldRun = false
        condition.broadcast()
        condition.unlock()
    }

    private func canRun() -> Bool {
        condition.lock()
        defer { condition.unlock() }
        return shouldRun
    }

    private func exercise(path: Int) {
        let info = FLLogOCLevel(rawValue: 1)!
        let error = FLLogOCLevel(rawValue: 3)!
        let privatePrivacy = FLLogOCPrivacy(rawValue: 0)!

        switch path {
        case 0:
            FLLogOCInfoH(handle, "concurrent Objective-C literal")
        case 1:
            _ = FLLogOCIsEnabledH(handle, info)
        case 2:
            FLLogOCLogH(
                handle,
                error,
                privatePrivacy,
                "concurrent Objective-C explicit"
            )
        default:
            FLLogOCLogStructuredH(
                handle,
                error,
                privatePrivacy,
                "lifecycle",
                "teardown",
                nil,
                "objc-worker",
                "concurrent Objective-C structured"
            )
        }
    }
}

@Suite("ForgeLogKit Objective-C API Tests")
struct ForgeLogKitOCRegressionTests {
    @Test("Objective-C convenience API creates, logs every level, and destroys")
    func testConvenienceLifecycle() {
        let handle = FLLogOCCreate("com.test", "ObjectiveC")

        FLLogOCDebugH(handle, "debug")
        FLLogOCInfoH(handle, "info")
        FLLogOCWarnH(handle, "warn")
        FLLogOCErrorH(handle, "error")
        FLLogOCFaultH(handle, "fault")

        FLLogOCDestroy(handle)
    }

    @Test("Objective-C unified API handles defaults, privacy, nil, and enabled checks")
    func testUnifiedDefaultsAndBoundaries() {
        let handle = FLLogOCCreate(nil, nil)
        let info = FLLogOCLevel(rawValue: 1)!
        let error = FLLogOCLevel(rawValue: 3)!
        let privatePrivacy = FLLogOCPrivacy(rawValue: 0)!
        let publicPrivacy = FLLogOCPrivacy(rawValue: 1)!

        _ = FLLogOCIsEnabledH(handle, info)
        FLLogOCLogH(handle, info, publicPrivacy, "public message")
        FLLogOCLogH(handle, error, privatePrivacy, "private message")
        FLLogOCLogH(handle, info, publicPrivacy, nil)
        FLLogOCLogStructuredH(
            handle,
            error,
            privatePrivacy,
            "packet-tunnel",
            "connect",
            "TCP_TIMEOUT",
            "flow-42",
            "structured smoke"
        )
        FLLogOCLogStructuredH(
            handle,
            info,
            publicPrivacy,
            "invalid component",
            nil,
            nil,
            nil,
            "must not emit"
        )

        FLLogOCDestroy(handle)
        FLLogOCDestroy(nil)
        _ = FLLogOCIsEnabledH(nil, info)
        FLLogOCLogH(nil, info, publicPrivacy, "default logger")
    }

    @Test("Objective-C entry points survive repeated concurrent teardown")
    func testConcurrentObjectiveCHandleTeardown() {
        let workerCount = 4
        let queue = DispatchQueue(
            label: "com.forgelogkit.tests.objc-teardown",
            attributes: .concurrent
        )

        for _ in 0 ..< 64 {
            let state = ObjectiveCHandleTeardownStress(
                handle: FLLogOCCreate(
                    "com.forgelogkit.tests",
                    "ObjectiveCTeardown"
                )
            )
            let group = DispatchGroup()
            for index in 0 ..< workerCount {
                group.enter()
                queue.async {
                    state.runWorker(index: index)
                    group.leave()
                }
            }

            state.startThenStopAfterEveryPathRuns(workerCount: workerCount)
            FLLogOCDestroy(state.handle)
            group.wait()
        }
    }
}
