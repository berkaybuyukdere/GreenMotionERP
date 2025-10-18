import SwiftUI

/// Shuttle customer input section for Dashboard
struct ShuttleInputView: View {
    @StateObject private var shuttleManager = ShuttleManager.shared
    @State private var customerCount: String = ""
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showEndSessionAlert = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "bus.fill")
                    .font(.title2)
                    .foregroundColor(.cyan)
                
                Text("Shuttle Service")
                    .font(.headline)
                
                Spacer()
                
                // Session status indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(shuttleManager.currentSession != nil ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(shuttleManager.currentSession != nil ? "Active" : "Inactive")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            
            if shuttleManager.currentSession == nil {
                // Start Session Button
                Button {
                    shuttleManager.startDailySession()
                } label: {
                    HStack {
                        Image(systemName: "play.circle.fill")
                        Text("Start Shuttle Session")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.cyan)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
            } else {
                // Active session UI
                VStack(spacing: 12) {
                    // Session info
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Today's Total")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(shuttleManager.currentSession?.totalCustomers ?? 0) Customers")
                                .font(.title3)
                                .fontWeight(.bold)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Trips")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(shuttleManager.todayEntries.count)")
                                .font(.title3)
                                .fontWeight(.bold)
                        }
                    }
                    .padding()
                    .background(Color.cyan.opacity(0.1))
                    .cornerRadius(12)
                    
                    Divider()
                    
                    // Customer input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Customer Count")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        TextField("Enter number of customers", text: $customerCount)
                            .keyboardType(.numberPad)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(10)
                    }
                    
                    // Pick Up & Drop Off Buttons
                    HStack(spacing: 12) {
                        // Pick Up Button
                        Button {
                            dismissKeyboard()
                            submitEntry(type: .pickup)
                        } label: {
                            HStack {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Pick Up")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(customerCount.isEmpty || Int(customerCount) == nil ? Color.gray.opacity(0.3) : Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(customerCount.isEmpty || Int(customerCount) == nil || isLoading)
                        
                        // Drop Off Button
                        Button {
                            dismissKeyboard()
                            submitEntry(type: .dropoff)
                        } label: {
                            HStack {
                                Image(systemName: "arrow.up.circle.fill")
                                Text("Drop Off")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(customerCount.isEmpty || Int(customerCount) == nil ? Color.gray.opacity(0.3) : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(customerCount.isEmpty || Int(customerCount) == nil || isLoading)
                    }
                    
                    Divider()
                    
                    // End session button
                    Button {
                        dismissKeyboard()
                        showEndSessionAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "stop.circle.fill")
                            Text("End Today's Session")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .foregroundColor(.red)
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
            }
            
            // Recent entries
            if !shuttleManager.todayEntries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Pickups")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(shuttleManager.todayEntries.prefix(5)) { entry in
                                ShuttleEntryCard(entry: entry)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
        .padding(.vertical)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(16)
        .onTapGesture {
            dismissKeyboard()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("End Session", isPresented: $showEndSessionAlert) {
            Button("Cancel", role: .cancel) {}
            Button("End Session", role: .destructive) {
                endSession()
            }
        } message: {
            Text("Are you sure you want to end today's shuttle session? This will generate a daily report.")
        }
    }
    
    private func submitEntry(type: ShuttleEntryType) {
        guard let count = Int(customerCount), count > 0 else { return }
        
        isLoading = true
        
        Task {
            do {
                try await shuttleManager.addCustomerEntry(customerCount: count, entryType: type)
                
                // Reset form
                await MainActor.run {
                    customerCount = ""
                    isLoading = false
                    let message = type == .pickup ? "✓ Customers Picked Up" : "✓ Customers Dropped Off"
                    ToastManager.shared.show(message, type: .success)
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
    
    private func endSession() {
        dismissKeyboard()
        Task {
            do {
                try await shuttleManager.endDailySession()
                ToastManager.shared.show("✅ Session Ended", type: .success)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Shuttle Entry Card (Mini preview)

struct ShuttleEntryCard: View {
    let entry: ShuttleEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: entry.entryType.icon)
                    .font(.caption)
                    .foregroundColor(entry.entryType == .pickup ? .green : .blue)
                Text("\(entry.customerCount)")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            
            Text(entry.formattedTime)
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Text(entry.entryType.rawValue)
                .font(.caption2)
                .foregroundColor(entry.entryType == .pickup ? .green : .blue)
                .lineLimit(1)
        }
        .padding(10)
        .frame(width: 100)
        .background((entry.entryType == .pickup ? Color.green : Color.blue).opacity(0.1))
        .cornerRadius(10)
    }
}

// MARK: - Preview

struct ShuttleInputView_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            ShuttleInputView()
                .padding()
        }
    }
}
