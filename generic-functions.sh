debug () {
message=$1
if [ "${DEBUG}" = "TRUE" ]; then
  echo "  [DEBUG] ${message}" | tee --append ${diagfile}
fi
}

verifyCommand () {
lastExit=$?
command=$1
if [ ${lastExit} -eq 0 ]; then
  echo "${command} succeeded" | tee --append ${logfile}
else
  echo "${command} failed!" | tee --append ${logfile}
  exit 1
fi
}

printResult () {
  echo "--------script completed--------"
  echo "you can find the log in: ${logfile}"
  if [ "${DEBUG}" == "TRUE" ]; then
    echo "you can find the debug log in ${diagfile}"
  fi
  if [ ! -z ${stageDir} ]; then
    echo "there is a stagedir available at"
    echo "${stageDir}"
  fi
}
