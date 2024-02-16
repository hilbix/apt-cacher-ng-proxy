#!/bin/bash
#
# This is a very simple HTTP client talking to some server on STDIN/STDOUT
# and passing back the response via FD 3.
# It apparently works with Debian repositories.
#
# It needs some environment variables:
#
# MODE		http or https
# Host		hostname to connect to
# PORT		PORT number to connect to
# URL		The URL PATH without the host part
# HEADS		all the headers, already correctly preformatted with \r\n in between
#		like with: printf -vHEADS '%s\r\n' "${HEADERS[@]}"
#		(because bash cannot pass arrays into subshells)
# TIMEOUT	Timeout in seconds
# PARENT	$SOCKLINGER_NR of the parent (or something similar)
#
# This needs some of my own tools:
#
# https://github.com/hilbix/unbuffered
# https://github.com/hilbix/timeout


STDOUT() { local a b; printf -va '[%s] %q' "${PARENT:-${SOCKLINGER_NR:-$PPID}}" "$1"; [ 1 -ge $# ] || printf -vb ' %q' "${@:2}"; printf '%s%s\n' "$a" "$b"; }
STDERR() { STDOUT "$@" >&2; }
OOPS() { STDERR OOPS: "$@"; exit 23; }
x() { "$@"; }
o() { x "$@" || OOPS fail $?: "$@"; }

get-headers()
{
  HEADS=()
  CURLHEADS=()
  while	read -rt${TIMEOUT:-10} h && h="${h%$'\r'}" && [ -n "$h" ]
  do
        ht="${h%%: *}"
        hd="${h#*: }"
        o test ".$h" = ".$ht: $hd"
        ht="${ht,,}"
        case "$ht:$hd" in
        (proxy-connection:*)	continue;;
        (connection:*)		continue;;
        (cache-control:*)	continue;;
        (content-length:*)	ContentLength="$hd";;
        (content-type:*)	ContentType="$hd";;

# request
#        (accept:*)		Accept="$hd";;
#        (host:*)		Host="$hd";;
#        (user-agent:*)		UserAgent="$hd";;
#        (accept-encoding:*)	;;
#        (range:*)		;;
#        (if-range:*)		;;
#        (referer:*)		;;
#        (accept-language:*)	;;

# response
	(upgrade:*)		continue;;
	(accept-ranges:*)	;;
	(date:*)		;;
	(expires:*)		;;
	(etag:*)		;;
	(content-range:*)	ContentRange="$hd";;
	(last-modified:*)	;;
	(server:*)		;;
	(age:*)			;;
	(via:*)			;;
	(vary:*)		;;
	(permissions-policy:*)	;;
	(referrer-policy:*)	;;
	(x-frame-options:*)	;;
	(x-xss-protection:*)	;;

# WTF?
	(x-content-type-options:*)	;;
	(x-clacks-overhead:*)	;;	# Terry Pratchett?
	(x-served-by:*)		;;
	(x-cache:*)		;;
	(x-cache-hits:*)	;;
	(x-timer:*)		;;

        (*)			STDERR head "$ht:" "$hd";;
        esac
        CURLHEADS+=(-H "$h")
        HEADS+=("$h")
  done
}


printf 'GET %s HTTP/1.1\r\n' "$URL"
printf 'connection: close\r\n'
printf '%s\r\n' "$HEADS"

read -rt${TIMEOUT:-10} HTTP CODE OK || OOPS no response: "$MODE" "$Host" "$PORT" "$URL"
OK="${OK%$'\r'}"

get-headers
STDERR GOT "$MODE" "$Host" "$PORT" "$URL" "$HTTP" "$CODE" "$OK" "$ContentType" "$ContentLength" "$ContentRange"
#STDERR "${HEADS[@]}"

# Now pass everything to the requestor
# Note that apt-cacher-ng fails if OK is an empty string

printf '%s %s %s\r\n' "$HTTP" "$CODE" "${OK:-OK}" >&3 || OOPS EOF
#printf 'connection: close\r\n'		# ignored by Apt-Cacher-NG?!?
#printf 'proxy-connection: close\r\n'	# ignored by Apt-Cacher-NG?!?
printf '%s\r\n' "${HEADS[@]}" '' >&3 || OOPS EOF

# Use `head` to restrict the number of incoming bytes.
# Because apparently some hosts seem to ignore "connection: close".
cnt="$(set -o pipefail; head -c "$ContentLength" | /usr/local/bin/timeout 60 - | /usr/local/bin/unbuffered -o3 | wc -c)" || OOPS timeout $TIMEOUT

# We probably should store the body above before passing it back
# such that we can test it for correctness before handing it to apt-cacher-ng

STDERR DONE "$cnt"
[ "$cnt" = "$ContentLength" ] || OOPS content got "$cnt" length "$ContentLength" range "$ContentRange"

