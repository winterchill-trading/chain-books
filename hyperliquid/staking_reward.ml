open! Core

type t =
  { time : int
  ; source : string
  ; total_amount : Chain_books.Exact.t
  }
[@@deriving sexp_of]

let of_json json =
  { time = Wire.int json "time"
  ; source = Wire.string json "source"
  ; total_amount = Wire.decimal json "totalAmount"
  }
;;

let of_yojson = Wire.decode ~what:"staking reward" of_json

let list_of_yojson = function
  | `List items -> List.map items ~f:of_yojson |> Or_error.combine_errors
  | json ->
    Wire.decode ~what:"staking rewards" (fun _ -> failwith "not a JSON array") json
;;
