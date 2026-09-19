//
//  MQTTPacket.swift
//  CH Drone
//

import Foundation

/// The subset of MQTT 3.1.1 the control link needs: connect with a Will, publish at QoS 0
/// or 1, subscribe, keep alive and disconnect.
///
/// Pure Foundation, no UIKit or DJI imports, because the Mac monitor in
/// `tools/ControlLinkMonitor` compiles this file by reference. Written against the
/// OASIS MQTT 3.1.1 specification, and checked against Mosquitto rather than only against
/// itself.

enum MQTTQoS: UInt8, Equatable {
    case atMostOnce = 0
    case atLeastOnce = 1
}

/// The message the broker publishes on the client's behalf if the connection drops without
/// a DISCONNECT.
struct MQTTWill: Equatable {
    let topic: String
    let payload: Data
    let qos: MQTTQoS
    let retain: Bool
}

struct MQTTSubscription: Equatable {
    let topicFilter: String
    let qos: MQTTQoS
}

enum MQTTPacket: Equatable {
    case connect(clientID: String, keepAlive: UInt16, cleanSession: Bool, will: MQTTWill?)
    case connack(sessionPresent: Bool, returnCode: UInt8)
    case publish(topic: String, payload: Data, qos: MQTTQoS, retain: Bool, packetID: UInt16?)
    case puback(packetID: UInt16)
    case subscribe(packetID: UInt16, subscriptions: [MQTTSubscription])
    case suback(packetID: UInt16, returnCodes: [UInt8])
    case pingreq
    case pingresp
    case disconnect
}

enum MQTTPacketError: Error, Equatable {
    case stringTooLong
    case packetTooLarge
    case malformedRemainingLength
    case malformedPacket
    case unexpectedPacketType(UInt8)
}

// MARK: - Encoding

extension MQTTPacket {

    /// The largest remaining length the four-byte encoding can express.
    static let maximumRemainingLength = 268_435_455

    func encoded() throws -> Data {
        var body = Data()
        let firstByte: UInt8

        switch self {
        case let .connect(clientID, keepAlive, cleanSession, will):
            firstByte = 0x10
            try body.appendMQTTString("MQTT")
            body.append(4) // protocol level 3.1.1

            var flags: UInt8 = 0
            if cleanSession { flags |= 0x02 }
            if let will {
                flags |= 0x04
                flags |= will.qos.rawValue << 3
                if will.retain { flags |= 0x20 }
            }
            body.append(flags)
            body.appendUInt16(keepAlive)

            try body.appendMQTTString(clientID)
            if let will {
                try body.appendMQTTString(will.topic)
                try body.appendMQTTBinary(will.payload)
            }

        case let .connack(sessionPresent, returnCode):
            firstByte = 0x20
            body.append(sessionPresent ? 1 : 0)
            body.append(returnCode)

        case let .publish(topic, payload, qos, retain, packetID):
            firstByte = 0x30 | (qos.rawValue << 1) | (retain ? 1 : 0)
            try body.appendMQTTString(topic)
            if qos != .atMostOnce {
                guard let packetID else { throw MQTTPacketError.malformedPacket }
                body.appendUInt16(packetID)
            }
            body.append(payload)

        case let .puback(packetID):
            firstByte = 0x40
            body.appendUInt16(packetID)

        case let .subscribe(packetID, subscriptions):
            firstByte = 0x82
            body.appendUInt16(packetID)
            for subscription in subscriptions {
                try body.appendMQTTString(subscription.topicFilter)
                body.append(subscription.qos.rawValue)
            }

        case let .suback(packetID, returnCodes):
            firstByte = 0x90
            body.appendUInt16(packetID)
            body.append(contentsOf: returnCodes)

        case .pingreq:
            firstByte = 0xC0

        case .pingresp:
            firstByte = 0xD0

        case .disconnect:
            firstByte = 0xE0
        }

        var packet = Data([firstByte])
        packet.append(try Self.encodeRemainingLength(body.count))
        packet.append(body)
        return packet
    }

    static func encodeRemainingLength(_ length: Int) throws -> Data {
        guard (0...maximumRemainingLength).contains(length) else {
            throw MQTTPacketError.packetTooLarge
        }

        var remaining = length
        var bytes = Data()
        repeat {
            var byte = UInt8(remaining % 128)
            remaining /= 128
            if remaining > 0 {
                byte |= 0x80
            }
            bytes.append(byte)
        } while remaining > 0
        return bytes
    }

}

private extension Data {

    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value >> 8))
        append(UInt8(value & 0xFF))
    }

    mutating func appendMQTTString(_ string: String) throws {
        try appendMQTTBinary(Data(string.utf8))
    }

    mutating func appendMQTTBinary(_ data: Data) throws {
        guard data.count <= Int(UInt16.max) else {
            throw MQTTPacketError.stringTooLong
        }
        appendUInt16(UInt16(data.count))
        append(data)
    }

}

// MARK: - Decoding

/// Turns a TCP byte stream into packets. Bytes arrive in whatever chunks the network hands
/// over, so a packet can be split across reads and one read can hold several.
///
/// Decodes only what a broker sends a client: CONNACK, PUBLISH, PUBACK, SUBACK and PINGRESP.
struct MQTTPacketDecoder {

    /// A guard against a corrupt length making the buffer grow without bound. Control link
    /// messages are a few hundred bytes.
    let maximumPacketSize: Int

    init(maximumPacketSize: Int = 64 * 1024) {
        self.maximumPacketSize = maximumPacketSize
    }

    mutating func append(_ data: Data) throws -> [MQTTPacket] {
        buffer.append(contentsOf: data)

        var packets: [MQTTPacket] = []
        while let packet = try nextPacket() {
            packets.append(packet)
        }
        return packets
    }

    // MARK: - Private

    private var buffer: [UInt8] = []

    private mutating func nextPacket() throws -> MQTTPacket? {
        guard buffer.count >= 2 else {
            return nil
        }

        // Remaining length: up to four bytes, seven bits each, low group first.
        var remainingLength = 0
        var multiplier = 1
        var index = 1
        while true {
            guard index <= 4 else {
                throw MQTTPacketError.malformedRemainingLength
            }
            guard index < buffer.count else {
                return nil
            }

            let byte = buffer[index]
            remainingLength += Int(byte & 0x7F) * multiplier
            multiplier *= 128
            index += 1

            if byte & 0x80 == 0 {
                break
            }
        }

        let packetLength = index + remainingLength
        guard packetLength <= maximumPacketSize else {
            throw MQTTPacketError.packetTooLarge
        }
        guard buffer.count >= packetLength else {
            return nil
        }

        let firstByte = buffer[0]
        let body = Array(buffer[index..<packetLength])
        buffer.removeFirst(packetLength)

        return try Self.decode(firstByte: firstByte, body: body)
    }

    private static func decode(firstByte: UInt8, body: [UInt8]) throws -> MQTTPacket {
        let type = firstByte >> 4
        var reader = Reader(bytes: body)

        switch type {
        case 2:
            guard body.count == 2 else { throw MQTTPacketError.malformedPacket }
            return .connack(sessionPresent: body[0] & 0x01 != 0, returnCode: body[1])

        case 3:
            guard let qos = MQTTQoS(rawValue: (firstByte >> 1) & 0x03) else {
                throw MQTTPacketError.malformedPacket
            }
            let topic = try reader.string()
            let packetID = qos == .atMostOnce ? nil : try reader.uint16()
            return .publish(
                topic: topic,
                payload: Data(reader.remainder()),
                qos: qos,
                retain: firstByte & 0x01 != 0,
                packetID: packetID
            )

        case 4:
            guard body.count == 2 else { throw MQTTPacketError.malformedPacket }
            return .puback(packetID: try reader.uint16())

        case 9:
            let packetID = try reader.uint16()
            return .suback(packetID: packetID, returnCodes: reader.remainder())

        case 13:
            guard body.isEmpty else { throw MQTTPacketError.malformedPacket }
            return .pingresp

        default:
            throw MQTTPacketError.unexpectedPacketType(type)
        }
    }

    private struct Reader {
        let bytes: [UInt8]
        var offset = 0

        mutating func uint16() throws -> UInt16 {
            guard offset + 2 <= bytes.count else { throw MQTTPacketError.malformedPacket }
            defer { offset += 2 }
            return UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
        }

        mutating func string() throws -> String {
            let length = Int(try uint16())
            guard offset + length <= bytes.count else { throw MQTTPacketError.malformedPacket }
            defer { offset += length }
            guard let string = String(bytes: bytes[offset..<offset + length], encoding: .utf8) else {
                throw MQTTPacketError.malformedPacket
            }
            return string
        }

        mutating func remainder() -> [UInt8] {
            defer { offset = bytes.count }
            return Array(bytes[offset...])
        }
    }

}
