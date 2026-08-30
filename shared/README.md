# Shared

Versioned product configuration. Edit these files directly. `scripts/validate_shared.py` must stay green.

```text
catalog/     Canonical items by category
rules/       Base, trip types, activities, weather, quantities, substitutions, reasons
schemas/     JSON schemas
contracts/   Intelligence API OpenAPI (typed)
fixtures/    Test-only destinations, weather, trip evals
```

`fixtures/test-destinations.json` is **not** a production destination database. Production uses MapKit.

Do not put Swift or TypeScript business logic here.
