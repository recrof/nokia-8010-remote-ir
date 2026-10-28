import CoreBluetooth
import Foundation

final class Forcer: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var central: CBCentralManager!
    var target: CBPeripheral?
    var pending = 0
    override init() { super.init(); central = CBCentralManager(delegate: self, queue: nil) }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        print("state:", c.state.rawValue, "(5 = poweredOn)")
        if c.state == .poweredOn { c.scanForPeripherals(withServices: nil, options: nil); print("scanning...") }
    }
    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? ""
        guard name.uppercased().contains("NOKIA"), target == nil else { return }
        print("found", name, p.identifier, "rssi", rssi)
        target = p; c.stopScan(); p.delegate = self; c.connect(p, options: nil)
    }
    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) { print("connected"); p.discoverServices(nil) }
    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) { print("connect failed:", String(describing: error)) }
    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) { print("disconnected:", String(describing: error)) }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] { print("service", s.uuid); p.discoverCharacteristics(nil, for: s) }
    }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] {
            print("  char", ch.uuid, "props", ch.properties.rawValue)
            if ch.properties.contains(.read) { p.readValue(for: ch) }
            if ch.properties.contains(.notify) || ch.properties.contains(.indicate) { p.setNotifyValue(true, for: ch) }
        }
    }
    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        if let e = error { print("  read", ch.uuid, "ERROR", (e as NSError).domain, (e as NSError).code, e.localizedDescription) }
        else {
            let d = ch.value ?? Data()
            let hex = d.map { String(format: "%02x", $0) }.joined(separator: " ")
            let asc = String(d.map { ($0 >= 32 && $0 < 127) ? Character(UnicodeScalar($0)) : "." })
            print("  value", ch.uuid, "|", hex, "|", asc)
        }
    }
    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        if let e = error { print("  notify", ch.uuid, "ERROR", (e as NSError).code, e.localizedDescription) }
        else { print("  notify", ch.uuid, "on") }
    }
}
let f = Forcer()
setbuf(stdout, nil)
DispatchQueue.main.asyncAfter(deadline: .now() + 40) { print("timeout, exiting"); exit(0) }
RunLoop.main.run()
