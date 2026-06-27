/**
 * WheelSys vehicleview grid (mainviewex GetData) — full vehicle master list.
 */
/* eslint-disable max-len */

const {
  wheelsysFetchJson,
  parseWheelsysWebMethodObject,
  pickField,
  formatStationsLiteral,
  BASE_URL,
  UA,
  WheelsysClientError,
  ERR,
} = require("./client");
const {canonicalPlate} = require("./plateNormalize");

const MAINVIEW_PAGE = "/ui/manage/views/mainviewex.aspx";
const VEHICLE_VIEW_PAGE = "/ui/manage/views/vehicleview.aspx";
const GET_DATA_PATH = "/ui/manage/views/mainviewex.aspx/GetData";
const DEFAULT_PAGE_SIZE = 1000;

/**
 * @param {*} value
 * @return {number|null}
 */
function parseOptionalInt(value) {
  if (value == null || value === "") return null;
  const n = Number(value);
  return Number.isFinite(n) ? Math.trunc(n) : null;
}

/**
 * @param {*} value
 * @return {string|null}
 */
function parseOptionalString(value) {
  if (value == null) return null;
  const s = String(value).trim();
  return s || null;
}

/**
 * @param {string|null|undefined} raw
 * @return {Date|null}
 */
function parseOptionalDate(raw) {
  const s = parseOptionalString(raw);
  if (!s) return null;
  const iso = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (iso) {
    const d = new Date(`${iso[1]}-${iso[2]}-${iso[3]}T00:00:00.000Z`);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  const dmy = s.match(/^(\d{2})\/(\d{2})\/(\d{4})/);
  if (dmy) {
    const d = new Date(`${dmy[3]}-${dmy[2]}-${dmy[1]}T00:00:00.000Z`);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  const t = Date.parse(s);
  return Number.isNaN(t) ? null : new Date(t);
}

/**
 * @param {object} row
 * @return {boolean}
 */
function isDefleetedStatus(row) {
  const status = String(
      pickField(row, "CarStatus", "carStatus", "Status", "status") || "",
  ).toLowerCase();
  return status.includes("defleet");
}

/**
 * @param {object} row
 * @return {object}
 */
function normalizeVehicleMasterRow(row) {
  const id = parseOptionalInt(pickField(row, "Id", "id"));
  const plateNo = String(pickField(row, "Plateno", "plateno", "PlateNo", "Plate") || "");
  const carGroup = parseOptionalString(pickField(row, "CarGroup", "cargroup", "Group"));
  const categoryName = parseOptionalString(
      pickField(row, "CategoryName", "categoryName", "Category"),
  );
  const effectiveCategory = categoryName || carGroup;

  return {
    id: id,
    wheelsysVehicleId: id,
    codeId: parseOptionalInt(pickField(row, "Codeid", "codeid", "CodeId")),
    plateNo,
    normalizedPlate: canonicalPlate(plateNo),
    status: parseOptionalString(pickField(row, "CarStatus", "carStatus", "Status")),
    carGroup,
    categoryName,
    effectiveCategory,
    brandName: parseOptionalString(pickField(row, "CarBrandName", "carBrandName", "Brand")),
    modelName: parseOptionalString(pickField(row, "Model_Name", "model_Name", "ModelName", "Model")),
    modelYear: parseOptionalInt(pickField(row, "ModelYear", "modelYear")),
    modelSeats: parseOptionalInt(pickField(row, "ModelSeats", "modelSeats")),
    modelSeriesName: parseOptionalString(pickField(row, "ModelSeriesName", "modelSeriesName")),
    colorName: parseOptionalString(pickField(row, "ColorTable_Name", "colorTable_Name")),
    mileage: parseOptionalInt(pickField(row, "Mileage", "mileage")),
    mileageRestriction: parseOptionalInt(pickField(row, "MileageRestriction", "mileageRestriction")),
    fuel: parseOptionalInt(pickField(row, "Fuel", "fuel")),
    station: parseOptionalString(pickField(row, "Station", "station")),
    vin: parseOptionalString(pickField(row, "Vin", "vin", "VIN")),
    ownership: parseOptionalInt(pickField(row, "Ownership", "ownership")),
    poolType: parseOptionalInt(pickField(row, "PoolType", "poolType")),
    fuelTypeName: parseOptionalString(pickField(row, "fuelTypeName", "FuelTypeName")),
    engineNo: parseOptionalString(pickField(row, "EngineNo", "engineNo")),
    keyRef: parseOptionalString(pickField(row, "KeyRef", "keyRef")),
    firstLicenseDate: parseOptionalDate(pickField(row, "FirstLicenseDate", "firstLicenseDate")),
    purchaseDate: parseOptionalDate(pickField(row, "purchasedate", "purchaseDate", "PurchaseDate")),
    exitDate: parseOptionalDate(pickField(row, "Exitdate", "exitdate", "ExitDate")),
    plannedExitDate: parseOptionalDate(pickField(row, "PlannedExitDate", "plannedExitDate")),
    remainingMileage: parseOptionalInt(pickField(row, "RemainingMileage", "remainingMileage")),
    hasAttachments: pickField(row, "HasAttachments", "hasAttachments") === true ||
      String(pickField(row, "HasAttachments", "hasAttachments") || "").toLowerCase() === "true",
    isDefleeted: isDefleetedStatus(row),
    raw: row,
  };
}

/**
 * @param {object} opts
 * @return {object}
 */
function buildVehicleViewGetDataPayload(opts = {}) {
  const pageSize = Math.min(
      DEFAULT_PAGE_SIZE,
      Math.max(1, Number(opts.pageSize) || DEFAULT_PAGE_SIZE),
  );
  const page = Math.max(1, Number(opts.page) || 1);
  const dataSkip = (page - 1) * pageSize;
  const station = String(opts.station || "ZRH").trim().toUpperCase();

  return {
    searchField: String(opts.searchField || "Plateno"),
    searchValue: String(opts.searchValue || ""),
    viewName: String(opts.viewName || "vehicleview"),
    stations: formatStationsLiteral(station),
    status: String(opts.status || ""),
    dateStart: String(opts.dateStart || ""),
    dateEnd: String(opts.dateEnd || ""),
    searchUserId: String(opts.searchUserId || "1"),
    mongoSupport: "false",
    dataSize: String(pageSize),
    dataSkip: String(dataSkip),
    sortModel: opts.sortModel ||
      "[{'colId':'Plateno','sort':'asc'}]",
  };
}

/**
 * Warm vehicleview page context before grid fetch.
 * @param {string} cookie
 * @return {Promise<void>}
 */
async function warmVehicleViewPage(cookie) {
  const urls = [
    `${BASE_URL}${MAINVIEW_PAGE}`,
    `${BASE_URL}${VEHICLE_VIEW_PAGE}`,
  ];
  for (const url of urls) {
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
}

/**
 * @param {string} cookie
 * @param {object} opts
 * @return {Promise<object>}
 */
async function fetchVehicleListPage(cookie, opts = {}) {
  const station = String(opts.station || "ZRH").toUpperCase();
  const page = Math.max(1, Number(opts.page) || 1);
  const pageSize = Math.min(
      DEFAULT_PAGE_SIZE,
      Math.max(1, Number(opts.pageSize) || DEFAULT_PAGE_SIZE),
  );

  if (page === 1 && !opts.skipWarm) {
    await warmVehicleViewPage(cookie);
  }

  const authCookie = require("./cookieJar").buildFleetAuthCookie(cookie) || cookie;
  const baseOpts = {...opts, station, page, pageSize};
  const searchFields = opts.searchField ?
    [String(opts.searchField)] :
    ["Plateno", "Plate"];

  let lastError = null;
  for (const searchField of searchFields) {
    for (let attempt = 0; attempt < 3; attempt += 1) {
      try {
        if (attempt > 0) {
          await warmVehicleViewPage(authCookie);
          await new Promise((r) => setTimeout(r, 400 * attempt));
        }
        const payload = buildVehicleViewGetDataPayload({...baseOpts, searchField});
        const {outer, text} = await wheelsysFetchJson(authCookie, GET_DATA_PATH, payload, {
          referer: `${BASE_URL}${VEHICLE_VIEW_PAGE}`,
        });
        return parseVehicleListResponse(outer, text, {station, page, pageSize});
      } catch (e) {
        lastError = e;
        const is500 = e instanceof WheelsysClientError && e.httpStatus === 500;
        if (is500 && attempt < 2) {
          console.warn(
              `[WheelSys][VehicleMaster] GetData 500 retry attempt=${attempt + 1} field=${searchField}`,
          );
          continue;
        }
        if (!(e instanceof WheelsysClientError) ||
            e.code !== ERR.PARSE_FAILED ||
            e.httpStatus !== 500) {
          throw e;
        }
        break;
      }
    }
  }
  if (lastError) throw lastError;
  throw new WheelsysClientError(ERR.PARSE_FAILED, "WheelSys vehicle list request failed.");
}

/**
 * @param {object} outer
 * @param {string} text
 * @param {object} meta
 * @return {object}
 */
function parseVehicleListResponse(outer, text, meta) {
  const {station, page, pageSize} = meta;
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
        rawRows: [],
        rows: [],
        dataLength: 0,
        responseSuccess: Boolean(outer && outer.d && outer.d.success),
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
    rawRows,
    rows: rawRows.map(normalizeVehicleMasterRow),
    dataLength: String(text || "").length,
    responseSuccess: Boolean(outer && outer.d && outer.d.success !== false),
  };
}

/**
 * @param {object} a
 * @param {object} b
 * @param {string} station
 * @return {number}
 */
function compareDuplicateCandidates(a, b, station = "ZRH") {
  const stationUpper = String(station || "ZRH").toUpperCase();
  const score = (row) => {
    let s = 0;
    if (!row.isDefleeted) s += 100000;
    if (String(row.station || "").toUpperCase() === stationUpper) s += 10000;
    const exit = row.exitDate;
    if (!exit) {
      s += 5000;
    } else if (exit.getTime() > Date.now()) {
      s += 4000;
    }
    s += (row.id || 0);
    if (row.purchaseDate) s += row.purchaseDate.getTime() / 1e10;
    return s;
  };
  return score(b) - score(a);
}

/**
 * Resolve duplicate plates — prefer active ZRH records.
 * @param {object[]} vehicles normalized rows
 * @param {object} [opts]
 * @return {{vehicles: object[], duplicateWarnings: object[]}}
 */
function resolveDuplicatePlates(vehicles, opts = {}) {
  const station = String(opts.station || "ZRH").toUpperCase();
  const byPlate = new Map();
  const resolved = [];
  const duplicateWarnings = [];
  const noPlateRows = [];

  for (const v of vehicles) {
    const key = v.normalizedPlate;
    if (!key) {
      noPlateRows.push(v);
      continue;
    }
    if (!byPlate.has(key)) byPlate.set(key, []);
    byPlate.get(key).push(v);
  }

  for (const [plate, rows] of byPlate.entries()) {
    if (rows.length === 1) {
      resolved.push(rows[0]);
      continue;
    }
    const sorted = [...rows].sort((a, b) => compareDuplicateCandidates(a, b, station));
    const chosen = sorted[0];
    resolved.push(chosen);
    duplicateWarnings.push({
      normalizedPlate: plate,
      rowIds: rows.map((r) => r.id),
      chosenId: chosen.id,
    });
    console.warn(
        `[WheelSys][VehicleMaster] duplicate plate=${plate} rows=${rows.map((r) => r.id).join(",")} chosen=${chosen.id}`,
    );
  }

  resolved.push(...noPlateRows);

  return {vehicles: resolved, duplicateWarnings, noPlateCount: noPlateRows.length};
}

/**
 * @param {object[]} vehicles
 * @return {object}
 */
function computeVehicleStats(vehicles) {
  let defleetedCount = 0;
  let rentedCount = 0;
  let nonRevenueCount = 0;
  let availableCount = 0;
  let zeroMileageCount = 0;
  let zeroFuelCount = 0;

  for (const v of vehicles) {
    const status = String(v.status || "").toLowerCase();
    if (v.isDefleeted || status.includes("defleet")) {
      defleetedCount += 1;
    } else if (status.includes("rented")) {
      rentedCount += 1;
    } else if (status.includes("non revenue")) {
      nonRevenueCount += 1;
    } else if (status.includes("available")) {
      availableCount += 1;
    }
    if (v.mileage === 0) zeroMileageCount += 1;
    if (v.fuel === 0) zeroFuelCount += 1;
  }

  const activeCount = vehicles.length - defleetedCount;
  return {
    total: vehicles.length,
    activeCount,
    defleetedCount,
    rentedCount,
    nonRevenueCount,
    availableCount,
    zeroMileageCount,
    zeroFuelCount,
  };
}

/**
 * Fetch all vehicles with pagination.
 * @param {string} cookie
 * @param {object} [opts]
 * @return {Promise<object>}
 */
async function fetchAllVehicleMaster(cookie, opts = {}) {
  const station = String(opts.station || "ZRH").toUpperCase();
  const pageSize = Math.min(
      DEFAULT_PAGE_SIZE,
      Math.max(1, Number(opts.pageSize) || DEFAULT_PAGE_SIZE),
  );

  console.info(`[WheelSys][VehicleMaster] fetch started station=${station}`);

  const allRaw = [];
  let page = 1;
  let totalCount = null;
  let responseSuccess = true;
  let dataLength = 0;
  let truncated = false;

  let keepFetching = true;

  while (keepFetching) {
    const batch = await fetchVehicleListPage(cookie, {
      ...opts,
      station,
      page,
      pageSize,
      skipWarm: page > 1,
    });
    responseSuccess = responseSuccess && batch.responseSuccess !== false;
    dataLength += batch.dataLength || 0;
    if (totalCount == null) totalCount = batch.totalCount;
    allRaw.push(...batch.rawRows);

    if (batch.rawRows.length < pageSize) {
      keepFetching = false;
      break;
    }
    if (totalCount != null && allRaw.length >= totalCount) {
      keepFetching = false;
      break;
    }
    page += 1;
    if (page > 50) {
      truncated = true;
      console.warn("[WheelSys][VehicleMaster] pagination cap reached (50 pages)");
      break;
    }
  }

  console.info(
      `[WheelSys][VehicleMaster] response success=${responseSuccess} dataLength=${dataLength}`,
  );

  const normalized = allRaw.map(normalizeVehicleMasterRow);
  console.info(`[WheelSys][VehicleMaster] parsed vehicles=${normalized.length}`);

  const {vehicles, duplicateWarnings, noPlateCount} = resolveDuplicatePlates(normalized, {station});
  const stats = computeVehicleStats(vehicles);

  console.info(
      `[WheelSys][VehicleMaster] active=${stats.activeCount} defleeted=${stats.defleetedCount} ` +
      `rented=${stats.rentedCount} nonRevenue=${stats.nonRevenueCount} available=${stats.availableCount}`,
  );
  console.info(
      `[WheelSys][VehicleMaster] zeroMileage=${stats.zeroMileageCount} zeroFuel=${stats.zeroFuelCount}`,
  );

  return {
    station,
    vehicles,
    allRowsCount: normalized.length,
    duplicateWarnings,
    noPlateCount,
    stats,
    totalCount: totalCount != null ? totalCount : normalized.length,
    responseSuccess,
    truncated,
    pagesFetched: page,
  };
}

module.exports = {
  VEHICLE_VIEW_PAGE,
  GET_DATA_PATH,
  buildVehicleViewGetDataPayload,
  normalizeVehicleMasterRow,
  fetchVehicleListPage,
  fetchAllVehicleMaster,
  resolveDuplicatePlates,
  computeVehicleStats,
  isDefleetedStatus,
};
