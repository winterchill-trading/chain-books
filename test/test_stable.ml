open! Core
open Chain_books
open Helpers

(* A changed digest means bytes written before no longer decode: add a Stable.V2 next to
   V1 instead of editing V1, and keep V1 readable. *)
let%expect_test "stable bin_prot digests" =
  List.iter
    [ "Binding_id", [%bin_digest: Binding_id.Stable.V1.t]
    ; "Address", [%bin_digest: Address.Stable.V1.t]
    ; "Event_id", [%bin_digest: Event_id.Stable.V1.t]
    ; "Venue", [%bin_digest: Venue.Stable.V1.t]
    ; "Location", [%bin_digest: Location.Stable.V1.t]
    ; "Category", [%bin_digest: Category.Stable.V1.t]
    ; "Exact", [%bin_digest: Exact.Stable.V1.t]
    ; "Instrument", [%bin_digest: Instrument.Stable.V1.t]
    ; "Activity.Kind", [%bin_digest: Activity.Kind.Stable.V1.t]
    ; "Activity.Counter", [%bin_digest: Activity.Counter.Stable.V1.t]
    ; "Activity", [%bin_digest: Activity.Stable.V1.t]
    ; "Fill.Side", [%bin_digest: Fill.Side.Stable.V1.t]
    ; "Fill", [%bin_digest: Fill.Stable.V1.t]
    ; "Observed.Balance", [%bin_digest: Observed.Balance.Stable.V1.t]
    ; "Observed.Position", [%bin_digest: Observed.Position.Stable.V1.t]
    ; "Observed", [%bin_digest: Observed.Stable.V1.t]
    ; "Normalized", [%bin_digest: Normalized.Stable.V1.t]
    ; "Positions.Method", [%bin_digest: Positions.Method.Stable.V1.t]
    ; "Positions.Lot", [%bin_digest: Positions.Lot.Stable.V1.t]
    ; "Positions.Position", [%bin_digest: Positions.Position.Stable.V1.t]
    ; "Positions", [%bin_digest: Positions.Stable.V1.t]
    ; "Reconciliation.Status", [%bin_digest: Reconciliation.Status.Stable.V1.t]
    ; "Reconciliation.Row", [%bin_digest: Reconciliation.Row.Stable.V1.t]
    ; "Chain_write", [%bin_digest: Chain_write.Stable.V1.t]
    ]
    ~f:(fun (name, digest) -> printf "%-22s %s\n" name digest);
  [%expect
    {|
    Binding_id             d9a8da25d5656b016fb4dbdc2e4197fb
    Address                d9a8da25d5656b016fb4dbdc2e4197fb
    Event_id               d9a8da25d5656b016fb4dbdc2e4197fb
    Venue                  6f82c3ac53cc97e0baec03a55b5a14ca
    Location               a97a10cb85ca908785dae74f80acf934
    Category               3cb2be02bbc24c3e10af213291e417ec
    Exact                  d9a8da25d5656b016fb4dbdc2e4197fb
    Instrument             51d319a9dd2f7f1a6b8b321a37d09d48
    Activity.Kind          9f7c6774f8576744773dbed1b95d2ce2
    Activity.Counter       b75a8230786908507f451bcbb2f788d6
    Activity               6f386a714ca0e1274d248249259e0372
    Fill.Side              201e24d8d0d9507c88320f4f72b73cda
    Fill                   2b29881be8800cb58a15d253a87bee4a
    Observed.Balance       eda1924eec71913a38c99334ab384efe
    Observed.Position      d4d9b55f52d2414b3455605aaf0b31af
    Observed               53729a3ad2e2f970226c2d7e512d8253
    Normalized             6d8afc9f2ade86ca572faf08f2f3998e
    Positions.Method       cbb578c00e2da3191e4d455c064e04b5
    Positions.Lot          1990745e8b70776f0169f7a777b53fb4
    Positions.Position     77893fbf63c8d8c6240dfdfafe194930
    Positions              7eb4a9b4a3292648fb04216d27a73245
    Reconciliation.Status  1f5d4cbddc66c43945e0157f34d2e0b4
    Reconciliation.Row     3203c308cb1fe29f3c398e8ab1eb37fa
    Chain_write            dbf2d37fcec3ba6ba86cc9ba7dfc64d5
    |}]
;;

let round_trip (type a) (module M : Binable.S with type t = a) ~equal (v : a) =
  let back = Binable.of_string (module M) (Binable.to_string (module M) v) in
  assert (equal back v)
;;

let%test_unit "activities, fills and positions round trip through bin_prot and sexp" =
  let a =
    activity "x1" Internal perp (usd "-1.5") ~counter:(Location spot) ~reference:"0xab"
  in
  round_trip (module Activity.Stable.V1) ~equal:Activity.equal a;
  [%test_result: Activity.t] (Activity.t_of_sexp (Activity.sexp_of_t a)) ~expect:a;
  let f = fill "f1" Sell "0.25" "1/3" ~reported_pnl:(usd "1") in
  round_trip (module Fill.Stable.V1) ~equal:Fill.equal f;
  let ps, _ = Positions.apply (Positions.empty Average_cost) f in
  let back =
    Binable.of_string
      (module Positions.Stable.V1)
      (Binable.to_string (module Positions.Stable.V1) ps)
  in
  [%test_result: Positions.Position.t list]
    (Positions.positions back)
    ~expect:(Positions.positions ps);
  (* The fill is remembered, so applying it again after a restore is a duplicate. *)
  [%test_result: Positions.Applied.t] (snd (Positions.apply back f)) ~expect:Duplicate
;;

let%expect_test "decoding validates again" =
  let a = activity "x1" Internal perp (usd "-1") ~counter:(Location spot) in
  let sexp = Activity.sexp_of_t a in
  let bad =
    Sexp.of_string
      (String.substr_replace_all
         (Sexp.to_string sexp)
         ~pattern:"(Location((address 0xa1)(venue Spot)))"
         ~with_:"(Location((address 0xa1)(venue Perp)))")
  in
  print_s
    [%sexp
      (Or_error.try_with (fun () -> Activity.t_of_sexp bad) |> Or_error.map ~f:ignore
       : unit Or_error.t)];
  print_s
    [%sexp
      (Or_error.try_with (fun () -> Event_id.t_of_sexp (Sexp.Atom "has space"))
       |> Or_error.map ~f:ignore
       : unit Or_error.t)];
  [%expect
    {|
    (Error ("activity moves an asset from a location to itself" (event_id x1)))
    (Error
     ((Chain_books.Event_id (id "has space")) ("character not allowed" (c " "))))
    |}]
;;
