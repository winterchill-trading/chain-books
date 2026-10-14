# lib: chain-books library

Library `chain-books` (module `Chain_books`). Layers:

- Values: `Short_id` (`Binding_id`, `Address`, `Event_id`), `Venue`, `Location`, `Assets`,
  `Category`, `Exact`, `Instrument`, `Activity`, `Fill`, `Observed`, `Normalized`,
  `Normalizer` (the adapter module type).
- Books: `Chart` (account ids and records), `Booking` (activity to entry), `Opening`,
  `Positions`, `Reconciliation`, `Price_source`, `Valuation`, and `Books`, which ties them
  together as one immutable value.
- `Chain_write`: the pure state machine for retry-safe writes.

Rules:

- Nothing here persists, fetches or reads a clock; times come in as arguments.
- Every id built here must fit the ledger's 128-character ids. Check the caps in
  `binding_id.ml`, `address.ml`, `event_id.ml` before lengthening an id format.
- A new account kind or category changes reports: update the table in `category.mli` and
  the README.
