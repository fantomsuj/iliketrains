# OpenStreetMap-derived data (ODbL)

`routes.json` contains route geometry produced by snapping published railroad timetable shapes onto
OpenStreetMap track (`npm run build:routes`). It is a derivative database of OpenStreetMap:

> © OpenStreetMap contributors. Available under the Open Database License (ODbL) 1.0,
> https://opendatacommons.org/licenses/odbl/1-0/ and https://www.openstreetmap.org/copyright

Keep this directory (and `tiles/dist/`) separate from other data so ODbL obligations stay contained:
if you distribute it, distribute it under the ODbL, with attribution. The timetable data it was
matched against stays under each railroad's own GTFS terms and is not stored here beyond station ids.
