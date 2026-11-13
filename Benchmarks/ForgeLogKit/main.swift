import Foundation
import ForgeLogKitC
import ForgeBenchC

struct BenchFailure: Error { let reason: String }
func require(_ condition: Bool, _ reason: String) throws {
    if !condition { throw BenchFailure(reason: reason) }
}
struct Canary: Decodable { let input: String; let expected: String; let forbidden: String }
struct Fixtures: Decodable {
    let canaries: [Canary]
    let sizes: [Int]
    let sizeTail: String
    let sizeExpectedTail: String
    let producerInput: String
    let producerExpected: String
}
func redacted(_ input: String) throws -> String {
    try input.withCString { pointer in
        let capacity = FLLogCRedactMessage(pointer, nil, 0)
        try require(capacity > 0, "redaction capacity")
        var output = [CChar](repeating: 0, count: capacity)
        let count = FLLogCRedactMessage(pointer, &output, output.count)
        try require(count == capacity, "redaction capacity changed")
        return String(cString: output)
    }
}
func row(_ name: String, _ size: Int, _ producers: Int, _ iterations: Int, _ elapsed: UInt64) -> [String: Any] {
    let operations = iterations * producers
    return ["case": name, "input_bytes": size, "producers": producers,
            "iterations_per_producer": iterations, "operations": operations,
            "elapsed_ns": elapsed, "ns_per_operation": Double(elapsed) / Double(operations)]
}
// Keep the loop behind a non-inlined call with runtime backend/builder values.
@inline(never)
func disabledBatch(_ logger: FLLog, _ iterations: Int, _ message: () -> String, _ fields: () -> FLLogFields?) {
    for _ in 0..<iterations {
        logger.log(.debug, message())
        logger.log(.debug, message(), lazyFields: fields)
    }
}
func execute(_ fixturePath: String, _ samples: Int, _ iterations: Int) throws -> [String: Any] {
    let fixture = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: URL(fileURLWithPath: fixturePath)))
    try require(fixture.canaries.count == 3 && fixture.sizes == [64, 1024, 16384, 65535], "fixture shape")
    for canary in fixture.canaries {
        let actual = try redacted(canary.input)
        try require(Array(actual.utf8) == Array(canary.expected.utf8) && !actual.contains(canary.forbidden), "literal oracle")
    }
    try require(FLBenchLifetimeReady(1, 1, 0, 0) != 0, "joined lifetime accepted")
    try require(FLBenchLifetimeReady(2, 1, 0, 0) == 0, "missing join refused")
    try require(FLBenchLifetimeReady(1, 1, 1, 0) == 0, "active borrower refused")
    try require(FLBenchLifetimeReady(1, 1, 0, 1) == 0, "repeat destruction refused")
    var results = [[String: Any]]()
    var messageBuilds = 0, fieldBuilds = 0, gateCalls = 0
    let logger = FLLog(category: "Bench", backend: FLLogBackend(
        isEnabled: { _ in gateCalls += 1; return false },
        emit: { _, _, _ in fatalError("disabled backend emitted") }
    ))
    func message() -> String { messageBuilds += 1; return "BENCH-DISABLED-SECRET" }
    func fields() -> FLLogFields? { fieldBuilds += 1; return FLLogFields(component: "bench") }
    for sample in 0..<samples {
        let start = DispatchTime.now().uptimeNanoseconds
        disabledBatch(logger, iterations, message, fields)
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        try require(messageBuilds == 0 && fieldBuilds == 0 && gateCalls == (sample + 1) * iterations * 2, "disabled builders")
        var disabled = row("disabled_swift", 0, 1, iterations * 2, elapsed)
        disabled["sample"] = sample
        results.append(disabled)
        for size in fixture.sizes {
            let input = String(repeating: "s", count: size - fixture.sizeTail.utf8.count) + fixture.sizeTail
            let expected = String(repeating: "s", count: size - fixture.sizeTail.utf8.count) + fixture.sizeExpectedTail
            try require(input.utf8.count == size && Array(try redacted(input).utf8) == Array(expected.utf8), "size oracle")
            let elapsed = try input.withCString { pointer -> UInt64 in
                let capacity = FLLogCRedactMessage(pointer, nil, 0)
                var output = [CChar](repeating: 0, count: capacity)
                var valid = true
                let start = DispatchTime.now().uptimeNanoseconds
                for _ in 0..<iterations {
                    valid = (FLLogCRedactMessage(pointer, &output, output.count) == capacity) && valid
                }
                let elapsed = DispatchTime.now().uptimeNanoseconds - start
                try require(valid && Array(String(cString: output).utf8) == Array(expected.utf8), "timed redaction oracle")
                return elapsed
            }
            var result = row("redact_c", size, 1, iterations, elapsed)
            result["sample"] = sample
            results.append(result)
        }
        for producers in [1, 2, 4, 8] {
            let native = fixture.producerInput.withCString { input in
                fixture.producerExpected.withCString { expected in
                    FLBenchProducers(producers, iterations, input, expected)
                }
            }
            try require(native.valid != 0 && native.created == producers && native.completed == producers &&
                        native.joined == producers && native.submitted == producers * iterations && native.destroyed == 1, "producer oracle/lifetime")
            var result = row("shared_handle_c", fixture.producerInput.utf8.count, producers, iterations, native.elapsed_ns)
            result.merge(["sample": sample, "created": native.created, "completed": native.completed,
                          "joined": native.joined, "submitted": native.submitted, "destroyed": native.destroyed]) { _, new in new }
            results.append(result)
        }
    }
    return ["checks": ["message_builds": messageBuilds, "field_builds": fieldBuilds,
                       "gate_calls": gateCalls, "literal_oracles": fixture.canaries.count, "lifetime_guards": 4],
            "samples": results]
}
do {
    let args = CommandLine.arguments
    try require(args.count == 4, "usage: native FIXTURE SAMPLES ITERATIONS")
    guard let samples = Int(args[2]), let iterations = Int(args[3]) else { throw BenchFailure(reason: "invalid counts") }
    try require((1...100).contains(samples) && (1...1000000).contains(iterations), "count range")
    let result = try execute(args[1], samples, iterations)
    let bytes = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    FileHandle.standardOutput.write(bytes)
    FileHandle.standardOutput.write(Data([10]))
} catch {
    FileHandle.standardError.write(Data("native benchmark failed: \(error)\n".utf8))
    exit(1)
}
