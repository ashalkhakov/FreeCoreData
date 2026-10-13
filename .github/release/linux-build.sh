#!/bin/bash
# On the stack in $PREFIX, what CI ran: the framework and its unit tests,
# Model Builder and its end-to-end test (driven under Xvfb), and the
# PostgreSQL and MySQL stores against PostgreSQL 16, MySQL 8 and MariaDB 11
# (the servers gnustep-release-actions starts: databases in build.yml), each
# alone and both in one process. linux-install.sh then installs what the
# AppImage carries.
set -eo pipefail
# GNUstep.sh reads unset variables (ZSH_VERSION), so set -u comes after it.
. "$PREFIX/System/Library/Makefiles/GNUstep.sh"
set -u
make
make -C Tests run-tests
make -C ModelBuilder
make -C Tests/ModelBuilder
xvfb-run -a make -C Tests/ModelBuilder check

make -C Backends/PostgreSQL
make -C Backends/MySQL
# A suite that cannot reach its server fails rather than skips.
export CD_TEST_REQUIRE_DATABASE=1
CD_TEST_POSTGRES_URL="$POSTGRES_URL" make -C Backends/PostgreSQL/Tests run-tests
CD_TEST_MYSQL_URL="${MYSQL_URL%/*}/cdtest" make -C Backends/MySQL/Tests run-tests
CD_TEST_MYSQL_URL="${MARIADB_URL%/*}/cdtest" make -C Backends/MySQL/Tests run-tests
CD_TEST_POSTGRES_URL="$POSTGRES_URL" CD_TEST_MYSQL_URL="${MYSQL_URL%/*}/cdtest" \
  make -C Backends/Common/Tests run-tests
