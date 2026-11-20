#!/bin/sh
set -eu

CDPATH='' cd "$(dirname "$0")"
alr -n build

./bin/queue_tests
timeout 10s ./bin/topic_tests
timeout 75s ./bin/topic_load_tests "${TOPIC_LOAD_SECONDS:-2}"
./bin/wire_tests
timeout 10s ./bin/transport_tests
timeout 10s ./bin/bridge_tests
timeout 10s ./bin/bridge_startup_tests
timeout 10s ./bin/bridge_ingress_tests
timeout 10s ./bin/bridge_shutdown_tests
timeout 10s ./bin/bridge_receive_shutdown_tests
