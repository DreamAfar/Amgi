//
//  WebViewInputAccessory.swift
//  BrowseFeature
//

#if canImport(UIKit)
import ObjectiveC
import UIKit
import WebKit

/// Gives a `WKWebView` a custom keyboard accessory view.
///
/// WebKit has no API for this: the first responder is its internal content
/// view, which supplies the system's previous/next/Done bar, and overriding
/// `inputAccessoryView` on the web view itself has no effect. The
/// long-standing workaround, used here, is to give that content view a
/// runtime subclass whose `inputAccessoryView` getter is ours. If WebKit's
/// view hierarchy ever changes so the content view isn't found, nothing is
/// installed and the system bar shows as before.
@MainActor
enum WebViewInputAccessory {
    /// `provider` is asked each time the keyboard comes up, so the view can
    /// be built lazily.
    static func install(on webView: WKWebView, provider: @escaping @MainActor () -> UIView?) {
        guard let contentView = webView.scrollView.subviews.first(where: {
            String(describing: type(of: $0)).hasPrefix("WKContent")
        }) else { return }

        unsafe objc_setAssociatedObject(
            contentView, &AssociatedKey.provider, AccessoryProvider(provider), .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )

        guard let original: AnyClass = unsafe object_getClass(contentView) else { return }
        let name = NSStringFromClass(original) + "_AmgiInputAccessory"
        if let existing = NSClassFromString(name) {
            unsafe object_setClass(contentView, existing)
            return
        }
        guard let subclass = unsafe objc_allocateClassPair(original, name, 0),
              let getter = unsafe class_getInstanceMethod(
                  AccessoryGetter.self, #selector(getter: AccessoryGetter.inputAccessoryView)
              ) else { return }
        unsafe class_addMethod(
            subclass,
            #selector(getter: UIResponder.inputAccessoryView),
            method_getImplementation(getter),
            method_getTypeEncoding(getter)
        )
        unsafe objc_registerClassPair(subclass)
        unsafe object_setClass(contentView, subclass)
    }
}

private enum AssociatedKey {
    nonisolated(unsafe) static var provider: UInt8 = 0
}

private final class AccessoryProvider: NSObject {
    let make: @MainActor () -> UIView?

    init(_ make: @escaping @MainActor () -> UIView?) {
        self.make = make
    }
}

/// Only this class's getter implementation is used: it is copied onto the
/// content view's runtime subclass, so `self` there is the content view.
private final class AccessoryGetter: NSObject {
    @MainActor @objc var inputAccessoryView: UIView? {
        (unsafe objc_getAssociatedObject(self, &AssociatedKey.provider) as? AccessoryProvider)?.make()
    }
}
#endif
