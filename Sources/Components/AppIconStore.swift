import SwiftUI
import UIKit

/// The selected app icon, owned by the app instead of read back from the system each time, so
/// the picker's ring moves the moment the user taps (optimistic) and only reverts on an error.
@MainActor
final class AppIconStore: ObservableObject {
    static let shared = AppIconStore(initial: UIApplication.shared.alternateIconName)

    /// nil = the primary (Ocean) icon.
    @Published private(set) var selected: String?

    /// The completion is `@Sendable`, so a closure passed to it is never main-actor isolated: the
    /// system may call it on any queue (iOS 27 calls the private API's completion off the main
    /// thread, and an isolated closure traps there with SIGTRAP).
    typealias Setter = (String?, @escaping @Sendable (Error?) -> Void) -> Void
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
        setter(name) { @Sendable [weak self] error in
            // Not isolated: only hop to the main actor, touch state there.
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
    ///
    /// `completion` always runs on the main thread, whatever queue the system calls back on.
    nonisolated static func setIcon(_ name: String?, completion: @escaping @Sendable (Error?) -> Void) {
        DispatchQueue.main.async {
            let application = UIApplication.shared
            let selector = NSSelectorFromString("_setAlternateIconName:completionHandler:")
            let privateAvailable = application.responds(to: selector)
            IconChangeDiagnostics.begin(name: name, privateAvailable: privateAvailable)
            if privateAvailable {
                // - (void)_setAlternateIconName:(NSString *)name completionHandler:(void (^)(NSError *))handler
                typealias Method = @convention(c) (NSObject, Selector, NSString?, IconCompletionBlock) -> Void
                let implementation = application.method(for: selector)
                let call = unsafeBitCast(implementation, to: Method.self)
                IconChangeDiagnostics.log("Icon change: calling private _setAlternateIconName:completionHandler: with \(name ?? "nil") on main=\(Thread.isMainThread)")
                call(application, selector, name as NSString?, completionBlock(path: "private", completion: completion))
                IconChangeDiagnostics.log("Icon change: private call returned")
            } else {
                IconChangeDiagnostics.log("Icon change: FALLBACK to public setAlternateIconName (private method missing); iOS will show its alert")
                let block = completionBlock(path: "public", completion: completion)
                application.setAlternateIconName(name) { error in block(error as NSError?) }
            }
        }
    }

    typealias IconCompletionBlock = @convention(block) (NSError?) -> Void

    /// The block handed to UIKit. Built in a nonisolated context and captures no main-actor state,
    /// so it is safe on any queue: it logs where it fired, then hops to main for everything else.
    nonisolated static func completionBlock(path: String, completion: @escaping @Sendable (Error?) -> Void) -> IconCompletionBlock {
        return { @Sendable (error: NSError?) in
            let onMain = Thread.isMainThread
            let errorText = error.map { "\($0.domain) \($0.code): \($0.localizedDescription)" } ?? "nil"
            IconChangeDiagnostics.log("Icon change: completion fired on main=\(onMain), error=\(errorText)")
            DispatchQueue.main.async {
                IconChangeDiagnostics.completion(path: path, error: error)
                completion(error)
            }
        }
    }
}
