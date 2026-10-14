# examples

`quickstart.ml` is the README example as a program. `dune test` runs it and diffs its output
with `quickstart.expected`; CI also runs `dune exec ./examples/quickstart.exe`. Keep the
README excerpt and the expected output in step when either changes.
