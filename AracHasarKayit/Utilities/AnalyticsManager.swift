import Foundation
import FirebaseAnalytics

/// Analytics manager for tracking user behavior, performance metrics, and errors
class AnalyticsManager {
    static let shared = AnalyticsManager()
    
    private init() {
        // Analytics is automatically initialized by Firebase
        print("✅ AnalyticsManager initialized")
    }
    
    // MARK: - Configuration
    
    /// Check if analytics tracking is enabled
    private var isTrackingEnabled: Bool {
        return UserDefaults.standard.bool(forKey: "analytics_enabled") ?? true
    }
    
    // MARK: - Safe Event Tracking (Core Method)
    
    /// Safe event tracking wrapper - never throws, never blocks UI
    private func safeTrackEvent(_ name: String, parameters: [String: Any]? = nil) {
        guard isTrackingEnabled else { return }
        
        // Run on background thread to not block UI
        DispatchQueue.global(qos: .utility).async { [weak self] in
            do {
                // Validate event name (Firebase requirements)
                let validatedName = self?.validateEventName(name) ?? name
                
                // Validate and sanitize parameters
                let validatedParams = self?.validateParameters(parameters) ?? parameters
                
                // Track event
                Analytics.logEvent(validatedName, parameters: validatedParams)
                
                #if DEBUG
                print("📊 Analytics Event: \(validatedName)\(validatedParams != nil ? " - \(validatedParams!)" : "")")
                #endif
            } catch {
                // Log error but don't crash - analytics is non-critical
                #if DEBUG
                print("⚠️ Analytics tracking error (non-critical): \(error.localizedDescription)")
                #endif
            }
        }
    }
    
    /// Validate event name according to Firebase requirements
    private func validateEventName(_ name: String) -> String {
        // Firebase event names: max 40 chars, alphanumeric + underscore
        var validated = name
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
        
        // Remove invalid characters
        validated = validated.filter { $0.isLetter || $0.isNumber || $0 == "_" }
        
        // Limit length
        if validated.count > 40 {
            validated = String(validated.prefix(40))
        }
        
        return validated.isEmpty ? "unnamed_event" : validated.lowercased()
    }
    
    /// Validate and sanitize parameters
    private func validateParameters(_ parameters: [String: Any]?) -> [String: Any]? {
        guard let params = parameters else { return nil }
        
        var validated: [String: Any] = [:]
        
        for (key, value) in params {
            // Validate key
            var validatedKey = key
                .replacingOccurrences(of: " ", with: "_")
                .replacingOccurrences(of: "-", with: "_")
            validatedKey = validatedKey.filter { $0.isLetter || $0.isNumber || $0 == "_" }
            
            if validatedKey.count > 40 {
                validatedKey = String(validatedKey.prefix(40))
            }
            
            // Validate value type (Firebase supports: String, Int, Double, Bool)
            if let stringValue = value as? String {
                validated[validatedKey.lowercased()] = String(stringValue.prefix(100)) // Limit string length
            } else if let intValue = value as? Int {
                validated[validatedKey.lowercased()] = intValue
            } else if let doubleValue = value as? Double {
                validated[validatedKey.lowercased()] = doubleValue
            } else if let boolValue = value as? Bool {
                validated[validatedKey.lowercased()] = boolValue
            } else {
                // Convert other types to string
                validated[validatedKey.lowercased()] = String(describing: value).prefix(100)
            }
        }
        
        return validated.isEmpty ? nil : validated
    }
    
    // MARK: - Event Tracking
    
    /// Track a custom event (safe wrapper)
    func logEvent(_ name: String, parameters: [String: Any]? = nil) {
        safeTrackEvent(name, parameters: parameters)
    }
    
    // MARK: - Feature Usage Tracking
    
    func trackFeatureUsage(_ feature: String, action: String, additionalInfo: [String: Any]? = nil) {
        var parameters: [String: Any] = [
            "feature": feature,
            "action": action
        ]
        
        if let additionalInfo = additionalInfo {
            parameters.merge(additionalInfo) { (_, new) in new }
        }
        
        logEvent("feature_usage", parameters: parameters)
    }
    
    // MARK: - Performance Metrics
    
    func trackPerformance(operation: String, duration: TimeInterval, success: Bool, additionalInfo: [String: Any]? = nil) {
        var parameters: [String: Any] = [
            "operation": operation,
            "duration": duration,
            "success": success
        ]
        
        if let additionalInfo = additionalInfo {
            parameters.merge(additionalInfo) { (_, new) in new }
        }
        
        logEvent("performance_metric", parameters: parameters)
    }
    
    func trackLoadTime(screen: String, loadTime: TimeInterval) {
        logEvent("screen_load_time", parameters: [
            "screen": screen,
            "load_time": loadTime
        ])
    }
    
    // MARK: - Error Tracking
    
    func trackError(_ error: Error, context: String, additionalInfo: [String: Any]? = nil) {
        var parameters: [String: Any] = [
            "error_domain": (error as NSError).domain,
            "error_code": (error as NSError).code,
            "error_description": error.localizedDescription,
            "context": context
        ]
        
        if let additionalInfo = additionalInfo {
            parameters.merge(additionalInfo) { (_, new) in new }
        }
        
        logEvent("error_occurred", parameters: parameters)
    }
    
    // MARK: - User Journey Tracking
    
    func trackScreenView(_ screenName: String, screenClass: String? = nil) {
        var parameters: [String: Any] = [
            AnalyticsParameterScreenName: screenName
        ]
        
        if let screenClass = screenClass {
            parameters[AnalyticsParameterScreenClass] = screenClass
        }
        
        safeTrackEvent(AnalyticsEventScreenView, parameters: parameters)
        
        #if DEBUG
        print("📱 Screen View: \(screenName)")
        #endif
    }
    
    /// Track screen exit (new method)
    func trackScreenExit(_ screenName: String, duration: TimeInterval? = nil) {
        var parameters: [String: Any] = [
            "screen_name": screenName
        ]
        
        if let duration = duration {
            parameters["duration_seconds"] = duration
        }
        
        safeTrackEvent("screen_exit", parameters: parameters)
    }
    
    func trackUserAction(action: String, screen: String, additionalInfo: [String: Any]? = nil) {
        var parameters: [String: Any] = [
            "action": action,
            "screen": screen
        ]
        
        if let additionalInfo = additionalInfo {
            parameters.merge(additionalInfo) { (_, new) in new }
        }
        
        logEvent("user_action", parameters: parameters)
    }
    
    // MARK: - Business Events
    
    func trackVehicleCreated(vehiclePlate: String, category: String) {
        logEvent("vehicle_created", parameters: [
            "vehicle_plate": vehiclePlate,
            "category": category
        ])
    }
    
    func trackDamageRecorded(vehiclePlate: String, resCode: String) {
        logEvent("damage_recorded", parameters: [
            "vehicle_plate": vehiclePlate,
            "res_code": resCode
        ])
    }
    
    func trackServiceRecorded(vehiclePlate: String, serviceType: String) {
        logEvent("service_recorded", parameters: [
            "vehicle_plate": vehiclePlate,
            "service_type": serviceType
        ])
    }
    
    func trackOfficeOperationCreated(operationType: String, amount: Double) {
        logEvent("office_operation_created", parameters: [
            "operation_type": operationType,
            "amount": amount
        ])
    }
    
    func trackReturnCreated(returnType: String, amount: Double) {
        logEvent("return_created", parameters: [
            "return_type": returnType,
            "amount": amount
        ])
    }
    
    // MARK: - CRUD Operations Tracking
    
    func trackVehicleUpdated(vehiclePlate: String) {
        logEvent("vehicle_updated", parameters: [
            "vehicle_plate": vehiclePlate
        ])
    }
    
    func trackVehicleDeleted(vehiclePlate: String) {
        logEvent("vehicle_deleted", parameters: [
            "vehicle_plate": vehiclePlate
        ])
    }
    
    func trackDamageUpdated(vehiclePlate: String, resCode: String) {
        logEvent("damage_updated", parameters: [
            "vehicle_plate": vehiclePlate,
            "res_code": resCode
        ])
    }
    
    func trackDamageDeleted(vehiclePlate: String, resCode: String) {
        logEvent("damage_deleted", parameters: [
            "vehicle_plate": vehiclePlate,
            "res_code": resCode
        ])
    }
    
    func trackServiceUpdated(vehiclePlate: String, serviceType: String) {
        logEvent("service_updated", parameters: [
            "vehicle_plate": vehiclePlate,
            "service_type": serviceType
        ])
    }
    
    func trackServiceDeleted(vehiclePlate: String, serviceType: String) {
        logEvent("service_deleted", parameters: [
            "vehicle_plate": vehiclePlate,
            "service_type": serviceType
        ])
    }
    
    func trackOfficeOperationUpdated(operationType: String, amount: Double) {
        logEvent("office_operation_updated", parameters: [
            "operation_type": operationType,
            "amount": amount
        ])
    }
    
    func trackOfficeOperationDeleted(operationType: String) {
        logEvent("office_operation_deleted", parameters: [
            "operation_type": operationType
        ])
    }
    
    func trackReturnUpdated(returnType: String, amount: Double) {
        logEvent("return_updated", parameters: [
            "return_type": returnType,
            "amount": amount
        ])
    }
    
    func trackReturnDeleted(returnType: String) {
        logEvent("return_deleted", parameters: [
            "return_type": returnType
        ])
    }
    
    func trackWorkScheduleCreated() {
        logEvent("work_schedule_created")
    }
    
    func trackWorkScheduleUpdated() {
        logEvent("work_schedule_updated")
    }
    
    func trackWorkScheduleDeleted() {
        logEvent("work_schedule_deleted")
    }
    
    // MARK: - Search and Filter Tracking
    
    func trackSearch(query: String, screen: String, resultsCount: Int) {
        logEvent("search_performed", parameters: [
            "query": query,
            "screen": screen,
            "results_count": resultsCount
        ])
    }
    
    func trackFilterApplied(filterType: String, screen: String, filterValue: String) {
        logEvent("filter_applied", parameters: [
            "filter_type": filterType,
            "screen": screen,
            "filter_value": filterValue
        ])
    }
    
    // MARK: - Export and Share Tracking
    
    func trackExport(type: String, format: String, itemCount: Int) {
        logEvent("export_performed", parameters: [
            "export_type": type,
            "format": format,
            "item_count": itemCount
        ])
    }
    
    func trackShare(type: String, method: String) {
        logEvent("share_performed", parameters: [
            "share_type": type,
            "method": method
        ])
    }
    
    // MARK: - Photo Operations
    
    func trackPhotoUploaded(count: Int, context: String) {
        logEvent("photo_uploaded", parameters: [
            "photo_count": count,
            "context": context
        ])
    }
    
    func trackPhotoDeleted(context: String) {
        logEvent("photo_deleted", parameters: [
            "context": context
        ])
    }
    
    // MARK: - Navigation Tracking
    
    func trackNavigation(from: String, to: String) {
        logEvent("navigation", parameters: [
            "from_screen": from,
            "to_screen": to
        ])
    }
    
    // MARK: - QR Code and Scanner
    
    func trackQRCodeScanned(success: Bool, context: String) {
        logEvent("qr_code_scanned", parameters: [
            "success": success,
            "context": context
        ])
    }
    
    func trackPlateScanned(success: Bool) {
        logEvent("plate_scanned", parameters: [
            "success": success
        ])
    }
    
    // MARK: - Shuttle Operations
    
    func trackShuttleSessionStarted() {
        logEvent("shuttle_session_started")
    }
    
    func trackShuttleSessionEnded(customerCount: Int, tripCount: Int) {
        logEvent("shuttle_session_ended", parameters: [
            "customer_count": customerCount,
            "trip_count": tripCount
        ])
    }
    
    func trackShuttleCustomerAdded() {
        logEvent("shuttle_customer_added")
    }
    
    // MARK: - User Properties
    
    func setUserProperty(_ value: String?, forName name: String) {
        Analytics.setUserProperty(value, forName: name)
    }
    
    func setUserId(_ userId: String?) {
        Analytics.setUserID(userId)
    }
    
    // MARK: - Button Tracking (New - Safe Methods)
    
    /// Track button tap - safe, non-blocking
    func trackButtonTap(action: String, screen: String, buttonLabel: String? = nil, parameters: [String: Any]? = nil) {
        var eventParams: [String: Any] = [
            "action": action,
            "screen": screen,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        if let buttonLabel = buttonLabel {
            eventParams["button_label"] = buttonLabel
        }
        
        if let additionalParams = parameters {
            eventParams.merge(additionalParams) { (_, new) in new }
        }
        
        safeTrackEvent("button_tap", parameters: eventParams)
    }
    
    // MARK: - Gesture Tracking (New)
    
    /// Track gesture interaction
    func trackGesture(gestureType: String, screen: String, direction: String? = nil, parameters: [String: Any]? = nil) {
        var eventParams: [String: Any] = [
            "gesture_type": gestureType,
            "screen": screen
        ]
        
        if let direction = direction {
            eventParams["direction"] = direction
        }
        
        if let additionalParams = parameters {
            eventParams.merge(additionalParams) { (_, new) in new }
        }
        
        safeTrackEvent("gesture_\(gestureType)", parameters: eventParams)
    }
    
    /// Track swipe gesture
    func trackSwipe(direction: String, screen: String, parameters: [String: Any]? = nil) {
        trackGesture(gestureType: "swipe", screen: screen, direction: direction, parameters: parameters)
    }
    
    /// Track long press gesture
    func trackLongPress(screen: String, parameters: [String: Any]? = nil) {
        trackGesture(gestureType: "long_press", screen: screen, parameters: parameters)
    }
    
    // MARK: - Tab Navigation Tracking (New)
    
    /// Track tab switch
    func trackTabSwitch(fromTab: String, toTab: String, tabIndex: Int? = nil) {
        var parameters: [String: Any] = [
            "from_tab": fromTab,
            "to_tab": toTab
        ]
        
        if let tabIndex = tabIndex {
            parameters["tab_index"] = tabIndex
        }
        
        safeTrackEvent("tab_switch", parameters: parameters)
    }
    
    // MARK: - Form Interaction Tracking (New)
    
    /// Track form field focus
    func trackFormFieldFocus(fieldName: String, screen: String) {
        safeTrackEvent("form_field_focus", parameters: [
            "field_name": fieldName,
            "screen": screen
        ])
    }
    
    /// Track form submission
    func trackFormSubmit(formName: String, screen: String, success: Bool, fieldCount: Int? = nil) {
        var parameters: [String: Any] = [
            "form_name": formName,
            "screen": screen,
            "success": success
        ]
        
        if let fieldCount = fieldCount {
            parameters["field_count"] = fieldCount
        }
        
        safeTrackEvent("form_submit", parameters: parameters)
    }
}

