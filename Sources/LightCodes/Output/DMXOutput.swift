import Foundation
import Network

/// Anything that can push a 512-channel DMX frame to real lights.
protocol DMXOutput: AnyObject {
    var name: String { get }
    func send(_ universe: [UInt8])
    func close()
}

// MARK: - Art-Net (DMX over Wi-Fi / Ethernet)

/// Art-Net 4 ArtDmx packet over UDP port 6454. Works with any Art-Net node,
/// and with free visualisers, so you can test without hardware.
final class ArtNetOutput: DMXOutput {
    let name: String
    private let connection: NWConnection
    private var sequence: UInt8 = 1
    private let universeNumber: UInt16

    init(host: String, universe: UInt16 = 0) {
        name = "Art-Net → \(host)"
        universeNumber = universe
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        connection = NWConnection(host: NWEndpoint.Host(host), port: 6454, using: params)
        connection.start(queue: .global(qos: .userInteractive))
    }

    func send(_ universe: [UInt8]) {
        var p = [UInt8]()
        p.reserveCapacity(18 + 512)
        p += Array("Art-Net".utf8) + [0]
        p += [0x00, 0x50]                 // OpDmx, little-endian
        p += [0x00, 14]                   // protocol version 14
        p += [sequence, 0]                // sequence, physical
        p += [UInt8(universeNumber & 0xFF), UInt8(universeNumber >> 8)]
        p += [0x02, 0x00]                 // length 512, big-endian
        p += universe.prefix(512)
        sequence = sequence == 255 ? 1 : sequence + 1
        connection.send(content: Data(p), completion: .idempotent)
    }

    func close() { connection.cancel() }
}

// MARK: - USB serial (Enttec and compatibles)

enum USBDMXDevices {
    /// Serial ports that look like USB-DMX dongles (FTDI-based).
    static func list() -> [String] {
        let dev = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        return dev.filter { $0.hasPrefix("cu.usbserial") || $0.hasPrefix("cu.usbmodem") }
            .map { "/dev/" + $0 }
            .sorted()
    }
}

/// Enttec DMX USB Pro protocol (also DMXking ultraDMX, many clones).
/// Packet: 0x7E, label 6, len LSB, len MSB, start code 0, 512 bytes, 0xE7.
/// The widget handles DMX timing itself, which makes it rock solid.
final class EnttecProOutput: DMXOutput {
    let name: String
    private let fd: Int32
    private let queue = DispatchQueue(label: "lightcodes.enttec", qos: .userInteractive)

    init?(path: String) {
        name = "Enttec Pro · " + (path as NSString).lastPathComponent
        fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        var t = termios()
        tcgetattr(fd, &t)
        cfmakeraw(&t)
        cfsetspeed(&t, speed_t(B57600))
        t.c_cflag |= tcflag_t(CLOCAL | CREAD)
        tcsetattr(fd, TCSANOW, &t)
    }

    func send(_ universe: [UInt8]) {
        let len = 513
        var p: [UInt8] = [0x7E, 0x06, UInt8(len & 0xFF), UInt8(len >> 8), 0x00]
        p += universe.prefix(512)
        p.append(0xE7)
        queue.async { [fd] in _ = p.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) } }
    }

    func close() { queue.sync { _ = Darwin.close(fd) } }
}

/// Enttec Open DMX (budget, "dumb" FTDI cable). The computer must generate DMX
/// timing itself: 250 kbaud, 8N2, a BREAK before every frame. Works, but is
/// more sensitive than the Pro.
final class OpenDMXOutput: DMXOutput {
    let name: String
    private let fd: Int32
    private let queue = DispatchQueue(label: "lightcodes.opendmx", qos: .userInteractive)
    // _IO('t', 123) / _IO('t', 122): these macros don't import into Swift.
    static let TIOCSBRK: UInt = 0x2000_747B
    static let TIOCCBRK: UInt = 0x2000_747A

    init?(path: String) {
        name = "Open DMX · " + (path as NSString).lastPathComponent
        fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        var t = termios()
        tcgetattr(fd, &t)
        cfmakeraw(&t)
        t.c_cflag |= tcflag_t(CLOCAL | CREAD | CSTOPB)
        tcsetattr(fd, TCSANOW, &t)
        // Non-standard 250000 baud via IOSSIOSPEED (_IOW('T', 2, speed_t)).
        var speed = speed_t(250_000)
        let IOSSIOSPEED: UInt = 0x80085402
        _ = ioctl(fd, IOSSIOSPEED, &speed)
    }

    func send(_ universe: [UInt8]) {
        var p: [UInt8] = [0x00]
        p += universe.prefix(512)
        queue.async { [fd] in
            _ = ioctl(fd, OpenDMXOutput.TIOCSBRK)
            usleep(110)                  // BREAK >= 88µs
            _ = ioctl(fd, OpenDMXOutput.TIOCCBRK)
            usleep(12)                   // Mark-after-break >= 8µs
            _ = p.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        }
    }

    func close() { queue.sync { _ = Darwin.close(fd) } }
}
