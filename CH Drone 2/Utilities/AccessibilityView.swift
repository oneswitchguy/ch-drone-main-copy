//
//  AccessibilityView.swift
//  CH Drone
//
//  Created by Alex Robinson on 29/11/21.
//

import UIKit

class AccessibilityView: UIView {

    var onDidBecomeAccessibilityFocused: ((AccessibilityView) -> Void)?
    var onDidLoseAccessibilityFocus: ((AccessibilityView) -> Void)?

    override func accessibilityElementDidBecomeFocused() {
        super.accessibilityElementDidBecomeFocused()

        onDidBecomeAccessibilityFocused?(self)
    }

    override func accessibilityElementDidLoseFocus() {
        super.accessibilityElementDidLoseFocus()

        onDidLoseAccessibilityFocus?(self)
    }

}

