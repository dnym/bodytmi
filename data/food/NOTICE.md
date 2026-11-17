# Food composition data

`slv.json.gz` contains data from the Swedish Food Agency's food composition
database (Livsmedelsverket, *Livsmedelsdatabasen*), retrieved from
<https://dataportal.livsmedelsverket.se/livsmedel/api/v1> and licensed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). It is not covered
by the repository's BSD-2-Clause-Patent licence.

Changes: values are copied as published, per 100 g edible part, into the
`bodytmi-food-dataset/1` format; the kJ energy and waste columns are omitted.
The release (newest food version date) and retrieval date are in the file
header. Rebuild with `dart run tool/fetch_slv.dart CACHE` and
`dart run tool/package_slv.dart CACHE data/food/slv.json.gz YYYY-MM-DD`.
