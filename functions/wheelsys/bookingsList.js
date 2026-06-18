/**
 * WheelSys mainviewex booking grid (bookingview).
 */
/* eslint-disable max-len */

const {
  wheelsysFetchJson,
  parseWheelsysWebMethodObject,
  pickField,
  formatStationsLiteral,
  normalizePlate,
  BASE_URL,
  WheelsysClientError,
  ERR,
  UA,
} = require("./client");
const {
  looksLikeResNo,
  pickResNoFromRow,
  pickAgentConfirmationFromRow,
} = require("./resCodeHelpers");

const MAINVIEW_PAGE = "/ui/manage/views/mainviewex.aspx";
const BOOKING_VIEW_PAGE = "/ui/manage/views/bookingview.aspx";
const GET_DATA_PATH = "/ui/manage/views/mainviewex.aspx/GetData";

/**
 * @param {object} row
 * @return {object}
 */
function normalizeBookingListRow(row) {
  const plate = String(pickField(row, "PlateNo", "plateno", "Plate") || "");
  const resNo = pickResNoFromRow(row);
  const agentConf = pickAgentConfirmationFromRow(row);
  return {
    entityId: pickField(
        row,
        "EntityId", "entityId", "BookingTable_Id", "bookingTable_Id",
        "Id", "id",
    ),
    displayDocNo: String(pickField(row, "DisplayDocNo", "displaydocno", "DocNo") || ""),
    confirmationNo: agentConf || String(pickField(row, "ConfirmationNo", "confirmationno") || ""),
    resNo,
    driverName: String(pickField(row, "DriverName", "drivername", "Customer") || ""),
    plate,
    normalizedPlate: normalizePlate(plate),
    carGroup: String(pickField(row, "CarGroup", "cargroup", "Group") || ""),
    dateFrom: pickField(row, "DateFrom", "datefrom"),
    dateTo: pickField(row, "DateTo", "dateto"),
    status: pickField(row, "Status", "status"),
    agent: String(pickField(row, "Agent", "agent") || ""),
    stationFrom: String(pickField(row, "StationFrom", "stationFrom", "Station") || ""),
    stationTo: String(pickField(row, "StationTo", "stationTo") || ""),
    chargeTotal: pickField(row, "ChargeTotal", "chargeTotal", "Total"),
    raw: row,
  };
}

/**
 * WheelSys bookingview GetData payload (mainviewex).
 * @param {object} opts
 * @return {object}
 */
function buildBookingViewGetDataPayload(opts = {}) {
  const pageSize = Math.min(200, Math.max(1, Number(opts.pageSize) || 50));
  const page = Math.max(1, Number(opts.page) || 1);
  const dataSkip = (page - 1) * pageSize;
  const searchValue = String(opts.searchValue || opts.searchText || opts.query || "").trim();
  let searchField = String(opts.searchField || "").trim();
  if (!searchField && searchValue) {
    searchField = looksLikeResNo(searchValue) ? "ConfirmationNo" : "DisplayDocNo";
  }

  const sortField = String(opts.sortField || opts.sort || "DateFrom").trim();
  const sortDir = String(opts.sortDir || opts.sortDirection || "asc").trim().toLowerCase();

  return {
    searchField,
    searchValue,
    viewName: String(opts.viewName || "bookingview"),
    stations: formatStationsLiteral(opts.station || "ZRH"),
    status: String(opts.status || ""),
    dateStart: String(opts.dateStart || ""),
    dateEnd: String(opts.dateEnd || ""),
    searchUserId: String(opts.searchUserId || "1"),
    mongoSupport: "false",
    dataSize: String(pageSize),
    dataSkip: String(dataSkip),
    sortModel: opts.sortModel ||
      JSON.stringify([{colId: sortField, sort: sortDir}]),
  };
}

/**
 * Warm bookingview page context before grid search.
 * @param {string} cookie
 * @return {Promise<void>}
 */
async function warmBookingViewPage(cookie) {
  const url = `${BASE_URL}${BOOKING_VIEW_PAGE}`;
  try {
    await fetch(url, {
      headers: {
        "Cookie": cookie,
        "User-Agent": UA,
        "Accept": "text/html,application/xhtml+xml",
      },
      redirect: "follow",
    });
  } catch (_) {
    // non-fatal
  }
}

/**
 * @param {string} cookie
 * @param {object} opts
 * @return {Promise<object>}
 */
async function searchBookingsList(cookie, opts = {}) {
  const station = String(opts.station || "ZRH").toUpperCase();
  const page = Math.max(1, Number(opts.page) || 1);
  const pageSize = Math.min(200, Math.max(1, Number(opts.pageSize) || 50));
  const searchValue = String(opts.searchValue || opts.searchText || opts.query || "").trim();

  if (searchValue) {
    await warmBookingViewPage(cookie);
  }

  const payload = buildBookingViewGetDataPayload({
    ...opts,
    station,
    page,
    pageSize,
    searchValue,
  });

  const {outer} = await wheelsysFetchJson(cookie, GET_DATA_PATH, payload, {
    referer: `${BASE_URL}${BOOKING_VIEW_PAGE}`,
  });

  let parsed;
  try {
    parsed = parseWheelsysWebMethodObject(outer);
  } catch (e) {
    if (e instanceof WheelsysClientError && e.code === ERR.NO_DATA) {
      return {
        station,
        page,
        pageSize,
        totalCount: 0,
        rows: [],
        rawRows: [],
        searchField: payload.searchField,
        searchValue,
      };
    }
    throw e;
  }

  const rawRows = Array.isArray(parsed) ?
    parsed :
    (
      (parsed && parsed.rows) ||
      (parsed && parsed.data) ||
      (parsed && parsed.Data) ||
      (parsed && parsed.Items) ||
      []
    );
  const totalCount = Number(
      pickField(parsed, "totalCount", "TotalCount", "total", "Total") ||
      rawRows.length,
  );

  return {
    station,
    page,
    pageSize,
    totalCount: Number.isFinite(totalCount) ? totalCount : rawRows.length,
    searchField: payload.searchField,
    searchValue,
    rows: rawRows.map(normalizeBookingListRow),
    rawRows,
    meta: parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : null,
  };
}

/**
 * Collect booking entity ids via bookingview searches (DisplayDocNo / RES).
 * @param {string} cookie
 * @param {object} opts
 * @return {Promise<string[]>}
 */
async function findBookingEntityIdsFromList(cookie, opts = {}) {
  const ids = [];
  const push = (id) => {
    const s = String(id || "").trim();
    if (/^\d+$/.test(s) && !ids.includes(s)) ids.push(s);
  };

  const displayDocNo = String(opts.displayDocNo || "").trim();
  const resNo = String(opts.resNo || "").trim();
  const station = String(opts.station || "ZRH").toUpperCase();

  const searches = [];
  if (displayDocNo) {
    searches.push({searchField: "DisplayDocNo", searchValue: displayDocNo});
    searches.push({searchField: "ConfirmationNo", searchValue: displayDocNo});
  }
  if (resNo) {
    searches.push({searchField: "ConfirmationNo", searchValue: resNo});
    if (looksLikeResNo(resNo)) {
      searches.push({searchField: "ResNo", searchValue: resNo});
    }
  }

  for (const search of searches) {
    try {
      const list = await searchBookingsList(cookie, {
        station,
        pageSize: 15,
        ...search,
      });
      for (const row of list.rows || []) {
        push(row.entityId);
      }
    } catch (_) {
      // try next search variant
    }
  }

  return ids;
}

module.exports = {
  MAINVIEW_PAGE,
  BOOKING_VIEW_PAGE,
  GET_DATA_PATH,
  buildBookingViewGetDataPayload,
  normalizeBookingListRow,
  searchBookingsList,
  findBookingEntityIdsFromList,
  warmBookingViewPage,
};
