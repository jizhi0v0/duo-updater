#!/bin/bash
# rerun-maketest.sh <run-name> — re-run the harness make test with Python >= 3.10
# for runs that started before the shim was added (their base Makefile calls bare python3).
. "$(dirname "$0")/env.sh"; R=$B/runs/$1
cd $R/repo && PATH=$PYSHIM:$PATH make test > $R/make-test.log 2>&1; echo $? > $R/make-test.rc
rm -rf DuoUpdaterCore/.build CLI/.build application-test/.build
echo "$1 make_test=$(cat $R/make-test.rc)"
