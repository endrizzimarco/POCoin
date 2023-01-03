# How to use the testing framework

## Run the tests

1. `epmd -daemon` to start the Erlang port mapper
2. `iex test_script.exs` to run the tests

## Change which tests get run 
You can comment/uncomment the tests in `test_script.exs` to run different tests.

## Debugging

If the multi-node tests fail with the `"Can not start :erlang::apply..."` warnings, start the Erlang port mapper from the command line as follows: `epmd -daemon`.
