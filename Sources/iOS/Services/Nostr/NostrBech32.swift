import Foundation

enum NostrBech32 {
    enum DecodeError: Error, Equatable {
        case empty
        case mixedCase
        case missingSeparator
        case invalidHRP
        case invalidCharacter
        case invalidChecksum
        case invalidLength
        case invalidPadding
    }

    private static let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    private static let charsetIndex: [Character: Int] = {
        var values: [Character: Int] = [:]
        for (index, character) in charset.enumerated() {
            values[character] = index
        }
        return values
    }()

    static func encode(hrp: String, bytes: Data) -> String {
        let fiveBit = convertBits(Array(bytes), from: 8, to: 5, pad: true) ?? []
        let combined = fiveBit + createChecksum(hrp: hrp, data: fiveBit)
        return "\(hrp)1" + combined.map { String(charset[$0]) }.joined()
    }

    static func decode(_ encoded: String) throws -> (hrp: String, bytes: Data) {
        guard !encoded.isEmpty else { throw DecodeError.empty }

        let lower = encoded.lowercased()
        let upper = encoded.uppercased()
        guard encoded == lower || encoded == upper else {
            throw DecodeError.mixedCase
        }

        let value = lower
        guard let separatorIndex = value.lastIndex(of: "1") else {
            throw DecodeError.missingSeparator
        }

        let hrp = String(value[..<separatorIndex])
        let dataPart = value[value.index(after: separatorIndex)...]
        guard !hrp.isEmpty, dataPart.count >= 6 else {
            throw DecodeError.invalidLength
        }
        for scalar in hrp.unicodeScalars {
            guard scalar.value >= 33, scalar.value <= 126 else {
                throw DecodeError.invalidHRP
            }
        }

        var values: [Int] = []
        values.reserveCapacity(dataPart.count)
        for character in dataPart {
            guard let index = charsetIndex[character] else {
                throw DecodeError.invalidCharacter
            }
            values.append(index)
        }
        guard verifyChecksum(hrp: hrp, data: values) else {
            throw DecodeError.invalidChecksum
        }

        let payload = Array(values.dropLast(6))
        guard let bytes = convertBits(payload, from: 5, to: 8, pad: false) else {
            throw DecodeError.invalidPadding
        }
        return (hrp, Data(bytes))
    }

    private static func polymod(_ values: [Int]) -> Int {
        let generators = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
        var checksum = 1
        for value in values {
            let top = checksum >> 25
            checksum = ((checksum & 0x1ffffff) << 5) ^ value
            for index in 0..<5 where ((top >> index) & 1) != 0 {
                checksum ^= generators[index]
            }
        }
        return checksum
    }

    private static func hrpExpand(_ hrp: String) -> [Int] {
        let scalars = Array(hrp.unicodeScalars)
        var output = scalars.map { Int($0.value) >> 5 }
        output.append(0)
        output.append(contentsOf: scalars.map { Int($0.value) & 31 })
        return output
    }

    private static func createChecksum(hrp: String, data: [Int]) -> [Int] {
        let values = hrpExpand(hrp) + data + Array(repeating: 0, count: 6)
        let checksum = polymod(values) ^ 1
        return (0..<6).map { (checksum >> (5 * (5 - $0))) & 31 }
    }

    private static func verifyChecksum(hrp: String, data: [Int]) -> Bool {
        polymod(hrpExpand(hrp) + data) == 1
    }

    private static func convertBits(_ data: [UInt8], from: Int, to: Int, pad: Bool) -> [Int]? {
        var accumulator = 0
        var bits = 0
        var output: [Int] = []
        let maxValue = (1 << to) - 1
        let maxAccumulator = (1 << (from + to - 1)) - 1

        for value in data {
            let intValue = Int(value)
            guard intValue >> from == 0 else { return nil }
            accumulator = ((accumulator << from) | intValue) & maxAccumulator
            bits += from
            while bits >= to {
                bits -= to
                output.append((accumulator >> bits) & maxValue)
            }
        }

        if pad {
            if bits > 0 {
                output.append((accumulator << (to - bits)) & maxValue)
            }
        } else if bits >= from || ((accumulator << (to - bits)) & maxValue) != 0 {
            return nil
        }

        return output
    }

    private static func convertBits(_ data: [Int], from: Int, to: Int, pad: Bool) -> [UInt8]? {
        var accumulator = 0
        var bits = 0
        var output: [UInt8] = []
        let maxValue = (1 << to) - 1
        let maxAccumulator = (1 << (from + to - 1)) - 1

        for value in data {
            guard value >= 0, value >> from == 0 else { return nil }
            accumulator = ((accumulator << from) | value) & maxAccumulator
            bits += from
            while bits >= to {
                bits -= to
                output.append(UInt8((accumulator >> bits) & maxValue))
            }
        }

        if pad {
            if bits > 0 {
                output.append(UInt8((accumulator << (to - bits)) & maxValue))
            }
        } else if bits >= from || ((accumulator << (to - bits)) & maxValue) != 0 {
            return nil
        }

        return output
    }
}

extension Data {
    init?(nostrHex hex: String) {
        let value = hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value.count % 2 == 0 else { return nil }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(value.count / 2)
        var index = value.startIndex
        while index < value.endIndex {
            let nextIndex = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<nextIndex], radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = nextIndex
        }
        self = Data(bytes)
    }

    var nostrHex: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
