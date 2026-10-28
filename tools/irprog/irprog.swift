import CoreBluetooth
import Foundation

// Packet formats reverse-engineered from the Smart RCU app (com.standard.irtvcontrol) in the SEI804HM firmware.
// Writes go to characteristic B002 of service 00000AA0-3C17-D293-8E48-14FE2E4DA212.

let samsung: [(name: String, key: UInt8, code: UInt32)] = [
    ("Power", 1, 0xE0E040BF),
    ("Vol+", 2, 0xE0E0E01F),
    ("Vol-", 3, 0xE0E0D02F),
    ("Mute", 17, 0xE0E0F00F),
    ("Input", 5, 0xE0E0807F),
    ("MuteAsSource", 17, 0xE0E0807F),
]

// Samsung32: 4500/4500 header, 560 mark, 560/1690 space per bit (MSB first), 560 stop mark, trailing gap.
func samsungTimings(_ code: UInt32) -> [Int] {
    var t = [4500, 4500]
    for i in (0..<32).reversed() { t.append(560); t.append((code >> UInt32(i)) & 1 == 1 ? 1690 : 560) }
    t.append(560); t.append(40000)
    return t
}

func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }

func irPackets(_ timingsUs: [Int], rnd: UInt8) -> [[UInt8]] {
    let units = timingsUs.map { $0 / 10 }
    let sum = units.reduce(0, +) % 65536
    var pkts: [[UInt8]] = [[1, 8, rnd, 0, 38, 0] + le16(units.count) + le16(sum)]
    var body: [UInt8] = []
    for u in units { body += le16(u) }
    var idx: UInt8 = 0
    var o = 0
    while o < body.count {
        let end = min(o + 18, body.count)
        pkts.append([2, idx] + Array(body[o..<end])); idx += 1; o = end
    }
    pkts.append([4, rnd, 0])
    return pkts
}

func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined(separator: " ") }

let args = Array(CommandLine.arguments.dropFirst())
let dry = args.contains("--dry-run")
let modeArg = args.first(where: { ["ir", "irble", "ble"].contains($0) }) ?? "ir"
let mode: UInt8 = ["ble": 1, "ir": 2, "irble": 3][modeArg]!
let wanted = Set(args.filter { !$0.hasPrefix("--") && !["ir", "irble", "ble"].contains($0) }.map { $0.lowercased() })
let keys = samsung.filter { wanted.isEmpty || wanted.contains($0.name.lowercased()) }

// Ordered write plan: (label, bytes, pause after in seconds)
var plan: [(String, [UInt8], Double)] = []
for k in keys {
    if modeArg != "ble" {
        plan.append(("\(k.name): select key", [0x10, k.key], 0.5))
        for (i, p) in irPackets(samsungTimings(k.code), rnd: 42).enumerated() { plan.append(("\(k.name): packet \(i)", p, 0)) }
        plan.append(("\(k.name): pause", [], 0.3))
    }
    plan.append(("\(k.name): set mode \(modeArg)", [0x11, k.key, mode], 0.3))
}

if dry {
    for (l, b, _) in plan where !b.isEmpty { print(l.padding(toLength: 26, withPad: " ", startingAt: 0), hex(b)) }
    print("total writes:", plan.filter { !$0.1.isEmpty }.count); exit(0)
}

final class Prog: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var central: CBCentralManager!
    var target: CBPeripheral?
    var writeChar: CBCharacteristic?
    var step = 0
    override init() { super.init(); central = CBCentralManager(delegate: self, queue: nil) }
    func centralManagerDidUpdateState(_ c: CBCentralManager) { if c.state == .poweredOn { print("scanning..."); c.scanForPeripherals(withServices: nil) } }
    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? ""
        guard name.uppercased().contains("NOKIA"), target == nil else { return }
        print("found", name); target = p; c.stopScan(); p.delegate = self; c.connect(p)
    }
    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) { print("connected"); p.discoverServices([CBUUID(string: "00000AA0-3C17-D293-8E48-14FE2E4DA212")]) }
    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) { print("disconnected at step \(step)/\(plan.count):", String(describing: error)); exit(step >= plan.count ? 0 : 1) }
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) { for s in p.services ?? [] { p.discoverCharacteristics([CBUUID(string: "B002")], for: s) } }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        guard let ch = s.characteristics?.first else { print("B002 not found"); exit(2) }
        writeChar = ch; p.setNotifyValue(true, for: ch)
        run(p)
    }
    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        if let d = ch.value { print("  notify:", hex([UInt8](d))) }
    }
    func run(_ p: CBPeripheral) {
        guard step < plan.count else { print("done; waiting 2 s for notifications"); DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.central.cancelPeripheralConnection(p) }; return }
        let (label, bytes, pause) = plan[step]
        if bytes.isEmpty { step += 1; DispatchQueue.main.asyncAfter(deadline: .now() + pause) { self.run(p) }; return }
        print(label, hex(bytes))
        p.writeValue(Data(bytes), for: writeChar!, type: .withResponse)
    }
    func peripheral(_ p: CBPeripheral, didWriteValueFor ch: CBCharacteristic, error: Error?) {
        if let e = error { print("  WRITE ERROR:", (e as NSError).domain, (e as NSError).code, e.localizedDescription); exit(3) }
        let pause = plan[step].2; step += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + pause) { self.run(p) }
    }
}
let prog = Prog()
setbuf(stdout, nil)
DispatchQueue.main.asyncAfter(deadline: .now() + 60) { print("timeout"); exit(4) }
RunLoop.main.run()
