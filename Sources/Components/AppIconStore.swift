import SwiftUI
import UIKit

/// The selected app icon, owned by the app instead of read back from the system each time, so
/// the picker's ring moves the moment the user taps (optimistic) and only reverts on an error.
@MainActor
final class AppIconStore: ObservableObject {
    static let shared = AppIconStore(initial: UIApplication.shared.alternateIconName)

    /// nil = the primary (Ocean) icon.
    @Published private(set) var selected: String?

    typealias Setter = (String?, @escaping (Error?) -> Void) -> Void
    private let setter: Setter

    init(initial: String?, setter: @escaping Setter = AppIconStore.setIcon) {
        selected = initial
        self.setter = setter
    }

    var supportsAlternateIcons: Bool { UIApplication.shared.supportsAlternateIcons }

    /// Re-reads the system value (e.g. after returning to the screen), unless a change is in flight.
    func sync() {
        guard !isChanging else { return }
        selected = UIApplication.shared.alternateIconName
    }

    private var isChanging = false

    /// Selects `name` immediately and applies it. Tapping the current icon does nothing.
    /// `onError` gets a readable message after the selection has been reverted.
    func select(_ name: String?, animation: Animation?, onError: @escaping (String) -> Void) {
        guard name != selected else { return }
        let previous = selected
        Haptics.impact(.light)
        withAnimation(animation) { selected = name }
        isChanging = true
        setter(name) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.isChanging = false
                guard let error else { return }
                // Revert only if nothing newer was chosen meanwhile.
                if self.selected == name {
                    withAnimation(animation) { self.selected = previous }
                }
                onError(error.localizedDescription)
            }
        }
    }

    /// Changes the icon without iOS's "You have changed the icon for CertSigner" alert.
    ///
    /// The public `setAlternateIconName(_:completionHandler:)` always shows that alert. UIKit's
    /// private `_setAlternateIconName:completionHandler:` does the same work without it (other
    /// sideloaded apps use it too). It is looked up at runtime and only called if UIApplication
    /// actually responds to it, so on any iOS that removes or renames it we fall back to the
    /// public API (alert included) and can never crash.
    nonisolated static func setIcon(_ name: String?, completion: @escaping (Error?) -> Void) {
        DispatchQueue.main.async {
            let application = UIApplication.shared
            let selector = NSSelectorFromString("_setAlternateIconName:completionHandler:")
            let privateAvailable = application.responds(to: selector)
            IconChangeDiagnostics.begin(name: name, privateAvailable: privateAvailable)
            if privateAvailable {
                typealias Completion = @convention(block) (NSError?) -> Void
                typealias Method = @convention(c) (NSObject, Selector, NSString?, Completion) -> Void
                let implementation = application.method(for: selector)
                let call = unsafeBitCast(implementation, to: Method.self)
                IconChangeDiagnostics.log("Icon change: calling private _setAlternateIconName:completionHandler: with \(name ?? "nil")")
                call(application, selector, name as NSString?, { error in
                    IconChangeDiagnostics.completion(path: "private", error: error)
                    completion(error)
                })
                IconChangeDiagnostics.log("Icon change: private call returned")
            } else {
                IconChangeDiagnostics.log("Icon change: FALLBACK to public setAlternateIconName (private method missing); iOS will show its alert")
                application.setAlternateIconName(name) { error in
                    IconChangeDiagnostics.completion(path: "public", error: error)
                    completion(error)
                }
            }
        }
    }
}
