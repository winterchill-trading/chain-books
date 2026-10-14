open! Core

include Short_id.Make (struct
    let module_name = "Chain_books.Address"
    let max_length = 44
    let allowed_char = Char.is_alphanum
    let sample_chars = "0123456789abcdefx"
  end)
