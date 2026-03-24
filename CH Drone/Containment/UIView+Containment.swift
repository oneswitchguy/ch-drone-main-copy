//
//  UIView.swift
//  MVCTodo
//
//  Created by Dave DeLong on 10/18/18.
//  Copyright © 2018 Syzygy. All rights reserved.
//

#if canImport(UIKit)

import UIKit

public extension UIView {

    func embedSubview(_ subview: UIView, usingSafeArea: Bool = false, margins: NSDirectionalEdgeInsets = .zero) {
        if subview.superview != nil {
            subview.removeFromSuperview()
        }

        subview.translatesAutoresizingMaskIntoConstraints = false

        subview.frame = bounds
        addSubview(subview)

        let leadingAnchor = usingSafeArea ? safeAreaLayoutGuide.leadingAnchor : leadingAnchor
        let trailingAnchor = usingSafeArea ? safeAreaLayoutGuide.trailingAnchor : trailingAnchor
        let topAnchor = usingSafeArea ? safeAreaLayoutGuide.topAnchor : topAnchor
        let bottomAnchor = usingSafeArea ? safeAreaLayoutGuide.bottomAnchor : bottomAnchor

        NSLayoutConstraint.activate([
            subview.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margins.leading),
            subview.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margins.trailing),

            subview.topAnchor.constraint(equalTo: topAnchor, constant: margins.top),
            subview.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -margins.bottom),
        ])
    }

    func isContainedWithin(_ other: UIView) -> Bool {
        var current: UIView? = self
        while let proposedView = current {
            if proposedView == other { return true }
            current = proposedView.superview
        }
        return false
    }

    var isRightToLeft: Bool { return UIView.userInterfaceLayoutDirection(for: semanticContentAttribute) == .rightToLeft }

    var isLeftToRight: Bool { return !isRightToLeft }
}

#endif
