import Foundation
import os.log

class CustomLogger {
    static let shared = CustomLogger()
    private let logger: Logger
    
    private init() {
        logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.polomaps", category: "AppLogs")
    }
    
    func log(_ message: String, type: OSLogType = .default) {
        logger.log(level: type, "\(message)")
    }
    
    func error(_ message: String) {
        log(message, type: .error)
    }
    
    func info(_ message: String) {
        log(message, type: .info)
    }
    
    func debug(_ message: String) {
        #if DEBUG
        log(message, type: .debug)
        #endif
    }
    
    func warning(_ message: String) {
        log(message, type: .default)
    }
}
