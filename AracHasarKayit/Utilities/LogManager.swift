import Foundation
import SwiftyBeaver

/// Centralized logging manager using SwiftyBeaver
class LogManager {
    static let shared = LogManager()
    
    private let log = SwiftyBeaver.self
    
    private init() {
        setupLogging()
    }
    
    private func setupLogging() {
        // Console destination - for development
        let console = ConsoleDestination()
        console.format = "$DHH:mm:ss$d $C$L$c $N.$F:$l - $M"
        console.levelColor.verbose = "⚪"
        console.levelColor.debug = "🔵"
        console.levelColor.info = "🟢"
        console.levelColor.warning = "🟡"
        console.levelColor.error = "🔴"
        
        // File destination - for production logs
        let file = FileDestination()
        file.format = "$Dyyyy-MM-dd HH:mm:ss$d $L $N.$F:$l - $M"
        file.logFileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("app.log")
        
        // Add destinations
        log.addDestination(console)
        log.addDestination(file)
        
        // Set minimum log level based on build configuration
        #if DEBUG
        console.minLevel = .verbose
        #else
        console.minLevel = .info
        #endif
        
        file.minLevel = .debug
    }
    
    // MARK: - Public Logging Methods
    
    /// Log verbose messages (detailed debugging)
    func verbose(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log.verbose(message, file: file, function: function, line: line)
    }
    
    /// Log debug messages (development debugging)
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log.debug(message, file: file, function: function, line: line)
    }
    
    /// Log info messages (general information)
    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log.info(message, file: file, function: function, line: line)
    }
    
    /// Log warning messages (potential issues)
    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log.warning(message, file: file, function: function, line: line)
    }
    
    /// Log error messages (errors that need attention)
    func error(_ message: String, error err: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        if let err = err {
            log.error("\(message): \(err.localizedDescription)", file: file, function: function, line: line)
        } else {
            log.error(message, file: file, function: function, line: line)
        }
    }
    
    /// Convenience method for success messages (logs as info)
    func success(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log.info("✅ \(message)", file: file, function: function, line: line)
    }
    
    /// Firebase operation logging
    func firebase(_ message: String, operation: String = "", file: String = #file, function: String = #function, line: Int = #line) {
        let fullMessage = operation.isEmpty ? "[Firebase] \(message)" : "[Firebase \(operation)] \(message)"
        log.debug(fullMessage, file: file, function: function, line: line)
    }
}
