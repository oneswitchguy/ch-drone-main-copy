//
//  ControlSettingsSheet.swift
//  CH Drone
//

import Combine
import SwiftUI
import UIKit
import DJIUXSDKBeta

final class ControlSettingsStore: ObservableObject {

    enum AxisTarget: String, CaseIterable, Identifiable {
        case horizontal
        case vertical

        var id: String { rawValue }

        var title: String {
            switch self {
            case .horizontal:
                return NSLocalizedString("Horizontal", comment: "")
            case .vertical:
                return NSLocalizedString("Vertical", comment: "")
            }
        }

        var symbolName: String {
            switch self {
            case .horizontal:
                return "arrow.left.and.right.circle.fill"
            case .vertical:
                return "arrow.up.and.down.circle.fill"
            }
        }
    }

    enum MultiplierControl: String, CaseIterable, Identifiable {
        case verticalThrottle
        case pitch
        case roll
        case yaw

        var id: String { rawValue }

        var title: String {
            switch self {
            case .verticalThrottle:
                return NSLocalizedString("Altitude", comment: "")
            case .pitch:
                return NSLocalizedString("Pitch", comment: "")
            case .roll:
                return NSLocalizedString("Roll", comment: "")
            case .yaw:
                return NSLocalizedString("Yaw", comment: "")
            }
        }

        var symbolName: String {
            switch self {
            case .verticalThrottle:
                return "arrow.up.and.down.circle.fill"
            case .pitch:
                return "arrow.up.circle.fill"
            case .roll:
                return "arrow.left.and.right.circle.fill"
            case .yaw:
                return "arrow.clockwise.circle.fill"
            }
        }
    }

    @Published private(set) var horizontalAxis: JoystickCommands.AxisOption?
    @Published private(set) var verticalAxis: JoystickCommands.AxisOption?
    @Published private(set) var multipliers: [MultiplierControl: MultiplierLevel]

    private let joystickCommands: JoystickCommands
    private let movementMultipliers: MovementMultipliers
    private var cancellables: Set<AnyCancellable> = []

    init(joystickCommands: JoystickCommands, movementMultipliers: MovementMultipliers) {
        self.joystickCommands = joystickCommands
        self.movementMultipliers = movementMultipliers
        self.horizontalAxis = joystickCommands.horizontalAxis
        self.verticalAxis = joystickCommands.verticalAxis
        self.multipliers = Self.makeMultipliersMap(from: movementMultipliers)

        joystickCommands.$horizontalAxis
            .combineLatest(joystickCommands.$verticalAxis)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] horizontalAxis, verticalAxis in
                self?.horizontalAxis = horizontalAxis
                self?.verticalAxis = verticalAxis
            }
            .store(in: &cancellables)

        movementMultipliers.didChangePublisher
            .prepend(())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                self.multipliers = Self.makeMultipliersMap(from: self.movementMultipliers)
            }
            .store(in: &cancellables)
    }

    func assignment(for option: JoystickCommands.AxisOption) -> AxisTarget? {
        if horizontalAxis == option {
            return .horizontal
        }

        if verticalAxis == option {
            return .vertical
        }

        return nil
    }

    func setAssignment(_ target: AxisTarget?, for option: JoystickCommands.AxisOption) {
        switch target {
        case .horizontal:
            joystickCommands.horizontalAxis = option
        case .vertical:
            joystickCommands.verticalAxis = option
        case nil:
            if joystickCommands.horizontalAxis == option {
                joystickCommands.horizontalAxis = nil
            }

            if joystickCommands.verticalAxis == option {
                joystickCommands.verticalAxis = nil
            }
        }
    }

    func multiplier(for control: MultiplierControl) -> MultiplierLevel {
        multipliers[control] ?? .medium
    }

    func setMultiplier(_ level: MultiplierLevel, for control: MultiplierControl) {
        switch control {
        case .verticalThrottle:
            movementMultipliers.verticalThrottle = level
        case .pitch:
            movementMultipliers.pitch = level
        case .roll:
            movementMultipliers.roll = level
        case .yaw:
            movementMultipliers.yaw = level
        }
    }

    private static func makeMultipliersMap(from movementMultipliers: MovementMultipliers) -> [MultiplierControl: MultiplierLevel] {
        [
            .verticalThrottle: movementMultipliers.verticalThrottle,
            .pitch: movementMultipliers.pitch,
            .roll: movementMultipliers.roll,
            .yaw: movementMultipliers.yaw,
        ]
    }
}

struct ControlSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ControlSettingsStore

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(JoystickCommands.AxisOption.allCases, id: \.rawValue) { option in
                        JoystickAssignmentButton(option: option, assignment: store.assignment(for: option)) { target in
                            store.setAssignment(target, for: option)
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    }
                } header: {
                    Label(NSLocalizedString("Joystick Assignments", comment: ""), systemImage: "gamecontroller.fill")
                }

                Section {
                    ForEach(ControlSettingsStore.MultiplierControl.allCases) { control in
                        MultiplierPopoverButton(
                            control: control,
                            level: store.multiplier(for: control)
                        ) { level in
                            store.setMultiplier(level, for: control)
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    }
                } header: {
                    Label(NSLocalizedString("Speed Multipliers", comment: ""), systemImage: "speedometer")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(NSLocalizedString("Control Settings", comment: ""))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Done", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

private struct JoystickAssignmentButton: View {
    let option: JoystickCommands.AxisOption
    let assignment: ControlSettingsStore.AxisTarget?
    let onAssignmentChange: (ControlSettingsStore.AxisTarget?) -> Void

    var body: some View {
        Menu {
            ForEach(ControlSettingsStore.AxisTarget.allCases) { target in
                Button {
                    onAssignmentChange(target)
                } label: {
                    Label(target.title, systemImage: target.symbolName)
                }
            }

            Button(role: .destructive) {
                onAssignmentChange(nil)
            } label: {
                Label(NSLocalizedString("Unassigned", comment: ""), systemImage: "slash.circle")
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: option.symbolName)
                    .font(.title3)
                    .foregroundStyle(.accent)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.headline)
                    Text(assignment?.title ?? NSLocalizedString("Unassigned", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: assignment?.symbolName ?? "circle.dashed")
                    .foregroundStyle(assignment == nil ? .secondary : .accent)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct MultiplierPopoverButton: View {
    let control: ControlSettingsStore.MultiplierControl
    let level: MultiplierLevel
    let onLevelChange: (MultiplierLevel) -> Void

    @State private var isPopoverPresented = false

    var body: some View {
        Button {
            isPopoverPresented = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: control.symbolName)
                    .font(.title3)
                    .foregroundStyle(.accent)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(control.title)
                        .font(.headline)
                    Text(level.localizedName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(level.localizedName)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))

                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPopoverPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
            MultiplierLevelPicker(level: level) { selectedLevel in
                onLevelChange(selectedLevel)
                isPopoverPresented = false
            }
        }
    }
}

private struct MultiplierLevelPicker: View {
    let level: MultiplierLevel
    let onSelection: (MultiplierLevel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(MultiplierLevel.allCases, id: \.rawValue) { candidate in
                Button {
                    onSelection(candidate)
                } label: {
                    HStack {
                        Text(candidate.localizedName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if candidate == level {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.accent)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if candidate != MultiplierLevel.allCases.last {
                    Divider()
                }
            }
        }
        .frame(width: 220)
        .presentationCompactAdaptation(.popover)
    }
}

private extension JoystickCommands.AxisOption {
    static var allCases: [JoystickCommands.AxisOption] {
        [.verticalThrottle, .pitch, .roll, .yaw]
    }

    var title: String {
        switch self {
        case .verticalThrottle:
            return NSLocalizedString("Altitude", comment: "")
        case .pitch:
            return NSLocalizedString("Pitch", comment: "")
        case .roll:
            return NSLocalizedString("Roll", comment: "")
        case .yaw:
            return NSLocalizedString("Yaw", comment: "")
        }
    }

    var symbolName: String {
        switch self {
        case .verticalThrottle:
            return "arrow.up.and.down.circle.fill"
        case .pitch:
            return "arrow.up.circle.fill"
        case .roll:
            return "arrow.left.and.right.circle.fill"
        case .yaw:
            return "arrow.clockwise.circle.fill"
        }
    }
}

final class ControlSettingsWidget: DUXBetaBaseWidget {
    private let button = UIButton(type: .system)
    private let action: (UIView) -> Void

    override var widgetSizeHint: DUXBetaWidgetSizeHint {
        get {
            DUXBetaWidgetSizeHint(preferredAspectRatio: 1, minimumWidth: 44, minimumHeight: 44)
        }
        set {}
    }

    init(action: @escaping (UIView) -> Void) {
        self.action = action
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear

        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "slider.horizontal.3"), for: .normal)
        button.tintColor = .white
        button.accessibilityLabel = NSLocalizedString("Control settings", comment: "")
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.action(self.button)
        }, for: .touchUpInside)

        view.addSubview(button)

        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: view.topAnchor),
            button.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            button.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            view.widthAnchor.constraint(equalTo: view.heightAnchor),
        ])
    }
}
