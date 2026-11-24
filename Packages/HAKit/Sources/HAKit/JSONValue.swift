import Foundation

/// A Sendable JSON value. HA payloads are heterogeneous, so everything coming off the wire
/// is converted into this right away.
public enum JSONValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    // MARK: Bridging

    public init(any value: Any?) {
        guard let value, !(value is NSNull) else { self = .null; return }
        if let n = value as? NSNumber, !(value is String) {
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                self = .bool(n.boolValue)
            } else {
                self = .number(n.doubleValue)
            }
            return
        }
        switch value {
        case let s as String: self = .string(s)
        case let a as [Any]: self = .array(a.map { JSONValue(any: $0) })
        case let d as [String: Any]: self = .object(d.mapValues { JSONValue(any: $0) })
        default: self = .null
        }
    }

    /// Foundation representation (for JSONSerialization). Integral numbers become Int so
    /// they serialise as `1`, not `1.0` (HA message IDs must be integers).
    public var anyValue: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let d):
            if d.rounded() == d, abs(d) < 9_007_199_254_740_992 { return Int(d) }
            return d
        case .string(let s): return s
        case .array(let a): return a.map(\.anyValue)
        case .object(let o): return o.mapValues(\.anyValue)
        }
    }

    public static func parse(_ data: Data) throws -> JSONValue {
        if data.isEmpty { return .null }
        return JSONValue(any: try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
    }

    public func serialized() throws -> Data {
        try JSONSerialization.data(withJSONObject: anyValue, options: [.fragmentsAllowed])
    }

    // MARK: Accessors

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public var string: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var double: Double? {
        switch self {
        case .number(let d): return d
        case .string(let s): return Double(s)
        default: return nil
        }
    }

    public var int: Int? { double.map { Int($0.rounded()) } }

    public var bool: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    public var array: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    public var object: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }
}

// MARK: Literals

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
    ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral
{
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, new in new }))
    }
    public init(nilLiteral: ()) { self = .null }
}

extension JSONValue {
    public static func integer(_ i: Int) -> JSONValue { .number(Double(i)) }
    public static func strings(_ s: [String]) -> JSONValue { .array(s.map { .string($0) }) }
}
