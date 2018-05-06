%%%-------------------------------------------------------------------
%%% @author yangyajun03
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 04. 五月 2018 上午11:57
%%%-------------------------------------------------------------------
-author("yangyajun03").

-define(APP_NAME, mq_seq_msg).
-define(MQ_POOLS, begin {ok, Pools} = application:get_env(?APP_NAME, mq_pools), Pools end).
-define(MQ_CONFIG, begin {ok, MqConfig} = application:get_env(?APP_NAME, mq_config), MqConfig end).
-define(TASK_CONFIG, begin {ok, TaskConfig} = application:get_env(?APP_NAME, task_config), TaskConfig end).