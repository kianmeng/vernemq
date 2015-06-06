%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License
%% at http://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and
%% limitations under the License.
%%
%% Developer of the eMQTT Code is <ery.lee@gmail.com>
%% Copyright (c) 2012 Ery Lee.  All rights reserved.
%%
-module(vmq_topic).

-import(lists, [reverse/1]).

-import(string, [rchr/2, substr/2, substr/3]).

%% ------------------------------------------------------------------------
%% Topic semantics and usage
%% ------------------------------------------------------------------------
%% A topic must be at least one character long.
%%
%% Topic names are case sensitive. For example, ACCOUNTS and Accounts are two different topics.
%%
%% Topic names can include the space character. For example, Accounts payable is a valid topic.
%%
%% A leading "/" creates a distinct topic. For example, /finance is different from finance. /finance matches "+/+" and "/+", but not "+".
%%
%% Do not include the null character (Unicode \x0000) in any topic.
%%
%% The following principles apply to the construction and content of a topic tree:
%%
%% The length is limited to 64k but within that there are no limits to the number of levels in a topic tree.
%%
%% There can be any number of root nodes; that is, there can be any number of topic trees.
%% ------------------------------------------------------------------------

-export([new/1,
		 type/1,
		 match/2,
		 validate/1,
		 triples/1,
		 words/1,
         unword/1]).

-define(MAX_LEN, 64*1024).

new(Name) when is_list(Name) ->
    {topic, Name}.

%% ------------------------------------------------------------------------
%% topic type: direct or wildcard
%% ------------------------------------------------------------------------
type({topic, Name}) ->
	type(words(Name));
type([]) ->
	direct;
type(["#"]) ->
	wildcard;
type(["+"|_T]) ->
	wildcard;
type([_|T]) ->
	type(T).

%% ------------------------------------------------------------------------
%% topic match
%% ------------------------------------------------------------------------
match([], []) ->
	true;
match([H|T1], [H|T2]) ->
	match(T1, T2);
match([_H|T1], ["+"|T2]) ->
	match(T1, T2);
match(_, ["#"]) ->
	true;
match([_H1|_], [_H2|_]) ->
	false;
match([], [_H|_T2]) ->
	false;
match(_, _) -> false.


%% ------------------------------------------------------------------------
%% topic validate
%% ------------------------------------------------------------------------
validate({_, ""}) ->
	false;
validate({_, Topic}) when length(Topic) > ?MAX_LEN ->
	false;
validate({Type, Topic}) when is_list(Topic) ->
	valid(Type, words(Topic)).

triples(S) when is_list(S) ->
	triples(S, []).

triples(S, Acc) ->
	triples(rchr(S, $/), S, Acc).

triples(0, S, Acc) ->
	[{root, S, S}|Acc];

triples(I, S, Acc) ->
	S1 = substr(S, 1, I-1),
	S2 = substr(S, I+1),
	triples(S1, [{S1, S2, S}|Acc]).

words(Topic) when is_list(Topic) ->
	words(Topic, [], []).

words([], Word, ResAcc) ->
	reverse([reverse(W) || W <- [Word|ResAcc]]);

words([$/|Topic], Word, ResAcc) ->
	words(Topic, [], [Word|ResAcc]);

words([C|Topic], Word, ResAcc) ->
	words(Topic, [C|Word], ResAcc).

unword(Topic) ->
    lists:reverse(unword(Topic, [])).

unword([[]], Acc) -> Acc;
unword([], Acc) -> [$/|Acc];
unword([Word], Acc) -> [Word|Acc];
unword([[]|Topic], Acc) ->
    unword(Topic, [$/|Acc]);
unword([Word|Rest], Acc) ->
    unword(Rest, [$/, Word|Acc]).

valid(Type, [""|Words]) -> valid2(Type, Words); %% leading '/'
valid(Type, Words) -> valid2(Type, Words).

valid2(_, [""]) -> true; %% allow trailing '/'
%valid2([""|_Words]) -> false; %% forbid '//'
valid2(subscribe, ["#"|Words]) when length(Words) > 0 -> false;
valid2(subscribe, ["#"]) -> true;
valid2(subscribe, ["+"|Words]) -> valid2(subscribe, Words);
valid2(publish, ["#"|_]) -> false;
valid2(publish, ["+"|_]) -> false;
valid2(Type, [Word|Words]) ->
    case include_wildcard_char(Word) of
        true -> false;
        false -> valid2(Type, Words)
    end;
valid2(_, []) -> true.

include_wildcard_char([]) -> false;
include_wildcard_char([$#|_]) -> true;
include_wildcard_char([$+|_]) -> true;
include_wildcard_char([_|Rest]) ->
    include_wildcard_char(Rest).


-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

validate_no_wildcard_test() ->
    % no wildcard
	true = validate({subscribe, "a/b/c"}),
	true = validate({subscribe, "/a/b"}),
    true = validate({subscribe, "test/topic/"}),
    true = validate({subscribe, "test////a//topic"}),
    true = validate({subscribe, "/test////a//topic"}),
    true = validate({subscribe, "foo//bar///baz"}),
    true = validate({subscribe, "foo//baz//"}),
    true = validate({subscribe, "foo//baz"}),
    true = validate({subscribe, "foo//baz/bar"}),
    true = validate({subscribe, "////foo///bar"}).

validate_wildcard_test() ->
	true = validate({subscribe, "/+/x"}),
	true = validate({subscribe, "/a/b/c/#"}),
    true = validate({subscribe, "#"}),
    true = validate({subscribe, "foo/#"}),
    true = validate({subscribe, "foo/+/baz"}),
    true = validate({subscribe, "foo/+/baz/#"}),
    true = validate({subscribe, "foo/foo/baz/#"}),
    true = validate({subscribe, "foo/#"}),
    true = validate({subscribe, "/#"}),
    true = validate({subscribe, "test/topic/+"}),
    true = validate({subscribe, "+/+/+/+/+/+/+/+/+/+/test"}),

    false = validate({publish, "test/#-"}),
    false = validate({publish, "test/+-"}),
	false = validate({subscribe, "a/#/c"}),
    false = validate({subscribe, "#testtopic"}),
    false = validate({subscribe, "testtopic#"}),
    false = validate({subscribe, "+testtopic"}),
    false = validate({subscribe, "testtopic+"}),
    false = validate({subscribe, "#testtopic/test"}),
    false = validate({subscribe, "testtopic#/test"}),
    false = validate({subscribe, "+testtopic/test"}),
    false = validate({subscribe, "testtopic+/test"}),
    false = validate({subscribe, "/test/#testtopic"}),
    false = validate({subscribe, "/test/testtopic#"}),
    false = validate({subscribe, "/test/+testtopic"}),
    false = validate({subscribe, "/testtesttopic+"}).



-endif.
