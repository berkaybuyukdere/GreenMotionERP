import Foundation
import Combine

@MainActor
final class WheelSysDailyViewViewModel: ObservableObject {

    @Published var selectedDay = WheelSysJournalService.todayZurich()
    @Published var station = "ZRH"
    @Published var selectedTab: WheelSysDailyViewTab = .checkouts
    @Published var searchText = ""
    @Published var loading = false
    @Published var errorMessage: String?

    @Published private(set) var snapshot: WheelSysDailyViewAllResult?

    private let franchiseId: String
    private var onSessionExpired: (() -> Void)?

    init(franchiseId: String, onSessionExpired: (() -> Void)? = nil) {
        self.franchiseId = franchiseId.uppercased()
        self.onSessionExpired = onSessionExpired
    }

    func loadDailyView() async {
        loading = true
        errorMessage = nil
        defer { loading = false }

        do {
            snapshot = try await WheelSysDailyViewService.loadAll(
                franchiseId: franchiseId,
                selectedDate: selectedDateString,
                station: station
            )
        } catch WheelSysDailyViewServiceError.notAuthenticated {
            errorMessage = WheelSysDailyViewServiceError.notAuthenticated.localizedDescription
        } catch {
            let message = error.localizedDescription
            if message.localizedCaseInsensitiveContains("session") {
                errorMessage = "wheelsys_journal.session_expired".localized
                onSessionExpired?()
            } else {
                errorMessage = message
            }
        }
    }

    func shiftDay(_ delta: Int) {
        if let next = WheelSysJournalService.zurichCalendar.date(byAdding: .day, value: delta, to: selectedDay) {
            selectedDay = WheelSysJournalService.startOfDayZurich(next)
        }
    }

    func goToToday() {
        selectedDay = WheelSysJournalService.todayZurich()
    }

    func setSelectedDay(_ day: Date) {
        selectedDay = WheelSysJournalService.startOfDayZurich(day)
    }

    func setStation(_ station: String) {
        self.station = station.uppercased()
    }

    func rows(for tab: WheelSysDailyViewTab) -> [WheelSysDailyViewRow] {
        guard let snapshot else { return [] }
        let mapped = WheelSysDailyViewRowMapper.rows(from: snapshot, tab: tab)
        return WheelSysDailyViewFilter.filterRows(mapped, query: searchText)
    }

    func count(for tab: WheelSysDailyViewTab) -> Int {
        guard let snapshot else { return 0 }
        switch tab {
        case .checkouts: return snapshot.checkouts.count
        case .checkins: return snapshot.checkins.count
        case .nonRevenue: return snapshot.nonRevenue.count
        case .available: return snapshot.available.count
        case .bookings: return snapshot.bookings.count
        }
    }

    private var selectedDateString: String {
        let df = DateFormatter()
        df.timeZone = WheelSysJournalService.zurichCalendar.timeZone
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: selectedDay)
    }
}
