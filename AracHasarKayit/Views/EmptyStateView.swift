import SwiftUI

/// Reusable empty state component with illustrations and messages
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var buttonText: String? = nil
    var buttonAction: (() -> Void)? = nil
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Animated Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color.gray.opacity(0.3), Color.gray.opacity(0.1)]
                                : [Color.gray.opacity(0.2), Color.gray.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Image(systemName: icon)
                    .font(.system(size: 50, weight: .light))
                    .foregroundColor(colorScheme == .dark ? .gray : .gray)
            }
            .padding(.bottom, 8)
            
            // Title
            Text(title)
                .font(AppTheme.titleFont)
                .foregroundColor(Color(.label))
            
            // Message
            Text(message)
                .font(AppTheme.bodyFont)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .lineLimit(3)
            
            // Optional Button
            if let buttonText = buttonText, let buttonAction = buttonAction {
                Button(action: buttonAction) {
                    Text(buttonText)
                }
                .buttonStyle(AppTheme.primaryButtonStyle)
                .frame(maxWidth: 200)
                .padding(.top, 8)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Pre-configured Empty States

/// Empty state for vehicles list
struct EmptyVehiclesView: View {
    var addVehicleAction: (() -> Void)? = nil
    
    var body: some View {
        EmptyStateView(
            icon: "car.circle.fill",
            title: "No Vehicles Yet",
            message: "Start by scanning a vehicle or adding one manually",
            buttonText: addVehicleAction != nil ? "Add Vehicle" : nil,
            buttonAction: addVehicleAction
        )
    }
}

/// Empty state for damage records
struct EmptyDamageRecordsView: View {
    var addDamageAction: (() -> Void)? = nil
    
    var body: some View {
        EmptyStateView(
            icon: "exclamationmark.triangle.fill",
            title: "No Damage Records",
            message: "All clear! No damage records found for this vehicle",
            buttonText: addDamageAction != nil ? "Add Damage Record" : nil,
            buttonAction: addDamageAction
        )
    }
}

/// Empty state for return records
struct EmptyReturnRecordsView: View {
    var addReturnAction: (() -> Void)? = nil
    
    var body: some View {
        EmptyStateView(
            icon: "arrow.uturn.backward.circle.fill",
            title: "No Return Records",
            message: "No return processes found for this vehicle",
            buttonText: addReturnAction != nil ? "Add Return" : nil,
            buttonAction: addReturnAction
        )
    }
}

/// Empty state for service records
struct EmptyServiceRecordsView: View {
    var addServiceAction: (() -> Void)? = nil
    
    var body: some View {
        EmptyStateView(
            icon: "wrench.and.screwdriver.fill",
            title: "No Service Records",
            message: "No service records found for this vehicle",
            buttonText: addServiceAction != nil ? "Add Service" : nil,
            buttonAction: addServiceAction
        )
    }
}

/// Empty state for reports
struct EmptyReportsView: View {
    var body: some View {
        EmptyStateView(
            icon: "doc.text.fill",
            title: "No Reports Available",
            message: "No reports found. Reports will appear here once created"
        )
    }
}

/// Empty state for search results
struct EmptySearchResultsView: View {
    let searchQuery: String
    
    var body: some View {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "No Results Found",
            message: "No items found matching '\(searchQuery)'"
        )
    }
}

#Preview {
    VStack(spacing: 20) {
        EmptyVehiclesView()
    }
    .padding()
}

