%%%-------------------------------------------------------------------
%%% @author lenovo
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 06. 五月 2018 12:08
%%%-------------------------------------------------------------------
-module(send_produce).
-author("lenovo").

-include("mq_seq_msg.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").
-export([
    send/1,
    send/2,
    loop_send/3,
    declare_exchange/0
]).

-export([
    send_test/1
]).

declare_exchange() ->
    Exchange = proplists:get_value(exchange, ?MQ_CONFIG),
    Type = proplists:get_value(ex_type, ?MQ_CONFIG),
    ExDurable = proplists:get_value(ex_durable, ?MQ_CONFIG, false),
    #'exchange.declare_ok'{} =
        rabbitmq_pool:channel_call(#'exchange.declare'{exchange = Exchange, type = Type, durable = ExDurable}).

send(Payload, RoutingKey) ->
    Exchange = proplists:get_value(exchange, ?MQ_CONFIG),
    rabbitmq_pool:safe_publish(Exchange, Payload, RoutingKey).

send(Payload) ->
    Exchange = proplists:get_value(exchange, ?MQ_CONFIG),
    rabbitmq_pool:safe_publish(Exchange, Payload).

send_test(LoopNum) ->
    Payload = <<"You keep on concentrating on the things you wish you had or things you wish you didn’t have and you sort of forget what you do have.-Nick Vujicic">>,
    Snum = proplists:get_value(start_num, ?TASK_CONFIG),
    Enum = proplists:get_value(end_num, ?TASK_CONFIG),
    Prefix = proplists:get_value(prefix, ?TASK_CONFIG),
    NumList = lists:seq(Snum, Enum),
    lists:foreach(fun(N) ->
        Bnum = integer_to_binary(N),
        spawn(send_produce, loop_send, [Payload, <<Prefix/binary, Bnum/binary, ".event">>, LoopNum]) end, NumList).

loop_send(_Payload, _RoutingKey, 0) ->
    ok;
loop_send(Payload, RoutingKey, LoopNum) ->
    send(Payload, RoutingKey),
    loop_send(Payload, RoutingKey, LoopNum - 1).


