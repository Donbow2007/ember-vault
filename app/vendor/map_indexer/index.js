const fs = require("fs")
const { PMTiles } = require("pmtiles")
const { VectorTile } = require("@mapbox/vector-tile")
const Protobuf = require("pbf")

class NodeSource {
  constructor(path) { this.path = path; this.file = fs.openSync(path, "r") }
  getKey() { return this.path }
  async getBytes(offset, length) {
    const buffer = Buffer.alloc(length)
    const bytesRead = fs.readSync(this.file, buffer, 0, length, offset)
    return { data: buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + bytesRead) }
  }
}

const longitudeToX = (longitude, zoom) => Math.floor((longitude + 180) / 360 * 2 ** zoom)
const latitudeToY = (latitude, zoom) => Math.floor((1 - Math.asinh(Math.tan(latitude * Math.PI / 180)) / Math.PI) / 2 * 2 ** zoom)

function centerOf(geometry) {
  const points = []
  const collect = coordinates => typeof coordinates[0] === "number" ? points.push(coordinates) : coordinates.forEach(collect)
  collect(geometry.coordinates)
  if (!points.length) return null
  const bounds = points.reduce((memo, point) => [Math.min(memo[0], point[0]), Math.min(memo[1], point[1]), Math.max(memo[2], point[0]), Math.max(memo[3], point[1])], [Infinity, Infinity, -Infinity, -Infinity])
  return [(bounds[0] + bounds[2]) / 2, (bounds[1] + bounds[3]) / 2]
}

async function main() {
  const archive = new PMTiles(new NodeSource(process.argv[2]))
  const header = await archive.getHeader()
  // Local and residential road names are commonly omitted from lower zoom tiles.
  // Zoom 14 captures residential roads while keeping a state-sized offline pass practical.
  const zoom = Math.min(14, header.maxZoom)
  const minX = longitudeToX(header.minLon, zoom)
  const maxX = longitudeToX(header.maxLon, zoom)
  const minY = latitudeToY(header.maxLat, zoom)
  const maxY = latitudeToY(header.minLat, zoom)
  const wantedLayers = new Set(["places", "roads", "water", "pois"])
  const seen = new Set()

  for (let x = minX; x <= maxX; x++) {
    for (let y = minY; y <= maxY; y++) {
      const tileData = await archive.getZxy(zoom, x, y)
      if (!tileData) continue
      const tile = new VectorTile(new Protobuf(Buffer.from(tileData.data)))
      for (const [layerName, layer] of Object.entries(tile.layers)) {
        if (!wantedLayers.has(layerName)) continue
        for (let index = 0; index < layer.length; index++) {
          const feature = layer.feature(index)
          const name = feature.properties.name || feature.properties["name:en"] || feature.properties.ref
          if (!name || String(name).length > 180) continue
          const key = `${layerName}|${String(name).toLowerCase()}`
          if (seen.has(key)) continue
          const geojson = feature.toGeoJSON(x, y, zoom)
          const center = centerOf(geojson.geometry)
          if (!center) continue
          seen.add(key)
          process.stdout.write(`${JSON.stringify({ name: String(name), category: layerName, kind: feature.properties.kind || feature.properties.kind_detail || "feature", longitude: center[0], latitude: center[1] })}\n`)
        }
      }
    }
  }
}

main().catch(error => { console.error(error); process.exit(1) })
