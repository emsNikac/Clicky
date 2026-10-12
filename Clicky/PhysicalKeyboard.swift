import Foundation

struct PhysicalKey: Identifiable, Sendable {
    let code: UInt16
    let label: String
    let x: Double
    let row: Int
    let width: Double
    var id: UInt16 { code }
    var pan: Float { Float((x + width / 2) / 15 * 2 - 1) }
    // kbsim labels rows from bottom (R0) to number row (R4).
    var sampleRow: Int { max(0, min(4, 5 - row)) }
    var sampleName: String? {
        switch code {
        case 49: "SPACE"
        case 36, 76: "ENTER"
        case 51, 117: "BACKSPACE"
        default: nil
        }
    }
}

enum PhysicalKeyboard {
    static let rows: [[PhysicalKey]] = [
        makeRow(0, codes: [53,122,120,99,118,96,97,98,100,101,109,103,111],
                labels: ["esc","F1","F2","F3","F4","F5","F6","F7","F8","F9","F10","F11","F12"],
                widths: [1.5] + Array(repeating: 1.125, count: 12)),
        makeRow(1, codes: [50,18,19,20,21,23,22,26,28,25,29,27,24,51],
                labels: ["`","1","2","3","4","5","6","7","8","9","0","−","=","⌫"],
                widths: Array(repeating: 1, count: 13) + [2]),
        makeRow(2, codes: [48,12,13,14,15,17,16,32,34,31,35,33,30,42],
                labels: ["⇥","Q","W","E","R","T","Y","U","I","O","P","[","]","\\"],
                widths: [1.5] + Array(repeating: 1, count: 12) + [1.5]),
        makeRow(3, codes: [57,0,1,2,3,5,4,38,40,37,41,39,36],
                labels: ["⇪","A","S","D","F","G","H","J","K","L",";","'","↩"],
                widths: [1.75] + Array(repeating: 1, count: 11) + [2.25]),
        makeRow(4, codes: [56,6,7,8,9,11,45,46,43,47,44,60],
                labels: ["⇧","Z","X","C","V","B","N","M",",",".","/","⇧"],
                widths: [2.25] + Array(repeating: 1, count: 10) + [2.75]),
        makeRow(5, codes: [63,59,58,55,49,54,61,123,126,125,124],
                labels: ["fn","⌃","⌥","⌘","","⌘","⌥","←","↑","↓","→"],
                widths: [1,1,1,1.25,4.25,1.25,1.25,1,1,1,1])
    ]

    private static func makeRow(_ row: Int, codes: [UInt16], labels: [String], widths: [Double]) -> [PhysicalKey] {
        var x = 0.0
        return zip(zip(codes, labels), widths).map { entry in
            defer { x += entry.1 }
            return PhysicalKey(code: entry.0.0, label: entry.0.1, x: x, row: row, width: entry.1)
        }
    }

    static let keys: [UInt16: PhysicalKey] = {
        var keys = Dictionary(uniqueKeysWithValues: rows.flatMap { $0 }.map { ($0.code, $0) })
        // Extra ISO/JIS keys and the numeric keypad retain their physical side and row.
        for (code, x, row) in [(UInt16(10), 1.75, 4), (93, 12.0, 1), (94, 13.0, 2),
                              (95, 5.0, 5), (102, 8.5, 5), (104, 4.0, 5), (117, 14.0, 1),
                              (76, 14.0, 3), (65, 14.0, 5), (67, 14.0, 1), (69, 14.0, 2),
                              (71, 13.0, 1), (75, 14.0, 1), (78, 14.0, 2), (81, 14.0, 1),
                              (82, 13.0, 5), (83, 13.0, 4), (84, 14.0, 4), (85, 14.0, 4),
                              (86, 13.0, 3), (87, 14.0, 3), (88, 14.0, 3), (89, 13.0, 2),
                              (91, 14.0, 2), (92, 14.0, 2)] {
            keys[code] = PhysicalKey(code: code, label: "", x: x, row: row, width: 1)
        }
        return keys
    }()

    static func key(for code: UInt16) -> PhysicalKey {
        keys[code] ?? PhysicalKey(code: code, label: "", x: 7, row: 3, width: 1)
    }
}
