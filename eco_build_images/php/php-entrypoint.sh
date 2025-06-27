#!/bin/bash
declare -a mysqlifailtests
declare -a pdofailtests

set -x -v

case "${PHP_VERSION}" in
	7\.[12])
		mysqlifailtests+=( mysqli_get_client_stats ) # 7.3 fixed
		mysqlifailtests+=( 057 )
		mysqlifailtests+=( mysqli_pconn_max_links )
		mysqlifailtests+=( mysqli_stmt_bind_param_many_columns )
		mysqlifailtests+=( mysqli_report )
		mysqlifailtests+=( bug34810 )
		mysqlifailtests+=( mysqli_class_mysqli_interface )
		mysqlifailtests+=( mysqli_reap_async_query )
		mysqlifailtests+=( mysqli_character_set ) # 001+ [008 + utf8mb3] [2019] Invalid characterset or character set not supported
		mysqlifailtests+=( mysqli_options ) # 013+ [009] Setting charset name 'utf8mb3' has failed
		mysqlifailtests+=( mysqli_set_charset ) # 001+ [017] Cannot set character set to 'utf8mb3', [2019] Invalid characterset or character set not supported \n002+
		;&
	7\.3)
		mysqlifailtests+=( mysqli_stmt_get_result_metadata_fetch_field ) # https://github.com/php/php-src/pull/6484 - fixed 7.4
		;&
	7\.4)
		mysqlifailtests+=( 063 ) # fixed in 8.0 at least
		mysqlifailtests+=( mysqli_change_user_new ) # at least 8.0 (not 7.4)
		;&
	8\.0)
		pdofailtests+=( bug_38546 bug76815 )
		;&
	8\.1)
		mysqlifailtests+=( mysqli_real_connect mysqli_real_connect_pconn mysqli_connect_oo mysqli_report ) # https://github.com/php/php-src/commit/b6b4a628a5009024f9abca664f6a25d64b6f64d6
		;&
	master)
		mysqlifailtests+=( mysqli_reap_async_query_error mysqli_execute_query.phpt ) # https://github.com/php/php-src/pull/10029
		mysqlifailtests+=( mysqli_connect ) # Using Password - like b6b4a628a5009024f9
		mysqlifailtests+=( gh8978 ) # 11.4 Warning: mysqli_real_connect(): This stream does not support SSL/crypto in
		                            # <11.4 - requires TLS setup on server maybe to get right result
		#mysqlifailtests+=( mysqli_change_user ) # will below 3 - fail on 7.1, not mdb-10.2. TODO
		#mysqlifailtests+=( mysqli_change_user_old ) # TODO
		#mysqlifailtests+=( mysqli_change_user_oo ) # TODO
		#mysqlifailtests+=( mysqli_class_mysqli_properties_no_conn ) # TODO
		#pdofailtests+=( pdo_mysql_prepare_load_data ) # 8.0, not 7.4 TODO investigate
		#pdofailtests+=( pdo_mysql_attr_oracle_nulls ) # 8.0, not 7.4. TODO investigate
		#mysqlifailtests+=( mysqli_debug )
		#mysqlifailtests+=( mysqli_debug_append )
		#mysqlifailtests+=( mysqli_debug_control_string )
		#mysqlifailtests+=( mysqli_debug_mysqlnd_control_string )
		#mysqlifailtests+=( mysqli_debug_mysqlnd_only )
		#mysqlifailtests+=( mysqli_class_mysqli_interface ) # 8.0, not 7.1
		#mysqlifailtests+=( mysqli_auth_pam ) # Access denied for user 'pamtest'@'localhost' (using password: NO) - but password is.

esac

GLOBIGNORE=

codedir=/php-src
for f in "${mysqlifailtests[@]}"
do
  GLOBIGNORE="$GLOBIGNORE:$codedir/ext/mysqli/tests/$f.phpt"
done
for f in "${pdofailtests[@]}"
do
  GLOBIGNORE="$GLOBIGNORE:$codedir/ext/pdo_mysql/tests/$f.phpt"
done
echo $GLOBIGNORE

mkdir -p /tmp/s /tmp/p
TEST_PHP_EXECUTABLE=/usr/local/bin/php /usr/local/bin/php run-tests.php \
	--temp-source /tmp/s \
	--temp-target /tmp/t \
	--show-diff ext/mysqli/tests/ \
       	ext/pdo_mysql/tests/

