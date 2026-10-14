(** Double-entry books for an organisation's on-chain treasury.

    Venue records (fills, funding payments, deposits and transfers, staking rewards)
    become normalised {!Activity} and {!Fill} values through a {!Normalizer}; activities
    become balanced [Ledger] entries over a {!Chart} of accounts ({!Booking}); fills
    feed positions and cost basis ({!Positions}). Balance reports from the chain give
    each location its opening balance once ({!Opening}) and are then reconciled against
    the books ({!Reconciliation}); holdings are valued through a {!Price_source}
    ({!Valuation}). {!Books} ties these together as one immutable value, and
    {!Chain_write} is the record that makes writes to the chain safe to retry.

    Pure: no storage, no network, no clock. The sub-library [chain-books.hyperliquid]
    is the adapter for Hyperliquid.

    {[
      let books = Books.create (Chart.create (Binding_id.of_string "treasury")) in
      let books, report = Books.ingest books history ~at |> Or_error.ok_exn in
      let books, openings =
        Books.open_balances books observed ~history_start ~at |> Or_error.ok_exn
      in
      Reconciliation.breaks (Books.reconcile books observed)
    ]}

    The complete program is [examples/quickstart.ml] in the source tree. *)

(** {1 Identifiers} *)

module Short_id = Short_id
module Binding_id = Binding_id
module Address = Address
module Event_id = Event_id

(** {1 Where assets are} *)

module Venue = Venue
module Location = Location
module Assets = Assets
module Category = Category

(** {1 What happened} *)

module Exact = Exact
module Instrument = Instrument
module Activity = Activity
module Fill = Fill
module Observed = Observed
module Normalized = Normalized
module Normalizer = Normalizer

(** {1 Books} *)

module Chart = Chart
module Booking = Booking
module Opening = Opening
module Positions = Positions
module Reconciliation = Reconciliation
module Price_source = Price_source
module Valuation = Valuation
module Books = Books

(** {1 Writes} *)

module Chain_write = Chain_write
