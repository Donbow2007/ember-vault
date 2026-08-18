import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["map", "query", "results", "coordinates", "locateButton"]
  static values = { url: String, searchUrl: String, title: String, initialLatitude: Number, initialLongitude: Number, initialName: String }

  async connect() {
    const connectionId = Symbol("atlas-connection")
    this.connectionId = connectionId
    const librariesReady = await this.waitForLibraries()
    if (this.connectionId !== connectionId) return
    if (!librariesReady) return this.showError("Offline map renderer did not load.")

    this.protocol = new window.pmtiles.Protocol()
    window.maplibregl.addProtocol("pmtiles", this.protocol.tile)
    this.archive = new window.pmtiles.PMTiles(new URL(this.urlValue, window.location.origin).href)
    this.protocol.add(this.archive)

    try {
      const header = await this.archive.getHeader()
      this.map = new window.maplibregl.Map({
        container: this.mapTarget,
        style: this.styleFor(new URL(this.urlValue, window.location.origin).href),
        bounds: [[header.minLon, header.minLat], [header.maxLon, header.maxLat]],
        fitBoundsOptions: { padding: 35 },
        attributionControl: false
      })
      this.map.addControl(new window.maplibregl.NavigationControl(), "top-right")
      this.map.addControl(new window.maplibregl.ScaleControl({ unit: "imperial" }), "bottom-right")
      if (this.hasInitialLatitudeValue && this.hasInitialLongitudeValue) {
        this.map.once("load", () => this.locateFeature({ name: this.initialNameValue, latitude: this.initialLatitudeValue, longitude: this.initialLongitudeValue }))
      }
      this.map.on("mousemove", event => { this.coordinatesTarget.textContent = `${event.lngLat.lat.toFixed(5)} / ${event.lngLat.lng.toFixed(5)}` })
      this.map.on("click", event => this.inspect(event))
    } catch (error) {
      this.showError(error.message)
    }
  }

  disconnect() {
    this.connectionId = null
    if (this.map) this.map.remove()
  }

  async waitForLibraries() {
    for (let attempt = 0; attempt < 50; attempt++) {
      if (window.maplibregl && window.pmtiles) return true
      await new Promise(resolve => window.setTimeout(resolve, 100))
    }
    return false
  }

  async search(event) {
    event.preventDefault()
    const query = this.queryTarget.value.trim().toLowerCase()
    if (!query || !this.map) return

    const response = await fetch(`${this.searchUrlValue}?q=${encodeURIComponent(query)}`, { headers: { Accept: "application/json" } })
    const features = await response.json()
    if (!features.length) return this.showError("No indexed geographic name matched that search.")

    this.resultsTarget.innerHTML = features.map(feature => `<button type="button" data-action="click->atlas#locate" data-longitude="${feature.longitude}" data-latitude="${feature.latitude}" data-name="${this.escape(feature.name)}"><b>${this.escape(feature.name)}</b><span>${this.escape(feature.category)} // ${this.escape(feature.kind)}</span></button>`).join("")
    this.locateFeature(features[0])
  }

  locate(event) {
    this.locateFeature({ name: event.currentTarget.dataset.name, longitude: Number(event.currentTarget.dataset.longitude), latitude: Number(event.currentTarget.dataset.latitude) })
  }

  locateFeature(feature) {
    const center = [feature.longitude, feature.latitude]
    this.map.flyTo({ center, zoom: 13 })
    if (this.marker) this.marker.remove()
    this.marker = new window.maplibregl.Marker({ color: "#d57838" }).setLngLat(center).addTo(this.map)
  }

  locateDevice() {
    if (!this.map) return
    if (!navigator.geolocation) return this.showError("This device does not provide GPS location.")

    this.locateButtonTarget.disabled = true
    this.locateButtonTarget.textContent = "◎ ACQUIRING GPS..."
    navigator.geolocation.getCurrentPosition(
      position => {
        const center = [position.coords.longitude, position.coords.latitude]
        this.map.flyTo({ center, zoom: 15 })
        if (this.deviceMarker) this.deviceMarker.remove()
        this.deviceMarker = new window.maplibregl.Marker({ color: "#f1eee4" }).setLngLat(center).addTo(this.map)
        this.coordinatesTarget.textContent = `${position.coords.latitude.toFixed(5)} / ${position.coords.longitude.toFixed(5)}`
        this.resultsTarget.innerHTML = `<p><b>DEVICE POSITION</b><br>ACCURATE WITHIN ${Math.round(position.coords.accuracy)} METERS</p>`
        this.resetLocateButton()
      },
      error => {
        const messages = { 1: "Location permission was denied.", 2: "GPS location is unavailable.", 3: "GPS location timed out." }
        this.showError(messages[error.code] || "Unable to determine this device's location.")
        this.resetLocateButton()
      },
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 30000 }
    )
  }

  resetLocateButton() {
    this.locateButtonTarget.disabled = false
    this.locateButtonTarget.textContent = "◎ LOCATE ME"
  }

  inspect(event) {
    const feature = this.map.queryRenderedFeatures(event.point).find(item => item.properties && (item.properties.name || item.properties.ref))
    if (!feature) return
    const name = feature.properties.name || feature.properties.ref
    new window.maplibregl.Popup().setLngLat(event.lngLat).setHTML(`<b>${this.escape(name)}</b><p>${this.escape(feature.sourceLayer || feature.properties.kind || "MAP FEATURE")}</p>`).addTo(this.map)
  }

  featureCenter(feature) {
    if (feature.geometry.type === "Point") return feature.geometry.coordinates
    const coordinates = feature.geometry.type === "LineString" ? feature.geometry.coordinates : feature.geometry.coordinates.flat(2)
    const middle = coordinates[Math.floor(coordinates.length / 2)]
    return Array.isArray(middle) ? middle : [this.map.getCenter().lng, this.map.getCenter().lat]
  }

  showError(message) {
    this.resultsTarget.innerHTML = `<p class="atlas-error">${this.escape(message)}</p>`
  }

  escape(value) {
    const node = document.createElement("span")
    node.textContent = String(value)
    return node.innerHTML
  }

  styleFor(url) {
    const light = document.body.dataset.theme === "light"
    const colors = light ? {
      background: "#ece9df", forest: "#cbd3c5", grass: "#d8dbc9", land: "#ddd9cf", water: "#b9d4da",
      landuse: "#d0cec2", boundary: "#777970", roadCasing: "#f7f4ec", highway: "#b65e2e", majorRoad: "#9a7959",
      road: "#77776f", building: "#aaa79d", waterText: "#376c78", roadText: "#454640", placeText: "#171918", halo: "#f2f0e9"
    } : {
      background: "#111514", forest: "#26352d", grass: "#30382d", land: "#242826", water: "#263d43",
      landuse: "#34362f", boundary: "#77766e", roadCasing: "#171817", highway: "#d57838", majorRoad: "#b99b77",
      road: "#77766e", building: "#66655e", waterText: "#83aeb8", roadText: "#c8c5b9", placeText: "#eeede4", halo: "#111514"
    }
    return { version: 8, glyphs: `${window.location.origin}/map_fonts/{fontstack}/{range}.pbf`, sources: { atlas: { type: "vector", url: `pmtiles://${url}`, attribution: "© OpenStreetMap contributors" } }, layers: [
      { id: "background", type: "background", paint: { "background-color": colors.background } },
      { id: "landcover", type: "fill", source: "atlas", "source-layer": "landcover", paint: { "fill-color": ["match", ["get", "kind"], "forest", colors.forest, "grass", colors.grass, colors.land], "fill-opacity": 0.8 } },
      { id: "water", type: "fill", source: "atlas", "source-layer": "water", paint: { "fill-color": colors.water } },
      { id: "landuse", type: "fill", source: "atlas", "source-layer": "landuse", paint: { "fill-color": colors.landuse, "fill-opacity": 0.45 } },
      { id: "boundaries", type: "line", source: "atlas", "source-layer": "boundaries", paint: { "line-color": colors.boundary, "line-width": 1, "line-dasharray": [3, 3] } },
      { id: "roads-casing", type: "line", source: "atlas", "source-layer": "roads", paint: { "line-color": colors.roadCasing, "line-width": ["interpolate", ["linear"], ["zoom"], 5, 1, 15, 8] } },
      { id: "roads", type: "line", source: "atlas", "source-layer": "roads", paint: { "line-color": ["match", ["get", "kind"], "highway", colors.highway, "major_road", colors.majorRoad, colors.road], "line-width": ["interpolate", ["linear"], ["zoom"], 5, 0.4, 15, 4] } },
      { id: "buildings", type: "fill", source: "atlas", "source-layer": "buildings", minzoom: 12, paint: { "fill-color": colors.building, "fill-opacity": 0.65 } },
      { id: "water-labels", type: "symbol", source: "atlas", "source-layer": "water", minzoom: 8, layout: { "text-field": ["coalesce", ["get", "name:en"], ["get", "name"]], "text-font": ["Noto Sans Regular"], "text-size": 11, "text-max-width": 8 }, paint: { "text-color": colors.waterText, "text-halo-color": colors.halo, "text-halo-width": 1.5 } },
      { id: "road-labels", type: "symbol", source: "atlas", "source-layer": "roads", minzoom: 10, filter: ["any", ["has", "name"], ["has", "ref"]], layout: { "symbol-placement": "line", "text-field": ["coalesce", ["get", "name"], ["get", "ref"]], "text-font": ["Noto Sans Regular"], "text-size": 10, "text-keep-upright": true }, paint: { "text-color": colors.roadText, "text-halo-color": colors.halo, "text-halo-width": 1.4 } },
      { id: "place-labels", type: "symbol", source: "atlas", "source-layer": "places", layout: { "text-field": ["coalesce", ["get", "name:en"], ["get", "name"]], "text-font": ["Noto Sans Regular"], "text-size": ["interpolate", ["linear"], ["zoom"], 5, 11, 14, 16], "text-max-width": 9, "text-variable-anchor": ["top", "bottom", "left", "right"], "text-radial-offset": 0.5 }, paint: { "text-color": colors.placeText, "text-halo-color": colors.halo, "text-halo-width": 2 } }
    ] }
  }
}
