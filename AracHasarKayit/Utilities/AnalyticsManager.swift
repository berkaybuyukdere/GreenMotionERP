import Foundation
import FirebaseAnalytics

/// Analytics manager for tracking user behavior, performance metrics, and errors
class AnalyticsManager {
    static let shared = AnalyticsManager()
    
    private init() {
        // Analytics is automatically initialized by Firebase
        print("✅ AnalyticsManager initialized")
    }
    
    // MARK: - Event Tracking
    
    /// Track a custom event
    func logEvent(_ name: String, parameters: [String: Any]? = nil) {
        Analytics.logEvent(name, parameters: parameters)
        print("📊 Analytics Event: \(name)\(parameters != nil ? " - \(parameters!)" : "")")
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
        
        Analytics.logEvent(AnalyticsEventScreenView, parameters: parameters)
        print("📱 Screen View: \(screenName)")
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
}

