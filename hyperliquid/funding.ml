open! Core

type t =
  { time : int
  ; coin : string
  ; usdc : Chain_books.Exact.t
  }
[@@deriving sexp_of]

let of_json json =
  let delta = Wire.field json "delta" in
  { time = Wire.int json "time"; coin = Wire.string delta "coin"; usdc = Wire.decimal delta "usdc" }
;;

let of_yojson = Wire.decode ~what:"funding" of_json

let list_of_yojson = function
  | `List items -> List.map items ~f:of_yojson |> Or_error.combine_errors
  | json -> Wire.decode ~what:"funding history" (fun _ -> failwith "not a JSON array") json
;;

let of_user_event (f : Hl_protocol.User_event.Funding.t) =
  { time = f.time
  ; coin = Hl_protocol.Coin.to_string f.coin
  ; usdc =
      Wire.q_of_fixed
        ~units:(Hl_protocol.Usd.to_units f.usdc)
        ~units_per_one:Hl_protocol.Usd.units_per_one
  }
;;
