/**
 * WheelSys Daily View dashboard tabs (checkouts, checkins, etc.).
 */
/* eslint-disable max-len */

const {
  buildOperationalDate,
  wheelsysFetchJson,
  parseWheelsysWebMethodArray,
  pickField,
  formatSelectedStations,
  normalizePlate,
  BASE_URL,
  WheelsysClientError,
  ERR,
} = require("./client");

const DAILY_VIEW_PAGE = "/ui/dashboards/dailyview.aspx";
const TAB_ENDPOINTS = {
  checkouts: "GetDataCheckouts",
  checkins: "GetDataCheckins",
  nonrevenue: "GetDataNonrevenue",
  available: "GetDataAvailable",
  bookings: "GetDataBookings",
};

/**
 * @param {object} row
 * @return {object}
 */
function normalizeDailyViewRow(row) {
  const plate = String(pickField(row, "PlateNo", "plateno", "Plate", "plate") || "");
  return {
    displayDocNo: String(pickField(row, "DisplayDocNo", "displaydocno", "DocNo") || ""),
    confirmationNo: String(pickField(row, "ConfirmationNo", "confirmationno", "ResNo") || ""),
    driverName: String(pickField(row, "DriverName", "drivername", "Customer") || ""),
    plate,
    normalizedPlate: normalizePlate(plate),
    carGroup: String(pickField(row, "CarGroup", "cargroup", "Group") || ""),
    model: String(pickField(row, "Model", "model", "ModelName") || ""),
    fuel: pickField(row, "Fuel", "fuel", "Tank"),
    mileage: pickField(row, "Mileage", "mileage", "Km"),
    dateFrom: pickField(row, "DateFrom", "datefrom", "StartDate"),
    dateTo: pickField(row, "DateTo", "dateto", "EndDate"),
    status: pickField(row, "Status", "status"),
    agent: String(pickField(row, "Agent", "agent", "Booker") || ""),
    station: String(pickField(row, "Station", "station") || ""),
    vehicleEntityId: pickField(row, "CarTable_Id", "carTable_Id", "CarId", "carId", "id"),
    rentalEntityId: pickField(row, "RentalTable_Id", "rentalTable_Id", "EntityId", "entityId"),
    domain: pickField(row, "Domain", "domain"),
    raw: row,
  };
}

/**
 * @param {string} cookie
 * @param {string} tab
 * @param {object} opts
 * @return {Promise<object>}
 */
async function fetchDailyViewTab(cookie, tab, opts = {}) {
  const tabKey = String(tab || "").toLowerCase();
  const endpoint = TAB_ENDPOINTS[tabKey];
  if (!endpoint) {
    throw new Error(`Unknown daily view tab: ${tab}`);
  }

  const station = String(opts.station || "ZRH").toUpperCase();
  const selectedDate = buildOperationalDate(
      opts.selectedDate || new Date(),
  );
  const payload = {
    SelectedDate: selectedDate,
    SelectedStations: formatSelectedStations(station),
    PendingOnly: Boolean(opts.pendingOnly),
    ForExport: Boolean(opts.forExport),
  };

  const dataPath = `${DAILY_VIEW_PAGE}/${endpoint}`;
  const pageUrl = `${BASE_URL}${DAILY_VIEW_PAGE}`;
  const {outer} = await wheelsysFetchJson(cookie, dataPath, payload, {
    referer: pageUrl,
  });

  let rows = [];
  try {
    rows = parseWheelsysWebMethodArray(outer);
  } catch (e) {
    if (e instanceof WheelsysClientError && e.code === ERR.NO_DATA) {
      rows = [];
    } else {
      throw e;
    }
  }

  return {
    tab: tabKey,
    selectedDate: selectedDate.slice(0, 10),
    station,
    count: rows.length,
    rows: rows.map(normalizeDailyViewRow),
    rawRows: rows,
  };
}

/**
 * @param {string} cookie
 * @param {object} opts
 * @return {Promise<object>}
 */
async function fetchDailyViewAll(cookie, opts = {}) {
  const tabs = Object.keys(TAB_ENDPOINTS);
  const results = {};
  await Promise.all(tabs.map(async (tab) => {
    results[tab] = await fetchDailyViewTab(cookie, tab, opts);
  }));
  return {
    selectedDate: results.checkouts.selectedDate,
    station: results.checkouts.station,
    tabs: results,
  };
}

module.exports = {
  DAILY_VIEW_PAGE,
  TAB_ENDPOINTS,
  normalizeDailyViewRow,
  fetchDailyViewTab,
  fetchDailyViewAll,
};
