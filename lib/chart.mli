(** The chart of accounts for one binding.

    {v
    chain:<binding>:custody:<address>:<venue>   Asset, one per location, every asset
    chain:<binding>:cp:<category>               one per counterparty category
    v}

    Ledger accounts hold several currencies, so one account per location carries every
    asset held there and a balance is looked up by location and asset. Custody accounts
    may go negative: a sync can read one side of a transfer between two venues before the
    other, and the books must accept that order. Spending checks (a payout must not
    overdraw a location) belong to the caller. *)

open! Core

(** The chart of one binding. *)
type t [@@deriving sexp_of]

(** The chart of [binding]. *)
val create : Binding_id.t -> t

(** The binding every account id is prefixed with. *)
val binding : t -> Binding_id.t

(** The custody account of a location. *)
val custody : t -> Location.t -> Ledger.Account_id.t

(** The account of a counterparty category. *)
val counterparty : t -> Category.t -> Ledger.Account_id.t

(** The other side of an activity: the counter location's custody account, or the
    counterparty account of [category] when given (a classification override) or of the
    activity's own category. *)
val counter_account : t -> ?category:Category.t -> Activity.t -> Ledger.Account_id.t

(** The location a custody account id of this binding names; [None] for any other id. *)
val location_of_account : t -> Ledger.Account_id.t -> Location.t option

(** The account record to open for a location: [Asset], [allow_negative], tagged with the
    binding, address and venue. *)
val custody_account : t -> Location.t -> Ledger.Account.t

(** The account record to open for a category: its {!Category.account_kind} and
    {!Category.purpose}, [allow_negative], tagged with the binding and category. *)
val counterparty_account : t -> Category.t -> Ledger.Account.t

(** The accounts [activities] post to (with [classify] applied like {!Booking.entry} does)
    that [balances] has not opened yet, without duplicates, sorted by id. *)
val missing_accounts
  :  t
  -> ?classify:(Activity.t -> Category.t option)
  -> Ledger.Balances.t
  -> Activity.t list
  -> Ledger.Account.t list
