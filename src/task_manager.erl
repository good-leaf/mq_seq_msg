%%%-------------------------------------------------------------------
%%% @author yangyajun03
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 04. 五月 2018 上午11:51
%%%-------------------------------------------------------------------
-module(task_manager).
-author("yangyajun03").

-include("mq_seq_msg.hrl").
-behaviour(gen_server).

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

-export([
    start/0,
    task_consumer_unbind/2,
    notice_execute/1,
    cancel_execute/1,
    consumer_append/1,
    consumer_choose/0,
    consumer_normal_choose/1,
    task_table/0,
    task_free_consumer/0
]).


-define(SERVER, ?MODULE).
-record(state, {
    consumer_free
}).

-define(TASK_TAB, task_table).
-define(CONSUMER, consumer).
-define(TIMEVAL, 5000).
%%%===================================================================
%%% API
%%%===================================================================
start() ->
    rabbitmq_pool:add_pools(?MQ_POOLS, infinity),
    task_server:start().
%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link() ->
    {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

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
init([]) ->
    ets:new(?TASK_TAB, [
        set,
        public,
        named_table,
        {write_concurrency, false},
        {read_concurrency, false}
    ]),
    erlang:send_after(?TIMEVAL, self(), task_check),
    {ok, #state{consumer_free = queue:new()}}.

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
handle_call({append, Pid}, _From, #state{consumer_free = Queue} = State) ->
    lager:debug("append consumer pid:~p", [Pid]),
    {reply, ok, State#state{consumer_free = queue:in(Pid, Queue)}};
handle_call(choose, _From, #state{consumer_free = Queue} = State) ->
    case consumer_check_alive(Queue) of
        {empty, Queue1} ->
            {reply, {error, undefined}, State#state{consumer_free = Queue1}};
        {Pid, Queue1} ->
            {reply, {ok, Pid}, State#state{consumer_free = Queue1}}
    end;
handle_call(get_consumer, _From, #state{consumer_free = Queue} = State) ->
    {reply, Queue, State};
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
handle_info(task_check, State) ->
    task_check(),
    erlang:send_after(?TIMEVAL, self(), task_check),
    {noreply, State};
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
terminate(_Reason, _State) ->
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

%%%===================================================================
%%% Internal functions
%%%===================================================================
consumer_append(Pid) ->
    gen_server:call(?SERVER, {append, Pid}).

consumer_choose() ->
    gen_server:call(?SERVER, choose).

consumer_check_alive(Queue) ->
    case queue:out(Queue) of
        {empty, Queue1} ->
            {empty, Queue1};
        {{value, Pid}, Queue1} ->
            case is_process_alive(Pid) of
                true ->
                    {Pid, Queue1};
                false ->
                    consumer_check_alive(Queue1)
            end
    end.

notice_execute(TaskInfo) ->
    lager:debug("task notice execute, task:~p", [TaskInfo]),
    case consumer_normal_choose(TaskInfo) of
        {ok, Pid} ->
            case recv_consumer:task_subscribe(Pid, TaskInfo) of
                ok ->
                    task_consumer_bind(TaskInfo, Pid),
                    ok;
                error ->
                    case is_process_alive(Pid) of
                        true ->
                            consumer_append(Pid);
                        false ->
                            %drop dead pid, task execute failed
                            drop
                    end,
                    lager:error("notice execute failed, task:~p", [TaskInfo]),
                    error
            end;
        {skip, _Pid} ->
            ok
    end.

cancel_execute(TaskInfo) ->
    lager:debug("task cancel execute, task:~p", [TaskInfo]),
    {ok, Pid} = get_consumer_pid_from_task(TaskInfo),
    %是否检查此进程已经停止
    case recv_consumer:task_unsubscribe(Pid) of
        ok ->
            task_consumer_unbind(TaskInfo, Pid),
            lager:debug("cancel execute success, task:~p", [TaskInfo]),
            ok;
        error ->
            lager:error("cancel execute failed, task:~p", [TaskInfo]),
            error
    end.

consumer_normal_choose(TaskInfo) ->
    TaskId = task_server:task_id(TaskInfo),
    {ok, Pid} = consumer_choose(),
    case ets:lookup(?TASK_TAB, TaskId) of
        [] ->
            {ok, Pid};
        [{TaskId, TaskInfo, ConsumerPid}] ->
            lager:error("task exist bind, task:~p, concumer:~p", [TaskInfo, ConsumerPid]),
            {skip, ConsumerPid}
    end.

get_consumer_pid_from_task(TaskInfo) ->
    TaskId = task_server:task_id(TaskInfo),
    case ets:lookup(?TASK_TAB, TaskId) of
        [] ->
            lager:error("get_consumer_pid_from_task exception, task:~p", [TaskInfo]),
            {error, empty};
        [{TaskId, TaskInfo, ConsumerPid}] ->
            {ok, ConsumerPid}
    end.

task_consumer_bind(TaskInfo, Pid) ->
    true = ets:insert(?TASK_TAB, {task_server:task_id(TaskInfo), TaskInfo, Pid}),
    ok.

task_consumer_unbind(TaskInfo, Pid) ->
    true = ets:delete(?TASK_TAB, task_server:task_id(TaskInfo)),
    case is_process_alive(Pid) of
        true ->
            consumer_append(Pid);
        false ->
            %drop dead pid, task execute failed
            drop
    end, ok.

task_table() ->
    ets:tab2list(?TASK_TAB).

task_free_consumer() ->
    gen_server:call(?SERVER, get_consumer).

task_check() ->
    TaskList = ets:tab2list(?TASK_TAB),
    Fun = fun(T) ->
        {_TaskId, TaskInfo, ConsumerPid} = T,
        case is_pid(ConsumerPid) andalso is_process_alive(ConsumerPid) of
            true ->
                ok;
            false ->
                lager:error("task status check, task:~p, consumer:~p is dead.", [TaskInfo, ConsumerPid])
        end
          end,
    [Fun(T) || T <- TaskList].