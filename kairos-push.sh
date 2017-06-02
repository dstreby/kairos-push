#!/usr/bin/env bash

readonly script_dir=$(cd -P -- "$(dirname -- "$0")" && pwd -P)
readonly config="$script_dir/kairos-push.conf"
readonly args="$@"

echerr() {
  echo -ne "[ \e[31mERROR\e[0m ] "
  cat <<< "$@" 1>&2
}

verbose() {
  if [ $kairos_VERBOSE -gt 0 ]; then
    echo -e "$@"
  fi
}

get_config() {
# Source the configuration
  if [[ -f "$config" ]]; then
    source $config
    verbose "Sourced configuration file '${config}'"
  else
    echerr "Missing config file '${config}'"
  fi

  if [ $kairos_VERBOSE -gt 0 ]; then
    echo -e "\nUsing configuration:"
    local kairos_vars=$(compgen -A variable | grep 'kairos_')
    for v in $kairos_vars; do
      echo "${v}=${!v}"
    done
    echo
  fi
}

get_value() {
  readonly kairos_VALUE=${args[0]:?}
  verbose "Metric value set to \"${kairos_VALUE}\""
}

get_now() {
  if [ $kairos_BSD -gt 0 ]; then
    readonly kairos_NOW=$(($(date +%s)*1000))
    verbose "\e[33mWARNING: Using BSD mode for timestamp\e[0m"
  else
    readonly kairos_NOW=$(($(date +%s%N)/1000000))
  fi

  verbose "Setting timestamp \"${kairos_NOW}\"\n"
}

push_raw() {
  get_value
  get_now
  verbose "Pushing to KairosDB..."

  echo "put ${kairos_METRIC} ${kairos_NOW} ${kairos_VALUE} ${kairos_TAG}" \
    | nc -w 30 "$kairos_HOST" "$kairos_PORT"

  local ret=$?
  if [ $ret -eq 0 ]; then
    echo "OK"
  else
    echerr "netcat returned $ret"
    return 1
  fi

}

push_http() {
  get_value
  get_now
  verbose "Pushing to KairosDB...\n"
  local curl_output=$(
  curl -vsSH "Content-Type: application/json" -X POST -d @<(cat <<EOF
  [{
    "name": "${kairos_METRIC}",
    "timestamp": "${kairos_NOW}",
    "value": "${kairos_VALUE}",
    "tags": { "${kairos_HTTP_TAG}" }
  }]
EOF
  ) ${kairos_PROTO}://${kairos_HOST}:${kairos_PORT}${kairos_URL} 2>&1
  )

  local ret=${PIPESTATUS[0]}
  if [ $ret -eq 0 ]; then
    verbose "********** Begin cURL Output **********\n" "$curl_output" "\n********** End cURL Output **********\n" "\nOK\n"
  else
    echerr "curl returned $ret"
    verbose "********** Begin cURL Output **********\n" "$curl_output" "\n********** End cURL Output **********\n"
    return 1
  fi
}

format_tag() {
  # We need to reformat the tag if it's being pushed via HTTP
  verbose "Reformating tag for http(s)..."
  readonly kairos_HTTP_TAG=$(echo $kairos_TAG | sed 's/=/\" : \"/')
  verbose "'${kairos_TAG}' reformated to '${kairos_HTTP_TAG}'\n"
}

##### MAIN PROGRAM BEGINS #####
get_config
# Determine the protocol
if [[ "$kairos_PROTO" =~ ^https?$ ]]; then
  verbose "Using protocol '${kairos_PROTO}'"
  format_tag
  push_http
elif [[ "$kairos_PROTO" == "raw" ]]; then
  verbose "Using protocol '${kairos_PROTO}'"
else
  echerr "Invalid protocol specified. Got '${kairos_PROTO}', expected http|https|raw"
fi
