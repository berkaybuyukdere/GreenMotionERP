import SwiftUI

struct CompanyPickerView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    @Binding var selectedCompany: AssistantCompany?
    
    var body: some View {
        NavigationView {
            List {
                if viewModel.assistantCompanies.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "building.2.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.gray.opacity(0.5))
                            Text("No Companies Available")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Add companies in Assistant Numbers section")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                } else {
                    ForEach(viewModel.assistantCompanies) { company in
                        Button {
                            selectedCompany = company
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(company.name)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
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
                                
                                if selectedCompany?.id == company.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                        .font(.title3)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Select Company")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

