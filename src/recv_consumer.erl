%%%-------------------------------------------------------------------
%%% @author yangyajun03
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 04. 五月 2018 下午12:17
%%%-------------------------------------------------------------------
-module(recv_consumer).
-author("yangyajun03").

-include("mq_seq_msg.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

-behaviour(gen_server).
%% API
-export([start/1, start_link/1]).
%% gen_server callbacks
-export([init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

-define(SERVER, ?MODULE).
-record(state, {
    channel,
    pid,
    task,
    config,
    consumer_tag,
    queue
}).

-export([
    callback_ack/2,
    task_subscribe/2,
    task_unsubscribe/1
]).
%%%===================================================================
%%% API
%%%===================================================================
%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link(_) ->
    {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link([Channel]) ->
    gen_server:start(?MODULE, [Channel], []).
start(Channel) ->
    start_link([Channel]).
%%%===================================================================
%%% gen_server callbacks
%%%===================================================================
%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
    {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term()} | ignore).
init([Channel]) ->
    process_flag(trap_exit, true),
    erlang:monitor(process, Channel),
    task_manager:consumer_append(self()),
    {ok, #state{channel = Channel, pid = self(), task = <<>>, config = [], queue = <<"">>, consumer_tag = <<>>}}.
%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #state{}) ->
    {reply, Reply :: term(), NewState :: #state{}} |
    {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_call({subscribe, TaskInfo}, _From, State) ->
    {Flag, NewState} = subscribe(TaskInfo, State),
    SaveState = case Flag of
                    ok ->
                        NewState;
                    error ->
                        State
                end,
    {reply, Flag, SaveState};
handle_call(unsubscribe, _From, State) ->
    {Flag, NewState} = unsubscribe(State),
    SaveState = case Flag of
                    ok ->
                        NewState;
                    error ->
                        State
                end,
    {reply, Flag, SaveState};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.
%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_cast({ack, Tag}, #state{channel = Channel} = State) ->
    amqp_channel:cast(Channel, #'basic.ack'{delivery_tag = Tag}),
    {noreply, State};
handle_cast(_Request, State) ->
    {noreply, State}.
%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_info({#'basic.deliver'{delivery_tag = Tag, redelivered = _Redelivered},
    #amqp_msg{payload = Body}}, State) ->
    try
        {ok, MsgModule} = application:get_env(mq_seq_msg, msg_module),
        MsgModule:handle_message(self(), Tag, Body)
    catch
        E:R ->
            lager:error("mq message overload, error:~p, reason:~p", [E, R])
    end,
    {noreply, State, hibernate};
handle_info(_Info, State) ->
    {noreply, State}.
%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #state{}) -> term()).
terminate(_Reason, State) ->
    task_manager:task_consumer_unbind(State#state.task, State#state.pid),
    ok.
%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) ->
    {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

task_subscribe(Pid, TaskInfo) ->
    gen_server:call(Pid, {subscribe, TaskInfo}).

task_unsubscribe(Pid) ->
    gen_server:call(Pid, unsubscribe).
%%%===================================================================
%%% Internal functions
%%%===================================================================
callback_ack(Pid, Tag) ->
    gen_server:cast(Pid, {ack, Tag}).

subscribe(TaskInfo, State) ->
    Config = TaskInfo ++ ?MQ_CONFIG,
    lager:debug("mq subscribe task:~p, config:~p, state:~p", [TaskInfo, Config, State]),
    Channel = State#state.channel,
    case is_pid(Channel) andalso is_process_alive(Channel) of
        true ->
            try
                #'basic.qos_ok'{} = amqp_channel:call(Channel, #'basic.qos'{prefetch_count = 0, global = true}),
                QueueDeclare = #'queue.declare'{
                    queue = proplists:get_value(queue, Config, <<"">>),
                    durable = proplists:get_value(durable, Config, false),
                    exclusive = proplists:get_value(exclusive, Config, false),
                    auto_delete = proplists:get_value(auto_delete, Config, false),
                    arguments = proplists:get_value(arguments, Config, [])
                },
                #'queue.declare_ok'{queue = MqName} = amqp_channel:call(Channel, QueueDeclare),

                QueueBind = #'queue.bind'{
                    queue = MqName,
                    exchange = proplists:get_value(exchange, Config),
                    routing_key = proplists:get_value(routing_key, Config, <<"">>)
                },
                #'queue.bind_ok'{} = amqp_channel:call(Channel, QueueBind),

                Sub = #'basic.consume'{queue = MqName, no_ack = false}, %需要确认回复
                #'basic.consume_ok'{consumer_tag = ConsumerTag} = amqp_channel:subscribe(Channel, Sub, self()),
                {ok, State#state{consumer_tag = ConsumerTag, task = TaskInfo, config = Config, queue = MqName}}
            catch
                Error:Reason ->
                    lager:error("mq subscribe error:~p, reason:~p, state:~p, trace:~p",
                        [Error, Reason, State, erlang:get_stacktrace()]),
                    {error, State}
            end;
        false ->
            lager:error("mq subscribe channel:~p is dead, config:~p, state:~p",
                [Channel, Config, State]),
            {error, State}
    end.

unsubscribe(State) ->
    Channel = State#state.channel,
    lager:debug("mq unsubscribe, state:~p", [State]),
    case is_pid(Channel) andalso is_process_alive(Channel) of
        true ->
            try
                %取消订阅
                #'basic.cancel_ok'{consumer_tag = _ConsumerTag} = amqp_channel:call(Channel, #'basic.cancel'{consumer_tag = State#state.consumer_tag}),

                {ok, State#state{queue = <<"">>, task = <<"">>, consumer_tag = <<>>, config = []}}
            catch
                Error:Reason ->
                    lager:error("mq unsubscribe error:~p, reason:~p, state:~p, trace:~p",
                        [Error, Reason, State, erlang:get_stacktrace()]),
                    {error, State}
            end;
        false ->
            lager:error("mq unsubscribe channel:~p is dead, state:~p",
                [Channel, State]),
            {error, State}
    end.


%%declare_exchange(Channel) ->
%%    Command = #'exchange.declare'{
%%        exchange = ?TASK_MQ_EXCHANGE
%%        , type = ?TASK_MQ_EX_TYPE
%%        , passive = false
%%        , durable = false
%%        , auto_delete = false
%%        , internal = false
%%        , nowait = false
%%        , arguments = []
%%    },
%%    try amqp_channel:call(Channel, Command)
%%    catch
%%        E:R ->
%%            lager:error("amqp command exchange:~p, extype:~p, exception:~p, reason:~p",
%%                [?TASK_MQ_EXCHANGE, ?TASK_MQ_EX_TYPE, E, R])
%%    end.