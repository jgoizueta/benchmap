The class `CartoBench` has useful functions for benchmarking imports, maps,
overviews, etc. See `benchmap.rb`for an example of use.

* The user account used for API calls (have to define username and api key)
  must have public maps enabled.
* Tables to be used in maps (create_map, fetch_tile) must be public.
* The user's statement_timeout should be long enough for all operations
  to be performed.
