-module(rss_feeds_http).
-compile({no_auto_import,[get/1]}).
-export([get/1]).

get(Url) when is_list(Url) ->
    get(unicode:characters_to_binary(Url));
get(Url) when is_binary(Url) ->
    _ = application:ensure_all_started(ssl),
    _ = application:ensure_all_started(inets),
    case httpc:request(get, {Url, []}, [], [{body_format, binary}]) of
        {ok, {{_, 200, _}, _Headers, Body}} ->
            {ok, Body};
        {ok, {{_, Status, _}, _Headers, Body}} ->
            {error, format_error({http_error, Status, Body})};
        {error, Reason} ->
            {error, format_error(Reason)}
    end.

format_error(Reason) ->
    unicode:characters_to_binary(io_lib:format("~p", [Reason])).
