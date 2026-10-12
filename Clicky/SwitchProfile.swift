import Foundation

enum SwitchCategory: String, CaseIterable, Identifiable, Sendable {
    case linear = "Linear", tactile = "Tactile", clicky = "Clicky", vintage = "Vintage"
    var id: String { rawValue }
}

struct SwitchProfile: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let maker: String
    let category: SwitchCategory
    let character: String
    let colorHex: UInt32
    var hasSpecialKeys: Bool { id != "mxblue" }

    static let all: [SwitchProfile] = [
        .init(id: "blackink", name: "Black Ink", maker: "Gateron", category: .linear,
              character: "Deep · rounded · resonant", colorHex: 0xA7B9C8),
        .init(id: "cream", name: "Cream", maker: "NovelKeys", category: .linear,
              character: "Woody · full · poppy", colorHex: 0xE8D7AF),
        .init(id: "alpaca", name: "Alpaca", maker: "Durock", category: .linear,
              character: "Smooth · balanced · crisp", colorHex: 0xE7A6B6),
        .init(id: "redink", name: "Red Ink", maker: "Gateron", category: .linear,
              character: "Clean · rounded · lively", colorHex: 0xD77872),
        .init(id: "turquoise", name: "Turquoise Tealios", maker: "Zeal", category: .linear,
              character: "Bright · glassy · precise", colorHex: 0x7BC8C2),
        .init(id: "mxblack", name: "MX Black", maker: "Cherry", category: .linear,
              character: "Classic · solid · dry", colorHex: 0xA6A6AF),
        .init(id: "holypanda", name: "Holy Panda", maker: "Invyr", category: .tactile,
              character: "Rounded · pronounced · knocking", colorHex: 0xEAB583),
        .init(id: "topre", name: "Topre", maker: "Electrocapacitive", category: .tactile,
              character: "Soft · cushioned · thocky", colorHex: 0xB9A7D9),
        .init(id: "mxbrown", name: "MX Brown", maker: "Cherry", category: .tactile,
              character: "Subtle · familiar · balanced", colorHex: 0xBE9677),
        .init(id: "mxblue", name: "MX Blue", maker: "Cherry", category: .clicky,
              character: "Sharp · bright · unmistakable", colorHex: 0x7AA9E3),
        .init(id: "boxnavy", name: "BOX Navy", maker: "Kailh", category: .clicky,
              character: "Bold · crunchy · thick click", colorHex: 0x8297C8),
        .init(id: "bluealps", name: "Blue Alps", maker: "Alps SKCM", category: .vintage,
              character: "Crisp · textured · nostalgic", colorHex: 0x85B7CF),
        .init(id: "buckling", name: "Buckling Spring", maker: "IBM", category: .vintage,
              character: "Springy · resonant · bold", colorHex: 0xB9C499)
    ]

    static func find(_ id: String) -> SwitchProfile { all.first { $0.id == id } ?? all[0] }
}
