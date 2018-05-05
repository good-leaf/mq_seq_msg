%%%-------------------------------------------------------------------
%%% @author yangyajun03
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 04. 五月 2018 上午11:57
%%%-------------------------------------------------------------------
-author("yangyajun03").

-include("../deps/slager/src/slager.hrl").
-define(APP_NAME, mq_seq_msg).
-define(MQ_POOLS, begin {ok, Pools} = application:get_env(?APP_NAME, mq_pools), Pools end).