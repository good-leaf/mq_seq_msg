-module(mq_seq_msg_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

-define(MILLISECONDS_IN_SECOND, 1000).
-define(WORKER(I), {I, {I, 'start_link', []}, 'permanent', 5 * ?MILLISECONDS_IN_SECOND, 'worker', [I]}).

-define(CHILDREN, [
    ?WORKER('task_callback'),
    ?WORKER('task_manager')
]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    {ok, {{one_for_one, 1, 5}, ?CHILDREN}}.
