#!/bin/bash

ME="$(readlink -e -- "$0")" || exit
DIR="${ME%/*/*}"

exec socklinger -n-15 127.0.0.2:8080 "$DIR/proxy.sh"
