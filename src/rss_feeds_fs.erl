-module(rss_feeds_fs).
-export([read_file/1, write_file/2]).

read_file(Path) when is_list(Path) ->
    read_file(unicode:characters_to_binary(Path));
read_file(Path) when is_binary(Path) ->
    case file:read_file(Path) of
        {ok, Body} -> {ok, Body};
        {error, Reason} -> {error, format_error(Reason)}
    end.

write_file(Path, Body) when is_list(Path) ->
    write_file(unicode:characters_to_binary(Path), Body);
write_file(Path, Body) when is_binary(Path) ->
    case filelib:ensure_dir(Path) of
        ok ->
            case file:write_file(Path, Body) of
                ok -> {ok, nil};
                {error, Reason} -> {error, format_error(Reason)}
            end;
        {error, Reason} -> {error, format_error(Reason)}
    end.

format_error(Reason) ->
    unicode:characters_to_binary(io_lib:format("~p", [Reason])).
