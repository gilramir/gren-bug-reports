%% The shortest module that makes dialyzer emit a warning.
%%
%% `f/0` always raises, so `g/0` can never return normally either. Dialyzer
%% reports that as "Function g/0 has no local return", which is one of the
%% warnings it gives with no flags asked for.
-module(m).
-export([g/0]).

f() -> erlang:error(bad).

g() -> f().
