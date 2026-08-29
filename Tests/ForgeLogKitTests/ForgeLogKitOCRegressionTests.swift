import ForgeLogKitOC
import Testing

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
}
