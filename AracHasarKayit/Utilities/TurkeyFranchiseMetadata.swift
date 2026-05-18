import Foundation

/// Türkiye franchise: trial Gmail şubeleri, e-posta konusu, ticari ünvan ve şube adı çözümlemesi.
enum TurkeyFranchiseMetadata {

  private static let trialBranchIds: Set<String> = [
    "TR_SABIHAGOKCEN",
    "TR_IST_SABIHA",
    "TR_NEVSEHIR",
  ]

  static func isTrialGmailFranchise(_ franchiseId: String?) -> Bool {
    let fid = normalizedFranchiseId(franchiseId)
    if trialBranchIds.contains(fid) { return true }
    if fid.contains("SABIHA") || fid.contains("SAW") { return true }
    if fid.contains("NEVSEHIR") || fid.contains("NEVŞEHIR") { return true }
    return false
  }

  static func normalizedFranchiseId(_ raw: String?) -> String {
    raw?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
  }

  /// Şube görünen adı: önce pickup/dropoff anahtarı, sonra franchise dokümanı / statik liste.
  static func branchDisplayTitle(
    pickUpBranch: String?,
    dropOffBranch: String?,
    preferDropOffForReturn: Bool,
    turkeyLocationBranches: [FranchiseGarageBranch],
    franchiseGarageBranches: [FranchiseGarageBranch]
  ) -> String {
    let pick = pickUpBranch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let drop = dropOffBranch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let primary = preferDropOffForReturn
      ? (drop.isEmpty ? pick : drop)
      : (pick.isEmpty ? drop : pick)
    if !primary.isEmpty {
      return title(forStoredKey: primary, candidates: turkeyLocationBranches + franchiseGarageBranches)
    }
    let session = TurkiyeGarajSubeleri.sessionBranchStorageKey()
    if !session.isEmpty {
      return title(forStoredKey: session, candidates: turkeyLocationBranches + franchiseGarageBranches)
    }
    return "—"
  }

  /// Kiraya veren ticari ünvanı: oturum `TR_*` franchise dokümanı adı, yoksa genel franchise adı.
  static func commercialTitle(
    franchiseDisplayName: String,
    turkeyLocationBranches: [FranchiseGarageBranch]
  ) -> String {
    let session = TurkiyeGarajSubeleri.sessionBranchStorageKey()
    if let match = turkeyLocationBranches.first(where: {
      $0.storageKey.uppercased() == session.uppercased()
        || TurkiyeGarajSubeleri.equivalentGarageBranchKeys($0.storageKey, session)
    }) {
      let name = match.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
      if !name.isEmpty { return name }
    }
    let fallback = franchiseDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
    return fallback.isEmpty ? "U-Save" : fallback
  }

  /// Trial Gmail şubeleri: `U-Save {Branch name}`.
  static func trialEmailSubject(
    franchiseId: String?,
    pickUpBranch: String?,
    dropOffBranch: String?,
    isReturn: Bool,
    turkeyLocationBranches: [FranchiseGarageBranch],
    franchiseGarageBranches: [FranchiseGarageBranch]
  ) -> String? {
    guard isTrialGmailFranchise(franchiseId) else { return nil }
    let branch = branchDisplayTitle(
      pickUpBranch: pickUpBranch,
      dropOffBranch: dropOffBranch,
      preferDropOffForReturn: isReturn,
      turkeyLocationBranches: turkeyLocationBranches,
      franchiseGarageBranches: franchiseGarageBranches
    )
    let label = branch == "—" ? TurkiyeGarajSubeleri.displayTitle(forStoredKey: franchiseId) : branch
    let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
  return "U-Save \(trimmed.isEmpty ? "Türkiye" : trimmed)"
  }

  private static func title(forStoredKey key: String, candidates: [FranchiseGarageBranch]) -> String {
    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "—" }
    if let m = candidates.first(where: {
      $0.storageKey.caseInsensitiveCompare(trimmed) == .orderedSame
        || TurkiyeGarajSubeleri.equivalentGarageBranchKeys($0.storageKey, trimmed)
    }) {
      return m.displayName
    }
    return TurkiyeGarajSubeleri.displayTitle(forStoredKey: trimmed)
  }
}
