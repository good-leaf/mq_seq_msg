%%%-------------------------------------------------------------------
%%% @author yangyajun03
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 04. 五月 2018 下午8:32
%%%-------------------------------------------------------------------
-module(task_callback).
-author("yangyajun03").

-include("mq_seq_msg.hrl").
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
    task_list/1,
    task_notice/2,
    task_cancel/2,
    mnesia_tables/0,
    handle_message/2
]).


-define(SERVER, ?MODULE).
-record(state, {}).

%%%===================================================================
%%% API
%%%===================================================================

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
    {ok, #state{}}.

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
handle_call(task_list, _From, State) ->
    %lager:debug("query task list"),
    Reply = generate_task(),
    {reply, Reply, State};
handle_call({task_notice, TaskInfo}, _From, State) ->
    lager:debug("recv task notice, task:~p", [TaskInfo]),
    try
        Flag = task_manager:notice_execute(TaskInfo),
        {reply, Flag, State}
    catch
        Error:Reason ->
            lager:error("task notice execute error:~p, reason:~p, task_info:~p, trace:~p",
                [Error, Reason, TaskInfo, erlang:get_stacktrace()]),
            {reply, error, State}
    end;
handle_call({task_cancel, TaskInfo}, _From, State) ->
    lager:debug("recv task cancel, task:~p", [TaskInfo]),
    try
        Flag = task_manager:cancel_execute(TaskInfo),
        {reply, Flag, State}
    catch
        Error:Reason ->
            lager:error("task cancel execute error:~p, reason:~p, task_info:~p, trace:~p",
                [Error, Reason, TaskInfo, erlang:get_stacktrace()]),
            {reply, error, State}
    end;
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
%%mnesia table test
-record(dispatch_task, {
    id,
    node,
    task
}).

mnesia_tables() ->
    [
        {dispatch_task, [
            {record_name, dispatch_task},
            {attributes, record_info(fields, dispatch_task)},
            {ram_copies, [node()]},
            {match, #dispatch_task{_ = '_'}}
        ]}
    ].

%callback
-spec task_list(integer()) -> {ok, list()} | {error, list()}.
task_list(TimeOut) ->
    gen_server:call(?SERVER, task_list, TimeOut).

-spec task_notice(any(), integer()) -> ok | error.
task_notice(TaskInfo, TimeOut) ->
    gen_server:call(?SERVER, {task_notice, TaskInfo}, TimeOut).

-spec task_cancel(any(), integer()) -> ok | error.
task_cancel(TaskInfo, TimeOut) ->
    gen_server:call(?SERVER, {task_cancel, TaskInfo}, TimeOut).

-spec generate_task() -> {ok, list()} | {error, list()}.
generate_task() ->
    Snum = proplists:get_value(start_num, ?TASK_CONFIG),
    Enum = proplists:get_value(end_num, ?TASK_CONFIG),
    Prefix = proplists:get_value(prefix, ?TASK_CONFIG),

    TaskNum = lists:seq(Snum, Enum),
    {ok, lists:foldl(fun(N, Acc) ->
        Bnum = integer_to_binary(N),
        Acc ++ [[{routing_key, <<Prefix/binary, Bnum/binary, ".*">>}]] end, [], TaskNum)}.

-spec handle_message(pid(), binary()) -> ok | error.
handle_message(ConsumerPid, Event) ->
    %消息如果采用异步处理，在任务取消变更时，可能存在异步进程还没有处理完消息，任务就被分配到别的节点。
    lager:debug("recv consumer:~p, event:~p", [ConsumerPid, Event]),
    ok.
