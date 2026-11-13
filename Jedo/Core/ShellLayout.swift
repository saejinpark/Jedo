import CoreGraphics
import Foundation

/// Where the control groups sit around the screen. A right-handed person
/// holds the pencil in the right hand and moves tools with the left, so the
/// pencil's choices sit top right, out from under the drawing palm, and what
/// the left hand reaches for (undo, the eraser, the tools, the sheets) sits
/// bottom left. Left-handed is the mirror. Each group can be moved to any
/// of six places, and the arrangement is remembered.
struct ShellLayout: Equatable, Codable, Sendable {
    /// A place around the screen's edge.
    enum Slot: String, CaseIterable, Codable, Sendable {
        case topLeading, top, topTrailing, bottomLeading, bottom, bottomTrailing

        var isTop: Bool { self == .topLeading || self == .top || self == .topTrailing }
        /// -1 leading, 0 centre, 1 trailing.
        var side: Int {
            switch self {
            case .topLeading, .bottomLeading: -1
            case .top, .bottom: 0
            case .topTrailing, .bottomTrailing: 1
            }
        }

        var mirrored: Slot {
            switch self {
            case .topLeading: .topTrailing
            case .topTrailing: .topLeading
            case .bottomLeading: .bottomTrailing
            case .bottomTrailing: .bottomLeading
            case .top, .bottom: self
            }
        }

        var name: String {
            switch self {
            case .topLeading: "왼쪽 위"
            case .top: "위 가운데"
            case .topTrailing: "오른쪽 위"
            case .bottomLeading: "왼쪽 아래"
            case .bottom: "아래 가운데"
            case .bottomTrailing: "오른쪽 아래"
            }
        }

        /// The place a point on a screen of `size` is closest to.
        static func at(_ point: CGPoint, in size: CGSize) -> Slot {
            let third = size.width / 3
            let side = point.x < third ? -1 : point.x > 2 * third ? 1 : 0
            let top = point.y < size.height / 2
            switch (top, side) {
            case (true, -1): return .topLeading
            case (true, 0): return .top
            case (true, _): return .topTrailing
            case (false, -1): return .bottomLeading
            case (false, 0): return .bottom
            default: return .bottomTrailing
            }
        }
    }

    /// A group of controls that moves as one.
    enum Group: String, CaseIterable, Codable, Sendable {
        /// What holds the lead, and the lead's grade.
        case pencil
        /// The eraser, the compass and the knife.
        case hand
        /// Rulers, set squares, templates, curves, pins.
        case desk
        /// The sheets panel.
        case sheets
        /// Undo and redo.
        case history
        /// Edge rulers, export, new paper, this arrangement.
        case view
    }

    /// Groups in each place, the first nearest the corner.
    private(set) var slots: [Slot: [Group]]
    var leftHanded: Bool

    static func standard(leftHanded: Bool) -> ShellLayout {
        var slots: [Slot: [Group]] = [
            .topTrailing: [.view, .pencil],
            .bottomLeading: [.history, .hand, .sheets, .desk],
        ]
        if leftHanded {
            slots = Dictionary(uniqueKeysWithValues: slots.map { ($0.key.mirrored, $0.value) })
        }
        return ShellLayout(slots: slots, leftHanded: leftHanded)
    }

    func groups(in slot: Slot) -> [Group] { slots[slot] ?? [] }

    func slot(of group: Group) -> Slot? {
        slots.first { $0.value.contains(group) }?.key
    }

    /// Puts a group in a place, after what is already there.
    mutating func move(_ group: Group, to slot: Slot) {
        for key in slots.keys { slots[key]?.removeAll { $0 == group } }
        slots[slot, default: []].append(group)
        slots = slots.filter { !$0.value.isEmpty }
    }

    /// The same arrangement for the other hand.
    var mirrored: ShellLayout {
        ShellLayout(slots: Dictionary(uniqueKeysWithValues: slots.map { ($0.key.mirrored, $0.value) }),
                    leftHanded: !leftHanded)
    }

    /// The map of the paper goes in the top corner with the fewest groups, the
    /// off hand's side when they tie.
    var mapOnTrailing: Bool {
        let leading = groups(in: .topLeading).count, trailing = groups(in: .topTrailing).count
        return leading == trailing ? leftHanded : leading > trailing
    }

    /// Every group exactly once, whatever was saved.
    var isComplete: Bool {
        let all = slots.values.flatMap { $0 }
        return all.count == Group.allCases.count && Set(all) == Set(Group.allCases)
    }

    // MARK: Saving

    var encoded: String {
        (try? String(decoding: JSONEncoder().encode(self), as: UTF8.self)) ?? ""
    }

    /// A saved arrangement, or nil if it is missing or doesn't hold every group once.
    init?(encoded: String) {
        guard let layout = try? JSONDecoder().decode(ShellLayout.self, from: Data(encoded.utf8)), layout.isComplete else { return nil }
        self = layout
    }

    private init(slots: [Slot: [Group]], leftHanded: Bool) {
        self.slots = slots
        self.leftHanded = leftHanded
    }
}
