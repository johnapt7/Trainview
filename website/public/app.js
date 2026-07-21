(() => {
  "use strict";

  const config = window.TRAINVIEW_CONFIG || {};
  const API_BASE = (config.API_BASE || "").replace(/\/$/, "");
  const DEFAULT_STATION = config.DEFAULT_STATION || { crs: "KGX", name: "London King's Cross" };
  const REFRESH_INTERVAL = 45_000;
  const SAVED_STATIONS_KEY = "trainview.savedStations";
  const INTERCITY_CODES = new Set(["GR", "XC", "AW", "GW", "TP", "VT", "EM", "HT", "GC"]);

  const demoBoards = {
    departures: [
      { scheduledTime: "14:32", expectedTime: "On time", destination: "Edinburgh", destinationVia: "via York", platform: "3", operator: "LNER", operatorCode: "GR", status: "On time", serviceId: "demo-1", length: 9, rollingStock: { name: "Azuma" } },
      { scheduledTime: "14:40", expectedTime: "14:46", destination: "Cambridge", platform: "9", operator: "Great Northern", operatorCode: "GN", status: "Delayed", serviceId: "demo-2", length: 8 },
      { scheduledTime: "14:48", expectedTime: "On time", destination: "Leeds", destinationVia: "via Wakefield Westgate", platform: "1", operator: "LNER", operatorCode: "GR", status: "On time", serviceId: "demo-3", length: 9, rollingStock: { name: "Azuma" } },
      { scheduledTime: "14:56", expectedTime: "On time", destination: "Ely", platform: "10", operator: "Great Northern", operatorCode: "GN", status: "On time", serviceId: "demo-4", length: 8 },
      { scheduledTime: "15:03", expectedTime: "Cancelled", destination: "Peterborough", platform: "7", operator: "Thameslink", operatorCode: "TL", status: "Cancelled", isCancelled: true, serviceId: "demo-5" },
    ],
    arrivals: [
      { scheduledTime: "14:31", expectedTime: "On time", origin: "Newcastle", platform: "4", operator: "LNER", operatorCode: "GR", status: "On time", serviceId: "demo-a1", length: 9, rollingStock: { name: "Azuma" } },
      { scheduledTime: "14:38", expectedTime: "14:42", origin: "Cambridge", platform: "8", operator: "Great Northern", operatorCode: "GN", status: "Delayed", serviceId: "demo-a2", length: 8 },
      { scheduledTime: "14:45", expectedTime: "On time", origin: "Leeds", platform: "2", operator: "LNER", operatorCode: "GR", status: "On time", serviceId: "demo-a3", length: 9 },
      { scheduledTime: "14:53", expectedTime: "On time", origin: "King's Lynn", platform: "9", operator: "Great Northern", operatorCode: "GN", status: "On time", serviceId: "demo-a4", length: 8 },
      { scheduledTime: "15:01", expectedTime: "On time", origin: "Edinburgh", platform: "5", operator: "LNER", operatorCode: "GR", status: "On time", serviceId: "demo-a5", length: 9 },
    ],
  };

  const params = new URLSearchParams(window.location.search);
  const state = {
    station: getInitialStation(),
    mode: params.get("mode") === "arrivals" ? "arrivals" : "departures",
    filter: ["on-time", "intercity"].includes(params.get("filter")) ? params.get("filter") : "all",
    journey: getInitialJourney(),
    timeOffset: clamp(Number(params.get("offset")) || 0, -120, 120),
    services: [],
    savedStations: loadSavedStations(),
    boardController: null,
    stationSearchController: null,
    journeySearchController: null,
    refreshTimer: null,
    stationSearchTimer: null,
    journeySearchTimer: null,
    isDemo: false,
  };

  const elements = {
    board: document.querySelector(".board"),
    boardTitle: document.querySelector("#board-title"),
    boardKicker: document.querySelector("#board-kicker"),
    boardStatus: document.querySelector("#board-status"),
    boardTime: document.querySelector("#board-time"),
    boardNote: document.querySelector("#board-note"),
    list: document.querySelector("#service-list"),
    stationSearch: document.querySelector("#station-search"),
    stationResults: document.querySelector("#station-results"),
    stationCode: document.querySelector("#station-code"),
    saveStation: document.querySelector("#save-station"),
    savedStations: document.querySelector("#saved-stations"),
    journeyPicker: document.querySelector(".journey-picker"),
    journeySearch: document.querySelector("#journey-search"),
    journeyResults: document.querySelector("#journey-results"),
    journeyLabel: document.querySelector("#journey-label"),
    journeyDirection: document.querySelector("#journey-direction"),
    clearJourney: document.querySelector("#clear-journey"),
    timeOffset: document.querySelector("#time-offset"),
    refresh: document.querySelector("#refresh-board"),
    tallyOnTime: document.querySelector("#tally-on-time"),
    tallyDelayed: document.querySelector("#tally-delayed"),
    tallyCancelled: document.querySelector("#tally-cancelled"),
    disruptionBanner: document.querySelector("#disruption-banner"),
    disruptionToggle: document.querySelector("#disruption-toggle"),
    disruptionTitle: document.querySelector("#disruption-title"),
    disruptionSummary: document.querySelector("#disruption-summary"),
    disruptionDetails: document.querySelector("#disruption-details"),
    modeButtons: [...document.querySelectorAll("[data-mode]")],
    filterButtons: [...document.querySelectorAll("[data-filter]")],
    timeStepButtons: [...document.querySelectorAll("[data-time-step]")],
    appLinks: [...document.querySelectorAll(".app-link")],
  };

  function getInitialStation() {
    const crs = (params.get("station") || DEFAULT_STATION.crs).toUpperCase().slice(0, 3);
    const name = crs === DEFAULT_STATION.crs ? DEFAULT_STATION.name : crs;
    return { crs, name };
  }

  function getInitialJourney() {
    const crs = (params.get("callingAt") || "").toUpperCase().slice(0, 3);
    return crs ? { crs, name: crs } : null;
  }

  function loadSavedStations() {
    try {
      const saved = JSON.parse(localStorage.getItem(SAVED_STATIONS_KEY) || "[]");
      return Array.isArray(saved)
        ? saved.filter((item) => item && /^[A-Z]{3}$/.test(item.crs) && item.name).slice(0, 8)
        : [];
    } catch {
      return [];
    }
  }

  function clamp(value, minimum, maximum) {
    return Math.min(maximum, Math.max(minimum, value));
  }

  function text(value) {
    return document.createTextNode(value == null ? "" : String(value));
  }

  function node(tag, className, value) {
    const element = document.createElement(tag);
    if (className) element.className = className;
    if (value != null) element.append(text(value));
    return element;
  }

  function formatClock(date = new Date()) {
    return new Intl.DateTimeFormat("en-GB", { hour: "2-digit", minute: "2-digit", hour12: false }).format(date);
  }

  function shiftedClock() {
    return formatClock(new Date(Date.now() + state.timeOffset * 60_000));
  }

  function statusFor(service) {
    const raw = `${service.status || ""} ${service.expectedTime || ""}`.toLowerCase();
    if (service.isCancelled || raw.includes("cancel")) return "cancelled";
    const expectedIsTime = /^\d{2}:\d{2}$/.test(service.expectedTime || "");
    if (raw.includes("delay") || (expectedIsTime && service.expectedTime !== service.scheduledTime)) return "delayed";
    return "on-time";
  }

  function statusLabel(service, kind) {
    if (kind === "cancelled") return "Cancelled";
    if (kind === "delayed") return /^\d{2}:\d{2}$/.test(service.expectedTime || "") ? `Exp ${service.expectedTime}` : "Delayed";
    return service.expectedTime && !/^\d{2}:\d{2}$/.test(service.expectedTime) ? service.expectedTime : "On time";
  }

  function headline(service) {
    return state.mode === "arrivals"
      ? service.origin || "Origin unavailable"
      : service.destination || "Destination unavailable";
  }

  function rollingStockLabel(service) {
    if (service.rollingStock?.name) return service.rollingStock.name;
    if (service.rollingStock?.class) return `Class ${service.rollingStock.class}`;
    return "";
  }

  function serviceFacts(service) {
    return [
      service.operator,
      rollingStockLabel(service),
      service.length ? `${service.length} coaches` : "",
      service.destinationVia,
    ].filter(Boolean).join(" · ");
  }

  function buildServiceRow(service) {
    const kind = statusFor(service);
    const row = node("button", "service-row");
    row.type = "button";
    row.dataset.serviceId = service.serviceId || "";
    row.setAttribute("aria-expanded", "false");
    row.setAttribute("aria-label", `${service.scheduledTime}, ${state.mode === "arrivals" ? "from" : "to"} ${headline(service)}, platform ${service.platform || "not announced"}, ${statusLabel(service, kind)}`);

    const due = node("span", "service-row__time");
    if (kind === "delayed") {
      due.append(node("del", "", service.scheduledTime), node("em", "", service.expectedTime));
    } else {
      due.append(text(service.scheduledTime || "--:--"));
    }

    const destination = node("span", "service-row__destination");
    destination.append(node("strong", "", headline(service)), node("small", "", serviceFacts(service) || "Service information"));

    const platform = node("span", "service-row__platform");
    const usesPrediction = !service.platform && service.predictedPlatform?.platform;
    platform.append(node("small", "", usesPrediction ? "Predicted" : "Plat"), text(service.platform || service.predictedPlatform?.platform || "—"));

    row.append(due, destination, platform, node("span", `status-pill status-pill--${kind}`, statusLabel(service, kind)));
    row.addEventListener("click", () => toggleServiceDetails(row, service));
    return row;
  }

  function filteredServices() {
    if (state.filter === "on-time") return state.services.filter((service) => statusFor(service) === "on-time");
    if (state.filter === "intercity") return state.services.filter((service) => INTERCITY_CODES.has(service.operatorCode));
    return state.services;
  }

  function updateTally() {
    const counts = { "on-time": 0, delayed: 0, cancelled: 0 };
    state.services.forEach((service) => { counts[statusFor(service)] += 1; });
    elements.tallyOnTime.textContent = counts["on-time"];
    elements.tallyDelayed.textContent = counts.delayed;
    elements.tallyCancelled.textContent = counts.cancelled;
  }

  function renderServices() {
    const services = filteredServices();
    elements.list.replaceChildren();
    if (!services.length) {
      const empty = node("div", "empty-state");
      const copy = node("div");
      copy.append(
        node("strong", "", `No matching ${state.mode}`),
        text(state.filter === "all" ? "Try another station, destination or time." : "Choose another service filter to see more trains.")
      );
      empty.append(copy);
      elements.list.append(empty);
      return;
    }
    services.slice(0, 8).forEach((service) => elements.list.append(buildServiceRow(service)));
    const visible = Math.min(services.length, 8);
    elements.boardNote.textContent = `${visible} of ${services.length} services shown · refreshes automatically.`;
  }

  async function toggleServiceDetails(row, service) {
    const existing = row.nextElementSibling;
    if (existing?.classList.contains("service-details")) {
      existing.remove();
      row.setAttribute("aria-expanded", "false");
      return;
    }

    document.querySelectorAll(".service-details").forEach((detail) => detail.remove());
    document.querySelectorAll(".service-row[aria-expanded='true']").forEach((openRow) => openRow.setAttribute("aria-expanded", "false"));
    row.setAttribute("aria-expanded", "true");

    const detail = node("div", "service-details");
    detail.append(node("div", "service-details__label", "Journey"), node("div", "service-details__content", "Loading route…"));
    row.after(detail);

    const inlinePoints = state.mode === "arrivals" ? service.previousCallingPoints : service.subsequentCallingPoints;
    if (Array.isArray(inlinePoints) && inlinePoints.length) {
      renderServiceDetails(detail, service, inlinePoints, service);
      return;
    }
    if (String(service.serviceId || "").startsWith("demo-")) {
      renderServiceDetails(detail, service, [], service);
      return;
    }

    try {
      const response = await fetch(`${API_BASE}/service/${encodeURIComponent(service.serviceId)}`);
      if (!response.ok) throw new Error(`Service request failed: ${response.status}`);
      const data = await response.json();
      const points = state.mode === "arrivals" ? data.previousCallingPoints : data.subsequentCallingPoints;
      renderServiceDetails(detail, service, points || [], data);
    } catch {
      detail.lastElementChild.replaceWith(node("div", "service-details__content", "Route information is temporarily unavailable."));
    }
  }

  function renderServiceDetails(detail, service, points, data) {
    const content = node("div", "service-details__content");
    const meta = node("div", "service-details__meta");
    [
      data.operator || service.operator,
      rollingStockLabel(service),
      (data.length || service.length) ? `${data.length || service.length} coaches` : "",
      service.platform ? `Platform ${service.platform}` : "Platform pending",
    ].filter(Boolean).forEach((fact) => meta.append(node("span", "", fact)));
    content.append(meta);

    const reason = data.cancelReason || data.delayReason || service.cancelReason || service.delayReason;
    if (reason) content.append(node("p", "service-details__reason", reason));

    if (points.length) {
      const list = node("ol", "calling-points");
      points.forEach((point) => {
        const item = node("li");
        item.append(node("span", "", point.station), node("time", "", point.actualTime || point.expectedTime || point.scheduledTime || ""));
        list.append(item);
      });
      content.append(list);
    } else {
      content.append(node("p", "service-details__empty", "Calling points are not available for this service."));
    }
    detail.lastElementChild.replaceWith(content);
  }

  function setLoading() {
    elements.board.dataset.state = "loading";
    elements.list.setAttribute("aria-busy", "true");
    const fragments = [];
    for (let i = 0; i < 6; i += 1) {
      const row = node("div", "service-row skeleton");
      row.append(node("span"), node("span"), node("span"), node("span"));
      fragments.push(row);
    }
    elements.list.replaceChildren(...fragments);
  }

  function boardRequestUrl() {
    const query = new URLSearchParams({ type: state.mode, rows: "20" });
    if (state.journey) query.set(state.mode === "arrivals" ? "from" : "to", state.journey.crs);
    if (state.timeOffset) query.set("timeOffset", String(state.timeOffset));
    return `${API_BASE}/board/${encodeURIComponent(state.station.crs)}?${query}`;
  }

  async function loadBoard({ showLoading = true } = {}) {
    state.boardController?.abort();
    state.boardController = new AbortController();
    if (showLoading) setLoading();

    updateBoardHeading();
    elements.boardStatus.textContent = "Updating";

    try {
      if (!API_BASE) throw new Error("API is not configured");
      const [boardResponse, disruptionData] = await Promise.all([
        fetch(boardRequestUrl(), { signal: state.boardController.signal }),
        fetch(`${API_BASE}/disruptions/stations/${encodeURIComponent(state.station.crs)}`, { signal: state.boardController.signal })
          .then((response) => response.ok ? response.json() : null)
          .catch(() => null),
      ]);
      if (!boardResponse.ok) throw new Error(`Board request failed: ${boardResponse.status}`);
      const data = await boardResponse.json();

      state.isDemo = false;
      state.station.name = data.stationName || state.station.name;
      if (state.journey && data.filterStation) state.journey.name = data.filterStation;
      state.services = Array.isArray(data.services) ? data.services : [];
      updateBoardHeading();
      updateJourneyUI();
      updateTally();
      renderServices();
      renderDisruptions(data.nrccMessages || [], disruptionData?.disruptions || []);
      renderSavedStations();
      elements.boardStatus.textContent = state.timeOffset ? "Timetable" : "Live";
      updateUrl();
    } catch (error) {
      if (error.name === "AbortError") return;
      state.isDemo = true;
      state.services = demoBoards[state.mode];
      updateTally();
      renderServices();
      renderDisruptions([], []);
      elements.boardStatus.textContent = "Preview";
      elements.boardNote.textContent = "Preview data shown — connect the public API to go live.";
    } finally {
      elements.board.dataset.state = "ready";
      elements.list.setAttribute("aria-busy", "false");
      elements.boardTime.textContent = shiftedClock();
    }
  }

  function updateBoardHeading() {
    elements.boardTitle.textContent = state.station.name;
    elements.stationCode.textContent = state.station.crs;
    elements.boardKicker.textContent = state.mode === "arrivals" ? "Arriving at" : "Departing from";
    elements.journeyLabel.textContent = state.mode === "arrivals" ? "Coming from" : "Going to";
    elements.journeyDirection.textContent = state.mode === "arrivals" ? "FROM" : "TO";
    elements.journeySearch.placeholder = state.mode === "arrivals" ? "Filter by origin" : "Filter by destination";
    elements.timeOffset.textContent = state.timeOffset ? `${state.timeOffset > 0 ? "+" : "−"}${Math.abs(state.timeOffset)} min` : "Now";
  }

  function renderDisruptions(messages, disruptions) {
    const entries = [
      ...messages.map((message) => ({ title: "National Rail update", detail: stripMarkup(message) })),
      ...disruptions.map((item) => ({ title: item.title || "Service update", detail: item.description || item.customerAdvice || "" })),
    ].filter((entry) => entry.detail);

    if (!entries.length) {
      elements.disruptionBanner.hidden = true;
      elements.disruptionDetails.hidden = true;
      elements.disruptionToggle.setAttribute("aria-expanded", "false");
      return;
    }

    elements.disruptionTitle.textContent = entries.length === 1 ? "1 service update" : `${entries.length} service updates`;
    elements.disruptionSummary.textContent = entries[0].title;
    elements.disruptionDetails.replaceChildren(...entries.map((entry) => {
      const paragraph = node("p");
      paragraph.append(node("strong", "", `${entry.title}: `), text(entry.detail));
      return paragraph;
    }));
    elements.disruptionBanner.hidden = false;
  }

  function stripMarkup(value) {
    return String(value)
      .replace(/<br\s*\/?>/gi, " ")
      .replace(/<[^>]*>/g, "")
      .replace(/&amp;/g, "&")
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .replace(/&nbsp;/g, " ")
      .replace(/\s+/g, " ")
      .trim();
  }

  function updateUrl() {
    const url = new URL(window.location.href);
    url.searchParams.set("station", state.station.crs);
    url.searchParams.set("mode", state.mode);
    state.journey ? url.searchParams.set("callingAt", state.journey.crs) : url.searchParams.delete("callingAt");
    state.filter === "all" ? url.searchParams.delete("filter") : url.searchParams.set("filter", state.filter);
    state.timeOffset ? url.searchParams.set("offset", String(state.timeOffset)) : url.searchParams.delete("offset");
    url.searchParams.delete("stationName");
    window.history.replaceState({}, "", url);
  }

  async function searchStations(query, kind) {
    const trimmed = query.trim();
    const isJourney = kind === "journey";
    const resultElement = isJourney ? elements.journeyResults : elements.stationResults;
    const controllerKey = isJourney ? "journeySearchController" : "stationSearchController";
    state[controllerKey]?.abort();
    if (trimmed.length < 2) {
      resultElement.hidden = true;
      resultElement.replaceChildren();
      return;
    }

    state[controllerKey] = new AbortController();
    try {
      const response = await fetch(`${API_BASE}/stations/search?q=${encodeURIComponent(trimmed)}&limit=6`, { signal: state[controllerKey].signal });
      if (!response.ok) throw new Error("Station search failed");
      const data = await response.json();
      renderStationResults(Array.isArray(data.results) ? data.results : [], kind);
    } catch (error) {
      if (error.name !== "AbortError") resultElement.hidden = true;
    }
  }

  function renderStationResults(stations, kind) {
    const resultElement = kind === "journey" ? elements.journeyResults : elements.stationResults;
    const filtered = kind === "journey" ? stations.filter((station) => station.crs !== state.station.crs) : stations;
    resultElement.replaceChildren();
    filtered.forEach((station) => {
      const option = node("button", "station-result");
      option.type = "button";
      option.setAttribute("role", "option");
      option.append(node("span", "", station.crs), node("span", "", station.name));
      option.addEventListener("click", () => kind === "journey" ? selectJourney(station) : selectStation(station));
      resultElement.append(option);
    });
    resultElement.hidden = filtered.length === 0;
  }

  function selectStation(station) {
    state.station = { crs: station.crs, name: station.name };
    if (state.journey?.crs === station.crs) state.journey = null;
    elements.stationSearch.value = "";
    elements.stationSearch.blur();
    elements.stationResults.hidden = true;
    updateJourneyUI();
    loadBoard();
  }

  function selectJourney(station) {
    state.journey = { crs: station.crs, name: station.name };
    elements.journeyResults.hidden = true;
    elements.journeySearch.blur();
    updateJourneyUI();
    loadBoard();
  }

  function clearJourney() {
    state.journey = null;
    updateJourneyUI();
    loadBoard();
  }

  function updateJourneyUI() {
    const active = Boolean(state.journey);
    elements.journeyPicker.classList.toggle("is-filtered", active);
    elements.journeySearch.value = active ? state.journey.name : "";
    elements.clearJourney.hidden = !active;
  }

  function setMode(mode) {
    if (state.mode === mode) return;
    state.mode = mode;
    elements.modeButtons.forEach((button) => {
      const active = button.dataset.mode === mode;
      button.classList.toggle("is-active", active);
      button.setAttribute("aria-pressed", String(active));
    });
    updateBoardHeading();
    updateJourneyUI();
    loadBoard();
  }

  function setFilter(filter) {
    state.filter = filter;
    elements.filterButtons.forEach((button) => {
      const active = button.dataset.filter === filter;
      button.classList.toggle("is-active", active);
      button.setAttribute("aria-pressed", String(active));
    });
    renderServices();
    updateUrl();
  }

  function changeTime(amount) {
    const next = clamp(state.timeOffset + amount, -120, 120);
    if (next === state.timeOffset) return;
    state.timeOffset = next;
    updateBoardHeading();
    loadBoard();
  }

  function saveCurrentStation() {
    const index = state.savedStations.findIndex((station) => station.crs === state.station.crs);
    if (index >= 0) state.savedStations.splice(index, 1);
    else state.savedStations.unshift({ crs: state.station.crs, name: state.station.name });
    state.savedStations = state.savedStations.slice(0, 8);
    localStorage.setItem(SAVED_STATIONS_KEY, JSON.stringify(state.savedStations));
    renderSavedStations();
  }

  function renderSavedStations() {
    const isSaved = state.savedStations.some((station) => station.crs === state.station.crs);
    elements.saveStation.textContent = isSaved ? "★" : "☆";
    elements.saveStation.setAttribute("aria-pressed", String(isSaved));
    elements.saveStation.setAttribute("aria-label", isSaved ? "Remove this saved station" : "Save this station");

    elements.savedStations.replaceChildren();
    state.savedStations.forEach((station) => {
      const button = node("button", `saved-station-chip${station.crs === state.station.crs ? " is-current" : ""}`, `${station.crs} · ${station.name}`);
      button.type = "button";
      button.addEventListener("click", () => selectStation(station));
      elements.savedStations.append(button);
    });
    elements.savedStations.hidden = state.savedStations.length === 0;
  }

  function bindSearch(input, resultElement, kind) {
    const timerKey = kind === "journey" ? "journeySearchTimer" : "stationSearchTimer";
    input.addEventListener("input", (event) => {
      if (kind === "journey" && state.journey) {
        state.journey = null;
        updateJourneyUI();
      }
      window.clearTimeout(state[timerKey]);
      state[timerKey] = window.setTimeout(() => searchStations(event.target.value, kind), 220);
    });
    input.addEventListener("keydown", (event) => {
      if (event.key === "Escape") {
        resultElement.hidden = true;
        input.blur();
      }
    });
  }

  function initialise() {
    elements.appLinks.forEach((link) => {
      link.href = config.APP_URL || "#in-your-pocket";
      if ((config.APP_URL || "").startsWith("http")) link.target = "_blank";
    });

    elements.modeButtons.forEach((button) => {
      const active = button.dataset.mode === state.mode;
      button.classList.toggle("is-active", active);
      button.setAttribute("aria-pressed", String(active));
      button.addEventListener("click", () => setMode(button.dataset.mode));
    });
    elements.filterButtons.forEach((button) => {
      const active = button.dataset.filter === state.filter;
      button.classList.toggle("is-active", active);
      button.setAttribute("aria-pressed", String(active));
      button.addEventListener("click", () => setFilter(button.dataset.filter));
    });

    bindSearch(elements.stationSearch, elements.stationResults, "station");
    bindSearch(elements.journeySearch, elements.journeyResults, "journey");
    elements.clearJourney.addEventListener("click", clearJourney);
    elements.saveStation.addEventListener("click", saveCurrentStation);
    elements.timeStepButtons.forEach((button) => button.addEventListener("click", () => changeTime(Number(button.dataset.timeStep))));
    elements.timeOffset.addEventListener("click", () => {
      if (state.timeOffset) {
        state.timeOffset = 0;
        updateBoardHeading();
        loadBoard();
      }
    });
    elements.disruptionToggle.addEventListener("click", () => {
      const expanded = elements.disruptionToggle.getAttribute("aria-expanded") === "true";
      elements.disruptionToggle.setAttribute("aria-expanded", String(!expanded));
      elements.disruptionDetails.hidden = expanded;
    });
    document.addEventListener("click", (event) => {
      if (!event.target.closest(".station-picker")) elements.stationResults.hidden = true;
      if (!event.target.closest(".journey-picker")) elements.journeyResults.hidden = true;
    });
    elements.refresh.addEventListener("click", () => loadBoard({ showLoading: false }));

    updateBoardHeading();
    updateJourneyUI();
    renderSavedStations();
    loadBoard();
    state.refreshTimer = window.setInterval(() => loadBoard({ showLoading: false }), REFRESH_INTERVAL);
  }

  initialise();
})();
