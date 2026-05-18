import SwiftUI

/// İletişim izni satırları — genel kiralama koşulları PDF `{callPermission}` vb. ile eşleşir.
struct TurkeyMarketingConsentSection: View {
  @Binding var allowCall: Bool
  @Binding var allowEmail: Bool
  @Binding var allowSms: Bool
  var useEnglish: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("tr_terms.marketing_consent_header".localized)
        .font(.custom("Helvetica-Bold", size: 13))
      Text("tr_terms.marketing_consent_hint".localized)
        .font(.custom("Helvetica", size: 12))
        .foregroundStyle(.secondary)
      Toggle("tr_terms.marketing_consent_call".localized, isOn: $allowCall)
        .font(.custom("Helvetica", size: 14))
      Toggle("tr_terms.marketing_consent_email".localized, isOn: $allowEmail)
        .font(.custom("Helvetica", size: 14))
      Toggle("tr_terms.marketing_consent_sms".localized, isOn: $allowSms)
        .font(.custom("Helvetica", size: 14))
    }
    .padding(.vertical, 4)
  }
}

extension TurkeyRentalTermsFillContext {
  static func permissionLabel(allowed: Bool, useEnglish: Bool) -> String {
    if useEnglish { return allowed ? "YES" : "NO" }
    return allowed ? "EVET" : "HAYIR"
  }
}
