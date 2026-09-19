//
//  MQTTPacketTests.swift
//  CHDroneTests
//

import XCTest

@testable import CH_Drone_2

/// Covers the MQTT codec and the stick deflection maths behind the control link.
///
/// Uses nothing but `MQTTPacket.swift` and `ControlLinkProtocol.swift`, so it also runs on a
/// Mac: `CHDroneTests` hosts in the app and needs the iPad, but a Swift package that
/// symlinks those two files into a module named `CH_Drone_2` runs this file unchanged with
/// `swift test`.
///
/// Encodings are checked against byte sequences worked out from the MQTT 3.1.1
/// specification, not by round-tripping through the decoder, which would pass a bug made
/// the same way on both sides.
final class MQTTPacketTests: XCTestCase {

    // MARK: - Encoding

    func testConnectWithoutWill() throws {
        let packet = MQTTPacket.connect(clientID: "abc", keepAlive: 60, cleanSession: true, will: nil)
        XCTAssertEqual(try packet.encoded(), bytes(
            0x10, 0x0F,
            0x00, 0x04, 0x4D, 0x51, 0x54, 0x54, // "MQTT"
            0x04,                               // level 3.1.1
            0x02,                               // clean session
            0x00, 0x3C,                         // keepalive 60
            0x00, 0x03, 0x61, 0x62, 0x63        // "abc"
        ))
    }

    func testConnectWithRetainedQoS1Will() throws {
        let will = MQTTWill(topic: "t", payload: Data("x".utf8), qos: .atLeastOnce, retain: true)
        let packet = MQTTPacket.connect(clientID: "c", keepAlive: 5, cleanSession: true, will: will)
        XCTAssertEqual(try packet.encoded(), bytes(
            0x10, 0x13,
            0x00, 0x04, 0x4D, 0x51, 0x54, 0x54,
            0x04,
            0x2E,                   // will retain, will QoS 1, will flag, clean session
            0x00, 0x05,
            0x00, 0x01, 0x63,       // client ID "c"
            0x00, 0x01, 0x74,       // will topic "t"
            0x00, 0x01, 0x78        // will payload "x"
        ))
    }

    func testPublishQoS0() throws {
        let packet = MQTTPacket.publish(topic: "a/b", payload: Data("hi".utf8), qos: .atMostOnce, retain: false, packetID: nil)
        XCTAssertEqual(try packet.encoded(), bytes(0x30, 0x07, 0x00, 0x03, 0x61, 0x2F, 0x62, 0x68, 0x69))
    }

    func testPublishQoS1Retained() throws {
        let packet = MQTTPacket.publish(topic: "a", payload: Data("z".utf8), qos: .atLeastOnce, retain: true, packetID: 10)
        XCTAssertEqual(try packet.encoded(), bytes(0x33, 0x06, 0x00, 0x01, 0x61, 0x00, 0x0A, 0x7A))
    }

    func testPublishQoS1WithoutPacketIDIsRefused() {
        let packet = MQTTPacket.publish(topic: "a", payload: Data(), qos: .atLeastOnce, retain: false, packetID: nil)
        XCTAssertThrowsError(try packet.encoded()) { error in
            XCTAssertEqual(error as? MQTTPacketError, .malformedPacket)
        }
    }

    func testSubscribe() throws {
        let packet = MQTTPacket.subscribe(packetID: 1, subscriptions: [MQTTSubscription(topicFilter: "a/#", qos: .atMostOnce)])
        XCTAssertEqual(try packet.encoded(), bytes(0x82, 0x08, 0x00, 0x01, 0x00, 0x03, 0x61, 0x2F, 0x23, 0x00))
    }

    func testFixedSizePackets() throws {
        XCTAssertEqual(try MQTTPacket.puback(packetID: 10).encoded(), bytes(0x40, 0x02, 0x00, 0x0A))
        XCTAssertEqual(try MQTTPacket.pingreq.encoded(), bytes(0xC0, 0x00))
        XCTAssertEqual(try MQTTPacket.disconnect.encoded(), bytes(0xE0, 0x00))
    }

    func testRemainingLengthBoundaries() throws {
        let cases: [(Int, Data)] = [
            (0, bytes(0x00)),
            (127, bytes(0x7F)),
            (128, bytes(0x80, 0x01)),
            (16_383, bytes(0xFF, 0x7F)),
            (16_384, bytes(0x80, 0x80, 0x01)),
            (2_097_151, bytes(0xFF, 0xFF, 0x7F)),
            (2_097_152, bytes(0x80, 0x80, 0x80, 0x01)),
            (268_435_455, bytes(0xFF, 0xFF, 0xFF, 0x7F)),
        ]
        for (length, expected) in cases {
            XCTAssertEqual(try MQTTPacket.encodeRemainingLength(length), expected, "length \(length)")
        }

        XCTAssertThrowsError(try MQTTPacket.encodeRemainingLength(268_435_456))
    }

    func testStringLongerThanSixtyFourKilobytesIsRefused() {
        let topic = String(repeating: "a", count: Int(UInt16.max) + 1)
        let packet = MQTTPacket.publish(topic: topic, payload: Data(), qos: .atMostOnce, retain: false, packetID: nil)
        XCTAssertThrowsError(try packet.encoded()) { error in
            XCTAssertEqual(error as? MQTTPacketError, .stringTooLong)
        }
    }

    // MARK: - Decoding

    func testConnack() throws {
        var decoder = MQTTPacketDecoder()
        XCTAssertEqual(try decoder.append(bytes(0x20, 0x02, 0x00, 0x00)), [.connack(sessionPresent: false, returnCode: 0)])
        XCTAssertEqual(try decoder.append(bytes(0x20, 0x02, 0x01, 0x05)), [.connack(sessionPresent: true, returnCode: 5)])
    }

    func testPublishDecodesWhatWasEncoded() throws {
        let original = MQTTPacket.publish(topic: "chdrone/v1/stick", payload: Data("{\"seq\":1}".utf8), qos: .atLeastOnce, retain: true, packetID: 300)
        var decoder = MQTTPacketDecoder()
        XCTAssertEqual(try decoder.append(try original.encoded()), [original])
    }

    func testPacketSplitAcrossReadsArrivesOnce() throws {
        // 200-byte payload, so the remaining length takes two bytes and can itself be split.
        let original = MQTTPacket.publish(topic: "t", payload: Data(repeating: 0x41, count: 200), qos: .atMostOnce, retain: false, packetID: nil)
        let encoded = try original.encoded()

        var decoder = MQTTPacketDecoder()
        var received: [MQTTPacket] = []
        for byte in encoded {
            received += try decoder.append(Data([byte]))
            if received.isEmpty == false {
                XCTAssertEqual(received.count, 1)
            }
        }
        XCTAssertEqual(received, [original])
    }

    func testSeveralPacketsInOneRead() throws {
        let publish = MQTTPacket.publish(topic: "p", payload: Data("1".utf8), qos: .atMostOnce, retain: false, packetID: nil)
        var stream = bytes(0x20, 0x02, 0x00, 0x00) // CONNACK
        stream += bytes(0x90, 0x03, 0x00, 0x01, 0x00) // SUBACK, one grant at QoS 0
        stream += bytes(0xD0, 0x00) // PINGRESP
        stream += try publish.encoded()

        var decoder = MQTTPacketDecoder()
        XCTAssertEqual(try decoder.append(stream), [
            .connack(sessionPresent: false, returnCode: 0),
            .suback(packetID: 1, returnCodes: [0]),
            .pingresp,
            publish,
        ])
    }

    func testOversizedPacketIsRefusedBeforeItArrives() {
        var decoder = MQTTPacketDecoder(maximumPacketSize: 16)
        // Declares 100 bytes; only the header has arrived.
        XCTAssertThrowsError(try decoder.append(bytes(0x30, 0x64))) { error in
            XCTAssertEqual(error as? MQTTPacketError, .packetTooLarge)
        }
    }

    func testFiveByteRemainingLengthIsMalformed() {
        var decoder = MQTTPacketDecoder()
        XCTAssertThrowsError(try decoder.append(bytes(0x30, 0xFF, 0xFF, 0xFF, 0xFF))) { error in
            XCTAssertEqual(error as? MQTTPacketError, .malformedRemainingLength)
        }
    }

    func testPacketTypeABrokerNeverSendsIsRefused() {
        var decoder = MQTTPacketDecoder()
        XCTAssertThrowsError(try decoder.append(bytes(0x10, 0x00))) { error in
            XCTAssertEqual(error as? MQTTPacketError, .unexpectedPacketType(1))
        }
    }

    // MARK: - Stick deflection

    /// A held button at each default speed step, on pitch (baseline 0.01) and on yaw
    /// (baseline 0.25). The table in `docs/control-link-mqtt.md`.
    func testEachSpeedStepIsAFixedFractionOfFullStick() {
        let fastest: Float = 2
        let steps: [(multiplier: Float, deflection: Float)] = [
            (0.5, 0.25), (0.75, 0.375), (1.0, 0.5), (1.5, 0.75), (2.0, 1.0),
        ]
        for step in steps {
            for baseline: Float in [0.01, 0.25] {
                let command = baseline * step.multiplier
                XCTAssertEqual(
                    ControlLinkProtocol.deflection(command: command, baseline: baseline, fastestMultiplier: fastest),
                    step.deflection,
                    "multiplier \(step.multiplier), baseline \(baseline)"
                )
            }
        }
    }

    func testDeflectionKeepsDirection() {
        XCTAssertEqual(ControlLinkProtocol.deflection(command: -0.01, baseline: 0.01, fastestMultiplier: 2), -0.5)
        XCTAssertEqual(ControlLinkProtocol.deflection(command: 0.01, baseline: -0.01, fastestMultiplier: 2), 0.5)
    }

    func testDeflectionIsClampedToFullStick() {
        XCTAssertEqual(ControlLinkProtocol.deflection(command: 0.05, baseline: 0.01, fastestMultiplier: 2), 1)
        XCTAssertEqual(ControlLinkProtocol.deflection(command: -0.05, baseline: 0.01, fastestMultiplier: 2), -1)
    }

    func testDeflectionWithNoFullStickIsZero() {
        XCTAssertEqual(ControlLinkProtocol.deflection(command: 0.01, baseline: 0.01, fastestMultiplier: 0), 0)
    }

    // MARK: - JSON

    /// The mover parses this with a flat JSON reader, so the keys are part of the contract.
    func testStickJSONIsFlatWithTheDocumentedKeys() throws {
        let stick = ControlLinkStick(
            session: "S", seq: 7, t: 1_000, pitch: 0.5, roll: 0, yaw: -0.375, throttle: 0,
            active: true, source: ControlLinkProtocol.simulatorSource
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(stick)) as? [String: Any])

        XCTAssertEqual(Set(object.keys), ["session", "seq", "t", "pitch", "roll", "yaw", "throttle", "active", "source"])
        XCTAssertEqual(object["pitch"] as? Double, 0.5)
        XCTAssertEqual(object["yaw"] as? Double, -0.375)
        XCTAssertEqual(object["source"] as? String, "simulator")
    }

    // MARK: - Helpers

    private func bytes(_ values: UInt8...) -> Data {
        Data(values)
    }

}
