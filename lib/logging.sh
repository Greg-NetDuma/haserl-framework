# Sets up logging.
#
# See this for log levels:
#   https://stackoverflow.com/questions/2031163/when-to-use-the-different-log-levels
#
# Usage:
#
#   Only runs logging commands when level is sufficient:
#     log <level> 'command(s)'
#
#   Redirects output to log() function of corresponding level:
#     { <program-commands>; } >&101 (for level 1)
#
#
export LOG_FILE=${LOG_FILE:=&2}
export LOG_LABLE=${LOG_LABLE:=HF}
export LOG_LEVEL=${LOG_LEVEL:=3}
export LOG_LEVELS=$(seq -s ' ' 1 6)
export LOG_LEVEL_NAMES='fatal error warn info debug trace'

# # Routes stderr through the log function.
# # See the other component of this below.
# exec 22>&2
	
log() {
	{	#echo "Logger ($1) called with str: $2" >> log.log
		local level=${1:-1}
		local input="${2:-$(cat -)}"
		
		local cmd="${input##[^-]*}"
		#echo "log cmd: $cmd"
		local str="${input##[-]*}"
		#echo "log str: $str"
		
		#echo "Checking input log level $1 against setting $LOG_LEVEL"
		if [ $level -le $LOG_LEVEL ]; then
			if [ $LOG_LEVEL -ge 5 ]; then
			  timer_data="$(timer)"
			fi
			printf '%s : ' "$(date -Iseconds) $timer_data $LOG_LABLE $$ [$(log_level_name $level)]" | sed 's/ \+/ /g'
			if [ ! -z "$cmd" ]; then				
				eval "${cmd/-/}"
			elif [ ! -z "$str" ]; then
				printf '%s\n' "$str"
			else
				printf '%s\n' "Logger called without the correct or enough data ($input) or args ($*)"
			fi
		fi
	} >&22
}

timer() {
	read up rest </proc/uptime
	printf '%s' "$1$up"
}

# Expects <n> <string>
nth_word() {
	echo "$2" | cut -d ' ' -f "$1"
}

# Expects log level n
log_level_name() {
	#nth_word "$1" "$LOG_LEVEL_NAMES" | awk '{ print toupper($0) }'
	nth_word "$1" "$LOG_LEVEL_NAMES" | tr '[a-z]' '[A-Z]'
}

cleanup_logging() {
	echo "Running cleanup_logging"
	for x in $LOG_LEVELS ; do
		{
		eval "exec 10$x>&-"
		rm -f /tmp/log_10$x
		}
	done
	unset LOGGING_IS_SETUP
} >&22 2>&1

# # Routes stderr through the log function.
# # See the other component of this below
#exec 22>&2

# TODO: Make whole block a function?
#
if [ -z "$LOGGING_IS_SETUP" ]; then
	# Routes stderr through the log function.
	# See the other component of this below
	local output=$(if [ "${LOG_FILE:0:1}" == '&' ]; then echo "$LOG_FILE"; else echo ">$LOG_FILE"; fi)
	eval "exec 22>$output"
	
	# Creates fifo files and listeners for each log level,
	# which allows command output to be piped to the logger.
	for x in $LOG_LEVELS; do
		rm -f /tmp/log_10$x
		mkfifo /tmp/log_10$x

		if [ $x -le $LOG_LEVEL ]; then
			
			while :; do
				IFS= read -r line </tmp/log_10$x
				echo "$line" | log $x
			done &
			
			log 6 "Logger daemon ($x) pid $! $$ listening to &10$x and /tmp/log_10$x"
		fi
		
		# TODO: Consider putting these FD manipulations in a function.
		eval "exec 10$x>&-"
		if [ $x -le $LOG_LEVEL ]; then
			eval "exec 10$x>/tmp/log_10$x"
		else
			eval "exec 10$x>/dev/null"
		fi
	done
	
	# See first half of this re-route above.
	# This has to go after the fifo is opened for reading, otherwise it breaks.'
	exec 2>&103
	#exec 2>/tmp/log_103
	
	# Creates file-descriptors and redirections to allow 
	# command output to be redirected to the logger.
	#
	# NOTE: Redirecting fd outputs to fifo files works, with caveats:
	#
	# If the fifo isn't already open for reading, you have to redirect
	# with BOTH read/write, or it will hang waiting for a reader.
	#   exec 103<>/tmp/log_103.
	#
	# if you 'cat' one of these fifo files (like in a daemon loop),
	# it will hange waiting for EOF, so you must use 'read line' instead,
	# if you want to push each line of input to a logger.
	#
	# TODO: Try putting the 'read line' in the 'log' function.
	#
	# TODO: Test this on alpine linux in docker. Does it work?
	# for x in $LOG_LEVELS; do
	# 	eval "exec 10$x>&-"
	# 	if [ $x -le $LOG_LEVEL ]; then
	# 		eval "exec 10$x>/tmp/log_10$x"
	# 	else
	# 		eval "exec 10$x>/dev/null"
	# 	fi
	# done

	export LOGGING_IS_SETUP=true
	
	echo "Logging activated" >&104
	# Print redirections to logger.
	log 6 "FD redirections for pid $$"
	log 6 '-ls -l /proc/$$/fd/ | awk '\''{print $9,$10,$11}'\''' &
	
fi
