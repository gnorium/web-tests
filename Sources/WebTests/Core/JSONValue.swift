import Foundation

/// A JSON value: what the browser sends back and what the protocols take.
///
/// Both protocols speak JSON, and a script's result is JSON too, so one
/// Sendable value type carries all of it. Literals build parameters:
/// `["url": "https://example.com", "flatten": true]`.
public enum JSONValue: Sendable, Hashable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])
}

extension JSONValue {
  /// The member called `key`, or `.null` when there is none or this is not
  /// an object.
  public subscript(key: String) -> JSONValue {
    if case .object(let members) = self, let value = members[key] { return value }
    return .null
  }

  /// The element at `index`, or `.null` out of bounds or when this is not an
  /// array.
  public subscript(index: Int) -> JSONValue {
    if case .array(let elements) = self, elements.indices.contains(index) { return elements[index] }
    return .null
  }

  public var isNull: Bool {
    if case .null = self { return true }
    return false
  }

  public var string: String? {
    if case .string(let value) = self { return value }
    return nil
  }

  public var double: Double? {
    if case .number(let value) = self { return value }
    return nil
  }

  public var int: Int? {
    double.map { Int($0) }
  }

  public var bool: Bool? {
    if case .bool(let value) = self { return value }
    return nil
  }

  public var array: [JSONValue]? {
    if case .array(let value) = self { return value }
    return nil
  }

  public var object: [String: JSONValue]? {
    if case .object(let value) = self { return value }
    return nil
  }

  /// Decodes this value as `T`, for a script that returns a structure.
  public func decode<T: Decodable>(as type: T.Type = T.self) throws -> T {
    let data = try JSONEncoder().encode(self)
    return try JSONDecoder().decode(T.self, from: data)
  }

  /// The value as compact JSON text, for embedding in a script.
  public var jsonText: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else {
      return "null"
    }
    return text
  }

  /// A JSON string literal for `text`, safe to paste into a script.
  public static func quoted(_ text: String) -> String {
    JSONValue.string(text).jsonText
  }
}

extension JSONValue: Codable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: JSONValue].self))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let value): try container.encode(value)
    case .number(let value):
      // Whole numbers go out without a fraction: CDP rejects 1.0 where it
      // wants an integer id or key code.
      if value.rounded() == value, abs(value) < 9_007_199_254_740_992 {
        try container.encode(Int64(value))
      } else {
        try container.encode(value)
      }
    case .string(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    }
  }
}

extension JSONValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
  ExpressibleByFloatLiteral, ExpressibleByStringLiteral, ExpressibleByArrayLiteral,
  ExpressibleByDictionaryLiteral
{
  public init(nilLiteral: ()) { self = .null }
  public init(booleanLiteral value: Bool) { self = .bool(value) }
  public init(integerLiteral value: Int) { self = .number(Double(value)) }
  public init(floatLiteral value: Double) { self = .number(value) }
  public init(stringLiteral value: String) { self = .string(value) }
  public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
  public init(dictionaryLiteral elements: (String, JSONValue)...) {
    self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
  }
}

extension JSONValue {
  public init(_ value: Int) { self = .number(Double(value)) }
  public init(_ value: Double) { self = .number(value) }
  public init(_ value: String) { self = .string(value) }
  public init(_ value: Bool) { self = .bool(value) }
}
