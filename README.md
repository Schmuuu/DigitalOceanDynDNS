# Digital Ocean Dynamic DNS Updater

Simple **Bash** script to automatically add/update Digital Ocean DNS record for a domain. Includes basic error checking and common linux commands only.

My use case: 
*Connect to home server that is on a dynamic IP via a fixed domain (ala DynDNS).*
`(e.g.- nas.mydomain.com vs. 74.125.231.100)`
The server should be reachable via both IP address types: **IPv4 and IPv6**. 
The difference here compared to IPv4 is, that the IPv4 address is assigned to the (DSL) Router and is checked via external 
websites, the IPv6 address on the other hand is assigned to the machine/ server itself. Therefor it is a different approach
to determine the IPv6 address. 
For that use case, IPv6 should be configured on the server, which is running this script, meaning that the server has to 
have a global IPv6 assigned.

## Usage

1. Generate [Personal Access Token](https://cloud.digitalocean.com/settings/applications) from your Digital Ocean account.

2. Modify the script to add `access token`  

3. Find out the interface which is connected to the Internet and has the global IPv6 address assigned. Modify the script to let it know which interface to look at. 
Run the following command and look for the string "scope global" and pick that interface name then: 

		ip -f inet6 addr

4. [Cron](http://en.wikipedia.org/wiki/Cron#Predefined_scheduling_definitions) the script to update Digital Ocean's DNS at desired frequency. (Note: *API rate limit is currently 1200 /hr. Script run uses 2.*)

		# once every two days @ 7:30am.
		30 07 */2 * * /path/to/file/do_dns_update.sh -s nas mydomain.com

## Options

	$ ./do_dns_update.sh -h

	Usage: do_dns_update.sh [options...] <record name> <domain>
	Options:
	  -h      This help text
	  -u      Updates only. Don't add non-existing
	  -s      Silent mode. Don't output anything


## Requires

* [Domain](https://www.digitalocean.com/community/tutorials/how-to-set-up-a-host-name-with-digitalocean) added on Digital Ocean.
* Crontab or equivalent.
* Available linux commands: **awk, curl, grep, sed, tr**

## Adapted From

[PHP / Python version](https://github.com/bensquire/Digital-Ocean-Dynamic-DNS-Updater)

## License

The MIT License (MIT).