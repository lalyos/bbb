#!/bin/bash

set -x

debug() {
  [[ "$DEBUG" ]] && echo "-----> $*" 1>&2
}

install_docker() {
  curl -L get.docker.com | bash -v
  until docker images ; do sleep1; done
}

fake_dns() {
  docker run \
  -d \
  -p 5380:5380  \
  --hostname dns.mageddo \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /etc/resolv.conf:/etc/resolv.conf defreitas/dns-proxy-server

  until curl -o /dev/null --silent --fail http://127.0.0.1:5380/hostname/; do
    sleep 1
  done

  curl 'http://127.0.0.1:5380/hostname/' \
  -H 'Content-Type: application/json' \
  --data-binary @- << EOF
  { 
    "hostname" :"${BBB_HOSTNAME}",
    "ip" : [$(ec2metadata --public-ipv4| sed 's/\./,/g')],
    "target" : "${BBB_HOSTNAME#*.}",
    "type" : "A",
    "ttl" : 60,
    "env" : ""
  }
EOF

}

_aws() {
  docker run -i \
    -v /tmp/:/tmp/ \
    mikesir87/aws-cli \
    aws "$@"
}

route53-get-zoneid() {
    declare desc="prints the ZoneId by Zone name"
    declare zone=$1

    : ${zone:? required}
    debug "ensure zone ends with dot"
    [[ ${zone} =~ \.$ ]] || zone="$zone."

    debug "zoneId for: $zone"
    _aws route53 list-hosted-zones \
      --query "HostedZones[?Name=='$zone'].Id" \
      --out text
}

route53-new-A-record() {
    declare sub=$1 value=$2

    : ${sub:? required}
    : ${value:? required}

    cat << EOF
 {
  "Comment": "A record for $sub",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "$sub",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [
          {
            "Value": "$value"
          }
        ]
      }
    }
  ]
}
EOF
}

route53-new-record() {
  declare desc=""
  declare sub=$1 zone=$2 value=$3

  : ${sub:?required} ${zone:? required} ${value:? required}

  debug "$desc"
  [[ ${zone} =~ \.$ ]] || zone="$zone."
  zoneId="$(route53-get-zoneid $zone)"
  debug "zoneId: $zoneId"

  route53-new-A-record "${sub}.${zone}" "${value}" > /tmp/new-a-record.dns
  _aws route53 change-resource-record-sets \
    --hosted-zone-id $zoneId \
    --change-batch file:///tmp/new-a-record.dns
}

main() {
  : ${BBB_VERSION:=xenial-220}
  : ${BBB_ACME_EMAIL:=lalyos@yahoo.com}
  : ${BBB_HOSTNAME:=maradjotthon.hatnem.de}

  install_docker
  # fake_dns
  ## IAM role required for route53 full access
  route53-new-record ${BBB_HOSTNAME%%.*} ${BBB_HOSTNAME#*.} $(ec2metadata --public-ipv4)
  # instead of fake dns wait for real dns entry:
  while ! dig +short ${BBB_HOSTNAME} | grep $(ec2metadata --public-ipv4); do echo -n .; sleep 5; done


  wget -qO- https://ubuntu.bigbluebutton.org/bbb-install.sh \
   | bash -xs -- \
     -v ${BBB_VERSION} \
     -e ${BBB_ACME_EMAIL} \
     -s ${BBB_HOSTNAME} \
     -g
}

main
