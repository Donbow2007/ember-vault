# Ember Vault Map Pack v1

A map pack is a self-contained directory under the portable `maps/` directory. Packs are deliberately file-copyable: no installer or network service is required to move one between Ember Vault drives.

## Required files

- `map-pack.json`
- one PMTiles archive referenced by the manifest

Example:

```json
{
  "format": "ember-map-pack",
  "version": "1",
  "title": "Arkansas",
  "region": "US-AR",
  "pmtiles": "arkansas.pmtiles"
}
```

`format` must be `ember-map-pack` and `version` must be `1`. The PMTiles path must remain inside the pack directory.

## Discovery

Ember scans `maps/*/map-pack.json` when the Maps screen opens. A valid copied pack is registered automatically. Missing removable media is not interpreted as permission to delete existing map metadata.

## Offline geographic search

The PMTiles archive is the visual source of truth. Ember's local map indexer extracts named places, roads, water, and POIs into the portable SQLite database. Search never requires a geocoding web service. Reindexing can be requested from the Maps interface.

## Sharing

Copy the entire pack directory. The receiving Ember Vault installation discovers the manifest and PMTiles archive automatically. Search data can be rebuilt locally, so database files do not need to travel with the pack.

Future format revisions must use a new version number rather than silently changing v1 semantics.
