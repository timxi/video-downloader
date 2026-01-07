import SwiftUI

extension Animation {
    /// Returns the animation or nil if Reduce Motion is enabled
    static func reduceMotionSafe(_ animation: Animation) -> Animation? {
        UIAccessibility.isReduceMotionEnabled ? nil : animation
    }

    /// Standard ease-out animation that respects Reduce Motion
    static var reduceMotionEaseOut: Animation? {
        reduceMotionSafe(.easeOut(duration: 0.3))
    }

    /// Spring animation that respects Reduce Motion
    static var reduceMotionSpring: Animation? {
        reduceMotionSafe(.spring(response: 0.4, dampingFraction: 0.7))
    }
}

extension View {
    /// Applies animation only if Reduce Motion is disabled
    @ViewBuilder
    func animationIfEnabled<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        if UIAccessibility.isReduceMotionEnabled {
            self
        } else {
            self.animation(animation, value: value)
        }
    }
}

extension UIView {
    /// Performs UIKit animation respecting Reduce Motion setting
    static func animateWithReduceMotion(
        duration: TimeInterval,
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        if UIAccessibility.isReduceMotionEnabled {
            animations()
            completion?(true)
        } else {
            UIView.animate(withDuration: duration, animations: animations, completion: completion)
        }
    }

    /// Performs spring animation respecting Reduce Motion setting
    static func springAnimateWithReduceMotion(
        duration: TimeInterval = 0.4,
        damping: CGFloat = 0.7,
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        if UIAccessibility.isReduceMotionEnabled {
            animations()
            completion?(true)
        } else {
            UIView.animate(
                withDuration: duration,
                delay: 0,
                usingSpringWithDamping: damping,
                initialSpringVelocity: 0.5,
                options: [],
                animations: animations,
                completion: completion
            )
        }
    }
}
