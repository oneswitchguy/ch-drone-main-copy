    //
//  GimbalPitchStepper.swift
//  CH Drone
//

import SwiftUI

struct GimbalPitchStepper: View {
    let onTiltUp: () -> Void
    let onTiltDown: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onTiltUp) {
                Image(systemName: "chevron.up")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(NSLocalizedString("Tilt camera up", comment: ""))

            Divider()
                .frame(width: 30)
                .background(Color.white.opacity(0.3))

            Button(action: onTiltDown) {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(NSLocalizedString("Tilt camera down", comment: ""))
        }
        .foregroundColor(.white)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.5))
        )
    }
}
