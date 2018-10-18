//
//  BLEManager.swift
//  smartdesk
//
//  Created by Jing Wei Li on 10/10/18.
//  Copyright © 2018 Jing Wei Li. All rights reserved.
//

import Foundation
import CoreBluetooth

/**
 * Note: dispatch to the main thread when interacting with this class
 */
class BLEManager: NSObject {
    
    static let current = BLEManager()
    
    weak var delegate: BLEManagerDelegate?
    
    private var bluetoothManager: CBCentralManager!
    private var smartDesk: CBPeripheral?
    private var smartDeskDataPoint: CBCharacteristic?
    
    private let bleModuleUUID = CBUUID(string: "0xFFE0") // gorgeous!
    private let bleCharacteristicUUID = CBUUID(string: "0xFFE1")
    
    // if the connection request last more than 5s, then let the delegate know of the timeout error.
    private let timeOutInterval: TimeInterval = 5.0
    private var timeOutTimer: Timer?
    
    override init() {
        super.init()
        bluetoothManager = CBCentralManager(delegate: self, queue: DispatchQueue.global(qos: .userInitiated))
    }
    
    // MARK: - Instance methods
    func connect() {
        if bluetoothManager.state == .poweredOn {
            bluetoothManager.scanForPeripherals(withServices: [bleModuleUUID], options: nil)
            timeOutTimer = Timer.scheduledTimer(withTimeInterval: timeOutInterval,
                                                repeats: false) { [weak self] _ in
                self?.delegate?.didReceiveError(error: .timeOut)
                self?.bluetoothManager.stopScan()
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                if let strongSelf = self {
                    strongSelf.delegate?.didReceiveError(error:
                        BLEError.error(fromBLEState: strongSelf.bluetoothManager.state))
                }
            }
        }
    }
    
    func disconnect() {
        if let smartDeskUnwrapped = smartDesk {
            bluetoothManager.cancelPeripheralConnection(smartDeskUnwrapped)
            smartDesk = nil
            smartDeskDataPoint = nil
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.didDisconnectFromSmartDesk()
            }
        }
    }
    
    func send(string: String) {
        guard let peripheral = smartDesk, let characteristic = smartDeskDataPoint else {
            print("Not ready to send data")
            return
        }
        // note: will not work using the .withResponse type
        peripheral.writeValue(string.data(using: String.Encoding.utf8)!,
                              for: characteristic, type: .withoutResponse)
    }
    
    func readSignalStrength() {
        smartDesk?.readRSSI()
    }
}

extension BLEManager: CBCentralManagerDelegate {
    
    // MARK: - CBCentralManagerDelegate
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        handle(updatedState: central.state)
    }
    
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print(peripheral.debugDescription)
        // if you rename the ble module, there will be a newline. Be sure to remove it
        guard peripheral.name?.trimmingCharacters(in: .newlines) == "Hexapi" else { return }
        smartDesk = peripheral
        bluetoothManager.stopScan()
        bluetoothManager.connect(smartDesk!)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected")
        smartDesk?.delegate = self
        smartDesk?.discoverServices([bleModuleUUID])
    }
    
    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.didReceiveError(error: .peripheralDisconnected)
        }
    }
    
    func handle(updatedState state: CBManagerState) {
        DispatchQueue.main.async { [weak self] in
            switch state {
            case .poweredOff:
                print("BLE Manager Powered off State")
                self?.delegate?.didReceiveError(error: .bluetoothOff)
            case .poweredOn:
                print("BLE Manager Powered on State")
            default:
                if let error = BLEError.error(fromBLEState: state) {
                    self?.delegate?.didReceiveError(error: error)
                }
            }
        }
    }
}

extension BLEManager: CBPeripheralDelegate {
    // MARK: - CBPeripheralDelegate
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        guard services.count == 1 else {
            delegate?.didReceiveError(error: .genericError(error:
                NSError(domain: "Should only have 1 service", code: 0, userInfo: [:])))
            return
        }
        peripheral.discoverCharacteristics([bleCharacteristicUUID], for: services.first!)
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard error == nil else {
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.didReceiveError(error: .genericError(error: error))
            }
            return
        }
        guard let characteristics = service.characteristics, characteristics.count == 1 else {
            delegate?.didReceiveError(error: .unexpected)
            return
        }
        smartDeskDataPoint = characteristics.first!
        // at this point, cancel the timeout error message
        timeOutTimer?.invalidate()
        // listen for values sent from the BLE module
        smartDesk?.setNotifyValue(true, for: smartDeskDataPoint!)
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.readyToSendData()
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let data = characteristic.value {
            let byteArray = [UInt8](data)
            // Arduino Serial string encoding is ascii
            // this can only receive 4 bytes at a time (4 characters)
            if let asciiStr = String(bytes: byteArray, encoding: String.Encoding.ascii) {
                DispatchQueue.main.async { [weak self] in
                    print(asciiStr)
                    let str = asciiStr.contains("\r\n") ? BLEManager.string(ascii: asciiStr) : asciiStr
                    if let cmd = IncomingCommand(rawValue: str) {
                        self?.delegate?.didReceiveCommand(command: cmd)
                    } else {
                        self?.delegate?.didReceiveMessage(message: str)
                    }
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil else {
            delegate?.didReceiveError(error: .genericError(error: error))
            return
        }
        let dbm = RSSI.intValue
        DispatchQueue.main.async { [weak self] in
            guard let strongSelf = self else { return }
             strongSelf.delegate?.didReceiveRSSIReading(reading: dbm,
                                                        status: strongSelf.signalStrengthString(from: dbm))
        }
    }
    
    /** Metrics obtained from https://www.metageek.com/training/resources/understanding-rssi.html*/
    private func signalStrengthString(from dbm: Int) -> String {
        if dbm < -90 {
            return "Unusable"
        } else if dbm < -80 {
            return "Not good"
        } else if dbm < -70 {
            return "OK"
        } else if dbm < -67 {
            return "Good"
        }
        return "Amazing"
    }
}

extension BLEManager {
    // MARK: - Utilities
    
    /**
     * Convert to a string with letters (e.g. `"AB"`) from an ascii string such as
     * `"65\r\n66\r\n10"`.
     *   - Use this method when processing strings from the serial monitor
     */
    class func string(ascii asciiStr: String) -> String {
        var asciiArr = asciiStr.components(separatedBy: "\r\n")
        print(asciiArr)
        // remove the 10 and empty string
        asciiArr = asciiArr.filter { $0 != "10" && $0 != "" }
        let strArr = asciiArr.map { element -> String in
            guard let asciiNum = Int(element), let unicodeScalar = UnicodeScalar(asciiNum) else {
                return ""
            }
            return "\(Character(unicodeScalar))"
        }
        return strArr.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
