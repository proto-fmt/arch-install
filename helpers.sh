#!/bin/bash

# Define colors
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RESET=$(tput sgr0)


check_error() {
  local exit_status="$1"
  local description="$2"
  local extra_info="$3"

  if [[ "$exit_status" -eq 0 ]]; then
    printf "\r%s[ OK ]%s %s %s%s%s\n" "${GREEN}" "${RESET}" "${description}" "${YELLOW}" "${extra_info}" "${RESET}"
  else
    printf "\r%s[ FAIL ]%s %s\n" "${RED}" "${RESET}" "${description}"
    exit 1
  fi
}

track_command() {
  local pid=$1
  local description=$2

  local spin=("-" "/" "|" "\\")
  local i=0

  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i+1) % ${#spin[@]} ))
    printf "\r%s[ %s ]%s %s" "${YELLOW}" "${spin[$i]}" "${RESET}" "${description}"
    sleep 0.2
  done

  wait "$pid"

  check_error "$?" "$description"
}
