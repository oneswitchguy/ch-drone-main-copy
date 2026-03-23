//
//  TouchTransparentView.swift
//  CH Drone
//
//  Created by Alex Robinson on 7/6/2022.
//  Copyright © 2022 Astrocode Pty Ltd. All rights reserved.
//

import Foundation
import UIKit

class TouchTransparentView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view == self ? nil : view
    }
}

class TouchTransparentStackView: UIStackView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view == self ? nil : view
    }
}
