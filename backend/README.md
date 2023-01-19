# Backend

## Dependencies

`mix deps.get`

## Run backend

`mix run --no-halt`

## Run in interactive mode

`iex lib/main.exs`

## Run Paxos tests

1. `epmd -daemon` to start the Erlang port mapper
2. `iex paxos_tests/test_script.exs` to run the tests

### Debugging

If the multi-node tests fail with the `"Can not start :erlang::apply..."` warnings, start the Erlang port mapper from the command line as follows: `epmd -daemon`.
