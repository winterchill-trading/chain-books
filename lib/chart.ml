open! Core

type t = { binding : Binding_id.t } [@@deriving sexp_of]

let create binding = { binding }
let binding t = t.binding
let prefix t = "chain:" ^ Binding_id.to_string t.binding

(* Every part is validated (address, venue, category name, binding), and the lengths are
   capped so that the longest id stays below [Ledger.Account_id.max_parent_length]. *)
let custody t (location : Location.t) =
  Ledger.Account_id.of_string
    (sprintf
       "%s:custody:%s:%s"
       (prefix t)
       (Address.to_string location.address)
       (Venue.to_string location.venue))
;;

let counterparty t category =
  Ledger.Account_id.of_string
    (sprintf "%s:cp:%s" (prefix t) (Category.to_string category))
;;

let counter_account t ?category (activity : Activity.t) =
  match activity.counter, category with
  | Location l, _ -> custody t l
  | Counterparty _, Some c -> counterparty t c
  | Counterparty c, None -> counterparty t c
;;

let location_of_account t id =
  let%bind.Option rest =
    String.chop_prefix (Ledger.Account_id.to_string id) ~prefix:(prefix t ^ ":custody:")
  in
  let%bind.Option address, venue = String.lsplit2 rest ~on:':' in
  let%bind.Option address = Address.of_string_or_error address |> Result.ok in
  let%map.Option venue = Venue.of_string_or_error venue |> Result.ok in
  { Location.address; venue }
;;

let tags t extra = ("binding", Binding_id.to_string t.binding) :: extra

let custody_account t (location : Location.t) =
  Ledger.Account.create
    ~allow_negative:true
    ~tags:
      (tags
         t
         [ "address", Address.to_string location.address
         ; "venue", Venue.to_string location.venue
         ])
    (custody t location)
    Asset
;;

let counterparty_account t category =
  Ledger.Account.create
    ~purpose:(Category.purpose category)
    ~allow_negative:true
    ~tags:(tags t [ "category", Category.to_string category ])
    (counterparty t category)
    (Category.account_kind category)
;;

let missing_accounts t ?(classify = fun _ -> None) balances activities =
  List.concat_map activities ~f:(fun (a : Activity.t) ->
    let counter =
      match a.counter with
      | Location l -> custody_account t l
      | Counterparty c -> counterparty_account t (Option.value (classify a) ~default:c)
    in
    [ custody_account t a.location; counter ])
  |> List.dedup_and_sort ~compare:(fun (a : Ledger.Account.t) b ->
    Ledger.Account_id.compare a.id b.id)
  |> List.filter ~f:(fun (a : Ledger.Account.t) ->
    Option.is_none (Ledger.Balances.find_account balances a.id))
;;
