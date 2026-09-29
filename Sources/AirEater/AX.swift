import ApplicationServices

// AX (アクセシビリティ API) の読み書きの小さな道具。CFTypeRef の型確認をここに閉じ込める

func element(
  _ element: AXUIElement, _ attribute: String
) -> Result<AXUIElement, AXFailure> {
  var value: CFTypeRef?
  let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
  guard error == .success else { return .failure(AXFailure(code: error)) }
  guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
    return .failure(AXFailure(code: .failure))
  }
  return .success(unsafeDowncast(value, to: AXUIElement.self))
}

func value<T: BitwiseCopyable>(
  _ element: AXUIElement, _ attribute: String, _ type: AXValueType, _ initial: T
) -> T? {
  var raw: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
    let raw, CFGetTypeID(raw) == AXValueGetTypeID()
  else { return nil }
  var result = initial
  guard AXValueGetValue(unsafeDowncast(raw, to: AXValue.self), type, &result) else { return nil }
  return result
}

func set(_ element: AXUIElement, _ attribute: String, _ size: CGSize) -> AXError {
  var size = size
  guard let value = AXValueCreate(.cgSize, &size) else { return .failure }
  return AXUIElementSetAttributeValue(element, attribute as CFString, value)
}

func set(_ element: AXUIElement, _ attribute: String, _ point: CGPoint) -> AXError {
  var point = point
  guard let value = AXValueCreate(.cgPoint, &point) else { return .failure }
  return AXUIElementSetAttributeValue(element, attribute as CFString, value)
}

/// Result に載せるための AXError の包み。
struct AXFailure: Error {
  let code: AXError
}
