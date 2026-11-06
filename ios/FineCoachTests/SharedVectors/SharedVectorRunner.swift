import CoreFoundation
import CryptoKit
import Foundation
import XCTest

@testable import FineCoach

// fictional-data: shared infrastructure inputs contain no real people.
struct VectorFailure: Error, CustomStringConvertible {
    let kind: String
    let field: String
    let id: String
    var description: String { "vector=\(id) path=\(field) kind=\(kind)" }
}

final class SharedVectorRunner {
    private let conformance: Bool
    private var id = "<unread>"
    private var seen = Set<String>()
    private static let errors: Set<String> = [
        "emptyText", "textTooLong", "invalidDecimal", "invalidNumber", "invalidUnit", "invalidMode",
        "invalidState", "invalidIdentifier", "conflict", "notFound", "staleRevision", "protectedDataUnavailable",
        "persistenceFailed", "randomSourceFailed", "invalidFileOperation", "incompatibleInput",
        "recurrenceLimitExceeded", "overlapConflict",
    ]
    private static let rules = Set((1...45).map { String(format: "M1A-FR-%03d", $0) }
        + (1...34).map { String(format: "M1B-FR-%03d", $0) })

    init(conformance: Bool) { self.conformance = conformance }

    private func fail(_ path: String, _ kind: String = "format") -> VectorFailure {
        VectorFailure(kind: kind, field: path, id: id)
    }
    private func object(_ value: Any?, _ path: String) throws -> [String: Any] {
        guard let value = value as? [String: Any] else { throw fail(path) }
        return value
    }
    private func string(_ value: Any?, _ path: String) throws -> String {
        guard let value = value as? String else { throw fail(path) }
        return value
    }
    private func integer(_ value: Any?, _ path: String) throws -> Int {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
            !["f", "d"].contains(String(cString: n.objCType)), let result = Int(n.stringValue)
        else { throw fail(path) }
        return result
    }
    private func keys(_ map: [String: Any], _ required: Set<String>, _ optional: Set<String>, _ path: String) throws {
        for key in required.sorted() where map[key] == nil { throw fail("\(path)/\(key)") }
        for key in map.keys.sorted() where !required.union(optional).contains(key) { throw fail("\(path)/\(key)") }
    }
    private func instant(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    func run(_ data: Data, filename: String) throws {
        id = filename.components(separatedBy: "__").last?.replacingOccurrences(of: ".json", with: "") ?? filename
        guard String(data: data, encoding: .utf8) != nil else { throw fail("/") }
        let decoded: Any
        do { decoded = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) }
        catch { throw fail("/") }
        let root = try object(decoded, "/")
        try keys(root, ["id", "rule", "given", "when", "then"], ["meta"], "")
        id = try string(root["id"], "/id")
        guard id.range(of: "^[a-z][a-z0-9-]*$", options: .regularExpression) != nil,
            filename.range(of: "^m1[ab]-fr-[0-9]{3}__" + NSRegularExpression.escapedPattern(for: id) + "\\.json$", options: .regularExpression) != nil
        else { throw fail("/id") }
        guard seen.insert(id).inserted else { throw fail("/id") }
        if let meta = root["meta"] { _ = try object(meta, "/meta") }
        let rules = root["rule"] as? [Any] ?? [root["rule"]!]
        guard !rules.isEmpty, rules.allSatisfy({ ($0 as? String).map(Self.rules.contains) == true }) else { throw fail("/rule") }
        let given = try object(root["given"], "/given")
        let clock = try object(given["clock"], "/given/clock")
        let now = try string(clock["now"], "/given/clock/now")
        guard now.hasSuffix("Z"), instant(now) != nil else { throw fail("/given/clock/now") }
        let then = try object(root["then"], "/then")
        try keys(then, [], ["state", "error"], "/then")
        guard !then.isEmpty else { throw fail("/then") }
        if let token = then["error"] {
            guard let token = token as? String, Self.errors.contains(token) else { throw fail("/then/error") }
        }
        let rawActions: [Any]
        if let action = root["when"] as? [String: Any] { rawActions = [action] }
        else if let actions = root["when"] as? [Any] { rawActions = actions }
        else { throw fail("/when") }
        guard !rawActions.isEmpty else { throw fail("/when") }
        let actions = try rawActions.enumerated().map { index, raw -> [String: Any] in
            let path = "/when/\(index)"
            let action = try object(raw, path)
            try keys(action, ["op", "args"], [], path)
            let op = try string(action["op"], "\(path)/op")
            guard op == "credit-ledger.balance" || (conformance && ["fixture.value", "fixture.fail", "fixture.calendar"].contains(op)) else { throw fail("\(path)/op") }
            _ = try object(action["args"], "\(path)/args")
            if op == "fixture.calendar" {
                let zone = try string(given["timeZone"], "/given/timeZone")
                guard TimeZone.knownTimeZoneIdentifiers.contains(zone) else { throw fail("/given/timeZone") }
            }
            return action
        }
        var results: [Any] = []
        var state: Any = NSNull()
        var error: String?
        for (index, action) in actions.enumerated() {
            let path = "/when/\(index)/args"
            let args = try object(resolve(action["args"]!, root: root, results: results, path: path), path)
            do {
                switch action["op"] as! String {
                case "fixture.value", "fixture.calendar":
                    try keys(args, ["value"], [], path)
                    state = args["value"]!
                case "fixture.fail":
                    try keys(args, ["error"], [], path)
                    let token = try string(args["error"], "\(path)/error")
                    guard Self.errors.contains(token) else { throw fail("\(path)/error") }
                    throw FixtureDomainFailure(token: token)
                default:
                    state = try balance(args, path)
                }
                results.append(state)
            } catch let failure as FixtureDomainFailure { error = failure.token; break }
            catch let failure as DomainError {
                // Only these two errors are reachable from this approved constructor subset.
                switch failure {
                case .invalidNumber: error = "invalidNumber"
                case .invalidIdentifier: error = "invalidIdentifier"
                default: throw failure
                }
                break
            }
        }
        guard error == then["error"] as? String else { throw fail("/then/error", "compare") }
        if let expected = then["state"] { try compare(expected, state, "/then/state") }
    }

    private struct FixtureDomainFailure: Error { let token: String }

    private func resolve(_ value: Any, root: [String: Any], results: [Any], path: String) throws -> Any {
        if let map = value as? [String: Any] {
            if let ref = map["$ref"] {
                guard map.count == 1 else { throw fail(path) }
                let pointer = try string(ref, path)
                guard pointer.hasPrefix("/"), pointer.range(of: "~(?![01])", options: .regularExpression) == nil else { throw fail(path) }
                let tokens = pointer.dropFirst().components(separatedBy: "/").map { $0.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~") }
                var space = root
                space["results"] = results
                var current: Any = space
                for token in tokens {
                    if let map = current as? [String: Any], let next = map[token] { current = next }
                    else if let array = current as? [Any], token.range(of: "^(0|[1-9][0-9]*)$", options: .regularExpression) != nil,
                        let n = Int(token), array.indices.contains(n) { current = array[n] }
                    else { throw fail(path) }
                }
                return current
            }
            var output: [String: Any] = [:]
            for (key, child) in map { output[key] = try resolve(child, root: root, results: results, path: "\(path)/\(key)") }
            return output
        }
        if let array = value as? [Any] {
            return try array.enumerated().map { try resolve($0.element, root: root, results: results, path: "\(path)/\($0.offset)") }
        }
        return value
    }

    private func balance(_ args: [String: Any], _ path: String) throws -> [String: Any] {
        try keys(args, ["totalCredits", "adjustments"], [], path)
        let total = try integer(args["totalCredits"], "\(path)/totalCredits")
        guard let list = args["adjustments"] as? [Any] else { throw fail("\(path)/adjustments") }
        let adjustments = try list.enumerated().map { n, raw -> CreditAdjustment in
            let p = "\(path)/adjustments/\(n)"
            let a = try object(raw, p)
            try keys(a, ["id", "packageID", "direction", "amount", "reasonKind", "sourceEventKey", "createdAtUTC"], [], p)
            func uuid(_ key: String) throws -> StableUUID {
                let text = try string(a[key], "\(p)/\(key)")
                guard let uuid = StableUUID(uuidString: text) else { throw fail("\(p)/\(key)") }
                return uuid
            }
            let adjustmentID = try uuid("id")
            let packageID = try uuid("packageID")
            guard let direction = CreditDirection(rawValue: try string(a["direction"], "\(p)/direction")) else { throw fail("\(p)/direction") }
            let amount = try integer(a["amount"], "\(p)/amount")
            let reasonText = try string(a["reasonKind"], "\(p)/reasonKind")
            guard ["sessionComplete", "sessionReopen", "appointmentAbsent", "adhocSession"].contains(reasonText),
                let reason = CreditReasonKind(rawValue: reasonText) else { throw fail("\(p)/reasonKind") }
            guard let created = instant(try string(a["createdAtUTC"], "\(p)/createdAtUTC")) else { throw fail("\(p)/createdAtUTC") }
            return try CreditAdjustment(
                id: adjustmentID, packageID: packageID, direction: direction, amount: amount,
                reasonKind: reason, sourceEventKey: string(a["sourceEventKey"], "\(p)/sourceEventKey"), createdAtUTC: created
            )
        }
        return ["balance": CreditLedger.balance(totalCredits: total, adjustments: adjustments)]
    }

    private func compare(_ expected: Any, _ actual: Any, _ path: String) throws {
        if let map = expected as? [String: Any] {
            guard let actual = actual as? [String: Any] else { throw fail(path, "compare") }
            for key in map.keys.sorted() {
                guard let value = actual[key] else { throw fail("\(path)/\(key)", "compare") }
                try compare(map[key]!, value, "\(path)/\(key)")
            }
        } else if let array = expected as? [Any] {
            guard let actual = actual as? [Any] else { throw fail(path, "compare") }
            if path.hasSuffix("/trainingFocus") {
                guard let a = array as? [String], let b = actual as? [String], Set(a) == Set(b) else { throw fail(path, "compare") }
            } else {
                guard array.count == actual.count else { throw fail(path, "compare") }
                for n in array.indices { try compare(array[n], actual[n], "\(path)/\(n)") }
            }
        } else if let text = expected as? String {
            guard let actual = actual as? String else { throw fail(path, "compare") }
            if path.hasSuffix("AtUTC") {
                guard let a = instant(text), let b = instant(actual), a == b else { throw fail(path, "compare") }
            } else if text != actual { throw fail(path, "compare") }
        } else if let n = expected as? NSNumber {
            guard let actual = actual as? NSNumber,
                (CFGetTypeID(n) == CFBooleanGetTypeID()) == (CFGetTypeID(actual) == CFBooleanGetTypeID()),
                ["f", "d"].contains(String(cString: n.objCType)) == ["f", "d"].contains(String(cString: actual.objCType)),
                n == actual else { throw fail(path, "compare") }
        } else if !(expected is NSNull && actual is NSNull) { throw fail(path, "compare") }
    }
}

// Both runners enumerate the source tree; no bundle resource copies.
enum VectorFiles {
    static var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("shared/test-vectors")
    }
    static func files(_ directory: String) throws -> [URL] {
        let dir = root.appendingPathComponent(directory)
        guard let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else {
            throw VectorFailure(kind: "format", field: directory, id: "<missing-directory>")
        }
        let files = try enumerator.compactMap { $0 as? URL }.filter {
            try $0.pathExtension == "json" && $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
        }.sorted { $0.path < $1.path }
        guard !files.isEmpty else { throw VectorFailure(kind: "format", field: directory, id: "<empty-directory>") }
        return files
    }
    static func decoded(_ file: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    }
    static func report(_ file: URL) throws {
        let data = try Data(contentsOf: file)
        let id = try decoded(file)["id"].map { String(describing: $0) } ?? "<missing>"
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let path = "shared/test-vectors/" + file.path.replacingOccurrences(of: root.path + "/", with: "")
        print("VECTOR id=\(id) path=\(path) sha256=\(digest)")
    }
    static func checkConformance(_ file: URL) throws {
        var root = try decoded(file)
        let meta = try XCTUnwrap(root["meta"] as? [String: Any])
        let c = try XCTUnwrap(meta["conformance"] as? [String: Any])
        var bytes = try Data(contentsOf: file)
        switch c["mutation"] as? String {
        case "invalid-json": bytes = Data("{fictional-data".utf8)
        case "invalid-utf8": bytes = Data([0xc3, 0x28])
        case "meta-array":
            root["meta"] = [Any]()
            bytes = try JSONSerialization.data(withJSONObject: root)
        default: break
        }
        let name = c["filename"] as? String ?? file.lastPathComponent
        let runner = SharedVectorRunner(conformance: true)
        if c["duplicate"] as? Bool == true { try runner.run(bytes, filename: name) }
        var failure: VectorFailure?
        do { try runner.run(bytes, filename: name) } catch let e as VectorFailure { failure = e }
        if c["outcome"] as? String == "pass" {
            XCTAssertNil(failure, "\(file.lastPathComponent): \(String(describing: failure))")
        } else {
            XCTAssertEqual(failure?.kind, c["outcome"] as? String, file.lastPathComponent)
            XCTAssertEqual(failure?.field, c["path"] as? String, file.lastPathComponent)
        }
        try report(file)
    }
}
