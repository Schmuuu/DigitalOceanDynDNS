#!/bin/bash
# @requires awk, curl, grep, sed, tr.

## START EDIT HERE.
do_access_token="";
ip6_interface="enp1s0";
tmpfile="/tmp/digital_ocean_records_";
storedIpAddresses="/tmp/digital_ocean_latest_ip_updates_"  # domain name and file extenstion .txt will be appended down below
verbose=true;
curl_timeout="15";
loop_max_records="50";
url_do_api="https://api.digitalocean.com/v2";
url_ext_ip="http://ipv4.icanhazip.com";
url_ext_ip2="http://ifconfig.me/ip";
filename="$(basename $BASH_SOURCE)";
## END EDIT.

update_only=false;
ipAddressesToStore="";

# get options.
while getopts "ush" opt; do
  case $opt in
    u)  # update.
      update_only=true;
      ;;
    s)  # silent.
      verbose=false;
      ;;
    h)  # help.
      echo "Usage: $filename [options...] <record name> <domain>";
      echo "Options:";
      echo "  -h      This help text";
      echo "  -u      Updates only. Don't add non-existing";
      echo "  -s      Silent mode. Don't output anything";
      echo "Example:";
      echo "  Add/Update nas.mydomain.com DNS A and AAAA record with current";
      echo "  public IPv4 and global IPv6 address";
      echo "    ./$filename -s nas mydomain.com";
      echo;
      echo "Example 2:";
      echo "  Add/Update Default A and AAAA record with current IPv4 and IPv6";
      echo "    ./$filename -u @ mydomain.com";
      echo;
      exit 0;
      ;;
    \?)
      echo "Invalid option: -$OPTARG (See -h for help)" >&2
      exit 1;
      ;;
  esac
done

# validate.
shift $(( OPTIND - 1 ));
do_record="$1";
do_domain="$2";
if [ $# -lt 2 ] || [ -z "$do_record" ] || [ -z "$do_domain" ] ; then
  echo "Missing required arguments. (See -h for help)";
  exit 1;
fi

if [[ $do_record == "@" ]]; then
  tmpfile="${tmpfile}${do_domain}.txt";
  storedIpAddresses="${storedIpAddresses}${do_domain}.txt";
else
  tmpfile="${tmpfile}${do_record}.txt";
  storedIpAddresses="${storedIpAddresses}${do_record}.txt";
fi

echov()
{
  if [ $verbose == true ] ; then
    if [ $# == 1 ] ; then
      echo "$1";
    else
      printf "$@";
    fi
  fi
}

# modified from https://gist.github.com/cjus/1047794#comment-1249451
json_value()
{
  local KEY=$1
  local num=$2
  awk -F"(\":)|([,}])" '{for(i=1;i<=NF;i++)if($i~/\042'$KEY'/){print $(i+1)}}' | tr -d '"' | sed -n "$num"p
}

get_external_ip()
{
  ip_address="$(curl -s --connect-timeout $curl_timeout $url_ext_ip | sed -e 's/.*Current IP Address: //' -e 's/<.*$//' | egrep -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')";
  if [ -z "$ip_address" ] ; then
    ip_address="$(curl -s --connect-timeout $curl_timeout $url_ext_ip2 | egrep -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')";
    if [ -z "$ip_address" ] ; then
      return 1;
    fi
  else
    return 0;
  fi
}

get_global_ip6()
{
  ip6_address="$(ip addr show $ip6_interface | grep 'inet6' | grep -v 'fe80' | grep -v 'fd00' | awk '{ print $2}' | sed 's/\/.*$//')";
  if [ -z "$ip6_address" ] ; then
    return 1;
  else
    return 0;
  fi
}

# https://developers.digitalocean.com/#list-all-domain-records
get_record()
{
  declare -A tmp_record;
  local success_v4=false;
  local success_v6=false;

  curl -s --connect-timeout "$curl_timeout" -H "Authorization: Bearer $do_access_token" -X GET "$url_do_api/domains/$do_domain/records" > "$tmpfile"
  if [ ! -s "$tmpfile" ] ; then
    return 1;
  fi

  local do_num_records="$(json_value total 1 < $tmpfile)";
  if [[ ! "$do_num_records" =~ ^[0-9]+$ ]] || [ "$do_num_records" -gt "$loop_max_records" ] ; then
    do_num_records=$loop_max_records;
  fi

  for (( i=1; i<="$do_num_records"; i++ ))
  do
    tmp_record['name']="$(json_value name $i < $tmpfile)";
    tmp_record['type']="$(json_value type $i < $tmpfile)";

    if [ "${tmp_record[name]}" == "$do_record" ] && [ "${tmp_record[type]}" == "AAAA" ]; then
      recordv6['name']="${tmp_record[name]}";
      recordv6['type']="${tmp_record[type]}";
      recordv6['id']="$(json_value id $i < $tmpfile)";
      recordv6['data']="$(json_value data $i < $tmpfile)";

      if [ ! -z "${recordv6[id]}" ] && [[ "${recordv6[id]}" =~ ^[0-9]+$ ]] ; then
	success_v6=true;
      fi
    elif [ "${tmp_record[name]}" == "$do_record" ] && [ "${tmp_record[type]}" == "A" ]; then
      recordv4['name']="${tmp_record[name]}";
      recordv4['type']="${tmp_record[type]}";
      recordv4['id']="$(json_value id $i < $tmpfile)";
      recordv4['data']="$(json_value data $i < $tmpfile)";

      if [ ! -z "${recordv4[id]}" ] && [[ "${recordv4[id]}" =~ ^[0-9]+$ ]] ; then
        success_v4=true;
      fi
    fi
    
    if [ "${success_v4}" == true ] && [ "${success_v6}" == true ] ; then
      return 0;
    fi
  done

  return 1;
}

# https://developers.digitalocean.com/#update-a-domain-record
set_record_ip()
{
  local id=$1
  local ip=$2

  local data=`curl -s --connect-timeout $curl_timeout -H "Content-Type: application/json" -H "Authorization: Bearer $do_access_token" -X PUT "$url_do_api/domains/$do_domain/records/$id" -d'{"data":"'"$ip"'"}'`;
  if [ -z "$data" ] || [[ "$data" != *"id\":$id"* ]]; then
    return 1;
  else
    return 0;
  fi
}

# https://developers.digitalocean.com/v2/#create-a-new-domain-record
new_record()
{
  local ip=$1
  local record=$2  # record "A" for IPv4 or "AAAA" for IPv6

  local data=`curl -s --connect-timeout $curl_timeout -H "Content-Type: application/json" -H "Authorization: Bearer $do_access_token" -X POST "$url_do_api/domains/$do_domain/records" -d'{"name":"'"$do_record"'","data":"'"$ip"'","type":"'"$record"'"}'`;
  if [ -z "$data" ] || [[ "$data" != *"data\":\"$ip"* ]]; then
    return 1;
  else
    return 0;
  fi
}

# start.
echov "===============================================================";
echov "* Updating $do_record.$do_domain: $(date +"%Y-%m-%d %H:%M:%S")";


echov "* Fetching external IP from: $url_ext_ip";
get_external_ip;
if [ $? -ne 0 ] ; then
  echo "! Unable to extract external IP address";
  exit 1;
fi

echov "* Fetching global IPv6 from interface: $ip6_interface";
get_global_ip6 "$ip6_interface";
if [ $? -ne 0 ] ; then
  echo "! Unable to extract global IPv6 address";
  exit 1;
fi


if [[ -f ${storedIpAddresses} ]]; then
  updatedAddressesFromFile=`cat $storedIpAddresses`
  if [[ $updatedAddressesFromFile =~ $ip_address ]] && [[ $updatedAddressesFromFile =~ $ip6_address ]]; then
    echov "* Current IP addresses have already been updated at Digital Ocean";
    echov "* Nothing to do here. Exiting...";
    exit 0;
  fi
else
  echov "! There is no file storing the latest IP addresses updated with Digital Ocean!"
fi


touch ${tmpfile};
if [ ! -f ${tmpfile} ] ; then
  echo "! Cannot create temporary record file! Exiting.";
  exit 1;
fi

just_added=0;
just_added_v4=false;
just_added_v6=false;
update_required_v4=true;
update_required_v6=true;
update_failed_v4=false;
update_failed_v6=false;
declare -A recordv4;
declare -A recordv6;

echov "* Fetching Record ID for: ${do_record}.${do_domain}";
get_record;

if [ $? -ne 0 ] ; then
  if [ $update_only == true ] ; then
    echov "! Unable to find requested record in Digital-Ocean account";
    update_required_v4=false;
    update_required_v6=false;
  else
    echov "* At least one record missing! Adding missing record...";
    if [ -z "${recordv4[id]}" ] ; then
      new_record "$ip_address" "A";
      if [ $? -ne 0 ] ; then
        echov "! Unable to add new IPv4 record";
      else
	      echov "* Successfully added new IPv4 record";
        just_added=$((just_added+1));
	      just_added_v4=true;
	      update_required_v4=false;
        if [ "$ipAddressesToStore" != "$ip_address"* ]; then
          ipAddressesToStore="${ipAddressesToStore}${ip_address};"
        fi
      fi
    fi

    if [ -z "${recordv6[id]}" ] ; then
      new_record "$ip6_address" "AAAA";
      if [ $? -ne 0 ] ; then
        echov "! Unable to add new IPv6 record";
      else
	      echov "* Successfully added new IPv6 record";
        just_added=$((just_added+1));
	      just_added_v6=true;
	      update_required_v6=false;
        if [ "$ipAddressesToStore" != "$ip6_address"* ]; then
          ipAddressesToStore="${ipAddressesToStore}${ip6_address};"
        fi
      fi
    fi
  fi
fi

if [ $update_only == true ] || [ $just_added -le 1 ] ; then

  if [ $update_required_v4 == true ] && [ ! -z "${recordv4[id]}" ] && [[ "${recordv4[id]}" =~ ^[0-9]+$ ]]; then 
      echov "* Comparing >> ${recordv4[type]} | ${recordv4[data]} << to $ip_address";
      if [ "${recordv4[data]}" == "$ip_address" ] ; then
        echov "* Record >>A<< already set to $ip_address";
        update_required_v4=false;
        if [ "$ipAddressesToStore" != "$ip_address"* ]; then
          ipAddressesToStore="${ipAddressesToStore}${ip_address};"
        fi
      fi
  fi
  if [ $update_required_v6 == true ] && [ ! -z "${recordv6[id]}" ] && [[ "${recordv6[id]}" =~ ^[0-9]+$ ]]; then
      echov "* Comparing >> ${recordv6[type]} | ${recordv6[data]} << to $ip6_address";
      if [ "${recordv6[data]}" == "$ip6_address" ] ; then
        echov "* Record >>AAAA<< already set to $ip6_address";
        update_required_v6=false;
        if [ "$ipAddressesToStore" != "$ip6_address" ]; then
          ipAddressesToStore="${ipAddressesToStore}${ip6_address};"
        fi
      fi
  fi


  if [ $update_required_v4 == true ]; then
    echov "* Updating record ${recordv4[name]}.$do_domain to $ip_address";
    set_record_ip "${recordv4[id]}" "$ip_address";
    if [ $? -ne 0 ] ; then
      echov "! Unable to update IPv4 address";
      update_failed_v4=true;
    elif [ "$ipAddressesToStore" != "$ip_address" ]; then
      ipAddressesToStore="${ipAddressesToStore}${ip_address};"
    fi
  fi
  if [ $update_required_v6 == true ]; then
    echov "* Updating record ${recordv6[name]}.$do_domain to $ip6_address";
    set_record_ip "${recordv6[id]}" "$ip6_address";
    if [ $? -ne 0 ] ; then
      echov "! Unable to update IPv6 address";
      update_failed_v6=true;
    elif [ "$ipAddressesToStore" != "$ip6_address"* ]; then
      ipAddressesToStore="${ipAddressesToStore}${ip6_address};"
    fi
  fi
fi

touch $storedIpAddresses;
if [[ ! -f ${storedIpAddresses} ]]; then
  echo "! Cannot create file to store latest updated IP addresses!";
else
  echo "$ipAddressesToStore" > $storedIpAddresses;
fi


rm ${tmpfile};
if [[ -f ${tmpfile} ]]; then
  echo "! Could not remove temporary record file ${tmpfile}";
fi

if [ ${update_failed_v4} == true ] || [ ${update_failed_v6} == true ] ; then
  echov "* At least one IP address update failed";
  exit 1;
fi

echov "\n* IP address(es) successfully added/updated when it where necessary.\n" "";

exit 0;
