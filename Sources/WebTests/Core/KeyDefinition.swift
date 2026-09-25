import Foundation

/// A key as both protocols need it: the DOM `key` and `code`, the Windows
/// virtual key code CDP sends, the text it types, and the code point
/// WebDriver uses for keys that type nothing.
public struct KeyDefinition: Sendable, Hashable {
  public var key: String
  public var code: String
  public var keyCode: Int
  /// What the key types, if anything (Enter types a carriage return).
  public var text: String?
  /// 0 standard, 1 left, 2 right, 3 numpad.
  public var location: Int
  /// The WebDriver key value: the character itself, or a code point in the
  /// private-use range for named keys.
  public var webDriverValue: String

  public init(key: String, code: String, keyCode: Int, text: String? = nil, location: Int = 0, webDriverValue: String) {
    self.key = key
    self.code = code
    self.keyCode = keyCode
    self.text = text
    self.location = location
    self.webDriverValue = webDriverValue
  }

  /// The modifier this key is, if it is one.
  public var modifier: KeyModifiers? {
    switch key {
    case "Alt": return .alt
    case "Control": return .control
    case "Meta": return .meta
    case "Shift": return .shift
    default: return nil
    }
  }
}

/// Modifier keys held during an event, as the CDP bit mask.
public struct KeyModifiers: OptionSet, Sendable, Hashable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }

  public static let alt = KeyModifiers(rawValue: 1)
  public static let control = KeyModifiers(rawValue: 2)
  public static let meta = KeyModifiers(rawValue: 4)
  public static let shift = KeyModifiers(rawValue: 8)
}

extension KeyDefinition {
  private static func named(_ key: String, _ keyCode: Int, _ webDriver: UInt32, code: String? = nil, text: String? = nil, location: Int = 0) -> KeyDefinition {
    KeyDefinition(
      key: key, code: code ?? key, keyCode: keyCode, text: text, location: location,
      webDriverValue: String(UnicodeScalar(webDriver)!))
  }

  /// The named keys, by their DOM `key` value.
  static let namedKeys: [String: KeyDefinition] = {
    let keys: [KeyDefinition] = [
      named("Enter", 13, 0xE007, text: "\r"),
      named("Escape", 27, 0xE00C),
      named("Tab", 9, 0xE004),
      named("Backspace", 8, 0xE003),
      named("Delete", 46, 0xE017),
      named("ArrowLeft", 37, 0xE012),
      named("ArrowUp", 38, 0xE013),
      named("ArrowRight", 39, 0xE014),
      named("ArrowDown", 40, 0xE015),
      named("PageUp", 33, 0xE00E),
      named("PageDown", 34, 0xE00F),
      named("Home", 36, 0xE011),
      named("End", 35, 0xE010),
      named("Insert", 45, 0xE016),
      named("Shift", 16, 0xE008, code: "ShiftLeft", location: 1),
      named("Control", 17, 0xE009, code: "ControlLeft", location: 1),
      named("Alt", 18, 0xE00A, code: "AltLeft", location: 1),
      named("Meta", 91, 0xE03D, code: "MetaLeft", location: 1),
      named("F1", 112, 0xE031), named("F2", 113, 0xE032), named("F3", 114, 0xE033),
      named("F4", 115, 0xE034), named("F5", 116, 0xE035), named("F6", 117, 0xE036),
      named("F7", 118, 0xE037), named("F8", 119, 0xE038), named("F9", 120, 0xE039),
      named("F10", 121, 0xE03A), named("F11", 122, 0xE03B), named("F12", 123, 0xE03C),
    ]
    var table = Dictionary(uniqueKeysWithValues: keys.map { ($0.key, $0) })
    table["Space"] = KeyDefinition(key: " ", code: "Space", keyCode: 32, text: " ", webDriverValue: " ")
    table["Esc"] = table["Escape"]
    table["Return"] = table["Enter"]
    table["Ctrl"] = table["Control"]
    table["Cmd"] = table["Meta"]
    table["Command"] = table["Meta"]
    table["Option"] = table["Alt"]
    return table
  }()

  /// The key that types `character`: a letter, digit or punctuation mark on
  /// a US layout, or any other character typed as text alone.
  public static func character(_ character: Character) -> KeyDefinition {
    let text = String(character)
    if text == " " { return namedKeys["Space"]! }
    if text == "\n" || text == "\r" { return namedKeys["Enter"]! }
    guard character.isASCII, let ascii = character.asciiValue else {
      return KeyDefinition(key: text, code: "", keyCode: 0, text: text, webDriverValue: text)
    }
    let scalar = Character(UnicodeScalar(ascii))
    if scalar.isLetter {
      let upper = String(scalar).uppercased()
      return KeyDefinition(key: text, code: "Key\(upper)", keyCode: Int(Character(upper).asciiValue!), text: text, webDriverValue: text)
    }
    if scalar.isNumber {
      return KeyDefinition(key: text, code: "Digit\(text)", keyCode: Int(ascii), text: text, webDriverValue: text)
    }
    let punctuation: [Character: (String, Int)] = [
      "-": ("Minus", 189), "=": ("Equal", 187), "[": ("BracketLeft", 219), "]": ("BracketRight", 221),
      "\\": ("Backslash", 220), ";": ("Semicolon", 186), "'": ("Quote", 222), ",": ("Comma", 188),
      ".": ("Period", 190), "/": ("Slash", 191), "`": ("Backquote", 192),
    ]
    if let (code, keyCode) = punctuation[scalar] {
      return KeyDefinition(key: text, code: code, keyCode: keyCode, text: text, webDriverValue: text)
    }
    return KeyDefinition(key: text, code: "", keyCode: 0, text: text, webDriverValue: text)
  }

  /// The key called `name`: a DOM key name ("Enter", "ArrowDown",
  /// "PageUp", "Escape") or a single character.
  public static func named(_ name: String) throws -> KeyDefinition {
    if let key = namedKeys[name] { return key }
    if name.count == 1 { return character(name.first!) }
    throw WebTestError("Unknown key \"\(name)\". Use a DOM key name such as Enter, Escape, Tab, ArrowDown, PageUp or a single character.")
  }

  /// A chord such as "Shift+PageDown" or "Control+a": the modifiers to hold,
  /// then the key.
  public static func chord(_ text: String) throws -> [KeyDefinition] {
    // "+" alone, or a chord ending in "+" ("Shift++"), means the plus key.
    var parts = text.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
    if text.hasSuffix("+") {
      parts.removeLast(2)
      parts.append("+")
    }
    guard !parts.isEmpty, !parts.contains(where: \.isEmpty) else {
      throw WebTestError("Malformed key chord \"\(text)\".")
    }
    return try parts.map(named)
  }
}
