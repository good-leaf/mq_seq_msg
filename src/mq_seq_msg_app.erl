-module(mq_seq_msg_app).
-behaviour(application).

-export([start/2]).
-export([stop/1]).
-include("mq_seq_msg.hrl").

start(_Type, _Args) ->
    check_fun_export(),
    %%启动bz相关rabbitmq
    mq_seq_msg_sup:start_link().

stop(_State) ->
    ok.

check_fun_export() ->
    {ok, MsgModule} = application:get_env(?APP_NAME, msg_module),
    true = erlang:function_exported(MsgModule, handle_message, 3).