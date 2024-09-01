#!/usr/bin/sh

# This script queries puppetdb given a res_type (e.g. "class" or a defined res_type)
# and a "res_name" parameter.  The result is a list of hosts that use that
# resource. In the case of a defined res_type, the res_name is really an instance of
# that res_type.
#
# The docs on puppetdb are here:
# https://puppet.com/docs/puppetdb/latest/index.html

function usage {
  prog=${0##*/}
  echo "
    USAGE: $prog <puppetdb-host-and-port> <res_type> [<res_name>]

    Examples:
      # Return a list of the machines using a class named 'Foo'.
      $prog https://pup:8081 class Foo

      # Return a list of the machines using the 'baz' instance of the foo::bar defined res_type.
      # Note the capital 'F'
      $prog https://pup:8081 Foo::bar baz

    Evironmental variables:
      DEBUG    If set to any value, the curl command line will be printed
               on stderr.
  "

  exit 1
}

if [ $# -lt 2 ]; then
  echo "Must have at least 2 arguments"
  usage
fi

host_port=$1

if [[ ! "$host_port" =~ ^https?:\/\/[^:\/]+:[0-9]+$ ]]; then
  echo "Invalid host format. Must conform to: http[s]//some-host:some-port"
  exit 1
fi

res_type=$2
res_name=$3
base_url="$host_port/pdb/query/v4"

if [ -n "$res_name" ]; then
  query="resources[certname,type,title] { type=\"$res_type\" and title = \"$res_name\" }"
else
  query="resources[certname,type,title] { type=\"$res_type\" }"
fi
cmd=(curl -s -k -X GET "$base_url" --data-urlencode "query=$query")

# DEBUG=1 can be supplied as an env variable
if [ -n "$DEBUG" ]; then
  # Redirect stdout to stderr not to interfere with jq (if it's piped to)
  1>&2 printf "==> %q\\n" "${cmd[*]}"
fi


"${cmd[@]}" | jq -r '.[] | .certname + " " + .type + " " + .title' | column -t
