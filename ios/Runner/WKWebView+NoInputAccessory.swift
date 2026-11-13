import UIKit
import WebKit
import ObjectiveC

/// WKWebView form alanlarında iOS'un varsayılan ↑↓ / ✓ (Done) çubuğunu kaldırır.
enum WebViewInputAccessory {
  static func hide() {
    guard let contentViewClass = NSClassFromString("WKContentView") else { return }
    let originalSelector = NSSelectorFromString("inputAccessoryView")
    let swizzledSelector = #selector(UIView._arconNoInputAccessoryView)

    guard let originalMethod = class_getInstanceMethod(contentViewClass, originalSelector),
          let swizzledMethod = class_getInstanceMethod(UIView.self, swizzledSelector) else { return }

    if class_addMethod(
      contentViewClass,
      swizzledSelector,
      method_getImplementation(swizzledMethod),
      method_getTypeEncoding(swizzledMethod)
    ) {
      guard let added = class_getInstanceMethod(contentViewClass, swizzledSelector) else { return }
      method_exchangeImplementations(originalMethod, added)
    } else {
      method_exchangeImplementations(originalMethod, swizzledMethod)
    }
  }
}

private extension UIView {
  @objc func _arconNoInputAccessoryView() -> AnyObject? { nil }
}
