PROJECT = mq_seq_msg
PROJECT_DESCRIPTION = New project
PROJECT_VERSION = 0.1.0

ERLC_OPTS = +'{parse_transform, lager_transform}'
DEPS = task_dispatch rabbitmq_pool lager
dep_task_dispatch = git https://github.com/good-leaf/task_dispatch.git 1.0.0
dep_rabbitmq_pool = git https://github.com/ccredrock/rabbitmq_pool 1.3

include erlang.mk
