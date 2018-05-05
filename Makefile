PROJECT = mq_seq_msg
PROJECT_DESCRIPTION = New project
PROJECT_VERSION = 0.1.0

ERLC_OPTS = +'{parse_transform, lager_transform}' +'{lager_truncation_size, 512000}' +'{lager_extra_sinks, [sdebug, sinfo, swarning, serror]}'
DEPS = task_dispatch rabbitmq_pool slager
dep_task_dispatch = git https://github.com/good-leaf/task_dispatch.git 1.0.0
dep_rabbitmq_pool = git https://github.com/ccredrock/rabbitmq_pool 1.3
dep_slager = git https://github.com/good-leaf/slager.git

include erlang.mk
