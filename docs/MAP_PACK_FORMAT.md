# Ember Vault Map Pack

Each portable map pack is a directory under `storage/maps`.

Required files:

- `map-pack.json`
- one PMTiles file referenced by the manifest

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

Optional geographic search data can be generated into Ember Vault's SQLite database by the map indexer. A pack can be shared by copying its entire directory to another Ember Vault drive. The Maps screen discovers valid manifests automatically.
