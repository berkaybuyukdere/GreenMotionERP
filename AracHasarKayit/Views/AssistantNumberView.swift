import SwiftUI

struct AssistantNumberView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    
    @State private var companyName = ""
    @State private var phoneNumber = ""
    @State private var showAddCompany = false
    @State private var editingCompany: AssistantCompany?
    @State private var showDeleteConfirmation = false
    @State private var companyToDelete: AssistantCompany?
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    Button {
                        showAddCompany = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                            Text("Add New Company".localized)
                        }
                    }
                } header: {
                    Text("Assistant Companies".localized)
                } footer: {
                    Text("Manage assistant company records with names and phone numbers".localized)
                }
                
                if viewModel.assistantCompanies.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "building.2.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.gray.opacity(0.5))
                            Text("No Companies".localized)
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Add your first assistant company".localized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                } else {
                    ForEach(viewModel.assistantCompanies) { company in
                        CompanyRowView(company: company) {
                            editingCompany = company
                            companyName = company.name
                            phoneNumber = company.phoneNumber
                            showAddCompany = true
                        } onDelete: {
                            companyToDelete = company
                            showDeleteConfirmation = true
                        }
                    }
                }
            }
            .navigationTitle("Assistant Numbers".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done".localized) {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showAddCompany) {
                AddAssistantCompanyView(
                    companyName: $companyName,
                    phoneNumber: $phoneNumber,
                    editingCompany: editingCompany,
                    onSave: { name, phone in
                        let formattedPhone = AssistantCompany.formatSwissPhoneNumber(phone)
                        let currentUserId = authManager.currentUser?.uid
                        
                        if let editing = editingCompany {
                            var updated = editing
                            updated.name = name
                            updated.phoneNumber = formattedPhone
                            viewModel.assistantCompanyGuncelle(updated)
                        } else {
                            let newCompany = AssistantCompany(
                                name: name,
                                phoneNumber: formattedPhone,
                                createdBy: currentUserId
                            )
                            viewModel.assistantCompanyEkle(newCompany)
                        }
                        
                        // Reset
                        companyName = ""
                        phoneNumber = ""
                        editingCompany = nil
                        showAddCompany = false
                    },
                    onCancel: {
                        companyName = ""
                        phoneNumber = ""
                        editingCompany = nil
                        showAddCompany = false
                    }
                )
            }
            .alert("Delete Company".localized, isPresented: $showDeleteConfirmation) {
                Button("Cancel".localized, role: .cancel) { }
                Button("Delete".localized, role: .destructive) {
                    if let company = companyToDelete {
                        viewModel.assistantCompanySil(company)
                        companyToDelete = nil
                    }
                }
            } message: {
                Text("Are you sure you want to delete \(companyToDelete?.name ?? "this company".localized)?")
            }
        }
    }
}

struct CompanyRowView: View {
    let company: AssistantCompany
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(company.name)
                    .font(.headline)
                
                HStack(spacing: 8) {
                    Image(systemName: "phone.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(company.phoneNumber)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                }
                
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash.circle.fill")
                        .foregroundColor(.red)
                        .font(.title3)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct AddAssistantCompanyView: View {
    @Binding var companyName: String
    @Binding var phoneNumber: String
    var editingCompany: AssistantCompany?
    let onSave: (String, String) -> Void
    let onCancel: () -> Void
    
    @State private var phoneNumberError: String?
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Company Name".localized, text: $companyName)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Company Information".localized)
                }
                
                Section {
                    TextField("Phone number Swiss format placeholder".localized, text: $phoneNumber)
                        .keyboardType(.phonePad)
                        .onChange(of: phoneNumber) { oldValue, newValue in
                            phoneNumberError = nil
                            
                            // Boşlukları ve tireleri temizle, sadece rakam ve + karakterine izin ver
                            let cleaned = newValue.replacingOccurrences(of: " ", with: "")
                                .replacingOccurrences(of: "-", with: "")
                                .filter { $0.isNumber || $0 == "+" }
                            
                            // Eğer temizlenmiş hali farklıysa formatla
                            if cleaned != newValue.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "") {
                                // Formatlama yap
                                if cleaned.hasPrefix("+41") {
                                    let numberPart = String(cleaned.dropFirst(3))
                                    if numberPart.count <= 9 && numberPart.allSatisfy({ $0.isNumber }) {
                                        phoneNumber = formatPhoneNumber(prefix: "+41", number: numberPart)
                                        return
                                    }
                                } else if cleaned.hasPrefix("0") {
                                    if cleaned.count <= 10 && cleaned.allSatisfy({ $0.isNumber }) {
                                        phoneNumber = formatPhoneNumber(prefix: "0", number: String(cleaned.dropFirst(1)))
                                        return
                                    }
                                }
                                
                                // Eğer formatlanamazsa sadece temizlenmiş halini göster
                                phoneNumber = cleaned
                            } else {
                                // Mevcut değeri temizle ve formatla
                                let currentCleaned = phoneNumber.replacingOccurrences(of: " ", with: "")
                                    .replacingOccurrences(of: "-", with: "")
                                
                                if currentCleaned.hasPrefix("+41") {
                                    let numberPart = String(currentCleaned.dropFirst(3))
                                    if numberPart.count <= 9 && numberPart.allSatisfy({ $0.isNumber }) {
                                        let formatted = formatPhoneNumber(prefix: "+41", number: numberPart)
                                        if formatted != phoneNumber {
                                            phoneNumber = formatted
                                        }
                                    }
                                } else if currentCleaned.hasPrefix("0") {
                                    if currentCleaned.count <= 10 && currentCleaned.allSatisfy({ $0.isNumber }) {
                                        let formatted = formatPhoneNumber(prefix: "0", number: String(currentCleaned.dropFirst(1)))
                                        if formatted != phoneNumber {
                                            phoneNumber = formatted
                                        }
                                    }
                                }
                            }
                        }
                    
                    if let error = phoneNumberError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                } header: {
                    Text("Phone Number".localized)
                } footer: {
                    Text("Enter phone number in Swiss format: +41 XX XXX XX XX or 0XX XXX XX XX".localized)
                }
            }
            .navigationTitle(editingCompany == nil ? "Add Company".localized : "Edit Company".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel".localized) {
                        onCancel()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save".localized) {
                        if validateInputs() {
                            onSave(companyName, phoneNumber)
                        }
                    }
                    .disabled(companyName.isEmpty || phoneNumber.isEmpty)
                }
            }
        }
    }
    
    private func formatPhoneNumber(prefix: String, number: String) -> String {
        let chars = Array(number)
        var formatted = prefix
        
        if prefix == "+41" {
            formatted += " "
            if chars.count >= 2 {
                formatted += String(chars[0..<2])
            }
            if chars.count > 2 {
                formatted += " "
                if chars.count >= 5 {
                    formatted += String(chars[2..<5])
                } else {
                    formatted += String(chars[2...])
                }
            }
            if chars.count > 5 {
                formatted += " "
                if chars.count >= 7 {
                    formatted += String(chars[5..<7])
                } else {
                    formatted += String(chars[5...])
                }
            }
            if chars.count > 7 {
                formatted += " "
                formatted += String(chars[7...])
            }
        } else if prefix == "0" {
            formatted += " "
            if chars.count >= 2 {
                formatted += String(chars[0..<2])
            } else if chars.count > 0 {
                formatted += String(chars[0...])
            }
            if chars.count > 2 {
                formatted += " "
                if chars.count >= 5 {
                    formatted += String(chars[2..<5])
                } else {
                    formatted += String(chars[2...])
                }
            }
            if chars.count > 5 {
                formatted += " "
                if chars.count >= 7 {
                    formatted += String(chars[5..<7])
                } else {
                    formatted += String(chars[5...])
                }
            }
            if chars.count > 7 {
                formatted += " "
                formatted += String(chars[7...])
            }
        }
        
        return formatted
    }
    
    private func validateInputs() -> Bool {
        guard !companyName.isEmpty else {
            phoneNumberError = "Company name is required".localized
            return false
        }
        
        guard !phoneNumber.isEmpty else {
            phoneNumberError = "Phone number is required".localized
            return false
        }
        
        // Validate Swiss phone number format (temizlenmiş halini kontrol et)
        let cleaned = phoneNumber.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
        
        if !AssistantCompany.isValidSwissPhoneNumber(cleaned) {
            phoneNumberError = "Please enter a valid Swiss phone number".localized
            return false
        }
        
        phoneNumberError = nil
        return true
    }
}


